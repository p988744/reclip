import Foundation
import SwiftUI
import SwiftData
import ReclipCore

/// 主內容視圖模型
@MainActor
public class ContentViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published public var projects: [Project] = []
    @Published public var selectedProject: Project?

    @Published public var isProcessing: Bool = false
    @Published public var progress: Double = 0
    @Published public var progressLabel: String = ""

    @Published public var waveformSamples: [Float] = []
    @Published public var currentTime: TimeInterval = 0

    @Published public var transcript: TranscriptResult?
    @Published public var analysisResult: AnalysisResult?
    @Published public var editReport: EditReport?

    @Published public var showSettings: Bool = false
    @Published public var showFileImporter: Bool = false

    @Published public var error: Error?
    @Published public var showError: Bool = false

    // MARK: - Dependencies

    private var modelContext: ModelContext?

    // MARK: - Initialization

    public init() {
        // 初始化時載入專案
        loadProjects()
    }

    // MARK: - Project Management

    public func loadProjects() {
        // 實際實作會從 SwiftData 載入
        // 這裡先用模擬資料
        projects = []
    }

    public func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task {
                await importAudio(from: url)
            }

        case .failure(let error):
            self.error = error
            self.showError = true
        }
    }

    public func importAudio(from url: URL) async {
        do {
            // 開始存取安全範圍資源
            guard url.startAccessingSecurityScopedResource() else {
                throw ImportError.accessDenied
            }
            defer { url.stopAccessingSecurityScopedResource() }

            // 建立專案
            let project = Project(
                name: url.deletingPathExtension().lastPathComponent,
                audioFileName: url.lastPathComponent
            )

            // 載入音訊資訊
            // TODO: 使用 AudioEditor 取得實際資訊
            project.duration = 0
            project.sampleRate = 48000
            project.channels = 1

            // 複製到 iCloud 容器
            // TODO: 實際複製檔案

            projects.append(project)
            selectedProject = project

            // 載入波形
            await loadWaveform(for: project)

        } catch {
            self.error = error
            self.showError = true
        }
    }

    // MARK: - Processing

    public func transcribe() async {
        guard let project = selectedProject else { return }

        isProcessing = true
        progressLabel = "轉錄中..."
        progress = 0

        defer {
            isProcessing = false
            progress = 0
            progressLabel = ""
        }

        do {
            project.status = .transcribing

            // TODO: 使用 WhisperKit 進行轉錄
            // let provider = WhisperKitProvider()
            // transcript = try await provider.transcribe(...)

            // 模擬進度
            for i in 1...10 {
                try await Task.sleep(for: .milliseconds(200))
                progress = Double(i) / 10.0
            }

            // 模擬結果
            transcript = TranscriptResult(
                segments: [
                    Segment(text: "這是一段測試文字", start: 0, end: 5),
                    Segment(text: "嗯 就是說 這個功能很棒", start: 5, end: 10),
                ],
                language: "zh",
                duration: project.duration
            )

            project.transcript = transcript
            project.status = .transcribed

        } catch {
            project.status = .failed
            self.error = error
            self.showError = true
        }
    }

    public func analyze() async {
        guard let project = selectedProject,
              let transcript = transcript else { return }

        isProcessing = true
        progressLabel = "分析中..."
        progress = 0

        defer {
            isProcessing = false
            progress = 0
            progressLabel = ""
        }

        do {
            project.status = .analyzing

            // TODO: 使用 LLM Provider 進行分析
            // let provider = ClaudeProvider(apiKey: settings.apiKey)
            // analysisResult = try await provider.analyze(transcript: transcript)

            // 模擬進度
            for i in 1...10 {
                try await Task.sleep(for: .milliseconds(300))
                progress = Double(i) / 10.0
            }

            // 模擬結果
            analysisResult = AnalysisResult(
                removals: [
                    Removal(start: 5.0, end: 5.5, reason: .filler, text: "嗯"),
                    Removal(start: 5.5, end: 6.2, reason: .filler, text: "就是說"),
                ],
                originalDuration: project.duration
            )

            project.analysis = analysisResult
            project.status = .analyzed

        } catch {
            project.status = .failed
            self.error = error
            self.showError = true
        }
    }

    public func edit() async {
        guard let project = selectedProject,
              let analysis = analysisResult else { return }

        isProcessing = true
        progressLabel = "剪輯中..."
        progress = 0

        defer {
            isProcessing = false
            progress = 0
            progressLabel = ""
        }

        do {
            project.status = .editing

            // TODO: 使用 AudioEditor 進行剪輯
            // let editor = AudioEditor()
            // editReport = try await editor.edit(...)

            // 模擬進度
            for i in 1...10 {
                try await Task.sleep(for: .milliseconds(150))
                progress = Double(i) / 10.0
            }

            // 模擬結果
            editReport = EditReport(
                inputURL: URL(fileURLWithPath: "/input.wav"),
                outputURL: URL(fileURLWithPath: "/output.wav"),
                originalDuration: project.duration,
                editedDuration: project.duration - analysis.removedDuration,
                edits: analysis.removals.map {
                    AppliedEdit(
                        originalStart: $0.start,
                        originalEnd: $0.end,
                        reason: $0.reason,
                        text: $0.text
                    )
                }
            )

            project.editReport = editReport
            project.status = .completed

        } catch {
            project.status = .failed
            self.error = error
            self.showError = true
        }
    }

    // MARK: - Waveform

    private func loadWaveform(for project: Project) async {
        // TODO: 從音訊檔案載入波形資料
        // 這裡用模擬資料
        waveformSamples = (0..<1000).map { i in
            let t = Float(i) / 1000
            return sin(t * 50) * (0.3 + 0.7 * sin(t * 5)) * Float.random(in: 0.8...1.0)
        }
    }
}

// MARK: - Errors

enum ImportError: LocalizedError {
    case accessDenied
    case invalidFormat
    case copyFailed

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "無法存取檔案"
        case .invalidFormat:
            return "不支援的音訊格式"
        case .copyFailed:
            return "複製檔案失敗"
        }
    }
}
