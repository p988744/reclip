#!/bin/bash
# Apple Developer Program 簽名設定腳本
# 用於設定程式碼簽名和公證所需的環境

set -e

# 顏色輸出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_step() { echo -e "${GREEN}==>${NC} $1"; }
print_warning() { echo -e "${YELLOW}警告:${NC} $1"; }
print_error() { echo -e "${RED}錯誤:${NC} $1"; }
print_info() { echo -e "${BLUE}資訊:${NC} $1"; }

# 配置檔路徑
CONFIG_DIR="$HOME/.reclip"
CONFIG_FILE="$CONFIG_DIR/signing.env"

# 建立配置目錄
mkdir -p "$CONFIG_DIR"

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║       Reclip - Apple Developer Program 設定精靈            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# 檢查是否已有配置
if [ -f "$CONFIG_FILE" ]; then
    print_warning "發現現有配置檔: $CONFIG_FILE"
    read -p "是否要重新設定？(y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "使用現有配置"
        source "$CONFIG_FILE"
        echo ""
        echo "目前設定："
        echo "  Team ID: $TEAM_ID"
        echo "  Apple ID: $APPLE_ID"
        echo "  Bundle ID: $BUNDLE_ID"
        exit 0
    fi
fi

# 收集資訊
echo ""
print_step "請輸入 Apple Developer Program 資訊"
echo ""

# Team ID
echo "Team ID 可在 https://developer.apple.com/account 找到"
read -p "Team ID: " TEAM_ID

# Apple ID
echo ""
echo "用於公證的 Apple ID（建議使用 App-Specific Password）"
read -p "Apple ID (email): " APPLE_ID

# Bundle ID
echo ""
echo "App Bundle Identifier（例如: com.yourcompany.reclip）"
read -p "Bundle ID [com.reclip.app]: " BUNDLE_ID
BUNDLE_ID=${BUNDLE_ID:-com.reclip.app}

# 簽名身份
echo ""
echo "程式碼簽名身份（執行 'security find-identity -v -p codesigning' 查看可用身份）"
echo "  1) Developer ID Application（DMG 發行）"
echo "  2) Apple Development（開發測試）"
echo "  3) 3rd Party Mac Developer Application（App Store）"
read -p "選擇簽名類型 [1]: " SIGN_TYPE
SIGN_TYPE=${SIGN_TYPE:-1}

case $SIGN_TYPE in
    1) CODE_SIGN_IDENTITY="Developer ID Application" ;;
    2) CODE_SIGN_IDENTITY="Apple Development" ;;
    3) CODE_SIGN_IDENTITY="3rd Party Mac Developer Application" ;;
    *) CODE_SIGN_IDENTITY="Developer ID Application" ;;
esac

# 儲存配置
cat > "$CONFIG_FILE" << EOF
# Reclip Apple Developer Program 配置
# 產生時間: $(date)

# Apple Developer Team ID
export TEAM_ID="$TEAM_ID"

# Apple ID（用於公證）
export APPLE_ID="$APPLE_ID"

# App Bundle Identifier
export BUNDLE_ID="$BUNDLE_ID"

# 程式碼簽名身份
export CODE_SIGN_IDENTITY="$CODE_SIGN_IDENTITY"

# iCloud 容器 ID
export ICLOUD_CONTAINER="iCloud.$BUNDLE_ID"

# App Group ID
export APP_GROUP="group.$BUNDLE_ID"
EOF

chmod 600 "$CONFIG_FILE"

echo ""
print_step "配置已儲存至: $CONFIG_FILE"

# 設定 App-Specific Password
echo ""
print_step "設定 App-Specific Password（用於公證）"
echo ""
echo "請前往 https://appleid.apple.com/account/manage"
echo "在「App-Specific Passwords」區塊產生密碼"
echo ""
read -p "是否要現在設定 App-Specific Password？(y/N) " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo "請輸入 App-Specific Password（不會顯示在螢幕上）"
    read -s -p "Password: " APP_PASSWORD
    echo ""

    # 儲存到 Keychain
    security add-generic-password \
        -a "$APPLE_ID" \
        -s "com.apple.notarization" \
        -w "$APP_PASSWORD" \
        -U 2>/dev/null || true

    print_step "密碼已儲存至 Keychain"
fi

# 驗證設定
echo ""
print_step "驗證設定..."

# 檢查簽名身份
echo ""
print_info "可用的簽名身份："
security find-identity -v -p codesigning | grep "$TEAM_ID" || print_warning "未找到 Team ID 對應的簽名身份"

# 檢查 Xcode
echo ""
if xcode-select -p &>/dev/null; then
    print_step "Xcode Command Line Tools: $(xcode-select -p)"
else
    print_warning "未安裝 Xcode Command Line Tools"
fi

# 輸出下一步
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                        設定完成                             ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "下一步："
echo ""
echo "  1. 在 Apple Developer Portal 建立 App ID："
echo "     https://developer.apple.com/account/resources/identifiers/list"
echo ""
echo "  2. 建立必要的 Provisioning Profiles："
echo "     https://developer.apple.com/account/resources/profiles/list"
echo ""
echo "  3. 更新 project.yml 中的 DEVELOPMENT_TEAM："
echo "     DEVELOPMENT_TEAM: $TEAM_ID"
echo ""
echo "  4. 建構並簽名 App："
echo "     source $CONFIG_FILE"
echo "     ./scripts/build-dmg.sh release"
echo ""
