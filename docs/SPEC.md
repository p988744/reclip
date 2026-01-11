# Reclip 專案規格書

Podcast 自動剪輯工具 - 使用 AI 分析逐字稿，自動移除語氣詞、重複、口誤和長停頓。

---

## 目標

將 Podcast 原始音訊自動剪輯成乾淨版本，省去手動剪輯的繁瑣工作。

---

## 平台與技術

| 項目 | 規格 |
|------|------|
| **平台** | macOS 26+（主要）、iOS/iPadOS 26+（未來） |
| **語言** | Swift 6.0 |
| **UI** | SwiftUI + Liquid Glass（macOS 26 設計語言） |
| **ASR** | WhisperKit（本地） |
| **LLM** | Claude API（雲端）/ Ollama（本地） |
| **音訊** | AVFoundation |
| **同步** | SwiftData + CloudKit |
| **發行** | DMG（初期）→ App Store（未來） |

---

## 核心功能

### 1. 語音辨識 (ASR)

```
輸入: 音訊檔 (wav, mp3, m4a, flac)
輸出: 逐字稿 (含時間戳)
```

- WhisperKit 本地處理
- 支援多語言（中、英、日、韓...）
- 單詞級時間戳
- 說話者分離（規劃中）

### 2. AI 分析

```
輸入: 逐字稿
輸出: 需移除的區間清單
```

**移除類型:**

| 類型 | 說明 | 範例 |
|------|------|------|
| `filler` | 語氣詞 | 嗯、啊、呃、um、uh |
| `repeat` | 重複詞語 | 我我我、the the |
| `restart` | 重新開始 | 這個...那個功能是... |
| `mouthNoise` | 唇齒音 | 咂嘴聲、吸氣聲 |
| `longPause` | 長停頓 | 超過 1.5 秒的沉默 |

**LLM 選項:**

| 提供者 | 類型 | 費用 | 隱私 |
|--------|------|------|------|
| Claude API | 雲端 | ~$0.03/hr | 需傳送資料 |
| Ollama | 本地 | 免費 | 完全本地 |

### 3. 音訊剪輯

```
輸入: 原始音訊 + 移除區間
輸出: 剪輯後音訊
```

- AVFoundation Composition
- Crossfade 過渡（30ms）
- Zero-crossing 對齊（避免爆音）
- 合併相鄰區間

### 4. 匯出

| 格式 | 用途 |
|------|------|
| M4A | 剪輯後音訊 |
| JSON | 編輯報告 |
| EDL | DaVinci/Premiere |
| CSV | Audacity 標記 |

---

## 架構

```
┌─────────────────────────────────────────────────────────────┐
│                        Reclip.app                            │
├─────────────────────────────────────────────────────────────┤
│  ReclipUI                                                    │
│  ├── ContentView          主介面                             │
│  ├── SettingsView         設定頁面                           │
│  ├── AIConsentView        AI 同意對話框                       │
│  ├── GlassComponents      Liquid Glass 元件                  │
│  └── WaveformView         波形顯示                           │
├─────────────────────────────────────────────────────────────┤
│  ReclipCore                                                  │
│  ├── Models/              資料模型                           │
│  │   ├── TranscriptModels   逐字稿                           │
│  │   ├── AnalysisModels     分析結果                         │
│  │   ├── EditModels         編輯報告                         │
│  │   ├── Project            專案（SwiftData）                │
│  │   └── Settings           設定                             │
│  ├── AudioEditor/         音訊編輯器                         │
│  └── Exporters/           匯出器                             │
├─────────────────────────────────────────────────────────────┤
│  ReclipASR                    │  ReclipLLM                   │
│  ├── ASRProvider (protocol)   │  ├── LLMProvider (protocol)  │
│  └── WhisperKitProvider       │  ├── ClaudeProvider          │
│                               │  └── OllamaProvider          │
└─────────────────────────────────────────────────────────────┘
```

---

## 資料模型

### TranscriptResult

```swift
struct TranscriptResult {
    let segments: [Segment]
    let language: String
    let duration: TimeInterval
}

struct Segment {
    let text: String
    let start: TimeInterval
    let end: TimeInterval
    let speaker: String?
    let words: [WordSegment]
}

struct WordSegment {
    let word: String
    let start: TimeInterval
    let end: TimeInterval
    let confidence: Double
    let speaker: String?
}
```

