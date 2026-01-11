"""報告匯出器 - 匯出 JSON 報告與 EDL 檔案"""

import json
from datetime import datetime
from pathlib import Path
from typing import Optional

from .editor import EditReport


class ReportExporter:
    """報告匯出器

    支援匯出 JSON 報告與 EDL 檔案。
    """

    @staticmethod
    def to_json(
        report: EditReport,
        output_path: Path,
        pretty: bool = True
    ) -> None:
        """
        匯出 JSON 報告

        Args:
            report: 編輯報告
            output_path: 輸出路徑
            pretty: 是否美化輸出
        """
        data = {
            "version": "1.0",
            "generated_at": datetime.now().isoformat(),
            "input": str(report.input_path),
            "output": str(report.output_path),
            "original_duration": report.original_duration,
            "edited_duration": report.edited_duration,
            "removed_duration": report.original_duration - report.edited_duration,
            "reduction_percent": (
                (report.original_duration - report.edited_duration)
                / report.original_duration * 100
                if report.original_duration > 0 else 0
            ),
            "edit_count": len(report.edits),
            "edits": [e.to_dict() for e in report.edits],
            "statistics": ReportExporter._compute_statistics(report)
        }

        output_path.parent.mkdir(parents=True, exist_ok=True)

        indent = 2 if pretty else None
        output_path.write_text(
            json.dumps(data, ensure_ascii=False, indent=indent),
            encoding="utf-8"
        )

    @staticmethod
    def _compute_statistics(report: EditReport) -> dict:
        """計算統計資訊"""
        stats = {
            "by_reason": {},
            "total_removed_duration": 0.0,
        }

        for edit in report.edits:
            reason = edit.reason
            duration = edit.original_end - edit.original_start

            if reason not in stats["by_reason"]:
                stats["by_reason"][reason] = {
                    "count": 0,
                    "duration": 0.0
                }

            stats["by_reason"][reason]["count"] += 1
            stats["by_reason"][reason]["duration"] += duration
            stats["total_removed_duration"] += duration

        return stats

    @staticmethod
    def to_edl(
        report: EditReport,
        output_path: Path,
        fps: float = 30.0,
        title: Optional[str] = None
    ) -> None:
        """
        匯出 EDL 檔案 (供 DAW 使用)

        EDL (Edit Decision List) 格式可被 DaVinci Resolve、
        Adobe Premiere、Pro Tools 等軟體讀取。

        Args:
            report: 編輯報告
            output_path: 輸出路徑
            fps: 影格率（用於時間碼轉換）
            title: EDL 標題
        """
        lines = []

        # EDL 標頭
        edl_title = title or report.input_path.stem
        lines.append(f"TITLE: {edl_title}")
        lines.append(f"FCM: NON-DROP FRAME")
        lines.append("")

        # 計算保留的區間
        keep_regions = ReportExporter._compute_keep_regions(report)

        # 生成 EDL 事件
        for i, (start, end) in enumerate(keep_regions, 1):
            event_num = f"{i:03d}"
            reel = "AX"  # Audio eXternal

            # 轉換時間碼
            src_in = ReportExporter._seconds_to_timecode(start, fps)
            src_out = ReportExporter._seconds_to_timecode(end, fps)

            # 計算記錄時間碼（累計時間）
            rec_start = sum(
                keep_regions[j][1] - keep_regions[j][0]
                for j in range(i - 1)
            )
            rec_end = rec_start + (end - start)

            rec_in = ReportExporter._seconds_to_timecode(rec_start, fps)
            rec_out = ReportExporter._seconds_to_timecode(rec_end, fps)

            # EDL 行格式
            line = f"{event_num}  {reel}       AA/V  C        {src_in} {src_out} {rec_in} {rec_out}"
            lines.append(line)

            # 檔案名稱註解
            lines.append(f"* FROM CLIP NAME: {report.input_path.name}")
            lines.append("")

        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text("\n".join(lines), encoding="utf-8")

    @staticmethod
    def _compute_keep_regions(report: EditReport) -> list:
        """計算保留的區間"""
        if not report.edits:
            return [(0.0, report.original_duration)]

        # 排序編輯
        sorted_edits = sorted(report.edits, key=lambda e: e.original_start)

        regions = []
        last_end = 0.0

        for edit in sorted_edits:
            if edit.original_start > last_end:
                regions.append((last_end, edit.original_start))
            last_end = edit.original_end

        # 最後一段
        if last_end < report.original_duration:
            regions.append((last_end, report.original_duration))

        return regions

    @staticmethod
    def _seconds_to_timecode(seconds: float, fps: float = 30.0) -> str:
        """
        將秒數轉換為時間碼格式 (HH:MM:SS:FF)

        Args:
            seconds: 秒數
            fps: 影格率

        Returns:
            時間碼字串
        """
        total_frames = int(seconds * fps)

        frames = total_frames % int(fps)
        total_seconds = total_frames // int(fps)

        secs = total_seconds % 60
        total_minutes = total_seconds // 60

        mins = total_minutes % 60
        hours = total_minutes // 60

        return f"{hours:02d}:{mins:02d}:{secs:02d}:{frames:02d}"

    @staticmethod
    def to_markers(
        report: EditReport,
        output_path: Path,
        format: str = "csv"
    ) -> None:
        """
        匯出標記檔案（可用於 Audacity、Reaper 等）

        Args:
            report: 編輯報告
            output_path: 輸出路徑
            format: 輸出格式 ("csv" 或 "txt")
        """
        output_path.parent.mkdir(parents=True, exist_ok=True)

        if format == "csv":
            lines = ["start,end,label,reason"]
            for edit in report.edits:
                # 處理文字中的逗號和換行
                text = edit.text.replace(",", ";").replace("\n", " ")
                lines.append(
                    f"{edit.original_start:.3f},{edit.original_end:.3f},"
                    f"\"{text}\",{edit.reason}"
                )
            output_path.write_text("\n".join(lines), encoding="utf-8")

        else:  # txt (Audacity label format)
            lines = []
            for edit in report.edits:
                text = edit.text.replace("\t", " ").replace("\n", " ")
                lines.append(
                    f"{edit.original_start:.6f}\t{edit.original_end:.6f}\t"
                    f"[{edit.reason}] {text}"
                )
            output_path.write_text("\n".join(lines), encoding="utf-8")
