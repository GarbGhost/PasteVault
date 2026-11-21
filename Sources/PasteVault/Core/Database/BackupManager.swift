import Foundation
import AppKit
import CryptoKit
import CommonCrypto
import Security

// MARK: - Backup Models

public struct BackupClipboardItem: Codable, Equatable, Sendable {
    public let id: String
    public let contentType: Int32
    public let textPreview: String
    public let contentHash: String
    public let sourceBundleId: String?
    public let sourceAppName: String?
    public let isSensitive: Bool
    public let secretKind: String?
    public let isPinned: Bool
    public let createdAt: Int64
    public let expiresAt: Int64?
    public let ocrText: String?
    public let fileURLPath: String?
    public let useCount: Int
    public let imagePNGDataBase64: String?

    enum CodingKeys: String, CodingKey {
        case id, contentType, textPreview, contentHash, sourceBundleId, sourceAppName
        case isSensitive, secretKind, isPinned, createdAt, expiresAt, ocrText
        case fileURLPath, useCount, imagePNGDataBase64
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.contentType = try container.decode(Int32.self, forKey: .contentType)
        self.textPreview = try container.decode(String.self, forKey: .textPreview)
        self.contentHash = try container.decode(String.self, forKey: .contentHash)
        self.sourceBundleId = try container.decodeIfPresent(String.self, forKey: .sourceBundleId)
        self.sourceAppName = try container.decodeIfPresent(String.self, forKey: .sourceAppName)
        self.isSensitive = try container.decodeIfPresent(Bool.self, forKey: .isSensitive) ?? false
        self.secretKind = try container.decodeIfPresent(String.self, forKey: .secretKind)
        self.isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        self.createdAt = try container.decode(Int64.self, forKey: .createdAt)
        self.expiresAt = try container.decodeIfPresent(Int64.self, forKey: .expiresAt)
        self.ocrText = try container.decodeIfPresent(String.self, forKey: .ocrText)
        self.fileURLPath = try container.decodeIfPresent(String.self, forKey: .fileURLPath)
        self.useCount = try container.decodeIfPresent(Int.self, forKey: .useCount) ?? 0
        self.imagePNGDataBase64 = try container.decodeIfPresent(String.self, forKey: .imagePNGDataBase64)
    }

    public init(
        id: String,
        contentType: Int32,
        textPreview: String,
        contentHash: String,
        sourceBundleId: String?,
        sourceAppName: String?,
        isSensitive: Bool,
        secretKind: String?,
        isPinned: Bool,
        createdAt: Int64,
        expiresAt: Int64?,
        ocrText: String?,
        fileURLPath: String?,
        useCount: Int,
        imagePNGDataBase64: String? = nil
    ) {
        self.id = id
        self.contentType = contentType
        self.textPreview = textPreview
        self.contentHash = contentHash
        self.sourceBundleId = sourceBundleId
        self.sourceAppName = sourceAppName
        self.isSensitive = isSensitive
        self.secretKind = secretKind
        self.isPinned = isPinned
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.ocrText = ocrText
        self.fileURLPath = fileURLPath
        self.useCount = useCount
        self.imagePNGDataBase64 = imagePNGDataBase64
    }

    public init(from row: ClipboardItemRow, imageBase64: String? = nil) {
        self.id = row.id
        self.contentType = row.contentType.rawValue
        self.textPreview = row.textPreview
        self.contentHash = row.contentHash
        self.sourceBundleId = row.sourceBundleId
        self.sourceAppName = row.sourceAppName
        self.isSensitive = row.isSensitive
        self.secretKind = row.secretKind
        self.isPinned = row.isPinned
        self.createdAt = row.createdAt
        self.expiresAt = row.expiresAt.map { Int64($0.timeIntervalSince1970) }
        self.ocrText = row.ocrText
        self.fileURLPath = row.fileURLPath
        self.useCount = row.useCount
        self.imagePNGDataBase64 = imageBase64
    }

    public func toClipboardItemRow(imageData: Data? = nil) -> ClipboardItemRow {
        let kind = ContentKind(rawValue: contentType) ?? .text
        let expDate = expiresAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        return ClipboardItemRow(
            id: id,
            rowid: createdAt,
            contentType: kind,
            textPreview: textPreview,
            contentHash: contentHash,
            sourceBundleId: sourceBundleId,
            sourceAppName: sourceAppName,
            isSensitive: isSensitive,
            secretKind: secretKind,
            isPinned: isPinned,
            createdAt: createdAt,
            expiresAt: expDate,
            ocrText: ocrText,
            rawImageData: imageData,
            fileURLPath: fileURLPath,
            useCount: useCount
        )
    }
}

