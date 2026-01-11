import Foundation
import SwiftUI

/// 應用設定（使用 @AppStorage 自動同步 iCloud）
@MainActor
public class AppSettings: ObservableObject {
    public static let shared = AppSettings()

    // MARK: - ASR Settings

    /// Whisper 模型大小
    @AppStorage("asr.whisperModel")
    public var whisperModel: WhisperModel = .largeV3

    /// ASR 語言
    @AppStorage("asr.language")
    public var asrLanguage: String = "zh"

    /// 是否啟用說話者分離
    @AppStorage("asr.enableDiarization")
    public var enableDiarization: Bool = true

    // MARK: - LLM Settings

    /// LLM 提供者
    @AppStorage("llm.provider")
    public var llmProvider: LLMProviderType = .claude

    /// Claude API Key（儲存在 Keychain）
    public var claudeAPIKey: String {
        get { KeychainHelper.get(key: "claude_api_key") ?? "" }
        set { KeychainHelper.set(key: "claude_api_key", value: newValue) }
    }

    /// Claude 模型
    @AppStorage("llm.claudeModel")
    public var claudeModel: String = "claude-sonnet-4-20250514"

    /// Ollama 主機
    @AppStorage("llm.ollamaHost")
    public var ollamaHost: String = "http://localhost:11434"

    /// Ollama 模型
    @AppStorage("llm.ollamaModel")
    public var ollamaModel: String = "llama3.2"

    // MARK: - Editor Settings

    /// Crossfade 長度（毫秒）
    @AppStorage("editor.crossfadeMs")
    public var crossfadeMs: Int = 30

    /// 最小移除長度（毫秒）
    @AppStorage("editor.minRemovalMs")
    public var minRemovalMs: Int = 100

    /// 最低信心閾值
    @AppStorage("editor.minConfidence")
    public var minConfidence: Double = 0.7

    // MARK: - Export Settings

    /// 預設輸出格式
    @AppStorage("export.format")
    public var exportFormat: ExportFormat = .m4a

    /// 是否自動匯出 JSON 報告
    @AppStorage("export.autoExportJSON")
    public var autoExportJSON: Bool = true

    /// 是否自動匯出 EDL
    @AppStorage("export.autoExportEDL")
    public var autoExportEDL: Bool = false

    // MARK: - Sync Settings

    /// 是否啟用 iCloud 同步（需要 Apple Developer Program）
    @AppStorage("sync.iCloudEnabled")
    public var iCloudEnabled: Bool = false

    /// 是否同步音訊檔案
    @AppStorage("sync.syncAudioFiles")
    public var syncAudioFiles: Bool = true

    private init() {}
}

// MARK: - Enums

public enum WhisperModel: String, CaseIterable, Identifiable {
    case tiny = "tiny"
    case base = "base"
    case small = "small"
    case medium = "medium"
    case largeV2 = "large-v2"
    case largeV3 = "large-v3"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .tiny: return "Tiny (最快)"
        case .base: return "Base"
        case .small: return "Small"
        case .medium: return "Medium"
        case .largeV2: return "Large V2"
        case .largeV3: return "Large V3 (最準確)"
        }
    }

    public var approximateSize: String {
        switch self {
        case .tiny: return "~75 MB"
        case .base: return "~150 MB"
        case .small: return "~500 MB"
        case .medium: return "~1.5 GB"
        case .largeV2, .largeV3: return "~3 GB"
        }
    }
}

public enum LLMProviderType: String, CaseIterable, Identifiable {
    case claude = "claude"
    case ollama = "ollama"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claude: return "Claude API"
        case .ollama: return "Ollama (本地)"
        }
    }

    public var isLocal: Bool {
        self == .ollama
    }
}

public enum ExportFormat: String, CaseIterable, Identifiable {
    case m4a = "m4a"
    case wav = "wav"
    case mp3 = "mp3"
    case flac = "flac"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .m4a: return "M4A (AAC)"
        case .wav: return "WAV"
        case .mp3: return "MP3"
        case .flac: return "FLAC"
        }
    }
}

// MARK: - Keychain Helper

enum KeychainHelper {
    private static let service = "com.reclip.app"

    static func get(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }

        return string
    }

    static func set(key: String, value: String) {
        let data = value.data(using: .utf8)!

        // 先刪除舊值
        delete(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrSynchronizable as String: true  // 同步到 iCloud Keychain
        ]

        SecItemAdd(query as CFDictionary, nil)
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        SecItemDelete(query as CFDictionary)
    }
}
