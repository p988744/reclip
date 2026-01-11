import Foundation
import SwiftUI
import SwiftData
import ReclipCore
import ReclipASR

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
    @Published public var waveformDuration: TimeInterval = 0
    @Published public var isLoadingWaveform: Bool = false

    @Published public var transcript: TranscriptResult?
    @Published public var analysisResult: AnalysisResult?
    @Published public var editReport: EditReport?

    @Published public var showFileImporter: Bool = false

    @Published public var error: Error?
    @Published public var showError: Bool = false

    // MARK: - Audio Player Properties

    @Published public private(set) var isPlaying: Bool = false
    @Published public private(set) var currentTime: TimeInterval = 0
    @Published public private(set) var duration: TimeInterval = 0
    @Published public var playbackRate: Float = 1.0 {
        didSet {
            audioPlayer.playbackRate = playbackRate
        }
    }
    @Published public var volume: Float = 1.0 {
        didSet {
            audioPlayer.volume = volume
        }
    }
    @Published public private(set) var isAudioLoaded: Bool = false

    // MARK: - ASR Properties

    @Published public private(set) var isModelLoaded: Bool = false
    @Published public private(set) var isLoadingModel: Bool = false
    @Published public var selectedLanguage: String = "zh"

    // MARK: - Edit Regions

    @Published public var editRegions: [EditRegion] = []
    @Published public var selectedEditRegionID: UUID?

    // MARK: - Dependencies

    private var modelContext: ModelContext?
    private let audioPlayer = AudioPlayer()
    private var currentAudioURL: URL?
    private let asrProvider: WhisperKitProvider

    // MARK: - Initialization

    public init(modelName: String = "large-v3") {
        self.asrProvider = WhisperKitProvider(modelName: modelName)
        setupAudioPlayerBindings()
        loadProjects()
    }

    // MARK: - Audio Player Setup

    private func setupAudioPlayerBindings() {
        audioPlayer.onTimeUpdate = { [weak self] time in
            Task { @MainActor in
                self?.currentTime = time
            }
        }
    }

    // MARK: - Project Management

    public func loadProjects() {
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
            guard url.startAccessingSecurityScopedResource() else {
                throw ImportError.accessDenied
            }
            defer { url.stopAccessingSecurityScopedResource() }

            // 建立專案
            let project = Project(
                name: url.deletingPathExtension().lastPathComponent,
                audioFileName: url.lastPathComponent
            )

            // 取得音訊資訊
            let audioEditor = AudioEditor()
            let audioInfo = try await audioEditor.getAudioInfo(url: url)

            project.duration = audioInfo.duration
            project.sampleRate = audioInfo.sampleRate
            project.channels = audioInfo.channelCount

            // 儲存 URL（實際應用中會複製到 iCloud 容器）
            currentAudioURL = url

            projects.append(project)
            selectedProject = project

            // 載入音訊和波形
            await loadAudio(from: url)

        } catch {
            self.error = error
            self.showError = true
        }
    }

    // MARK: - Audio Loading

    /// 載入音訊檔案
    public func loadAudio(from url: URL) async {
        do {
            currentAudioURL = url

            // 載入播放器
            try await audioPlayer.load(url: url)
            isAudioLoaded = audioPlayer.isLoaded
            duration = audioPlayer.duration

            // 載入波形
            await loadWaveform(from: url)

        } catch {
            self.error = error
            self.showError = true
        }
    }

    /// 從 URL 載入波形
    public func loadWaveform(from url: URL) async {
        isLoadingWaveform = true
        progressLabel = "載入波形中..."

        do {
            // 先快速載入縮圖波形
            let thumbnail = try await WaveformGenerator.generateThumbnail(from: url)
            waveformSamples = thumbnail.peaks
            waveformDuration = thumbnail.duration

            // 背景載入詳細波形
            let detailed = try await WaveformGenerator.generate(
                from: url,
                resolution: .standard,
                useCache: true
            ) { [weak self] progress in
                Task { @MainActor in
                    self?.progress = progress
                }
            }

            waveformSamples = detailed.peaks
            waveformDuration = detailed.duration
            progress = 0
            progressLabel = ""

        } catch {
            self.error = error
            self.showError = true
        }

        isLoadingWaveform = false
    }

    // MARK: - Playback Controls

    /// 播放
    public func play() {
        audioPlayer.play()
        isPlaying = audioPlayer.isPlaying
    }

    /// 暫停
    public func pause() {
        audioPlayer.pause()
        isPlaying = audioPlayer.isPlaying
    }

    /// 切換播放/暫停
    public func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    /// 跳轉到指定時間
    public func seek(to time: TimeInterval) async {
        await audioPlayer.seek(to: time)
        currentTime = time
    }

    /// 快進
    public func skipForward(seconds: TimeInterval = 5) async {
        await audioPlayer.skipForward(seconds: seconds)
        currentTime = audioPlayer.currentTime
    }

    /// 快退
    public func skipBackward(seconds: TimeInterval = 5) async {
        await audioPlayer.skipBackward(seconds: seconds)
        currentTime = audioPlayer.currentTime
    }

    /// 停止播放
    public func stop() {
        audioPlayer.stop()
        isPlaying = false
    }

    // MARK: - Edit Operations

    /// 刪除選取的區間
    public func deleteRegion(_ region: EditRegion) {
        editRegions.removeAll { $0.id == region.id }
        if selectedEditRegionID == region.id {
            selectedEditRegionID = nil
        }
    }

    /// 移動補上（將刪除區間後的內容向前移動填補空隙）
    public func moveAndFillRegion(_ region: EditRegion) {
        // 將區間標記為待處理的移除區域
        // 實際的音訊處理會在執行 applyEdits() 時進行
        if let index = editRegions.firstIndex(where: { $0.id == region.id }) {
            var updatedRegion = editRegions[index]
            updatedRegion.isSelected = true
            editRegions[index] = updatedRegion
        }
    }

    /// 套用所有編輯
    public func applyEdits() async {
        guard let project = selectedProject,
              let audioURL = currentAudioURL,
              !editRegions.isEmpty else { return }

        isProcessing = true
        progressLabel = "套用編輯中..."
        progress = 0

        do {
            // 建立 Removal 物件
            let removals = editRegions.map { region in
                Removal(
                    start: region.start,
                    end: region.end,
                    reason: .filler, // 手動編輯標記為 filler
                    text: "[手動刪除]"
                )
            }

            let analysis = AnalysisResult(
                removals: removals,
                originalDuration: duration
            )

            // 輸出路徑
            let outputDir = FileManager.default.temporaryDirectory
            let outputURL = outputDir.appendingPathComponent("edited_\(project.audioFileName)")

            // 執行編輯
            let editor = AudioEditor()
            let report = try await editor.edit(
                inputURL: audioURL,
                outputURL: outputURL,
                analysis: analysis
            ) { [weak self] progress in
                Task { @MainActor in
                    self?.progress = progress
                }
            }

            editReport = report
            project.editReport = report
            project.status = .completed

            // 清除編輯區域
            editRegions.removeAll()
            selectedEditRegionID = nil

            // 重新載入編輯後的音訊
            await loadAudio(from: outputURL)

        } catch {
            self.error = error
            self.showError = true
        }

        isProcessing = false
        progress = 0
        progressLabel = ""
    }

    // MARK: - ASR Model Management

    /// 載入 ASR 模型
    public func loadASRModel() async {
        guard !isModelLoaded && !isLoadingModel else { return }

        isLoadingModel = true
        isProcessing = true
        progressLabel = "下載 WhisperKit 模型中..."
        progress = 0

        do {
            try await asrProvider.loadModel { [weak self] downloadProgress in
                Task { @MainActor in
                    self?.progress = downloadProgress
                    if downloadProgress < 0.8 {
                        self?.progressLabel = "下載模型中... \(Int(downloadProgress / 0.8 * 100))%"
                    } else {
                        self?.progressLabel = "載入模型中..."
                    }
                }
            }
            isModelLoaded = true
        } catch {
            self.error = error
            self.showError = true
        }

        isLoadingModel = false
        isProcessing = false
        progressLabel = ""
        progress = 0
    }

    /// 卸載 ASR 模型（釋放記憶體）
    public func unloadASRModel() {
        asrProvider.unloadModel()
        isModelLoaded = false
    }

    /// 支援的語言列表
    public var supportedLanguages: [String] {
        asrProvider.supportedLanguages
    }

    // MARK: - Processing

    public func transcribe() async {
        guard let project = selectedProject,
              let audioURL = currentAudioURL else { return }

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

            // 確保模型已載入
            if !isModelLoaded {
                try await asrProvider.loadModelWithDetails { [weak self] downloadProgress in
                    Task { @MainActor in
                        self?.progress = downloadProgress.fractionCompleted
                        self?.progressLabel = downloadProgress.formattedProgress
                    }
                }
                isModelLoaded = true
            }

            progressLabel = "轉錄中..."
            progress = 0

            // 使用 WhisperKit 進行轉錄
            transcript = try await asrProvider.transcribe(
                url: audioURL,
                language: selectedLanguage,
                includeWordTimestamps: true
            ) { [weak self] transcribeProgress in
                Task { @MainActor in
                    self?.progress = transcribeProgress
                    self?.progressLabel = "轉錄中... \(Int(transcribeProgress * 100))%"
                }
            }

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
              transcript != nil else { return }

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
              let analysis = analysisResult,
              let audioURL = currentAudioURL else { return }

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

            // 輸出路徑
            let outputDir = FileManager.default.temporaryDirectory
            let outputURL = outputDir.appendingPathComponent("edited_\(project.audioFileName)")

            // 使用 AudioEditor 進行剪輯
            let editor = AudioEditor()
            editReport = try await editor.edit(
                inputURL: audioURL,
                outputURL: outputURL,
                analysis: analysis
            ) { [weak self] progress in
                Task { @MainActor in
                    self?.progress = progress
                }
            }

            project.editReport = editReport
            project.status = .completed

            // 重新載入編輯後的音訊
            await loadAudio(from: outputURL)

        } catch {
            project.status = .failed
            self.error = error
            self.showError = true
        }
    }

    // MARK: - Cleanup

    public func cleanup() {
        audioPlayer.unload()
        isAudioLoaded = false
        currentAudioURL = nil
        unloadASRModel()
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
