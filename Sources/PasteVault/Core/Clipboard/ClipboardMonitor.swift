import AppKit
import SwiftUI
import Foundation
import ApplicationServices
import CoreGraphics
import Carbon
import CryptoKit
import Vision
import ImageIO
import UniformTypeIdentifiers

@MainActor
public final class ClipboardMonitor: ObservableObject {
    public static let shared = ClipboardMonitor()

    @Published public var items: [ClipboardItemRow] = [] {
        didSet {
            itemsRevision &+= 1
            refreshCachedStorageSize()
        }
    }
    /// Монотонный счётчик изменений массива items (O(1) ключ для кэша фильтрации списка в UI)
    public private(set) var itemsRevision: Int = 0
    @Published public var imagePreviews: [String: NSImage] = [:]
    private let imageCache = NSCache<NSString, NSImage>()
    @Published public private(set) var cachedStorageSize: String = "0 КБ"
    @Published public var annotatedCopyToastMessage: String? = nil
    @Published public var isModalOverlayActive: Bool = false
    @Published public var isEditingScreenshotText: Bool = false
    @Published public var isIncognitoPaused: Bool = false
    @Published public var targetApp: NSRunningApplication?
    @Published public var lastActiveApp: NSRunningApplication?
    @Published public var targetAppName: String = "активное окно"
    @Published public var targetAppIcon: NSImage?
    @Published public var isAccessibilityGranted: Bool = AccessibilityService.isAccessibilityTrusted()
    public var isRecordingShortcut: Bool {
        ShortcutManager.shared.isRecordingShortcut
    }

    // MARK: - Защита строки поиска при авто-вставке (⌘V)
    private var lastSafeSearchQuery: String = ""

    @Published public var searchQuery: String = "" {
        didSet {
            if isPerformingAutoPaste {
                if searchQuery != lastSafeSearchQuery {
                    searchQuery = lastSafeSearchQuery
                }
            } else {
                lastSafeSearchQuery = searchQuery
            }
        }
    }

    @Published public var isPerformingAutoPaste: Bool = false {
        didSet {
            if isPerformingAutoPaste {
                lastSafeSearchQuery = searchQuery
            }
        }
    }

    @AppStorage("autoPurgeSecretsEnabled") public var autoPurgeSecretsEnabled: Bool = false {
        didSet { objectWillChange.send() }
    }
    @AppStorage("autoPurgeSecretsSeconds") public var autoPurgeSecretsSeconds: Int = 60 {
        didSet { objectWillChange.send() }
    }

    // MARK: - Настройки хранения и типов данных (Storage & Types)
    @AppStorage("saveFilesEnabled") public var saveFilesEnabled: Bool = true {
        didSet { objectWillChange.send() }
    }
    @AppStorage("saveImagesEnabled") public var saveImagesEnabled: Bool = true {
        didSet { objectWillChange.send() }
    }
    @AppStorage("saveTextEnabled") public var saveTextEnabled: Bool = true {
        didSet { objectWillChange.send() }
    }
    @AppStorage("maxHistoryLimit") public var maxHistoryLimit: Int = 500 {
        didSet {
            enforceHistoryLimit()
            objectWillChange.send()
        }
    }
    @AppStorage("historySortOrder") public var historySortOrder: String = "lastCopied" {
        didSet {
            applySortOrder()
            objectWillChange.send()
        }
    }

