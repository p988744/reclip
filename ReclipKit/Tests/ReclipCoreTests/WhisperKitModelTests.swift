import Testing
import Foundation
@testable import ReclipASR

/// WhisperKit 模型下載測試
/// 注意：這些測試需要網路連線，首次執行會下載模型
@Suite("WhisperKit Model Tests", .tags(.integration))
struct WhisperKitModelTests {

    /// 測試 Provider 初始化
    @Test("WhisperKitProvider initialization")
    func testProviderInit() async throws {
        let provider = WhisperKitProvider(modelName: "base")

        #expect(provider.name == "WhisperKit")
        #expect(provider.isLocal == true)
        #expect(provider.supportedLanguages.contains("zh"))
        #expect(provider.supportedLanguages.contains("en"))
    }

    /// 測試取得可用模型列表
    @Test("Fetch available models")
    func testFetchAvailableModels() async {
        let modelInfo = await ModelDownloader.availableModels()

        #expect(!modelInfo.supported.isEmpty, "Should have supported models")
        #expect(!modelInfo.defaultModel.isEmpty, "Should have default model")

        print("✅ 可用模型列表：")
        for model in modelInfo.supported {
            print("   - \(model)")
        }
        print("   預設模型：\(modelInfo.defaultModel)")
    }

    /// 測試模型載入（需要下載模型，可能需要較長時間）
    /// 此測試預設跳過，手動執行時可移除 .disabled
    @Test("Load WhisperKit model", .disabled("Requires model download (~1GB), run manually"))
    func testLoadModel() async throws {
        let provider = WhisperKitProvider(modelName: "base")

        // 載入模型
        try await provider.loadModel()

        // 驗證模型已載入 - 透過嘗試轉錄一個不存在的檔案來測試
        // 應該拋出 fileNotFound 而不是 modelNotLoaded
        do {
            _ = try await provider.transcribe(
                url: URL(fileURLWithPath: "/nonexistent/file.mp3"),
                language: "en",
                includeWordTimestamps: false
            ) { _ in }
            Issue.record("Should have thrown an error")
        } catch let error as ASRError {
            // 預期是 fileNotFound，而不是 modelNotLoaded
            switch error {
            case .fileNotFound:
                // 正確 - 模型已載入但檔案不存在
                break
            case .modelNotLoaded:
                Issue.record("Model should be loaded but got modelNotLoaded error")
            default:
                // 其他錯誤也可以接受
                break
            }
        }

        // 卸載模型
        provider.unloadModel()
    }

    /// 測試實際轉錄 - 使用 JFK 測試音訊
    /// 需要下載模型，執行時間較長
    @Test("Transcribe JFK audio", .disabled("Run manually: swift test --filter WhisperKit"))
    func testTranscribeJFK() async throws {
        // 使用 tiny 模型（最小，約 75MB）
        let provider = WhisperKitProvider(modelName: "openai_whisper-tiny")

        print("\n📥 下載並載入模型中...")
        try await provider.loadModel { progress in
            let percent = Int(progress * 100)
            if percent % 20 == 0 {
                print("   進度: \(percent)%")
            }
        }
        print("✅ 模型載入完成\n")

        // 找到測試音訊
        let jfkPath = "/Users/weifan/claudeProjects/reclip/ReclipKit/.build/checkouts/WhisperKit/Tests/WhisperKitTests/Resources/jfk.wav"

        let audioURL = URL(fileURLWithPath: jfkPath)

        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            print("❌ 找不到測試音訊: \(jfkPath)")
            return
        }

        print("🎙️ 開始轉錄: \(audioURL.lastPathComponent)")
        print("─────────────────────────────────────")

        let result = try await provider.transcribe(
            url: audioURL,
            language: "en",
            includeWordTimestamps: true
        ) { progress in
            // 轉錄進度
        }

        // 輸出結果
        print("\n📝 轉錄結果:")
        print("─────────────────────────────────────")
        print("語言: \(result.language)")
        print("時長: \(String(format: "%.2f", result.duration)) 秒")
        print("段落數: \(result.segments.count)")
        print("")

