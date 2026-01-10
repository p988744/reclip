#if os(macOS)
import Foundation
import ReclipCore
import Ollama

/// Ollama 本地 LLM 提供者（僅 macOS）
public final class OllamaProvider: LLMProvider, @unchecked Sendable {
    public let name = "Ollama"
    public let isLocal = true

    private let client: OllamaClient
    private let model: String

    public init(
        host: String = "http://localhost:11434",
        model: String = "llama3.2"
    ) {
        self.client = OllamaClient(host: URL(string: host)!)
        self.model = model
    }

    /// 檢查 Ollama 是否正在運行
    public func isAvailable() async -> Bool {
        do {
            _ = try await client.models()
            return true
        } catch {
            return false
        }
    }

    /// 列出可用的模型
    public func listModels() async throws -> [String] {
        let response = try await client.models()
        return response.models.map { $0.name }
    }

    public func analyze(
        transcript: TranscriptResult,
        configuration: AnalysisConfiguration
    ) async throws -> AnalysisResult {
        // 檢查連線
        guard await isAvailable() else {
            throw LLMError.connectionFailed("無法連線到 Ollama，請確認 Ollama 正在運行")
        }

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

        let response = try await client.generate(
            model: model,
            prompt: prompt,
            options: [
                "temperature": 0.1,
                "num_predict": 4096
            ]
        )

        return try parseResponse(response.response)
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
#endif
