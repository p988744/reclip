# Reclip - Podcast 自動剪輯工具

自動剪輯 Podcast，利用 LLM 分析逐字稿，移除 filler words、重複內容、唇齒瑕疵，輸出順剪後的乾淨音訊。

## 功能特色

- **智慧分析**: 使用 Claude API 分析逐字稿，識別需要移除的內容
- **精確時間戳**: 使用 WhisperX 取得單詞級別的時間戳
- **說話者分離**: 自動識別不同說話者
- **零交叉點對齊**: 避免剪輯點產生爆音
- **Crossfade**: 平滑的音訊過渡
- **多種匯出格式**: JSON 報告、EDL、Audacity 標記

## 系統需求

- Python 3.10+
- CUDA 12.x (GPU 加速)
- FFmpeg
- 16GB+ VRAM GPU (建議 RTX 5060 Ti 16GB+)
- Rust 1.75+ (桌面應用)
- Node.js 18+ (前端)

## 安裝

### 1. 安裝 Python 依賴

```bash
# 建立虛擬環境
python -m venv venv
source venv/bin/activate  # Linux/Mac
# or: venv\Scripts\activate  # Windows

# 安裝依賴
pip install -r requirements.txt
```

### 2. 設定環境變數

```bash
cp .env.example .env
# 編輯 .env 填入 API keys
```

### 3. 安裝 Rust 依賴（桌面應用）

```bash
# 安裝 Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# 編譯核心庫
cargo build --release
```

### 4. 安裝前端依賴

```bash
cd ui
npm install
```

## 使用方式

### CLI 模式

```bash
# 基本使用
reclip input.wav -o output.wav

# 多軌合併
reclip track1.wav track2.wav --mode merge -o output.wav

# 只分析不剪輯
reclip input.wav --analyze-only --export-report report.json

# 詳細輸出
reclip input.wav -o output.wav -v
```

### 桌面應用

```bash
# 開發模式
cd src-tauri
cargo tauri dev

# 編譯
cargo tauri build
```

## 專案結構

```
reclip/
├── src/                    # Python 模組
│   ├── preprocessor.py     # 音訊預處理
│   ├── transcriber.py      # WhisperX 轉錄
│   ├── analyzer.py         # Claude API 分析
│   ├── editor.py           # 音訊剪輯
│   ├── exporter.py         # 報告匯出
│   └── cli.py              # 命令列介面
│
├── crates/
│   └── reclip-core/        # Rust 核心庫
│       └── src/
│           ├── audio.rs    # 音訊處理
│           ├── editor.rs   # 剪輯器
│           ├── exporter.rs # 匯出器
│           ├── types.rs    # 類型定義
│           └── python.rs   # PyO3 綁定
│
├── src-tauri/              # Tauri 桌面應用
│   └── src/
│       └── main.rs
│
└── ui/                     # 前端 (Vue 3)
    └── src/
        └── App.vue
```

## 移除類型

1. **filler** - 語氣詞、填充詞 (嗯、啊、呃、um, uh)
2. **repeat** - 重複的詞語或片語
3. **restart** - 句子重新開始
4. **mouth_noise** - 唇齒音或雜音
5. **long_pause** - 超過 1.5 秒的停頓

## 匯出格式

- **JSON**: 完整的編輯報告與統計
- **EDL**: 可匯入 DaVinci Resolve、Premiere 等
- **CSV/TXT**: Audacity 標記格式

## API 費用估算

- Claude API: 約 $0.03-0.05/小時音訊
- WhisperX: 本地運行，免費

## 授權

MIT License
