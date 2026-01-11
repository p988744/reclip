//! Model download and cache manager

use std::path::PathBuf;
use directories::ProjectDirs;
use tokio::fs;
use tokio::io::AsyncWriteExt;
use futures::StreamExt;
use sha2::{Sha256, Digest};
use tracing::{info, debug, warn};
use serde::{Deserialize, Serialize};

use crate::error::ModelError;
use crate::registry::{ModelInfo, ModelType};

/// Download progress information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DownloadProgress {
    /// Model name being downloaded
    pub model_name: String,
    /// Bytes downloaded so far
    pub bytes_downloaded: u64,
    /// Total bytes to download
    pub total_bytes: u64,
    /// Progress fraction (0.0 - 1.0)
    pub fraction: f64,
}

/// Model download and cache manager
pub struct ModelManager {
    /// Cache directory path
    cache_dir: PathBuf,
    /// HTTP client
    client: reqwest::Client,
}

impl ModelManager {
    /// Create a new ModelManager
    pub fn new() -> Result<Self, ModelError> {
        let dirs = ProjectDirs::from("com", "reclip", "Reclip")
            .ok_or_else(|| ModelError::CacheDirectoryError(
                "Could not determine cache directory".to_string()
            ))?;

        let cache_dir = dirs.cache_dir().join("models");

        Ok(Self {
            cache_dir,
            client: reqwest::Client::builder()
                .user_agent("reclip/0.2.0")
                .build()
                .map_err(|e| ModelError::DownloadFailed(e.to_string()))?,
        })
    }

    /// Create ModelManager with custom cache directory
    pub fn with_cache_dir(cache_dir: PathBuf) -> Result<Self, ModelError> {
        Ok(Self {
            cache_dir,
            client: reqwest::Client::builder()
                .user_agent("reclip/0.2.0")
                .build()
                .map_err(|e| ModelError::DownloadFailed(e.to_string()))?,
        })
    }

    /// Get the cache directory path
    pub fn cache_directory(&self) -> &PathBuf {
        &self.cache_dir
    }

    /// Get the path where a model would be stored
    pub fn model_path(&self, model: &ModelInfo) -> PathBuf {
        self.cache_dir
            .join(model.model_type.subdirectory())
            .join(&model.filename)
    }

    /// Check if a model is downloaded
    pub async fn is_downloaded(&self, model: &ModelInfo) -> bool {
        let path = self.model_path(model);
        path.exists()
    }

    /// Check if a model is downloaded by ID
    pub async fn is_downloaded_by_id(&self, model_id: &str) -> bool {
        if let Some(model) = crate::registry::get_model(model_id) {
            self.is_downloaded(&model).await
        } else {
            false
        }
    }

    /// Get the size of a downloaded model
    pub async fn downloaded_size(&self, model: &ModelInfo) -> Option<u64> {
        let path = self.model_path(model);
        fs::metadata(&path).await.ok().map(|m| m.len())
    }

