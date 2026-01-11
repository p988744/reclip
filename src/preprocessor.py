"""音訊預處理器 - 格式標準化與多軌處理"""

from pathlib import Path
from typing import List, Literal

from pydub import AudioSegment


class AudioPreprocessor:
    """音訊預處理器

    將輸入音訊標準化為統一格式，支援多軌合併。
    """

    def __init__(self, sample_rate: int = 48000, channels: int = 1):
        """
        初始化預處理器

        Args:
            sample_rate: 目標取樣率 (Hz)
            channels: 目標聲道數 (1=mono, 2=stereo)
        """
        self.sample_rate = sample_rate
        self.channels = channels

    def process(
        self,
        input_paths: List[Path],
        output_path: Path,
        mode: Literal["merge", "first"] = "first"
    ) -> Path:
        """
        處理音訊檔案

        Args:
            input_paths: 輸入音訊路徑列表
            output_path: 輸出路徑
            mode: "merge" 合併所有軌道, "first" 只用第一軌

        Returns:
            處理後的音訊路徑

        Raises:
            ValueError: 若輸入路徑列表為空
            FileNotFoundError: 若輸入檔案不存在
        """
        if not input_paths:
            raise ValueError("至少需要一個輸入檔案")

        # 驗證所有檔案存在
        for path in input_paths:
            if not path.exists():
                raise FileNotFoundError(f"找不到檔案: {path}")

        # 載入音訊
        audio_segments = [self._load_audio(p) for p in input_paths]

        # 根據模式處理
        if mode == "first":
            result = self._normalize(audio_segments[0])
        elif mode == "merge":
            result = self._merge_tracks(audio_segments)
        else:
            raise ValueError(f"不支援的模式: {mode}")

        # 確保輸出目錄存在
        output_path.parent.mkdir(parents=True, exist_ok=True)

        # 匯出
        result.export(
            output_path,
            format="wav",
            parameters=["-ar", str(self.sample_rate)]
        )

        return output_path

    def _load_audio(self, path: Path) -> AudioSegment:
        """載入音訊檔案

        Args:
            path: 音訊檔案路徑

        Returns:
            AudioSegment 物件
        """
        suffix = path.suffix.lower()

        if suffix == ".wav":
            return AudioSegment.from_wav(str(path))
        elif suffix == ".mp3":
            return AudioSegment.from_mp3(str(path))
        elif suffix == ".flac":
            return AudioSegment.from_file(str(path), format="flac")
        elif suffix in [".ogg", ".opus"]:
            return AudioSegment.from_ogg(str(path))
        elif suffix == ".m4a":
            return AudioSegment.from_file(str(path), format="m4a")
        else:
            # 嘗試自動偵測格式
            return AudioSegment.from_file(str(path))

    def _normalize(self, audio: AudioSegment) -> AudioSegment:
        """標準化音訊格式

        Args:
            audio: 輸入音訊

        Returns:
            標準化後的音訊
        """
        return audio.set_frame_rate(self.sample_rate).set_channels(self.channels)

    def _merge_tracks(self, tracks: List[AudioSegment]) -> AudioSegment:
        """合併多個音軌

        Args:
            tracks: 音軌列表

        Returns:
            合併後的音訊
        """
        if not tracks:
            raise ValueError("沒有音軌可合併")

        # 先標準化所有軌道
        normalized = [self._normalize(t) for t in tracks]

        # 找出最長的軌道長度
        max_length = max(len(t) for t in normalized)

        # 將所有軌道填充到相同長度
        padded = []
        for track in normalized:
            if len(track) < max_length:
                # 用靜音填充
                silence = AudioSegment.silent(
                    duration=max_length - len(track),
                    frame_rate=self.sample_rate
                )
                track = track + silence
            padded.append(track)

        # 疊加合併
        result = padded[0]
        for track in padded[1:]:
            result = result.overlay(track)

        return result

    def get_audio_info(self, path: Path) -> dict:
        """取得音訊檔案資訊

        Args:
            path: 音訊檔案路徑

        Returns:
            包含音訊資訊的字典
        """
        audio = self._load_audio(path)
        return {
            "path": str(path),
            "duration_seconds": len(audio) / 1000.0,
            "sample_rate": audio.frame_rate,
            "channels": audio.channels,
            "sample_width": audio.sample_width,
            "frame_count": audio.frame_count(),
        }
