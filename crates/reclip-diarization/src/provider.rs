//! Speaker diarization provider using pyannote-rs

use std::path::Path;
use serde::{Deserialize, Serialize};
use tracing::{info, debug};

use crate::error::DiarizationError;

/// Speaker segment from diarization
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SpeakerSegment {
    /// Start time in seconds
    pub start: f64,
    /// End time in seconds
    pub end: f64,
    /// Speaker ID (e.g., "Speaker1", "Speaker2")
    pub speaker_id: String,
    /// Confidence score (0.0 - 1.0)
    pub confidence: f64,
}

impl SpeakerSegment {
    /// Get the duration of this segment
    pub fn duration(&self) -> f64 {
        self.end - self.start
    }
}

/// Diarization result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DiarizationResult {
    /// Speaker segments
    pub segments: Vec<SpeakerSegment>,
    /// Number of unique speakers detected
    pub num_speakers: usize,
    /// Total audio duration
    pub duration: f64,
}

/// Diarization options
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DiarizationOptions {
    /// Minimum number of speakers (None = auto-detect)
    pub min_speakers: Option<u32>,
    /// Maximum number of speakers (None = auto-detect)
    pub max_speakers: Option<u32>,
}

impl Default for DiarizationOptions {
    fn default() -> Self {
        Self {
            min_speakers: None,
            max_speakers: None,
        }
    }
}

/// Diarization progress information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DiarizationProgress {
    /// Progress fraction (0.0 - 1.0)
    pub fraction: f64,
    /// Current stage description
    pub stage: String,
}

/// Speaker diarization provider using pyannote-rs
pub struct DiarizationProvider {
    /// Path to segmentation model (ONNX)
    segmentation_model_path: Option<String>,
    /// Path to embedding model (ONNX)
    embedding_model_path: Option<String>,
    /// Whether models are loaded
    is_loaded: bool,
}

impl DiarizationProvider {
    /// Create a new DiarizationProvider
    pub fn new() -> Self {
        Self {
            segmentation_model_path: None,
            embedding_model_path: None,
            is_loaded: false,
        }
    }

    /// Check if models are loaded
    pub fn is_loaded(&self) -> bool {
        self.is_loaded
    }

    /// Load diarization models
    ///
    /// # Arguments
    /// * `segmentation_model_path` - Path to segmentation-3.0.onnx
    /// * `embedding_model_path` - Path to wespeaker-voxceleb-resnet34-LM.onnx
    pub async fn load_models<F>(
        &mut self,
        segmentation_model_path: &str,
        embedding_model_path: &str,
        progress_callback: F,
    ) -> Result<(), DiarizationError>
    where
        F: Fn(DiarizationProgress) + Send + 'static,
    {
        info!("Loading diarization models...");

        // Check if files exist
        if !Path::new(segmentation_model_path).exists() {
            return Err(DiarizationError::FileNotFound(
                segmentation_model_path.to_string(),
            ));
        }

        if !Path::new(embedding_model_path).exists() {
            return Err(DiarizationError::FileNotFound(
                embedding_model_path.to_string(),
            ));
        }

        progress_callback(DiarizationProgress {
            fraction: 0.0,
            stage: "Loading segmentation model...".to_string(),
        });

        // Store paths (actual loading happens during diarization)
        self.segmentation_model_path = Some(segmentation_model_path.to_string());

        progress_callback(DiarizationProgress {
            fraction: 0.5,
            stage: "Loading embedding model...".to_string(),
        });

        self.embedding_model_path = Some(embedding_model_path.to_string());

        progress_callback(DiarizationProgress {
            fraction: 1.0,
            stage: "Models loaded".to_string(),
        });

        self.is_loaded = true;
        info!("Diarization models loaded successfully");

        Ok(())
    }

    /// Unload models
    pub fn unload(&mut self) {
        self.segmentation_model_path = None;
        self.embedding_model_path = None;
        self.is_loaded = false;
        info!("Diarization models unloaded");
    }

