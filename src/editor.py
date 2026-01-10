"""音訊編輯器 - 執行剪輯操作"""

from dataclasses import dataclass
from pathlib import Path
from typing import List, Tuple

import numpy as np
from pydub import AudioSegment

from .analyzer import AnalysisResult, Removal


@dataclass
class AppliedEdit:
    """已套用的編輯"""
    original_start: float
    original_end: float
    reason: str
    text: str

    def to_dict(self) -> dict:
        """轉換為字典"""
        return {
            "original_start": self.original_start,
            "original_end": self.original_end,
            "reason": self.reason,
            "text": self.text,
        }


@dataclass
class EditReport:
    """編輯報告"""
    input_path: Path
    output_path: Path
    original_duration: float
    edited_duration: float
    edits: List[AppliedEdit]

    def to_dict(self) -> dict:
        """轉換為字典"""
        return {
            "input_path": str(self.input_path),
            "output_path": str(self.output_path),
            "original_duration": self.original_duration,
            "edited_duration": self.edited_duration,
            "edits": [e.to_dict() for e in self.edits],
        }


class Editor:
    """音訊編輯器

    根據分析結果執行剪輯，支援零交叉點對齊與 crossfade。
    """

    def __init__(
        self,
        crossfade_ms: int = 30,
        min_removal_ms: int = 100,
        merge_gap_ms: int = 50,
        zero_crossing_search_ms: int = 5
    ):
        """
        初始化編輯器

        Args:
            crossfade_ms: Crossfade 長度 (毫秒)
            min_removal_ms: 最小移除長度 (毫秒)
            merge_gap_ms: 合併相鄰移除區間的閾值 (毫秒)
            zero_crossing_search_ms: 零交叉點搜尋範圍 (毫秒)
        """
        self.crossfade_ms = crossfade_ms
        self.min_removal_ms = min_removal_ms
        self.merge_gap_ms = merge_gap_ms
        self.zero_crossing_search_ms = zero_crossing_search_ms

    def edit(
        self,
        audio_path: Path,
        analysis: AnalysisResult,
        output_path: Path
    ) -> EditReport:
        """
        執行剪輯

        Args:
            audio_path: 原始音訊路徑
            analysis: 分析結果
            output_path: 輸出路徑

        Returns:
            EditReport
        """
        # 載入音訊
        audio = AudioSegment.from_file(str(audio_path))
        original_duration = len(audio) / 1000.0  # 毫秒轉秒
        sample_rate = audio.frame_rate

        # 過濾太短的移除區間
        valid_removals = [
            r for r in analysis.removals
            if (r.end - r.start) * 1000 >= self.min_removal_ms
        ]

        # 合併相鄰的移除區間
        merged_removals = self._merge_removals(valid_removals)

        # 排序移除區間
        sorted_removals = sorted(merged_removals, key=lambda r: r.start)

        # 轉換音訊為 numpy 陣列以進行零交叉點搜尋
        samples = np.array(audio.get_array_of_samples())
        if audio.channels == 2:
            samples = samples.reshape((-1, 2)).mean(axis=1)

        # 調整切點到零交叉點
        adjusted_removals = self._adjust_to_zero_crossings(
            sorted_removals, samples, sample_rate
        )

        # 執行剪輯
        result_audio, applied_edits = self._apply_removals(
            audio, adjusted_removals
        )

        # 確保輸出目錄存在
        output_path.parent.mkdir(parents=True, exist_ok=True)

        # 匯出
        result_audio.export(str(output_path), format=output_path.suffix[1:])

        edited_duration = len(result_audio) / 1000.0

        return EditReport(
            input_path=audio_path,
            output_path=output_path,
            original_duration=original_duration,
            edited_duration=edited_duration,
            edits=applied_edits
        )

    def _merge_removals(self, removals: List[Removal]) -> List[Removal]:
        """合併相鄰的移除區間"""
        if not removals:
            return []

        sorted_removals = sorted(removals, key=lambda r: r.start)
        merged = [sorted_removals[0]]

        for removal in sorted_removals[1:]:
            last = merged[-1]
            gap_ms = (removal.start - last.end) * 1000

            if gap_ms <= self.merge_gap_ms:
                # 合併區間
                merged_removal = Removal(
                    start=last.start,
                    end=removal.end,
                    reason=last.reason,  # 使用第一個的原因
                    text=f"{last.text} ... {removal.text}",
                    confidence=min(last.confidence, removal.confidence)
                )
                merged[-1] = merged_removal
            else:
                merged.append(removal)

        return merged

    def _find_zero_crossing(
        self,
        samples: np.ndarray,
        target_ms: float,
        sample_rate: int,
        search_direction: str = "both"
    ) -> int:
        """
        在目標點附近尋找零交叉點

        Args:
            samples: 音訊樣本陣列
            target_ms: 目標時間點（毫秒）
            sample_rate: 取樣率
            search_direction: 搜尋方向 ("forward", "backward", "both")

        Returns:
            零交叉點的樣本索引
        """
        target_sample = int(target_ms * sample_rate / 1000)
        search_samples = int(self.zero_crossing_search_ms * sample_rate / 1000)

        # 確保在有效範圍內
        target_sample = max(0, min(target_sample, len(samples) - 1))

        # 定義搜尋範圍
        start = max(0, target_sample - search_samples)
        end = min(len(samples) - 1, target_sample + search_samples)

        # 尋找零交叉點
        best_idx = target_sample
        min_abs_value = abs(samples[target_sample])

        for i in range(start, end):
            if i < len(samples) - 1:
                # 檢查是否為零交叉點（符號改變）
                if samples[i] * samples[i + 1] <= 0:
                    # 選擇更接近目標的零交叉點
                    if abs(i - target_sample) < abs(best_idx - target_sample):
                        best_idx = i
                        min_abs_value = 0
                        break

        # 如果找不到零交叉點，選擇最接近零的點
        if min_abs_value > 0:
            for i in range(start, end):
                if abs(samples[i]) < min_abs_value:
                    min_abs_value = abs(samples[i])
                    best_idx = i

        return best_idx

    def _adjust_to_zero_crossings(
        self,
        removals: List[Removal],
        samples: np.ndarray,
        sample_rate: int
    ) -> List[Tuple[float, float, Removal]]:
        """
        將所有移除區間的切點調整到零交叉點

        Returns:
            調整後的 (start_ms, end_ms, removal) 列表
        """
        adjusted = []

        for removal in removals:
            start_ms = removal.start * 1000
            end_ms = removal.end * 1000

            # 調整開始點
            start_sample = self._find_zero_crossing(
                samples, start_ms, sample_rate, "backward"
            )
            adjusted_start_ms = start_sample * 1000 / sample_rate

            # 調整結束點
            end_sample = self._find_zero_crossing(
                samples, end_ms, sample_rate, "forward"
            )
            adjusted_end_ms = end_sample * 1000 / sample_rate

            # 確保調整後區間仍然有效
            if adjusted_end_ms > adjusted_start_ms:
                adjusted.append((adjusted_start_ms, adjusted_end_ms, removal))

        return adjusted

    def _apply_removals(
        self,
        audio: AudioSegment,
        removals: List[Tuple[float, float, Removal]]
    ) -> Tuple[AudioSegment, List[AppliedEdit]]:
        """
        套用移除區間

        Args:
            audio: 原始音訊
            removals: 調整後的移除區間列表

        Returns:
            (剪輯後音訊, 套用的編輯列表)
        """
        if not removals:
            return audio, []

        applied_edits = []
        segments = []
        last_end = 0.0

        for start_ms, end_ms, removal in removals:
            # 加入保留的區間
            if start_ms > last_end:
                segment = audio[last_end:start_ms]
                segments.append(segment)

            # 記錄編輯
            applied_edits.append(AppliedEdit(
                original_start=removal.start,
                original_end=removal.end,
                reason=removal.reason,
                text=removal.text
            ))

            last_end = end_ms

        # 加入最後一段
        if last_end < len(audio):
            segments.append(audio[last_end:])

        # 合併所有區間，套用 crossfade
        if not segments:
            return AudioSegment.silent(duration=0), applied_edits

        result = segments[0]
        for segment in segments[1:]:
            result = self._apply_crossfade(result, segment)

        return result, applied_edits

    def _apply_crossfade(
        self,
        segment1: AudioSegment,
        segment2: AudioSegment
    ) -> AudioSegment:
        """套用 crossfade"""
        # 確保兩個片段都夠長
        if len(segment1) < self.crossfade_ms or len(segment2) < self.crossfade_ms:
            # 片段太短，直接連接
            return segment1 + segment2

        return segment1.append(segment2, crossfade=self.crossfade_ms)

    def preview_removals(
        self,
        audio_path: Path,
        analysis: AnalysisResult
    ) -> List[dict]:
        """
        預覽將要移除的區間（不實際編輯）

        Args:
            audio_path: 音訊路徑
            analysis: 分析結果

        Returns:
            移除區間的詳細資訊列表
        """
        audio = AudioSegment.from_file(str(audio_path))
        sample_rate = audio.frame_rate

        samples = np.array(audio.get_array_of_samples())
        if audio.channels == 2:
            samples = samples.reshape((-1, 2)).mean(axis=1)

        valid_removals = [
            r for r in analysis.removals
            if (r.end - r.start) * 1000 >= self.min_removal_ms
        ]
        merged = self._merge_removals(valid_removals)
        sorted_removals = sorted(merged, key=lambda r: r.start)
        adjusted = self._adjust_to_zero_crossings(
            sorted_removals, samples, sample_rate
        )

        preview = []
        for start_ms, end_ms, removal in adjusted:
            preview.append({
                "original_start": removal.start,
                "original_end": removal.end,
                "adjusted_start": start_ms / 1000,
                "adjusted_end": end_ms / 1000,
                "duration": (end_ms - start_ms) / 1000,
                "reason": removal.reason,
                "text": removal.text,
                "confidence": removal.confidence,
            })

        return preview
