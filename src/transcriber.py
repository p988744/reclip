"""WhisperX 轉錄器 - 語音轉文字與說話者分離"""

from dataclasses import dataclass, field
from pathlib import Path
from typing import List, Optional
import os

import torch
import whisperx


@dataclass
class WordSegment:
    """單詞級別的時間戳"""
    word: str
    start: float  # 秒
    end: float
    confidence: float = 1.0
    speaker: Optional[str] = None

    def to_dict(self) -> dict:
        """轉換為字典"""
        return {
            "word": self.word,
            "start": self.start,
            "end": self.end,
            "confidence": self.confidence,
            "speaker": self.speaker,
        }


@dataclass
class Segment:
    """句子級別的段落"""
    text: str
    start: float
    end: float
    speaker: Optional[str] = None
    words: List[WordSegment] = field(default_factory=list)

    def to_dict(self) -> dict:
        """轉換為字典"""
        return {
            "text": self.text,
            "start": self.start,
            "end": self.end,
            "speaker": self.speaker,
            "words": [w.to_dict() for w in self.words],
        }


@dataclass
class TranscriptResult:
    """轉錄結果"""
    segments: List[Segment]
    language: str
    duration: float

    def to_dict(self) -> dict:
        """轉換為字典"""
        return {
            "segments": [s.to_dict() for s in self.segments],
            "language": self.language,
            "duration": self.duration,
        }

    def get_full_text(self) -> str:
        """取得完整文字"""
        return " ".join(s.text for s in self.segments)

    def get_words(self) -> List[WordSegment]:
        """取得所有單詞"""
        words = []
        for segment in self.segments:
            words.extend(segment.words)
        return words


class Transcriber:
    """WhisperX 轉錄器

    使用 WhisperX 進行語音轉文字，支援單詞級時間戳與說話者分離。
    """

    def __init__(
        self,
        model_size: str = "large-v3",
        device: str = "cuda",
        compute_type: str = "float16",
        language: str = "zh",
        hf_token: Optional[str] = None,
        batch_size: int = 16
    ):
        """
        初始化轉錄器

        Args:
            model_size: Whisper 模型大小 (tiny, base, small, medium, large-v2, large-v3)
            device: 執行裝置 ("cuda" 或 "cpu")
            compute_type: 計算精度 ("float16", "float32", "int8")
            language: 語言代碼 (zh, en, ja, etc.)
            hf_token: Hugging Face token (用於 pyannote 說話者分離)
            batch_size: 批次大小
        """
        self.model_size = model_size
        self.device = device
        self.compute_type = compute_type
        self.language = language
        self.hf_token = hf_token or os.getenv("HF_TOKEN")
        self.batch_size = batch_size

        self._model = None
        self._align_model = None
        self._align_metadata = None
        self._diarize_model = None

    def _load_models(self):
        """延遲載入模型"""
        if self._model is None:
            self._model = whisperx.load_model(
                self.model_size,
                self.device,
                compute_type=self.compute_type,
                language=self.language
            )

    def _load_align_model(self):
        """載入對齊模型"""
        if self._align_model is None:
            self._align_model, self._align_metadata = whisperx.load_align_model(
                language_code=self.language,
                device=self.device
            )

    def _load_diarize_model(self):
        """載入說話者分離模型"""
        if self._diarize_model is None:
            if not self.hf_token:
                raise ValueError(
                    "說話者分離需要 Hugging Face token，"
                    "請設定 HF_TOKEN 環境變數或傳入 hf_token 參數"
                )
            self._diarize_model = whisperx.DiarizationPipeline(
                use_auth_token=self.hf_token,
                device=self.device
            )

    def transcribe(
        self,
        audio_path: Path,
        diarize: bool = True,
        min_speakers: Optional[int] = None,
        max_speakers: Optional[int] = None
    ) -> TranscriptResult:
        """
        執行轉錄

        Args:
            audio_path: 音訊檔案路徑
            diarize: 是否執行說話者分離
            min_speakers: 最少說話者數 (用於 diarization)
            max_speakers: 最多說話者數 (用於 diarization)

        Returns:
            TranscriptResult
        """
        # 載入模型
        self._load_models()

        # 載入音訊
        audio = whisperx.load_audio(str(audio_path))
        duration = len(audio) / 16000  # WhisperX 使用 16kHz

        # 執行轉錄
        result = self._model.transcribe(audio, batch_size=self.batch_size)

        # 單詞級對齊
        self._load_align_model()
        result = whisperx.align(
            result["segments"],
            self._align_model,
            self._align_metadata,
            audio,
            self.device,
            return_char_alignments=False
        )

        # 說話者分離
        if diarize:
            try:
                self._load_diarize_model()
                diarize_segments = self._diarize_model(
                    audio,
                    min_speakers=min_speakers,
                    max_speakers=max_speakers
                )
                result = whisperx.assign_word_speakers(
                    diarize_segments, result
                )
            except ValueError as e:
                # 如果沒有 HF token，跳過 diarization
                if "Hugging Face" in str(e) or "HF_TOKEN" in str(e):
                    pass
                else:
                    raise

        # 轉換結果
        segments = self._convert_result(result)

        return TranscriptResult(
            segments=segments,
            language=self.language,
            duration=duration
        )

    def _convert_result(self, result: dict) -> List[Segment]:
        """轉換 WhisperX 結果為內部格式"""
        segments = []

        for seg in result.get("segments", []):
            words = []
            for word_data in seg.get("words", []):
                # 處理可能缺失的時間戳
                start = word_data.get("start")
                end = word_data.get("end")

                if start is None or end is None:
                    continue

                word = WordSegment(
                    word=word_data.get("word", ""),
                    start=start,
                    end=end,
                    confidence=word_data.get("score", 1.0),
                    speaker=word_data.get("speaker")
                )
                words.append(word)

            segment = Segment(
                text=seg.get("text", "").strip(),
                start=seg.get("start", 0.0),
                end=seg.get("end", 0.0),
                speaker=seg.get("speaker"),
                words=words
            )
            segments.append(segment)

        return segments

    def unload_models(self):
        """釋放模型記憶體"""
        del self._model
        del self._align_model
        del self._diarize_model
        self._model = None
        self._align_model = None
        self._align_metadata = None
        self._diarize_model = None

        if torch.cuda.is_available():
            torch.cuda.empty_cache()
