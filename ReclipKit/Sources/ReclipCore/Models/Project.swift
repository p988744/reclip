import Foundation
import SwiftData

/// 專案模型（支援 SwiftData + iCloud 同步）
@Model
public final class Project: Identifiable {
    /// 唯一識別碼
    public var id: UUID

    /// 專案名稱
    public var name: String

    /// 音訊檔案 URL（相對於 iCloud 容器）
    public var audioFileName: String

    /// 音訊時長（秒）
    public var duration: TimeInterval

    /// 取樣率
    public var sampleRate: Double

    /// 聲道數
    public var channels: Int

    /// 處理狀態
    public var statusRawValue: String

    /// 建立時間
    public var createdAt: Date

    /// 修改時間
    public var modifiedAt: Date

    /// 轉錄結果（JSON）
    public var transcriptJSON: Data?

    /// 分析結果（JSON）
    public var analysisJSON: Data?

    /// 編輯報告（JSON）
    public var editReportJSON: Data?

    public init(
        id: UUID = UUID(),
        name: String,
        audioFileName: String,
        duration: TimeInterval = 0,
        sampleRate: Double = 48000,
        channels: Int = 1
    ) {
        self.id = id
        self.name = name
        self.audioFileName = audioFileName
        self.duration = duration
        self.sampleRate = sampleRate
        self.channels = channels
        self.statusRawValue = ProjectStatus.imported.rawValue
        self.createdAt = Date()
        self.modifiedAt = Date()
    }

    // MARK: - Computed Properties

    public var status: ProjectStatus {
        get { ProjectStatus(rawValue: statusRawValue) ?? .imported }
        set { statusRawValue = newValue.rawValue }
    }

    public var formattedDuration: String {
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    // MARK: - Transcript Access

    public var transcript: TranscriptResult? {
        get {
            guard let data = transcriptJSON else { return nil }
            return try? JSONDecoder().decode(TranscriptResult.self, from: data)
        }
        set {
            transcriptJSON = try? JSONEncoder().encode(newValue)
            modifiedAt = Date()
        }
    }

    public var analysis: AnalysisResult? {
        get {
            guard let data = analysisJSON else { return nil }
            return try? JSONDecoder().decode(AnalysisResult.self, from: data)
        }
        set {
            analysisJSON = try? JSONEncoder().encode(newValue)
            modifiedAt = Date()
        }
    }

    public var editReport: EditReport? {
        get {
            guard let data = editReportJSON else { return nil }
            return try? JSONDecoder().decode(EditReport.self, from: data)
        }
        set {
            editReportJSON = try? JSONEncoder().encode(newValue)
            modifiedAt = Date()
        }
    }
}

/// 專案狀態
public enum ProjectStatus: String, Codable, Sendable {
    case imported = "imported"
    case transcribing = "transcribing"
    case transcribed = "transcribed"
    case analyzing = "analyzing"
    case analyzed = "analyzed"
    case editing = "editing"
    case completed = "completed"
    case failed = "failed"

    public var icon: String {
        switch self {
        case .imported: return "doc.badge.plus"
        case .transcribing: return "waveform"
        case .transcribed: return "text.bubble"
        case .analyzing: return "sparkles"
        case .analyzed: return "checkmark.circle"
        case .editing: return "scissors"
        case .completed: return "checkmark.seal.fill"
        case .failed: return "exclamationmark.triangle"
        }
    }

    public var color: some ShapeStyle {
        switch self {
        case .imported: return .secondary
        case .transcribing, .analyzing, .editing: return .blue
        case .transcribed, .analyzed: return .orange
        case .completed: return .green
        case .failed: return .red
        }
    }
}

// MARK: - SwiftData Configuration

extension Project {
    /// SwiftData 模型容器配置
    public static var modelContainer: ModelContainer {
        let schema = Schema([Project.self])

        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .private("iCloud.com.reclip.app")
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("無法建立 ModelContainer: \(error)")
        }
    }
}
