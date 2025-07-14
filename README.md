# ECU-AI 企業環境 Claude 連線解決方案

## 專案概述

這個專案為企業網路環境中使用 Claude AI 提供完整的連線解決方案，包含智能代理伺服器和網路診斷工具。

## 主要功能

- 🚀 **智能代理伺服器** - 自動重定向 Claude API 請求
- 🔍 **網路診斷工具** - 檢測企業防火牆和代理設定
- 🛡️ **安全性增強** - 完善的錯誤處理和輸入驗證
- ⚙️ **配置管理** - 支援外部配置文件

## 檔案說明

- `claude_proxy.js` - 主要的代理伺服器程式
- `proxy_config.json` - 代理伺服器配置文件
- `network_test.sh` - 企業網路環境診斷腳本
- `enterprise_network_test.sh` - 企業環境 Claude Code 適配測試
- `proxy_solution.sh` - 代理解決方案測試腳本

## 快速開始

### 1. 啟動代理伺服器

```bash
node claude_proxy.js
```

### 2. 設定環境變數

```bash
export HTTP_PROXY=http://localhost:8888
export HTTPS_PROXY=http://localhost:8888
```

### 3. 執行網路診斷

```bash
chmod +x network_test.sh
./network_test.sh
```

## 配置選項

編輯 `proxy_config.json` 來自訂設定：

```json
{
  "port": 8888,
  "targetHost": "claude.ai",
  "timeout": 30000,
  "userAgent": "Claude-Proxy/1.0"
}
```

## 安全性特色

- ✅ 嚴格的輸入驗證
- ✅ 超時控制
- ✅ 錯誤處理
- ✅ 日誌記錄
- ✅ IPv6 支援
- ✅ 安全標頭處理

## 故障排除

1. **連接失敗** - 執行 `network_test.sh` 檢查網路狀況
2. **代理錯誤** - 檢查 `proxy_config.json` 設定
3. **權限問題** - 避免使用 root 權限執行

## 系統需求

- Node.js 12+ 
- Bash shell
- curl (用於網路測試)
- openssl (用於憑證檢查)

## 授權

本專案為防禦性安全工具，僅供合法的企業網路環境使用。