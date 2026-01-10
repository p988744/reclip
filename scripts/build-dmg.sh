#!/bin/bash
# Reclip DMG Build Script
# 建構並打包 Reclip.app 為 DMG 安裝檔

set -e

# 配置
APP_NAME="Reclip"
SCHEME="Reclip"
CONFIGURATION="Release"
ARCHIVE_PATH="build/${APP_NAME}.xcarchive"
EXPORT_PATH="build/export"
DMG_PATH="build/${APP_NAME}.dmg"
TEAM_ID="${TEAM_ID:-}"  # 從環境變數取得，或留空（開發時不需要）

# 顏色輸出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_step() {
    echo -e "${GREEN}==>${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}警告:${NC} $1"
}

print_error() {
    echo -e "${RED}錯誤:${NC} $1"
}

# 檢查必要工具
check_requirements() {
    print_step "檢查必要工具..."

    if ! command -v xcodebuild &> /dev/null; then
        print_error "找不到 xcodebuild，請安裝 Xcode Command Line Tools"
        exit 1
    fi

    if ! command -v create-dmg &> /dev/null; then
        print_warning "找不到 create-dmg，將使用 hdiutil 建立簡易 DMG"
        print_warning "建議安裝: brew install create-dmg"
        USE_HDIUTIL=true
    else
        USE_HDIUTIL=false
    fi
}

# 清理舊建構
clean_build() {
    print_step "清理舊建構..."
    rm -rf build/
    mkdir -p build
}

# 建構 App
build_app() {
    print_step "建構 ${APP_NAME}.app (${CONFIGURATION})..."

    # 建構參數
    BUILD_ARGS=(
        -scheme "${SCHEME}"
        -configuration "${CONFIGURATION}"
        -destination "generic/platform=macOS"
        -archivePath "${ARCHIVE_PATH}"
        archive
    )

    # 如果有 workspace，使用 workspace
    if [ -f "${APP_NAME}.xcworkspace/contents.xcworkspacedata" ]; then
        BUILD_ARGS=(-workspace "${APP_NAME}.xcworkspace" "${BUILD_ARGS[@]}")
    elif [ -f "${APP_NAME}.xcodeproj/project.pbxproj" ]; then
        BUILD_ARGS=(-project "${APP_NAME}.xcodeproj" "${BUILD_ARGS[@]}")
    else
        print_error "找不到 Xcode 專案檔"
        exit 1
    fi

    xcodebuild "${BUILD_ARGS[@]}"
}

# 匯出 App
export_app() {
    print_step "匯出 ${APP_NAME}.app..."

    mkdir -p "${EXPORT_PATH}"

    # 建立 ExportOptions.plist
    cat > build/ExportOptions.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>destination</key>
    <string>export</string>
</dict>
</plist>
EOF

    xcodebuild -exportArchive \
        -archivePath "${ARCHIVE_PATH}" \
        -exportPath "${EXPORT_PATH}" \
        -exportOptionsPlist build/ExportOptions.plist
}

# 公證 App（可選）
notarize_app() {
    if [ -z "${TEAM_ID}" ]; then
        print_warning "未設定 TEAM_ID，跳過公證步驟"
        print_warning "首次發布時請設定環境變數: export TEAM_ID=your_team_id"
        return 0
    fi

    if [ -z "${APPLE_ID}" ] || [ -z "${APPLE_PASSWORD}" ]; then
        print_warning "未設定 APPLE_ID 或 APPLE_PASSWORD，跳過公證步驟"
        print_warning "設定方式:"
        print_warning "  export APPLE_ID=your@email.com"
        print_warning "  export APPLE_PASSWORD=your-app-specific-password"
        return 0
    fi

    print_step "公證 ${APP_NAME}.app..."

    # 建立 zip 用於公證
    ditto -c -k --keepParent "${EXPORT_PATH}/${APP_NAME}.app" "build/${APP_NAME}.zip"

    # 提交公證
    xcrun notarytool submit "build/${APP_NAME}.zip" \
        --apple-id "${APPLE_ID}" \
        --password "${APPLE_PASSWORD}" \
        --team-id "${TEAM_ID}" \
        --wait

    # 裝訂票證
    xcrun stapler staple "${EXPORT_PATH}/${APP_NAME}.app"

    print_step "公證完成！"
}

# 建立 DMG
create_dmg_file() {
    print_step "建立 DMG 安裝檔..."

    if [ "${USE_HDIUTIL}" = true ]; then
        # 使用 hdiutil 建立簡易 DMG
        create_simple_dmg
    else
        # 使用 create-dmg 建立美觀的 DMG
        create_fancy_dmg
    fi
}

create_simple_dmg() {
    print_step "使用 hdiutil 建立 DMG..."

    # 建立臨時目錄
    DMG_TEMP="build/dmg_temp"
    mkdir -p "${DMG_TEMP}"

    # 複製 App
    cp -R "${EXPORT_PATH}/${APP_NAME}.app" "${DMG_TEMP}/"

    # 建立 Applications 連結
    ln -s /Applications "${DMG_TEMP}/Applications"

    # 建立 DMG
    hdiutil create -volname "${APP_NAME}" \
        -srcfolder "${DMG_TEMP}" \
        -ov -format UDZO \
        "${DMG_PATH}"

    # 清理
    rm -rf "${DMG_TEMP}"
}

create_fancy_dmg() {
    print_step "使用 create-dmg 建立 DMG..."

    # 移除舊的 DMG
    rm -f "${DMG_PATH}"

    create-dmg \
        --volname "${APP_NAME}" \
        --volicon "Reclip/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png" \
        --window-pos 200 120 \
        --window-size 660 400 \
        --icon-size 100 \
        --icon "${APP_NAME}.app" 160 185 \
        --hide-extension "${APP_NAME}.app" \
        --app-drop-link 500 185 \
        --background "resources/dmg-background.png" \
        "${DMG_PATH}" \
        "${EXPORT_PATH}/${APP_NAME}.app"
}

# 開發模式：直接建構不打包
build_dev() {
    print_step "開發模式建構..."

    xcodebuild \
        -scheme "${SCHEME}" \
        -configuration Debug \
        -destination "platform=macOS" \
        build

    print_step "建構完成！執行檔位於 DerivedData 目錄"
}

# 主程式
main() {
    cd "$(dirname "$0")/.."

    case "${1:-release}" in
        dev|debug)
            check_requirements
            build_dev
            ;;
        release)
            check_requirements
            clean_build
            build_app
            export_app
            notarize_app
            create_dmg_file
            print_step "完成！DMG 檔案：${DMG_PATH}"
            ;;
        clean)
            clean_build
            print_step "清理完成"
            ;;
        *)
            echo "用法: $0 [dev|release|clean]"
            echo ""
            echo "選項:"
            echo "  dev     - 開發模式建構（Debug，不打包）"
            echo "  release - 發布模式（Release + DMG）"
            echo "  clean   - 清理建構目錄"
            echo ""
            echo "環境變數:"
            echo "  TEAM_ID        - Apple Developer Team ID（公證用）"
            echo "  APPLE_ID       - Apple ID 電子郵件（公證用）"
            echo "  APPLE_PASSWORD - App-specific password（公證用）"
            exit 1
            ;;
    esac
}

main "$@"
