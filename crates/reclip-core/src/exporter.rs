//! 報告匯出模組

use std::collections::HashMap;
use std::fs;
use std::io::Write;
use std::path::Path;

use chrono::Local;
use serde::Serialize;
use thiserror::Error;

use crate::types::EditReport;

/// 匯出錯誤
#[derive(Error, Debug)]
pub enum ExportError {
    #[error("IO 錯誤: {0}")]
    Io(#[from] std::io::Error),

    #[error("JSON 序列化錯誤: {0}")]
    Json(#[from] serde_json::Error),
}

/// 報告匯出器
pub struct Exporter;

impl Exporter {
    /// 匯出 JSON 報告
    pub fn to_json<P: AsRef<Path>>(
        report: &EditReport,
        output_path: P,
        pretty: bool,
    ) -> Result<(), ExportError> {
        let output_path = output_path.as_ref();

        // 確保目錄存在
        if let Some(parent) = output_path.parent() {
            fs::create_dir_all(parent)?;
        }

        let data = JsonReport::from_report(report);

        let json = if pretty {
            serde_json::to_string_pretty(&data)?
        } else {
            serde_json::to_string(&data)?
        };

        fs::write(output_path, json)?;
        Ok(())
    }

    /// 匯出 EDL 檔案
    pub fn to_edl<P: AsRef<Path>>(
        report: &EditReport,
        output_path: P,
        fps: f64,
        title: Option<&str>,
    ) -> Result<(), ExportError> {
        let output_path = output_path.as_ref();

        if let Some(parent) = output_path.parent() {
            fs::create_dir_all(parent)?;
        }

        let edl_title = title.unwrap_or_else(|| {
            Path::new(&report.input_path)
                .file_stem()
                .and_then(|s| s.to_str())
                .unwrap_or("Untitled")
        });

        let mut content = String::new();
        content.push_str(&format!("TITLE: {}\n", edl_title));
        content.push_str("FCM: NON-DROP FRAME\n\n");

        // 計算保留的區間
        let keep_regions = Self::compute_keep_regions(report);

        let mut rec_offset = 0.0;
        for (i, (start, end)) in keep_regions.iter().enumerate() {
            let event_num = format!("{:03}", i + 1);
            let reel = "AX";

            let src_in = Self::seconds_to_timecode(*start, fps);
            let src_out = Self::seconds_to_timecode(*end, fps);

            let duration = end - start;
            let rec_in = Self::seconds_to_timecode(rec_offset, fps);
            let rec_out = Self::seconds_to_timecode(rec_offset + duration, fps);

            content.push_str(&format!(
                "{}  {}       AA/V  C        {} {} {} {}\n",
                event_num, reel, src_in, src_out, rec_in, rec_out
            ));

            let input_name = Path::new(&report.input_path)
                .file_name()
                .and_then(|s| s.to_str())
                .unwrap_or("input");
            content.push_str(&format!("* FROM CLIP NAME: {}\n\n", input_name));

            rec_offset += duration;
        }

        fs::write(output_path, content)?;
        Ok(())
    }

    /// 匯出標記檔案
    pub fn to_markers<P: AsRef<Path>>(
        report: &EditReport,
        output_path: P,
        format: MarkerFormat,
    ) -> Result<(), ExportError> {
        let output_path = output_path.as_ref();

        if let Some(parent) = output_path.parent() {
            fs::create_dir_all(parent)?;
        }

        let content = match format {
            MarkerFormat::Csv => Self::format_markers_csv(report),
            MarkerFormat::Audacity => Self::format_markers_audacity(report),
        };

        fs::write(output_path, content)?;
        Ok(())
    }

    /// 計算保留的區間
    fn compute_keep_regions(report: &EditReport) -> Vec<(f64, f64)> {
        if report.edits.is_empty() {
            return vec![(0.0, report.original_duration)];
        }

        let mut sorted_edits = report.edits.clone();
        sorted_edits.sort_by(|a, b| a.original_start.partial_cmp(&b.original_start).unwrap());

        let mut regions = Vec::new();
        let mut last_end = 0.0;

        for edit in &sorted_edits {
            if edit.original_start > last_end {
                regions.push((last_end, edit.original_start));
            }
            last_end = edit.original_end;
        }

        if last_end < report.original_duration {
            regions.push((last_end, report.original_duration));
        }

        regions
    }

    /// 將秒數轉換為時間碼
    fn seconds_to_timecode(seconds: f64, fps: f64) -> String {
        let total_frames = (seconds * fps) as u32;
        let frames = total_frames % fps as u32;
        let total_seconds = total_frames / fps as u32;
        let secs = total_seconds % 60;
        let total_minutes = total_seconds / 60;
        let mins = total_minutes % 60;
        let hours = total_minutes / 60;

        format!("{:02}:{:02}:{:02}:{:02}", hours, mins, secs, frames)
    }

    /// 格式化為 CSV 標記
    fn format_markers_csv(report: &EditReport) -> String {
        let mut lines = vec!["start,end,label,reason".to_string()];

        for edit in &report.edits {
            let text = edit.text.replace(',', ";").replace('\n', " ");
            lines.push(format!(
                "{:.3},{:.3},\"{}\",{}",
                edit.original_start, edit.original_end, text, edit.reason
            ));
        }

        lines.join("\n")
    }

    /// 格式化為 Audacity 標記
    fn format_markers_audacity(report: &EditReport) -> String {
        let mut lines = Vec::new();

        for edit in &report.edits {
            let text = edit.text.replace('\t', " ").replace('\n', " ");
            lines.push(format!(
                "{:.6}\t{:.6}\t[{}] {}",
                edit.original_start, edit.original_end, edit.reason, text
            ));
        }

        lines.join("\n")
    }
}

/// 標記格式
pub enum MarkerFormat {
    /// CSV 格式
    Csv,
    /// Audacity 標籤格式
    Audacity,
}

/// JSON 報告結構
#[derive(Serialize)]
struct JsonReport {
    version: String,
    generated_at: String,
    input: String,
    output: String,
    original_duration: f64,
    edited_duration: f64,
    removed_duration: f64,
    reduction_percent: f64,
    edit_count: usize,
    edits: Vec<JsonEdit>,
    statistics: Statistics,
}

#[derive(Serialize)]
struct JsonEdit {
    original_start: f64,
    original_end: f64,
    reason: String,
    text: String,
}

#[derive(Serialize)]
struct Statistics {
    by_reason: HashMap<String, ReasonStats>,
    total_removed_duration: f64,
}

#[derive(Serialize)]
struct ReasonStats {
    count: u32,
    duration: f64,
}

impl JsonReport {
    fn from_report(report: &EditReport) -> Self {
        let removed_duration = report.original_duration - report.edited_duration;
        let reduction_percent = if report.original_duration > 0.0 {
            removed_duration / report.original_duration * 100.0
        } else {
            0.0
        };

        // 計算統計
        let mut by_reason: HashMap<String, ReasonStats> = HashMap::new();
        let mut total_removed = 0.0;

        for edit in &report.edits {
            let duration = edit.original_end - edit.original_start;
            total_removed += duration;

            let stats = by_reason.entry(edit.reason.clone()).or_insert(ReasonStats {
                count: 0,
                duration: 0.0,
            });
            stats.count += 1;
            stats.duration += duration;
        }

        Self {
            version: "1.0".to_string(),
            generated_at: Local::now().to_rfc3339(),
            input: report.input_path.clone(),
            output: report.output_path.clone(),
            original_duration: report.original_duration,
            edited_duration: report.edited_duration,
            removed_duration,
            reduction_percent,
            edit_count: report.edits.len(),
            edits: report
                .edits
                .iter()
                .map(|e| JsonEdit {
                    original_start: e.original_start,
                    original_end: e.original_end,
                    reason: e.reason.clone(),
                    text: e.text.clone(),
                })
                .collect(),
            statistics: Statistics {
                by_reason,
                total_removed_duration: total_removed,
            },
        }
    }
}