    /// Download a model with progress callback
    pub async fn download<F>(
        &self,
        model: &ModelInfo,
        progress_callback: F,
    ) -> Result<PathBuf, ModelError>
    where
        F: Fn(DownloadProgress) + Send + 'static,
    {
        let dest_path = self.model_path(model);

        // Check if already downloaded
        if dest_path.exists() {
            info!("Model {} already downloaded", model.name);
            return Ok(dest_path);
        }

        info!("Downloading model: {} from {}", model.name, model.url);

        // Create parent directory
        if let Some(parent) = dest_path.parent() {
            fs::create_dir_all(parent).await?;
        }

        // Start download
        let response = self.client
            .get(&model.url)
            .send()
            .await
            .map_err(|e| ModelError::DownloadFailed(e.to_string()))?;

        if !response.status().is_success() {
            return Err(ModelError::DownloadFailed(format!(
                "HTTP error: {}",
                response.status()
            )));
        }

        let total_size = response.content_length().unwrap_or(model.size_bytes);

        // Create temp file for download
        let temp_path = dest_path.with_extension("tmp");
        let mut file = fs::File::create(&temp_path).await?;

        let mut downloaded: u64 = 0;
        let mut stream = response.bytes_stream();

        while let Some(chunk_result) = stream.next().await {
            let chunk = chunk_result
                .map_err(|e| ModelError::DownloadFailed(e.to_string()))?;

            file.write_all(&chunk).await?;
            downloaded += chunk.len() as u64;

            progress_callback(DownloadProgress {
                model_name: model.name.clone(),
                bytes_downloaded: downloaded,
                total_bytes: total_size,
                fraction: downloaded as f64 / total_size as f64,
            });
        }

        file.flush().await?;
        drop(file);

        // Verify download if SHA256 is provided
        if !model.sha256.is_empty() {
            debug!("Verifying model checksum...");
            let actual_hash = self.compute_sha256(&temp_path).await?;
            if actual_hash != model.sha256 {
                fs::remove_file(&temp_path).await?;
                return Err(ModelError::VerificationFailed {
                    expected: model.sha256.clone(),
                    actual: actual_hash,
                });
            }
        }

        // Move temp file to final location
        fs::rename(&temp_path, &dest_path).await?;

        info!("Model {} downloaded successfully", model.name);
        Ok(dest_path)
    }

    /// Download a model by ID
    pub async fn download_by_id<F>(
        &self,
        model_id: &str,
        progress_callback: F,
    ) -> Result<PathBuf, ModelError>
    where
        F: Fn(DownloadProgress) + Send + 'static,
    {
        let model = crate::registry::get_model(model_id)
            .ok_or_else(|| ModelError::ModelNotFound(model_id.to_string()))?;

        self.download(&model, progress_callback).await
    }

    /// Delete a downloaded model
    pub async fn delete(&self, model: &ModelInfo) -> Result<(), ModelError> {
        let path = self.model_path(model);
        if path.exists() {
            fs::remove_file(&path).await?;
            info!("Model {} deleted", model.name);
        }
        Ok(())
    }

    /// Delete a model by ID
    pub async fn delete_by_id(&self, model_id: &str) -> Result<(), ModelError> {
        let model = crate::registry::get_model(model_id)
            .ok_or_else(|| ModelError::ModelNotFound(model_id.to_string()))?;

        self.delete(&model).await
    }

    /// Get list of downloaded models
    pub async fn list_downloaded(&self) -> Vec<ModelInfo> {
        let mut downloaded = Vec::new();

        for model in crate::registry::get_all_models() {
            if self.is_downloaded(&model).await {
                downloaded.push(model);
            }
        }

        downloaded
    }

    /// Compute SHA256 hash of a file
    async fn compute_sha256(&self, path: &PathBuf) -> Result<String, ModelError> {
        let data = fs::read(path).await?;
        let mut hasher = Sha256::new();
        hasher.update(&data);
        Ok(hex::encode(hasher.finalize()))
    }

    /// Get total size of all downloaded models
    pub async fn total_cache_size(&self) -> u64 {
        let mut total = 0u64;

        for model in crate::registry::get_all_models() {
            if let Some(size) = self.downloaded_size(&model).await {
                total += size;
            }
        }

        total
    }

    /// Clear all downloaded models
    pub async fn clear_cache(&self) -> Result<(), ModelError> {
        if self.cache_dir.exists() {
            fs::remove_dir_all(&self.cache_dir).await?;
            info!("Model cache cleared");
        }
        Ok(())
    }
}

impl Default for ModelManager {
    fn default() -> Self {
        Self::new().expect("Failed to create ModelManager")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_model_path() {
        let manager = ModelManager::with_cache_dir(PathBuf::from("/tmp/test"))
            .unwrap();

        let model = ModelInfo {
            id: "test".to_string(),
            name: "Test".to_string(),
            model_type: ModelType::Whisper,
            filename: "test.bin".to_string(),
            url: "http://example.com/test.bin".to_string(),
            size_bytes: 1000,
            sha256: String::new(),
            description: "Test model".to_string(),
        };

        let path = manager.model_path(&model);
        assert_eq!(path, PathBuf::from("/tmp/test/whisper/test.bin"));
    }
}
