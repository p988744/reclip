//! 音訊處理模組

use std::fs::File;
use std::path::Path;

use hound::{WavReader, WavSpec, WavWriter};
use symphonia::core::audio::SampleBuffer;
use symphonia::core::codecs::DecoderOptions;
use symphonia::core::formats::FormatOptions;
use symphonia::core::io::MediaSourceStream;
use symphonia::core::meta::MetadataOptions;
use symphonia::core::probe::Hint;
use thiserror::Error;

use crate::AudioInfo;

/// 音訊處理錯誤
#[derive(Error, Debug)]
pub enum AudioError {
    #[error("檔案不存在: {0}")]
    FileNotFound(String),

    #[error("不支援的格式: {0}")]
    UnsupportedFormat(String),

    #[error("IO 錯誤: {0}")]
    Io(#[from] std::io::Error),

    #[error("WAV 處理錯誤: {0}")]
    Hound(#[from] hound::Error),

    #[error("重取樣錯誤: {0}")]
    Resample(String),

    #[error("解碼錯誤: {0}")]
    Decode(String),
}

/// 音訊樣本資料
#[derive(Debug, Clone)]
pub struct AudioData {
    /// 樣本資料 (mono, f32)
    pub samples: Vec<f32>,
    /// 取樣率
    pub sample_rate: u32,
}

impl AudioData {
    /// 取得時長（秒）
    pub fn duration(&self) -> f64 {
        self.samples.len() as f64 / self.sample_rate as f64
    }

    /// 取得時間點的樣本索引
    pub fn time_to_sample(&self, time_sec: f64) -> usize {
        (time_sec * self.sample_rate as f64) as usize
    }

    /// 取得樣本索引的時間點
    pub fn sample_to_time(&self, sample: usize) -> f64 {
        sample as f64 / self.sample_rate as f64
    }
}

/// 音訊處理器
pub struct AudioProcessor {
    /// 目標取樣率
    target_sample_rate: u32,
}

impl AudioProcessor {
    /// 建立新的音訊處理器
    pub fn new(target_sample_rate: u32) -> Self {
        Self { target_sample_rate }
    }

    /// 取得音訊資訊
    pub fn get_info<P: AsRef<Path>>(&self, path: P) -> Result<AudioInfo, AudioError> {
        let path = path.as_ref();
        if !path.exists() {
            return Err(AudioError::FileNotFound(path.display().to_string()));
        }

        let extension = path
            .extension()
            .and_then(|e| e.to_str())
            .map(|e| e.to_lowercase());

        // Use hound for WAV files (faster)
        if extension.as_deref() == Some("wav") {
            let reader = WavReader::open(path)?;
            let spec = reader.spec();
            let duration = reader.duration() as f64 / spec.sample_rate as f64;

            return Ok(AudioInfo {
                path: path.display().to_string(),
                duration,
                sample_rate: spec.sample_rate,
                channels: spec.channels,
                bits_per_sample: spec.bits_per_sample,
            });
        }

        // Use symphonia for other formats
        self.get_info_symphonia(path)
    }

    /// 使用 symphonia 取得音訊資訊
    fn get_info_symphonia<P: AsRef<Path>>(&self, path: P) -> Result<AudioInfo, AudioError> {
        let path = path.as_ref();
        let file = File::open(path)?;
        let mss = MediaSourceStream::new(Box::new(file), Default::default());

        let mut hint = Hint::new();
        if let Some(ext) = path.extension().and_then(|e| e.to_str()) {
            hint.with_extension(ext);
        }

        let probed = symphonia::default::get_probe()
            .format(&hint, mss, &FormatOptions::default(), &MetadataOptions::default())
            .map_err(|e| AudioError::Decode(format!("無法探測格式: {}", e)))?;

        let format = probed.format;
        let track = format
            .tracks()
            .iter()
            .find(|t| t.codec_params.codec != symphonia::core::codecs::CODEC_TYPE_NULL)
            .ok_or_else(|| AudioError::Decode("找不到音訊軌道".to_string()))?;

        let codec_params = &track.codec_params;

        let sample_rate = codec_params
            .sample_rate
            .ok_or_else(|| AudioError::Decode("無法取得取樣率".to_string()))?;

        let channels = codec_params
            .channels
            .map(|c| c.count() as u16)
            .unwrap_or(2);

        let bits_per_sample = codec_params
            .bits_per_sample
            .unwrap_or(16) as u16;

        // Calculate duration from time base and n_frames
        let duration = if let Some(n_frames) = codec_params.n_frames {
            n_frames as f64 / sample_rate as f64
        } else {
            0.0
        };

        Ok(AudioInfo {
            path: path.display().to_string(),
            duration,
            sample_rate,
            channels,
            bits_per_sample,
        })
    }

    /// 載入音訊檔案
    pub fn load<P: AsRef<Path>>(&self, path: P) -> Result<AudioData, AudioError> {
        let path = path.as_ref();
        if !path.exists() {
            return Err(AudioError::FileNotFound(path.display().to_string()));
        }

        let extension = path
            .extension()
            .and_then(|e| e.to_str())
            .map(|e| e.to_lowercase());

        match extension.as_deref() {
            Some("wav") => self.load_wav(path),
            Some("mp3") | Some("m4a") | Some("aac") | Some("flac") | Some("ogg") => {
                self.load_symphonia(path)
            }
            Some(ext) => Err(AudioError::UnsupportedFormat(ext.to_string())),
            None => Err(AudioError::UnsupportedFormat("unknown".to_string())),
        }
    }

    /// 使用 symphonia 載入音訊檔案
    fn load_symphonia<P: AsRef<Path>>(&self, path: P) -> Result<AudioData, AudioError> {
        let path = path.as_ref();
        let file = File::open(path)?;
        let mss = MediaSourceStream::new(Box::new(file), Default::default());

        let mut hint = Hint::new();
        if let Some(ext) = path.extension().and_then(|e| e.to_str()) {
            hint.with_extension(ext);
        }

        let probed = symphonia::default::get_probe()
            .format(&hint, mss, &FormatOptions::default(), &MetadataOptions::default())
            .map_err(|e| AudioError::Decode(format!("無法探測格式: {}", e)))?;

        let mut format = probed.format;

        let track = format
            .tracks()
            .iter()
            .find(|t| t.codec_params.codec != symphonia::core::codecs::CODEC_TYPE_NULL)
            .ok_or_else(|| AudioError::Decode("找不到音訊軌道".to_string()))?;

        let track_id = track.id;
        let codec_params = track.codec_params.clone();

        let sample_rate = codec_params
            .sample_rate
            .ok_or_else(|| AudioError::Decode("無法取得取樣率".to_string()))?;

        let channels = codec_params
            .channels
            .map(|c| c.count())
            .unwrap_or(2);

        let mut decoder = symphonia::default::get_codecs()
            .make(&codec_params, &DecoderOptions::default())
            .map_err(|e| AudioError::Decode(format!("無法建立解碼器: {}", e)))?;

        let mut all_samples: Vec<f32> = Vec::new();

        loop {
            let packet = match format.next_packet() {
                Ok(p) => p,
                Err(symphonia::core::errors::Error::IoError(ref e))
                    if e.kind() == std::io::ErrorKind::UnexpectedEof =>
                {
                    break;
                }
                Err(e) => {
                    tracing::warn!("解碼警告: {}", e);
                    continue;
                }
            };

            if packet.track_id() != track_id {
                continue;
            }

            let decoded = match decoder.decode(&packet) {
                Ok(d) => d,
                Err(e) => {
                    tracing::warn!("解碼封包錯誤: {}", e);
                    continue;
                }
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

        // Resample if needed
        let final_samples = if sample_rate != self.target_sample_rate {
            self.resample(&all_samples, sample_rate, self.target_sample_rate)?
        } else {
            all_samples
        };

        Ok(AudioData {
            samples: final_samples,
            sample_rate: self.target_sample_rate,
        })
    }

    /// 載入 WAV 檔案
    fn load_wav<P: AsRef<Path>>(&self, path: P) -> Result<AudioData, AudioError> {
        let mut reader = WavReader::open(path)?;
        let spec = reader.spec();

        // 讀取樣本並轉換為 f32 mono
        let samples: Vec<f32> = match spec.sample_format {
            hound::SampleFormat::Int => {
                let max_val = (1 << (spec.bits_per_sample - 1)) as f32;
                reader
                    .samples::<i32>()
                    .map(|s| s.map(|v| v as f32 / max_val))
                    .collect::<Result<Vec<_>, _>>()?
            }
            hound::SampleFormat::Float => reader.samples::<f32>().collect::<Result<Vec<_>, _>>()?,
        };

        // 轉換為 mono（如果是 stereo）
        let mono_samples = if spec.channels == 2 {
            samples
                .chunks(2)
                .map(|chunk| (chunk[0] + chunk[1]) / 2.0)
                .collect()
        } else if spec.channels == 1 {
            samples
        } else {
            // 多聲道取平均
            samples
                .chunks(spec.channels as usize)
                .map(|chunk| chunk.iter().sum::<f32>() / chunk.len() as f32)
                .collect()
        };

        // 重取樣（如果需要）
        let final_samples = if spec.sample_rate != self.target_sample_rate {
            self.resample(&mono_samples, spec.sample_rate, self.target_sample_rate)?
        } else {
            mono_samples
        };

        Ok(AudioData {
            samples: final_samples,
            sample_rate: self.target_sample_rate,
        })
    }

    /// 重取樣
    fn resample(
        &self,
        samples: &[f32],
        from_rate: u32,
        to_rate: u32,
    ) -> Result<Vec<f32>, AudioError> {
        use rubato::{FftFixedInOut, Resampler};

        let ratio = to_rate as f64 / from_rate as f64;
        let chunk_size = 1024;

        let mut resampler = FftFixedInOut::<f32>::new(from_rate as usize, to_rate as usize, chunk_size, 1)
            .map_err(|e| AudioError::Resample(e.to_string()))?;

        let mut output = Vec::with_capacity((samples.len() as f64 * ratio) as usize);

        // 處理完整的 chunks
        for chunk in samples.chunks(chunk_size) {
            if chunk.len() == chunk_size {
                let input = vec![chunk.to_vec()];
                let result = resampler
                    .process(&input, None)
                    .map_err(|e| AudioError::Resample(e.to_string()))?;
                output.extend_from_slice(&result[0]);
            }
        }

        // 處理剩餘的樣本
        let remaining = samples.len() % chunk_size;
        if remaining > 0 {
            let mut padded = samples[samples.len() - remaining..].to_vec();
            padded.resize(chunk_size, 0.0);
            let input = vec![padded];
            let result = resampler
                .process(&input, None)
                .map_err(|e| AudioError::Resample(e.to_string()))?;
            let output_remaining = (remaining as f64 * ratio) as usize;
            output.extend_from_slice(&result[0][..output_remaining.min(result[0].len())]);
        }

        Ok(output)
    }

    /// 儲存音訊檔案
    pub fn save<P: AsRef<Path>>(
        &self,
        audio: &AudioData,
        path: P,
        bits_per_sample: u16,
    ) -> Result<(), AudioError> {
        let path = path.as_ref();

        // 確保目錄存在
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }

        let spec = WavSpec {
            channels: 1,
            sample_rate: audio.sample_rate,
            bits_per_sample,
            sample_format: if bits_per_sample == 32 {
                hound::SampleFormat::Float
            } else {
                hound::SampleFormat::Int
            },
        };

        let mut writer = WavWriter::create(path, spec)?;

        match spec.sample_format {
            hound::SampleFormat::Float => {
                for &sample in &audio.samples {
                    writer.write_sample(sample)?;
                }
            }
            hound::SampleFormat::Int => {
                let max_val = (1 << (bits_per_sample - 1)) as f32;
                for &sample in &audio.samples {
                    let int_sample = (sample * max_val).clamp(-max_val, max_val - 1.0) as i32;
                    writer.write_sample(int_sample)?;
                }
            }
        }

        writer.finalize()?;
        Ok(())
    }

    /// 在指定位置附近尋找零交叉點
    pub fn find_zero_crossing(
        samples: &[f32],
        target_sample: usize,
        search_range: usize,
    ) -> usize {
        let start = target_sample.saturating_sub(search_range);
        let end = (target_sample + search_range).min(samples.len().saturating_sub(1));

        let mut best_idx = target_sample.min(samples.len().saturating_sub(1));
        let mut min_dist = usize::MAX;

        for i in start..end {
            if i + 1 < samples.len() && samples[i] * samples[i + 1] <= 0.0 {
                let dist = (i as isize - target_sample as isize).unsigned_abs();
                if dist < min_dist {
                    min_dist = dist;
                    best_idx = i;
                }
            }
        }

        // 如果找不到零交叉點，找最接近零的點
        if min_dist == usize::MAX {
            let mut min_abs = f32::MAX;
            for i in start..end {
                let abs_val = samples[i].abs();
                if abs_val < min_abs {
                    min_abs = abs_val;
                    best_idx = i;
                }
            }
        }

        best_idx
    }

    /// 套用 crossfade
    pub fn apply_crossfade(
        segment1: &[f32],
        segment2: &[f32],
        crossfade_samples: usize,
    ) -> Vec<f32> {
        if crossfade_samples == 0 || segment1.is_empty() || segment2.is_empty() {
            let mut result = segment1.to_vec();
            result.extend_from_slice(segment2);
            return result;
        }

        let fade_len = crossfade_samples.min(segment1.len()).min(segment2.len());

        let mut result = segment1[..segment1.len() - fade_len].to_vec();

        // Crossfade 區間
        for i in 0..fade_len {
            let t = i as f32 / fade_len as f32;
            let fade_out = segment1[segment1.len() - fade_len + i] * (1.0 - t);
            let fade_in = segment2[i] * t;
            result.push(fade_out + fade_in);
        }

        result.extend_from_slice(&segment2[fade_len..]);
        result
    }
}

impl Default for AudioProcessor {
    fn default() -> Self {
        Self::new(48000)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_find_zero_crossing() {
        let samples = vec![0.5, 0.3, 0.1, -0.1, -0.3, -0.5];
        let idx = AudioProcessor::find_zero_crossing(&samples, 3, 2);
        assert!(idx == 2 || idx == 3); // 零交叉點在 2-3 之間
    }

    #[test]
    fn test_crossfade() {
        let seg1 = vec![1.0; 100];
        let seg2 = vec![0.0; 100];
        let result = AudioProcessor::apply_crossfade(&seg1, &seg2, 10);
        assert_eq!(result.len(), 190); // 100 + 100 - 10
    }
}
