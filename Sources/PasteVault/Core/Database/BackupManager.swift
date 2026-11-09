import Foundation
import AppKit

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

    public init(
        selectedThemeId: String? = nil,
        userGlassLevel: Double? = nil,
        selectedFontId: String? = nil,
        appLanguage: String? = nil,
        historyLimit: Int? = nil,
        saveFiles: Bool? = nil,
        saveImages: Bool? = nil,
        saveText: Bool? = nil
    ) {
        self.selectedThemeId = selectedThemeId
        self.userGlassLevel = userGlassLevel
        self.selectedFontId = selectedFontId
        self.appLanguage = appLanguage
        self.historyLimit = historyLimit
        self.saveFiles = saveFiles
        self.saveImages = saveImages
        self.saveText = saveText
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
    public var appVersion: String = "1.0.0"
    public var clipboardItems: [BackupClipboardItem]?
    public var snippets: [QuickSnippetItem]?
    public var settings: BackupSettingsPayload?

    public init(
        version: Int = 1,
        createdAt: Date = Date(),
        appVersion: String = "1.0.0",
        clipboardItems: [BackupClipboardItem]? = nil,
        snippets: [QuickSnippetItem]? = nil,
        settings: BackupSettingsPayload? = nil
    ) {
        self.version = version
        self.createdAt = createdAt
        self.appVersion = appVersion
        self.clipboardItems = clipboardItems
        self.snippets = snippets
        self.settings = settings
    }
}

// MARK: - Backup Manager Service

public enum BackupManager {

    /// Формирует архив резервной копии на основе выбранных пользователем категорий
    @MainActor
    public static func buildArchive(
        items: [ClipboardItemRow],
        monitor: ClipboardMonitor,
        snippets: [QuickSnippetItem],
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
                        base64Img = rawData.base64EncodedString()
                    } else if let img = monitor.imageForItem(item),
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
        if includeSnippets {
            archiveSnippets = snippetsPinnedOnly ? snippets.filter { $0.isPinned } : snippets
        }

        var settingsPayload: BackupSettingsPayload? = nil
        if includeBlacklist || includeShortcuts || includeAppearance {
            var payload = BackupSettingsPayload()
            if includeBlacklist {
                payload.blacklistedBundleIDs = monitor.blacklistedBundleIDs
            }
            if includeShortcuts {
                payload.shortcutsData = try? JSONEncoder().encode(ShortcutManager.shared.config)
            }
            if includeAppearance {
                payload.appearanceAndStorage = BackupAppearanceAndStorage(
                    selectedThemeId: UserDefaults.standard.string(forKey: "selectedThemeId"),
                    userGlassLevel: UserDefaults.standard.double(forKey: "userGlassLevel"),
                    selectedFontId: UserDefaults.standard.string(forKey: "selectedFontId"),
                    appLanguage: UserDefaults.standard.string(forKey: "appLanguage"),
                    historyLimit: monitor.maxHistoryLimit,
                    saveFiles: monitor.saveFilesEnabled,
                    saveImages: monitor.saveImagesEnabled,
                    saveText: monitor.saveTextEnabled
                )
            }
            settingsPayload = payload
        }

        return PasteVaultBackupArchive(
            version: 1,
            createdAt: Date(),
            appVersion: "1.0.0",
            clipboardItems: archiveItems,
            snippets: archiveSnippets,
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
                // Полная замена: предварительно очищаем текущую БД и монитор
                try await DatabaseManager.shared.clearAllHistory()
                await MainActor.run {
                    monitor.clearAllHistory()
                }
            }

            let appSupport = try? FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appendingPathComponent("PasteVault/Screenshots", isDirectory: true)

            for item in backupItems {
                let kind = ContentKind(rawValue: item.contentType) ?? .text
                var finalFilePath = item.fileURLPath

                // Сохранение скриншота на диск в Application Support
                if let b64 = item.imagePNGDataBase64, let data = Data(base64Encoded: b64) {
                    if let appSupport {
                        let fileURL = appSupport.appendingPathComponent("\(item.id).png")
                        try? data.write(to: fileURL)
                        if finalFilePath == nil {
                            finalFilePath = fileURL.path
                        }
                    }
                    if let nsImg = NSImage(data: data) {
                        await MainActor.run {
                            monitor.imagePreviews[item.id] = nsImg
                        }
                    }
                }

                try await DatabaseManager.shared.restoreItem(
                    id: item.id,
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
                    useCount: item.useCount
                )
            }

            // Мгновенная перезагрузка истории в памяти монитора
            await monitor.loadInitialHistory()
        }

        // 2. Восстановление быстрых фрагментов (Snippets)
        if restoreSnippets, let backupSnippets = archive.snippets {
            var updatedSnippets: [QuickSnippetItem]
            if mergeMode {
                var merged = currentSnippets
                for snip in backupSnippets {
                    if let existingIndex = merged.firstIndex(where: { $0.id == snip.id || ($0.title == snip.title && $0.content == snip.content) }) {
                        if snip.isPinned && !merged[existingIndex].isPinned {
                            merged[existingIndex].isPinned = true
                        }
                    } else {
                        merged.append(snip)
                    }
                }
                updatedSnippets = merged
            } else {
                updatedSnippets = backupSnippets
            }

            if let encoded = try? JSONEncoder().encode(updatedSnippets) {
                UserDefaults.standard.set(encoded, forKey: "pasteVaultQuickSnippets")
            }
            let snippetsToPass = updatedSnippets
            await MainActor.run {
                onUpdateSnippets(snippetsToPass)
            }
        }

        // 3. Восстановление настроек и чёрного списка
        if restoreSettings, let settings = archive.settings {
            if let blacklist = settings.blacklistedBundleIDs {
                await MainActor.run {
                    if mergeMode {
                        let combined = Array(Set(monitor.blacklistedBundleIDs).union(blacklist))
                        monitor.blacklistedBundleIDs = combined
                    } else {
                        monitor.blacklistedBundleIDs = blacklist
                    }
                }
            }

            if let shortcutsData = settings.shortcutsData,
               let config = try? JSONDecoder().decode(ShortcutConfig.self, from: shortcutsData) {
                await MainActor.run {
                    ShortcutManager.shared.config = config
                }
            }

            if let appearance = settings.appearanceAndStorage {
                await MainActor.run {
                    if let theme = appearance.selectedThemeId {
                        UserDefaults.standard.set(theme, forKey: "selectedThemeId")
                        UserDefaults.standard.set(theme, forKey: "pasteVaultTheme")
                        let isLight = (theme == "frost" || theme == "solarizedPaper")
                        NSApp.windows.first(where: { $0 is NSPanel })?.appearance = NSAppearance(named: isLight ? .aqua : .darkAqua)
                    }
                    if let glass = appearance.userGlassLevel {
                        UserDefaults.standard.set(glass, forKey: "userGlassLevel")
                    }
                    if let font = appearance.selectedFontId {
                        UserDefaults.standard.set(font, forKey: "selectedFontId")
                    }
                    if let lang = appearance.appLanguage {
                        UserDefaults.standard.set(lang, forKey: "appLanguage")
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
                }
            }
        }
    }

    /// Сохраняет архив в формате форматированного JSON
    public static func exportArchiveToFile(archive: PasteVaultBackupArchive, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(archive)
        try data.write(to: url, options: .atomic)
    }

    /// Читает и валидирует архив из JSON файла
    public static func loadArchiveFromFile(from url: URL) throws -> PasteVaultBackupArchive {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PasteVaultBackupArchive.self, from: data)
    }
}
