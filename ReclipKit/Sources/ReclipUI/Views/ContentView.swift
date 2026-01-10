import SwiftUI
import ReclipCore
#if os(macOS)
import AppKit
#endif

/// 主內容視圖
public struct ContentView: View {
    @StateObject private var viewModel = ContentViewModel()
    @Namespace private var namespace

    @State private var selectedTab: EditorTab = .waveform

    enum EditorTab: String, CaseIterable {
        case waveform = "波形編輯"
        case transcript = "逐字稿"
        case analysis = "AI 分析"

        var icon: String {
            switch self {
            case .waveform: return "waveform"
            case .transcript: return "text.bubble"
            case .analysis: return "sparkles"
            }
        }
    }

    public init() {}

    public var body: some View {
        NavigationSplitView {
            // 側邊欄：專案列表
            ProjectSidebar(
                projects: viewModel.projects,
                selectedProject: $viewModel.selectedProject
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 300)
        } detail: {
            // 主內容
            if let project = viewModel.selectedProject {
                projectDetailContent(project)
            } else {
                emptyState
            }
        }
        .toolbar {
            toolbarContent
        }
        .fileImporter(
            isPresented: $viewModel.showFileImporter,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { result in
            viewModel.handleFileImport(result)
        }
        .alert("錯誤", isPresented: $viewModel.showError) {
            Button("確定", role: .cancel) {}
        } message: {
            Text(viewModel.error?.localizedDescription ?? "發生未知錯誤")
        }
    }

    // MARK: - Project Detail Content

    @ViewBuilder
    private func projectDetailContent(_ project: Project) -> some View {
        VStack(spacing: 0) {
            // 頂部標籤選擇
            tabPicker

            Divider()

            // 內容區
            switch selectedTab {
            case .waveform:
                AudioEditorView(viewModel: viewModel)
            case .transcript:
                TranscriptTab(viewModel: viewModel)
            case .analysis:
                ProjectDetailView(project: project, viewModel: viewModel)
            }
        }
        .navigationTitle(project.name)
    }

    // MARK: - Tab Picker

    private var tabPicker: some View {
        HStack(spacing: 0) {
            ForEach(EditorTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: tab.icon)
                        Text(tab.rawValue)
                    }
                    .font(.subheadline.weight(selectedTab == tab ? .semibold : .regular))
                    .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background {
                        if selectedTab == tab {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.ultraThinMaterial)
                                .matchedGeometryEffect(id: "tabIndicator", in: namespace)
                        }
                    }
                }
                .buttonStyle(.borderless)
            }

            Spacer()

            // 迷你播放控制
            if viewModel.isAudioLoaded {
                CompactPlaybackControls(
                    isPlaying: Binding(
                        get: { viewModel.isPlaying },
                        set: { _ in }
                    ),
                    onToggle: { viewModel.togglePlayPause() },
                    onSkipBackward: { Task { await viewModel.skipBackward() } },
                    onSkipForward: { Task { await viewModel.skipForward() } }
                )

                MiniTimeDisplay(
                    currentTime: viewModel.currentTime,
                    duration: viewModel.duration
                )
                .padding(.leading, 12)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 24) {
            Image(systemName: "waveform.circle")
                .font(.system(size: 80))
                .foregroundStyle(.tertiary)
                .glassEffect(.regular, in: .circle)

            VStack(spacing: 8) {
                Text("開始使用 Reclip")
                    .font(.title2.weight(.semibold))

                Text("拖放音訊檔案或點擊匯入按鈕")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button("匯入音訊", systemImage: "plus.circle") {
                viewModel.showFileImporter = true
            }
            .buttonStyle(.reclipGlass(tint: .accentColor))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            // 動態背景
            MeshGradient(
                width: 3,
                height: 3,
                points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.5], [0.5, 0.5], [1, 0.5],
                    [0, 1], [0.5, 1], [1, 1]
                ],
                colors: [
                    .blue.opacity(0.3), .purple.opacity(0.2), .blue.opacity(0.3),
                    .purple.opacity(0.2), .clear, .purple.opacity(0.2),
                    .blue.opacity(0.3), .purple.opacity(0.2), .blue.opacity(0.3)
                ]
            )
            .ignoresSafeArea()
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button("匯入", systemImage: "plus") {
                viewModel.showFileImporter = true
            }

            #if os(macOS)
            Button("設定", systemImage: "gearshape") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            .keyboardShortcut(",", modifiers: .command)
            #endif
        }
    }
}

