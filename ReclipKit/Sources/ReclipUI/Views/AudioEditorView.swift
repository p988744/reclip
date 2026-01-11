import SwiftUI
import ReclipCore

/// 音訊編輯視圖 - 整合播放、波形、手動剪輯功能
public struct AudioEditorView: View {
    @ObservedObject var viewModel: ContentViewModel

    @State private var showExportSheet: Bool = false
    @State private var showUndoConfirm: Bool = false

    public init(viewModel: ContentViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // 頂部工具列
            editorToolbar

            Divider()

            // 主編輯區
            ScrollView {
                VStack(spacing: 16) {
                    // 波形編輯器
                    waveformEditorSection

                    // 播放控制
                    playbackControlsSection

                    // 編輯區域列表
                    if !viewModel.editRegions.isEmpty {
                        editRegionsListSection
                    }

                    // 編輯報告
                    if let report = viewModel.editReport {
                        editReportSection(report)
                    }
                }
                .padding()
            }
        }
        .alert("確認復原", isPresented: $showUndoConfirm) {
            Button("取消", role: .cancel) {}
            Button("復原全部", role: .destructive) {
                viewModel.editRegions.removeAll()
                viewModel.selectedEditRegionID = nil
            }
        } message: {
            Text("確定要清除所有編輯區域嗎？此操作無法復原。")
        }
        .sheet(isPresented: $showExportSheet) {
            ExportOptionsSheet(viewModel: viewModel)
        }
    }

    // MARK: - Editor Toolbar

    private var editorToolbar: some View {
        HStack(spacing: 16) {
            // 標題
            VStack(alignment: .leading, spacing: 2) {
                Text("音訊編輯器")
                    .font(.headline)

                if let project = viewModel.selectedProject {
                    Text(project.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // 載入狀態
            if viewModel.isLoadingWaveform {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("載入波形...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // 編輯操作按鈕
            if !viewModel.editRegions.isEmpty {
                Button("復原全部", systemImage: "arrow.uturn.backward") {
                    showUndoConfirm = true
                }
                .buttonStyle(.borderless)

                Button("套用編輯", systemImage: "checkmark.circle") {
                    Task {
                        await viewModel.applyEdits()
                    }
                }
                .buttonStyle(.reclipGlass(tint: .green))
                .disabled(viewModel.isProcessing)
            }

            // 匯出按鈕
            Button("匯出", systemImage: "square.and.arrow.up") {
                showExportSheet = true
            }
            .buttonStyle(.borderless)
            .disabled(!viewModel.isAudioLoaded)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    // MARK: - Waveform Editor Section

    private var waveformEditorSection: some View {
        GlassCard(title: "波形編輯") {
            if viewModel.waveformSamples.isEmpty {
                emptyWaveformPlaceholder
            } else {
                WaveformEditor(
                    samples: viewModel.waveformSamples,
                    duration: viewModel.duration,
                    currentTime: Binding(
                        get: { viewModel.currentTime },
                        set: { newTime in
                            Task { await viewModel.seek(to: newTime) }
                        }
                    ),
                    editRegions: $viewModel.editRegions,
                    selectedRegionID: $viewModel.selectedEditRegionID,
                    onSeek: { time in
                        Task { await viewModel.seek(to: time) }
                    },
                    onDelete: { region in
                        viewModel.deleteRegion(region)
                    },
                    onMoveAndFill: { region in
                        viewModel.moveAndFillRegion(region)
                    }
                )
            }
        }
    }

    private var emptyWaveformPlaceholder: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text("載入音訊檔案以顯示波形")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(height: 150)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Playback Controls Section

    private var playbackControlsSection: some View {
        PlaybackControls(
            isPlaying: Binding(
                get: { viewModel.isPlaying },
                set: { _ in }
            ),
            currentTime: Binding(
                get: { viewModel.currentTime },
                set: { newTime in
                    Task { await viewModel.seek(to: newTime) }
                }
            ),
            playbackRate: $viewModel.playbackRate,
            duration: viewModel.duration,
            onPlay: { viewModel.play() },
            onPause: { viewModel.pause() },
            onSeek: { time in await viewModel.seek(to: time) },
            onSkipForward: { await viewModel.skipForward() },
            onSkipBackward: { await viewModel.skipBackward() }
        )
        .disabled(!viewModel.isAudioLoaded)
    }

    // MARK: - Edit Regions List Section

    private var editRegionsListSection: some View {
        GlassCard(title: "編輯區域 (\(viewModel.editRegions.count))") {
            LazyVStack(spacing: 8) {
                ForEach(viewModel.editRegions.sorted(by: { $0.start < $1.start })) { region in
                    editRegionRow(region)
                }
            }
        }
    }

    private func editRegionRow(_ region: EditRegion) -> some View {
        let isSelected = viewModel.selectedEditRegionID == region.id

        return HStack(spacing: 12) {
            // 選取指示器
            Circle()
                .fill(isSelected ? Color.blue : Color.clear)
                .frame(width: 8, height: 8)

            // 時間範圍
            Text("\(formatTime(region.start)) - \(formatTime(region.end))")
                .font(.body.monospacedDigit())

            // 長度
            Text("(\(formatDuration(region.duration)))")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            // 操作按鈕
            Button {
                Task {
                    await viewModel.seek(to: region.start)
                }
            } label: {
                Image(systemName: "play.circle")
            }
            .buttonStyle(.borderless)
            .help("播放此區段")

            Button {
                viewModel.deleteRegion(region)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
            .help("刪除此區段")
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.blue.opacity(0.1) : Color.clear)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.selectedEditRegionID = region.id
        }
    }

    // MARK: - Edit Report Section

    private func editReportSection(_ report: EditReport) -> some View {
        GlassCard(title: "編輯報告") {
            VStack(alignment: .leading, spacing: 12) {
                // 統計資訊
                HStack(spacing: 32) {
                    statItem(
                        label: "原始長度",
                        value: formatDuration(report.originalDuration)
                    )

                    statItem(
                        label: "編輯後長度",
                        value: formatDuration(report.editedDuration)
                    )

                    statItem(
                        label: "節省時間",
                        value: formatDuration(report.removedDuration),
                        highlight: true
                    )

                    statItem(
                        label: "節省比例",
                        value: String(format: "%.1f%%", report.reductionPercent),
                        highlight: true
                    )
                }

                Divider()

                // 編輯詳情
                Text("已套用 \(report.edits.count) 個編輯")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func statItem(label: String, value: String, highlight: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(highlight ? .green : .primary)
        }
    }

    // MARK: - Helpers

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let ms = Int((seconds.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%02d:%02d.%02d", mins, secs, ms)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Export Options Sheet

struct ExportOptionsSheet: View {
    @ObservedObject var viewModel: ContentViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedFormat: ExportFormat = .m4a
    @State private var includeEDL: Bool = false
    @State private var isExporting: Bool = false

    enum ExportFormat: String, CaseIterable {
        case m4a = "M4A (AAC)"
        case wav = "WAV"
        case mp3 = "MP3"

        var fileExtension: String {
            switch self {
            case .m4a: return "m4a"
            case .wav: return "wav"
            case .mp3: return "mp3"
            }
        }
    }

    var body: some View {
        VStack(spacing: 24) {
            // 標題
            Text("匯出選項")
                .font(.title2.weight(.semibold))

            // 格式選擇
            VStack(alignment: .leading, spacing: 8) {
                Text("輸出格式")
                    .font(.subheadline.weight(.medium))

                Picker("格式", selection: $selectedFormat) {
                    ForEach(ExportFormat.allCases, id: \.self) { format in
                        Text(format.rawValue).tag(format)
                    }
                }
                .pickerStyle(.segmented)
            }

            // EDL 選項
            Toggle("同時匯出 EDL 編輯清單", isOn: $includeEDL)

            Spacer()

            // 按鈕
            HStack(spacing: 16) {
                Button("取消") {
                    dismiss()
                }
                .buttonStyle(.borderless)

                Button("匯出") {
                    exportAudio()
                }
                .buttonStyle(.reclipGlass(tint: .blue))
                .disabled(isExporting)
            }
        }
        .padding(24)
        .frame(minWidth: 350, idealWidth: 400, minHeight: 250)
    }

    private func exportAudio() {
        isExporting = true
        // TODO: 實作匯出邏輯
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            isExporting = false
            dismiss()
        }
    }
}

// MARK: - Preview

#Preview {
    AudioEditorView(viewModel: ContentViewModel())
        .frame(width: 900, height: 700)
}
