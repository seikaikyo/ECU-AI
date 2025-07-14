#!/bin/bash
set -euo pipefail  # 嚴格錯誤處理

# 輸入驗證和安全檢查
validate_environment() {
    if [[ $EUID -eq 0 ]]; then
        echo "警告: 不建議以 root 權限執行此腳本"
        read -p "是否繼續? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

validate_environment

echo "===== 企業網路環境 Claude Code 診斷 ====="
echo ""

# 檢查代理設定
echo "1. 代理設定檢查："
if [ -n "${HTTP_PROXY:-}" ]; then
    echo "   HTTP_PROXY: $HTTP_PROXY"
fi
if [ -n "${HTTPS_PROXY:-}" ]; then
    echo "   HTTPS_PROXY: $HTTPS_PROXY"
fi
if [ -n "${ALL_PROXY:-}" ]; then
    echo "   ALL_PROXY: $ALL_PROXY"
fi
if [ -z "${HTTP_PROXY:-}" ] && [ -z "${HTTPS_PROXY:-}" ] && [ -z "${ALL_PROXY:-}" ]; then
    echo "   未發現系統層級代理設定"
fi

echo "   npm 代理設定："
npm config get proxy 2>/dev/null && echo "   npm HTTP proxy: $(npm config get proxy)"
npm config get https-proxy 2>/dev/null && echo "   npm HTTPS proxy: $(npm config get https-proxy)"
echo ""

# 檢查企業憑證
echo "2. SSL/TLS 憑證檢查："
if command -v openssl >/dev/null 2>&1; then
    timeout 10 openssl s_client -connect api.anthropic.com:443 -servername api.anthropic.com < /dev/null 2>/dev/null | grep -E "(Certificate chain|subject|issuer)" | head -10 || echo "   憑證檢查失敗"
else
    echo "   openssl 未安裝，跳過憑證檢查"
fi
echo ""

# 測試不同的連接方式
echo "3. 連接測試（多種方式）："
if command -v curl >/dev/null 2>&1; then
    echo "   標準 HTTPS 連接："
    timeout 15 curl -s -w "HTTP狀態: %{http_code}, 總時間: %{time_total}s\n" -o /dev/null --connect-timeout 10 --max-time 10 https://api.anthropic.com || echo "   連接失敗"

    echo "   使用 User-Agent 的連接："
    timeout 15 curl -s -w "HTTP狀態: %{http_code}, 總時間: %{time_total}s\n" -o /dev/null --connect-timeout 10 --max-time 10 -H "User-Agent: Claude-Code/1.0" https://api.anthropic.com || echo "   連接失敗"

    echo "   測試 WebSocket 連接能力："
    timeout 15 curl -s -w "HTTP狀態: %{http_code}, 總時間: %{time_total}s\n" -o /dev/null --connect-timeout 10 --max-time 10 -H "Upgrade: websocket" -H "Connection: Upgrade" https://api.anthropic.com || echo "   連接失敗"
else
    echo "   curl 未安裝，跳過連接測試"
fi
echo ""

# 檢查防火牆規則
echo "4. 網路政策檢查："
echo "   測試常用 AI 服務連接："
if command -v curl >/dev/null 2>&1; then
    # 安全的服務列表
    declare -a services=("openai.com" "api.openai.com" "api.anthropic.com")
    for service in "${services[@]}"; do
        # 輸入驗證：確保服務名稱只包含有效字元
        if [[ $service =~ ^[a-zA-Z0-9.-]+$ ]]; then
            if timeout 10 curl -s --connect-timeout 5 --max-time 5 "https://$service" > /dev/null 2>&1; then
                echo "   ✓ $service - 可連接"
            else
                echo "   ✗ $service - 連接失敗"
            fi
        else
            echo "   ✗ $service - 無效的服務名稱"
        fi
    done
else
    echo "   curl 未安裝，跳過網路政策檢查"
fi
echo ""

# 檢查 DNS over HTTPS
echo "5. DNS over HTTPS 測試："
if command -v curl >/dev/null 2>&1; then
    timeout 10 curl -s "https://1.1.1.1/dns-query?name=api.anthropic.com&type=A" -H "Accept: application/dns-json" | grep -o '"Answer":\[.*\]' | head -1 || echo "   DNS over HTTPS 查詢失敗"
else
    echo "   curl 未安裝，跳過 DNS over HTTPS 測試"
fi
echo ""

# 檢查網路延遲
echo "6. 網路延遲測試："
if command -v ping >/dev/null 2>&1; then
    timeout 15 ping -c 3 api.anthropic.com 2>/dev/null | tail -1 || echo "   Ping 失敗"
else
    echo "   ping 未安裝，跳過延遲測試"
fi
echo ""

# Node.js 環境測試
echo "7. Node.js 網路測試："
if command -v node >/dev/null 2>&1; then
    timeout 15 node -e "
const https = require('https');
const options = {
  hostname: 'api.anthropic.com',
  port: 443,
  path: '/',
  method: 'GET',
  timeout: 10000
};

const req = https.request(options, (res) => {
  console.log('Node.js HTTPS 連接成功:', res.statusCode);
});

req.on('error', (e) => {
  console.log('Node.js HTTPS 連接失敗:', e.message);
});

req.on('timeout', () => {
  console.log('Node.js HTTPS 連接超時');
  req.destroy();
});

req.end();
" 2>/dev/null || echo "   Node.js 測試失敗"
else
    echo "   Node.js 未安裝，跳過 Node.js 測試"
fi

echo ""
echo "===== 診斷完成 ====="
echo ""
echo "如果發現問題："
echo "1. 代理設定問題 → 聯繫 IT 部門取得正確的代理設定"
echo "2. SSL 憑證問題 → 可能需要安裝企業根憑證"
echo "3. 防火牆阻擋 → 請 IT 部門將 api.anthropic.com 加入白名單"
echo "4. DPI 阻擋 → 嘗試使用個人網路（手機熱點）"