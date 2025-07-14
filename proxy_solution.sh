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

echo "===== 代理解決方案測試 ====="
echo ""

# 1. 測試是否可以通過網頁介面間接訪問 API
echo "1. 測試 Claude 網頁版相關端點："

# 測試不同的 Anthropic 端點
if command -v curl >/dev/null 2>&1; then
    declare -a endpoints=(
        "https://claude.ai"
        "https://console.anthropic.com"
        "https://api.anthropic.com"
        "https://claude.ai/api"
    )

    for endpoint in "${endpoints[@]}"; do
        # URL 驗證：確保是 HTTPS 且域名有效
        if [[ $endpoint =~ ^https://[a-zA-Z0-9.-]+(/.*)?$ ]]; then
            echo "   測試 $endpoint:"
            response=$(timeout 10 curl -s -w "%{http_code}" -o /dev/null --connect-timeout 5 --max-time 5 \
                -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" \
                "$endpoint" 2>/dev/null || echo "000")
            if [ "$response" = "000" ]; then
                echo "   ✗ 無法連接"
            else
                echo "   ✓ 可連接 (HTTP $response)"
            fi
        else
            echo "   ✗ $endpoint - 無效的 URL"
        fi
    done
else
    echo "   curl 未安裝，無法測試端點"
fi

echo ""

# 2. 測試 SSH 動態轉發（如果有海外伺服器）
echo "2. 如果您有海外 VPS，可以使用 SSH 隧道："
echo "   # 建立 SOCKS5 代理"
echo "   ssh -D 1080 -N username@your-overseas-server.com"
echo ""
echo "   # 設定環境變數"
echo "   export HTTP_PROXY=socks5://127.0.0.1:1080"
echo "   export HTTPS_PROXY=socks5://127.0.0.1:1080"
echo ""
echo "   # 測試連接"
echo "   curl --proxy socks5://127.0.0.1:1080 https://api.anthropic.com"
echo ""

# 3. 測試本地代理設定
echo "3. 本地代理設定測試："
echo "   如果您的企業有內部代理："

# 常見的企業代理埠
if command -v curl >/dev/null 2>&1; then
    declare -a proxy_ports=(3128 8080 8888 9090)
    for port in "${proxy_ports[@]}"; do
        # 輸入驗證：確保埠號在有效範圍內
        if [[ $port =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; then
            # 測試本地代理
            proxy_test=$(timeout 5 curl -s -w "%{http_code}" -o /dev/null --connect-timeout 3 --max-time 3 \
                --proxy "http://127.0.0.1:$port" \
                "https://httpbin.org/ip" 2>/dev/null || echo "000")
            if [ "$proxy_test" = "200" ]; then
                echo "   ✓ 發現本地代理在埠 $port"
            fi
        fi
    done
else
    echo "   curl 未安裝，無法測試本地代理"
fi

echo ""

# 4. Claude Code 特定解決方案
echo "4. Claude Code 特定修復："
echo "   # 方案 A: 修改 hosts 檔案"
echo "   echo '172.67.74.226 api.anthropic.com' | sudo tee -a /etc/hosts"
echo ""
echo "   # 方案 B: 使用不同的 Claude Code 啟動參數"
echo "   NODE_TLS_REJECT_UNAUTHORIZED=0 claude"
echo ""
echo "   # 方案 C: 使用 npx 而非全域安裝版本"
echo "   npx @anthropic-ai/claude-code"
echo ""

# 5. 暫時性解決方案
echo "5. 立即可用的替代方案："
echo "   ✓ 使用 claude.ai 網頁版（已確認可連接）"
echo "   ✓ 使用瀏覽器擴充套件版本（如果有）"
echo "   ✓ 透過 API 金鑰直接調用（需要先取得金鑰）"
echo ""

echo "===== 建議執行順序 ====="
echo "1. 立即使用 claude.ai 網頁版開始工作"
echo "2. 測試上述代理方案"
echo "3. 向 IT 部門申請開放 api.anthropic.com"
echo "4. 考慮企業級解決方案（AWS Bedrock）"