public struct BackupAppearanceAndStorage: Codable, Equatable, Sendable {
    public var selectedThemeId: String?
    public var userGlassLevel: Double?
    public var selectedFontId: String?
    public var appLanguage: String?
    public var historyLimit: Int?
    public var saveFiles: Bool?
    public var saveImages: Bool?
    public var saveText: Bool?
    public var soundEnabled: Bool?
    public var autoCheckUpdates: Bool?
    public var launchAtLogin: Bool?

    enum CodingKeys: String, CodingKey {
        case selectedThemeId, userGlassLevel, selectedFontId, appLanguage
        case historyLimit, saveFiles, saveImages, saveText
        case soundEnabled, autoCheckUpdates, launchAtLogin
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.selectedThemeId = try container.decodeIfPresent(String.self, forKey: .selectedThemeId)
        self.userGlassLevel = try container.decodeIfPresent(Double.self, forKey: .userGlassLevel)
        self.selectedFontId = try container.decodeIfPresent(String.self, forKey: .selectedFontId)
        self.appLanguage = try container.decodeIfPresent(String.self, forKey: .appLanguage)
        self.historyLimit = try container.decodeIfPresent(Int.self, forKey: .historyLimit)
        self.saveFiles = try container.decodeIfPresent(Bool.self, forKey: .saveFiles)
        self.saveImages = try container.decodeIfPresent(Bool.self, forKey: .saveImages)
        self.saveText = try container.decodeIfPresent(Bool.self, forKey: .saveText)
        self.soundEnabled = try container.decodeIfPresent(Bool.self, forKey: .soundEnabled)
        self.autoCheckUpdates = try container.decodeIfPresent(Bool.self, forKey: .autoCheckUpdates)
        self.launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin)
    }

    public init(
        selectedThemeId: String? = nil,
        userGlassLevel: Double? = nil,
        selectedFontId: String? = nil,
        appLanguage: String? = nil,
        historyLimit: Int? = nil,
        saveFiles: Bool? = nil,
        saveImages: Bool? = nil,
        saveText: Bool? = nil,
        soundEnabled: Bool? = nil,
        autoCheckUpdates: Bool? = nil,
        launchAtLogin: Bool? = nil
    ) {
        self.selectedThemeId = selectedThemeId
        self.userGlassLevel = userGlassLevel
        self.selectedFontId = selectedFontId
        self.appLanguage = appLanguage
        self.historyLimit = historyLimit
        self.saveFiles = saveFiles
        self.saveImages = saveImages
        self.saveText = saveText
        self.soundEnabled = soundEnabled
        self.autoCheckUpdates = autoCheckUpdates
        self.launchAtLogin = launchAtLogin
    }
}

public struct BackupSettingsPayload: Codable, Equatable, Sendable {
    public var blacklistedBundleIDs: [String]?
    public var shortcutsData: Data?
    public var appearanceAndStorage: BackupAppearanceAndStorage?

    public init(
        blacklistedBundleIDs: [String]? = nil,
        shortcutsData: Data? = nil,
        appearanceAndStorage: BackupAppearanceAndStorage? = nil
    ) {
        self.blacklistedBundleIDs = blacklistedBundleIDs
        self.shortcutsData = shortcutsData
        self.appearanceAndStorage = appearanceAndStorage
    }
}

public struct PasteVaultBackupArchive: Codable, Equatable, Sendable {
    public var version: Int = 1
    public var createdAt: Date = Date()
    public var appVersion: String = "1.1.5"
    public var clipboardItems: [BackupClipboardItem]?
    public var snippets: [QuickSnippetItem]?
    public var snippetCategories: [SnippetCategoryRecord]?
    public var settings: BackupSettingsPayload?

    public init(
        version: Int = 1,
        createdAt: Date = Date(),
        appVersion: String = "1.1.5",
        clipboardItems: [BackupClipboardItem]? = nil,
        snippets: [QuickSnippetItem]? = nil,
        snippetCategories: [SnippetCategoryRecord]? = nil,
        settings: BackupSettingsPayload? = nil
    ) {
        self.version = version
        self.createdAt = createdAt
        self.appVersion = appVersion
        self.clipboardItems = clipboardItems
        self.snippets = snippets
        self.snippetCategories = snippetCategories
        self.settings = settings
    }

