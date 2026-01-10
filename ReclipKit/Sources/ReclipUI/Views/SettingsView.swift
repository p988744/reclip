import SwiftUI
import ReclipCore

/// 設定視圖
public struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var settings = AppSettings.shared

    @State private var selectedTab: SettingsTab = .asr

    public init() {}

    public var body: some View {
        NavigationStack {
            TabView(selection: $selectedTab) {
                // ASR 設定
                ASRSettingsTab(settings: settings)
                    .tabItem {
                        Label("語音辨識", systemImage: "waveform")
                    }
                    .tag(SettingsTab.asr)

                // LLM 設定
                LLMSettingsTab(settings: settings)
                    .tabItem {
                        Label("AI 分析", systemImage: "sparkles")
                    }
                    .tag(SettingsTab.llm)

                // 編輯器設定
                EditorSettingsTab(settings: settings)
                    .tabItem {
                        Label("編輯器", systemImage: "scissors")
                    }
                    .tag(SettingsTab.editor)

                // 同步設定
                SyncSettingsTab(settings: settings)
                    .tabItem {
                        Label("同步", systemImage: "icloud")
                    }
                    .tag(SettingsTab.sync)
            }
            .navigationTitle("設定")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 500, height: 400)
    }
}

enum SettingsTab {
    case asr, llm, editor, sync
}

// MARK: - ASR Settings Tab

struct ASRSettingsTab: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("Whisper 模型") {
                Picker("模型大小", selection: $settings.whisperModel) {
                    ForEach(WhisperModel.allCases) { model in
                        HStack {
                            Text(model.displayName)
                            Spacer()
                            Text(model.approximateSize)
                                .foregroundStyle(.secondary)
                        }
                        .tag(model)
                    }
                }

                Picker("語言", selection: $settings.asrLanguage) {
                    Text("中文").tag("zh")
                    Text("English").tag("en")
                    Text("日本語").tag("ja")
                    Text("한국어").tag("ko")
                }

                Toggle("說話者分離", isOn: $settings.enableDiarization)
            }

            Section {
                Text("WhisperKit 會在首次使用時下載模型，較大的模型需要更多 VRAM 但準確度更高。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
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