// MARK: - Project Sidebar

struct ProjectSidebar: View {
    let projects: [Project]
    @Binding var selectedProject: Project?

    var body: some View {
        List(selection: $selectedProject) {
            Section("專案") {
                ForEach(projects) { project in
                    ProjectRow(project: project)
                        .tag(project)
                }
            }
        }
        .listStyle(.sidebar)
    }
}

struct ProjectRow: View {
    let project: Project

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: project.status.icon)
                .foregroundStyle(statusColor(for: project.status.colorName))

            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.body)

                Text(project.formattedDuration)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func statusColor(for colorName: String) -> Color {
        switch colorName {
        case "blue": return .blue
        case "orange": return .orange
        case "green": return .green
        case "red": return .red
        case "secondary": return .secondary
        default: return .primary
        }
    }
}

// MARK: - Project Detail View

struct ProjectDetailView: View {
    let project: Project
    @ObservedObject var viewModel: ContentViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // 音訊資訊卡片
                audioInfoCard

                // 波形視圖
                waveformSection

                // 處理控制
                processingControls

                // 分析結果
                if let analysis = viewModel.analysisResult {
                    analysisResultSection(analysis)
                }
            }
            .padding()
        }
    }

    private var audioInfoCard: some View {
        GlassCard(title: "音訊資訊") {
            HStack(spacing: 32) {
                infoItem(label: "時長", value: project.formattedDuration)
                infoItem(label: "取樣率", value: "\(Int(project.sampleRate)) Hz")
                infoItem(label: "聲道", value: "\(project.channels)")

                Spacer()

                if let reduction = viewModel.editReport?.reductionPercent {
                    VStack(alignment: .trailing) {
                        Text("-\(String(format: "%.1f", reduction))%")
                            .font(.title.weight(.bold))
                            .foregroundStyle(.green)
                        Text("時間節省")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func infoItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body.monospacedDigit())
        }
    }

    private var waveformSection: some View {
        GlassCard(title: "波形") {
            WaveformView(
                samples: viewModel.waveformSamples,
                removals: viewModel.analysisResult?.removals ?? [],
                currentTime: viewModel.currentTime,
                duration: project.duration
            )
        }
    }

    private var processingControls: some View {
        HStack(spacing: 16) {
            Button("轉錄", systemImage: "waveform") {
                Task { await viewModel.transcribe() }
            }
            .buttonStyle(.reclipGlass)
            .disabled(viewModel.isProcessing)

            Button("分析", systemImage: "sparkles") {
                Task { await viewModel.analyze() }
            }
            .buttonStyle(.reclipGlass)
            .disabled(viewModel.transcript == nil || viewModel.isProcessing)

            Button("剪輯", systemImage: "scissors") {
                Task { await viewModel.edit() }
            }
            .buttonStyle(.reclipGlass(tint: .green))
            .disabled(viewModel.analysisResult == nil || viewModel.isProcessing)

            Spacer()

            if viewModel.isProcessing {
                GlassProgress(
                    value: viewModel.progress,
                    label: viewModel.progressLabel
                )
                .frame(width: 200)
            }
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: GlassStyle.cornerRadius)
                .fill(.ultraThinMaterial)
        }
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: GlassStyle.cornerRadius))
    }

    private func analysisResultSection(_ analysis: AnalysisResult) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // 統計
            HStack(spacing: 24) {
                ForEach(analysis.statistics.sorted(by: { $0.key.rawValue < $1.key.rawValue }), id: \.key) { reason, count in
                    statBadge(reason: reason, count: count)
                }

                Spacer()

                VStack(alignment: .trailing) {
                    Text(formatDuration(analysis.removedDuration))
                        .font(.title2.weight(.semibold).monospacedDigit())
                    Text("將移除")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // 移除項目列表
            GlassCard(title: "待移除區間 (\(analysis.removals.count))") {
                LazyVStack(spacing: 8) {
                    ForEach(analysis.removals.prefix(20)) { removal in
                        removalRow(removal)
                    }

                    if analysis.removals.count > 20 {
                        Text("還有 \(analysis.removals.count - 20) 項...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                    }
                }
            }
        }
    }

    private func statBadge(reason: RemovalReason, count: Int) -> some View {
        HStack(spacing: 8) {
            GlassBadge(reason.displayName, color: colorForReason(reason))
            Text("\(count)")
                .font(.headline.monospacedDigit())
        }
    }

    private func removalRow(_ removal: Removal) -> some View {
        HStack {
            Text(String(format: "%.2f - %.2fs", removal.start, removal.end))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)

            GlassBadge(removal.reason.displayName, color: colorForReason(removal.reason))

            Text(removal.text)
                .font(.body)
                .lineLimit(1)

            Spacer()

            Text(String(format: "%.0f%%", removal.confidence * 100))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func colorForReason(_ reason: RemovalReason) -> Color {
        switch reason {
        case .filler: return .orange
        case .repair: return .purple
        case .restart: return .blue
        case .mouthNoise: return .pink
        case .longPause: return .gray
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Transcript Tab

struct TranscriptTab: View {
    @ObservedObject var viewModel: ContentViewModel

    var body: some View {
        VStack(spacing: 16) {
            if let transcript = viewModel.transcript {
                // 逐字稿顯示
                TranscriptView(
                    transcript: transcript,
                    currentTime: viewModel.currentTime,
                    onSeek: { time in
                        Task {
                            await viewModel.seek(to: time)
                        }
                    }
                )
            } else {
                // 尚無逐字稿
                transcriptionEmptyState
            }
        }
        .padding()
    }

    private var transcriptionEmptyState: some View {
        VStack(spacing: 24) {
            Image(systemName: "text.bubble")
                .font(.system(size: 60))
                .foregroundStyle(.tertiary)

            VStack(spacing: 8) {
                Text("尚無逐字稿")
                    .font(.title2.weight(.semibold))

                Text("點擊下方按鈕開始轉錄音訊")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // 語言選擇
            HStack(spacing: 12) {
                Text("語言：")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Picker("語言", selection: $viewModel.selectedLanguage) {
                    ForEach(viewModel.supportedLanguages, id: \.self) { lang in
                        Text(languageName(lang)).tag(lang)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 150)
            }

            // 轉錄按鈕
            Button {
                Task {
                    await viewModel.transcribe()
                }
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isProcessing {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "waveform")
                    }
                    Text(viewModel.isProcessing ? "處理中..." : "開始轉錄")
                }
            }
            .buttonStyle(.reclipGlass(tint: .blue))
            .disabled(viewModel.isProcessing || !viewModel.isAudioLoaded)

            // 進度條
            if viewModel.isProcessing {
                VStack(spacing: 8) {
                    ProgressView(value: viewModel.progress)
                        .frame(width: 300)

                    Text(viewModel.progressLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // 模型狀態
            if !viewModel.isProcessing && !viewModel.isModelLoaded {
                Text("首次轉錄會自動下載 WhisperKit 模型（約 1GB）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func languageName(_ code: String) -> String {
        let names: [String: String] = [
            "zh": "中文",
            "en": "English",
            "ja": "日本語",
            "ko": "한국어",
            "es": "Español",
            "fr": "Français",
            "de": "Deutsch",
            "it": "Italiano",
            "pt": "Português",
            "ru": "Русский",
            "ar": "العربية",
            "hi": "हिन्दी"
        ]
        return names[code] ?? code
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .frame(width: 1000, height: 700)
}
