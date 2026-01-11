# Reclip

AI-powered podcast auto-editor that intelligently removes filler words, repetitions, mistakes, and long pauses from audio recordings.

## Features

- **Speech Recognition (ASR)**: Local speech-to-text using WhisperKit with Metal acceleration
- **Speaker Diarization**: Identify different speakers using pyannote-rs
- **AI Analysis**: Analyze transcripts with Claude API or Ollama to identify removable content
- **Auto Editing**: AVFoundation-based editing with crossfade and zero-crossing
- **Multi-format Support**: MP3, M4A, AAC, FLAC, OGG, WAV

## Tech Stack

| Category | Technology |
|----------|------------|
| Backend | Rust + Tauri 2.0 |
| Frontend | React + TypeScript + Tailwind CSS |
| ASR | whisper-rs (Metal acceleration) |
| Diarization | pyannote-rs (ONNX Runtime) |
| LLM | Claude API / Ollama |
| Audio | symphonia + hound |

## Quick Start

### Prerequisites

- Rust 1.75+
- Node.js 20+
- macOS 14+ (for Metal acceleration)

### Development

```bash
# Install dependencies
cd ui && npm install

# Run development server
cargo tauri dev

# Build for production
cargo tauri build
```

## Project Structure

```
reclip/
├── crates/
│   ├── reclip-core/        # Audio processing & editing
│   ├── reclip-asr/         # WhisperKit ASR
│   ├── reclip-diarization/ # Speaker diarization
│   ├── reclip-waveform/    # Waveform generation
│   ├── reclip-models/      # Model download management
│   └── reclip-llm/         # Claude API / Ollama
├── src-tauri/              # Tauri backend
│   ├── src/
│   │   ├── commands/       # Tauri commands
│   │   └── state.rs        # App state
│   └── icons/              # App icons
├── ui/                     # React frontend
│   └── src/
│       ├── components/     # UI components
│       ├── hooks/          # Custom hooks
│       └── types/          # TypeScript types
└── logo/                   # Logo assets
```

## Removal Types

| Type | Description | Example |
|------|-------------|---------|
| **filler** | Filler words | um, uh, 嗯, 啊 |
| **repeat** | Repeated words/phrases | I I I want to say |
| **restart** | Sentence restarts | This... that feature is... |
| **mouthNoise** | Lip/teeth sounds | Smacking, breathing |
| **longPause** | Pauses > 1.5 seconds | [silence] |

## Export Formats

- **JSON**: Complete edit report with statistics
- **EDL**: Import to DaVinci Resolve, Premiere, etc.
- **CSV/TXT**: Audacity marker format

## API Cost Estimate

- **Claude API**: ~$0.03-0.05/hour of audio
- **Ollama**: Local, completely free
- **WhisperKit**: Local, completely free

## License

MIT
