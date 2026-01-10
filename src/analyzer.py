"""LLM 分析引擎 - 使用 Claude API 分析逐字稿並產生剪輯決策"""

import json
import os
from dataclasses import dataclass, field
from typing import Dict, List, Literal

from anthropic import Anthropic

from .transcriber import Segment, TranscriptResult, WordSegment


RemovalReason = Literal["filler", "repeat", "restart", "mouth_noise", "long_pause"]


@dataclass
class Removal:
    """移除區間"""
    start: float
    end: float
    reason: RemovalReason
    text: str
    confidence: float = 0.9

    def to_dict(self) -> dict:
        """轉換為字典"""
        return {
            "start": self.start,
            "end": self.end,
            "reason": self.reason,
            "text": self.text,
            "confidence": self.confidence,
        }


@dataclass
class AnalysisResult:
    """分析結果"""
    removals: List[Removal]
    original_duration: float
    removed_duration: float
    statistics: Dict[str, int] = field(default_factory=dict)

    def to_dict(self) -> dict:
        """轉換為字典"""
        return {
            "removals": [r.to_dict() for r in self.removals],
            "original_duration": self.original_duration,
            "removed_duration": self.removed_duration,
            "statistics": self.statistics,
        }


ANALYSIS_PROMPT = """你是一個專業的 Podcast 剪輯助理。分析以下逐字稿，標記需要移除的區間。

## 需要移除的內容類型

1. **filler** - 語氣詞、填充詞
   - 中文：嗯、啊、呃、那個、就是說、對對對、然後然後、所以說
   - 英文：um, uh, like, you know, so, basically, actually, I mean

2. **repeat** - 重複的詞語或片語
   - 說話者重複同一個詞或片語多次

3. **restart** - 句子重新開始
   - 說話者講到一半停下，重新開始說

4. **mouth_noise** - 唇齒音或雜音
   - 吸氣聲、咂嘴聲、喉音（通常標記為特殊字元或空白）

5. **long_pause** - 過長的停頓
   - 超過 1.5 秒的停頓（根據時間戳判斷）

## 輸入格式

每行格式：[開始時間-結束時間] (說話者) 文字內容
時間單位為秒。

## 輸出格式

請以 JSON 格式輸出，包含 removals 陣列：

```json
{
  "removals": [
    {
      "start": 1.23,
      "end": 1.56,
      "reason": "filler",
      "text": "嗯",
      "confidence": 0.95
    }
  ]
}
```

## 注意事項

1. 只標記確定需要移除的內容，不確定就不要標記
2. 保留有意義的語氣詞（如表達驚訝、認同的「嗯」）
3. 時間戳必須精確對應輸入中的時間
4. confidence 範圍 0.0-1.0，表示移除的確定程度
5. 不要移除可能影響語意的內容

## 逐字稿

{transcript}

請分析以上逐字稿，輸出 JSON 格式的移除區間。只輸出 JSON，不要有其他說明。"""


