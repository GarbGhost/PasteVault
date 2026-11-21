import Foundation
import AppKit

@MainActor
public final class UpdateService: ObservableObject {
    public static let shared = UpdateService()

    public static let releasesPageURL = URL(string: "https://github.com/GarbGhost/PasteVault/releases")!
    public static let projectPageURL = URL(string: "https://github.com/GarbGhost/PasteVault")!
    public static let latestReleaseAPIURL = URL(string: "https://api.github.com/repos/GarbGhost/PasteVault/releases/latest")!

    public enum UpdateState: Equatable {
        case idle
        case checking
        case upToDate(currentVersion: String)
        case updateAvailable(latestVersion: String, downloadURL: URL, releasePageURL: URL, releaseNotes: String)
        case privateOrOffline(currentVersion: String, releasesURL: URL)
    }

    @Published public var state: UpdateState = .idle
    @Published public var isUpdateModalPresented: Bool = false
    @Published public var isUpToDateModalPresented: Bool = false
    @Published public var isInstallingUpdate: Bool = false
    @Published public var installProgress: Double = 0.0
    @Published public var installErrorMessage: String? = nil
    @Published public var postUpdateTCCNotice: String? = nil
    @Published public var autoCheckUpdates: Bool {
        didSet {
            AppDefaults.shared.set(autoCheckUpdates, forKey: "autoCheckUpdates")
            if autoCheckUpdates {
                startAutoCheckTimer()
                Task {
                    await self.checkForUpdates(manual: false)
                }
            } else {
                stopAutoCheckTimer()
            }
        }
    }

    private var autoCheckTimer: Timer?
    public private(set) var lastCheckDate: Date? = nil
    private var wakeObserver: Any?

    private struct GitHubReleaseResponse: Decodable {
        let tagName: String
        let htmlURL: String
        let body: String?
        let assets: [GitHubAsset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case body
            case assets
        }
    }

    private struct GitHubAsset: Decodable {
        let name: String
        let browserDownloadURL: String

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    nonisolated public static let openPanelOnNextLaunchKey = "pv_open_panel_on_next_launch"

    public var currentVersion: String {
        if let bundleID = Bundle.main.bundleIdentifier, bundleID != "com.pastevault.app" {
            return "1.1.5"
        }
        let raw = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.1.5"
        if Bundle.main.bundlePath.contains("xctest") || raw.isEmpty {
            return "1.1.5"
        }
        return raw
    }

    private init() {
        if AppDefaults.shared.object(forKey: "autoCheckUpdates") == nil {
            AppDefaults.shared.set(false, forKey: "autoCheckUpdates")
            self.autoCheckUpdates = false
        } else {
            self.autoCheckUpdates = AppDefaults.shared.bool(forKey: "autoCheckUpdates")
        }

        setupLifecycleObservers()

        if self.autoCheckUpdates {
            startAutoCheckTimer()
            Task { [weak self] in
                await self?.checkForUpdates(manual: false)
            }
        }
    }

    private func startAutoCheckTimer() {
        stopAutoCheckTimer()
        guard autoCheckUpdates else { return }
        autoCheckTimer = Timer.scheduledTimer(withTimeInterval: 4 * 3600, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.autoCheckUpdates else { return }
                await self.checkForUpdates(manual: false)
            }
        }
    }

    private func stopAutoCheckTimer() {
        autoCheckTimer?.invalidate()
        autoCheckTimer = nil
    }

