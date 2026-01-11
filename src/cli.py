"""命令列介面 - Podcast 自動剪輯工具"""

import os
import sys
from pathlib import Path
from typing import Optional, Tuple

import click
from dotenv import load_dotenv
from rich.console import Console
from rich.progress import Progress, SpinnerColumn, TextColumn, BarColumn
from rich.table import Table

from .preprocessor import AudioPreprocessor
from .transcriber import Transcriber, TranscriptResult
from .analyzer import Analyzer, AnalysisResult
from .editor import Editor, EditReport
from .exporter import ReportExporter


# 載入環境變數
load_dotenv()

console = Console()


def format_duration(seconds: float) -> str:
    """格式化時間長度"""
    mins, secs = divmod(int(seconds), 60)
    hours, mins = divmod(mins, 60)
    if hours > 0:
        return f"{hours}:{mins:02d}:{secs:02d}"
    return f"{mins}:{secs:02d}"


def format_percent(value: float) -> str:
    """格式化百分比"""
    return f"{value:.1f}%"


@click.command()
@click.argument('input_files', nargs=-1, type=click.Path(exists=True))
@click.option('-o', '--output', type=click.Path(), help='輸出檔案路徑')
@click.option('--mode', type=click.Choice(['merge', 'first']), default='first',
              help='多軌處理模式')
@click.option('--whisper-model', default='large-v3', help='Whisper 模型大小')
@click.option('--language', default='zh', help='語言代碼')
@click.option('--no-diarization', is_flag=True, help='停用說話者分離')
@click.option('--claude-model', default='claude-sonnet-4-20250514', help='Claude 模型')
@click.option('--crossfade', default=30, type=int, help='Crossfade 毫秒數')
@click.option('--min-confidence', default=0.7, type=float, help='最低信心閾值')
@click.option('--analyze-only', is_flag=True, help='只分析不剪輯')
@click.option('--export-report', type=click.Path(), help='匯出 JSON 報告')
@click.option('--export-edl', type=click.Path(), help='匯出 EDL 檔案')
@click.option('--export-markers', type=click.Path(), help='匯出標記檔案')
@click.option('-v', '--verbose', is_flag=True, help='詳細輸出')
def main(
    input_files: Tuple[str],
    output: Optional[str],
    mode: str,
    whisper_model: str,
    language: str,
    no_diarization: bool,
    claude_model: str,
    crossfade: int,
    min_confidence: float,
    analyze_only: bool,
    export_report: Optional[str],
    export_edl: Optional[str],
    export_markers: Optional[str],
    verbose: bool
):
    """
    Podcast 自動剪輯工具

    使用範例:

    \b
        reclip input.wav -o output.wav
        reclip track1.wav track2.wav --mode merge -o output.wav
        reclip input.wav --analyze-only --export-report report.json
    """
    # 驗證輸入
    if not input_files:
        console.print("[red]錯誤：請提供至少一個輸入檔案[/red]")
        sys.exit(1)

    if not analyze_only and not output:
        # 自動生成輸出檔名
        input_path = Path(input_files[0])
        output = str(input_path.parent / f"{input_path.stem}_edited{input_path.suffix}")

    # 檢查 API keys
    if not os.getenv("ANTHROPIC_API_KEY"):
        console.print("[red]錯誤：請設定 ANTHROPIC_API_KEY 環境變數[/red]")
        sys.exit(1)

    input_paths = [Path(f) for f in input_files]
    output_path = Path(output) if output else None

    try:
        with Progress(
            SpinnerColumn(),
            TextColumn("[progress.description]{task.description}"),
            BarColumn(),
            TextColumn("[progress.percentage]{task.percentage:>3.0f}%"),
            console=console
        ) as progress:
            # Step 1: 預處理
            task1 = progress.add_task("預處理音訊...", total=100)
            preprocessor = AudioPreprocessor()

            # 建立暫存檔案
            temp_path = Path("/tmp/reclip_temp.wav")
            preprocessor.process(input_paths, temp_path, mode=mode)
            progress.update(task1, completed=100)

            if verbose:
                info = preprocessor.get_audio_info(temp_path)
                console.print(f"[dim]音訊長度: {format_duration(info['duration_seconds'])}[/dim]")

            # Step 2: 轉錄
            task2 = progress.add_task("轉錄中...", total=100)
            transcriber = Transcriber(
                model_size=whisper_model,
                language=language,
                hf_token=os.getenv("HF_TOKEN")
            )

            transcript = transcriber.transcribe(
                temp_path,
                diarize=not no_diarization
            )
            progress.update(task2, completed=100)

            if verbose:
                console.print(f"[dim]轉錄完成: {len(transcript.segments)} 段[/dim]")

            # Step 3: 分析
            task3 = progress.add_task("分析中...", total=100)
            analyzer = Analyzer(
                model=claude_model,
                min_confidence=min_confidence
            )

            def update_analysis_progress(current, total):
                progress.update(task3, completed=int(current / total * 100))

            analysis = analyzer.analyze_with_progress(
                transcript,
                progress_callback=update_analysis_progress
            )
            progress.update(task3, completed=100)

            # Step 4: 剪輯（如果需要）
            report = None
            if not analyze_only and output_path:
                task4 = progress.add_task("剪輯中...", total=100)
                editor = Editor(crossfade_ms=crossfade)

                report = editor.edit(temp_path, analysis, output_path)
                progress.update(task4, completed=100)

        # 顯示結果
        _display_results(analysis, report, verbose)

        # 匯出報告
        if report:
            if export_report:
                ReportExporter.to_json(report, Path(export_report))
                console.print(f"[green]JSON 報告已匯出: {export_report}[/green]")

            if export_edl:
                ReportExporter.to_edl(report, Path(export_edl))
                console.print(f"[green]EDL 檔案已匯出: {export_edl}[/green]")

            if export_markers:
                ReportExporter.to_markers(report, Path(export_markers))
                console.print(f"[green]標記檔案已匯出: {export_markers}[/green]")

        # 如果只分析，也輸出分析結果
        if analyze_only and export_report:
            # 建立假的 report 用於匯出
            from .editor import EditReport, AppliedEdit
            fake_report = EditReport(
                input_path=input_paths[0],
                output_path=Path(export_report),
                original_duration=analysis.original_duration,
                edited_duration=analysis.original_duration - analysis.removed_duration,
                edits=[
                    AppliedEdit(
                        original_start=r.start,
                        original_end=r.end,
                        reason=r.reason,
                        text=r.text
                    )
                    for r in analysis.removals
                ]
            )
            ReportExporter.to_json(fake_report, Path(export_report))
            console.print(f"[green]分析報告已匯出: {export_report}[/green]")

        # 清理暫存
        if temp_path.exists():
            temp_path.unlink()

        console.print("\n[green]✓ 完成！[/green]")

    except KeyboardInterrupt:
        console.print("\n[yellow]已取消[/yellow]")
        sys.exit(130)
    except Exception as e:
        console.print(f"[red]錯誤: {e}[/red]")
        if verbose:
            console.print_exception()
        sys.exit(1)


