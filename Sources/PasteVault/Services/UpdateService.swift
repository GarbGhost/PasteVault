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
    @Published public var autoCheckUpdates: Bool {
        didSet {
            UserDefaults.standard.set(autoCheckUpdates, forKey: "autoCheckUpdates")
        }
    }

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

    public var currentVersion: String {
        let raw = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0.0"
        if Bundle.main.bundlePath.hasSuffix(".xctest") || raw.isEmpty {
            return "1.0.0"
        }
        return raw
    }

    private init() {
        if UserDefaults.standard.object(forKey: "autoCheckUpdates") == nil {
            UserDefaults.standard.set(false, forKey: "autoCheckUpdates")
            self.autoCheckUpdates = false
        } else {
            self.autoCheckUpdates = UserDefaults.standard.bool(forKey: "autoCheckUpdates")
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

        // Эфемерная конфигурация URLSession без cookies и кэша (100% Zero-Telemetry)
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieAcceptPolicy = .never
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let session = URLSession(configuration: config)

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
                // Если релизов на GitHub еще нет, установленная версия v1.0.0 является актуальной
                state = .upToDate(currentVersion: localVersion)
                if manual {
                    isUpToDateModalPresented = true
                }
                return
            }

            guard httpResponse.statusCode == 200 else {
                state = .privateOrOffline(currentVersion: localVersion, releasesURL: Self.releasesPageURL)
                return
            }

            let release = try JSONDecoder().decode(GitHubReleaseResponse.self, from: data)
            let remoteClean = Self.cleanVersionString(release.tagName)
            let pageURL = URL(string: release.htmlURL) ?? Self.releasesPageURL

            let dmgAssetURL = release.assets
                .first(where: { $0.name.lowercased().hasSuffix(".dmg") })
                .flatMap { URL(string: $0.browserDownloadURL) }
            let downloadURL = dmgAssetURL ?? pageURL

            if Self.isVersion(release.tagName, newerThan: localVersion) {
                state = .updateAvailable(
                    latestVersion: remoteClean.isEmpty ? release.tagName : remoteClean,
                    downloadURL: downloadURL,
                    releasePageURL: pageURL,
                    releaseNotes: release.body ?? ""
                )
                if manual {
                    isUpdateModalPresented = true
                }
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

    public func downloadAndInstallUpdate(from downloadURL: URL, silent: Bool = false) async {
        isInstallingUpdate = true
        installProgress = 0.1
        installErrorMessage = nil

        let config = URLSessionConfiguration.ephemeral
        config.httpCookieAcceptPolicy = .never
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let session = URLSession(configuration: config)

        do {
            let (tempLocalURL, _) = try await session.download(from: downloadURL)
            installProgress = 0.6

            let fileManager = FileManager.default
            let dmgPath = tempLocalURL.path

            if downloadURL.pathExtension.lowercased() == "dmg" || dmgPath.hasSuffix(".dmg") {
                let mountPoint = "/Volumes/PasteVaultUpdate_\(UUID().uuidString.prefix(6))"
                let attachProcess = Process()
                attachProcess.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
                attachProcess.arguments = ["attach", "-nobrowse", "-readonly", dmgPath, "-mountpoint", mountPoint]
                try attachProcess.run()
                attachProcess.waitUntilExit()

                if attachProcess.terminationStatus == 0 {
                    installProgress = 0.8
                    let mountedAppPath = "\(mountPoint)/Paste Vault.app"
                    let targetAppPath = "/Applications/Paste Vault.app"

                    if fileManager.fileExists(atPath: mountedAppPath) {
                        let sourceBinary = "\(mountedAppPath)/Contents/MacOS/Paste Vault"
                        let targetBinary = "\(targetAppPath)/Contents/MacOS/Paste Vault"

                        if fileManager.fileExists(atPath: sourceBinary) && fileManager.fileExists(atPath: targetBinary) {
                            try? fileManager.removeItem(atPath: targetBinary)
                            try fileManager.copyItem(atPath: sourceBinary, toPath: targetBinary)

                            let codesignProcess = Process()
                            codesignProcess.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
                            codesignProcess.arguments = ["--force", "--deep", "--sign", "-", "--identifier", "com.pastevault.app", targetAppPath]
                            try? codesignProcess.run()
                            codesignProcess.waitUntilExit()
                        }
                    }

                    let detachProcess = Process()
                    detachProcess.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
                    detachProcess.arguments = ["detach", mountPoint, "-force"]
                    try? detachProcess.run()
                    detachProcess.waitUntilExit()
                }
            } else {
                NSWorkspace.shared.open(downloadURL)
            }

            installProgress = 1.0
            isInstallingUpdate = false

            if !silent {
                dismissModal()
                // Перезапуск обновлённого приложения
                let relaunch = Process()
                relaunch.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                relaunch.arguments = ["-a", "/Applications/Paste Vault.app"]
                try? relaunch.run()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    NSApplication.shared.terminate(nil)
                }
            }
        } catch {
            isInstallingUpdate = false
            installErrorMessage = error.localizedDescription
            if !silent {
                NSWorkspace.shared.open(downloadURL)
            }
        }
    }

    public func openDownloadOrReleasePage() {
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
        NSWorkspace.shared.open(Self.projectPageURL)
    }
}
