# Reclip - Claude 開發指南

此文件提供 Claude 開發 Reclip 專案時的快速上下文。

---

## 專案概述

**Reclip** 是一個 macOS Podcast 自動剪輯工具，使用 AI 分析逐字稿並自動移除語氣詞、重複、口誤和長停頓。

---

## 技術棧

| 類別 | 技術 |
|------|------|
| 語言 | Swift 6.0 |
| 平台 | macOS 26+（主要）|
| UI | SwiftUI + Liquid Glass |
| ASR | WhisperKit |
| LLM | Claude API / Ollama |
| 音訊 | AVFoundation |
| 資料 | SwiftData + CloudKit |
| 建構 | XcodeGen + Fastlane |

---

## 專案結構

```
reclip/
├── Reclip/                      # macOS App
│   ├── ReclipApp.swift          # App 入口
│   ├── Info.plist
│   ├── Reclip.entitlements      # DMG 用
│   └── Reclip-AppStore.entitlements
│
├── ReclipKit/                   # Swift Package
│   └── Sources/
│       ├── ReclipCore/          # 核心邏輯
│       │   ├── Models/          # 資料模型
│       │   │   ├── TranscriptModels.swift
│       │   │   ├── AnalysisModels.swift
│       │   │   ├── EditModels.swift
│       │   │   ├── Project.swift      # SwiftData
│       │   │   └── Settings.swift     # AppSettings
│       │   ├── AudioEditor/
│       │   │   └── AudioEditor.swift  # AVFoundation
│       │   └── Exporters/
│       │       └── ReportExporter.swift
│       │
│       ├── ReclipASR/           # 語音辨識
│       │   ├── ASRProvider.swift      # Protocol
│       │   └── WhisperKitProvider.swift
│       │
│       ├── ReclipLLM/           # LLM 分析
│       │   ├── LLMProvider.swift      # Protocol
│       │   ├── ClaudeProvider.swift
│       │   └── OllamaProvider.swift
│       │
│       └── ReclipUI/            # UI 元件
│           ├── Components/
│           │   ├── GlassComponents.swift  # Liquid Glass
│           │   └── WaveformView.swift
│           ├── Views/
│           │   ├── ContentView.swift
│           │   ├── SettingsView.swift
│           │   └── AIConsentView.swift
│           └── ViewModels/
│               └── ContentViewModel.swift
│
├── scripts/
│   ├── build-dmg.sh             # DMG 建構
│   ├── notarize.sh              # 公證
│   └── setup-signing.sh         # 簽名設定
│
├── fastlane/
│   ├── Fastfile
│   ├── Appfile
│   └── Matchfile
│
├── docs/
│   ├── SPEC.md                  # 規格書
│   ├── DESIGN_GUIDELINES.md     # 設計規範
│   ├── APP_STORE_COMPLIANCE.md  # App Store 合規
│   ├── DEVELOPER_SETUP.md       # 開發者設定
│   └── SWIFT_FEASIBILITY.md     # 技術可行性
│
├── project.yml                  # XcodeGen
├── Makefile
└── README.md
```

---

## 完成狀態

### ✅ 已完成

| 模組 | 狀態 | 說明 |
|------|------|------|
| 專案架構 | ✅ | Swift Package + App 結構 |
| 資料模型 | ✅ | Transcript, Analysis, Edit, Project, Settings |
| UI 框架 | ✅ | Liquid Glass, ContentView, SettingsView |
| ASR Provider | ✅ | WhisperKitProvider 架構 |
| LLM Provider | ✅ | ClaudeProvider, OllamaProvider 架構 |
| AudioEditor | ✅ | AVFoundation composition + crossfade |
| iCloud 同步 | ✅ | SwiftData + CloudKit |
| AI 同意流程 | ✅ | AIConsentView |
| 設定管理 | ✅ | AppSettings + Keychain |
| DMG 建構 | ✅ | build-dmg.sh + notarize.sh |
| CI/CD | ✅ | GitHub Actions |
| Fastlane | ✅ | 憑證管理 + 建構 |
| 文件 | ✅ | 規格、設計、合規指南 |

### 🔄 需測試

| 模組 | 狀態 | 說明 |
|------|------|------|
| WhisperKit 整合 | 🔄 | 架構完成，需實機測試 |
| Claude API | 🔄 | 架構完成，需 API Key 測試 |
| Ollama | 🔄 | 架構完成，需本地 Ollama 測試 |
| AudioEditor | 🔄 | 架構完成，需音訊檔測試 |
| 匯出功能 | 🔄 | EDL/JSON 匯出 |

### ⬜ 未完成

| 模組 | 狀態 | 說明 |
|------|------|------|
| 說話者分離 | ⬜ | 規劃中 |
| 批次處理 | ⬜ | 規劃中 |
| iOS 支援 | ⬜ | v2.0 |

---

## 關鍵檔案

### 資料模型

- `ReclipCore/Models/TranscriptModels.swift` - ASR 結果
- `ReclipCore/Models/AnalysisModels.swift` - LLM 分析結果
- `ReclipCore/Models/EditModels.swift` - 編輯報告
- `ReclipCore/Models/Project.swift` - SwiftData 專案模型
- `ReclipCore/Models/Settings.swift` - App 設定

### Provider Protocols

- `ReclipASR/ASRProvider.swift` - ASR 抽象介面
- `ReclipLLM/LLMProvider.swift` - LLM 抽象介面

### 核心實作

- `ReclipASR/WhisperKitProvider.swift` - WhisperKit 整合
- `ReclipLLM/ClaudeProvider.swift` - Claude API
- `ReclipLLM/OllamaProvider.swift` - Ollama 本地
- `ReclipCore/AudioEditor/AudioEditor.swift` - 音訊剪輯

### UI

- `ReclipUI/Views/ContentView.swift` - 主介面
- `ReclipUI/Views/SettingsView.swift` - 設定
- `ReclipUI/Components/GlassComponents.swift` - Liquid Glass

---

## 開發命令

```bash
# 首次設定
make setup

# 建構
make build

# 執行
make run

# 測試
make test

# DMG
make dmg
```

---

## 分支

| 分支 | 內容 |
|------|------|
| `claude/swift-native-TGVdX` | Swift 版本（目前開發中） |
| `claude/podcast-auto-editor-TGVdX` | Python + Rust 版本（保留） |

---

## 注意事項

1. **macOS 26**: 使用 Liquid Glass API，需要 Xcode 16+
2. **WhisperKit**: 首次執行會下載模型（~1GB+）
3. **Claude API**: 需要 API Key，費用約 $0.03/hr
4. **App Sandbox**: DMG 版本不需要，App Store 版本需要
5. **公證**: DMG 發行需要 Apple Developer Program

---

## 下一步

1. 實機測試 WhisperKit 轉錄
2. 測試 Claude API 分析
3. 測試 AudioEditor 剪輯輸出
4. 端對端流程測試
5. DMG 發行測試
