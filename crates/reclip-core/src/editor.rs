//! 音訊編輯模組

use std::path::Path;

use crate::audio::{AudioData, AudioError, AudioProcessor};
use crate::types::{AnalysisResult, AppliedEdit, EditReport, Removal};

/// 編輯器設定
#[derive(Debug, Clone)]
pub struct EditorConfig {
    /// Crossfade 長度（毫秒）
    pub crossfade_ms: u32,
    /// 最小移除長度（毫秒）
    pub min_removal_ms: u32,
    /// 合併相鄰區間的閾值（毫秒）
    pub merge_gap_ms: u32,
    /// 零交叉點搜尋範圍（毫秒）
    pub zero_crossing_search_ms: u32,
}

impl Default for EditorConfig {
    fn default() -> Self {
        Self {
            crossfade_ms: 30,
            min_removal_ms: 100,
            merge_gap_ms: 50,
            zero_crossing_search_ms: 5,
        }
    }
}

/// 音訊編輯器
pub struct Editor {
    config: EditorConfig,
    processor: AudioProcessor,
}

impl Editor {
    /// 建立新的編輯器
    pub fn new(config: EditorConfig) -> Self {
        Self {
            config,
            processor: AudioProcessor::default(),
        }
    }

    /// 執行剪輯
    pub fn edit<P: AsRef<Path>>(
        &self,
        audio_path: P,
        analysis: &AnalysisResult,
        output_path: P,
    ) -> Result<EditReport, AudioError> {
        let audio_path = audio_path.as_ref();
        let output_path = output_path.as_ref();

        // 載入音訊
        let audio = self.processor.load(audio_path)?;
        let original_duration = audio.duration();
        let sample_rate = audio.sample_rate;

        // 過濾太短的移除區間
        let min_duration = self.config.min_removal_ms as f64 / 1000.0;
        let valid_removals: Vec<_> = analysis
            .removals
            .iter()
            .filter(|r| r.duration() >= min_duration)
            .cloned()
            .collect();

        // 合併相鄰區間
        let merged_removals = self.merge_removals(&valid_removals);

        // 排序
        let mut sorted_removals = merged_removals;
        sorted_removals.sort_by(|a, b| a.start.partial_cmp(&b.start).unwrap());

        // 調整到零交叉點
        let adjusted_removals =
            self.adjust_to_zero_crossings(&audio, &sorted_removals);

        // 執行剪輯
        let (edited_audio, edits) = self.apply_removals(&audio, &adjusted_removals)?;

        // 儲存
        self.processor.save(&edited_audio, output_path, 24)?;

        let edited_duration = edited_audio.duration();

        Ok(EditReport {
            input_path: audio_path.display().to_string(),
            output_path: output_path.display().to_string(),
            original_duration,
            edited_duration,
            edits,
        })
    }

    /// 合併相鄰的移除區間
    fn merge_removals(&self, removals: &[Removal]) -> Vec<Removal> {
        if removals.is_empty() {
            return Vec::new();
        }

        let mut sorted = removals.to_vec();
        sorted.sort_by(|a, b| a.start.partial_cmp(&b.start).unwrap());

        let mut merged = vec![sorted[0].clone()];
        let merge_threshold = self.config.merge_gap_ms as f64 / 1000.0;

        for removal in sorted.iter().skip(1) {
            let last = merged.last_mut().unwrap();
            let gap = removal.start - last.end;

            if gap <= merge_threshold {
                // 合併區間
                last.end = removal.end;
                last.text = format!("{} ... {}", last.text, removal.text);
                last.confidence = last.confidence.min(removal.confidence);
            } else {
                merged.push(removal.clone());
            }
        }

        merged
    }