    /// Perform speaker diarization on an audio file
    pub async fn diarize<F>(
        &self,
        audio_path: &str,
        options: DiarizationOptions,
        progress_callback: F,
    ) -> Result<DiarizationResult, DiarizationError>
    where
        F: Fn(DiarizationProgress) + Send + Clone + 'static,
    {
        if !self.is_loaded {
            return Err(DiarizationError::ModelNotLoaded);
        }

        if !Path::new(audio_path).exists() {
            return Err(DiarizationError::FileNotFound(audio_path.to_string()));
        }

        let segmentation_path = self.segmentation_model_path.clone()
            .ok_or(DiarizationError::ModelNotLoaded)?;
        let embedding_path = self.embedding_model_path.clone()
            .ok_or(DiarizationError::ModelNotLoaded)?;

        info!("Starting diarization: {}", audio_path);
        debug!("Options: {:?}", options);

        progress_callback(DiarizationProgress {
            fraction: 0.0,
            stage: "Initializing...".to_string(),
        });

        // Use pyannote-rs for diarization
        let audio_path = audio_path.to_string();
        let callback = progress_callback.clone();

        let result = tokio::task::spawn_blocking(move || {
            use pyannote_rs::{get_segments, read_wav, EmbeddingExtractor};

            callback(DiarizationProgress {
                fraction: 0.1,
                stage: "Loading audio file...".to_string(),
            });

            // Read audio file
            let (samples, sample_rate) = read_wav(&audio_path)
                .map_err(|e| DiarizationError::DiarizationFailed(format!("Failed to read audio: {}", e)))?;

            callback(DiarizationProgress {
                fraction: 0.2,
                stage: "Running voice activity detection...".to_string(),
            });

            // Get voice activity segments using segmentation model
            let segments_iter = get_segments(&samples, sample_rate, &segmentation_path)
                .map_err(|e| DiarizationError::ModelLoadFailed(format!("Failed to load segmentation model: {}", e)))?;

            // Collect segments
            let mut vad_segments = Vec::new();
            for segment_result in segments_iter {
                match segment_result {
                    Ok(segment) => vad_segments.push(segment),
                    Err(e) => debug!("Segment processing error: {}", e),
                }
            }

            callback(DiarizationProgress {
                fraction: 0.4,
                stage: "Extracting speaker embeddings...".to_string(),
            });

            // Initialize embedding extractor
            let mut extractor = EmbeddingExtractor::new(&embedding_path)
                .map_err(|e| DiarizationError::ModelLoadFailed(format!("Failed to load embedding model: {}", e)))?;

            callback(DiarizationProgress {
                fraction: 0.6,
                stage: "Clustering speakers...".to_string(),
            });

            // Extract embeddings and cluster speakers
            let mut speaker_segments = Vec::new();
            let mut speaker_embeddings: Vec<(String, Vec<f32>)> = Vec::new();
            let total_segments = vad_segments.len();

            for (idx, segment) in vad_segments.iter().enumerate() {
                // Extract embedding for this segment's samples
                let embedding: Vec<f32> = extractor.compute(&segment.samples)
                    .map_err(|e| DiarizationError::DiarizationFailed(format!("Failed to compute embedding: {}", e)))?
                    .collect();

                // Find closest speaker or create new one
                let speaker_id = find_or_create_speaker(
                    &embedding,
                    &mut speaker_embeddings,
                    options.max_speakers,
                );

                speaker_segments.push(SpeakerSegment {
                    start: segment.start,
                    end: segment.end,
                    speaker_id,
                    confidence: 0.9, // pyannote-rs doesn't provide confidence
                });

                // Update progress
                if idx % 10 == 0 {
                    let progress = 0.6 + 0.3 * (idx as f64 / total_segments as f64);
                    callback(DiarizationProgress {
                        fraction: progress,
                        stage: format!("Processing segment {}/{}...", idx + 1, total_segments),
                    });
                }
            }

            callback(DiarizationProgress {
                fraction: 0.9,
                stage: "Finalizing...".to_string(),
            });

            // Calculate total duration
            let duration = speaker_segments.iter()
                .map(|s| s.end)
                .fold(0.0f64, |a, b| a.max(b));

            let num_speakers = speaker_embeddings.len();

            callback(DiarizationProgress {
                fraction: 1.0,
                stage: "Complete".to_string(),
            });

            Ok::<_, DiarizationError>(DiarizationResult {
                segments: speaker_segments,
                num_speakers,
                duration,
            })
        })
        .await
        .map_err(|e| DiarizationError::DiarizationFailed(e.to_string()))??;

        info!("Diarization completed: {} speakers, {} segments",
              result.num_speakers, result.segments.len());

        Ok(result)
    }
}

