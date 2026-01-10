# App Store 審核合規指南

確保 Reclip 順利通過 Apple App Store 審核的完整檢查清單。

---

## 1. 隱私與資料處理

### 1.1 第三方 AI 揭露（2025 年 11 月新規）

> **關鍵規則 5.1.2**：若 App 與第三方 AI 分享個人資料，必須明確揭露並取得使用者同意。

**Reclip 需要揭露：**

| 資料類型 | 傳送對象 | 用途 | 同意方式 |
|---------|---------|------|---------|
| 音訊逐字稿 | Claude API (Anthropic) | 分析語氣詞 | 首次使用前彈窗確認 |
| 音訊逐字稿 | Ollama (本地) | 同上 | 無需（本地處理） |

**實作要求：**
```swift
// 首次使用 Claude API 前必須顯示
struct AIConsentView: View {
    var body: some View {
        VStack {
            Text("資料處理說明")
                .font(.title)

            Text("""
            Reclip 會將您的音訊逐字稿傳送至 Anthropic 的 Claude API 進行分析。

            • 僅傳送文字內容，不傳送原始音訊
            • 資料用於識別需移除的語氣詞
            • Anthropic 不會儲存您的資料用於訓練
            """)

            Button("同意並繼續") { ... }
            Button("使用本地 AI (Ollama)") { ... }
        }
    }
}
```

### 1.2 隱私標籤揭露

App Store Connect 需填寫的隱私標籤：

| 資料類型 | 是否收集 | 連結使用者 | 用途 |
|---------|---------|-----------|------|
| 音訊資料 | ✅ | ❌ | App 功能 |
| 使用資料 | ❌ | - | - |
| 診斷資料 | ❌ | - | - |

### 1.3 資料保留與刪除

**必須提供：**
- 帳號刪除功能（若有帳號系統）
- 本地資料清除選項
- iCloud 資料刪除說明

```swift
// 設定頁面
Section("資料管理") {
    Button("清除本地快取") { ... }
    Button("刪除 iCloud 資料") { ... }
    Link("隱私權政策", destination: privacyPolicyURL)
}
```

---

## 2. App Sandbox（macOS 必要）

### 2.1 必要權限

```xml
<!-- Reclip.entitlements -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "...">
<plist version="1.0">
<dict>
    <!-- App Sandbox（必要） -->
    <key>com.apple.security.app-sandbox</key>
    <true/>

    <!-- 網路存取（Claude API） -->
    <key>com.apple.security.network.client</key>
    <true/>

    <!-- 使用者選擇的檔案（音訊匯入） -->
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>

    <!-- 下載資料夾（匯出） -->
    <key>com.apple.security.files.downloads.read-write</key>
    <true/>

    <!-- iCloud 容器 -->
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.com.reclip.app</string>
    </array>

    <!-- 音訊錄製（未來功能） -->
    <!-- <key>com.apple.security.device.audio-input</key> -->
    <!-- <true/> -->
</dict>
</plist>
```

### 2.2 禁止的操作

❌ 存取任意檔案系統路徑
❌ 執行外部程式（除非使用者明確選擇）
❌ 修改系統設定
❌ 存取其他 App 的資料

### 2.3 Security-Scoped Bookmarks

用於記住使用者選擇的檔案：

```swift
// 儲存書籤
func saveBookmark(for url: URL) throws {
    let bookmark = try url.bookmarkData(
        options: .withSecurityScope,
        includingResourceValuesForKeys: nil,
        relativeTo: nil
    )
    UserDefaults.standard.set(bookmark, forKey: "lastAudioBookmark")
}

// 還原書籤
func restoreBookmark() -> URL? {
    guard let data = UserDefaults.standard.data(forKey: "lastAudioBookmark") else {
        return nil
    }

    var isStale = false
    guard let url = try? URL(
        resolvingBookmarkData: data,
        options: .withSecurityScope,
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
    ) else { return nil }

    if isStale {
        try? saveBookmark(for: url)  // 更新書籤
    }

    return url
}
```

---

## 3. Privacy Manifest（iOS 17+ / macOS 14+）

