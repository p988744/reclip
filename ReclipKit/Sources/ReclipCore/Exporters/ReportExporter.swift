import Foundation

/// 報告匯出器
public enum ReportExporter {
    /// 匯出 JSON 報告
    public static func exportJSON(
        report: EditReport,
        to url: URL,
        pretty: Bool = true
    ) throws {
        let data = JSONReport(from: report)

        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : []
        encoder.dateEncodingStrategy = .iso8601

        let jsonData = try encoder.encode(data)
        try jsonData.write(to: url)
    }

    /// 匯出 EDL 檔案
    public static func exportEDL(
        report: EditReport,
        to url: URL,
        fps: Double = 30.0,
        title: String? = nil
    ) throws {
        let edlTitle = title ?? report.inputURL.deletingPathExtension().lastPathComponent
        var content = "TITLE: \(edlTitle)\n"
        content += "FCM: NON-DROP FRAME\n\n"

        let keepRegions = computeKeepRegions(report: report)
        var recOffset: TimeInterval = 0

        for (index, region) in keepRegions.enumerated() {
            let eventNum = String(format: "%03d", index + 1)
            let reel = "AX"

            let srcIn = secondsToTimecode(region.start, fps: fps)
            let srcOut = secondsToTimecode(region.end, fps: fps)

            let duration = region.end - region.start
            let recIn = secondsToTimecode(recOffset, fps: fps)
            let recOut = secondsToTimecode(recOffset + duration, fps: fps)

            content += "\(eventNum)  \(reel)       AA/V  C        \(srcIn) \(srcOut) \(recIn) \(recOut)\n"
            content += "* FROM CLIP NAME: \(report.inputURL.lastPathComponent)\n\n"

            recOffset += duration
        }

        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    /// 匯出標記檔案
    public static func exportMarkers(
        report: EditReport,
        to url: URL,
        format: MarkerFormat = .csv
    ) throws {
        let content: String

        switch format {
        case .csv:
            content = formatMarkersCSV(report: report)
        case .audacity:
            content = formatMarkersAudacity(report: report)
        }

        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Private Helpers

    private static func computeKeepRegions(
        report: EditReport
    ) -> [(start: TimeInterval, end: TimeInterval)] {
        guard !report.edits.isEmpty else {
            return [(start: 0, end: report.originalDuration)]
        }

        let sortedEdits = report.edits.sorted { $0.originalStart < $1.originalStart }
        var regions: [(start: TimeInterval, end: TimeInterval)] = []
        var lastEnd: TimeInterval = 0

        for edit in sortedEdits {
            if edit.originalStart > lastEnd {
                regions.append((start: lastEnd, end: edit.originalStart))
            }
            lastEnd = edit.originalEnd
        }

        if lastEnd < report.originalDuration {
            regions.append((start: lastEnd, end: report.originalDuration))
        }

        return regions
    }

    private static func secondsToTimecode(_ seconds: TimeInterval, fps: Double) -> String {
        let totalFrames = Int(seconds * fps)
        let frames = totalFrames % Int(fps)
        let totalSeconds = totalFrames / Int(fps)
        let secs = totalSeconds % 60
        let totalMinutes = totalSeconds / 60
        let mins = totalMinutes % 60
        let hours = totalMinutes / 60

        return String(format: "%02d:%02d:%02d:%02d", hours, mins, secs, frames)
    }

    private static func formatMarkersCSV(report: EditReport) -> String {
        var lines = ["start,end,label,reason"]

        for edit in report.edits {
            let text = edit.text
                .replacingOccurrences(of: ",", with: ";")
                .replacingOccurrences(of: "\n", with: " ")

            lines.append(String(
                format: "%.3f,%.3f,\"%@\",%@",
                edit.originalStart,
                edit.originalEnd,
                text,
                edit.reason.rawValue
            ))
        }

        return lines.joined(separator: "\n")
    }

    private static func formatMarkersAudacity(report: EditReport) -> String {
        var lines: [String] = []

        for edit in report.edits {
            let text = edit.text
                .replacingOccurrences(of: "\t", with: " ")
                .replacingOccurrences(of: "\n", with: " ")

            lines.append(String(
                format: "%.6f\t%.6f\t[%@] %@",
                edit.originalStart,
                edit.originalEnd,
                edit.reason.rawValue,
                text
            ))
        }

        return lines.joined(separator: "\n")
    }
}

/// 標記格式
public enum MarkerFormat {
    case csv
    case audacity
}

// MARK: - JSON Report Structure

private struct JSONReport: Encodable {
    let version: String
    let generatedAt: Date
    let input: String
    let output: String
    let originalDuration: TimeInterval
    let editedDuration: TimeInterval
    let removedDuration: TimeInterval
    let reductionPercent: Double
    let editCount: Int
    let edits: [JSONEdit]
    let statistics: [String: Int]

    init(from report: EditReport) {
        self.version = "1.0"
        self.generatedAt = report.createdAt
        self.input = report.inputURL.path
        self.output = report.outputURL.path
        self.originalDuration = report.originalDuration
        self.editedDuration = report.editedDuration
        self.removedDuration = report.removedDuration
        self.reductionPercent = report.reductionPercent
        self.editCount = report.edits.count
        self.edits = report.edits.map { JSONEdit(from: $0) }

        var stats: [String: Int] = [:]
        for (reason, count) in report.statistics {
            stats[reason.rawValue] = count
        }
        self.statistics = stats
    }
}

private struct JSONEdit: Encodable {
    let originalStart: TimeInterval
    let originalEnd: TimeInterval
    let reason: String
    let text: String

    init(from edit: AppliedEdit) {
        self.originalStart = edit.originalStart
        self.originalEnd = edit.originalEnd
        self.reason = edit.reason.rawValue
        self.text = edit.text
    }
}
