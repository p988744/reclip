#!/bin/bash
# Apple 公證腳本
# 用於將 App 提交至 Apple 進行公證

set -e

# 顏色輸出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_step() { echo -e "${GREEN}==>${NC} $1"; }
print_warning() { echo -e "${YELLOW}警告:${NC} $1"; }
print_error() { echo -e "${RED}錯誤:${NC} $1"; }

# 載入配置
CONFIG_FILE="$HOME/.reclip/signing.env"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

# 參數
APP_PATH="${1:-}"
BUNDLE_ID="${BUNDLE_ID:-com.reclip.app}"

# 顯示使用說明
usage() {
    echo "用法: $0 <app-path>"
    echo ""
    echo "範例:"
    echo "  $0 build/export/Reclip.app"
    echo "  $0 Reclip.dmg"
    echo ""
    echo "環境變數（或在 ~/.reclip/signing.env 設定）:"
    echo "  APPLE_ID       - Apple ID 電子郵件"
    echo "  TEAM_ID        - Apple Developer Team ID"
    echo ""
    echo "App-Specific Password 從 Keychain 讀取"
    exit 1
}

# 檢查參數
if [ -z "$APP_PATH" ]; then
    usage
fi

if [ ! -e "$APP_PATH" ]; then
    print_error "找不到檔案: $APP_PATH"
    exit 1
fi

# 檢查環境變數
if [ -z "$APPLE_ID" ]; then
    print_error "未設定 APPLE_ID"
    echo "請執行 ./scripts/setup-signing.sh 或設定環境變數"
    exit 1
fi

if [ -z "$TEAM_ID" ]; then
    print_error "未設定 TEAM_ID"
    echo "請執行 ./scripts/setup-signing.sh 或設定環境變數"
    exit 1
fi

# 取得 App-Specific Password
get_password() {
    # 嘗試從 Keychain 讀取
    local password
    password=$(security find-generic-password -a "$APPLE_ID" -s "com.apple.notarization" -w 2>/dev/null) || true

    if [ -z "$password" ]; then
        print_warning "Keychain 中未找到密碼"
        echo "請輸入 App-Specific Password:"
        read -s password
    fi

    echo "$password"
}

# 建立 zip（如果是 .app）
prepare_for_notarization() {
    local input="$1"
    local ext="${input##*.}"

    if [ "$ext" = "app" ]; then
        local zip_path="${input%.app}.zip"
        print_step "建立 zip: $zip_path"
        ditto -c -k --keepParent "$input" "$zip_path"
        echo "$zip_path"
    else
        echo "$input"
    fi
}

# 提交公證
submit_for_notarization() {
    local file_path="$1"
    local password="$2"

    print_step "提交公證..."
    print_step "檔案: $file_path"
    print_step "Apple ID: $APPLE_ID"
    print_step "Team ID: $TEAM_ID"

    xcrun notarytool submit "$file_path" \
        --apple-id "$APPLE_ID" \
        --password "$password" \
        --team-id "$TEAM_ID" \
        --wait \
        --progress
}

# 裝訂票證
staple_ticket() {
    local app_path="$1"

    print_step "裝訂票證..."

    if [[ "$app_path" == *.zip ]]; then
        # 如果是 zip，先解壓縮再裝訂
        local app_name="${app_path%.zip}.app"
        if [ -d "$app_name" ]; then
            xcrun stapler staple "$app_name"
        else
            print_warning "找不到 App 進行裝訂: $app_name"
        fi
    else
        xcrun stapler staple "$app_path"
    fi
}

# 驗證公證狀態
verify_notarization() {
    local app_path="$1"

    print_step "驗證公證狀態..."

    if [[ "$app_path" == *.app ]]; then
        spctl --assess --type execute --verbose "$app_path"
    elif [[ "$app_path" == *.dmg ]]; then
        spctl --assess --type open --context context:primary-signature --verbose "$app_path"
    fi
}

# 主程式
main() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║              Reclip - Apple 公證工具                        ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""

    # 取得密碼
    local password
    password=$(get_password)

    if [ -z "$password" ]; then
        print_error "無法取得 App-Specific Password"
        exit 1
    fi

    # 準備檔案
    local file_to_submit
    file_to_submit=$(prepare_for_notarization "$APP_PATH")

    # 提交公證
    if submit_for_notarization "$file_to_submit" "$password"; then
        print_step "公證成功！"

        # 裝訂票證
        staple_ticket "$APP_PATH"

        # 驗證
        verify_notarization "$APP_PATH"

        # 清理 zip
        if [ "$file_to_submit" != "$APP_PATH" ]; then
            rm -f "$file_to_submit"
        fi

        echo ""
        print_step "公證完成！App 已準備好發行。"
    else
        print_error "公證失敗"
        exit 1
    fi
}

main
