//! Application state management

use reclip_asr::WhisperProvider;
use reclip_core::{audio::AudioProcessor, AudioInfo, types::AnalysisResult};
use reclip_diarization::DiarizationProvider;
use reclip_llm::{ClaudeProvider, OllamaProvider};
use reclip_models::ModelManager;
use reclip_waveform::WaveformGenerator;
use std::sync::Mutex as StdMutex;
use tokio::sync::Mutex;

use crate::commands::llm::LlmProviderType;

/// LLM provider state
pub struct LlmState {
    pub current_provider: Option<LlmProviderType>,
    pub claude_provider: Option<ClaudeProvider>,
    pub ollama_provider: Option<OllamaProvider>,
}

impl Default for LlmState {
    fn default() -> Self {
        Self {
            current_provider: None,
            claude_provider: None,
            ollama_provider: None,
        }
    }
}

/// Main application state
pub struct AppState {
    /// Audio processor (sync)
    pub processor: AudioProcessor,
    /// Current loaded audio info (sync)
    pub current_audio: StdMutex<Option<AudioInfo>>,
    /// Current analysis result (sync)
    pub current_analysis: StdMutex<Option<AnalysisResult>>,
    /// ASR provider (async)
    pub asr_provider: Mutex<WhisperProvider>,
    /// Diarization provider (async)
    pub diarization_provider: Mutex<DiarizationProvider>,
    /// Model manager (async)
    pub model_manager: Mutex<ModelManager>,
    /// Waveform generator (async)
    pub waveform_generator: Mutex<WaveformGenerator>,
    /// LLM state (async)
    pub llm_state: Mutex<LlmState>,
}

impl Default for AppState {
    fn default() -> Self {
        Self {
            processor: AudioProcessor::new(48000),
            current_audio: StdMutex::new(None),
            current_analysis: StdMutex::new(None),
            asr_provider: Mutex::new(WhisperProvider::new()),
            diarization_provider: Mutex::new(DiarizationProvider::new()),
            model_manager: Mutex::new(ModelManager::new().expect("Failed to create ModelManager")),
            waveform_generator: Mutex::new(WaveformGenerator::new()),
            llm_state: Mutex::new(LlmState::default()),
        }
    }
}
