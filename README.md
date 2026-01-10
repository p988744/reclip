# Reclip

Podcast 自動剪輯工具 - 使用 AI 自動移除語氣詞、重複、口誤和長停頓。

## 功能

- **語音辨識 (ASR)**: 使用 WhisperKit 進行本地語音轉文字
- **AI 分析**: 使用 Claude API 或 Ollama 分析逐字稿，識別需移除的內容
- **自動剪輯**: 基於 AVFoundation，支援 Crossfade 和 Zero-crossing
- **iCloud 同步**: 專案和設定自動同步到所有裝置
- **Liquid Glass UI**: macOS 26 原生設計

## 系統需求

- macOS 26.0+
- Xcode 16.0+
- Swift 6.0+

## 快速開始

### 1. 安裝開發工具

```bash
# 安裝必要工具
brew install xcodegen swiftformat swiftlint create-dmg
```

### 2. 生成 Xcode 專案

```bash
# 使用 Makefile
make setup

# 或直接使用 xcodegen
xcodegen generate
```

### 3. 開啟專案

```bash
open Reclip.xcodeproj
```

### 4. 建構與執行

在 Xcode 中選擇 `Reclip` scheme，按 `Cmd+R` 執行。

或使用命令列：

```bash
make build
make run
```

## 專案結構

```
reclip/
├── Reclip/                   # macOS App
│   ├── ReclipApp.swift       # App 入口
│   ├── Info.plist            # App 資訊
│   ├── Reclip.entitlements   # 權限設定
│   └── Assets.xcassets/      # 資源檔
│
├── ReclipKit/                # Swift Package
│   ├── Sources/
│   │   ├── ReclipCore/       # 核心邏輯
│   │   │   ├── Models/       # 資料模型
│   │   │   ├── AudioEditor/  # 音訊編輯
│   │   │   └── Exporters/    # 匯出功能
│   │   ├── ReclipASR/        # 語音辨識
│   │   ├── ReclipLLM/        # LLM 整合
│   │   └── ReclipUI/         # UI 元件
│   └── Tests/
│
├── scripts/
│   └── build-dmg.sh          # DMG 建構腳本
│
├── docs/
│   ├── SWIFT_FEASIBILITY.md  # 技術可行性報告
│   ├── DESIGN_GUIDELINES.md  # 設計規範
│   └── APP_STORE_COMPLIANCE.md
│
├── project.yml               # XcodeGen 配置
├── Makefile                  # 建構命令
└── README.md
```

## 開發命令

```bash
# 設定開發環境（首次使用）
make setup

# 生成 Xcode 專案
make generate

# Debug 建構
make build

# Release 建構
make build-release

# 建構並執行
make run

# 執行測試
make test

# 建立 DMG
make dmg

# 清理
make clean

# 格式化程式碼
make format

# Lint 檢查
make lint
```

## AI 設定

### Claude API（雲端）

1. 前往 [Anthropic Console](https://console.anthropic.com/) 取得 API Key
2. 在 App 設定中貼上 API Key
3. 選擇模型（建議使用 Claude Sonnet 4）

### Ollama（本地）

1. 安裝 Ollama: `brew install ollama`
2. 下載模型: `ollama pull llama3.2`
3. 啟動服務: `ollama serve`
4. 在 App 設定中選擇 Ollama

## 建立 DMG

```bash
# 完整建構流程
./scripts/build-dmg.sh release

# 開發模式建構
./scripts/build-dmg.sh dev

# 清理
./scripts/build-dmg.sh clean
```

### 公證（可選）

```bash
export TEAM_ID=your_team_id
export APPLE_ID=your@email.com
export APPLE_PASSWORD=your-app-specific-password

./scripts/build-dmg.sh release
```

## 架構

```
┌──────────────────────────────────────────────────────────────┐
│                        Reclip App                             │
│  ┌────────────────────────────────────────────────────────┐  │
│  │                     ReclipUI                            │  │
│  │  ┌──────────┐ ┌──────────┐ ┌───────────────────────┐   │  │
│  │  │ContentView│ │SettingsView│ │GlassComponents      │   │  │
│  │  └──────────┘ └──────────┘ └───────────────────────┘   │  │
│  └────────────────────────────────────────────────────────┘  │
│                             │                                 │
│  ┌──────────────────────────┼─────────────────────────────┐  │
│  │                     ReclipCore                          │  │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐                │  │
│  │  │ Models   │ │AudioEditor│ │ Exporters │                │  │
│  │  └──────────┘ └──────────┘ └──────────┘                │  │
│  └────────────────────────────────────────────────────────┘  │
│                             │                                 │
│  ┌────────────┐      ┌─────────────┐                         │
│  │ ReclipASR  │      │  ReclipLLM  │                         │
│  │ WhisperKit │      │ Claude/Ollama│                         │
│  └────────────┘      └─────────────┘                         │
└──────────────────────────────────────────────────────────────┘
```

## 移除類型

| 類型 | 說明 | 範例 |
|------|------|------|
| **filler** | 語氣詞、填充詞 | 嗯、啊、呃、um, uh |
| **repeat** | 重複的詞語或片語 | 我我我要說 |
| **restart** | 句子重新開始 | 這個... 那個功能是... |
| **mouthNoise** | 唇齒音或雜音 | 咂嘴聲、吸氣聲 |
| **longPause** | 超過 1.5 秒的停頓 | [silence] |

## 匯出格式

- **JSON**: 完整的編輯報告與統計
- **EDL**: 可匯入 DaVinci Resolve、Premiere 等
- **CSV/TXT**: Audacity 標記格式

## API 費用估算

- **Claude API**: 約 $0.03-0.05/小時音訊
- **Ollama**: 本地運行，完全免費
- **WhisperKit**: 本地運行，完全免費

---

## 舊版本

Python + Rust + Tauri 版本保留在 `claude/podcast-auto-editor-TGVdX` 分支。

## 授權

MIT License
