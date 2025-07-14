#!/bin/bash

# ECU-AI 專案專用的 Git 同步腳本
# 整合了 git_sync 的功能，專為 ECU-AI 專案優化
# 版本：1.0

set -euo pipefail

# 腳本目錄
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 顏色代碼
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# 專案配置
PROJECT_NAME="ECU-AI"
GITHUB_REPO="https://github.com/seikaikyo/ECU-AI.git"
GITLAB_REPO="https://gitlab.yesiang.com/ys_it_teams/ecu-ai.git"
DEFAULT_BRANCH="main"

# 調試模式
DEBUG=false

# 調試函數
debug_log() {
    if [ "$DEBUG" = true ]; then
        echo -e "${BLUE}[DEBUG] $1${NC}" >&2
    fi
}

# 顯示標題
show_header() {
    echo -e "${CYAN}======================================${NC}"
    echo -e "${CYAN}    ECU-AI 企業網路環境同步工具     ${NC}"
    echo -e "${CYAN}======================================${NC}"
    echo ""
}

# 顯示幫助
show_help() {
    cat << EOF
ECU-AI 同步工具 - 版本 1.0

用法:
    $0 [選項]

選項:
    -h, --help      顯示此幫助訊息
    -d, --debug     啟用調試模式
    -c, --check     僅執行安全檢查，不推送
    -f, --force     跳過安全檢查強制推送
    --github-only   僅推送到 GitHub
    --gitlab-only   僅推送到 GitLab

功能:
    - 自動檢測並配置遠端倉庫
    - 執行安全檢查，防止敏感資訊外洩
    - 支援雙平台同步（GitHub + GitLab）
    - 專為 ECU-AI 企業環境優化

範例:
    $0              # 標準同步到兩個平台
    $0 --check      # 僅執行安全檢查
    $0 --github-only # 僅推送到 GitHub
EOF
}

# 檢查 Git 倉庫狀態
check_git_status() {
    debug_log "檢查 Git 倉庫狀態..."
    
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo -e "${RED}錯誤：當前目錄不是 Git 倉庫${NC}"
        return 1
    fi
    
    # 檢查是否有未提交的更改
    if ! git diff-index --quiet HEAD --; then
        echo -e "${YELLOW}警告：檢測到未提交的更改${NC}"
        echo -e "${YELLOW}建議先提交更改再進行同步${NC}"
        read -p "是否繼續？(y/N): " continue_choice
        if [[ ! $continue_choice =~ ^[Yy]$ ]]; then
            return 1
        fi
    fi
    
    return 0
}

# 配置遠端倉庫
configure_remotes() {
    debug_log "配置遠端倉庫..."
    
    # 檢查並設定 GitHub 遠端
    if ! git remote get-url github > /dev/null 2>&1; then
        echo -e "${BLUE}配置 GitHub 遠端...${NC}"
        git remote add github "$GITHUB_REPO"
    else
        debug_log "GitHub 遠端已存在"
    fi
    
    # 檢查並設定 GitLab 遠端
    if ! git remote get-url origin > /dev/null 2>&1; then
        echo -e "${BLUE}配置 GitLab 遠端...${NC}"
        git remote add origin "$GITLAB_REPO"
    else
        debug_log "GitLab 遠端已存在"
    fi
}

# ECU-AI 專案特定的安全檢查
perform_ecu_security_check() {
    echo -e "${PURPLE}================== ECU-AI 安全檢查 ==================${NC}"
    
    local security_issues=0
    
    # 檢查敏感配置
    local sensitive_patterns=(
        "password.*=.*[^*]"
        "token.*=.*[^*]"
        "key.*=.*[^*]"
        "secret.*=.*[^*]"
        "glpat-[A-Za-z0-9_-]+"
        "ghp_[A-Za-z0-9_-]+"
    )
    
    echo -e "${BLUE}檢查敏感資訊...${NC}"
    
    for pattern in "${sensitive_patterns[@]}"; do
        if grep -r -i --exclude-dir=.git --exclude="*.log" --exclude="*.example" --exclude="ecu_sync.sh" --exclude="security_check.sh" --exclude="git_sync.sh" --exclude="remote_config.sh" "$pattern" . > /dev/null 2>&1; then
            echo -e "${RED}發現可能的敏感資訊: $pattern${NC}"
            ((security_issues++))
        fi
    done
    
    # 檢查 ECU-AI 特定檔案
    echo -e "${BLUE}檢查 ECU-AI 配置檔案...${NC}"
    
    if [ -f "proxy_config.json" ]; then
        # 檢查配置檔案中是否有真實的認證資訊
        if grep -q '"password":\s*"[^*]' proxy_config.json 2>/dev/null; then
            echo -e "${YELLOW}警告：proxy_config.json 可能包含真實密碼${NC}"
            ((security_issues++))
        fi
    fi
    
    # 檢查 shell 腳本中的硬編碼秘密
    for script in *.sh; do
        if [ -f "$script" ]; then
            if grep -q "export.*=.*[\"'][^*].*[\"']" "$script" 2>/dev/null; then
                echo -e "${YELLOW}警告：$script 可能包含硬編碼環境變數${NC}"
            fi
        fi
    done
    
    echo -e "${PURPLE}=====================================================${NC}"
    
    if [ $security_issues -gt 0 ]; then
        echo -e "${RED}發現 $security_issues 個潛在安全問題${NC}"
        echo -e "${YELLOW}建議處理方式：${NC}"
        echo "1. 將敏感資訊移至環境變數"
        echo "2. 使用 .env.example 檔案提供範本"
        echo "3. 確保 .gitignore 包含敏感檔案"
        echo ""
        read -p "是否繼續推送？(y/N): " continue_push
        if [[ ! $continue_push =~ ^[Yy]$ ]]; then
            return 1
        fi
    else
        echo -e "${GREEN}✅ 安全檢查通過${NC}"
    fi
    
    return 0
}

