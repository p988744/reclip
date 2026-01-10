import SwiftUI
import ReclipCore
import ReclipASR

/// 設定視圖
public struct SettingsView: View {
    @StateObject private var settings = AppSettings.shared

    public init() {}

    public var body: some View {
        TabView {
            // ASR 設定
            ASRSettingsTab(settings: settings)
                .tabItem {
                    Label("語音辨識", systemImage: "waveform")
                }

            // LLM 設定
            LLMSettingsTab(settings: settings)
                .tabItem {
                    Label("AI 分析", systemImage: "sparkles")
                }

            // 編輯器設定
            EditorSettingsTab(settings: settings)
                .tabItem {
                    Label("編輯器", systemImage: "scissors")
                }

            // 同步設定
            SyncSettingsTab(settings: settings)
                .tabItem {
                    Label("同步", systemImage: "icloud")
                }
        }
    }
}


// MARK: - ASR Settings Tab

struct ASRSettingsTab: View {
    @ObservedObject var settings: AppSettings

    @State private var models: [ModelDownloader.ModelDetails] = []
    @State private var isLoading: Bool = true
    @State private var downloadingModel: String?
    @State private var downloadProgress: Double = 0
    @State private var totalSize: Int64 = 0
    @State private var showDeleteConfirmation: Bool = false
    @State private var modelToDelete: String?

