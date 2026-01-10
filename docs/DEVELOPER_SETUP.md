# Apple Developer Program 設定指南

完整的 Reclip 開發者設定流程，包含憑證、簽名和發行配置。

---

## 1. 加入 Apple Developer Program

### 1.1 註冊

1. 前往 [Apple Developer Program](https://developer.apple.com/programs/)
2. 以個人或組織身份註冊（年費 $99 USD）
3. 等待 Apple 審核（通常 24-48 小時）

### 1.2 取得 Team ID

1. 登入 [Apple Developer Portal](https://developer.apple.com/account)
2. 在 Membership 頁面找到 **Team ID**（10 位字母數字）
3. 記下此 ID，後續會用到

---

## 2. 建立 App ID

### 2.1 在 Developer Portal 建立

1. 前往 [Identifiers](https://developer.apple.com/account/resources/identifiers/list)
2. 點擊 **+** 建立新 Identifier
3. 選擇 **App IDs** → **App**
4. 填寫資訊：
   - Description: `Reclip`
   - Bundle ID: `com.reclip.app`（Explicit）
5. 啟用 Capabilities：
   - ✅ iCloud（包含 CloudKit）
   - ✅ Associated Domains（如需要）

### 2.2 建立 iCloud Container

1. 前往 [Identifiers](https://developer.apple.com/account/resources/identifiers/list)
2. 點擊 **+** → **iCloud Containers**
3. 填寫：
   - Description: `Reclip iCloud`
   - Identifier: `iCloud.com.reclip.app`

### 2.3 建立 App Group

1. 前往 [Identifiers](https://developer.apple.com/account/resources/identifiers/list)
2. 點擊 **+** → **App Groups**
3. 填寫：
   - Description: `Reclip App Group`
   - Identifier: `group.com.reclip.app`

---

## 3. 建立憑證

### 3.1 憑證類型

| 類型 | 用途 | 有效期 |
|------|------|--------|
| Apple Development | 開發測試 | 1 年 |
| Developer ID Application | DMG 發行 | 5 年 |
| Developer ID Installer | PKG 安裝檔 | 5 年 |
| Mac App Distribution | App Store | 1 年 |
| Mac Installer Distribution | App Store PKG | 1 年 |

### 3.2 手動建立憑證

```bash
# 1. 建立 CSR（Certificate Signing Request）
openssl req -new -newkey rsa:2048 -nodes \
  -keyout reclip.key \
  -out reclip.csr \
  -subj "/CN=Reclip/C=TW"

# 2. 在 Developer Portal 上傳 CSR
# https://developer.apple.com/account/resources/certificates/add

# 3. 下載憑證 (.cer)

# 4. 匯入到 Keychain
security import developer_id_application.cer -k ~/Library/Keychains/login.keychain-db
```

### 3.3 使用 Fastlane Match（推薦）

```bash
# 初始化 Match
fastlane match init

# 建立開發憑證
fastlane match development

# 建立 Developer ID 憑證
fastlane match developer_id

# 建立 App Store 憑證
fastlane match appstore
```

---

## 4. 建立 Provisioning Profiles

### 4.1 Profile 類型

| 類型 | 用途 |
|------|------|
| macOS Development | 開發測試 |
| Developer ID | DMG 發行（不需要 profile） |
| Mac App Store | App Store 發行 |

### 4.2 在 Developer Portal 建立

1. 前往 [Profiles](https://developer.apple.com/account/resources/profiles/list)
2. 點擊 **+** 建立新 Profile
3. 選擇類型並關聯 App ID
4. 下載並安裝 Profile

```bash
# 安裝 Profile
open ~/Downloads/Reclip_Development.provisionprofile
```

---

## 5. 本地設定

### 5.1 執行設定腳本

```bash
./scripts/setup-signing.sh
```

這會引導你設定：
- Team ID
- Apple ID
- App-Specific Password（用於公證）

### 5.2 設定環境變數

```bash
# ~/.zshrc 或 ~/.bashrc
export TEAM_ID="YOUR_TEAM_ID"
export APPLE_ID="your@email.com"
export BUNDLE_ID="com.reclip.app"
```

### 5.3 建立 App-Specific Password

1. 前往 [appleid.apple.com](https://appleid.apple.com/account/manage)
2. 登入 → Security → App-Specific Passwords
3. 建立新密碼，命名為 "Reclip Notarization"
4. 將密碼儲存到 Keychain：

```bash
security add-generic-password \
  -a "your@email.com" \
  -s "com.apple.notarization" \
  -w "your-app-specific-password"
```

---

## 6. 更新專案設定

### 6.1 更新 project.yml

```yaml
settings:
  base:
    DEVELOPMENT_TEAM: "YOUR_TEAM_ID"
    CODE_SIGN_IDENTITY: "Developer ID Application"
    CODE_SIGN_STYLE: Manual
```

### 6.2 重新生成專案

```bash
xcodegen generate
```

---

## 7. 建構與發行

### 7.1 開發建構

```bash
make build
# 或
fastlane build_debug
```

### 7.2 發行 DMG（Developer ID）

```bash
# 使用腳本
./scripts/build-dmg.sh release

# 或使用 Fastlane
fastlane release_dmg
```

### 7.3 公證

```bash
./scripts/notarize.sh build/export/Reclip.app
```

### 7.4 發行至 App Store

```bash
# 上傳至 TestFlight
fastlane beta

# 提交至 App Store
fastlane release_appstore
```

---

## 8. CI/CD 設定

### 8.1 GitHub Secrets

在 GitHub Repository Settings → Secrets 中設定：

| Secret | 說明 |
|--------|------|
| `TEAM_ID` | Apple Developer Team ID |
| `APPLE_ID` | Apple ID 電子郵件 |
| `APPLE_PASSWORD` | App-Specific Password |
| `CERTIFICATE_P12` | Base64 編碼的 .p12 憑證 |
| `CERTIFICATE_PASSWORD` | .p12 密碼 |

### 8.2 匯出憑證為 Base64

```bash
# 從 Keychain 匯出 .p12
security export -k ~/Library/Keychains/login.keychain-db \
  -t identities \
  -f pkcs12 \
  -o certificate.p12

# 轉換為 Base64
base64 -i certificate.p12 -o certificate.txt
```

### 8.3 觸發 Release

```bash
# 建立 tag 觸發 Release workflow
git tag v1.0.0
git push origin v1.0.0
```

---

## 9. 疑難排解

### 9.1 簽名問題

```bash
# 列出可用的簽名身份
security find-identity -v -p codesigning

# 驗證 App 簽名
codesign -dv --verbose=4 Reclip.app

# 重新簽名
codesign --force --deep --sign "Developer ID Application: Your Name (TEAM_ID)" Reclip.app
```

### 9.2 公證問題

```bash
# 查看公證歷史
xcrun notarytool history --apple-id "$APPLE_ID" --team-id "$TEAM_ID"

# 查看特定提交的日誌
xcrun notarytool log <submission-id> \
  --apple-id "$APPLE_ID" \
  --team-id "$TEAM_ID"
```

### 9.3 Entitlements 問題

```bash
# 查看 App 的 entitlements
codesign -d --entitlements - Reclip.app

# 驗證 Sandbox
codesign --verify --deep --strict Reclip.app
```

---

## 10. 檢查清單

### 發行前檢查

- [ ] Team ID 已設定
- [ ] 憑證已安裝到 Keychain
- [ ] App-Specific Password 已設定
- [ ] Bundle ID 與 Developer Portal 一致
- [ ] Entitlements 正確配置
- [ ] Privacy Manifest 已包含
- [ ] App 已簽名
- [ ] App 已公證
- [ ] DMG 已公證

### App Store 額外檢查

- [ ] App Sandbox 啟用
- [ ] 所有 Capabilities 在 Developer Portal 啟用
- [ ] Provisioning Profile 有效
- [ ] 隱私權政策 URL 準備好
- [ ] App Store 截圖準備好
- [ ] App 描述已撰寫

---

## 參考連結

- [Apple Developer Documentation](https://developer.apple.com/documentation/)
- [Notarizing macOS Software](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)
- [App Sandbox](https://developer.apple.com/documentation/security/app_sandbox)
- [Fastlane Documentation](https://docs.fastlane.tools)
- [GitHub Actions for Xcode](https://docs.github.com/en/actions/deployment/deploying-xcode-applications)
