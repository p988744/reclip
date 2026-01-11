//! Whisper ASR provider using whisper-rs

use std::path::Path;
use std::sync::Arc;
use tokio::sync::Mutex;
use serde::{Deserialize, Serialize};
use tracing::{info, debug, warn};
use whisper_rs::{WhisperContext, WhisperContextParameters, FullParams, SamplingStrategy};

use reclip_core::{TranscriptResult, Segment, WordSegment};
use crate::error::AsrError;
use crate::languages::Language;

/// Transcription options
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TranscriptionOptions {
    /// Language code (e.g., "zh", "en")
    pub language: String,
    /// Include word-level timestamps
    pub word_timestamps: bool,
    /// Number of threads (0 = auto)
    pub threads: u32,
}

impl Default for TranscriptionOptions {
    fn default() -> Self {
        Self {
            language: "zh".to_string(),
            word_timestamps: true,
            threads: 0,
        }
    }
}

/// Transcription progress information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TranscribeProgress {
    /// Progress fraction (0.0 - 1.0)
    pub fraction: f64,
    /// Processed time in seconds
    pub processed_time: f64,
    /// Total audio duration in seconds
    pub total_time: f64,
    /// Current transcribed text (live)
    pub current_text: String,
}

/// Whisper ASR provider
pub struct WhisperProvider {
    context: Option<Arc<Mutex<WhisperContext>>>,
    model_path: Option<String>,
}

impl WhisperProvider {
    /// Create a new WhisperProvider
    pub fn new() -> Self {
        Self {
            context: None,
            model_path: None,
        }
    }

    /// Check if model is loaded
    pub fn is_loaded(&self) -> bool {
        self.context.is_some()
    }

    /// Get loaded model path
    pub fn model_path(&self) -> Option<&str> {
        self.model_path.as_deref()
    }

    /// Load a Whisper model from file
    pub async fn load_model<F>(
        &mut self,
        model_path: &str,
        progress_callback: F,
    ) -> Result<(), AsrError>
    where
        F: Fn(f64) + Send + 'static,
    {
        info!("Loading Whisper model from: {}", model_path);

        if !Path::new(model_path).exists() {
            return Err(AsrError::FileNotFound(model_path.to_string()));
        }

        // Report initial progress
        progress_callback(0.0);

        // Load model (this is a blocking operation)
        let path = model_path.to_string();
        let context = tokio::task::spawn_blocking(move || {
            let params = WhisperContextParameters::default();
            WhisperContext::new_with_params(&path, params)
        })
        .await
        .map_err(|e| AsrError::ModelLoadFailed(e.to_string()))?
        .map_err(|e| AsrError::ModelLoadFailed(e.to_string()))?;

        progress_callback(1.0);

        self.context = Some(Arc::new(Mutex::new(context)));
        self.model_path = Some(model_path.to_string());

        info!("Whisper model loaded successfully");
        Ok(())
    }

    /// Unload the current model
    pub fn unload(&mut self) {
        self.context = None;
        self.model_path = None;
        info!("Whisper model unloaded");
    }

    /// Transcribe an audio file
    pub async fn transcribe<F>(
        &self,
        audio_path: &str,
        options: TranscriptionOptions,
        progress_callback: F,
    ) -> Result<TranscriptResult, AsrError>
    where
        F: Fn(TranscribeProgress) + Send + Clone + 'static,
    {
        let context = self.context.as_ref()
            .ok_or(AsrError::ModelNotLoaded)?;

        if !Language::is_supported(&options.language) {
            return Err(AsrError::UnsupportedLanguage(options.language.clone()));
        }

        if !Path::new(audio_path).exists() {
            return Err(AsrError::FileNotFound(audio_path.to_string()));
        }

        info!("Starting transcription: {}", audio_path);
        debug!("Options: {:?}", options);

        // Load audio file
        let audio_path = audio_path.to_string();
        let audio_data = tokio::task::spawn_blocking(move || {
            load_audio_file(&audio_path)
        })
        .await
        .map_err(|e| AsrError::TranscriptionFailed(e.to_string()))?
        .map_err(|e| AsrError::TranscriptionFailed(e.to_string()))?;

        let total_duration = audio_data.len() as f64 / 16000.0; // 16kHz sample rate

        // Map language code
        let whisper_lang = Language::to_whisper_code(&options.language);

        // Transcribe
        let context = context.clone();
        let callback = progress_callback.clone();

        let result = tokio::task::spawn_blocking(move || {
            let ctx = context.blocking_lock();

            let mut params = FullParams::new(SamplingStrategy::Greedy { best_of: 1 });
            params.set_language(Some(whisper_lang));
            params.set_token_timestamps(options.word_timestamps);
            params.set_print_progress(false);
            params.set_print_realtime(false);

            if options.threads > 0 {
                params.set_n_threads(options.threads as i32);
            }

            // Create state
            let mut state = ctx.create_state()
                .map_err(|e| AsrError::TranscriptionFailed(e.to_string()))?;

            // Run transcription
            state.full(params, &audio_data)
                .map_err(|e| AsrError::TranscriptionFailed(e.to_string()))?;

            // Collect results
            let num_segments = state.full_n_segments()
                .map_err(|e| AsrError::TranscriptionFailed(e.to_string()))?;

            let mut segments = Vec::new();
            let mut accumulated_text = String::new();

            for i in 0..num_segments {
                let text = state.full_get_segment_text(i)
                    .map_err(|e| AsrError::TranscriptionFailed(e.to_string()))?;

                let start = state.full_get_segment_t0(i)
                    .map_err(|e| AsrError::TranscriptionFailed(e.to_string()))? as f64 / 100.0;

                let end = state.full_get_segment_t1(i)
                    .map_err(|e| AsrError::TranscriptionFailed(e.to_string()))? as f64 / 100.0;

                // Get word-level timestamps if enabled
                let words = if options.word_timestamps {
                    let num_tokens = state.full_n_tokens(i)
                        .map_err(|e| AsrError::TranscriptionFailed(e.to_string()))?;

                    let mut word_segments = Vec::new();
                    for j in 0..num_tokens {
                        let token_text = state.full_get_token_text(i, j)
                            .map_err(|e| AsrError::TranscriptionFailed(e.to_string()))?;

                        let token_data = state.full_get_token_data(i, j)
                            .map_err(|e| AsrError::TranscriptionFailed(e.to_string()))?;

                        // Skip special tokens
                        if token_text.starts_with('<') && token_text.ends_with('>') {
                            continue;
                        }

                        word_segments.push(WordSegment {
                            word: token_text.trim().to_string(),
                            start: token_data.t0 as f64 / 100.0,
                            end: token_data.t1 as f64 / 100.0,
                            confidence: token_data.p as f64,
                            speaker: None,
                        });
                    }
                    word_segments
                } else {
                    Vec::new()
                };

                // Clean text (remove special tokens)
                let clean_text = clean_whisper_text(&text);
                if !clean_text.is_empty() {
                    accumulated_text.push_str(&clean_text);
                    accumulated_text.push(' ');

                    segments.push(Segment {
                        text: clean_text,
                        start,
                        end,
                        speaker: None,
                        words,
                    });

                    // Report progress
                    let progress = (i as f64 + 1.0) / num_segments as f64;
                    callback(TranscribeProgress {
                        fraction: progress.min(0.99),
                        processed_time: end,
                        total_time: total_duration,
                        current_text: accumulated_text.clone(),
                    });
                }
            }

            Ok::<_, AsrError>(TranscriptResult {
                segments,
                language: options.language,
                duration: total_duration,
            })
        })
        .await
        .map_err(|e| AsrError::TranscriptionFailed(e.to_string()))??;

        // Report completion
        progress_callback(TranscribeProgress {
            fraction: 1.0,
            processed_time: total_duration,
            total_time: total_duration,
            current_text: String::new(),
        });

        info!("Transcription completed: {} segments", result.segments.len());
        Ok(result)
    }
}

