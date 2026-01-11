//! Model registry with download information

use serde::{Deserialize, Serialize};
use std::sync::LazyLock;

/// Model type enumeration
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ModelType {
    /// Whisper ASR model
    Whisper,
    /// Pyannote segmentation model
    PyannoteSegmentation,
    /// Pyannote/wespeaker embedding model
    PyannoteEmbedding,
}

impl ModelType {
    /// Get the subdirectory name for this model type
    pub fn subdirectory(&self) -> &'static str {
        match self {
            ModelType::Whisper => "whisper",
            ModelType::PyannoteSegmentation => "pyannote",
            ModelType::PyannoteEmbedding => "pyannote",
        }
    }
}

/// Model information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ModelInfo {
    /// Model identifier
    pub id: String,
    /// Display name
    pub name: String,
    /// Model type
    pub model_type: ModelType,
    /// File name
    pub filename: String,
    /// Download URL
    pub url: String,
    /// File size in bytes
    pub size_bytes: u64,
    /// SHA256 hash for verification (empty if unknown)
    pub sha256: String,
    /// Description
    pub description: String,
}

impl ModelInfo {
    /// Get human-readable size string
    pub fn size_string(&self) -> String {
        const KB: u64 = 1024;
        const MB: u64 = KB * 1024;
        const GB: u64 = MB * 1024;

        if self.size_bytes >= GB {
            format!("{:.1} GB", self.size_bytes as f64 / GB as f64)
        } else if self.size_bytes >= MB {
            format!("{:.0} MB", self.size_bytes as f64 / MB as f64)
        } else if self.size_bytes >= KB {
            format!("{:.0} KB", self.size_bytes as f64 / KB as f64)
        } else {
            format!("{} bytes", self.size_bytes)
        }
    }
}

/// Available Whisper models
pub static WHISPER_MODELS: LazyLock<Vec<ModelInfo>> = LazyLock::new(|| {
    vec![
        ModelInfo {
            id: "whisper-tiny".to_string(),
            name: "Whisper Tiny".to_string(),
            model_type: ModelType::Whisper,
            filename: "ggml-tiny.bin".to_string(),
            url: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin".to_string(),
            size_bytes: 75_000_000,
            sha256: String::new(),
            description: "Fastest, lowest accuracy (~75MB)".to_string(),
        },
        ModelInfo {
            id: "whisper-base".to_string(),
            name: "Whisper Base".to_string(),
            model_type: ModelType::Whisper,
            filename: "ggml-base.bin".to_string(),
            url: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin".to_string(),
            size_bytes: 142_000_000,
            sha256: String::new(),
            description: "Fast, good accuracy (~140MB)".to_string(),
        },
        ModelInfo {
            id: "whisper-small".to_string(),
            name: "Whisper Small".to_string(),
            model_type: ModelType::Whisper,
            filename: "ggml-small.bin".to_string(),
            url: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin".to_string(),
            size_bytes: 466_000_000,
            sha256: String::new(),
            description: "Balanced speed/accuracy (~460MB)".to_string(),
        },
        ModelInfo {
            id: "whisper-medium".to_string(),
            name: "Whisper Medium".to_string(),
            model_type: ModelType::Whisper,
            filename: "ggml-medium.bin".to_string(),
            url: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin".to_string(),
            size_bytes: 1_500_000_000,
            sha256: String::new(),
            description: "High accuracy (~1.5GB)".to_string(),
        },
        ModelInfo {
            id: "whisper-large-v3".to_string(),
            name: "Whisper Large V3".to_string(),
            model_type: ModelType::Whisper,
            filename: "ggml-large-v3.bin".to_string(),
            url: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3.bin".to_string(),
            size_bytes: 3_000_000_000,
            sha256: String::new(),
            description: "Highest accuracy, slowest (~3GB)".to_string(),
        },
    ]
});

/// Available diarization models
pub static DIARIZATION_MODELS: LazyLock<Vec<ModelInfo>> = LazyLock::new(|| {
    vec![
        ModelInfo {
            id: "pyannote-segmentation".to_string(),
            name: "Pyannote Segmentation 3.0".to_string(),
            model_type: ModelType::PyannoteSegmentation,
            filename: "segmentation-3.0.onnx".to_string(),
            url: "https://huggingface.co/pyannote/segmentation-3.0/resolve/main/pytorch_model.onnx".to_string(),
            size_bytes: 17_000_000,
            sha256: String::new(),
            description: "Voice activity detection (~17MB)".to_string(),
        },
        ModelInfo {
            id: "wespeaker-embedding".to_string(),
            name: "WeSpeaker Embedding".to_string(),
            model_type: ModelType::PyannoteEmbedding,
            filename: "wespeaker-voxceleb-resnet34-LM.onnx".to_string(),
            url: "https://huggingface.co/pyannote/wespeaker-voxceleb-resnet34-LM/resolve/main/pytorch_model.onnx".to_string(),
            size_bytes: 90_000_000,
            sha256: String::new(),
            description: "Speaker embedding extraction (~90MB)".to_string(),
        },
    ]
});

/// Get model info by ID
pub fn get_model(id: &str) -> Option<ModelInfo> {
    WHISPER_MODELS.iter()
        .chain(DIARIZATION_MODELS.iter())
        .find(|m| m.id == id)
        .cloned()
}

/// Get all models of a specific type
pub fn get_models_by_type(model_type: ModelType) -> Vec<ModelInfo> {
    WHISPER_MODELS.iter()
        .chain(DIARIZATION_MODELS.iter())
        .filter(|m| m.model_type == model_type)
        .cloned()
        .collect()
}

/// Get all available models
pub fn get_all_models() -> Vec<ModelInfo> {
    WHISPER_MODELS.iter()
        .chain(DIARIZATION_MODELS.iter())
        .cloned()
        .collect()
}