        for (index, segment) in result.segments.enumerated() {
            print("[\(index + 1)] \(formatTime(segment.start)) → \(formatTime(segment.end))")
            print("    \"\(segment.text)\"")

            if !segment.words.isEmpty {
                print("    詞彙: ", terminator: "")
                for word in segment.words.prefix(5) {
                    print("\(word.word)(\(Int(word.confidence * 100))%) ", terminator: "")
                }
                if segment.words.count > 5 {
                    print("... +\(segment.words.count - 5) more")
                } else {
                    print("")
                }
            }
            print("")
        }

        print("─────────────────────────────────────")
        print("📄 完整文字:")
        print(result.fullText)
        print("─────────────────────────────────────\n")

        // 驗證
        #expect(!result.segments.isEmpty, "Should have segments")
        #expect(result.duration > 0, "Should have duration")

        // 卸載模型
        provider.unloadModel()
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let ms = Int((seconds.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%02d:%02d.%02d", mins, secs, ms)
    }

    /// 測試大型中文 Podcast 轉錄
    /// 使用 87 分鐘的 PyCon 節目測試
    @Test("Transcribe large Chinese podcast", .disabled("Run manually: swift test --filter WhisperKit"))
    func testTranscribeLargePodcast() async throws {
        let audioPath = "/Users/weifan/Library/CloudStorage/SynologyDrive-macbook/pycon/S5/S5EP2.mp3"
        let audioURL = URL(fileURLWithPath: audioPath)

        guard FileManager.default.fileExists(atPath: audioPath) else {
            print("❌ 測試檔案不存在: \(audioPath)")
            return
        }

        // 使用 small 模型（中文效果較好，約 500MB）
        let provider = WhisperKitProvider(modelName: "openai_whisper-small")

        print("\n📥 下載並載入模型中（small 模型約 500MB）...")
        let loadStart = Date()
        try await provider.loadModel { progress in
            let percent = Int(progress * 100)
            if percent % 20 == 0 {
                print("   模型載入進度: \(percent)%")
            }
        }
        let loadTime = Date().timeIntervalSince(loadStart)
        print("✅ 模型載入完成（耗時 \(String(format: "%.1f", loadTime)) 秒）\n")

        print("🎙️ 開始轉錄大型檔案...")
        print("   檔案: \(audioURL.lastPathComponent)")
        print("   預計時間: 10-30 分鐘（依 GPU 效能而定）")
        print("─────────────────────────────────────")

        let transcribeStart = Date()

        let result = try await provider.transcribe(
            url: audioURL,
            language: "zh",
            includeWordTimestamps: true
        ) { progress in
            let percent = Int(progress * 100)
            if percent % 10 == 0 {
                print("   轉錄進度: \(percent)%")
            }
        }

        let transcribeTime = Date().timeIntervalSince(transcribeStart)

        // 輸出結果摘要
        print("\n📝 轉錄完成！")
        print("─────────────────────────────────────")
        print("語言: \(result.language)")
        print("音訊時長: \(String(format: "%.1f", result.duration / 60)) 分鐘")
        print("轉錄耗時: \(String(format: "%.1f", transcribeTime / 60)) 分鐘")
        print("處理速度: \(String(format: "%.1fx", result.duration / transcribeTime)) 即時速度")
        print("段落數: \(result.segments.count)")
        print("總字數: \(result.fullText.count)")
        print("")

        // 顯示前 5 個段落
        print("📄 前 5 個段落：")
        for (index, segment) in result.segments.prefix(5).enumerated() {
            print("[\(index + 1)] \(formatTime(segment.start)) → \(formatTime(segment.end))")
            print("    \"\(segment.text.prefix(100))\(segment.text.count > 100 ? "..." : "")\"")
            print("")
        }

        // 顯示完整文字的前 500 字
        print("─────────────────────────────────────")
        print("📄 完整文字（前 500 字）：")
        print(String(result.fullText.prefix(500)))
        if result.fullText.count > 500 {
            print("... (共 \(result.fullText.count) 字)")
        }
        print("─────────────────────────────────────\n")

        // 驗證
        #expect(!result.segments.isEmpty, "Should have segments")
        #expect(result.duration > 60 * 60, "Should be > 1 hour")

        // 卸載模型
        provider.unloadModel()
    }
}

// MARK: - Test Tags

extension Tag {
    @Tag static var integration: Self
}
