//! Waveform data generator

use std::path::{Path, PathBuf};
use serde::{Deserialize, Serialize};
use tracing::{info, debug};
use directories::ProjectDirs;
use tokio::fs;

use crate::error::WaveformError;

/// Waveform resolution preset
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum WaveformResolution {
    /// Thumbnail (256 samples)
    Thumbnail,
    /// Standard (2048 samples)
    Standard,
    /// High (8192 samples)
    High,
    /// Full (sample per pixel)
    Full,
}

impl WaveformResolution {
    /// Get the target number of samples for this resolution
    pub fn sample_count(&self) -> usize {
        match self {
            WaveformResolution::Thumbnail => 256,
            WaveformResolution::Standard => 2048,
            WaveformResolution::High => 8192,
            WaveformResolution::Full => 0, // Dynamic based on audio length
        }
    }
}

/// Waveform data
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WaveformData {
    /// Peak values (normalized 0.0 - 1.0)
    pub peaks: Vec<f32>,
    /// Audio duration in seconds
    pub duration: f64,
    /// Resolution used
    pub resolution: WaveformResolution,
    /// Sample rate of source audio
    pub sample_rate: u32,
}

/// Waveform generator
pub struct WaveformGenerator {
    /// Cache directory
    cache_dir: Option<PathBuf>,
}

impl WaveformGenerator {
    /// Create a new WaveformGenerator
    pub fn new() -> Self {
        let cache_dir = ProjectDirs::from("com", "reclip", "Reclip")
            .map(|dirs| dirs.cache_dir().join("waveforms"));

        Self { cache_dir }
    }

    /// Create WaveformGenerator with custom cache directory
    pub fn with_cache_dir(cache_dir: PathBuf) -> Self {
        Self { cache_dir: Some(cache_dir) }
    }

    /// Disable caching
    pub fn without_cache() -> Self {
        Self { cache_dir: None }
    }

    /// Generate waveform data from an audio file
    pub async fn generate<F>(
        &self,
        audio_path: &str,
        resolution: WaveformResolution,
        use_cache: bool,
        progress_callback: F,
    ) -> Result<WaveformData, WaveformError>
    where
        F: Fn(f64) + Send + 'static,
    {
        if !Path::new(audio_path).exists() {
            return Err(WaveformError::FileNotFound(audio_path.to_string()));
        }

        // Try to load from cache
        if use_cache {
            if let Some(cached) = self.load_from_cache(audio_path, resolution).await? {
                info!("Loaded waveform from cache");
                return Ok(cached);
            }
        }

        info!("Generating waveform for: {}", audio_path);

        let path = audio_path.to_string();
        let callback = progress_callback;

        // Generate waveform
        let waveform = tokio::task::spawn_blocking(move || {
            generate_waveform_sync(&path, resolution, callback)
        })
        .await
        .map_err(|e| WaveformError::GenerationFailed(e.to_string()))??;

        // Save to cache
        if use_cache {
            if let Err(e) = self.save_to_cache(audio_path, &waveform).await {
                debug!("Failed to cache waveform: {}", e);
            }
        }

        Ok(waveform)
    }

    /// Generate thumbnail waveform (fast)
    pub async fn generate_thumbnail(&self, audio_path: &str) -> Result<WaveformData, WaveformError> {
        self.generate(audio_path, WaveformResolution::Thumbnail, true, |_| {}).await
    }

    /// Get cache path for an audio file
    fn cache_path(&self, audio_path: &str, resolution: WaveformResolution) -> Option<PathBuf> {
        self.cache_dir.as_ref().map(|dir| {
            let hash = compute_file_hash(audio_path);
            let res_str = match resolution {
                WaveformResolution::Thumbnail => "thumb",
                WaveformResolution::Standard => "std",
                WaveformResolution::High => "high",
                WaveformResolution::Full => "full",
            };
            dir.join(format!("{}_{}.json", hash, res_str))
        })
    }