    // MARK: - Ручные переопределения статуса секретности
    public nonisolated static var manuallyDemotedTextIds: Set<String> {
        get {
            let array = UserDefaults.standard.stringArray(forKey: "manuallyDemotedTextIds") ?? []
            return Set(array)
        }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: "manuallyDemotedTextIds")
        }
    }

    public nonisolated static var manuallyPromotedSecretIds: Set<String> {
        get {
            let array = UserDefaults.standard.stringArray(forKey: "manuallyPromotedSecretIds") ?? []
            return Set(array)
        }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: "manuallyPromotedSecretIds")
        }
    }

    public var manuallyDemotedTextIds: Set<String> {
        get { Self.manuallyDemotedTextIds }
        set { Self.manuallyDemotedTextIds = newValue }
    }

    public var manuallyPromotedSecretIds: Set<String> {
        get { Self.manuallyPromotedSecretIds }
        set { Self.manuallyPromotedSecretIds = newValue }
    }

    // MARK: - Автозапуск при входе (Launch at Login)
    @Published public var isLaunchAtLoginEnabled: Bool = LaunchAtLoginManager.shared.isEnabled {
        didSet {
            LaunchAtLoginManager.shared.isEnabled = isLaunchAtLoginEnabled
        }
    }

    /// Форматированный размер хранилища (реальный объём данных самих записей в Paste Vault)
    public var formattedStorageSize: String {
        return cachedStorageSize
    }

    /// Пересчитывает размер хранилища строго при изменениях массива items
    public func refreshCachedStorageSize() {
        let isEn = (UserDefaults.standard.string(forKey: "appLanguage") == "en")
        guard !items.isEmpty else {
            cachedStorageSize = isEn ? "0 KB" : "0 КБ"
            return
        }

        var totalBytes: Int64 = 0
        for item in items {
            // Текстовое содержимое
            totalBytes += Int64(item.textPreview.utf8.count)

            // Данные реальных картинок и скриншотов
            if let rawData = item.rawImageData {
                totalBytes += Int64(rawData.count)
            }

            // Строковый путь к внешнему файлу (сам внешний файл Paste Vault не копирует)
            if let path = item.fileURLPath {
                totalBytes += Int64(path.utf8.count)
            }

            // Фиксированный оверхед метаданных на запись (id, хэш, даты, флаги, SQLite overhead)
            totalBytes += 256
        }

        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.includesUnit = true
        cachedStorageSize = formatter.string(fromByteCount: max(totalBytes, 1024))
    }

    /// Получение изображения из кэша NSCache или декодирование с кэшированием
    public func imageForItem(_ item: ClipboardItemRow) -> NSImage? {
        let key = item.id as NSString
        if let cached = imageCache.object(forKey: key) {
            return cached
        }
        if let preview = imagePreviews[item.id] {
            imageCache.setObject(preview, forKey: key)
            return preview
        }
        if let data = item.rawImageData, let img = NSImage(data: data) {
            imageCache.setObject(img, forKey: key)
            return img
        }
        if item.effectiveContentType == .image {
            let synth = Self.generateSyntheticScreenshotImage(label: item.textPreview)
            imageCache.setObject(synth, forKey: key)
            return synth
        }
        return nil
    }

    /// Удаление изображения из кэша
    public func evictImage(for id: String) {
        imagePreviews.removeValue(forKey: id)
        imageCache.removeObject(forKey: id as NSString)
    }

    /// Полная очистка всей истории буфера (память, превью, база с VACUUM)
    public func clearAllHistory() {
        items.removeAll()
        imagePreviews.removeAll()
        imageCache.removeAllObjects()
        canonicalColorsByItemId.removeAll()
        pausedTimerSeconds.removeAll()
        refreshCachedStorageSize()
        Task {
            try? await DatabaseManager.shared.clearAllHistory()
        }
    }

    /// Очищает только незакрепленные записи из истории буфера, сохраняя закрепленные
    public func clearUnpinnedHistory() {
        let removedIds = items.filter { !$0.isPinned }.map { $0.id }
        items.removeAll(where: { !$0.isPinned })
        for id in removedIds {
            imageCache.removeObject(forKey: id as NSString)
            canonicalColorsByItemId.removeValue(forKey: id)
        }
        let pinnedIds = Set(items.filter { $0.isPinned }.map { $0.id })
        imagePreviews = imagePreviews.filter { pinnedIds.contains($0.key) }
        pausedTimerSeconds = pausedTimerSeconds.filter { pinnedIds.contains($0.key) }
        refreshCachedStorageSize()
        Task {
            try? await DatabaseManager.shared.clearUnpinnedHistory()
        }
    }

    /// Переключает статус закрепления записи (isPinned)
    public func togglePin(for id: String) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        let cur = items[idx]
        let newPinned = !cur.isPinned
        let updated = ClipboardItemRow(
            id: cur.id,
            rowid: cur.rowid,
            contentType: cur.contentType,
            textPreview: cur.textPreview,
            contentHash: cur.contentHash,
            sourceBundleId: cur.sourceBundleId,
            sourceAppName: cur.sourceAppName,
            isSensitive: cur.isSensitive,
            secretKind: cur.secretKind,
            isPinned: newPinned,
            createdAt: cur.createdAt,
            expiresAt: cur.expiresAt,
            ocrText: cur.ocrText,
            rawImageData: cur.rawImageData,
            fileURLPath: cur.fileURLPath,
            useCount: cur.useCount
        )
        items[idx] = updated
        applySortOrder()
        Task {
            try? await DatabaseManager.shared.togglePin(id: id)
        }
    }

    /// Кэш эталонных представлений цвета (HEX, RGB, HSL) для карточек типа .color по itemId.
    /// Гарантирует 100% отсутствие дрейфа точности при переключении HEX <-> RGB <-> HSL.
    private var canonicalColorsByItemId: [String: (hex: String, rgb: String, hsl: String, color: NSColor)] = [:]

    /// Возвращает эталонные строковые форматы (HEX, RGB, HSL) и NSColor для карточки цвета.
    /// При первом вызове рассчитывает и кэширует эталонные значения, сохраняя точность исходного цвета.
    public func colorFormats(for item: ClipboardItemRow) -> (hex: String, rgb: String, hsl: String, color: NSColor)? {
        if let cached = canonicalColorsByItemId[item.id] {
            return cached
        }
        guard let nsColor = SmartClassifier.parseNSColor(item.textPreview) else {
            return nil
        }

        let trimmed = item.textPreview.trimmingCharacters(in: .whitespacesAndNewlines)
        let hex: String
        let rgb: String
        let hsl: String

        if trimmed.hasPrefix("#") {
            hex = trimmed.uppercased()
            rgb = nsColor.rgbString
            hsl = nsColor.hslString
        } else if trimmed.lowercased().hasPrefix("rgb") {
            rgb = trimmed
            hex = nsColor.hexString
            hsl = nsColor.hslString
        } else if trimmed.lowercased().hasPrefix("hsl") {
            hsl = trimmed
            hex = nsColor.hexString
            rgb = nsColor.rgbString
        } else {
            hex = nsColor.hexString
            rgb = nsColor.rgbString
            hsl = nsColor.hslString
        }

        let formats = (hex: hex, rgb: rgb, hsl: hsl, color: nsColor)
        canonicalColorsByItemId[item.id] = formats
        return formats
    }

    /// Регистрирует эталонный цвет для карточки (используется для предварительной инициализации или тестов)
    public func setCanonicalColor(for itemId: String, hex: String, rgb: String, hsl: String, color: NSColor) {
        canonicalColorsByItemId[itemId] = (hex: hex, rgb: rgb, hsl: hsl, color: color)
    }

    /// Удаляет кэш цвета для удалённой записи
    public func evictCanonicalColor(for id: String) {
        canonicalColorsByItemId.removeValue(forKey: id)
    }

    /// Переключает активный формат цвета карточки (.color) на выбранный (HEX, RGB или HSL).
    /// Обновляет item.content / textPreview в памяти и SQLite, сохраняя тип .color,
    /// и записывает выбранную строку в NSPasteboard.general без создания карточки-дубликата.
    public func selectColorFormat(for itemId: String, newText: String) {
        guard let idx = items.firstIndex(where: { $0.id == itemId }) else { return }
        let cur = items[idx]

        // Убедимся, что эталонный кэш цвета для этой карточки сохранён до смены формата текста
        if canonicalColorsByItemId[itemId] == nil {
            _ = colorFormats(for: cur)
        }

        let digest = SHA256.hash(data: Data(newText.utf8))
        let newHash = digest.map { String(format: "%02x", $0) }.joined()

        let updated = ClipboardItemRow(
            id: cur.id,
            rowid: cur.rowid,
            contentType: .color,
            textPreview: newText,
            contentHash: newHash,
            sourceBundleId: cur.sourceBundleId,
            sourceAppName: cur.sourceAppName,
            isSensitive: cur.isSensitive,
            secretKind: cur.secretKind,
            isPinned: cur.isPinned,
            createdAt: cur.createdAt,
            expiresAt: cur.expiresAt,
            ocrText: cur.ocrText,
            rawImageData: cur.rawImageData,
            fileURLPath: cur.fileURLPath,
            useCount: cur.useCount
        )

        items[idx] = updated

        // Синхронизируем системный буфер обмена без создания дубликата
        copyToPasteboardImmediately(text: newText)

        Task {
            try? await DatabaseManager.shared.updateItemText(id: itemId, newText: newText, newHash: newHash, contentType: .color)
        }
    }

    /// Быстрое редактирование текста записи прямо в буфере
    public func updateItemText(id: String, newText: String) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        let cur = items[idx]
        let digest = SHA256.hash(data: Data(newText.utf8))
        let newHash = digest.map { String(format: "%02x", $0) }.joined()
        let updated = ClipboardItemRow(
            id: cur.id,
            rowid: cur.rowid,
            contentType: cur.contentType,
            textPreview: newText,
            contentHash: newHash,
            sourceBundleId: cur.sourceBundleId,
            sourceAppName: cur.sourceAppName,
            isSensitive: cur.isSensitive,
            secretKind: cur.secretKind,
            isPinned: cur.isPinned,
            createdAt: cur.createdAt,
            expiresAt: cur.expiresAt,
            ocrText: cur.ocrText,
            rawImageData: cur.rawImageData,
            fileURLPath: cur.fileURLPath,
            useCount: cur.useCount
        )
        items[idx] = updated
        Task {
            try? await DatabaseManager.shared.updateItemText(id: id, newText: newText, newHash: newHash)
        }
    }

    /// Переключает статус записи между «Пароль» (.secret) и «Текст» (.text)
    public func togglePasswordClassification(for itemId: String) {
        toggleSecretStatus(for: itemId)
    }

    public func toggleSecretStatus(for itemId: String) {
        guard let idx = items.firstIndex(where: { $0.id == itemId }) else { return }
        let current = items[idx]
        let wasSensitive = current.isSensitive || current.effectiveContentType == .secret
        let newSensitive = !wasSensitive

        var demoted = manuallyDemotedTextIds
        var promoted = manuallyPromotedSecretIds

        let newContentType: ContentKind
        let newSecretKind: String?

        if newSensitive {
            // Пользователь скрыл как пароль
            promoted.insert(itemId)
            demoted.remove(itemId)
            newContentType = .secret
            newSecretKind = "Пароль"
        } else {
            // Пользователь сделал обычным текстом
            demoted.insert(itemId)
            promoted.remove(itemId)
            newContentType = .text
            newSecretKind = nil
        }

        manuallyDemotedTextIds = demoted
        manuallyPromotedSecretIds = promoted

        // Сбрасываем таймер для записи
        pausedTimerSeconds.removeValue(forKey: itemId)

        let updated = ClipboardItemRow(
            id: current.id,
            rowid: current.rowid,
            contentType: newContentType,
            textPreview: current.textPreview,
            contentHash: current.contentHash,
            sourceBundleId: current.sourceBundleId,
            sourceAppName: current.sourceAppName,
            isSensitive: newSensitive,
            secretKind: newSecretKind,
            isPinned: current.isPinned,
            createdAt: current.createdAt,
            expiresAt: nil,
            ocrText: current.ocrText,
            rawImageData: current.rawImageData,
            fileURLPath: current.fileURLPath,
            useCount: current.useCount
        )

        items[idx] = updated
        objectWillChange.send()

        Task {
            try? await DatabaseManager.shared.updateSecretStatus(
                id: itemId,
                isSensitive: newSensitive,
                contentType: newContentType,
                secretKind: newSecretKind,
                expiresAt: nil
            )
        }
    }

    /// Контроль лимита истории: удаляет самые старые незакрепленные записи (!isPinned)
    public func enforceHistoryLimit() {
        guard items.count > maxHistoryLimit else { return }
        var unpinnedIndices: [Int] = []
        for idx in stride(from: items.count - 1, through: 0, by: -1) {
            if !items[idx].isPinned {
                unpinnedIndices.append(idx)
                if items.count - unpinnedIndices.count <= maxHistoryLimit {
                    break
                }
            }
        }
        let idsToDelete = unpinnedIndices.map { items[$0].id }
        for idx in unpinnedIndices.sorted(by: >) {
            items.remove(at: idx)
        }
        for id in idsToDelete {
            imagePreviews.removeValue(forKey: id)
        }
        Task {
            for id in idsToDelete {
                try? await DatabaseManager.shared.deleteItem(id: id)
            }
        }
    }

    /// Применяет выбранный порядок сортировки истории, сохраняя закрепленные (isPinned) всегда сверху
    public func applySortOrder() {
        let order = historySortOrder
        items.sort { a, b in
            if a.isPinned != b.isPinned {
                return a.isPinned && !b.isPinned
            }
            switch order {
            case "firstCopied":
                return a.createdAt < b.createdAt
            case "mostUsed":
                if a.useCount != b.useCount {
                    return a.useCount > b.useCount
                }
                return a.createdAt > b.createdAt
            case "lastCopied":
                fallthrough
            default:
                return a.createdAt > b.createdAt
            }
        }
    }

    /// Увеличивает счетчик использований элемента и повторно применяет сортировку
    public func recordItemUsage(id: String) {
        if let idx = items.firstIndex(where: { $0.id == id }) {
            let cur = items[idx]
            let updated = ClipboardItemRow(
                id: cur.id,
                rowid: cur.rowid,
                contentType: cur.contentType,
                textPreview: cur.textPreview,
                contentHash: cur.contentHash,
                sourceBundleId: cur.sourceBundleId,
                sourceAppName: cur.sourceAppName,
                isSensitive: cur.isSensitive,
                secretKind: cur.secretKind,
                isPinned: cur.isPinned,
                createdAt: cur.createdAt,
                expiresAt: cur.expiresAt,
                ocrText: cur.ocrText,
                rawImageData: cur.rawImageData,
                fileURLPath: cur.fileURLPath,
                useCount: cur.useCount + 1
            )
            items[idx] = updated
            applySortOrder()
            Task {
                try? await DatabaseManager.shared.incrementUseCount(id: id)
            }
        }
    }

    public static let defaultBlacklistedBundleIDs: [String] = [
        "com.apple.keychainaccess",
        "com.bitwarden.desktop",
        "org.keepassxc.keepassxc",
        "com.1password.1password",
        "com.agilebits.onepassword7"
    ]
    private static let blacklistedDefaultsKey = "PasteVault_BlacklistedBundleIDs"

    @Published public var blacklistedBundleIDs: [String] = [] {
        didSet {
            UserDefaults.standard.set(blacklistedBundleIDs, forKey: Self.blacklistedDefaultsKey)
            objectWillChange.send()
        }
    }

    public var blacklistedBundleIds: Set<String> {
        Set(blacklistedBundleIDs)
    }

    public func isAppBlacklisted(_ bundleID: String?) -> Bool {
        guard let bundleID = bundleID?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !bundleID.isEmpty else {
            return false
        }
        return blacklistedBundleIDs.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == bundleID }
    }

    public func addBlacklistedApp(bundleID: String) {
        let trimmed = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !isAppBlacklisted(trimmed) {
            blacklistedBundleIDs.append(trimmed)
        }
    }

    public func removeBlacklistedApp(bundleID: String) {
        let trimmedLower = bundleID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        blacklistedBundleIDs.removeAll { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == trimmedLower }
    }

    public func resetBlacklistedAppsToDefaults() {
        blacklistedBundleIDs = Self.defaultBlacklistedBundleIDs
    }

    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var dispatchTimer: DispatchSourceTimer?
    private var purgeTimer: Timer?
    private var accessibilityTimer: Timer?
    private var accessibilityObservers: [NSObjectProtocol] = []
    private var workspaceObserver: NSObjectProtocol?

    private let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    private let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    private let autoGeneratedType = NSPasteboard.PasteboardType("org.nspasteboard.AutoGeneratedType")

    public init() {
        self.lastChangeCount = pasteboard.changeCount
        if let saved = UserDefaults.standard.stringArray(forKey: Self.blacklistedDefaultsKey), !saved.isEmpty {
            self.blacklistedBundleIDs = saved
        } else {
            self.blacklistedBundleIDs = Self.defaultBlacklistedBundleIDs
            UserDefaults.standard.set(Self.defaultBlacklistedBundleIDs, forKey: Self.blacklistedDefaultsKey)
        }
        // Однократная миграция: отключаем принудительное автоудаление по умолчанию, чтобы пароли жили пока пользователь сам не включит таймер
        if !UserDefaults.standard.bool(forKey: "didMigrateManualSecretTimerV2") {
            UserDefaults.standard.set(false, forKey: "autoPurgeSecretsEnabled")
            UserDefaults.standard.set(true, forKey: "didMigrateManualSecretTimerV2")
            self.autoPurgeSecretsEnabled = false
        }
        detectFrontmostExternalApp()
        startPurgeTimer()
        startAccessibilityMonitoring()
        refreshCachedStorageSize()
    }

    public func loadInitialHistory() async {
        var loaded = (try? await DatabaseManager.shared.queryItems(searchQuery: "", limit: Int32(maxHistoryLimit))) ?? []
        if !UserDefaults.standard.bool(forKey: "didMigrateClearExistingTimersV2") {
            UserDefaults.standard.set(true, forKey: "didMigrateClearExistingTimersV2")
            for idx in loaded.indices where loaded[idx].expiresAt != nil {
                loaded[idx].expiresAt = nil
                let itemId = loaded[idx].id
                try? await DatabaseManager.shared.updateExpiresAt(id: itemId, expiresAt: nil)
            }
        }

        // Быстрая проверка существующих записей с типом .code:
        // если по обновленному SmartClassifier запись теперь определяется как .text, обновляем в памяти и в базе
        for idx in loaded.indices where loaded[idx].contentType == .code {
            let cur = loaded[idx]
            let reclassified = SmartClassifier.classify(text: cur.content, isSensitive: cur.isSensitive, isImage: false)
            if reclassified == .text {
                let updated = ClipboardItemRow(
                    id: cur.id,
                    rowid: cur.rowid,
                    contentType: .text,
                    textPreview: cur.textPreview,
                    contentHash: cur.contentHash,
                    sourceBundleId: cur.sourceBundleId,
                    sourceAppName: cur.sourceAppName,
                    isSensitive: cur.isSensitive,
                    secretKind: cur.secretKind,
                    isPinned: cur.isPinned,
                    createdAt: cur.createdAt,
                    expiresAt: cur.expiresAt,
                    ocrText: cur.ocrText,
                    rawImageData: cur.rawImageData,
                    fileURLPath: cur.fileURLPath,
                    useCount: cur.useCount
                )
                loaded[idx] = updated
                try? await DatabaseManager.shared.updateContentType(id: cur.id, contentType: .text)
            }
        }

        // Проверка записей с типом .secret или isSensitive == true:
        // если текст является именем файла (isLikelyFileName) или кириллической строкой без цифр, автоматически переводим в .text
        for idx in loaded.indices {
            let cur = loaded[idx]
            if cur.isSensitive || cur.contentType == .secret {
                if SecretDetector.isLikelyFileName(cur.content) || SecretDetector.isCyrillicSnakeOrKebabWithoutDigits(cur.content) {
                    let updated = ClipboardItemRow(
                        id: cur.id,
                        rowid: cur.rowid,
                        contentType: .text,
                        textPreview: cur.textPreview,
                        contentHash: cur.contentHash,
                        sourceBundleId: cur.sourceBundleId,
                        sourceAppName: cur.sourceAppName,
                        isSensitive: false,
                        secretKind: nil,
                        isPinned: cur.isPinned,
                        createdAt: cur.createdAt,
                        expiresAt: nil,
                        ocrText: cur.ocrText,
                        rawImageData: cur.rawImageData,
                        fileURLPath: cur.fileURLPath,
                        useCount: cur.useCount
                    )
                    loaded[idx] = updated
                    try? await DatabaseManager.shared.updateSecretStatus(
                        id: cur.id,
                        isSensitive: false,
                        contentType: .text,
                        secretKind: nil,
                        expiresAt: nil
                    )
                }
            }
        }

        self.items = loaded
        // Обеспечиваем наличие превью для всех файлов и скриншотов в истории
        for item in loaded {
            if item.contentType == .file {
                if imagePreviews[item.id] == nil, let firstURL = item.fileURLs.first {
                    let icon = NSWorkspace.shared.icon(forFile: firstURL.path)
                    icon.size = NSSize(width: 48, height: 48)
                    imagePreviews[item.id] = icon
                }
            } else if item.effectiveContentType == .image {
                if imagePreviews[item.id] == nil {
                    imagePreviews[item.id] = Self.generateSyntheticScreenshotImage(label: item.textPreview)
                }
            }
        }
        applySortOrder()
    }

    public func startMonitoring() {
        guard dispatchTimer == nil else { return }

        // Сразу проверяем текущий буфер и целевое приложение при запуске
        detectFrontmostExternalApp()
        captureCurrentPasteboard(force: true)

        // Высокочастотный таймер (60 мс = 0.06 сек) со флагом .strict — мгновенная реакция на ⌘+C
        let source = DispatchSource.makeTimerSource(flags: .strict, queue: .main)
        source.schedule(deadline: .now() + .milliseconds(60), repeating: .milliseconds(60), leeway: .milliseconds(5))
        source.setEventHandler { [weak self] in
            self?.captureCurrentPasteboard(force: false)
        }
        source.resume()
        self.dispatchTimer = source

        // Отслеживаем переключение окон в macOS (Warp, Safari, ChatGPT, Antigravity и т.д.)
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let activatedApp = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            Task { @MainActor in
                guard let self else { return }
                if let app = activatedApp,
                   app.activationPolicy == .regular,
                   app.bundleIdentifier != Bundle.main.bundleIdentifier,
                   app.localizedName != "Paste Vault",
                   app.localizedName != "PasteVault",
                   !Self.isIgnoredTarget(app) {
                    self.lastActiveApp = app
                    self.updateTargetApplication(app)
                }
                self.captureCurrentPasteboard(force: false)
            }
        }
    }

    public func stopMonitoring() {
        dispatchTimer?.cancel()
        dispatchTimer = nil
        purgeTimer?.invalidate()
        purgeTimer = nil
        accessibilityTimer?.invalidate()
        accessibilityTimer = nil
        for obs in accessibilityObservers {
            NotificationCenter.default.removeObserver(obs)
        }
        accessibilityObservers.removeAll()
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
            self.workspaceObserver = nil
        }
    }

    /// Постоянный 1-секундный таймер для живого обратного отсчёта и реального удаления истёкших паролей/ключей
    private func startPurgeTimer() {
        purgeTimer?.invalidate()
        purgeTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.purgeExpiredItemsTick()
            }
        }
    }

    public func purgeExpiredItemsTick(referenceDate: Date = Date()) {
        let expiredItems = items.filter { item in
            guard let exp = item.expiresAt else { return false }
            return exp <= referenceDate
        }
        // Вызываем обновление UI и массива ТОЛЬКО тогда, когда запись реально истекла и удаляется!
        guard !expiredItems.isEmpty else { return }

        // Тройной пульсирующий тактильный и аудио-импульс при завершении таймера (00:00)
        TapticSoundAndHaptics.shared.performTriplePurgePulse()

        let currentPasteboardText = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines)

        for expired in expiredItems {
            items.removeAll { $0.id == expired.id }
            imagePreviews.removeValue(forKey: expired.id)

            // Если удаляемый пароль сейчас находится в системном NSPasteboard.general — очищаем буфер обмена!
            if let currentPasteboardText,
               currentPasteboardText == expired.textPreview.trimmingCharacters(in: .whitespacesAndNewlines) {
                pasteboard.clearContents()
                lastChangeCount = pasteboard.changeCount
            }

            let expiredId = expired.id
            Task {
                try? await DatabaseManager.shared.deleteItem(id: expiredId)
            }
        }
    }

    /// Словарь оставшихся секунд для записей на паузе [itemId: remainingSeconds]
    @Published public var pausedTimerSeconds: [String: Int] = [:]

    /// Приостанавливает таймер автоудаления для конкретной записи id
    public func pauseTimerForItem(id: String, remainingSeconds: Int) {
        setItemExpiration(id: id, expiresAt: nil)
        pausedTimerSeconds[id] = max(1, remainingSeconds)
    }

    /// Возобновляет приостановленный таймер автоудаления для конкретной записи id
    public func resumeTimerForItem(id: String) {
        if let paused = pausedTimerSeconds.removeValue(forKey: id) {
            startTimerForItem(id: id, seconds: paused)
        }
    }

    /// Запускает таймер автоудаления ТОЛЬКО для одной конкретной записи id
    public func startTimerForItem(id: String, seconds: Int) {
        pausedTimerSeconds.removeValue(forKey: id)
        let expiration = Date().addingTimeInterval(TimeInterval(seconds))
        setItemExpiration(id: id, expiresAt: expiration)
    }

    /// Мгновенно отменяет таймер автоудаления ТОЛЬКО для одной конкретной записи id (пароль остаётся в истории бессрочно)
    public func cancelTimerForItem(id: String) {
        pausedTimerSeconds.removeValue(forKey: id)
        setItemExpiration(id: id, expiresAt: nil)
    }

    /// Прибавляет дополнительные секунды к таймеру ТОЛЬКО для одной конкретной записи id
    public func addTimeForItem(id: String, seconds: Int) {
        if let paused = pausedTimerSeconds[id] {
            pausedTimerSeconds[id] = paused + seconds
            return
        }
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        let baseDate = items[idx].expiresAt ?? Date()
        let newExpiration = baseDate.addingTimeInterval(TimeInterval(seconds))
        setItemExpiration(id: id, expiresAt: newExpiration)
    }

    /// Устанавливает или отключает индивидуальный таймер автоудаления для конкретной записи
    public func setItemExpiration(id: String, expiresAt: Date?) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        var updated = items
        updated[idx].expiresAt = expiresAt
        self.items = updated
        Task {
            try? await DatabaseManager.shared.updateExpiresAt(id: id, expiresAt: expiresAt)
        }
    }

    /// Системные настройки macOS никогда не должны становиться целью вставки
    nonisolated public static let ignoredTargetBundleIds: Set<String> = [
        "com.apple.systempreferences",
        "com.apple.Settings"
    ]

    nonisolated public static func isIgnoredTarget(_ app: NSRunningApplication?) -> Bool {
        guard let id = app?.bundleIdentifier else { return false }
        return ignoredTargetBundleIds.contains(id)
    }

    /// Обновляет ссылку на целевое приложение, куда будет вставляться текст (Warp, Safari, ChatGPT, Antigravity и т.д.)
    public func updateTargetApplication(_ app: NSRunningApplication?) {
        guard let app,
              !app.isTerminated,
              app.bundleIdentifier != Bundle.main.bundleIdentifier,
              app.localizedName != "Paste Vault",
              app.localizedName != "PasteVault",
              !Self.isIgnoredTarget(app),
              app.activationPolicy == .regular else {
            return
        }
        self.lastActiveApp = app
        self.targetApp = app
        self.targetAppName = app.localizedName ?? "активное окно"
        self.targetAppIcon = app.icon
    }

    /// Определяет текущее внешнее приложение перед открытием Paste Vault (даже если кликнули по меню или Dock)
    public func detectFrontmostExternalApp() {
        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != Bundle.main.bundleIdentifier,
           front.localizedName != "Paste Vault",
           front.localizedName != "PasteVault",
           !Self.isIgnoredTarget(front),
           front.activationPolicy == .regular {
            updateTargetApplication(front)
            return
        }

        // Если текущий lastActiveApp / targetApp еще жив и валиден — сохраняем его, чтобы фоновые утилиты не перебивали цель вставки
        if let current = lastActiveApp ?? targetApp,
           !current.isTerminated,
           current.activationPolicy == .regular,
           current.localizedName != "Paste Vault",
           current.localizedName != "PasteVault",
           !Self.isIgnoredTarget(current),
           current.bundleIdentifier != Bundle.main.bundleIdentifier {
            updateTargetApplication(current)
            return
        }

        // Проверяем самое верхнее окно на экране через CoreGraphics
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return
        }

        let myPID = ProcessInfo.processInfo.processIdentifier
        for entry in windowList {
            guard let layer = entry[kCGWindowLayer as String] as? Int, layer == 0,
                  let ownerPID = entry[kCGWindowOwnerPID as String] as? pid_t, ownerPID != myPID,
                  let bounds = entry[kCGWindowBounds as String] as? [String: CGFloat],
                  (bounds["Width"] ?? 0) > 180, (bounds["Height"] ?? 0) > 120,
                  let app = NSRunningApplication(processIdentifier: ownerPID),
                  app.activationPolicy == .regular,
                  app.localizedName != "Paste Vault",
                  app.localizedName != "PasteVault",
                  !Self.isIgnoredTarget(app),
                  app.bundleIdentifier != Bundle.main.bundleIdentifier else {
                continue
            }
            updateTargetApplication(app)
            return
        }
    }

    /// Мгновенная синхронная проверка буфера (вызывается перед открытием окна и по таймеру)
    public func pollPasteboardImmediately() {
        captureCurrentPasteboard(force: false)
    }

    private func captureCurrentPasteboard(force: Bool) {
        let currentCount = pasteboard.changeCount
        if !force {
            guard currentCount != lastChangeCount else { return }
        }
        lastChangeCount = currentCount

        guard !isIncognitoPaused else { return }

        if let types = pasteboard.types {
            if types.contains(transientType) || types.contains(autoGeneratedType) {
                return
            }
        }

        let frontApp = NSWorkspace.shared.frontmostApplication
        let sourceBundleID = frontApp?.bundleIdentifier ?? lastActiveApp?.bundleIdentifier ?? targetApp?.bundleIdentifier
        if isAppBlacklisted(sourceBundleID) {
            return
        }

        let bundleId = frontApp?.bundleIdentifier
        let appName: String
        if bundleId == Bundle.main.bundleIdentifier {
            appName = "PasteVault"
        } else {
            appName = frontApp?.localizedName ?? targetApp?.localizedName ?? "Системный буфер"
        }

        let isMarkedConcealed = (pasteboard.types?.contains(concealedType) == true) || (pasteboard.types?.contains(autoGeneratedType) == true)

        // 1. ПРИОРИТЕТ 1: Файлы (NSPasteboard.PasteboardType.fileURL / NSFilenamesPboardType)
        // В macOS при копировании файла в Finder в буфер попадает и fileURL, и tiff иконка.
        // Поэтому проверяем fileURL ДО картинок и текста!
        var extractedFileURLs: [URL] = []
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] {
            extractedFileURLs = urls
        }
        if extractedFileURLs.isEmpty, let filenames = pasteboard.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String] {
            extractedFileURLs = filenames.map { URL(fileURLWithPath: $0) }
        }

        if !extractedFileURLs.isEmpty {
            guard saveFilesEnabled else {
                // Если сохранение файлов отключено — полностью игнорируем событие (НЕ переходим к картинкам и тексту)
                return
            }
            captureFileItem(extractedFileURLs, bundleId: bundleId, appName: appName)
            return
        }

        // 2. ПРИОРИТЕТ 2: Изображения (.tiff, .png, когда это НЕ файл)
        if let types = pasteboard.types,
           (types.contains(.tiff) || types.contains(.png)),
           let image = NSImage(pasteboard: pasteboard),
           let tiffData = image.tiffRepresentation {
            guard saveImagesEnabled else {
                // Если сохранение картинок отключено — полностью игнорируем изображение и НЕ запускаем Vision OCR
                return
            }
            captureImageItem(image, tiffData: tiffData, bundleId: bundleId, appName: appName)
            return
        }

        // 3. ПРИОРИТЕТ 3: Текст, ссылки, код (.string)
        if let rawText = pasteboard.string(forType: .string),
           !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard saveTextEnabled else {
                // Если сохранение текста отключено — полностью игнорируем текстовую запись
                return
            }
            captureTextItem(rawText, isMarkedConcealed: isMarkedConcealed, bundleId: bundleId, appName: appName)
            return
        }
    }

    /// Захват файлов
    public func captureFileItem(_ urls: [URL], bundleId: String? = nil, appName: String? = nil) {
        guard !urls.isEmpty else { return }
        guard saveFilesEnabled else { return }

        let firstURL = urls[0]
        let fileName = firstURL.lastPathComponent
        let count = urls.count
        let previewText = count == 1 ? "[Файл: \(fileName)]" : "[Файлы: \(count) шт. — \(fileName) и др.]"

        let fileIcon = NSWorkspace.shared.icon(forFile: firstURL.path)
        fileIcon.size = NSSize(width: 48, height: 48)

        let filePathsString = urls.map { $0.path }.joined(separator: "\n")
        let payloadData = Data(filePathsString.utf8)
        let digest = SHA256.hash(data: payloadData)
        let contentHash = digest.map { String(format: "%02x", $0) }.joined()
        let nowTs = Int64(Date().timeIntervalSince1970)

        let existingItem = items.first(where: { $0.contentHash == contentHash })
        let itemId = existingItem?.id ?? UUID().uuidString
        let isPinned = existingItem?.isPinned ?? false

        let newRow = ClipboardItemRow(
            id: itemId,
            rowid: existingItem?.rowid ?? nowTs,
            contentType: .file,
            textPreview: previewText,
            contentHash: contentHash,
            sourceBundleId: bundleId,
            sourceAppName: appName ?? "Finder",
            isSensitive: false,
            secretKind: nil,
            isPinned: isPinned,
            createdAt: nowTs,
            expiresAt: nil,
            ocrText: filePathsString,
            rawImageData: fileIcon.tiffRepresentation,
            fileURLPath: filePathsString,
            useCount: existingItem?.useCount ?? 0
        )

        imagePreviews[itemId] = fileIcon
        items.removeAll { $0.contentHash == contentHash }
        items.insert(newRow, at: 0)
        applySortOrder()
        enforceHistoryLimit()
        NotificationCenter.default.post(name: Notification.Name("pasteVaultDidCaptureItem"), object: itemId)

        Task {
            _ = try? await DatabaseManager.shared.upsertItem(
                id: itemId,
                contentType: .file,
                textPreview: previewText,
                rawPayload: payloadData,
                sourceBundleId: bundleId,
                sourceAppName: appName,
                isSensitive: false,
                secretKind: nil,
                ttlSeconds: nil,
                fileURLPath: filePathsString
            )
        }
    }

    /// Захват изображений / скриншотов
    public func captureImageItem(_ image: NSImage, tiffData: Data, bundleId: String? = nil, appName: String? = nil) {
        guard saveImagesEnabled else { return }

        let width = Int(image.size.width)
        let height = Int(image.size.height)
        let previewText = "[Скриншот \(width)×\(height) пкс] #OCR"
        let digest = SHA256.hash(data: tiffData)
        let contentHash = digest.map { String(format: "%02x", $0) }.joined()
        let now = Int64(Date().timeIntervalSince1970)

        let existingItem = items.first(where: { $0.contentHash == contentHash })
        let itemId = existingItem?.id ?? UUID().uuidString
        let isPinned = existingItem?.isPinned ?? false
        let ocr = existingItem?.ocrText ?? Self.recognizeOCRText(from: tiffData)

        let newRow = ClipboardItemRow(
            id: itemId,
            rowid: existingItem?.rowid ?? now,
            contentType: .image,
            textPreview: previewText,
            contentHash: contentHash,
            sourceBundleId: bundleId,
            sourceAppName: appName ?? "Снимок экрана",
            isSensitive: false,
            secretKind: nil,
            isPinned: isPinned,
            createdAt: now,
            expiresAt: nil,
            ocrText: ocr,
            rawImageData: tiffData,
            fileURLPath: nil,
            useCount: existingItem?.useCount ?? 0
        )

        imagePreviews[itemId] = image
        items.removeAll { $0.contentHash == contentHash }
        items.insert(newRow, at: 0)
        applySortOrder()
        enforceHistoryLimit()
        NotificationCenter.default.post(name: Notification.Name("pasteVaultDidCaptureItem"), object: itemId)

        Task {
            _ = try? await DatabaseManager.shared.upsertItem(
                id: itemId,
                contentType: .image,
                textPreview: previewText,
                rawPayload: tiffData,
                sourceBundleId: bundleId,
                sourceAppName: appName,
                isSensitive: false,
                secretKind: nil,
                ttlSeconds: nil
            )
        }
    }

    /// Сохраняет размеченный скриншот новой копией в буфер обмена (на 1-е место рядом с оригиналом), не изменяя оригинал
    @discardableResult
    public func saveAnnotatedCopy(from originalItem: ClipboardItem, annotatedImage: NSImage) -> ClipboardItem {
        let width = max(1, Int(annotatedImage.size.width))
        let height = max(1, Int(annotatedImage.size.height))
        let isEn = (UserDefaults.standard.string(forKey: "appLanguage") == "en")
        let previewText = isEn
            ? "[Скриншот \(width)×\(height) px • Annotated] #OCR"
            : "[Скриншот \(width)×\(height) пкс • Разметка] #OCR"

        let itemId = UUID().uuidString
        let tiffData = annotatedImage.tiffRepresentation ?? originalItem.rawImageData ?? Data(itemId.utf8)

        // Уникальный хэш для новой копии, чтобы оригинальная карточка гарантированно осталась нетронутой
        var hashInput = Data()
        hashInput.append(tiffData)
        hashInput.append(Data(itemId.utf8))
        let digest = SHA256.hash(data: hashInput)
        let contentHash = digest.map { String(format: "%02x", $0) }.joined()

        let maxExistingTimestamp = items.map(\.createdAt).max() ?? 0
        let now = max(Int64(Date().timeIntervalSince1970), maxExistingTimestamp + 1)

        let sourceBundle = originalItem.sourceBundleId ?? "com.pastevault.app"
        let sourceApp = originalItem.sourceAppName ?? (isEn ? "Screenshot (Edited)" : "Снимок экрана (Разметка)")
        let ocr = originalItem.ocrText

        let newRow = ClipboardItemRow(
            id: itemId,
            rowid: now,
            contentType: .image,
            textPreview: previewText,
            contentHash: contentHash,
            sourceBundleId: sourceBundle,
            sourceAppName: sourceApp,
            isSensitive: false,
            secretKind: nil,
            isPinned: originalItem.isPinned,
            createdAt: now,
            expiresAt: nil,
            ocrText: ocr,
            rawImageData: tiffData,
            fileURLPath: nil,
            useCount: 0
        )

        imagePreviews[itemId] = annotatedImage
        imageCache.setObject(annotatedImage, forKey: itemId as NSString)
        items.insert(newRow, at: 0)
        applySortOrder()
        enforceHistoryLimit()

        // Записываем размеченное изображение в системный NSPasteboard.general для мгновенной вставки по ⌘+V
        pasteboard.clearContents()
        if let rep = NSBitmapImageRep(data: tiffData),
           let pngData = rep.representation(using: .png, properties: [:]) {
            let pbItem = NSPasteboardItem()
            pbItem.setData(pngData, forType: .png)
            pasteboard.writeObjects([pbItem])
        } else {
            pasteboard.writeObjects([annotatedImage])
        }
        lastChangeCount = pasteboard.changeCount

        let toastMsg = isEn
            ? "Annotated copy saved to clipboard"
            : "Копия с разметкой сохранена в буфер обмена"
        annotatedCopyToastMessage = toastMsg
        NotificationCenter.default.post(name: Notification.Name("pasteVaultDidCaptureItem"), object: itemId)
        NotificationCenter.default.post(name: Notification.Name("pasteVaultDidSaveAnnotatedCopy"), object: itemId)

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) { [weak self] in
            if self?.annotatedCopyToastMessage == toastMsg {
                self?.annotatedCopyToastMessage = nil
            }
        }

        Task {
            _ = try? await DatabaseManager.shared.upsertItem(
                id: itemId,
                contentType: .image,
                textPreview: previewText,
                rawPayload: tiffData,
                sourceBundleId: sourceBundle,
                sourceAppName: sourceApp,
                isSensitive: false,
                secretKind: nil,
                ttlSeconds: nil
            )
        }

        return newRow
    }

    /// Захват текста, ссылок, кода
    public func captureTextItem(_ rawText: String, isMarkedConcealed: Bool = false, bundleId: String? = nil, appName: String? = nil) {
        guard saveTextEnabled else { return }

        let text = String(rawText.prefix(500_000))
        let secretAnalysis = SecretDetector.inspect(text)
        let isSensitive = isMarkedConcealed || secretAnalysis.isSensitive
        let contentKind = SmartClassifier.classify(text: text, isSensitive: isSensitive, isImage: false)
        let isSecretKind = isSensitive || contentKind == .secret

        let payloadData = Data(text.utf8)
        let digest = SHA256.hash(data: payloadData)
        let contentHash = digest.map { String(format: "%02x", $0) }.joined()
        let nowTs = Int64(Date().timeIntervalSince1970)

        let existingItem = items.first(where: { $0.contentHash == contentHash })
        let itemId = existingItem?.id ?? UUID().uuidString
        let isPinned = existingItem?.isPinned ?? false

        // Автотаймер для новых паролей полностью отключен (таймер выставляется только вручную пользователем)
        let expiresAtDate: Date? = existingItem?.expiresAt
        let ttlSeconds: Int64? = expiresAtDate.map { max(1, Int64($0.timeIntervalSinceNow)) }
        let secretKind = secretAnalysis.secretKind ?? (isMarkedConcealed ? "Пароль" : nil)

        let newRow = ClipboardItemRow(
            id: itemId,
            rowid: existingItem?.rowid ?? nowTs,
            contentType: contentKind,
            textPreview: text,
            contentHash: contentHash,
            sourceBundleId: bundleId,
            sourceAppName: appName ?? "Системный буфер",
            isSensitive: isSecretKind,
            secretKind: secretKind,
            isPinned: isPinned,
            createdAt: nowTs,
            expiresAt: expiresAtDate,
            fileURLPath: nil,
            useCount: existingItem?.useCount ?? 0
        )

        items.removeAll { $0.contentHash == contentHash }
        items.insert(newRow, at: 0)
        applySortOrder()
        enforceHistoryLimit()
        NotificationCenter.default.post(name: Notification.Name("pasteVaultDidCaptureItem"), object: itemId)

        Task {
            _ = try? await DatabaseManager.shared.upsertItem(
                id: itemId,
                contentType: contentKind,
                textPreview: text,
                rawPayload: payloadData,
                sourceBundleId: bundleId,
                sourceAppName: appName,
                isSensitive: isSecretKind,
                secretKind: secretKind,
                ttlSeconds: ttlSeconds
            )
        }
    }

    private func classifyContent(text: String, isSensitive: Bool) -> ContentKind {
        SmartClassifier.classify(text: text, isSensitive: isSensitive)
    }

    /// Копирует запись в системный буфер обмена. Для файлов помещает NSURL, для картинок — данные изображения
    public func copyToClipboard(item: ClipboardItemRow, selfDestructAfterSeconds: TimeInterval? = nil) {
        pasteboard.clearContents()

        // 1. Для файлов — записываем реальные NSURL в буфер обмена
        if item.contentType == .file, !item.fileURLs.isEmpty {
            let urls = item.fileURLs.map { $0 as NSURL }
            pasteboard.writeObjects(urls)
            let paths = item.fileURLs.map { $0.path }.joined(separator: "\n")
            pasteboard.setString(paths, forType: .string)
        } else if let img = imagePreviews[item.id] ?? (item.contentType == .image ? (item.rawImageData.flatMap { NSImage(data: $0) }) : nil) {
            // 2. Для картинок — помещаем данные изображения строго в формате .png (БЕЗ .tiff и БЕЗ writeObjects)
            var targetPNGData: Data? = nil
            if let rawData = item.rawImageData,
               let rep = NSBitmapImageRep(data: rawData),
               let png = rep.representation(using: .png, properties: [:]) {
                targetPNGData = png
            } else if let tiff = img.tiffRepresentation,
                      let rep = NSBitmapImageRep(data: tiff),
                      let png = rep.representation(using: .png, properties: [:]) {
                targetPNGData = png
            }

            if let targetPNGData {
                let pbItem = NSPasteboardItem()
                pbItem.setData(targetPNGData, forType: .png)
                pasteboard.writeObjects([pbItem])
            }
        } else {
            // 3. Для текста
            pasteboard.setString(item.textPreview, forType: .string)
        }
        lastChangeCount = pasteboard.changeCount

        if let ttl = selfDestructAfterSeconds {
            let expectedChangeCount = lastChangeCount
            DispatchQueue.main.asyncAfter(deadline: .now() + ttl) { [weak self] in
                guard let self, self.pasteboard.changeCount == expectedChangeCount else { return }
                self.pasteboard.clearContents()
                self.lastChangeCount = self.pasteboard.changeCount
            }
        }
    }

    /// Синхронно кладет текст в системный буфер обмена за 0 мс (без повторного дублирования)
    public func copyToPasteboardImmediately(text: String, selfDestructAfterSeconds: TimeInterval? = nil) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        lastChangeCount = pasteboard.changeCount

        if let ttl = selfDestructAfterSeconds {
            let expectedChangeCount = lastChangeCount
            DispatchQueue.main.asyncAfter(deadline: .now() + ttl) { [weak self] in
                guard let self, self.pasteboard.changeCount == expectedChangeCount else { return }
                self.pasteboard.clearContents()
                self.lastChangeCount = self.pasteboard.changeCount
            }
        }
    }

    /// Явно записывает сгенерированный пароль в NSPasteboard.general и добавляет его в историю буфера обмена как .secret
    @discardableResult
    public func recordGeneratedPassword(_ password: String, ttlSeconds: TimeInterval? = nil) -> String {
        let trimmed = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        // Автотаймер для сгенерированных паролей отключен — таймер выставляется только вручную
        let effectiveTTL: TimeInterval? = ttlSeconds

        // 1. Очищаем системный буфер и записываем пароль обычной строкой
        pasteboard.clearContents()
        pasteboard.setString(trimmed, forType: .string)
        lastChangeCount = pasteboard.changeCount

        if let effectiveTTL {
            let expectedChangeCount = lastChangeCount
            DispatchQueue.main.asyncAfter(deadline: .now() + effectiveTTL) { [weak self] in
                guard let self, self.pasteboard.changeCount == expectedChangeCount else { return }
                self.pasteboard.clearContents()
                self.lastChangeCount = self.pasteboard.changeCount
            }
        }

        // 2. Явно добавляем запись в историю с типом .secret, sourceAppName = "Paste Vault (PassGen)", isSensitive = true
        let payloadData = Data(trimmed.utf8)
        let digest = SHA256.hash(data: payloadData)
        let contentHash = digest.map { String(format: "%02x", $0) }.joined()
        let nowTs = Int64(Date().timeIntervalSince1970)
        let ttlInt: Int64? = effectiveTTL.map { Int64($0) }
        let expiresAtDate: Date? = effectiveTTL.map { Date().addingTimeInterval($0) }

        let existingItem = items.first(where: { $0.contentHash == contentHash })
        let itemId = existingItem?.id ?? UUID().uuidString
        let isPinned = existingItem?.isPinned ?? false

        let newRow = ClipboardItemRow(
            id: itemId,
            rowid: existingItem?.rowid ?? nowTs,
            contentType: .secret,
            textPreview: trimmed,
            contentHash: contentHash,
            sourceBundleId: Bundle.main.bundleIdentifier,
            sourceAppName: "PasteVault (PassGen)",
            isSensitive: true,
            secretKind: "Сгенерированный пароль",
            isPinned: isPinned,
            createdAt: nowTs,
            expiresAt: expiresAtDate
        )

        items.removeAll { $0.contentHash == contentHash }
        items.insert(newRow, at: 0)
        NotificationCenter.default.post(name: Notification.Name("pasteVaultDidCaptureItem"), object: itemId)

        Task {
            _ = try? await DatabaseManager.shared.upsertItem(
                id: itemId,
                contentType: .secret,
                textPreview: trimmed,
                rawPayload: payloadData,
                sourceBundleId: Bundle.main.bundleIdentifier,
                sourceAppName: "PasteVault (PassGen)",
                isSensitive: true,
                secretKind: "Сгенерированный пароль",
                ttlSeconds: ttlInt
            )
        }

        return itemId
    }

    /// Мониторинг прав Универсального доступа
    private func startAccessibilityMonitoring() {
        refreshAccessibilityStatus()

        // Проверка каждые 0.5 сек для мгновенной реакции на включение тумблера пользователем в Системных настройках
        accessibilityTimer?.invalidate()
        accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshAccessibilityStatus()
            }
        }

        // Обновление статуса при активации приложения и при получении фокуса окном
        let obs1 = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshAccessibilityStatus()
            }
        }
        let obs2 = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshAccessibilityStatus()
            }
        }
        let obs3 = NotificationCenter.default.addObserver(
            forName: Notification.Name("pasteVaultAccessibilityDidChange"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshAccessibilityStatus()
            }
        }
        accessibilityObservers = [obs1, obs2, obs3]
    }

    /// Синхронно обновляет статус прав Универсального доступа
    public func refreshAccessibilityStatus() {
        let currentTrust = AccessibilityService.isAccessibilityTrusted()
        if self.isAccessibilityGranted != currentTrust {
            let wasGranted = self.isAccessibilityGranted
            self.isAccessibilityGranted = currentTrust
            if !wasGranted && currentTrust {
                AppDelegate.shared?.restorePanelAfterAccessibilityGranted()
            }
        }
    }

    /// Прямая проверка прав Универсального доступа без кэширования
    public func checkAccessibilityPermission() -> Bool {
        refreshAccessibilityStatus()
        return isAccessibilityGranted
    }

    /// Открывает Системные настройки macOS ровно на странице «Конфиденциальность → Универсальный доступ».
    /// triggerSystemPrompt: true вызывается ТОЛЬКО если пользователь явно запросил системное окно через нативный prompt Apple.
    public func openAccessibilitySettings(triggerSystemPrompt: Bool = false) {
        if triggerSystemPrompt {
            AccessibilityService.requestAccessPrompt()
        } else {
            AccessibilityService.openSystemSettingsOnly()
        }
    }

    /// Собственный движок контекстной вставки Paste Vault для Warp, Safari, ChatGPT, Antigravity (независимо от раскладки клавиатуры)
    public func pasteIntoTargetApp(_ item: ClipboardItemRow) {
        isPerformingAutoPaste = true
        let ttl: TimeInterval? = item.expiresAt.map { max(1, $0.timeIntervalSinceNow) }
        copyToClipboard(item: item, selfDestructAfterSeconds: ttl)
        recordItemUsage(id: item.id)
        performPasteOperation()
    }

    /// Вставляет выбранный элемент как чистый неформатированный текст
    public func pasteIntoTargetAppPlainText(_ item: ClipboardItemRow) {
        isPerformingAutoPaste = true
        let ttl: TimeInterval? = item.expiresAt.map { max(1, $0.timeIntervalSinceNow) }
        let text = item.ocrText ?? item.textPreview
        copyToPasteboardImmediately(text: text, selfDestructAfterSeconds: ttl)
        recordItemUsage(id: item.id)
        performPasteOperation()
    }

    /// Уведомление для UI: автовставка заблокирована, т.к. Универсальный доступ (Accessibility) не выдан
    public static let pasteBlockedNotification = Notification.Name("pasteVaultPasteBlockedNoAccessibility")

    /// Копирует выбранный текст, возвращает фокус в целевое приложение и выполняет двухконтурную вставку (AXMenuItem Paste / CGEvent ⌘V)
    public func pasteIntoTargetApp(text: String, selfDestructAfterSeconds: TimeInterval? = nil) {
        isPerformingAutoPaste = true
        copyToPasteboardImmediately(text: text, selfDestructAfterSeconds: selfDestructAfterSeconds)
        performPasteOperation()
    }

    private func performPasteOperation() {
        isPerformingAutoPaste = true

        // 1. Принудительно снимаем фокус с любого текстового поля внутри всех окон самого PasteVault
        for window in NSApp.windows {
            window.makeFirstResponder(nil)
            if window is NSPanel {
                window.resignKey()
            }
        }

        // 2. Проверяем Универсальный доступ через AccessibilityService.
        //    Если доступа нет — НЕ вызываем системный prompt! Показываем аккуратный баннер в окне приложения.
        guard checkAccessibilityPermission() else {
            isPerformingAutoPaste = false
            NotificationCenter.default.post(name: Self.pasteBlockedNotification, object: nil)
            return
        }

        if (lastActiveApp == nil || lastActiveApp?.isTerminated == true) && (targetApp == nil || targetApp?.isTerminated == true) {
            detectFrontmostExternalApp()
        }
        var destinationApp = lastActiveApp ?? targetApp
        if destinationApp?.bundleIdentifier == Bundle.main.bundleIdentifier {
            destinationApp = nil
        }

        // 3. Активируем целевое приложение (окно Paste Vault остаётся открытым поверх для повторных вставок)
        if let destinationApp, !destinationApp.isTerminated {
            destinationApp.activate(options: [.activateIgnoringOtherApps])
        } else {
            NSApp.deactivate()
        }

        // 4. Ждём подтверждения фокуса целевого приложения и вставляем
        waitForTargetAppAndPaste(targetApp: destinationApp, elapsedMs: 0)
    }

    /// Автоматическое распознавание текста со скриншота через Apple Vision OCR
    nonisolated public static func recognizeOCRText(from tiffData: Data) -> String? {
        guard let source = CGImageSourceCreateWithData(tiffData as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        if #available(macOS 13.0, *) {
            request.recognitionLanguages = ["ru-RU", "en-US"]
        }
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
        guard let observations = request.results else { return nil }
        let recognized = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        let trimmed = recognized.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Определяет терминалы и кастомные GPU-окна (Warp, Electron/ToDesktop, VSCode, ChatGPT), которые ждут аппаратный CGEvent ⌘V
    private func requiresHardwareCommandV(for app: NSRunningApplication?) -> Bool {
        guard let bundleId = app?.bundleIdentifier else { return false }
        return bundleId.contains("dev.warp.Warp")
            || bundleId.contains("com.todesktop")
            || bundleId.contains("com.microsoft.VSCode")
            || bundleId.contains("com.openai.chat")
            || bundleId == "com.apple.Terminal"
            || bundleId == "com.googlecode.iterm2"
            || bundleId.contains("com.mitchellh.ghostty")
            || bundleId.contains("net.kovidgoyal.kitty")
            || bundleId.contains("org.alacritty")
    }

    private func waitForTargetAppAndPaste(targetApp: NSRunningApplication?, elapsedMs: Int) {
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let targetPID = targetApp?.processIdentifier
        let frontBundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let isOurApp = (frontBundleId == Bundle.main.bundleIdentifier)

        // Если активен процесс самого PasteVault, ждём переключения фокуса на внешнее приложение
        if isOurApp && elapsedMs < 300 {
            if let targetApp, !targetApp.isTerminated {
                targetApp.activate(options: [.activateIgnoringOtherApps])
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(40)) { [weak self] in
                self?.waitForTargetAppAndPaste(targetApp: targetApp, elapsedMs: elapsedMs + 40)
            }
            return
        }

        let isFrontmostConfirmed = (targetPID == nil) || (frontPID == targetPID) || (elapsedMs >= 250)
        if isFrontmostConfirmed {
            let activeApp = targetApp ?? NSWorkspace.shared.frontmostApplication

            // Терминалы и GPU-окна (Warp и др.): 80 мс на передачу GPU-фокуса, проверка прав и аппаратный ⌘V
            if requiresHardwareCommandV(for: activeApp) {
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(80)) { [weak self] in
                    guard let self else { return }
                    if self.checkAccessibilityPermission() {
                        self.postPasteEvent()
                    }
                    self.scheduleResetAutoPasteFlag()
                }
                return
            }

            // Стандартные приложения: 70 мс на восстановление курсора, затем AX-меню «Вставить», иначе ⌘V
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(70)) { [weak self] in
                guard let self else { return }
                guard self.checkAccessibilityPermission() else {
                    self.scheduleResetAutoPasteFlag()
                    return
                }
                if let pid = activeApp?.processIdentifier, self.triggerNativeMenuPaste(for: pid) {
                    self.scheduleResetAutoPasteFlag()
                    return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(30)) { [weak self] in
                    self?.postPasteEvent()
                    self?.scheduleResetAutoPasteFlag()
                }
            }
        } else {
            if let targetApp, !targetApp.isTerminated {
                targetApp.activate(options: [.activateIgnoringOtherApps])
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(20)) { [weak self] in
                self?.waitForTargetAppAndPaste(targetApp: targetApp, elapsedMs: elapsedMs + 20)
            }
        }
    }

    private func scheduleResetAutoPasteFlag() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.isPerformingAutoPaste = false
        }
    }

    /// Отправляет ⌘V (kVK_Command 0x37 + kVK_ANSI_V 0x09) через CGEvent.
    /// Основной канал — `.cghidEventTap` (его принимают Warp и GPU-терминалы). Резервный `.cgSessionEventTap`
    /// используется только если не удалось создать событие для HID-канала — одновременная отправка в оба канала
    /// приводит к двойной вставке, т.к. события из HID-tap и так проходят через session-tap.
    public func postPasteEvent() {
        // Убеждаемся, что фокус не находится на PasteVault в момент посылки ⌘V
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Bundle.main.bundleIdentifier {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(70)) { [weak self] in
                self?.synthesizeCommandV()
            }
        } else {
            synthesizeCommandV()
        }
    }

    /// Контур 1: Нативный вызов пункта меню «Вставить / Paste» целевого приложения через Apple Accessibility (AXUIElement)
    /// Работает на 100% независимо от текущей раскладки клавиатуры (русской или английской) в Warp, Safari, ChatGPT, Antigravity
    public func triggerNativeMenuPaste(for pid: pid_t) -> Bool {
        guard checkAccessibilityPermission() else { return false }

        let appElement = AXUIElementCreateApplication(pid)
        var menuBarRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXMenuBarAttribute as CFString, &menuBarRef) == .success,
              let menuBar = menuBarRef else {
            return false
        }

        var topChildrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(menuBar as! AXUIElement, kAXChildrenAttribute as CFString, &topChildrenRef) == .success,
              let topMenuBarItems = topChildrenRef as? [AXUIElement],
              !topMenuBarItems.isEmpty else {
            return false
        }

        // Приоритетно проверяем 2-е, 3-е, 4-е и 5-е меню (индексы 1, 2, 3, 4 — обычно «Правка» / «Edit»), затем остальные
        let priorityIndices = [1, 2, 3, 4]
        var orderedIndices: [Int] = []
        for idx in priorityIndices where idx < topMenuBarItems.count {
            orderedIndices.append(idx)
        }
        for idx in topMenuBarItems.indices where !orderedIndices.contains(idx) && idx != 0 {
            orderedIndices.append(idx)
        }

        for idx in orderedIndices {
            if searchAndPressPasteMenuItem(in: topMenuBarItems[idx], depth: 0) {
                return true
            }
        }
        return false
    }

    private func searchAndPressPasteMenuItem(in element: AXUIElement, depth: Int) -> Bool {
        guard depth <= 5 else { return false }

        var roleRef: CFTypeRef?
        let role = (AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success)
            ? (roleRef as? String)
            : nil

        if role == (kAXMenuItemRole as String) {
            var cmdCharRef: CFTypeRef?
            let cmdChar = (AXUIElementCopyAttributeValue(element, kAXMenuItemCmdCharAttribute as CFString, &cmdCharRef) == .success)
                ? (cmdCharRef as? String)?.uppercased()
                : nil

            var cmdModRef: CFTypeRef?
            let cmdModifiers: Int
            if AXUIElementCopyAttributeValue(element, kAXMenuItemCmdModifiersAttribute as CFString, &cmdModRef) == .success,
               let modVal = cmdModRef as? Int {
                cmdModifiers = modVal
            } else {
                cmdModifiers = 0
            }

            var titleRef: CFTypeRef?
            let title = (AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef) == .success)
                ? (titleRef as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                : nil

            let isPureCmdV = (cmdChar == "V" && cmdModifiers == 0)
            let isPasteTitle = (title == "Paste" || title == "Вставить") && cmdModifiers == 0

            if isPureCmdV || isPasteTitle {
                var enabledRef: CFTypeRef?
                let isEnabled: Bool
                if AXUIElementCopyAttributeValue(element, kAXEnabledAttribute as CFString, &enabledRef) == .success,
                   let flag = enabledRef as? Bool {
                    isEnabled = flag
                } else {
                    isEnabled = true
                }

                if isEnabled {
                    if AXUIElementPerformAction(element, kAXPressAction as CFString) == .success {
                        return true
                    }
                }
            }
        }

        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else {
            return false
        }

        for child in children {
            if searchAndPressPasteMenuItem(in: child, depth: depth + 1) {
                return true
            }
        }
        return false
    }

    /// Помещает выбранный элемент в буфер и мгновенно вставляет в активное окно
    public func copyAndSynthesizePaste(text: String, selfDestructAfterSeconds: TimeInterval? = nil) {
        pasteIntoTargetApp(text: text, selfDestructAfterSeconds: selfDestructAfterSeconds)
    }

    /// Контур 2: Аппаратный сигнал клавиши ⌘V через CGEvent в основной системный канал .cghidEventTap
    /// Если активна не-ASCII раскладка (например, русская), на 45 мс включает системную ASCII-раскладку для гарантированного приёма ⌘V в Warp/Electron и сразу возвращает исходную
    public func synthesizeCommandV() {
        var previousInputSource: TISInputSource? = nil
        if let currentSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() {
            var isASCII = false
            if let asciiPtr = TISGetInputSourceProperty(currentSource, kTISPropertyInputSourceIsASCIICapable) {
                let asciiBool = Unmanaged<CFBoolean>.fromOpaque(asciiPtr).takeUnretainedValue()
                isASCII = CFBooleanGetValue(asciiBool)
            }
            if !isASCII, let asciiSource = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue() {
                previousInputSource = currentSource
                TISSelectInputSource(asciiSource)
            }
        }

        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            if let prev = previousInputSource {
                TISSelectInputSource(prev)
            }
            return
        }
        source.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitLocalKeyboardEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )
        source.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitLocalKeyboardEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateRemoteMouseDrag
        )

        let cmdKey: CGKeyCode = 0x37 // kVK_Command
        let vKey: CGKeyCode = 0x09   // kVK_ANSI_V

        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: cmdKey, keyDown: true)
        cmdDown?.flags = .maskCommand

        let vDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        vDown?.flags = .maskCommand

        let vUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        vUp?.flags = .maskCommand

        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: cmdKey, keyDown: false)
        cmdUp?.flags = []

        // Основной канал — HID (Warp/GPU-терминалы). Резервный session-tap — только если HID-события не создались,
        // иначе получится двойная вставка (HID-события и так проходят через session-tap).
        if let cmdDown, let vDown, let vUp, let cmdUp {
            cmdDown.post(tap: .cghidEventTap)
            vDown.post(tap: .cghidEventTap)
            vUp.post(tap: .cghidEventTap)
            cmdUp.post(tap: .cghidEventTap)
        } else if let fallbackSource = CGEventSource(stateID: .hidSystemState) {
            let fDown = CGEvent(keyboardEventSource: fallbackSource, virtualKey: vKey, keyDown: true)
            fDown?.flags = .maskCommand
            let fUp = CGEvent(keyboardEventSource: fallbackSource, virtualKey: vKey, keyDown: false)
            fUp?.flags = .maskCommand
            fDown?.post(tap: .cgSessionEventTap)
            fUp?.post(tap: .cgSessionEventTap)
        }

        if let prev = previousInputSource {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(45)) {
                TISSelectInputSource(prev)
            }
        }
    }

    // MARK: - Synthetic Test Runner & Reference Samples
    public static func generateSyntheticScreenshotImage(label: String = "PasteVault 320×180") -> NSImage {
        let size = NSSize(width: 320, height: 180)
        let image = NSImage(size: size)
        image.lockFocus()
        let rect = NSRect(origin: .zero, size: size)
        let gradient = NSGradient(starting: NSColor.systemCyan, ending: NSColor.systemIndigo)
        gradient?.draw(in: rect, angle: 35)

        let borderPath = NSBezierPath(roundedRect: rect.insetBy(dx: 8, dy: 8), xRadius: 12, yRadius: 12)
        NSColor.white.withAlphaComponent(0.35).setStroke()
        borderPath.lineWidth = 2
        borderPath.stroke()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 16),
            .foregroundColor: NSColor.white
        ]
        let title = "📸 Скриншот 320×180 (#OCR)" as NSString
        title.draw(at: NSPoint(x: 28, y: 95), withAttributes: attrs)

        let subAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.9)
        ]
        let sub = "PasteVault Synthetic Image Preview" as NSString
        sub.draw(at: NSPoint(x: 28, y: 68), withAttributes: subAttrs)
        image.unlockFocus()
        return image
    }

    /// Заполняет историю эталонными записями всех 6 категорий и тегов и проверяет SmartClassifier + фильтрацию
    @discardableResult
    public func seedSyntheticSamples() -> String {
        let now = Int64(Date().timeIntervalSince1970)
        let isEn = (UserDefaults.standard.string(forKey: "appLanguage") == "en")

        struct SampleSpec {
            let text: String
            let sourceApp: String
            let isSensitive: Bool
            let isImage: Bool
            let secretKind: String?
            let expectedKind: ContentKind
            let expectedTag: String?
        }

        let specs: [SampleSpec] = [
            SampleSpec(
                text: isEn
                    ? "Meeting notes: review macOS release architecture and zero-network security policy"
                    : "Заметки со встречи: обсудить архитектуру релиза macOS приложения",
                sourceApp: "Notes",
                isSensitive: false,
                isImage: false,
                secretKind: nil,
                expectedKind: .text,
                expectedTag: nil
            ),
            SampleSpec(
                text: "https://developer.apple.com/documentation/security?utm_source=newsletter&utm_medium=email",
                sourceApp: "Safari",
                isSensitive: false,
                isImage: false,
                secretKind: nil,
                expectedKind: .url,
                expectedTag: "#UTM-трекер"
            ),
            SampleSpec(
                text: "func authenticateUser(token: String) -> Bool {\n    return !token.isEmpty\n}",
                sourceApp: "Xcode",
                isSensitive: false,
                isImage: false,
                secretKind: nil,
                expectedKind: .code,
                expectedTag: "#Swift"
            ),
            SampleSpec(
                text: "{\"app\":\"PasteVault\",\"encryption\":\"AES-256-GCM\",\"offline\":true}",
                sourceApp: "VS Code",
                isSensitive: false,
                isImage: false,
                secretKind: nil,
                expectedKind: .code,
                expectedTag: "#JSON"
            ),
            SampleSpec(
                text: isEn
                    ? "[Screenshot 320×180 px] #OCR — PasteVault Security Architecture"
                    : "[Скриншот 320×180 пкс] #OCR — Архитектура безопасности PasteVault",
                sourceApp: isEn ? "Screenshot" : "Снимок экрана",
                isSensitive: false,
                isImage: true,
                secretKind: nil,
                expectedKind: .image,
                expectedTag: "#OCR"
            ),
            SampleSpec(
                text: "sk-live-98a7f6d5e4c3b2a10987654321fedcba",
                sourceApp: "Terminal",
                isSensitive: true,
                isImage: false,
                secretKind: "Production API Secret",
                expectedKind: .secret,
                expectedTag: nil
            ),
            SampleSpec(
                text: "#38BDF8",
                sourceApp: "Figma",
                isSensitive: false,
                isImage: false,
                secretKind: nil,
                expectedKind: .color,
                expectedTag: "Цвет"
            ),
            SampleSpec(
                text: "rgb(16, 185, 129)",
                sourceApp: "Figma",
                isSensitive: false,
                isImage: false,
                secretKind: nil,
                expectedKind: .color,
                expectedTag: "Цвет"
            ),
            SampleSpec(
                text: isEn ? "[File: Security_Architecture.pdf]" : "[Файл: Архитектура_Безопасности.pdf]",
                sourceApp: "Finder",
                isSensitive: false,
                isImage: false,
                secretKind: nil,
                expectedKind: .file,
                expectedTag: "#Файл"
            )
        ]

        var passedCount = 0
        let synthImage = Self.generateSyntheticScreenshotImage()
        let synthTiff = synthImage.tiffRepresentation ?? Data()
        let synthFileIcon = NSWorkspace.shared.icon(for: .pdf)
        synthFileIcon.size = NSSize(width: 48, height: 48)

        for (idx, spec) in specs.enumerated() {
            let detectedSecret = SecretDetector.inspect(spec.text)
            let isSens = spec.isSensitive || detectedSecret.isSensitive
            let classified = SmartClassifier.classify(text: spec.text, isSensitive: isSens, isImage: spec.isImage)
            let tags = SmartClassifier.tags(for: spec.text, contentType: classified, isSensitive: isSens)

            let kindMatches = (classified == spec.expectedKind)
            let tagMatches = spec.expectedTag == nil || tags.contains(spec.expectedTag!)
            if kindMatches && tagMatches {
                passedCount += 1
            } else {
                NSLog("[PasteVault][TestRunner] MISMATCH for \(spec.text): got kind=\(classified) tags=\(tags)")
            }

            let rawData = spec.isImage ? synthTiff : Data(spec.text.utf8)
            let digest = SHA256.hash(data: Data(spec.text.utf8))
            let contentHash = digest.map { String(format: "%02x", $0) }.joined()
            let existing = items.first(where: { $0.contentHash == contentHash })
            let itemId = existing?.id ?? UUID().uuidString
            let createdAt = now - Int64(specs.count - idx)

            let itemExpiresAt: Date? = nil
            let itemTTLSeconds: Int64? = nil

            let sampleOcr = isEn
                ? "PasteVault Security Architecture: Zero-knowledge local-first AES-256-GCM encryption with Apple Silicon Secure Enclave hardware binding"
                : "Архитектура безопасности PasteVault: Локальное шифрование AES-256-GCM с аппаратной привязкой к Apple Silicon Secure Enclave"

            let isFileKind = (spec.expectedKind == .file)
            let row = ClipboardItemRow(
                id: itemId,
                rowid: createdAt,
                contentType: classified,
                textPreview: spec.text,
                contentHash: contentHash,
                sourceBundleId: "com.pastevault.app.tests",
                sourceAppName: spec.sourceApp,
                isSensitive: isSens,
                secretKind: spec.secretKind ?? detectedSecret.secretKind,
                isPinned: false,
                createdAt: createdAt,
                expiresAt: itemExpiresAt,
                ocrText: spec.isImage ? sampleOcr : (isFileKind ? "/Applications/Paste Vault.app" : nil),
                rawImageData: spec.isImage ? synthTiff : (isFileKind ? synthFileIcon.tiffRepresentation : nil),
                fileURLPath: isFileKind ? "/Applications/Paste Vault.app" : nil,
                useCount: 0
            )

            if spec.isImage {
                imagePreviews[itemId] = synthImage
            } else if isFileKind {
                imagePreviews[itemId] = synthFileIcon
            }

            items.removeAll { $0.contentHash == contentHash }
            items.insert(row, at: 0)

            Task {
                _ = try? await DatabaseManager.shared.upsertItem(
                    id: itemId,
                    contentType: classified,
                    textPreview: spec.text,
                    rawPayload: rawData,
                    sourceBundleId: "com.pastevault.app.tests",
                    sourceAppName: spec.sourceApp,
                    isSensitive: isSens,
                    secretKind: spec.secretKind ?? detectedSecret.secretKind,
                    ttlSeconds: itemTTLSeconds
                )
            }
        }

        let summary = isEn
            ? "Type test passed: \(passedCount)/\(specs.count) samples loaded (Text, Link #UTM, Code #Swift/#JSON, Screenshot #OCR, Secret, Color)"
            : "Тест типов пройден: \(passedCount)/\(specs.count) эталонов (Текст, Ссылки #UTM, Код #Swift/#JSON, Скриншот #OCR, Пароли, Цвета)"
        NSLog("[PasteVault][TestRunner] \(summary)")
        return summary
    }
}

