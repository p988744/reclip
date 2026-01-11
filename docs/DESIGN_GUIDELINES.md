# Reclip 設計規範

基於 Apple Human Interface Guidelines 與 Liquid Glass 設計系統 (WWDC 2025)

---

## 核心設計原則

### 1. 階層 (Hierarchy)

> **「透過深度傳達重要性」** — 使用透明度、折射和視覺重量來區分層級

| 層級 | 用途 | 透明度 |
|------|------|--------|
| **內容層** | 波形、文字、資料 | 不透明 |
| **控制層** | 工具列、按鈕 | Liquid Glass |
| **彈出層** | 對話框、選單 | Liquid Glass |

### 2. 和諧 (Harmony)

- 介面與內容的關係應該是**輔助**而非**競爭**
- Glass 效果應該讓內容更突出，而不是吸引注意力
- 跨平台保持一致的視覺語言

### 3. 一致性 (Consistency)

- 使用平台標準元件和行為
- 在所有視窗大小和顯示器上保持適應性設計
- 遵循 macOS 慣例（鍵盤快捷鍵、選單結構）

---

## Liquid Glass 使用規範

### ✅ 適合使用的場景

- 浮動工具列
- 導航元素
- 控制按鈕
- 彈出面板
- 側邊欄標題

### ❌ 不適合使用的場景

- 內容本身（列表、表格、媒體）
- 純裝飾目的
- 需要直接互動的主要內容
- 波形視圖內部

### 材質變體選擇

```swift
// 標準控制元件
.glassEffect(.regular)

// 媒體上的小型浮動控制
.glassEffect(.clear)

// 停用狀態
.glassEffect(.identity)
```

**`.clear` 變體條件**（必須全部滿足）：
1. 元素位於媒體內容上方
2. 內容不會因變暗而受影響
3. Glass 上的內容使用粗體明亮色彩

---

## 控制元件尺寸 (macOS)

| 尺寸 | 形狀 | 用途 |
|------|------|------|
| Mini, Small, Medium | 圓角矩形 | 緊湊面板、檢視器 |
| Large | 膠囊形 | 標準按鈕 |
| X-Large | 膠囊形 + Glass | 強調區域 |

---

## 文字與圖示

### 文字規範
- 使用高對比色（Glass 上建議白色）
- 使用粗體字重增加可讀性
- 系統會自動調整 vibrancy（鮮豔度）

### 圖示規範
- 使用 SF Symbols
- 選擇粗體版本（`.bold`）
- 適當尺寸（建議 16-24pt）

```swift
Image(systemName: "waveform")
    .font(.body.weight(.semibold))
```

---

## 無障礙設計

### 系統自動適應
- **減少透明度**：增加磨砂效果
- **增加對比度**：使用鮮明色彩和邊框
- **減少動態效果**：降低動畫強度

### 開發者實作

```swift
@Environment(\.accessibilityReduceTransparency) var reduceTransparency

.glassEffect(reduceTransparency ? .identity : .regular)
```

**最佳做法**：讓系統處理無障礙適應，除非絕對必要否則不要覆蓋。

---

## 動畫與轉場

### Morphing 轉場

```swift
@Namespace private var namespace

GlassEffectContainer(spacing: 30) {
    if isExpanded {
        expandedView
            .glassEffectID("control", in: namespace)
    } else {
        collapsedView
            .glassEffectID("control", in: namespace)
    }
}
```

### 動畫曲線
- 使用 `.bouncy` 或 `.spring` 動畫
- 避免線性動畫

```swift
withAnimation(.bouncy) {
    isExpanded.toggle()
}
```

---

## 色彩與語意

### Tint 使用原則
- ✅ 傳達語意（主要動作、狀態）
- ✅ 僅用於 Call-to-Action
- ❌ 純裝飾用途

### 語意色彩對應

| 動作 | 顏色 |
|------|------|
| 開始處理 | `.blue` |
| 執行剪輯 | `.green` |
| 警告/移除 | `.orange` |
| 錯誤 | `.red` |

```swift
Button("開始處理") { }
    .buttonStyle(.glass(tint: .blue))

Button("執行剪輯") { }
    .buttonStyle(.glass(tint: .green))
```

---

## Reclip 特定規範

### 波形視圖
- 波形本身**不使用** Glass 效果
- 移除區域使用半透明色塊標記
- 播放頭使用白色高對比

### 移除原因色彩

| 原因 | 顏色 | 用途 |
|------|------|------|
| 語氣詞 (filler) | `.orange` | 嗯、啊、um |
| 重複 (repeat) | `.purple` | 重複的詞語 |
| 重說 (restart) | `.blue` | 句子重新開始 |
| 雜音 (mouthNoise) | `.pink` | 唇齒音 |
| 長停頓 (longPause) | `.gray` | 超過 1.5 秒 |

### 面板佈局
```
┌─────────────────────────────────────────┐
│ 側邊欄          │ 主內容區               │
│ (不使用 Glass)  │                        │
│                 │ ┌─────────────────────┐│
│ 專案列表        │ │ 音訊資訊卡 (Glass)  ││
│                 │ └─────────────────────┘│
│                 │                        │
│                 │ ┌─────────────────────┐│
│                 │ │ 波形視圖 (無 Glass) ││
│                 │ └─────────────────────┘│
│                 │                        │
│                 │ ┌─────────────────────┐│
│                 │ │ 工具列 (Glass)      ││
│                 │ └─────────────────────┘│
└─────────────────────────────────────────┘
```

---

## 效能考量

1. **避免嵌套 Glass 容器**
2. 使用 `GlassEffectContainer` 優化取樣區域
3. 限制同時顯示的 Glass 元素數量
4. 大量資料使用 `LazyVStack` / `LazyHStack`

---

## 參考資源

- [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)
- [Liquid Glass Documentation](https://developer.apple.com/documentation/TechnologyOverviews/liquid-glass)
- [WWDC25: Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/)
- [WWDC25: Build a SwiftUI app with the new design](https://developer.apple.com/videos/play/wwdc2025/323/)
- [WWDC25: Get to know the new design system](https://developer.apple.com/videos/play/wwdc2025/356/)
