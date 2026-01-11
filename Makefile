# Reclip Makefile
# macOS Podcast Auto-Editor

.PHONY: all clean build run test generate dmg help

# 預設目標
all: generate build

# 生成 Xcode 專案（需要 xcodegen）
generate:
	@echo "📦 生成 Xcode 專案..."
	@if command -v xcodegen >/dev/null 2>&1; then \
		xcodegen generate; \
	else \
		echo "❌ 請先安裝 xcodegen: brew install xcodegen"; \
		exit 1; \
	fi

# 建構 Debug 版本
build:
	@echo "🔨 建構 Debug 版本..."
	xcodebuild -scheme Reclip -configuration Debug -destination "platform=macOS" build

# 建構 Release 版本
build-release:
	@echo "🔨 建構 Release 版本..."
	xcodebuild -scheme Reclip -configuration Release -destination "platform=macOS" build

# 執行 App
run: build
	@echo "🚀 啟動 Reclip..."
	@open "$$(xcodebuild -scheme Reclip -showBuildSettings | grep -m 1 'BUILT_PRODUCTS_DIR' | sed 's/.*= //')/Reclip.app"

# 執行測試
test:
	@echo "🧪 執行測試..."
	xcodebuild -scheme Reclip -configuration Debug -destination "platform=macOS" test

# 建立 DMG
dmg:
	@echo "💿 建立 DMG..."
	./scripts/build-dmg.sh release

# 清理建構
clean:
	@echo "🧹 清理..."
	xcodebuild -scheme Reclip clean
	rm -rf build/
	rm -rf DerivedData/

# 解析 Swift Package 依賴
resolve:
	@echo "📥 解析依賴..."
	xcodebuild -resolvePackageDependencies

# 格式化程式碼（需要 swiftformat）
format:
	@echo "✨ 格式化程式碼..."
	@if command -v swiftformat >/dev/null 2>&1; then \
		swiftformat .; \
	else \
		echo "❌ 請先安裝 swiftformat: brew install swiftformat"; \
	fi

# Lint 檢查（需要 swiftlint）
lint:
	@echo "🔍 Lint 檢查..."
	@if command -v swiftlint >/dev/null 2>&1; then \
		swiftlint; \
	else \
		echo "❌ 請先安裝 swiftlint: brew install swiftlint"; \
	fi

# 設定開發環境
setup:
	@echo "⚙️  設定開發環境..."
	@echo ""
	@echo "📦 安裝必要工具..."
	brew install xcodegen swiftformat swiftlint create-dmg || true
	@echo ""
	@echo "📦 生成 Xcode 專案..."
	xcodegen generate
	@echo ""
	@echo "✅ 設定完成！"
	@echo ""
	@echo "下一步："
	@echo "  1. 開啟 Reclip.xcodeproj"
	@echo "  2. 選擇 Reclip scheme"
	@echo "  3. 按 Cmd+R 執行"

# 顯示說明
help:
	@echo "Reclip Makefile"
	@echo ""
	@echo "用法: make [目標]"
	@echo ""
	@echo "目標:"
	@echo "  setup          - 設定開發環境（首次使用）"
	@echo "  generate       - 生成 Xcode 專案"
	@echo "  build          - 建構 Debug 版本"
	@echo "  build-release  - 建構 Release 版本"
	@echo "  run            - 建構並執行"
	@echo "  test           - 執行測試"
	@echo "  dmg            - 建立 DMG 安裝檔"
	@echo "  clean          - 清理建構產物"
	@echo "  resolve        - 解析 Package 依賴"
	@echo "  format         - 格式化程式碼"
	@echo "  lint           - Lint 檢查"
	@echo "  help           - 顯示此說明"
