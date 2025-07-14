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

echo "===== 企業環境 Claude Code 適配設定 ====="
echo ""

# 檢查當前網路環境
echo "1. 當前網路環境檢查："
echo "   DNS 伺服器："
cat /etc/resolv.conf | grep nameserver
echo "   預設路由："
ip route | grep default
echo ""

# 企業環境常見問題檢測
echo "2. 企業防火牆檢測："

# 測試 HTTPS POST 請求（Claude Code 核心功能）
echo "   測試 API POST 請求："
if command -v curl >/dev/null 2>&1; then
    response=$(timeout 15 curl -s -w "%{http_code}" -o /dev/null --connect-timeout 10 --max-time 10 \
      -X POST https://api.anthropic.com/v1/messages \
      -H "Content-Type: application/json" \
      -H "User-Agent: Claude-Code/1.0.35" \
      --data '{}' 2>/dev/null || echo "000")
else
    response="000"
    echo "   curl 未安裝，無法測試 API 請求"
fi

if [ "$response" = "401" ] || [ "$response" = "400" ]; then
    echo "   ✓ API 端點可達（HTTP $response - 正常的認證錯誤）"
elif [ "$response" = "000" ]; then
    echo "   ✗ API 端點被阻擋（連接失敗）"
else
    echo "   ? API 端點狀態未知（HTTP $response）"
fi

# 測試 WebSocket 能力
echo "   測試 WebSocket 升級："
if command -v curl >/dev/null 2>&1; then
    ws_response=$(timeout 15 curl -s -w "%{http_code}" -o /dev/null --connect-timeout 10 --max-time 10 \
      -H "Upgrade: websocket" \
      -H "Connection: Upgrade" \
      -H "Sec-WebSocket-Key: x3JJHMbDL1EzLkh9GBhXDw==" \
      -H "Sec-WebSocket-Version: 13" \
      https://api.anthropic.com 2>/dev/null || echo "000")
else
    ws_response="000"
    echo "   curl 未安裝，無法測試 WebSocket"
fi

if [ "$ws_response" = "101" ] || [ "$ws_response" = "426" ]; then
    echo "   ✓ WebSocket 能力正常"
elif [ "$ws_response" = "000" ]; then
    echo "   ✗ WebSocket 被阻擋"
else
    echo "   ? WebSocket 狀態：HTTP $ws_response"
fi

echo ""

# Node.js 環境測試
echo "3. Node.js 企業環境測試："
if command -v node >/dev/null 2>&1; then
    timeout 20 node -e "
const https = require('https');

// 測試標準 HTTPS 請求
const testAPI = () => {
  const postData = JSON.stringify({});
  const options = {
    hostname: 'api.anthropic.com',
    port: 443,
    path: '/v1/messages',
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'User-Agent': 'Claude-Code/1.0.35',
      'Content-Length': Buffer.byteLength(postData)
    },
    timeout: 10000
  };

  const req = https.request(options, (res) => {
    console.log('   ✓ Node.js API 請求成功:', res.statusCode);
  });

  req.on('error', (e) => {
    console.log('   ✗ Node.js API 請求失敗:', e.code || e.message);
  });

  req.on('timeout', () => {
    console.log('   ✗ Node.js API 請求超時');
    req.destroy();
  });

  req.write(postData);
  req.end();
};

testAPI();
" 2>/dev/null || echo "   Node.js 測試執行失敗"
else
    echo "   Node.js 未安裝，跳過 Node.js 測試"
fi

echo ""

# 企業代理檢測
echo "4. 企業代理環境檢測："
if [ -n "$HTTP_PROXY" ] || [ -n "$HTTPS_PROXY" ]; then
    echo "   發現代理設定："
    [ -n "$HTTP_PROXY" ] && echo "   HTTP_PROXY: $HTTP_PROXY"
    [ -n "$HTTPS_PROXY" ] && echo "   HTTPS_PROXY: $HTTPS_PROXY"
else
    echo "   未發現明顯的代理設定"
    
    # 檢測透明代理
    echo "   檢測透明代理："
    if command -v curl >/dev/null 2>&1; then
        transparent_proxy=$(timeout 10 curl -v https://httpbin.org/ip 2>&1 | grep -i "via\|x-forwarded\|proxy" | head -1 || echo "")
        if [ -n "$transparent_proxy" ]; then
            echo "   可能存在透明代理"
        else
            echo "   未檢測到透明代理"
        fi
    else
        echo "   curl 未安裝，無法檢測透明代理"
    fi
fi

echo ""

# 解決方案建議
echo "===== 建議解決方案 ====="
echo ""

if [ "$response" = "000" ]; then
    echo "🔥 問題確認：企業防火牆阻擋 Claude Code API 請求"
    echo ""
    echo "立即解決方案："
    echo "1. 切換到手機熱點測試（確認問題源頭）"
    echo "2. 聯繫 IT 部門，要求將以下加入白名單："
    echo "   - api.anthropic.com"
    echo "   - console.anthropic.com"
    echo "   - *.anthropic.com"
    echo ""
    echo "IT 部門設定要求："
    echo "   - 允許 HTTPS POST 請求到 api.anthropic.com"
    echo "   - 允許 User-Agent: Claude-Code/*"
    echo "   - 開放連接埠 443"
    echo "   - 允許現代 TLS 1.2+ 連接"
    echo ""
else
    echo "✅ API 連接基本正常，問題可能在認證層面"
    echo ""
    echo "建議嘗試："
    echo "1. 確保您有 Anthropic 帳號並且已設定計費"
    echo "2. 重新執行 claude 指令進行認證"
    echo "3. 檢查是否有 API 使用限制"
fi

echo ""
echo "替代方案："
echo "- 使用 Claude 網頁版：https://claude.ai"
echo "- 使用個人網路環境（非企業網路）"
echo "- 考慮使用企業版透過 AWS Bedrock 或 Google Vertex AI"