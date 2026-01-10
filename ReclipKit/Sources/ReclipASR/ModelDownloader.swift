import Foundation
import WhisperKit

/// 模型下載工具
public struct ModelDownloader {

    /// 可用模型資訊
    public struct ModelInfo: Sendable {
        public let supported: [String]
        public let defaultModel: String
    }

    /// 單一模型的詳細資訊
    public struct ModelDetails: Identifiable, Sendable {
        public let id: String
        public let name: String
        public let displayName: String
        public let isDownloaded: Bool
        public let sizeOnDisk: Int64?  // bytes, nil if not downloaded
        public let estimatedSize: String

        public init(id: String, name: String, displayName: String, isDownloaded: Bool, sizeOnDisk: Int64?, estimatedSize: String) {
            self.id = id
            self.name = name
            self.displayName = displayName
            self.isDownloaded = isDownloaded
            self.sizeOnDisk = sizeOnDisk
            self.estimatedSize = estimatedSize
        }
    }

    /// 模型快取目錄
    private static var modelCacheDirectory: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml")
    }

    /// 取得可用的 WhisperKit 模型列表
    public static func availableModels() async -> ModelInfo {
        let recommended = WhisperKit.recommendedModels()
        return ModelInfo(
            supported: recommended.supported,
            defaultModel: recommended.default
        )
    }

    /// 取得所有模型的詳細資訊
    public static func allModelDetails() async -> [ModelDetails] {
        let modelInfo = await availableModels()

        return modelInfo.supported.map { modelName in
            let isDownloaded = isModelDownloaded(modelName)
            let sizeOnDisk = isDownloaded ? getModelSize(modelName) : nil

            return ModelDetails(
                id: modelName,
                name: modelName,
                displayName: formatModelName(modelName),
                isDownloaded: isDownloaded,
                sizeOnDisk: sizeOnDisk,
                estimatedSize: estimateModelSize(modelName)
            )
        }
    }

    /// 下載指定模型
    /// - Parameters:
    ///   - modelName: 模型名稱（如 "base", "small", "large-v3"）
    ///   - progress: 下載進度回調
    /// - Returns: 模型路徑 URL
    public static func downloadModel(
        _ modelName: String,
        progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> URL {
        let modelPath = try await WhisperKit.download(
            variant: modelName,
            progressCallback: { prog in
                progress(prog.fractionCompleted)
            }
        )
        return modelPath
    }

    /// 檢查模型是否已下載
    public static func isModelDownloaded(_ modelName: String) -> Bool {
        guard let modelDir = modelCacheDirectory else { return false }
        let modelPath = modelDir.appendingPathComponent(modelName)
        return FileManager.default.fileExists(atPath: modelPath.path)
    }

    /// 取得模型資料夾大小
    public static func getModelSize(_ modelName: String) -> Int64? {
        guard let modelDir = modelCacheDirectory else { return nil }
        let modelPath = modelDir.appendingPathComponent(modelName)
        return directorySize(at: modelPath)
    }

    /// 刪除已下載的模型
    public static func deleteModel(_ modelName: String) throws {
        guard let modelDir = modelCacheDirectory else { return }
        let modelPath = modelDir.appendingPathComponent(modelName)

        if FileManager.default.fileExists(atPath: modelPath.path) {
            try FileManager.default.removeItem(at: modelPath)
        }
    }

    /// 取得所有已下載模型的總大小
    public static func totalDownloadedSize() -> Int64 {
        guard let modelDir = modelCacheDirectory else { return 0 }
        return directorySize(at: modelDir) ?? 0
    }

    // MARK: - Private Helpers

    private static func directorySize(at url: URL) -> Int64? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        var totalSize: Int64 = 0
        let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey])

        while let fileURL = enumerator?.nextObject() as? URL {
            do {
                let attributes = try fileURL.resourceValues(forKeys: [.fileSizeKey])
                totalSize += Int64(attributes.fileSize ?? 0)
            } catch {
                continue
            }
        }

        return totalSize
    }

    private static func formatModelName(_ name: String) -> String {
        // openai_whisper-large-v3 -> Large V3
        // distil-whisper_distil-large-v3 -> Distil Large V3
        var displayName = name

        // Remove prefix
        if displayName.hasPrefix("openai_whisper-") {
            displayName = String(displayName.dropFirst("openai_whisper-".count))
        } else if displayName.hasPrefix("distil-whisper_") {
            displayName = "Distil " + String(displayName.dropFirst("distil-whisper_".count))
        }

        // Remove size suffix like _949MB
        if let underscoreIndex = displayName.lastIndex(of: "_"),
           displayName[displayName.index(after: underscoreIndex)...].allSatisfy({ $0.isNumber || $0 == "M" || $0 == "B" || $0 == "G" }) {
            displayName = String(displayName[..<underscoreIndex])
        }

        // Capitalize and format
        displayName = displayName
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "v2", with: "V2")
            .replacingOccurrences(of: "v3", with: "V3")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")

        return displayName
    }

    private static func estimateModelSize(_ name: String) -> String {
        // Extract size from name if present (e.g., _949MB)
        if let match = name.range(of: #"_(\d+)(MB|GB)"#, options: .regularExpression) {
            let sizeStr = name[match]
            return String(sizeStr.dropFirst()) // Remove leading underscore
        }

        // Estimate based on model type
        let lowercased = name.lowercased()
        if lowercased.contains("tiny") { return "~75 MB" }
        if lowercased.contains("base") { return "~150 MB" }
        if lowercased.contains("small") { return "~500 MB" }
        if lowercased.contains("medium") { return "~1.5 GB" }
        if lowercased.contains("large") { return "~1-3 GB" }

        return "未知"
    }

    /// 格式化檔案大小
    public static func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