# 推送到指定平台
push_to_platform() {
    local remote="$1"
    local platform="$2"
    local branch="${3:-$DEFAULT_BRANCH}"
    
    echo -e "${BLUE}推送到 $platform...${NC}"
    
    if git push "$remote" "$branch"; then
        echo -e "${GREEN}✅ 成功推送到 $platform${NC}"
        return 0
    else
        echo -e "${RED}❌ 推送到 $platform 失敗${NC}"
        return 1
    fi
}

# 雙平台同步
sync_dual_platform() {
    local branch="${1:-$DEFAULT_BRANCH}"
    local github_success=false
    local gitlab_success=false
    
    echo -e "${BLUE}開始雙平台同步...${NC}"
    
    # 推送到 GitHub
    if push_to_platform "github" "GitHub" "$branch"; then
        github_success=true
    fi
    
    # 推送到 GitLab
    if push_to_platform "origin" "GitLab" "$branch"; then
        gitlab_success=true
    fi
    
    # 結果報告
    echo ""
    echo -e "${CYAN}=============== 同步結果 ===============${NC}"
    if [ "$github_success" = true ]; then
        echo -e "${GREEN}✅ GitHub: 同步成功${NC}"
    else
        echo -e "${RED}❌ GitHub: 同步失敗${NC}"
    fi
    
    if [ "$gitlab_success" = true ]; then
        echo -e "${GREEN}✅ GitLab: 同步成功${NC}"
    else
        echo -e "${RED}❌ GitLab: 同步失敗${NC}"
    fi
    echo -e "${CYAN}=======================================${NC}"
    
    if [ "$github_success" = true ] || [ "$gitlab_success" = true ]; then
        return 0
    else
        return 1
    fi
}

# 主執行函數
main() {
    local check_only=false
    local force_push=false
    local github_only=false
    local gitlab_only=false
    
    # 參數解析
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -d|--debug)
                DEBUG=true
                shift
                ;;
            -c|--check)
                check_only=true
                shift
                ;;
            -f|--force)
                force_push=true
                shift
                ;;
            --github-only)
                github_only=true
                shift
                ;;
            --gitlab-only)
                gitlab_only=true
                shift
                ;;
            *)
                echo -e "${RED}未知參數: $1${NC}"
                show_help
                exit 1
                ;;
        esac
    done
    
    show_header
    
    # 檢查 Git 狀態
    if ! check_git_status; then
        exit 1
    fi
    
    # 配置遠端倉庫
    configure_remotes
    
    # 執行安全檢查
    if [ "$force_push" != true ]; then
        if ! perform_ecu_security_check; then
            echo -e "${RED}安全檢查失敗，同步終止${NC}"
            exit 1
        fi
    fi
    
    # 如果只是檢查模式，這裡結束
    if [ "$check_only" = true ]; then
        echo -e "${GREEN}僅檢查模式完成${NC}"
        exit 0
    fi
    
    # 獲取當前分支
    local current_branch
    current_branch=$(git branch --show-current)
    
    # 執行推送
    if [ "$github_only" = true ]; then
        push_to_platform "github" "GitHub" "$current_branch"
    elif [ "$gitlab_only" = true ]; then
        push_to_platform "origin" "GitLab" "$current_branch"
    else
        sync_dual_platform "$current_branch"
    fi
}

# 錯誤處理
trap 'echo -e "${RED}腳本執行過程中發生錯誤${NC}"; exit 1' ERR

# 執行主函數
main "$@"