### 3.1 PrivacyInfo.xcprivacy

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "...">
<plist version="1.0">
<dict>
    <!-- 存取的 API 類型 -->
    <key>NSPrivacyAccessedAPITypes</key>
    <array>
        <dict>
            <key>NSPrivacyAccessedAPIType</key>
            <string>NSPrivacyAccessedAPICategoryFileTimestamp</string>
            <key>NSPrivacyAccessedAPITypeReasons</key>
            <array>
                <string>C617.1</string>  <!-- 顯示給使用者 -->
            </array>
        </dict>
        <dict>
            <key>NSPrivacyAccessedAPIType</key>
            <string>NSPrivacyAccessedAPICategoryUserDefaults</string>
            <key>NSPrivacyAccessedAPITypeReasons</key>
            <array>
                <string>CA92.1</string>  <!-- App 自身設定 -->
            </array>
        </dict>
    </array>

    <!-- 追蹤網域（無） -->
    <key>NSPrivacyTrackingDomains</key>
    <array/>

    <!-- 收集的資料類型 -->
    <key>NSPrivacyCollectedDataTypes</key>
    <array>
        <dict>
            <key>NSPrivacyCollectedDataType</key>
            <string>NSPrivacyCollectedDataTypeAudioData</string>
            <key>NSPrivacyCollectedDataTypeLinked</key>
            <false/>
            <key>NSPrivacyCollectedDataTypeTracking</key>
            <false/>
            <key>NSPrivacyCollectedDataTypePurposes</key>
            <array>
                <string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
            </array>
        </dict>
    </array>

    <!-- 不追蹤使用者 -->
    <key>NSPrivacyTracking</key>
    <false/>
</dict>
</plist>
```

---

## 4. AI 功能揭露

### 4.1 App Store 描述

必須在 App 描述中說明 AI 功能：

> Reclip 使用人工智慧分析您的 Podcast 逐字稿，自動識別語氣詞、重複內容和長停頓。您可以選擇使用雲端 AI (Claude) 或本地 AI (Ollama) 進行分析。

### 4.2 App 內說明

```swift
struct AIInfoSheet: View {
    var body: some View {
        List {
            Section("AI 如何運作") {
                Label("分析逐字稿文字", systemImage: "text.bubble")
                Label("識別需移除的內容", systemImage: "wand.and.stars")
                Label("不會學習或儲存您的資料", systemImage: "lock.shield")
            }

            Section("資料處理") {
                LabeledContent("Claude API") {
                    Text("傳送至 Anthropic 伺服器")
                }
                LabeledContent("Ollama") {
                    Text("完全本地處理")
                }
            }
        }
    }
}
```

---

## 5. 常見拒絕原因與解決方案

### 5.1 Guideline 2.1 - App 完整性

**問題**：App 功能不完整或有明顯 bug
**解決**：確保所有功能都能正常運作，包含錯誤處理

```swift
// 良好的錯誤處理
do {
    try await processAudio()
} catch {
    // 顯示使用者友善的錯誤訊息
    showError(
        title: "處理失敗",
        message: error.localizedDescription,
        recovery: "請確認檔案格式正確後重試"
    )
}
```

### 5.2 Guideline 4.2 - 最低功能

**問題**：App 功能太少
**解決**：Reclip 提供完整的處理流程（轉錄→分析→剪輯→匯出）

### 5.3 Guideline 5.1.1 - 資料收集

**問題**：未說明資料如何使用
**解決**：
- 提供完整的隱私權政策 URL
- 在 App 內說明資料流向
- 使用前取得同意

### 5.4 Guideline 5.1.2 - 第三方 AI

**問題**：未揭露 AI 資料分享
**解決**：
- 首次使用前顯示同意對話框
- 提供本地替代方案 (Ollama)
- 在設定中可隨時切換

---

## 6. 檢查清單

### 提交前檢查

- [ ] App Sandbox 已啟用
- [ ] 所有 entitlements 都有正當理由
- [ ] Privacy Manifest 已建立
- [ ] 隱私權政策 URL 有效
- [ ] 第三方 AI 同意對話框已實作
- [ ] 資料刪除功能已實作
- [ ] 錯誤訊息使用者友善
- [ ] 所有功能都經過測試
- [ ] App 描述包含 AI 說明
- [ ] 螢幕截圖準確反映功能

### 必要文件

- [ ] `Reclip.entitlements`
- [ ] `PrivacyInfo.xcprivacy`
- [ ] 隱私權政策網頁
- [ ] App Store 描述文字
- [ ] 螢幕截圖（各尺寸）

---

## 參考連結

- [App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [App Sandbox Documentation](https://developer.apple.com/documentation/security/app-sandbox)
- [Privacy Manifest](https://developer.apple.com/documentation/bundleresources/privacy_manifest_files)
- [App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/)
- [2025 AI Guidelines Update](https://techcrunch.com/2025/11/13/apples-new-app-review-guidelines-clamp-down-on-apps-sharing-personal-data-with-third-party-ai/)