    var body: some View {
        Form {
            // 語言設定
            Section("轉錄設定") {
                Picker("語言", selection: $settings.asrLanguage) {
                    Text("中文").tag("zh")
                    Text("English").tag("en")
                    Text("日本語").tag("ja")
                    Text("한국어").tag("ko")
                    Text("Español").tag("es")
                    Text("Français").tag("fr")
                    Text("Deutsch").tag("de")
                }

                Toggle("說話者分離", isOn: $settings.enableDiarization)
            }

            // 模型管理
            Section {
                if isLoading {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("載入模型列表...")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(models) { model in
                        ModelRow(
                            model: model,
                            isDownloading: downloadingModel == model.name,
                            downloadProgress: downloadingModel == model.name ? downloadProgress : 0,
                            onDownload: { downloadModel(model.name) },
                            onDelete: {
                                modelToDelete = model.name
                                showDeleteConfirmation = true
                            }
                        )
                    }
                }
            } header: {
                HStack {
                    Text("WhisperKit 模型")
                    Spacer()
                    if totalSize > 0 {
                        Text("已使用 \(ModelDownloader.formatSize(totalSize))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("較大的模型準確度更高但需要更多記憶體和處理時間。建議使用 Large V3 以獲得最佳中文辨識效果。")
            }
        }
        .formStyle(.grouped)
        .padding()
        .task {
            await loadModels()
        }
        .alert("刪除模型", isPresented: $showDeleteConfirmation) {
            Button("取消", role: .cancel) {
                modelToDelete = nil
            }
            Button("刪除", role: .destructive) {
                if let model = modelToDelete {
                    deleteModel(model)
                }
            }
        } message: {
            Text("確定要刪除此模型嗎？下次使用時需要重新下載。")
        }
    }

    private func loadModels() async {
        isLoading = true
        models = await ModelDownloader.allModelDetails()
        totalSize = ModelDownloader.totalDownloadedSize()
        isLoading = false
    }

    private func downloadModel(_ name: String) {
        guard downloadingModel == nil else { return }

        downloadingModel = name
        downloadProgress = 0

        Task {
            do {
                _ = try await ModelDownloader.downloadModel(name) { progress in
                    Task { @MainActor in
                        self.downloadProgress = progress
                    }
                }

                await loadModels()
            } catch {
                print("Download error: \(error)")
            }

            await MainActor.run {
                downloadingModel = nil
                downloadProgress = 0
            }
        }
    }

    private func deleteModel(_ name: String) {
        do {
            try ModelDownloader.deleteModel(name)
            Task {
                await loadModels()
            }
        } catch {
            print("Delete error: \(error)")
        }
        modelToDelete = nil
    }
}

// MARK: - Model Row

struct ModelRow: View {
    let model: ModelDownloader.ModelDetails
    let isDownloading: Bool
    let downloadProgress: Double
    let onDownload: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // 模型資訊
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(model.displayName)
                        .font(.body)

                    if model.isDownloaded {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                }

                HStack(spacing: 8) {
                    if let size = model.sizeOnDisk {
                        Text(ModelDownloader.formatSize(size))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(model.estimatedSize)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // 下載進度或操作按鈕
            if isDownloading {
                HStack(spacing: 8) {
                    ProgressView(value: downloadProgress)
                        .frame(width: 80)

                    Text("\(Int(downloadProgress * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 40)
                }
            } else if model.isDownloaded {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            } else {
                Button {
                    onDownload()
                } label: {
                    Label("下載", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - LLM Settings Tab

struct LLMSettingsTab: View {
    @ObservedObject var settings: AppSettings
    @State private var apiKey: String = ""
    @State private var isOllamaAvailable: Bool = false

    var body: some View {
        Form {
            Section("AI 提供者") {
                Picker("提供者", selection: $settings.llmProvider) {
                    ForEach(LLMProviderType.allCases) { provider in
                        HStack {
                            Text(provider.displayName)
                            if provider.isLocal {
                                Text("免費")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }
                        }
                        .tag(provider)
                    }
                }
                .pickerStyle(.segmented)
            }

            if settings.llmProvider == .claude {
                Section("Claude API") {
                    SecureField("API Key", text: $apiKey)
                        .onAppear { apiKey = settings.claudeAPIKey }
                        .onChange(of: apiKey) { _, newValue in
                            settings.claudeAPIKey = newValue
                        }

                    Picker("模型", selection: $settings.claudeModel) {
                        Text("Claude Sonnet 4").tag("claude-sonnet-4-20250514")
                        Text("Claude Opus 4").tag("claude-opus-4-20250514")
                        Text("Claude Haiku 3.5").tag("claude-3-5-haiku-20241022")
                    }

                    Link("取得 API Key", destination: URL(string: "https://console.anthropic.com/")!)
                        .font(.caption)
                }
            } else {
                Section("Ollama") {
                    TextField("主機位址", text: $settings.ollamaHost)

                    TextField("模型名稱", text: $settings.ollamaModel)

                    HStack {
                        Circle()
                            .fill(isOllamaAvailable ? .green : .red)
                            .frame(width: 8, height: 8)

                        Text(isOllamaAvailable ? "Ollama 運行中" : "Ollama 未連線")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button("測試連線") {
                            checkOllamaConnection()
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            if settings.llmProvider == .ollama {
                checkOllamaConnection()
            }
        }
    }

    private func checkOllamaConnection() {
        Task {
            // TODO: 實際檢查 Ollama 連線
            isOllamaAvailable = false
        }
    }
}

// MARK: - Editor Settings Tab

struct EditorSettingsTab: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("剪輯參數") {
                HStack {
                    Text("Crossfade")
                    Spacer()
                    TextField("", value: $settings.crossfadeMs, format: .number)
                        .frame(width: 60)
                        .textFieldStyle(.roundedBorder)
                    Text("ms")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("最小移除長度")
                    Spacer()
                    TextField("", value: $settings.minRemovalMs, format: .number)
                        .frame(width: 60)
                        .textFieldStyle(.roundedBorder)
                    Text("ms")
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading) {
                    HStack {
                        Text("信心閾值")
                        Spacer()
                        Text("\(Int(settings.minConfidence * 100))%")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $settings.minConfidence, in: 0.5...1.0, step: 0.05)
                }
            }

            Section("匯出設定") {
                Picker("輸出格式", selection: $settings.exportFormat) {
                    ForEach(ExportFormat.allCases) { format in
                        Text(format.displayName).tag(format)
                    }
                }

                Toggle("自動匯出 JSON 報告", isOn: $settings.autoExportJSON)
                Toggle("自動匯出 EDL", isOn: $settings.autoExportEDL)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Sync Settings Tab

struct SyncSettingsTab: View {
    @ObservedObject var settings: AppSettings
    @State private var iCloudStatus: String = "檢查中..."

    var body: some View {
        Form {
            Section("iCloud 同步") {
                Toggle("啟用 iCloud 同步", isOn: $settings.iCloudEnabled)

                if settings.iCloudEnabled {
                    Toggle("同步音訊檔案", isOn: $settings.syncAudioFiles)

                    HStack {
                        Text("iCloud 狀態")
                        Spacer()
                        Text(iCloudStatus)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("iCloud 同步說明")
                        .font(.headline)

                    Text("• 專案資料會自動同步到所有裝置")
                    Text("• 音訊檔案會儲存在 iCloud Drive")
                    Text("• API Key 透過 iCloud Keychain 同步")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            checkiCloudStatus()
        }
    }

    private func checkiCloudStatus() {
        Task {
            if FileManager.default.ubiquityIdentityToken != nil {
                iCloudStatus = "已登入"
            } else {
                iCloudStatus = "未登入"
            }
        }
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
}
