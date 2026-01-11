//! Python 綁定模組 (PyO3)

use pyo3::prelude::*;
use pyo3::types::PyDict;
use std::collections::HashMap;

use crate::audio::AudioProcessor;
use crate::editor::{Editor, EditorConfig};
use crate::exporter::{Exporter, MarkerFormat};
use crate::types::{AnalysisResult, AppliedEdit, EditReport, Removal, RemovalReason};

/// Python 音訊處理器
#[pyclass(name = "AudioProcessor")]
pub struct PyAudioProcessor {
    inner: AudioProcessor,
}

#[pymethods]
impl PyAudioProcessor {
    #[new]
    #[pyo3(signature = (sample_rate=48000))]
    fn new(sample_rate: u32) -> Self {
        Self {
            inner: AudioProcessor::new(sample_rate),
        }
    }

    /// 取得音訊資訊
    fn get_info(&self, path: &str) -> PyResult<HashMap<String, PyObject>> {
        Python::with_gil(|py| {
            let info = self
                .inner
                .get_info(path)
                .map_err(|e| PyErr::new::<pyo3::exceptions::PyIOError, _>(e.to_string()))?;

            let mut dict = HashMap::new();
            dict.insert("path".to_string(), info.path.into_py(py));
            dict.insert("duration".to_string(), info.duration.into_py(py));
            dict.insert("sample_rate".to_string(), info.sample_rate.into_py(py));
            dict.insert("channels".to_string(), info.channels.into_py(py));
            dict.insert(
                "bits_per_sample".to_string(),
                info.bits_per_sample.into_py(py),
            );

            Ok(dict)
        })
    }
}

/// Python 編輯器
#[pyclass(name = "Editor")]
pub struct PyEditor {
    inner: Editor,
}

#[pymethods]
impl PyEditor {
    #[new]
    #[pyo3(signature = (crossfade_ms=30, min_removal_ms=100, merge_gap_ms=50, zero_crossing_search_ms=5))]
    fn new(
        crossfade_ms: u32,
        min_removal_ms: u32,
        merge_gap_ms: u32,
        zero_crossing_search_ms: u32,
    ) -> Self {
        Self {
            inner: Editor::new(EditorConfig {
                crossfade_ms,
                min_removal_ms,
                merge_gap_ms,
                zero_crossing_search_ms,
            }),
        }
    }

    /// 執行剪輯
    fn edit(
        &self,
        audio_path: &str,
        analysis: &PyAnalysisResult,
        output_path: &str,
    ) -> PyResult<PyEditReport> {
        let report = self
            .inner
            .edit(audio_path, &analysis.inner, output_path)
            .map_err(|e| PyErr::new::<pyo3::exceptions::PyIOError, _>(e.to_string()))?;

        Ok(PyEditReport { inner: report })
    }
}

/// Python 分析結果
#[pyclass(name = "AnalysisResult")]
#[derive(Clone)]
pub struct PyAnalysisResult {
    inner: AnalysisResult,
}

#[pymethods]
impl PyAnalysisResult {
    #[new]
    fn new(
        removals: Vec<PyRemoval>,
        original_duration: f64,
        removed_duration: f64,
        statistics: HashMap<String, u32>,
    ) -> Self {
        Self {
            inner: AnalysisResult {
                removals: removals.into_iter().map(|r| r.inner).collect(),
                original_duration,
                removed_duration,
                statistics,
            },
        }
    }

    #[getter]
    fn removals(&self) -> Vec<PyRemoval> {
        self.inner
            .removals
            .iter()
            .map(|r| PyRemoval { inner: r.clone() })
            .collect()
    }

    #[getter]
    fn original_duration(&self) -> f64 {
        self.inner.original_duration
    }

    #[getter]
    fn removed_duration(&self) -> f64 {
        self.inner.removed_duration
    }
}

/// Python 移除區間
#[pyclass(name = "Removal")]
#[derive(Clone)]
pub struct PyRemoval {
    inner: Removal,
}