class Analyzer:
    """LLM 分析引擎

    使用 Claude API 分析逐字稿，識別需要移除的區間。
    """

    def __init__(
        self,
        api_key: str = None,
        model: str = "claude-sonnet-4-20250514",
        max_segment_duration: float = 300.0,  # 5 分鐘
        min_confidence: float = 0.7
    ):
        """
        初始化分析器

        Args:
            api_key: Anthropic API key
            model: Claude 模型名稱
            max_segment_duration: 每次分析的最大時長（秒）
            min_confidence: 最低信心閾值
        """
        self.api_key = api_key or os.getenv("ANTHROPIC_API_KEY")
        if not self.api_key:
            raise ValueError(
                "需要 Anthropic API key，"
                "請設定 ANTHROPIC_API_KEY 環境變數或傳入 api_key 參數"
            )

        self.client = Anthropic(api_key=self.api_key)
        self.model = model
        self.max_segment_duration = max_segment_duration
        self.min_confidence = min_confidence

    def analyze(self, transcript: TranscriptResult) -> AnalysisResult:
        """
        分析逐字稿並產生剪輯決策

        Args:
            transcript: 轉錄結果

        Returns:
            AnalysisResult
        """
        all_removals = []

        # 分段處理
        chunks = self._chunk_transcript(transcript)

        for chunk in chunks:
            removals = self._call_llm(chunk)
            all_removals.extend(removals)

        # 過濾低信心的移除
        filtered_removals = [
            r for r in all_removals
            if r.confidence >= self.min_confidence
        ]

        # 計算統計
        removed_duration = sum(r.end - r.start for r in filtered_removals)
        statistics = self._compute_statistics(filtered_removals)

        return AnalysisResult(
            removals=filtered_removals,
            original_duration=transcript.duration,
            removed_duration=removed_duration,
            statistics=statistics
        )

    def _chunk_transcript(
        self,
        transcript: TranscriptResult
    ) -> List[List[Segment]]:
        """將逐字稿分段處理

        Args:
            transcript: 轉錄結果

        Returns:
            分段後的 segments 列表
        """
        chunks = []
        current_chunk = []
        chunk_start = 0.0

        for segment in transcript.segments:
            current_chunk.append(segment)

            # 檢查是否超過最大時長
            chunk_duration = segment.end - chunk_start
            if chunk_duration >= self.max_segment_duration:
                chunks.append(current_chunk)
                current_chunk = []
                chunk_start = segment.end

        # 加入最後一個 chunk
        if current_chunk:
            chunks.append(current_chunk)

        return chunks

    def _format_transcript(self, segments: List[Segment]) -> str:
        """格式化逐字稿供 LLM 分析"""
        lines = []
        for seg in segments:
            speaker = f"({seg.speaker})" if seg.speaker else ""
            line = f"[{seg.start:.2f}-{seg.end:.2f}] {speaker} {seg.text}"
            lines.append(line)

            # 加入單詞級別的詳細資訊
            if seg.words:
                word_details = []
                for w in seg.words:
                    word_details.append(f"  [{w.start:.2f}-{w.end:.2f}] {w.word}")
                lines.extend(word_details)

        return "\n".join(lines)

    def _call_llm(self, segments: List[Segment]) -> List[Removal]:
        """呼叫 Claude API"""
        transcript_text = self._format_transcript(segments)
        prompt = self._get_prompt(transcript_text)

        message = self.client.messages.create(
            model=self.model,
            max_tokens=4096,
            messages=[
                {"role": "user", "content": prompt}
            ]
        )

        # 解析回應
        response_text = message.content[0].text
        return self._parse_response(response_text)

    def _get_prompt(self, transcript_text: str) -> str:
        """產生 prompt"""
        return ANALYSIS_PROMPT.format(transcript=transcript_text)

    def _parse_response(self, response: str) -> List[Removal]:
        """解析 LLM 回應"""
        removals = []

        try:
            # 嘗試提取 JSON
            # 處理可能包含 markdown code block 的情況
            json_str = response
            if "```json" in response:
                start = response.find("```json") + 7
                end = response.find("```", start)
                json_str = response[start:end].strip()
            elif "```" in response:
                start = response.find("```") + 3
                end = response.find("```", start)
                json_str = response[start:end].strip()

            data = json.loads(json_str)

            for item in data.get("removals", []):
                removal = Removal(
                    start=float(item["start"]),
                    end=float(item["end"]),
                    reason=item["reason"],
                    text=item.get("text", ""),
                    confidence=float(item.get("confidence", 0.9))
                )
                removals.append(removal)

        except (json.JSONDecodeError, KeyError, ValueError) as e:
            # 解析失敗，返回空列表
            pass

        return removals

    def _compute_statistics(self, removals: List[Removal]) -> Dict[str, int]:
        """計算移除統計"""
        stats: Dict[str, int] = {
            "filler": 0,
            "repeat": 0,
            "restart": 0,
            "mouth_noise": 0,
            "long_pause": 0,
        }

        for removal in removals:
            if removal.reason in stats:
                stats[removal.reason] += 1

        return stats

    def analyze_with_progress(
        self,
        transcript: TranscriptResult,
        progress_callback=None
    ) -> AnalysisResult:
        """
        分析逐字稿並回報進度

        Args:
            transcript: 轉錄結果
            progress_callback: 進度回調函數 (current, total)

        Returns:
            AnalysisResult
        """
        all_removals = []

        chunks = self._chunk_transcript(transcript)
        total = len(chunks)

        for i, chunk in enumerate(chunks):
            if progress_callback:
                progress_callback(i, total)

            removals = self._call_llm(chunk)
            all_removals.extend(removals)

        if progress_callback:
            progress_callback(total, total)

        # 過濾與統計
        filtered_removals = [
            r for r in all_removals
            if r.confidence >= self.min_confidence
        ]
        removed_duration = sum(r.end - r.start for r in filtered_removals)
        statistics = self._compute_statistics(filtered_removals)

        return AnalysisResult(
            removals=filtered_removals,
            original_duration=transcript.duration,
            removed_duration=removed_duration,
            statistics=statistics
        )
