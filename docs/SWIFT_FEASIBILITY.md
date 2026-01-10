# Swift Native 技術可行性報告

## 結論：✅ 完全可行

所有關鍵技術都有成熟的 Swift 解決方案，可以建構完整的原生 Apple 平台應用。

---

## 1. 語音轉文字 (ASR)

### WhisperKit ✅
- **來源**: [argmaxinc/WhisperKit](https://github.com/argmaxinc/WhisperKit)
- **支援平台**: iOS 16+, macOS 14+
- **功能**:
  - ✅ Word-level timestamps（單詞級時間戳）
  - ✅ Real-time streaming（即時串流）
  - ✅ Voice Activity Detection
  - ✅ CoreML/Metal 加速
  - ✅ 多語言支援（含中文）
- **效能**:
  - 0.46s 每詞延遲（與 Fireworks 並列最快）
  - 2.2% WER（最高準確度）
- **模型大小**: ~150MB - 1.5GB（依模型選擇）

```swift
// 整合方式
dependencies: [
    .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0")
]
```

### API 備選方案
- Deepgram API
- AssemblyAI API
- OpenAI Whisper API

---

## 2. 說話者分離 (Speaker Diarization)

### SpeakerKit ✅
- **來源**: [Argmax SpeakerKit](https://www.argmaxinc.com/blog/speakerkit)
- **支援平台**: iOS 16+, macOS 13+
- **功能**:
  - ✅ 與 WhisperKit 無縫整合
  - ✅ 4 分鐘音訊約 1 秒處理完成
  - ✅ 準確度與 Pyannote 相當
  - ✅ 模型僅 ~10MB
- **狀態**: 可用（需確認授權模式）

### 備選方案
- Picovoice Falcon
- API: AssemblyAI, Deepgram

---

## 3. LLM 整合

### macOS: Ollama ✅
- **Swift 客戶端**:
  - [mattt/ollama-swift](https://github.com/mattt/ollama-swift) - 支援 structured outputs、tool use、vision
  - [kevinhermawan/OllamaKit](https://github.com/kevinhermawan/OllamaKit) - 成熟穩定

```swift
// ollama-swift 整合方式
dependencies: [
    .package(url: "https://github.com/mattt/ollama-swift.git", from: "0.4.0")
]
```

- **支援模型**: Llama 3.2, Mistral, Qwen, DeepSeek 等
- **優點**: 完全本地、隱私保護、無 API 費用
- **限制**: 僅 macOS

### iOS/macOS: Claude API ✅
- **Swift 客戶端**:
  - [jamesrochabrun/SwiftAnthropic](https://github.com/jamesrochabrun/SwiftAnthropic) - 最完整，支援 extended thinking
  - [GeorgeLyon/SwiftClaude](https://github.com/GeorgeLyon/SwiftClaude) - 支援 vision、prompt caching
  - [fumito-ito/AnthropicSwiftSDK](https://github.com/fumito-ito/AnthropicSwiftSDK) - 支援 Bedrock/Vertex AI

```swift
// SwiftAnthropic 整合方式
dependencies: [
    .package(url: "https://github.com/jamesrochabrun/SwiftAnthropic.git", from: "1.0.0")
]
```

---

## 4. 音訊處理

### AVFoundation ✅
- **功能**:
  - ✅ 音訊載入/儲存（多格式）
  - ✅ AVMutableComposition 剪輯
  - ✅ Cross-fade 過渡
  - ✅ 音量調整 (AVAudioMix)
- **零交叉點**: 需自行實作（讀取 PCM buffer）

### AudioKit（備選）
- 更高階的音訊處理 API
- 提供 AVAudioPCMBuffer extensions

### 實作策略
```swift
// 零交叉點檢測
func findZeroCrossing(in buffer: AVAudioPCMBuffer, near sample: Int) -> Int {
    guard let channelData = buffer.floatChannelData?[0] else { return sample }
    // ... 搜尋最近的零交叉點
}

// Cross-fade
func applyCrossfade(
    composition: AVMutableComposition,
    at time: CMTime,
    duration: CMTime
) {
    // 使用 AVMutableAudioMix 和 AVMutableAudioMixInputParameters
}
```

---

## 5. 架構建議

```
ReclipKit/                      # Swift Package
├── Sources/
│   ├── ReclipCore/             # 核心邏輯（共用）
│   │   ├── Models/
│   │   ├── AudioEditor/
│   │   └── Exporters/
│   │
│   ├── ReclipASR/              # ASR 抽象層
│   │   ├── ASRProvider.swift   # Protocol
│   │   ├── WhisperKitProvider.swift
│   │   └── APIProvider.swift
│   │
│   ├── ReclipLLM/              # LLM 抽象層
│   │   ├── LLMProvider.swift   # Protocol
│   │   ├── OllamaProvider.swift      # macOS only
│   │   └── ClaudeProvider.swift
│   │
│   └── ReclipUI/               # SwiftUI 元件（共用）
│
└── Apps/
    ├── Reclip-macOS/           # macOS App
    └── Reclip-iOS/             # iOS/iPadOS App
```

---

## 6. 平台特定考量

| 功能 | macOS | iOS/iPadOS |
|------|-------|------------|
| WhisperKit | ✅ | ✅ |
| SpeakerKit | ✅ | ✅ |
| Ollama (本地 LLM) | ✅ | ❌ |
| Claude API | ✅ | ✅ |
| 背景處理 | ✅ | ⚠️ 有限制 |
| 大型音訊檔案 | ✅ | ⚠️ 記憶體限制 |

### iOS 限制與解決方案
1. **背景處理**: 使用 `BGProcessingTask` 或限制處理時間
2. **記憶體**: 分段處理音訊，streaming 模式
3. **無本地 LLM**: 強制使用 Claude API

---

## 7. 依賴套件總覽

```swift
// Package.swift
dependencies: [
    // ASR
    .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),

    // LLM - Ollama (macOS)
    .package(url: "https://github.com/mattt/ollama-swift.git", from: "0.4.0"),

    // LLM - Claude API
    .package(url: "https://github.com/jamesrochabrun/SwiftAnthropic.git", from: "1.0.0"),
]
```

---

## 8. 風險與注意事項

### 低風險
- ✅ WhisperKit 成熟穩定，Apple 官方推薦
- ✅ Claude API 有多個 Swift SDK 可選
- ✅ AVFoundation 是 Apple 第一方框架

### 中風險
- ⚠️ SpeakerKit 授權模式需確認（可能需付費）
- ⚠️ Ollama Swift 客戶端由社群維護

### 注意事項
- 首次使用需下載 Whisper 模型（~150MB - 1.5GB）
- 需處理網路錯誤和 API rate limiting
- iOS 需考慮 App Store 審核規範

---

## 9. 下一步

1. **建立 Swift Package 結構**
2. **實作 Provider Protocols** (ASR, LLM)
3. **實作音訊編輯器**（零交叉點、crossfade）
4. **建立 SwiftUI 基礎 UI**
5. **整合測試**

---

## 參考連結

- [WhisperKit GitHub](https://github.com/argmaxinc/WhisperKit)
- [SpeakerKit Blog](https://www.argmaxinc.com/blog/speakerkit)
- [ollama-swift](https://github.com/mattt/ollama-swift)
- [SwiftAnthropic](https://github.com/jamesrochabrun/SwiftAnthropic)
- [AVFoundation Documentation](https://developer.apple.com/documentation/avfoundation)
- [Claude in Xcode 26](https://www.anthropic.com/news/claude-in-xcode)