#[pymethods]
impl PyRemoval {
    #[new]
    fn new(start: f64, end: f64, reason: &str, text: &str, confidence: f64) -> Self {
        let reason = match reason {
            "filler" => RemovalReason::Filler,
            "repeat" => RemovalReason::Repeat,
            "restart" => RemovalReason::Restart,
            "mouth_noise" => RemovalReason::MouthNoise,
            "long_pause" => RemovalReason::LongPause,
            _ => RemovalReason::Filler,
        };

        Self {
            inner: Removal {
                start,
                end,
                reason,
                text: text.to_string(),
                confidence,
            },
        }
    }

    #[getter]
    fn start(&self) -> f64 {
        self.inner.start
    }

    #[getter]
    fn end(&self) -> f64 {
        self.inner.end
    }

    #[getter]
    fn reason(&self) -> String {
        self.inner.reason.to_string()
    }

    #[getter]
    fn text(&self) -> String {
        self.inner.text.clone()
    }

    #[getter]
    fn confidence(&self) -> f64 {
        self.inner.confidence
    }
}

/// Python 編輯報告
#[pyclass(name = "EditReport")]
pub struct PyEditReport {
    inner: EditReport,
}

#[pymethods]
impl PyEditReport {
    #[getter]
    fn input_path(&self) -> String {
        self.inner.input_path.clone()
    }

    #[getter]
    fn output_path(&self) -> String {
        self.inner.output_path.clone()
    }

    #[getter]
    fn original_duration(&self) -> f64 {
        self.inner.original_duration
    }

    #[getter]
    fn edited_duration(&self) -> f64 {
        self.inner.edited_duration
    }

    #[getter]
    fn edits(&self) -> Vec<PyAppliedEdit> {
        self.inner
            .edits
            .iter()
            .map(|e| PyAppliedEdit { inner: e.clone() })
            .collect()
    }

    /// 匯出 JSON 報告
    fn to_json(&self, output_path: &str, pretty: bool) -> PyResult<()> {
        Exporter::to_json(&self.inner, output_path, pretty)
            .map_err(|e| PyErr::new::<pyo3::exceptions::PyIOError, _>(e.to_string()))
    }

    /// 匯出 EDL 檔案
    #[pyo3(signature = (output_path, fps=30.0, title=None))]
    fn to_edl(&self, output_path: &str, fps: f64, title: Option<&str>) -> PyResult<()> {
        Exporter::to_edl(&self.inner, output_path, fps, title)
            .map_err(|e| PyErr::new::<pyo3::exceptions::PyIOError, _>(e.to_string()))
    }

    /// 匯出標記檔案
    fn to_markers(&self, output_path: &str, format: &str) -> PyResult<()> {
        let marker_format = match format {
            "csv" => MarkerFormat::Csv,
            "audacity" | "txt" => MarkerFormat::Audacity,
            _ => MarkerFormat::Csv,
        };

        Exporter::to_markers(&self.inner, output_path, marker_format)
            .map_err(|e| PyErr::new::<pyo3::exceptions::PyIOError, _>(e.to_string()))
    }
}

/// Python 已套用編輯
#[pyclass(name = "AppliedEdit")]
pub struct PyAppliedEdit {
    inner: AppliedEdit,
}

#[pymethods]
impl PyAppliedEdit {
    #[getter]
    fn original_start(&self) -> f64 {
        self.inner.original_start
    }

    #[getter]
    fn original_end(&self) -> f64 {
        self.inner.original_end
    }

    #[getter]
    fn reason(&self) -> String {
        self.inner.reason.clone()
    }

    #[getter]
    fn text(&self) -> String {
        self.inner.text.clone()
    }
}

/// Python 模組初始化
#[pymodule]
fn _core(m: &Bound<'_, PyModule>) -> PyResult<()> {
    m.add_class::<PyAudioProcessor>()?;
    m.add_class::<PyEditor>()?;
    m.add_class::<PyAnalysisResult>()?;
    m.add_class::<PyRemoval>()?;
    m.add_class::<PyEditReport>()?;
    m.add_class::<PyAppliedEdit>()?;
    Ok(())
}