    /// 調整切點到零交叉點
    fn adjust_to_zero_crossings(
        &self,
        audio: &AudioData,
        removals: &[Removal],
    ) -> Vec<(usize, usize, Removal)> {
        let search_samples =
            (self.config.zero_crossing_search_ms as f64 / 1000.0 * audio.sample_rate as f64) as usize;

        removals
            .iter()
            .filter_map(|removal| {
                let start_sample = audio.time_to_sample(removal.start);
                let end_sample = audio.time_to_sample(removal.end);

                // 調整開始點
                let adjusted_start = AudioProcessor::find_zero_crossing(
                    &audio.samples,
                    start_sample,
                    search_samples,
                );

                // 調整結束點
                let adjusted_end = AudioProcessor::find_zero_crossing(
                    &audio.samples,
                    end_sample,
                    search_samples,
                );

                if adjusted_end > adjusted_start {
                    Some((adjusted_start, adjusted_end, removal.clone()))
                } else {
                    None
                }
            })
            .collect()
    }

    /// 套用移除區間
    fn apply_removals(
        &self,
        audio: &AudioData,
        removals: &[(usize, usize, Removal)],
    ) -> Result<(AudioData, Vec<AppliedEdit>), AudioError> {
        if removals.is_empty() {
            return Ok((audio.clone(), Vec::new()));
        }

        let crossfade_samples =
            (self.config.crossfade_ms as f64 / 1000.0 * audio.sample_rate as f64) as usize;

        let mut edits = Vec::new();
        let mut segments: Vec<&[f32]> = Vec::new();
        let mut last_end = 0;

        for (start, end, removal) in removals {
            // 保留的區間
            if *start > last_end {
                segments.push(&audio.samples[last_end..*start]);
            }

            // 記錄編輯
            edits.push(AppliedEdit {
                original_start: removal.start,
                original_end: removal.end,
                reason: removal.reason.to_string(),
                text: removal.text.clone(),
            });

            last_end = *end;
        }

        // 最後一段
        if last_end < audio.samples.len() {
            segments.push(&audio.samples[last_end..]);
        }

        // 合併並套用 crossfade
        if segments.is_empty() {
            return Ok((
                AudioData {
                    samples: Vec::new(),
                    sample_rate: audio.sample_rate,
                },
                edits,
            ));
        }

        let mut result = segments[0].to_vec();
        for segment in segments.iter().skip(1) {
            result = AudioProcessor::apply_crossfade(&result, segment, crossfade_samples);
        }

        Ok((
            AudioData {
                samples: result,
                sample_rate: audio.sample_rate,
            },
            edits,
        ))
    }

    /// 預覽將要移除的區間（不實際編輯）
    pub fn preview<P: AsRef<Path>>(
        &self,
        audio_path: P,
        analysis: &AnalysisResult,
    ) -> Result<Vec<PreviewEdit>, AudioError> {
        let audio = self.processor.load(audio_path)?;

        let min_duration = self.config.min_removal_ms as f64 / 1000.0;
        let valid_removals: Vec<_> = analysis
            .removals
            .iter()
            .filter(|r| r.duration() >= min_duration)
            .cloned()
            .collect();

        let merged = self.merge_removals(&valid_removals);
        let mut sorted = merged;
        sorted.sort_by(|a, b| a.start.partial_cmp(&b.start).unwrap());

        let adjusted = self.adjust_to_zero_crossings(&audio, &sorted);

        Ok(adjusted
            .into_iter()
            .map(|(start, end, removal)| PreviewEdit {
                original_start: removal.start,
                original_end: removal.end,
                adjusted_start: audio.sample_to_time(start),
                adjusted_end: audio.sample_to_time(end),
                duration: audio.sample_to_time(end) - audio.sample_to_time(start),
                reason: removal.reason.to_string(),
                text: removal.text,
                confidence: removal.confidence,
            })
            .collect())
    }
}

/// 預覽編輯
#[derive(Debug, Clone)]
pub struct PreviewEdit {
    pub original_start: f64,
    pub original_end: f64,
    pub adjusted_start: f64,
    pub adjusted_end: f64,
    pub duration: f64,
    pub reason: String,
    pub text: String,
    pub confidence: f64,
}

impl Default for Editor {
    fn default() -> Self {
        Self::new(EditorConfig::default())
    }
}