    enum CodingKeys: String, CodingKey {
        case version, createdAt, appVersion, clipboardItems, snippets, snippetCategories, settings
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        self.appVersion = try container.decodeIfPresent(String.self, forKey: .appVersion) ?? "1.1.5"
        self.clipboardItems = try container.decodeIfPresent([BackupClipboardItem].self, forKey: .clipboardItems)
        self.snippets = try container.decodeIfPresent([QuickSnippetItem].self, forKey: .snippets)
        self.snippetCategories = try container.decodeIfPresent([SnippetCategoryRecord].self, forKey: .snippetCategories)
        self.settings = try container.decodeIfPresent(BackupSettingsPayload.self, forKey: .settings)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(appVersion, forKey: .appVersion)
        try container.encodeIfPresent(clipboardItems, forKey: .clipboardItems)
        try container.encodeIfPresent(snippets, forKey: .snippets)
        try container.encodeIfPresent(snippetCategories, forKey: .snippetCategories)
        try container.encodeIfPresent(settings, forKey: .settings)
    }
}

// MARK: - Backup Manager Service

public enum BackupManager {

    private static func sanitizedSafeFilenameComponent(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains("/"),
              !trimmed.contains("\\"),
              !trimmed.contains(".."),
              !trimmed.contains("\0") else {
            return UUID().uuidString
        }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
        if trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) && trimmed.count <= 128 {
            return trimmed
        }
        return UUID().uuidString
    }

    private static func readDiskPNGData(for item: ClipboardItemRow) -> Data? {
        let fm = FileManager.default
        if let safeURL = DatabaseManager.safeScreenshotFileURL(for: item.fileURLPath, itemId: item.id),
           let data = try? Data(contentsOf: safeURL),
           !data.isEmpty {
            return data
        }

        guard let supportDir = try? DatabaseManager.pasteVaultSupportDirectory() else { return nil }
        let safeId = sanitizedSafeFilenameComponent(item.id)
        let candidatePaths = [
            supportDir.appendingPathComponent("Screenshots", isDirectory: true).appendingPathComponent("\(safeId).png"),
            supportDir.appendingPathComponent("Images", isDirectory: true).appendingPathComponent("\(safeId).png")
        ]
        for url in candidatePaths where fm.fileExists(atPath: url.path) {
            if let data = try? Data(contentsOf: url), !data.isEmpty {
                return data
            }
        }
        return nil
    }

    @MainActor
    public static func captureSettings(
        monitor: ClipboardMonitor,
        includeBlacklist: Bool,
        includeShortcuts: Bool,
        includeAppearance: Bool
    ) -> BackupSettingsPayload? {
        guard includeBlacklist || includeShortcuts || includeAppearance else { return nil }
        var payload = BackupSettingsPayload()
        if includeBlacklist {
            payload.blacklistedBundleIDs = monitor.blacklistedBundleIDs
        }
        if includeShortcuts {
            payload.shortcutsData = try? JSONEncoder().encode(ShortcutManager.shared.config)
        }
        if includeAppearance {
            let defaults = AppDefaults.shared
            let theme = defaults.string(forKey: "selectedThemeId")
                ?? defaults.string(forKey: "pasteVaultTheme")
                ?? AppTheme.obsidian.rawValue
            let glass = defaults.object(forKey: "userGlassLevel") != nil
                ? defaults.double(forKey: "userGlassLevel")
                : 0.70
            let font = defaults.string(forKey: "selectedFontId") ?? AppFont.default.rawValue
            let lang = defaults.string(forKey: "appLanguage") ?? AppLanguage.ru.rawValue
            let sound = defaults.object(forKey: "tapticAudioFeedbackEnabled") != nil
                ? defaults.bool(forKey: "tapticAudioFeedbackEnabled")
                : true
            let autoUpdates = defaults.object(forKey: "autoCheckUpdates") != nil
                ? defaults.bool(forKey: "autoCheckUpdates")
                : UpdateService.shared.autoCheckUpdates
            let launch = DatabaseManager.isRunningTests
                ? monitor.isLaunchAtLoginEnabled
                : LaunchAtLoginManager.shared.isEnabled

            payload.appearanceAndStorage = BackupAppearanceAndStorage(
                selectedThemeId: theme,
                userGlassLevel: glass,
                selectedFontId: font,
                appLanguage: lang,
                historyLimit: monitor.maxHistoryLimit,
                saveFiles: monitor.saveFilesEnabled,
                saveImages: monitor.saveImagesEnabled,
                saveText: monitor.saveTextEnabled,
                soundEnabled: sound,
                autoCheckUpdates: autoUpdates,
                launchAtLogin: launch
            )
        }
        return payload
    }

    /// Формирует архив резервной копии на основе выбранных пользователем категорий
    @MainActor
    public static func buildArchive(
        items: [ClipboardItemRow],
        monitor: ClipboardMonitor,
        snippets: [QuickSnippetItem],
        snippetCategories: [SnippetCategoryRecord] = [],
        includeClipboard: Bool,
        clipboardPinnedOnly: Bool,
        includeSnippets: Bool,
        snippetsPinnedOnly: Bool,
        includeBlacklist: Bool,
        includeShortcuts: Bool,
        includeAppearance: Bool
    ) -> PasteVaultBackupArchive {
        var archiveItems: [BackupClipboardItem]? = nil
        if includeClipboard {
            let candidates = clipboardPinnedOnly ? items.filter { $0.isPinned } : items
            archiveItems = candidates.map { item in
                var base64Img: String? = nil
                if item.effectiveContentType == .image {
                    if let rawData = item.rawImageData {
                        if let bitmap = NSBitmapImageRep(data: rawData),
                           let png = bitmap.representation(using: .png, properties: [:]) {
                            base64Img = png.base64EncodedString()
                        } else {
                            base64Img = rawData.base64EncodedString()
                        }
                    } else if let diskData = readDiskPNGData(for: item) {
                        if let bitmap = NSBitmapImageRep(data: diskData),
                           let png = bitmap.representation(using: .png, properties: [:]) {
                            base64Img = png.base64EncodedString()
                        } else {
                            base64Img = diskData.base64EncodedString()
                        }
                    } else if let img = monitor.imagePreviews[item.id],
                              let tiff = img.tiffRepresentation,
                              let bitmap = NSBitmapImageRep(data: tiff),
                              let png = bitmap.representation(using: .png, properties: [:]) {
                        base64Img = png.base64EncodedString()
                    }
                }
                return BackupClipboardItem(from: item, imageBase64: base64Img)
            }
        }

        var archiveSnippets: [QuickSnippetItem]? = nil
        var archiveCategories: [SnippetCategoryRecord]? = nil
        if includeSnippets {
            var snips = snippetsPinnedOnly ? snippets.filter { $0.isPinned } : snippets
            for i in 0..<snips.count {
                if let path = snips[i].imagePath, snips[i].imageDataBase64 == nil,
                   let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
                    snips[i].imageDataBase64 = data.base64EncodedString()
                }
            }
            archiveSnippets = snips
            archiveCategories = snippetCategories
        }

        let settingsPayload = captureSettings(
            monitor: monitor,
            includeBlacklist: includeBlacklist,
            includeShortcuts: includeShortcuts,
            includeAppearance: includeAppearance
        )

        return PasteVaultBackupArchive(
            version: 2,
            createdAt: Date(),
            appVersion: (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.1.5",
            clipboardItems: archiveItems,
            snippets: archiveSnippets,
            snippetCategories: archiveCategories,
            settings: settingsPayload
        )
    }

    /// Восстанавливает архив в систему в режиме объединения (Merge) или полной замены (Replace)
    public static func restoreArchive(
        _ archive: PasteVaultBackupArchive,
        restoreClipboard: Bool,
        restoreSnippets: Bool,
        restoreSettings: Bool,
        mergeMode: Bool,
        monitor: ClipboardMonitor,
        currentSnippets: [QuickSnippetItem],
        onUpdateSnippets: @MainActor @escaping ([QuickSnippetItem]) -> Void
    ) async throws {
        // 1. Восстановление буфера обмена
        if restoreClipboard, let backupItems = archive.clipboardItems {
            if !mergeMode {
                // Полная замена: строго синхронно очищаем БД и память ДО цикла restoreItem (без фоновой гонки)
                try await DatabaseManager.shared.clearAllHistory()
                await MainActor.run {
                    monitor.clearAllHistoryInMemory()
                }
            }

            let fm = FileManager.default
            let screenshotsDir = try? DatabaseManager.pasteVaultSupportDirectory()
                .appendingPathComponent("Screenshots", isDirectory: true)
            if let screenshotsDir {
                try? fm.createDirectory(at: screenshotsDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            }

            for item in backupItems {
                let kind = ContentKind(rawValue: item.contentType) ?? .text
                let safeItemId = sanitizedSafeFilenameComponent(item.id)
                var finalFilePath: String? = nil
                if let candidatePath = item.fileURLPath?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !candidatePath.isEmpty,
                   !candidatePath.contains("..") {
                    if kind == .file {
                        finalFilePath = candidatePath
                    } else if let screenshotsDir {
                        let resolvedScreenshots = screenshotsDir.resolvingSymlinksInPath().standardized.path + "/"
                        let resolvedCandidate = URL(fileURLWithPath: candidatePath).deletingLastPathComponent().resolvingSymlinksInPath().standardized.path + "/" + URL(fileURLWithPath: candidatePath).lastPathComponent
                        if resolvedCandidate.hasPrefix(resolvedScreenshots) {
                            finalFilePath = candidatePath
                        }
                    }
                }

                // Сохранение скриншота на диск в Application Support/PasteVault/Screenshots
                if let b64 = item.imagePNGDataBase64, let data = Data(base64Encoded: b64) {
                    if let screenshotsDir {
                        let fileURL = screenshotsDir.appendingPathComponent("\(safeItemId).png")
                        if (try? data.write(to: fileURL, options: .atomic)) != nil, finalFilePath == nil {
                            finalFilePath = fileURL.path
                        }
                    }
                    if let nsImg = NSImage(data: data) {
                        await MainActor.run {
                            monitor.imagePreviews[safeItemId] = nsImg
                        }
                    }
                }

                try await DatabaseManager.shared.restoreItem(
                    id: safeItemId,
                    contentType: kind,
                    textPreview: item.textPreview,
                    contentHash: item.contentHash,
                    sourceBundleId: item.sourceBundleId,
                    sourceAppName: item.sourceAppName,
                    isSensitive: item.isSensitive,
                    secretKind: item.secretKind,
                    isPinned: item.isPinned,
                    createdAt: item.createdAt,
                    expiresAt: item.expiresAt,
                    fileURLPath: finalFilePath,
                    useCount: item.useCount,
                    ocrText: item.ocrText
                )
            }

            // Мгновенная перезагрузка истории в памяти монитора
            await monitor.loadInitialHistory()
        }

        // 2. Восстановление быстрых фрагментов (Snippets) и категорий
        if restoreSnippets {
            // Восстановление категорий в DatabaseManager
            if let backupCategories = archive.snippetCategories {
                if !mergeMode {
                    let currentCats = await DatabaseManager.shared.fetchSnippetCategories()
                    for cat in currentCats {
                        _ = try? await DatabaseManager.shared.deleteSnippetCategoryAndSnippets(id: cat.id)
                    }
                    for cat in backupCategories {
                        _ = await DatabaseManager.shared.createSnippetCategory(name: cat.name, iconName: cat.iconName)
                    }
                } else {
                    let currentCats = await DatabaseManager.shared.fetchSnippetCategories()
                    for cat in backupCategories {
                        if !currentCats.contains(where: { $0.name.localizedCaseInsensitiveCompare(cat.name) == .orderedSame }) {
                            _ = await DatabaseManager.shared.createSnippetCategory(name: cat.name, iconName: cat.iconName)
                        }
                    }
                }
            }

            if let backupSnippets = archive.snippets {
                var restoredSnippets: [QuickSnippetItem] = []
                let fm = FileManager.default
                let imagesDir = try? DatabaseManager.pasteVaultSupportDirectory().appendingPathComponent("Images")
                if let imagesDir {
                    try? fm.createDirectory(at: imagesDir, withIntermediateDirectories: true)
                }

                for var snip in backupSnippets {
                    if let base64 = snip.imageDataBase64, let data = Data(base64Encoded: base64), let imagesDir {
                        let filename = "snippet_img_\(UUID().uuidString).png"
                        let fileURL = imagesDir.appendingPathComponent(filename)
                        if (try? data.write(to: fileURL, options: .atomic)) != nil {
                            snip.imagePath = fileURL.path
                        }
                    } else if let existingPath = snip.imagePath {
                        let candidate = existingPath.hasPrefix("/")
                            ? URL(fileURLWithPath: existingPath)
                            : (imagesDir?.appendingPathComponent(existingPath) ?? URL(fileURLWithPath: existingPath))
                        if existingPath.contains("..") || !DatabaseManager.isSafeAllowedSnippetImageURL(candidate) {
                            snip.imagePath = nil
                        }
                    }
                    restoredSnippets.append(snip)
                }

                var updatedSnippets: [QuickSnippetItem]
                if mergeMode {
                    var merged = currentSnippets
                    for snip in restoredSnippets {
                        if let existingIndex = merged.firstIndex(where: { $0.id == snip.id || ($0.title == snip.title && $0.content == snip.content) }) {
                            if snip.isPinned && !merged[existingIndex].isPinned {
                                merged[existingIndex].isPinned = true
                            }
                            if snip.imagePath != nil && merged[existingIndex].imagePath == nil {
                                merged[existingIndex].imagePath = snip.imagePath
                            }
                            merged[existingIndex].useCount = max(merged[existingIndex].useCount, snip.useCount)
                        } else {
                            merged.append(snip)
                        }
                    }
                    updatedSnippets = merged
                } else {
                    updatedSnippets = restoredSnippets
                }

                // Гарантируем, что для всех фрагментов (из старого или нового бэкапа) существуют категории в DatabaseManager
                let fallbackCategory = (AppLanguage.current == .en) ? "Work" : "Работа"
                var activeCats = await DatabaseManager.shared.fetchSnippetCategories()
                var knownLowerNames = Set(activeCats.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
                for snip in updatedSnippets {
                    let catName = snip.category.trimmingCharacters(in: .whitespacesAndNewlines)
                    let targetCategory = catName.isEmpty ? fallbackCategory : catName
                    let targetLower = targetCategory.lowercased()
                    if !knownLowerNames.contains(targetLower) {
                        let icon = (targetCategory == "Поддержка" || targetCategory == "Контакты") ? "bubble.left.and.bubble.right.fill" : "doc.text.fill"
                        if let created = await DatabaseManager.shared.createSnippetCategory(name: targetCategory, iconName: icon) {
                            activeCats.append(created)
                        }
                        knownLowerNames.insert(targetLower)
                    }
                }

                // Синхронизируем восстановленные фрагменты с таблицей snippets в SQLite
                if !mergeMode {
                    await DatabaseManager.shared.deleteAllSnippets()
                }
                for snip in updatedSnippets {
                    let catName = snip.category.trimmingCharacters(in: .whitespacesAndNewlines)
                    let safeCategory = catName.isEmpty ? fallbackCategory : catName
                    _ = await DatabaseManager.shared.insertSnippet(
                        id: snip.id,
                        title: snip.title,
                        content: snip.content,
                        category: safeCategory,
                        isPinned: snip.isPinned,
                        imagePath: snip.imagePath,
                        useCount: snip.useCount,
                        createdAt: snip.createdAt
                    )
                }

                if let encoded = try? JSONEncoder().encode(updatedSnippets) {
                    AppDefaults.shared.set(encoded, forKey: "pasteVaultQuickSnippets")
                }
                let snippetsToPass = updatedSnippets
                await MainActor.run {
                    onUpdateSnippets(snippetsToPass)
                }
            }
        }

        // 3. Восстановление настроек и чёрного списка (строго на @MainActor)
        if restoreSettings, let settings = archive.settings {
            await MainActor.run {
                if let blacklist = settings.blacklistedBundleIDs {
                    if mergeMode {
                        let combined = Array(Set(monitor.blacklistedBundleIDs).union(blacklist))
                        monitor.blacklistedBundleIDs = combined
                    } else {
                        monitor.blacklistedBundleIDs = blacklist
                    }
                }

                if let shortcutsData = settings.shortcutsData,
                   let config = try? JSONDecoder().decode(ShortcutConfig.self, from: shortcutsData) {
                    ShortcutManager.shared.config = config
                    ShortcutManager.shared.objectWillChange.send()
                }

                if let appearance = settings.appearanceAndStorage {
                    if let theme = appearance.selectedThemeId {
                        AppDefaults.shared.set(theme, forKey: "selectedThemeId")
                        AppDefaults.shared.set(theme, forKey: "pasteVaultTheme")
                        let isLight = (theme == "frost" || theme == "solarizedPaper")
                        let targetAppearance = NSAppearance(named: isLight ? .aqua : .darkAqua)
                        for panel in NSApp.windows.compactMap({ $0 as? FloatingPanel<MainPanelView> }) {
                            panel.appearance = targetAppearance
                        }
                    }
                    if let glass = appearance.userGlassLevel {
                        AppDefaults.shared.set(glass, forKey: "userGlassLevel")
                    }
                    if let font = appearance.selectedFontId {
                        let normalizedFont = (font == "jetbrains") ? AppFont.jetBrainsMono.rawValue : font
                        AppDefaults.shared.set(normalizedFont, forKey: "selectedFontId")
                    }
                    if let lang = appearance.appLanguage {
                        AppDefaults.shared.set(lang, forKey: "appLanguage")
                    }
                    if let limit = appearance.historyLimit {
                        monitor.maxHistoryLimit = limit
                        monitor.enforceHistoryLimit()
                    }
                    if let saveFiles = appearance.saveFiles {
                        monitor.saveFilesEnabled = saveFiles
                    }
                    if let saveImages = appearance.saveImages {
                        monitor.saveImagesEnabled = saveImages
                    }
                    if let saveText = appearance.saveText {
                        monitor.saveTextEnabled = saveText
                    }
                    if let sound = appearance.soundEnabled {
                        AppDefaults.shared.set(sound, forKey: "tapticAudioFeedbackEnabled")
                    }
                    if let autoUpdates = appearance.autoCheckUpdates {
                        AppDefaults.shared.set(autoUpdates, forKey: "autoCheckUpdates")
                        UpdateService.shared.autoCheckUpdates = autoUpdates
                        UpdateService.shared.objectWillChange.send()
                    }
                    if let launchAtLogin = appearance.launchAtLogin {
                        if !DatabaseManager.isRunningTests {
                            LaunchAtLoginManager.shared.setLaunchAtLogin(launchAtLogin)
                        }
                        monitor.isLaunchAtLoginEnabled = launchAtLogin
                    }
                }

                AppDefaults.shared.synchronize()
                monitor.objectWillChange.send()
            }
        }
    }

    public enum BackupArchiveError: Error, LocalizedError {
        case passwordRequired
        case incorrectPasswordOrCorrupted
        case randomGenerationFailed(OSStatus)
        case keyDerivationFailed(Int32)
        case corruptedArchive

        public var errorDescription: String? {
            let isEN = AppLanguage.current == .en
            switch self {
            case .passwordRequired:
                return isEN
                    ? "Password is required to decrypt this backup"
                    : "Для расшифровки резервной копии требуется пароль"
            case .incorrectPasswordOrCorrupted:
                return isEN
                    ? "Incorrect password or corrupted backup file"
                    : "Неверный пароль или повреждённый файл бэкапа"
            case .randomGenerationFailed(let status):
                return "CSPRNG error (\(status))"
            case .keyDerivationFailed(let status):
                return "PBKDF2 key derivation error (\(status))"
            case .corruptedArchive:
                return isEN
                    ? "Corrupted backup file format"
                    : "Повреждённый формат файла бэкапа"
            }
        }
    }

    public static let encryptedArchivePrefixV2 = Data("PVENC2:".utf8)
    private static let legacyEncryptedArchivePrefixV1 = Data("PVENC1:".utf8)
    private static let pvenc2SaltByteCount = 16
    private static let pbkdf2Iterations: UInt32 = 200_000
    private static let derivedKeyByteCount = 32

    /// Только для обратной совместимости импорта устаревших архивов `PVENC1:` (при экспорте НЕ используется)
    private static func legacyV1BackupSymmetricKeyForDecodeOnly() -> SymmetricKey {
        let material = Data("com.pastevault.app.backup.aesgcm.v1".utf8)
        let digest = SHA256.hash(data: material)
        return SymmetricKey(data: digest)
    }

    private static func derivePBKDF2Key(password: String, salt: Data) throws -> SymmetricKey {
        let passwordData = Array(password.utf8)
        var derivedBytes = [UInt8](repeating: 0, count: derivedKeyByteCount)
        defer {
            derivedBytes.withUnsafeMutableBufferPointer { buf in
                guard let base = buf.baseAddress else { return }
                for i in 0..<buf.count { base[i] = 0 }
            }
        }

        let rc: Int32 = passwordData.withUnsafeBufferPointer { pwdPtr in
            salt.withUnsafeBytes { saltRaw in
                let pwdPointer: UnsafePointer<Int8>? = pwdPtr.baseAddress.map { UnsafeRawPointer($0).assumingMemoryBound(to: Int8.self) }
                let saltPointer: UnsafePointer<UInt8>? = saltRaw.bindMemory(to: UInt8.self).baseAddress
                return CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    pwdPointer,
                    passwordData.count,
                    saltPointer,
                    salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    pbkdf2Iterations,
                    &derivedBytes,
                    derivedKeyByteCount
                )
            }
        }
        guard rc == kCCSuccess else {
            throw BackupArchiveError.keyDerivationFailed(rc)
        }
        return SymmetricKey(data: Data(derivedBytes))
    }

    public static func isEncryptedPVENC2(_ data: Data) -> Bool {
        data.starts(with: encryptedArchivePrefixV2)
    }

    public static func fileRequiresPassword(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let header = (try? handle.read(upToCount: encryptedArchivePrefixV2.count)) ?? Data()
        return header.starts(with: encryptedArchivePrefixV2)
    }

    /// Кодирует архив в бинарный формат `PVENC2:` (PBKDF2-HMAC-SHA256 200k + AES-256-GCM без двойного base64)
    public static func encodeEncryptedArchiveData(_ archive: PasteVaultBackupArchive, password: String) throws -> Data {
        guard !password.isEmpty else {
            return try encodePlainArchiveData(archive)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(archive)

        var salt = Data(count: pvenc2SaltByteCount)
        let rngStatus = salt.withUnsafeMutableBytes { buf -> OSStatus in
            guard let base = buf.baseAddress else { return errSecParam }
            return SecRandomCopyBytes(kSecRandomDefault, pvenc2SaltByteCount, base)
        }
        guard rngStatus == errSecSuccess else {
            throw BackupArchiveError.randomGenerationFailed(rngStatus)
        }

        let key = try derivePBKDF2Key(password: password, salt: salt)
        let sealed = try AES.GCM.seal(jsonData, using: key)
        guard let combined = sealed.combined else {
            throw CocoaError(.fileWriteUnknown)
        }

        var output = Data()
        output.reserveCapacity(encryptedArchivePrefixV2.count + salt.count + combined.count)
        output.append(encryptedArchivePrefixV2)
        output.append(salt)
        output.append(combined)
        return output
    }

    /// Кодирует архив в открытый JSON (формат v2 с ISO-8601 датами)
    public static func encodePlainArchiveData(_ archive: PasteVaultBackupArchive) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(archive)
    }

    /// Декодирует архив из `PVENC2:` (с паролем), устаревшего `PVENC1:` или открытого JSON (ISO-8601 и Double timestamps)
    public static func decodeArchiveData(_ data: Data, password: String? = nil) throws -> PasteVaultBackupArchive {
        let jsonData: Data
        if data.starts(with: encryptedArchivePrefixV2) {
            guard let password, !password.isEmpty else {
                throw BackupArchiveError.passwordRequired
            }
            let payload = data.dropFirst(encryptedArchivePrefixV2.count)
            // Минимум: 16 байт salt + 12 байт nonce + 16 байт GCM tag
            guard payload.count >= pvenc2SaltByteCount + 28 else {
                throw BackupArchiveError.incorrectPasswordOrCorrupted
            }
            let salt = Data(payload.prefix(pvenc2SaltByteCount))
            let combined = Data(payload.dropFirst(pvenc2SaltByteCount))
            let key = try derivePBKDF2Key(password: password, salt: salt)
            do {
                let box = try AES.GCM.SealedBox(combined: combined)
                jsonData = try AES.GCM.open(box, using: key)
            } catch {
                throw BackupArchiveError.incorrectPasswordOrCorrupted
            }
        } else if data.starts(with: legacyEncryptedArchivePrefixV1) {
            let payloadData = data.dropFirst(legacyEncryptedArchivePrefixV1.count)
            guard let combined = Data(base64Encoded: payloadData) else {
                throw BackupArchiveError.corruptedArchive
            }
            let box = try AES.GCM.SealedBox(combined: combined)
            jsonData = try AES.GCM.open(box, using: legacyV1BackupSymmetricKeyForDecodeOnly())
        } else {
            jsonData = data
        }

        let isoDecoder = JSONDecoder()
        isoDecoder.dateDecodingStrategy = .iso8601
        if let decoded = try? isoDecoder.decode(PasteVaultBackupArchive.self, from: jsonData) {
            return decoded
        }

        // Обратная совместимость со старыми JSON v1 с числовыми Double-датами (secondsSince1970)
        let numericDecoder = JSONDecoder()
        numericDecoder.dateDecodingStrategy = .secondsSince1970
        return try numericDecoder.decode(PasteVaultBackupArchive.self, from: jsonData)
    }

    /// Сохраняет архив: при непустом пароле в зашифрованном формате `PVENC2:`, без пароля — в открытом JSON v2
    public static func exportArchiveToFile(archive: PasteVaultBackupArchive, to url: URL, password: String? = nil) throws {
        let data: Data
        if let password, !password.isEmpty {
            data = try encodeEncryptedArchiveData(archive, password: password)
        } else {
            data = try encodePlainArchiveData(archive)
        }
        try data.write(to: url, options: .atomic)
    }

    /// Читает и валидирует архив (поддерживает `PVENC2:`, `PVENC1:` и открытый JSON)
    public static func loadArchiveFromFile(from url: URL, password: String? = nil) throws -> PasteVaultBackupArchive {
        let data = try Data(contentsOf: url)
        return try decodeArchiveData(data, password: password)
    }
}