    /// Load waveform from cache
    async fn load_from_cache(
        &self,
        audio_path: &str,
        resolution: WaveformResolution,
    ) -> Result<Option<WaveformData>, WaveformError> {
        let cache_path = match self.cache_path(audio_path, resolution) {
            Some(p) => p,
            None => return Ok(None),
        };

        if !cache_path.exists() {
            return Ok(None);
        }

        let data = fs::read_to_string(&cache_path).await?;
        let waveform: WaveformData = serde_json::from_str(&data)
            .map_err(|e| WaveformError::CacheError(e.to_string()))?;

        Ok(Some(waveform))
    }

    /// Save waveform to cache
    async fn save_to_cache(
        &self,
        audio_path: &str,
        waveform: &WaveformData,
    ) -> Result<(), WaveformError> {
        let cache_path = match self.cache_path(audio_path, waveform.resolution) {
            Some(p) => p,
            None => return Ok(()),
        };

        if let Some(parent) = cache_path.parent() {
            fs::create_dir_all(parent).await?;
        }

        let data = serde_json::to_string(waveform)
            .map_err(|e| WaveformError::CacheError(e.to_string()))?;

        fs::write(&cache_path, data).await?;
        Ok(())
    }

    /// Clear waveform cache
    pub async fn clear_cache(&self) -> Result<(), WaveformError> {
        if let Some(cache_dir) = &self.cache_dir {
            if cache_dir.exists() {
                fs::remove_dir_all(cache_dir).await?;
            }
        }
        Ok(())
    }
}

impl Default for WaveformGenerator {
    fn default() -> Self {
        Self::new()
    }
}

/// Generate waveform synchronously (called from blocking task)
fn generate_waveform_sync<F>(
    audio_path: &str,
    resolution: WaveformResolution,
    progress_callback: F,
) -> Result<WaveformData, WaveformError>
where
    F: Fn(f64),
{
    use std::path::Path;

    progress_callback(0.0);

    let path = Path::new(audio_path);
    let extension = path
        .extension()
        .and_then(|e| e.to_str())
        .map(|e| e.to_lowercase());

    // Load samples based on format
    let (mono_samples, sample_rate) = match extension.as_deref() {
        Some("wav") => load_wav_samples(audio_path)?,
        Some("mp3") | Some("m4a") | Some("aac") | Some("flac") | Some("ogg") => {
            load_symphonia_samples(audio_path)?
        }
        Some(ext) => return Err(WaveformError::InvalidFormat(format!("Unsupported format: {}", ext))),
        None => return Err(WaveformError::InvalidFormat("Unknown format".to_string())),
    };

    progress_callback(0.5);

    let total_samples = mono_samples.len();
    let duration = total_samples as f64 / sample_rate as f64;

    // Calculate target sample count
    let target_count = match resolution {
        WaveformResolution::Full => total_samples.min(32768),
        _ => resolution.sample_count(),
    };

    if target_count == 0 || total_samples == 0 {
        return Ok(WaveformData {
            peaks: vec![],
            duration,
            resolution,
            sample_rate,
        });
    }

    // Downsample to get peaks
    let samples_per_peak = (total_samples / target_count).max(1);
    let mut peaks = Vec::with_capacity(target_count);

    for i in 0..target_count {
        let start = i * samples_per_peak;
        let end = ((i + 1) * samples_per_peak).min(total_samples);

        if start >= total_samples {
            break;
        }

        // Find peak (max absolute value) in this chunk
        let peak = mono_samples[start..end]
            .iter()
            .map(|s| s.abs())
            .fold(0.0f32, |a, b| a.max(b));

        peaks.push(peak);

        if i % 100 == 0 {
            progress_callback(0.5 + 0.5 * (i as f64 / target_count as f64));
        }
    }

    progress_callback(1.0);

    Ok(WaveformData {
        peaks,
        duration,
        resolution,
        sample_rate,
    })
}