### AnalysisResult

```swift
struct AnalysisResult {
    let removals: [Removal]
    let originalDuration: TimeInterval
}

struct Removal {
    let id: UUID
    let start: TimeInterval
    let end: TimeInterval
    let reason: RemovalReason
    let text: String
    let confidence: Double
}

enum RemovalReason {
    case filler, repeat, restart, mouthNoise, longPause
}
```

### EditReport

```swift
struct EditReport {
    let inputURL: URL
    let outputURL: URL
    let originalDuration: TimeInterval
    let editedDuration: TimeInterval
    let edits: [AppliedEdit]
}
```

---

## 使用者介面

### 主要畫面

1. **側邊欄**: 專案列表
2. **主內容區**:
   - 波形顯示 + 移除標記
   - 逐字稿
3. **工具列**: 播放控制、處理按鈕
4. **檢視器**: 統計資訊

### 處理流程

```
[匯入音訊] → [轉錄] → [分析] → [預覽] → [剪輯] → [匯出]
     ↓          ↓         ↓         ↓          ↓         ↓
   選擇檔案   WhisperKit  Claude   波形標記   AVFoundation  M4A/JSON
```

---

## 設定項目

### ASR 設定

| 項目 | 預設值 | 說明 |
|------|--------|------|
| 模型大小 | large-v3 | tiny/base/small/medium/large |
| 語言 | 自動偵測 | zh/en/ja/ko... |
| 說話者分離 | 關閉 | 未來功能 |

### LLM 設定

| 項目 | 預設值 | 說明 |
|------|--------|------|
| 提供者 | Claude | Claude/Ollama |
| Claude 模型 | Sonnet 4 | Sonnet/Opus/Haiku |
| Ollama 模型 | llama3.2 | 本地模型 |
| Ollama 主機 | localhost:11434 | 自訂主機 |

### 編輯器設定

| 項目 | 預設值 | 說明 |
|------|--------|------|
| Crossfade | 30ms | 過渡時間 |
| 最小移除長度 | 100ms | 過短不移除 |
| 信心閾值 | 80% | 低於不移除 |

### 同步設定

| 項目 | 預設值 | 說明 |
|------|--------|------|
| iCloud 同步 | 開啟 | 專案資料 |
| 同步音訊 | 關閉 | 大檔案可選 |

---

## 安全與隱私

### App Sandbox（App Store）

```xml
com.apple.security.app-sandbox = true
com.apple.security.network.client = true
com.apple.security.files.user-selected.read-write = true
```

### Privacy Manifest

- UserDefaults（App 設定）
- File Timestamp（顯示日期）
- Audio Data（App 功能，不追蹤）

### 第三方 AI 揭露

- 首次使用 Claude 前需同意
- 說明資料傳送至 Anthropic
- 提供本地替代方案

---

## 發行

### DMG（初期）

```bash
./scripts/build-dmg.sh release
```

- Developer ID 簽名
- 公證（notarization）
- DMG 打包

### App Store（未來）

- App Sandbox 啟用
- 隱私標籤填寫
- AI 功能揭露
- 審核提交

---

## API 費用估算

| 服務 | 費用 |
|------|------|
| WhisperKit | 免費（本地） |
| Ollama | 免費（本地） |
| Claude API | ~$0.03-0.05/hr 音訊 |

**計算方式:**
- 1 小時音訊 ≈ 8000-10000 tokens
- Claude Sonnet: $3/M input, $15/M output
- 實際費用視逐字稿長度而定

---

## 版本規劃

### v1.0（MVP）

- [x] 專案架構
- [x] 資料模型
- [x] UI 框架
- [ ] WhisperKit 整合（架構完成，需測試）
- [ ] Claude/Ollama 整合（架構完成，需測試）
- [ ] 音訊剪輯（架構完成，需測試）
- [ ] DMG 發行

### v1.1

- [ ] 說話者分離
- [ ] 批次處理
- [ ] 快捷鍵

### v2.0

- [ ] iOS/iPadOS 支援
- [ ] App Store 上架
- [ ] 多語言介面