impl Default for DiarizationProvider {
    fn default() -> Self {
        Self::new()
    }
}

/// Find the closest existing speaker or create a new one
fn find_or_create_speaker(
    embedding: &[f32],
    speaker_embeddings: &mut Vec<(String, Vec<f32>)>,
    max_speakers: Option<u32>,
) -> String {
    const SIMILARITY_THRESHOLD: f32 = 0.6;

    // Calculate cosine similarity with existing speakers
    let mut best_match: Option<(usize, f32)> = None;

    for (idx, (_, existing_embedding)) in speaker_embeddings.iter().enumerate() {
        let similarity = cosine_similarity(embedding, existing_embedding);
        if similarity > SIMILARITY_THRESHOLD {
            match &best_match {
                Some((_, best_sim)) if similarity > *best_sim => {
                    best_match = Some((idx, similarity));
                }
                None => {
                    best_match = Some((idx, similarity));
                }
                _ => {}
            }
        }
    }

    if let Some((idx, _)) = best_match {
        // Return existing speaker
        speaker_embeddings[idx].0.clone()
    } else {
        // Check max speakers limit
        if let Some(max) = max_speakers {
            if speaker_embeddings.len() >= max as usize {
                // Assign to closest speaker even if below threshold
                if let Some((idx, _)) = speaker_embeddings
                    .iter()
                    .enumerate()
                    .map(|(i, (_, e))| (i, cosine_similarity(embedding, e)))
                    .max_by(|a, b| a.1.partial_cmp(&b.1).unwrap())
                {
                    return speaker_embeddings[idx].0.clone();
                }
            }
        }

        // Create new speaker
        let speaker_id = format!("Speaker{}", speaker_embeddings.len() + 1);
        speaker_embeddings.push((speaker_id.clone(), embedding.to_vec()));
        speaker_id
    }
}

/// Calculate cosine similarity between two vectors
fn cosine_similarity(a: &[f32], b: &[f32]) -> f32 {
    let dot: f32 = a.iter().zip(b.iter()).map(|(x, y)| x * y).sum();
    let norm_a: f32 = a.iter().map(|x| x * x).sum::<f32>().sqrt();
    let norm_b: f32 = b.iter().map(|x| x * x).sum::<f32>().sqrt();

    if norm_a == 0.0 || norm_b == 0.0 {
        0.0
    } else {
        dot / (norm_a * norm_b)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_cosine_similarity() {
        let a = vec![1.0, 0.0, 0.0];
        let b = vec![1.0, 0.0, 0.0];
        assert!((cosine_similarity(&a, &b) - 1.0).abs() < 0.001);

        let c = vec![0.0, 1.0, 0.0];
        assert!((cosine_similarity(&a, &c)).abs() < 0.001);
    }

    #[test]
    fn test_speaker_segment_duration() {
        let segment = SpeakerSegment {
            start: 1.0,
            end: 3.5,
            speaker_id: "Speaker1".to_string(),
            confidence: 0.9,
        };
        assert!((segment.duration() - 2.5).abs() < 0.001);
    }
}