/// Load samples from WAV file using hound
fn load_wav_samples(audio_path: &str) -> Result<(Vec<f32>, u32), WaveformError> {
    use std::fs::File;
    use std::io::BufReader;

    let file = File::open(audio_path)
        .map_err(|e| WaveformError::FileNotFound(e.to_string()))?;

    let reader = hound::WavReader::new(BufReader::new(file))
        .map_err(|e| WaveformError::InvalidFormat(e.to_string()))?;

    let spec = reader.spec();
    let sample_rate = spec.sample_rate;
    let channels = spec.channels as usize;

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

    // Convert to mono
    let mono_samples: Vec<f32> = if channels == 2 {
        samples.chunks(2)
            .map(|chunk| (chunk[0] + chunk.get(1).unwrap_or(&0.0)) / 2.0)
            .collect()
    } else if channels > 2 {
        samples.chunks(channels)
            .map(|chunk| chunk.iter().sum::<f32>() / chunk.len() as f32)
            .collect()
    } else {
        samples
    };

    Ok((mono_samples, sample_rate))
}

/// Load samples from audio file using symphonia
fn load_symphonia_samples(audio_path: &str) -> Result<(Vec<f32>, u32), WaveformError> {
    use std::fs::File;
    use symphonia::core::audio::SampleBuffer;
    use symphonia::core::codecs::DecoderOptions;
    use symphonia::core::formats::FormatOptions;
    use symphonia::core::io::MediaSourceStream;
    use symphonia::core::meta::MetadataOptions;
    use symphonia::core::probe::Hint;

    let file = File::open(audio_path)
        .map_err(|e| WaveformError::FileNotFound(e.to_string()))?;

    let mss = MediaSourceStream::new(Box::new(file), Default::default());

    let mut hint = Hint::new();
    if let Some(ext) = std::path::Path::new(audio_path).extension().and_then(|e| e.to_str()) {
        hint.with_extension(ext);
    }

    let probed = symphonia::default::get_probe()
        .format(&hint, mss, &FormatOptions::default(), &MetadataOptions::default())
        .map_err(|e| WaveformError::InvalidFormat(format!("Probe failed: {}", e)))?;

    let mut format = probed.format;

    let track = format
        .tracks()
        .iter()
        .find(|t| t.codec_params.codec != symphonia::core::codecs::CODEC_TYPE_NULL)
        .ok_or_else(|| WaveformError::InvalidFormat("No audio track found".to_string()))?;

    let track_id = track.id;
    let codec_params = track.codec_params.clone();

    let sample_rate = codec_params
        .sample_rate
        .ok_or_else(|| WaveformError::InvalidFormat("No sample rate".to_string()))?;

    let channels = codec_params
        .channels
        .map(|c| c.count())
        .unwrap_or(2);

    let mut decoder = symphonia::default::get_codecs()
        .make(&codec_params, &DecoderOptions::default())
        .map_err(|e| WaveformError::InvalidFormat(format!("Decoder error: {}", e)))?;

    let mut all_samples: Vec<f32> = Vec::new();

    loop {
        let packet = match format.next_packet() {
            Ok(p) => p,
            Err(symphonia::core::errors::Error::IoError(ref e))
                if e.kind() == std::io::ErrorKind::UnexpectedEof =>
            {
                break;
            }
            Err(_) => continue,
        };

        if packet.track_id() != track_id {
            continue;
        }

        let decoded = match decoder.decode(&packet) {
            Ok(d) => d,
            Err(_) => continue,
        };

        let spec = *decoded.spec();
        let duration = decoded.capacity() as u64;

        let mut sample_buf = SampleBuffer::<f32>::new(duration, spec);
        sample_buf.copy_interleaved_ref(decoded);

        let samples = sample_buf.samples();

        // Convert to mono
        if channels == 1 {
            all_samples.extend_from_slice(samples);
        } else {
            for chunk in samples.chunks(channels) {
                let sum: f32 = chunk.iter().sum();
                all_samples.push(sum / channels as f32);
            }
        }
    }

    Ok((all_samples, sample_rate))
}

/// Compute a short hash for cache key
fn compute_file_hash(path: &str) -> String {
    use sha2::{Sha256, Digest};
    let mut hasher = Sha256::new();
    hasher.update(path.as_bytes());
    hex::encode(&hasher.finalize()[..8])
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_resolution_sample_count() {
        assert_eq!(WaveformResolution::Thumbnail.sample_count(), 256);
        assert_eq!(WaveformResolution::Standard.sample_count(), 2048);
    }
}
