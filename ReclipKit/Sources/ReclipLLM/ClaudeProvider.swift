import Foundation
import ReclipCore
import SwiftAnthropic

/// Claude API 提供者
public final class ClaudeProvider: LLMProvider, @unchecked Sendable {
    public let name = "Claude"
    public let isLocal = false

    private let service: AnthropicService
    private let model: String

    public init(
        apiKey: String,
        model: String = "claude-sonnet-4-20250514"
    ) {
        self.service = AnthropicServiceFactory.service(
            apiKey: apiKey,
            betaHeaders: nil
        )
        self.model = model
    }

    public func analyze(
        transcript: TranscriptResult,
        configuration: AnalysisConfiguration
    ) async throws -> AnalysisResult {
        // 分段處理
        let chunks = chunkTranscript(transcript, maxDuration: configuration.maxSegmentDuration)
        var allRemovals: [Removal] = []

        for chunk in chunks {
            let removals = try await analyzeChunk(chunk, configuration: configuration)
            allRemovals.append(contentsOf: removals)
        }

        // 過濾低信心的結果
        let filteredRemovals = allRemovals.filter { $0.confidence >= configuration.minConfidence }

        return AnalysisResult(
            removals: filteredRemovals,
            originalDuration: transcript.duration
        )
    }

    private func chunkTranscript(
        _ transcript: TranscriptResult,
        maxDuration: TimeInterval
    ) -> [[Segment]] {
        var chunks: [[Segment]] = []
        var currentChunk: [Segment] = []
        var chunkStart: TimeInterval = 0

        for segment in transcript.segments {
            currentChunk.append(segment)

            if segment.end - chunkStart >= maxDuration {
                chunks.append(currentChunk)
                currentChunk = []
                chunkStart = segment.end
            }
        }

        if !currentChunk.isEmpty {
            chunks.append(currentChunk)
        }

        return chunks
    }

    private func analyzeChunk(
        _ segments: [Segment],
        configuration: AnalysisConfiguration
    ) async throws -> [Removal] {
        let prompt = AnalysisPrompt.generate(for: segments)

        let message = MessageParameter.Message(
            role: .user,
            content: .text(prompt)
        )

        let parameter = MessageParameter(
            model: .other(model),
            messages: [message],
            maxTokens: 4096
        )

        let response = try await service.createMessage(parameter)

        // 解析回應
        guard let textContent = response.content.first else {
            throw LLMError.invalidResponse("無法取得回應內容")
        }

        let text: String
        switch textContent {
        case .text(let content, _):
            text = content
        default:
            throw LLMError.invalidResponse("回應內容類型不支援")
        }

        return try parseResponse(text)
    }

    private func parseResponse(_ response: String) throws -> [Removal] {
        // 提取 JSON
        var jsonString = response

        // 處理 markdown code block
        if let jsonStart = response.range(of: "```json") {
            let startIndex = response.index(jsonStart.upperBound, offsetBy: 0)
            if let jsonEnd = response.range(of: "```", range: startIndex..<response.endIndex) {
                jsonString = String(response[startIndex..<jsonEnd.lowerBound])
            }
        } else if let jsonStart = response.range(of: "```") {
            let startIndex = response.index(jsonStart.upperBound, offsetBy: 0)
            if let jsonEnd = response.range(of: "```", range: startIndex..<response.endIndex) {
                jsonString = String(response[startIndex..<jsonEnd.lowerBound])
            }
        }

        jsonString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)

        // 解析 JSON
        guard let data = jsonString.data(using: .utf8) else {
            throw LLMError.invalidResponse("無法解析 JSON")
        }

        let decoded = try JSONDecoder().decode(RemovalResponse.self, from: data)

        return decoded.removals.map { item in
            Removal(
                start: item.start,
                end: item.end,
                reason: RemovalReason(rawValue: item.reason) ?? .filler,
                text: item.text,
                confidence: item.confidence
            )
        }
    }
}

// MARK: - Response Models

private struct RemovalResponse: Decodable {
    let removals: [RemovalItem]
}

private struct RemovalItem: Decodable {
    let start: TimeInterval
    let end: TimeInterval
    let reason: String
    let text: String
    let confidence: Double
}