def _display_results(
    analysis: AnalysisResult,
    report: Optional[EditReport],
    verbose: bool
):
    """顯示處理結果"""
    console.print()

    # 統計表格
    table = Table(title="處理結果")
    table.add_column("項目", style="cyan")
    table.add_column("數值", justify="right")

    original_duration = analysis.original_duration
    removed_duration = analysis.removed_duration
    edited_duration = original_duration - removed_duration

    table.add_row("原始長度", format_duration(original_duration))
    table.add_row("移除長度", format_duration(removed_duration))
    table.add_row("輸出長度", format_duration(edited_duration))
    table.add_row("縮減比例", format_percent(
        removed_duration / original_duration * 100 if original_duration > 0 else 0
    ))
    table.add_row("編輯點數", str(len(analysis.removals)))

    console.print(table)

    # 移除類型統計
    if analysis.statistics:
        stats_table = Table(title="移除類型統計")
        stats_table.add_column("類型", style="cyan")
        stats_table.add_column("數量", justify="right")

        type_names = {
            "filler": "語氣詞",
            "repeat": "重複",
            "restart": "重說",
            "mouth_noise": "唇齒音",
            "long_pause": "長停頓",
        }

        for reason, count in analysis.statistics.items():
            if count > 0:
                name = type_names.get(reason, reason)
                stats_table.add_row(name, str(count))

        console.print(stats_table)

    # 詳細編輯列表（僅在 verbose 模式）
    if verbose and analysis.removals:
        detail_table = Table(title="詳細編輯列表")
        detail_table.add_column("時間", style="dim")
        detail_table.add_column("類型")
        detail_table.add_column("內容", max_width=40)
        detail_table.add_column("信心", justify="right")

        for removal in analysis.removals[:20]:  # 只顯示前 20 個
            time_range = f"{removal.start:.2f}s - {removal.end:.2f}s"
            text = removal.text[:40] + "..." if len(removal.text) > 40 else removal.text
            detail_table.add_row(
                time_range,
                removal.reason,
                text,
                f"{removal.confidence:.0%}"
            )

        if len(analysis.removals) > 20:
            detail_table.add_row("...", "...", f"(還有 {len(analysis.removals) - 20} 項)", "...")

        console.print(detail_table)

    # 輸出檔案
    if report and report.output_path:
        console.print(f"\n[green]輸出檔案: {report.output_path}[/green]")


if __name__ == '__main__':
    main()