impl Default for WhisperProvider {
    fn default() -> Self {
        Self::new()
    }
}

/// Load audio file and convert to 16kHz mono f32 samples
fn load_audio_file(path: &str) -> Result<Vec<f32>, String> {
    use std::fs::File;
    use std::io::BufReader;

    // Try to load as WAV first
    if path.to_lowercase().ends_with(".wav") {
        let file = File::open(path).map_err(|e| e.to_string())?;
        let reader = hound::WavReader::new(BufReader::new(file))
            .map_err(|e| e.to_string())?;

        let spec = reader.spec();
        let samples: Vec<f32> = match spec.sample_format {
            hound::SampleFormat::Float => {
                reader.into_samples::<f32>()
                    .filter_map(|s| s.ok())
                    .collect()
            }
            hound::SampleFormat::Int => {
                let max_val = (1 << (spec.bits_per_sample - 1)) as f32;
                reader.into_samples::<i32>()
                    .filter_map(|s| s.ok())
                    .map(|s| s as f32 / max_val)
                    .collect()
            }
        };

        // Convert to mono if stereo
        let mono_samples = if spec.channels == 2 {
            samples.chunks(2)
                .map(|chunk| (chunk[0] + chunk.get(1).unwrap_or(&0.0)) / 2.0)
                .collect()
        } else {
            samples
        };

        // Resample to 16kHz if needed
        if spec.sample_rate != 16000 {
            // Simple linear interpolation resampling
            let ratio = 16000.0 / spec.sample_rate as f64;
            let new_len = (mono_samples.len() as f64 * ratio) as usize;
            let mut resampled = Vec::with_capacity(new_len);

            for i in 0..new_len {
                let src_idx = i as f64 / ratio;
                let src_idx_floor = src_idx.floor() as usize;
                let frac = src_idx - src_idx_floor as f64;

                let s0 = mono_samples.get(src_idx_floor).unwrap_or(&0.0);
                let s1 = mono_samples.get(src_idx_floor + 1).unwrap_or(s0);

                resampled.push(s0 + (s1 - s0) * frac as f32);
            }

            Ok(resampled)
        } else {
            Ok(mono_samples)
        }
    } else {
        // For other formats, use symphonia
        Err("Non-WAV formats require additional implementation".to_string())
    }
}

/// Clean Whisper output text by removing special tokens
fn clean_whisper_text(text: &str) -> String {
    // Remove <|...|> style tokens
    let re = regex::Regex::new(r"<\|[^|]+\|>").unwrap();
    re.replace_all(text, "").trim().to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_clean_whisper_text() {
        assert_eq!(clean_whisper_text("<|startoftranscript|>Hello"), "Hello");
        assert_eq!(clean_whisper_text("Hello<|endoftext|>"), "Hello");
        assert_eq!(clean_whisper_text("<|zh|>你好<|endoftext|>"), "你好");
    }

    #[test]
    fn test_language_mapping() {
        assert_eq!(Language::to_whisper_code("zh"), "zh");
        assert_eq!(Language::to_whisper_code("zh-TW"), "zh");
        assert_eq!(Language::to_whisper_code("yue"), "yue");
        assert_eq!(Language::to_whisper_code("en"), "en");
    }
}