    private func setupLifecycleObservers() {
        if wakeObserver == nil {
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self = self, self.autoCheckUpdates else { return }
                    let elapsed = Date().timeIntervalSince(self.lastCheckDate ?? .distantPast)
                    if elapsed > 30 * 60 {
                        await self.checkForUpdates(manual: false)
                    }
                }
            }
        }
    }

    public func onSettingsTabOpened() {
        guard autoCheckUpdates else { return }
        let elapsed = Date().timeIntervalSince(lastCheckDate ?? .distantPast)
        if elapsed > 15 * 60 {
            Task { [weak self] in
                await self?.checkForUpdates(manual: false)
            }
        }
    }

    /// Чистая функция семантического сравнения версий (например, "v1.0.1" > "1.0.0")
    nonisolated public static func isVersion(_ remote: String, newerThan local: String) -> Bool {
        let remoteParts = parseVersionComponents(remote)
        let localParts = parseVersionComponents(local)
        let maxCount = max(remoteParts.count, localParts.count)

        for i in 0..<maxCount {
            let r = i < remoteParts.count ? remoteParts[i] : 0
            let l = i < localParts.count ? localParts[i] : 0
            if r != l {
                return r > l
            }
        }
        return false
    }

    nonisolated public static func cleanVersionString(_ version: String) -> String {
        var s = version.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("v") || s.hasPrefix("V") {
            s.removeFirst()
        }
        if let dashIndex = s.firstIndex(of: "-") {
            s = String(s[..<dashIndex])
        }
        if let plusIndex = s.firstIndex(of: "+") {
            s = String(s[..<plusIndex])
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func parseVersionComponents(_ version: String) -> [Int] {
        let cleaned = cleanVersionString(version)
        guard !cleaned.isEmpty else { return [0] }
        return cleaned.split(separator: ".").map { Int($0) ?? 0 }
    }

    public func checkForUpdates(manual: Bool = true) async {
        state = .checking
        let localVersion = currentVersion
        defer {
            lastCheckDate = Date()
        }

        // Эфемерная конфигурация URLSession без cookies и кэша (100% Zero-Telemetry)
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieAcceptPolicy = .never
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let session = URLSession(configuration: config)
        defer {
            session.finishTasksAndInvalidate()
        }

        var request = URLRequest(url: Self.latestReleaseAPIURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.httpShouldHandleCookies = false
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("PasteVault-macOS", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                state = .privateOrOffline(currentVersion: localVersion, releasesURL: Self.releasesPageURL)
                return
            }

            if httpResponse.statusCode == 404 {
                // Отсутствие /releases/latest (404 — нет релизов, приватный или перенесённый репозиторий) не выдаём за «установлена последняя версия»
                state = .privateOrOffline(currentVersion: localVersion, releasesURL: Self.releasesPageURL)
                return
            }

            guard httpResponse.statusCode == 200 else {
                state = .privateOrOffline(currentVersion: localVersion, releasesURL: Self.releasesPageURL)
                return
            }

            let release = try JSONDecoder().decode(GitHubReleaseResponse.self, from: data)
            let remoteClean = Self.cleanVersionString(release.tagName)
            let parsedPageURL = URL(string: release.htmlURL)
            let pageURL = (parsedPageURL.map { Self.isTrustedUpdateURL($0) } == true) ? parsedPageURL! : Self.releasesPageURL

            let dmgAssetURL = release.assets
                .first(where: { $0.name.lowercased().hasSuffix(".dmg") })
                .flatMap { URL(string: $0.browserDownloadURL) }
                .flatMap { Self.isTrustedUpdateURL($0) ? $0 : nil }
            let downloadURL = dmgAssetURL ?? pageURL

            if Self.isVersion(release.tagName, newerThan: localVersion) {
                state = .updateAvailable(
                    latestVersion: remoteClean.isEmpty ? release.tagName : remoteClean,
                    downloadURL: downloadURL,
                    releasePageURL: pageURL,
                    releaseNotes: release.body ?? ""
                )
                isUpdateModalPresented = true
            } else {
                state = .upToDate(currentVersion: localVersion)
                if manual {
                    isUpToDateModalPresented = true
                }
            }
        } catch {
            state = .privateOrOffline(currentVersion: localVersion, releasesURL: Self.releasesPageURL)
        }
    }

    /// Очистка текста описания релиза для аккуратного компактного показа в попапе обновления с учётом языка интерфейса
    nonisolated public static func formattedPopupReleaseNotes(
        from rawBody: String,
        language: AppLanguage = .current
    ) -> String {
        let content = extractLocalizedReleaseSection(from: rawBody, language: language)

        let stopMarkers = [
            "### 📦 Установка", "### 📦 Installing",
            "## 📦 Установка", "## 📦 Installing",
            "📦 Установка", "📦 Installing",
            "### Установка", "### Installing",
            "## Установка", "## Installing",
            "### 🔐 Checksums", "## 🔐 Checksums",
            "Checksums", "SHA-256",
            "## [v", "### [v"
        ]

        var cutoffIndex = content.endIndex
        let lowerContent = content.lowercased()
        for marker in stopMarkers {
            if let range = lowerContent.range(of: marker.lowercased()), range.lowerBound < cutoffIndex {
                cutoffIndex = range.lowerBound
            }
        }
        let trimmedSection = String(content[..<cutoffIndex])
        let sanitizedHTML = stripReleaseHTMLTags(trimmedSection)

        let lines = sanitizedHTML.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        var resultItems: [String] = []
        var currentItem: String = ""

        for line in lines {
            if line.isEmpty {
                if !currentItem.isEmpty {
                    resultItems.append(currentItem)
                    currentItem = ""
                }
                continue
            }

            // Пропускаем markdown-заголовки и разделители
            if line.hasPrefix("#") || line == "---" {
                if !currentItem.isEmpty {
                    resultItems.append(currentItem)
                    currentItem = ""
                }
                continue
            }

            // Пропускаем приветственные вводные строки
            let lowerLine = line.lowercased()
            if lowerLine.hasPrefix("вышел pastevault") || lowerLine.contains("is out") {
                continue
            }

            // Очищаем сырой markdown: **, `
            var clean = line.replacingOccurrences(of: "**", with: "")
                .replacingOccurrences(of: "`", with: "")

            var isBullet = false
            let bulletPrefixes = ["•", "-", "*", "💾", "✨", "⚡️", "🔒", "🎨", "🚀"]
            for prefix in bulletPrefixes {
                if clean.hasPrefix(prefix) {
                    isBullet = true
                    clean = clean.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
                    break
                }
            }

            if isBullet {
                if !currentItem.isEmpty {
                    resultItems.append(currentItem)
                }
                currentItem = clean
            } else {
                if !currentItem.isEmpty {
                    currentItem += " " + clean
                } else {
                    currentItem = clean
                }
            }
        }

        if !currentItem.isEmpty {
            resultItems.append(currentItem)
        }

        let bullets = resultItems.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.map { "• \($0)" }
        if bullets.isEmpty {
            let fallback = sanitizedHTML.replacingOccurrences(of: "#", with: "")
                .replacingOccurrences(of: "**", with: "")
                .replacingOccurrences(of: "`", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return fallback.isEmpty ? "" : fallback
        }
        return bullets.joined(separator: "\n\n")
    }

    nonisolated private static func extractLocalizedReleaseSection(from rawBody: String, language: AppLanguage) -> String {
        if language == .en {
            // 1. Ищем <details>...</details> с английским summary/содержимым
            if let detailsRegex = try? NSRegularExpression(
                pattern: #"<details\b[^>]*>(.*?)</details>"#,
                options: [.caseInsensitive, .dotMatchesLineSeparators]
            ) {
                let nsRaw = rawBody as NSString
                let matches = detailsRegex.matches(in: rawBody, range: NSRange(location: 0, length: nsRaw.length))
                for match in matches where match.numberOfRanges > 1 {
                    let inner = nsRaw.substring(with: match.range(at: 1))
                    if inner.localizedCaseInsensitiveContains("english") {
                        return removeSummaryTagBlock(inner)
                    }
                }
            }

            // 2. Ищем markdown-заголовок вида ### English / ### 🇬🇧 English
            let lines = rawBody.components(separatedBy: .newlines)
            if let startIdx = lines.firstIndex(where: { isEnglishHeadingLine($0) }) {
                var collected: [String] = []
                for idx in (startIdx + 1)..<lines.count {
                    let trimmed = lines[idx].trimmingCharacters(in: .whitespaces)
                    if isLanguageOrMajorBoundaryHeading(trimmed) {
                        break
                    }
                    collected.append(lines[idx])
                }
                let joined = collected.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                if !joined.isEmpty {
                    return joined
                }
            }

            return rawBody
        }

        // Для русского языка (ru): отсекаем <details> и английскую секцию, сохраняя русскую часть
        var ruSection = rawBody
        let ruCutMarkers = [
            "<details",
            "### 🇬🇧 English", "## 🇬🇧 English",
            "### English", "## English"
        ]
        let lowerRu = ruSection.lowercased()
        var earliestCut = ruSection.endIndex
        for marker in ruCutMarkers {
            if let range = lowerRu.range(of: marker.lowercased()), range.lowerBound < earliestCut {
                earliestCut = range.lowerBound
            }
        }
        ruSection = String(ruSection[..<earliestCut])
        return ruSection
    }

    nonisolated private static func isEnglishHeadingLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("#") else { return false }
        let title = trimmed.drop(while: { $0 == "#" || $0 == " " }).lowercased()
        return title == "english" || title == "🇬🇧 english" || title.hasPrefix("🇬🇧 english") || title.hasPrefix("english ")
    }

    nonisolated private static func isLanguageOrMajorBoundaryHeading(_ trimmedLine: String) -> Bool {
        guard trimmedLine.hasPrefix("#") else { return false }
        let lower = trimmedLine.lowercased()
        return lower.contains("русск") || lower.contains("checksum") || lower.contains("sha-256")
            || lower.contains("установка") || lower.contains("installing")
    }

    nonisolated private static func removeSummaryTagBlock(_ text: String) -> String {
        guard let summaryRegex = try? NSRegularExpression(
            pattern: #"<summary\b[^>]*>.*?</summary>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return text
        }
        let range = NSRange(location: 0, length: (text as NSString).length)
        return summaryRegex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }

    nonisolated private static func stripReleaseHTMLTags(_ text: String) -> String {
        var cleaned = removeSummaryTagBlock(text)
        let lineBreakTags = ["<br>", "<br/>", "<br />", "</p>", "</li>"]
        for tag in lineBreakTags {
            cleaned = cleaned.replacingOccurrences(of: tag, with: "\n", options: .caseInsensitive)
        }
        if let tagRegex = try? NSRegularExpression(pattern: #"</?[a-zA-Z][^>]*>"#, options: []) {
            let range = NSRange(location: 0, length: (cleaned as NSString).length)
            cleaned = tagRegex.stringByReplacingMatches(in: cleaned, range: range, withTemplate: "")
        }
        return cleaned
    }

    public func dismissModal() {
        isUpdateModalPresented = false
    }

    public func dismissUpToDateModal() {
        isUpToDateModalPresented = false
    }

    public func showModal() {
        if case .updateAvailable = state {
            isUpdateModalPresented = true
        }
    }

    /// Проверяет, что URL обновления ведёт строго на официальный репозиторий GitHub или официальные asset-домены GitHub
    nonisolated public static func isTrustedUpdateURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(), !host.isEmpty else {
            return false
        }
        if host == "github.com" {
            return url.path.hasPrefix("/GarbGhost/PasteVault/") || url.path == "/GarbGhost/PasteVault"
        }
        if host == "objects.githubusercontent.com" || host == "release-assets.githubusercontent.com" {
            return true
        }
        return false
    }

    nonisolated public static func buildDetachedRelaunchCommand(waitingForPID pid: Int32, appPath: String) -> String {
        let escapedPath = appPath.replacingOccurrences(of: "'", with: "'\\''")
        return "while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.1; done; /usr/bin/xattr -dr com.apple.quarantine '\(escapedPath)' 2>/dev/null || true; /usr/bin/open -a '\(escapedPath)'"
    }

    public static func launchDetachedRelaunch(
        appURL: URL,
        currentPID: Int32 = ProcessInfo.processInfo.processIdentifier
    ) {
        AppDefaults.shared.set(true, forKey: openPanelOnNextLaunchKey)
        AppDefaults.shared.synchronize()

        let innerCommand = buildDetachedRelaunchCommand(waitingForPID: currentPID, appPath: appURL.path)
        let launcher = Process()
        launcher.executableURL = URL(fileURLWithPath: "/bin/sh")
        launcher.arguments = [
            "-c",
            "nohup /bin/sh -c \"$1\" >/dev/null 2>&1 </dev/null &",
            "pastevault-relaunch",
            innerCommand
        ]
        launcher.standardInput = FileHandle.nullDevice
        launcher.standardOutput = FileHandle.nullDevice
        launcher.standardError = FileHandle.nullDevice
        try? launcher.run()
    }

    nonisolated private static func runProcessAsync(executablePath: String, arguments: [String]) async throws -> (status: Int32, stderr: String) {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executablePath)
                process.arguments = arguments
                let errPipe = Pipe()
                process.standardError = errPipe
                do {
                    try process.run()
                    process.waitUntilExit()
                    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    let errText = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    continuation.resume(returning: (process.terminationStatus, errText))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func downloadAndInstallUpdate(from downloadURL: URL, silent: Bool = false) async {
        guard Self.isTrustedUpdateURL(downloadURL) else {
            installProgress = 0.0
            isInstallingUpdate = false
            installErrorMessage = AppLanguage.current == .en
                ? "Untrusted update download URL blocked."
                : "Заблокирован недоверенный URL загрузки обновления."
            return
        }

        isInstallingUpdate = true
        installProgress = 0.1
        installErrorMessage = nil

        let config = URLSessionConfiguration.ephemeral
        config.httpCookieAcceptPolicy = .never
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let session = URLSession(configuration: config)
        defer {
            session.finishTasksAndInvalidate()
        }

        var downloadedTempURL: URL? = nil
        var mountedPointToDetach: String? = nil
        var stagingDirURL: URL? = nil
        let fileManager = FileManager.default

        defer {
            if let mountPoint = mountedPointToDetach {
                let detachProcess = Process()
                detachProcess.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
                detachProcess.arguments = ["detach", mountPoint, "-force"]
                try? detachProcess.run()
                detachProcess.waitUntilExit()
            }
            if let downloadedTempURL {
                try? fileManager.removeItem(at: downloadedTempURL)
            }
            if let stagingDirURL {
                try? fileManager.removeItem(at: stagingDirURL)
            }
        }

        do {
            let (tempLocalURL, response) = try await session.download(from: downloadURL)
            downloadedTempURL = tempLocalURL
            if let finalURL = response.url, !Self.isTrustedUpdateURL(finalURL) {
                throw NSError(
                    domain: "PasteVault.Update",
                    code: 403,
                    userInfo: [NSLocalizedDescriptionKey: "Redirected update URL is not trusted: \(finalURL.absoluteString)"]
                )
            }
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw NSError(
                    domain: "PasteVault.Update",
                    code: http.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: "HTTP error \(http.statusCode) while downloading update"]
                )
            }
            installProgress = 0.55

            let dmgPath = tempLocalURL.path
            guard downloadURL.pathExtension.lowercased() == "dmg" || dmgPath.hasSuffix(".dmg") else {
                isInstallingUpdate = false
                installProgress = 0.0
                if !silent {
                    AppDelegate.shared?.dismissFloatingPanel(restorePreviousApp: false)
                    NSWorkspace.shared.open(downloadURL)
                }
                return
            }

            let mountPoint = "/Volumes/PasteVaultUpdate_\(UUID().uuidString.prefix(6))"
            let attachRes = try await Self.runProcessAsync(
                executablePath: "/usr/bin/hdiutil",
                arguments: ["attach", "-nobrowse", "-readonly", dmgPath, "-mountpoint", mountPoint]
            )
            guard attachRes.status == 0 else {
                throw NSError(
                    domain: "PasteVault.Update",
                    code: Int(attachRes.status),
                    userInfo: [NSLocalizedDescriptionKey: "hdiutil attach failed (\(attachRes.status)): \(attachRes.stderr)"]
                )
            }
            mountedPointToDetach = mountPoint
            installProgress = 0.72

            let mountedAppURL = URL(fileURLWithPath: mountPoint, isDirectory: true).appendingPathComponent("Paste Vault.app", isDirectory: true)
            let mountedBinaryURL = mountedAppURL.appendingPathComponent("Contents/MacOS/Paste Vault")
            let mountedPlistURL = mountedAppURL.appendingPathComponent("Contents/Info.plist")
            guard fileManager.fileExists(atPath: mountedAppURL.path),
                  fileManager.fileExists(atPath: mountedBinaryURL.path),
                  fileManager.fileExists(atPath: mountedPlistURL.path) else {
                throw NSError(
                    domain: "PasteVault.Update",
                    code: 404,
                    userInfo: [NSLocalizedDescriptionKey: "Paste Vault.app bundle inside DMG is missing or incomplete"]
                )
            }

            let targetAppURL = URL(fileURLWithPath: "/Applications/Paste Vault.app", isDirectory: true)
            let targetParentURL = targetAppURL.deletingLastPathComponent()
            let stagingDir = targetParentURL.appendingPathComponent(".PasteVaultUpdateStaging_\(UUID().uuidString.prefix(8))", isDirectory: true)
            try fileManager.createDirectory(at: stagingDir, withIntermediateDirectories: true)
            stagingDirURL = stagingDir

            let stagedAppURL = stagingDir.appendingPathComponent("Paste Vault.app", isDirectory: true)
            let dittoRes = try await Self.runProcessAsync(
                executablePath: "/usr/bin/ditto",
                arguments: [mountedAppURL.path, stagedAppURL.path]
            )
            guard dittoRes.status == 0 else {
                throw NSError(
                    domain: "PasteVault.Update",
                    code: Int(dittoRes.status),
                    userInfo: [NSLocalizedDescriptionKey: "Failed to stage updated .app bundle: \(dittoRes.stderr)"]
                )
            }
            installProgress = 0.85

            let bundleId = Bundle.main.bundleIdentifier ?? "com.pastevault.app"
            let codesignRes = try await Self.runProcessAsync(
                executablePath: "/usr/bin/codesign",
                arguments: ["--force", "--deep", "--sign", "-", "--identifier", bundleId, stagedAppURL.path]
            )
            guard codesignRes.status == 0 else {
                throw NSError(
                    domain: "PasteVault.Update",
                    code: Int(codesignRes.status),
                    userInfo: [NSLocalizedDescriptionKey: "codesign failed (\(codesignRes.status)): \(codesignRes.stderr)"]
                )
            }

            // Атомарная подмена всего .app бандла с откатом на бэкап при ошибке (обновляет Info.plist, Resources и бинарник)
            let backupOldAppURL = stagingDir.appendingPathComponent("Paste Vault.previous.app", isDirectory: true)
            let hadExistingTarget = fileManager.fileExists(atPath: targetAppURL.path)
            if hadExistingTarget {
                try fileManager.moveItem(at: targetAppURL, to: backupOldAppURL)
            }
            do {
                try fileManager.moveItem(at: stagedAppURL, to: targetAppURL)
            } catch {
                if hadExistingTarget, fileManager.fileExists(atPath: backupOldAppURL.path), !fileManager.fileExists(atPath: targetAppURL.path) {
                    try? fileManager.moveItem(at: backupOldAppURL, to: targetAppURL)
                }
                throw error
            }

            // Предупреждаем систему баннера, что после переподписи новой версии macOS может потребовать повторное подтверждение Универсального доступа
            AppDefaults.shared.set(false, forKey: "isAccessibilityBannerDismissed")
            if !AccessibilityService.isAccessibilityTrusted() {
                postUpdateTCCNotice = AppLanguage.current == .en
                    ? "Update installed. macOS may ask to re-confirm Accessibility permission after relaunch."
                    : "Обновление установлено. После перезапуска macOS может потребовать повторно подтвердить Универсальный доступ."
            }

            installProgress = 1.0
            isInstallingUpdate = false

            if !silent {
                dismissModal()
                Self.launchDetachedRelaunch(appURL: targetAppURL)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    NSApplication.shared.terminate(nil)
                }
            }
        } catch {
            isInstallingUpdate = false
            installProgress = 0.0
            installErrorMessage = error.localizedDescription
        }
    }

    public func openDownloadOrReleasePage() {
        AppDelegate.shared?.dismissFloatingPanel(restorePreviousApp: false)
        switch state {
        case .updateAvailable(_, let downloadURL, _, _):
            NSWorkspace.shared.open(downloadURL)
        case .privateOrOffline(_, let releasesURL):
            NSWorkspace.shared.open(releasesURL)
        case .idle, .checking, .upToDate:
            NSWorkspace.shared.open(Self.releasesPageURL)
        }
    }

    public func openReleasePage() {
        AppDelegate.shared?.dismissFloatingPanel(restorePreviousApp: false)
        switch state {
        case .updateAvailable(_, _, let releasePageURL, _):
            NSWorkspace.shared.open(releasePageURL)
        case .privateOrOffline(_, let releasesURL):
            NSWorkspace.shared.open(releasesURL)
        default:
            NSWorkspace.shared.open(Self.releasesPageURL)
        }
    }

    public func openProjectPage() {
        AppDelegate.shared?.dismissFloatingPanel(restorePreviousApp: false)
        NSWorkspace.shared.open(Self.projectPageURL)
    }
}
