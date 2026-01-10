import SwiftUI
import ReclipCore

/// 主內容視圖
public struct ContentView: View {
    @StateObject private var viewModel = ContentViewModel()
    @Namespace private var namespace

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
                ProjectDetailView(project: project, viewModel: viewModel)
            } else {
                emptyState
            }
        }
        .toolbar {
            toolbarContent
        }
        .sheet(isPresented: $viewModel.showSettings) {
            SettingsView()
        }
        .fileImporter(
            isPresented: $viewModel.showFileImporter,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { result in
            viewModel.handleFileImport(result)
        }
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

            Button("設定", systemImage: "gearshape") {
                viewModel.showSettings = true
            }
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
        .navigationTitle(project.name)
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

// MARK: - Preview

#Preview {
    ContentView()
        .frame(width: 1000, height: 700)
}
