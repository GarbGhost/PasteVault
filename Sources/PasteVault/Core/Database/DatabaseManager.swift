import Foundation
import AppKit
import SQLite3
import CryptoKit

public enum AppDefaults {
    nonisolated public static let testSuiteName: String? = {
        guard DatabaseManager.isRunningTests else { return nil }
        return "com.pastevault.tests.\(ProcessInfo.processInfo.processIdentifier)"
    }()

    nonisolated public static func preferencesDirectoryURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences", isDirectory: true)
    }

    nonisolated public static func removeTestPreferences(forSuiteName suiteName: String, preferencesDir: URL? = nil) {
        guard suiteName.hasPrefix("com.pastevault.tests.") else { return }
        if preferencesDir == nil {
            if let suiteDefaults = UserDefaults(suiteName: suiteName) {
                suiteDefaults.synchronize()
                suiteDefaults.removePersistentDomain(forName: suiteName)
                suiteDefaults.synchronize()
            }
            if let keys = CFPreferencesCopyKeyList(suiteName as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) {
                CFPreferencesSetMultiple(nil, keys, suiteName as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            }
            CFPreferencesSynchronize(suiteName as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        }

        let fm = FileManager.default
        let prefsDir = preferencesDir ?? preferencesDirectoryURL()
        let plistURL = prefsDir.appendingPathComponent("\(suiteName).plist")
        if fm.fileExists(atPath: plistURL.path) {
            try? fm.removeItem(at: plistURL)
        }
        if let entries = try? fm.contentsOfDirectory(at: prefsDir, includingPropertiesForKeys: nil) {
            for entry in entries where entry.lastPathComponent.hasPrefix("\(suiteName).plist") {
                try? fm.removeItem(at: entry)
            }
        }
    }

    nonisolated public static func cleanupCurrentTestPreferencesAndSync() {
        if let suite = testSuiteName {
            removeTestPreferences(forSuiteName: suite)
        }
        cleanupOrphanedTestPreferences(currentPID: ProcessInfo.processInfo.processIdentifier)
        let testTmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PasteVault_TestRun_\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        if FileManager.default.fileExists(atPath: testTmpDir.path) {
            try? FileManager.default.removeItem(at: testTmpDir)
        }
    }

    nonisolated public static func cleanupOrphanedTestPreferences(
        currentPID: Int32 = ProcessInfo.processInfo.processIdentifier,
        preferencesDir: URL? = nil
    ) {
        let fm = FileManager.default
        let prefsDir = preferencesDir ?? preferencesDirectoryURL()
        guard let entries = try? fm.contentsOfDirectory(at: prefsDir, includingPropertiesForKeys: nil) else { return }
        for entry in entries {
            let name = entry.lastPathComponent
            guard name.hasPrefix("com.pastevault.tests."), name.hasSuffix(".plist") else { continue }
            let suiteName = String(name.dropLast(".plist".count))
            let pidString = String(suiteName.dropFirst("com.pastevault.tests.".count))
            guard let oldPid = Int32(pidString), oldPid != currentPID else { continue }
            if kill(oldPid, 0) != 0 && errno == ESRCH {
                removeTestPreferences(forSuiteName: suiteName, preferencesDir: prefsDir)
            }
        }
    }

    private static let testDefaultsCleanupRegistered: Void = {
        guard let suiteName = testSuiteName else { return }
        cleanupOrphanedTestPreferences(currentPID: ProcessInfo.processInfo.processIdentifier)
        atexit {
            guard let suite = AppDefaults.testSuiteName else { return }
            AppDefaults.removeTestPreferences(forSuiteName: suite)
            let plistPath = AppDefaults.preferencesDirectoryURL().appendingPathComponent("\(suite).plist").path
            let pidStr = "\(ProcessInfo.processInfo.processIdentifier)"
            let reaper = Process()
            reaper.executableURL = URL(fileURLWithPath: "/bin/sh")
            reaper.arguments = [
                "-c",
                "nohup /bin/sh -c 'while /bin/kill -0 \"$1\" 2>/dev/null; do /bin/sleep 0.05; done; /bin/sleep 0.25; /bin/rm -f \"$2\"*; /bin/sleep 2.0; /bin/rm -f \"$2\"*' _ \"$1\" \"$2\" >/dev/null 2>&1 </dev/null &",
                "pv-test-prefs-reaper",
                pidStr,
                plistPath
            ]
            reaper.standardInput = FileHandle.nullDevice
            reaper.standardOutput = FileHandle.nullDevice
            reaper.standardError = FileHandle.nullDevice
            try? reaper.run()
        }
        _ = suiteName
    }()

    nonisolated public static let shared: UserDefaults = {
        if let suiteName = testSuiteName {
            _ = testDefaultsCleanupRegistered
            return UserDefaults(suiteName: suiteName) ?? .standard
        }
        return .standard
    }()
}

public enum ContentKind: Int32, Sendable {
    case text = 0
    case url = 1
    case code = 2
    case image = 3
    case secret = 4
    case color = 5
    case file = 6
}

public struct ClipboardItemRow: Identifiable, Equatable, Sendable {
    public let id: String
    public let rowid: Int64
    public let contentType: ContentKind
    public let textPreview: String
    public var content: String { textPreview }
    public let contentHash: String
    public let sourceBundleId: String?
    public let sourceAppName: String?
    public let isSensitive: Bool
    public let secretKind: String?
    public var isPinned: Bool
    public let createdAt: Int64
    public var expiresAt: Date?
    public var ocrText: String?
    public let rawImageData: Data?
    public let fileURLPath: String?
    public let useCount: Int

    // Кэшированные поля (вычисляются 1 раз при инициализации, чтобы исключить пересчёт при наведении мыши и скролле)
    public let cachedEffectiveContentType: ContentKind
    public let detectedTags: [String]
    public let displayPreviewText: String

    public init(
        id: String,
        rowid: Int64,
        contentType: ContentKind,
        textPreview: String,
        contentHash: String,
        sourceBundleId: String?,
        sourceAppName: String?,
        isSensitive: Bool,
        secretKind: String?,
        isPinned: Bool,
        createdAt: Int64,
        expiresAt: Date?,
        ocrText: String? = nil,
        rawImageData: Data? = nil,
        fileURLPath: String? = nil,
        useCount: Int = 0,
        demotedIds: Set<String>? = nil,
        promotedIds: Set<String>? = nil
    ) {
        let resolvedDemoted = demotedIds ?? ClipboardMonitor.manuallyDemotedTextIds
        let resolvedPromoted = promotedIds ?? ClipboardMonitor.manuallyPromotedSecretIds
        let isDemoted = resolvedDemoted.contains(id)
        let isPromoted = resolvedPromoted.contains(id)

        let effectiveIsSensitive: Bool
        let effectiveContentType: ContentKind
        let effectiveSecretKind: String?

        if isDemoted {
            effectiveIsSensitive = false
            effectiveContentType = .text
            effectiveSecretKind = nil
        } else if isPromoted {
            effectiveIsSensitive = true
            effectiveContentType = .secret
            effectiveSecretKind = secretKind ?? (AppLanguage.current == .en ? "Password" : "Пароль")
        } else {
            effectiveIsSensitive = isSensitive
            effectiveContentType = contentType
            effectiveSecretKind = secretKind
        }

        self.id = id
        self.rowid = rowid
        self.contentType = effectiveContentType
        self.textPreview = textPreview
        self.contentHash = contentHash
        self.sourceBundleId = sourceBundleId
        self.sourceAppName = sourceAppName
        self.isSensitive = effectiveIsSensitive
        self.secretKind = effectiveSecretKind
        self.isPinned = isPinned
        self.createdAt = createdAt
        self.expiresAt = isDemoted ? nil : expiresAt
        self.ocrText = ocrText
        self.rawImageData = rawImageData
        self.fileURLPath = fileURLPath
        self.useCount = useCount

        let computedKind: ContentKind
        if effectiveContentType == .file {
            computedKind = .file
        } else if effectiveContentType == .image {
            computedKind = .image
        } else if isDemoted {
            computedKind = SmartClassifier.classify(text: textPreview, isSensitive: false, isImage: false)
        } else if isPromoted || effectiveIsSensitive || effectiveContentType == .secret {
            computedKind = .secret
        } else {
            let secretCheck = SecretDetector.inspect(textPreview).isSensitive
            let realSensitive = (effectiveIsSensitive && !SmartClassifier.isJSON(textPreview)) || secretCheck
            if realSensitive {
                computedKind = .secret
            } else {
                computedKind = SmartClassifier.classify(text: textPreview, isSensitive: false, isImage: false)
            }
        }
        self.cachedEffectiveContentType = computedKind
        self.detectedTags = SmartClassifier.tags(for: textPreview, contentType: computedKind, isSensitive: effectiveIsSensitive || computedKind == .secret)

        if effectiveIsSensitive || computedKind == .secret {
            self.displayPreviewText = SmartClassifier.maskedSecret(textPreview)
        } else {
            self.displayPreviewText = String(textPreview.prefix(250)).replacingOccurrences(of: "\n", with: " ")
        }
    }

    public var effectiveContentType: ContentKind {
        cachedEffectiveContentType
    }

    public var tags: [String] {
        detectedTags
    }

    public var imageData: Data? {
        rawImageData
    }

    public var fileURLs: [URL] {
        guard contentType == .file, let paths = fileURLPath ?? ocrText else { return [] }
        return paths.components(separatedBy: "\n").filter { !$0.isEmpty }.map { URL(fileURLWithPath: $0) }
    }

    public var userForcedPlainText: Bool {
        ClipboardMonitor.manuallyDemotedTextIds.contains(id)
    }

    @MainActor
    public var isPasswordCandidate: Bool {
        ClipboardRowCardView.isPasswordCandidate(self)
    }
}

public typealias ClipboardItem = ClipboardItemRow

public actor DatabaseManager {
    public static let shared = DatabaseManager()
    public private(set) var databaseFileURL: URL?
    private var db: OpaquePointer?
    private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private init() {}

    public func closeForTesting() {
        if let db {
            sqlite3_close_v2(db)
            self.db = nil
            self.databaseFileURL = nil
        }
    }

    nonisolated public static let isRunningTests: Bool = {
        if NSClassFromString("XCTestCase") != nil { return true }
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return true }
        let prog = ProcessInfo.processInfo.processName.lowercased()
        if prog.contains("xctest") || prog.contains("packagetests") { return true }
        let lowerArgs = CommandLine.arguments.map { $0.lowercased() }
        if lowerArgs.contains(where: {
            $0.contains("xctest")
            || $0.contains(".xctest")
            || $0 == "--run-synthetic-tests"
            || $0 == "--uitest"
            || $0 == "--test"
        }) {
            return true
        }
        return false
    }()

    private static let testRunCleanupRegistered: Void = {
        guard isRunningTests else { return }
        let currentPid = ProcessInfo.processInfo.processIdentifier
        let tmpDir = URL(fileURLWithPath: "/tmp", isDirectory: true)
        if let entries = try? FileManager.default.contentsOfDirectory(at: tmpDir, includingPropertiesForKeys: nil) {
            for entry in entries where entry.lastPathComponent.hasPrefix("PasteVault_TestRun_") {
                let suffix = entry.lastPathComponent.dropFirst("PasteVault_TestRun_".count)
                if let oldPid = Int32(suffix), oldPid != currentPid {
                    if kill(oldPid, 0) != 0 && errno == ESRCH {
                        try? FileManager.default.removeItem(at: entry)
                    }
                }
            }
        }
        atexit {
            let currentDir = URL(fileURLWithPath: "/tmp", isDirectory: true).appendingPathComponent(
                "PasteVault_TestRun_\(ProcessInfo.processInfo.processIdentifier)",
                isDirectory: true
            )
            try? FileManager.default.removeItem(at: currentDir)
        }
    }()

    nonisolated public static func pasteVaultSupportDirectory() throws -> URL {
        if isRunningTests {
            _ = testRunCleanupRegistered
            return URL(fileURLWithPath: "/tmp", isDirectory: true).appendingPathComponent(
                "PasteVault_TestRun_\(ProcessInfo.processInfo.processIdentifier)",
                isDirectory: true
            )
        }
        return try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("PasteVault", isDirectory: true)
    }

    public func initializeDatabase(at customURL: URL? = nil) throws {
        if let customURL, databaseFileURL != nil && customURL != databaseFileURL {
            closeForTesting()
        }
        if db != nil { return }

        let dbURL: URL
        if let customURL {
            dbURL = customURL
        } else {
            let appSupport = try Self.pasteVaultSupportDirectory()

            try FileManager.default.createDirectory(
                at: appSupport,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let screenshotsDir = appSupport.appendingPathComponent("Screenshots", isDirectory: true)
            try? FileManager.default.createDirectory(
                at: screenshotsDir,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let imagesDir = appSupport.appendingPathComponent("Images", isDirectory: true)
            try? FileManager.default.createDirectory(
                at: imagesDir,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let dbFileName = Self.isRunningTests ? "pastevault_test.sqlite" : "pastevault_v2.sqlite"
            dbURL = appSupport.appendingPathComponent(dbFileName)
        }
        self.databaseFileURL = dbURL

        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let openRC = sqlite3_open_v2(dbURL.path, &db, flags, nil)
        guard openRC == SQLITE_OK else {
            let errMessage = db.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "sqlite3_open_v2 failed (\(openRC))"
            if let dbHandle = db {
                sqlite3_close_v2(dbHandle)
                db = nil
            }
            databaseFileURL = nil
            throw NSError(domain: "PasteVault.SQLite", code: Int(openRC), userInfo: [NSLocalizedDescriptionKey: errMessage])
        }
        sqlite3_busy_timeout(db, 5000)

        try executeRaw("""
            PRAGMA journal_mode = WAL;
            PRAGMA synchronous = NORMAL;
            PRAGMA foreign_keys = ON;
            PRAGMA temp_store = MEMORY;
        """)

        try migrateSchema()
        seedDefaultSnippetCategoriesIfNeeded()
        seedStressTest100SnippetsIfNeeded()
        fixSavedClipboardMacrosIfNeeded()
        normalizeExistingCategoriesIfNeeded()
        cleanupLegacyDataIfNeeded()
        cleanupDemoClipboardItemsIfNeeded()
        wipeClipboardToZeroIfNeeded()
        cleanupUnusedSnippetImageFiles()
    }

    private func wipeClipboardToZeroIfNeeded() {
        guard !Self.isRunningTests else { return }
        let defaults = AppDefaults.shared
        let key = "pv_wipe_clipboard_to_zero_v1"
        guard !defaults.bool(forKey: key) else { return }

        do {
            try executeRawThrowing("DELETE FROM clipboard_items;")
            if let supportDir = try? Self.pasteVaultSupportDirectory() {
                let imagesDir = supportDir.appendingPathComponent("Images", isDirectory: true)
                let fm = FileManager.default
                if let files = try? fm.contentsOfDirectory(at: imagesDir, includingPropertiesForKeys: nil) {
                    for fileURL in files where !fileURL.lastPathComponent.hasPrefix("snippet_img_") {
                        try? fm.removeItem(at: fileURL)
                    }
                }
            }
            defaults.removeObject(forKey: "manuallyDemotedTextIds")
            defaults.removeObject(forKey: "manuallyPromotedSecretIds")
            defaults.set(true, forKey: key)
        } catch {
            // Если не удалось, повторим на следующем запуске
        }
    }

    private func cleanupDemoClipboardItemsIfNeeded() {
        guard !Self.isRunningTests else { return }
        let defaults = AppDefaults.shared
        let key = "pv_cleaned_demo_clipboard_items_v1"
        guard !defaults.bool(forKey: key) else { return }

        try? executeRaw("""
            DELETE FROM clipboard_items
            WHERE source_bundle_id = 'com.pastevault.app.tests'
               OR text_preview LIKE '%PasteVault Synthetic%'
               OR text_preview LIKE '%Заметки со встречи: обсудить архитектуру релиза%'
               OR text_preview LIKE '%Meeting notes: review macOS release architecture%'
               OR text_preview = 'sk-live-98a7f6d5e4c3b2a10987654321fedcba';
        """)
        defaults.set(true, forKey: key)
    }

    private func migrateSchema() throws {
        let schemaSQL = """
        CREATE TABLE IF NOT EXISTS clipboard_items (
            id TEXT PRIMARY KEY NOT NULL,
            content_type INTEGER NOT NULL,
            text_preview TEXT NOT NULL,
            content_hash TEXT NOT NULL UNIQUE,
            source_bundle_id TEXT,
            source_app_name TEXT,
            is_sensitive INTEGER NOT NULL DEFAULT 0,
            secret_kind TEXT,
            is_pinned INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL,
            expires_at INTEGER,
            ocr_text TEXT
        );

        CREATE INDEX IF NOT EXISTS idx_clipboard_created_at
            ON clipboard_items(is_pinned DESC, created_at DESC);

        CREATE VIRTUAL TABLE IF NOT EXISTS clipboard_fts USING fts5(
            text_preview,
            source_app_name,
            content='clipboard_items',
            content_rowid='rowid',
            tokenize='unicode61 remove_diacritics 2'
        );

        CREATE TRIGGER IF NOT EXISTS trg_clipboard_ai AFTER INSERT ON clipboard_items
        WHEN new.is_sensitive = 0 BEGIN
            INSERT INTO clipboard_fts(rowid, text_preview, source_app_name)
            VALUES (new.rowid, new.text_preview, COALESCE(new.source_app_name, ''));
        END;

        CREATE TRIGGER IF NOT EXISTS trg_clipboard_ad AFTER DELETE ON clipboard_items
        WHEN old.is_sensitive = 0 BEGIN
            INSERT INTO clipboard_fts(clipboard_fts, rowid, text_preview, source_app_name)
            VALUES ('delete', old.rowid, old.text_preview, COALESCE(old.source_app_name, ''));
        END;

        CREATE TRIGGER IF NOT EXISTS trg_clipboard_au_del AFTER UPDATE OF text_preview, source_app_name, is_sensitive ON clipboard_items
        WHEN old.is_sensitive = 0 BEGIN
            INSERT INTO clipboard_fts(clipboard_fts, rowid, text_preview, source_app_name)
            VALUES ('delete', old.rowid, old.text_preview, COALESCE(old.source_app_name, ''));
        END;

        CREATE TRIGGER IF NOT EXISTS trg_clipboard_au_ins AFTER UPDATE OF text_preview, source_app_name, is_sensitive ON clipboard_items
        WHEN new.is_sensitive = 0 BEGIN
            INSERT INTO clipboard_fts(rowid, text_preview, source_app_name)
            VALUES (new.rowid, new.text_preview, COALESCE(new.source_app_name, ''));
        END;

        CREATE TABLE IF NOT EXISTS snippet_categories (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL UNIQUE,
            icon_name TEXT NOT NULL,
            sort_order INTEGER NOT NULL DEFAULT 0,
            created_at REAL NOT NULL
        );

        CREATE TABLE IF NOT EXISTS snippets (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            content TEXT NOT NULL,
            category TEXT NOT NULL,
            shortcut_hint TEXT,
            is_pinned INTEGER NOT NULL DEFAULT 0,
            created_at REAL NOT NULL DEFAULT (strftime('%s', 'now')),
            image_path TEXT
        );
        """
        try executeRaw(schemaSQL)
        _ = try? executeRaw("ALTER TABLE clipboard_items ADD COLUMN use_count INTEGER NOT NULL DEFAULT 0;")
        _ = try? executeRaw("ALTER TABLE clipboard_items ADD COLUMN file_path TEXT;")
        _ = try? executeRaw("ALTER TABLE clipboard_items ADD COLUMN ocr_text TEXT;")
        _ = try? executeRaw("ALTER TABLE snippets ADD COLUMN use_count INTEGER NOT NULL DEFAULT 0;")
    }

    public func incrementUseCount(id: String) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "UPDATE clipboard_items SET use_count = use_count + 1 WHERE id = ?1;", -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        bindTextExact(stmt, 1, id)
        _ = sqlite3_step(stmt)
    }

    public func upsertItem(
        id: String? = nil,
        contentType: ContentKind,
        textPreview: String,
        rawPayload: Data,
        sourceBundleId: String?,
        sourceAppName: String?,
        isSensitive: Bool,
        secretKind: String?,
        ttlSeconds: Int64?,
        fileURLPath: String? = nil,
        ocrText: String? = nil
    ) throws -> String {
        if db == nil {
            do {
                try initializeDatabase()
            } catch {
                NSLog("[PasteVault][DB] upsertItem failed to initialize database: %@", error.localizedDescription)
                throw error
            }
        }

        let digest = SHA256.hash(data: rawPayload)
        let contentHash = digest.map { String(format: "%02x", $0) }.joined()
        let now = Int64(Date().timeIntervalSince1970)
        let expiresAt = ttlSeconds.map { now + $0 }
        let itemId = id ?? UUID().uuidString

        let upsertSQL = """
        INSERT INTO clipboard_items (
            id, content_type, text_preview, content_hash,
            source_bundle_id, source_app_name, is_sensitive, secret_kind,
            is_pinned, created_at, expires_at, file_path, ocr_text
        ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, 0, ?9, ?10, ?11, ?12)
        ON CONFLICT(content_hash) DO UPDATE SET
            id = excluded.id,
            created_at = excluded.created_at,
            expires_at = excluded.expires_at,
            source_bundle_id = COALESCE(excluded.source_bundle_id, clipboard_items.source_bundle_id),
            source_app_name = COALESCE(excluded.source_app_name, clipboard_items.source_app_name),
            file_path = COALESCE(excluded.file_path, clipboard_items.file_path),
            ocr_text = COALESCE(excluded.ocr_text, clipboard_items.ocr_text);
        """

        var stmt: OpaquePointer?
        let prepRC = sqlite3_prepare_v2(db, upsertSQL, -1, &stmt, nil)
        guard prepRC == SQLITE_OK else {
            let errMsg = db.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "database handle is nil"
            NSLog("[PasteVault][DB] upsertItem sqlite3_prepare_v2 failed (rc=%d): %@", prepRC, errMsg)
            throw NSError(domain: "PasteVault.SQLite", code: Int(prepRC), userInfo: [NSLocalizedDescriptionKey: "upsertItem prepare failed: \(errMsg)"])
        }
        defer { sqlite3_finalize(stmt) }

        bindTextExact(stmt, 1, itemId)
        sqlite3_bind_int(stmt, 2, contentType.rawValue)
        bindTextExact(stmt, 3, String(textPreview.prefix(500_000)))
        bindTextExact(stmt, 4, contentHash)
        bindOpt(stmt, 5, sourceBundleId)
        bindOpt(stmt, 6, sourceAppName)
        sqlite3_bind_int(stmt, 7, isSensitive ? 1 : 0)
        bindOpt(stmt, 8, secretKind)
        sqlite3_bind_int64(stmt, 9, now)
        if let expiresAt { sqlite3_bind_int64(stmt, 10, expiresAt) } else { sqlite3_bind_null(stmt, 10) }
        bindOpt(stmt, 11, fileURLPath)
        bindOpt(stmt, 12, ocrText)

        let stepRC = sqlite3_step(stmt)
        guard stepRC == SQLITE_DONE else {
            let errMsg = db.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "sqlite3_step failed"
            NSLog("[PasteVault][DB] upsertItem sqlite3_step failed (rc=%d) for id=%@: %@", stepRC, itemId, errMsg)
            throw NSError(domain: "PasteVault.SQLite", code: Int(stepRC), userInfo: [NSLocalizedDescriptionKey: "upsertItem step failed: \(errMsg)"])
        }
        return itemId
    }

    public func updateItemOCRText(id: String, ocrText: String?) throws {
        if db == nil {
            do {
                try initializeDatabase()
            } catch {
                NSLog("[PasteVault][DB] updateItemOCRText failed to initialize database: %@", error.localizedDescription)
                throw error
            }
        }
        var stmt: OpaquePointer?
        let prepRC = sqlite3_prepare_v2(db, "UPDATE clipboard_items SET ocr_text = ?1 WHERE id = ?2;", -1, &stmt, nil)
        guard prepRC == SQLITE_OK else {
            let errMsg = db.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "database handle is nil"
            NSLog("[PasteVault][DB] updateItemOCRText sqlite3_prepare_v2 failed (rc=%d): %@", prepRC, errMsg)
            throw NSError(domain: "PasteVault.SQLite", code: Int(prepRC), userInfo: [NSLocalizedDescriptionKey: "updateItemOCRText prepare failed: \(errMsg)"])
        }
        defer { sqlite3_finalize(stmt) }
        bindOpt(stmt, 1, ocrText)
        bindTextExact(stmt, 2, id)
        let stepRC = sqlite3_step(stmt)
        guard stepRC == SQLITE_DONE else {
            let errMsg = db.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "sqlite3_step failed"
            NSLog("[PasteVault][DB] updateItemOCRText sqlite3_step failed (rc=%d) for id=%@: %@", stepRC, id, errMsg)
            throw NSError(domain: "PasteVault.SQLite", code: Int(stepRC), userInfo: [NSLocalizedDescriptionKey: "updateItemOCRText step failed: \(errMsg)"])
        }
    }

    public func restoreItem(
        id: String,
        contentType: ContentKind,
        textPreview: String,
        contentHash: String,
        sourceBundleId: String?,
        sourceAppName: String?,
        isSensitive: Bool,
        secretKind: String?,
        isPinned: Bool,
        createdAt: Int64,
        expiresAt: Int64?,
        fileURLPath: String?,
        useCount: Int = 0,
        ocrText: String? = nil
    ) throws {
        if db == nil {
            try? initializeDatabase()
        }

        let sql = """
        INSERT INTO clipboard_items (
            id, content_type, text_preview, content_hash,
            source_bundle_id, source_app_name, is_sensitive, secret_kind,
            is_pinned, created_at, expires_at, file_path, use_count, ocr_text
        ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14)
        ON CONFLICT(content_hash) DO UPDATE SET
            is_pinned = CASE WHEN excluded.is_pinned = 1 THEN 1 ELSE clipboard_items.is_pinned END,
            source_bundle_id = COALESCE(excluded.source_bundle_id, clipboard_items.source_bundle_id),
            source_app_name = COALESCE(excluded.source_app_name, clipboard_items.source_app_name),
            file_path = COALESCE(excluded.file_path, clipboard_items.file_path),
            ocr_text = COALESCE(excluded.ocr_text, clipboard_items.ocr_text);
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        bindTextExact(stmt, 1, id)
        sqlite3_bind_int(stmt, 2, contentType.rawValue)
        bindTextExact(stmt, 3, String(textPreview.prefix(500_000)))
        bindTextExact(stmt, 4, contentHash)
        bindOpt(stmt, 5, sourceBundleId)
        bindOpt(stmt, 6, sourceAppName)
        sqlite3_bind_int(stmt, 7, isSensitive ? 1 : 0)
        bindOpt(stmt, 8, secretKind)
        sqlite3_bind_int(stmt, 9, isPinned ? 1 : 0)
        sqlite3_bind_int64(stmt, 10, createdAt)
        if let expiresAt {
            sqlite3_bind_int64(stmt, 11, expiresAt)
        } else {
            sqlite3_bind_null(stmt, 11)
        }
        bindOpt(stmt, 12, fileURLPath)
        sqlite3_bind_int(stmt, 13, Int32(useCount))
        bindOpt(stmt, 14, ocrText)

        _ = sqlite3_step(stmt)
    }

    public func queryItems(searchQuery: String, limit: Int32 = 100) throws -> [ClipboardItemRow] {
        if db == nil {
            try? initializeDatabase()
        }

        let now = Int64(Date().timeIntervalSince1970)
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        let sql = trimmed.isEmpty ? """
        SELECT rowid, id, content_type, text_preview, content_hash,
               source_bundle_id, source_app_name, is_sensitive, secret_kind,
               is_pinned, created_at, expires_at, use_count, file_path, ocr_text
        FROM clipboard_items
        WHERE expires_at IS NULL OR expires_at > ?1
        ORDER BY is_pinned DESC, created_at DESC
        LIMIT ?2;
        """ : """
        SELECT rowid, id, content_type, text_preview, content_hash,
               source_bundle_id, source_app_name, is_sensitive, secret_kind,
               is_pinned, created_at, expires_at, use_count, file_path, ocr_text
        FROM clipboard_items
        WHERE (expires_at IS NULL OR expires_at > ?1)
          AND (text_preview LIKE ?3 ESCAPE '\\' OR COALESCE(source_app_name, '') LIKE ?3 ESCAPE '\\' OR COALESCE(ocr_text, '') LIKE ?3 ESCAPE '\\')
        ORDER BY is_pinned DESC, created_at DESC
        LIMIT ?2;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, now)
        sqlite3_bind_int(stmt, 2, limit)
        if !trimmed.isEmpty {
            let escaped = trimmed
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "%", with: "\\%")
                .replacingOccurrences(of: "_", with: "\\_")
            let likePattern = "%\(escaped)%"
            bindTextExact(stmt, 3, likePattern)
        }

        let demotedIds = ClipboardMonitor.manuallyDemotedTextIds
        let promotedIds = ClipboardMonitor.manuallyPromotedSecretIds

        var results: [ClipboardItemRow] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let idValue = readTextColumn(stmt, 1),
                  let textPreviewValue = readTextColumn(stmt, 3),
                  let hashValue = readTextColumn(stmt, 4) else {
                continue
            }
            let row = ClipboardItemRow(
                id: idValue,
                rowid: sqlite3_column_int64(stmt, 0),
                contentType: ContentKind(rawValue: sqlite3_column_int(stmt, 2)) ?? .text,
                textPreview: textPreviewValue,
                contentHash: hashValue,
                sourceBundleId: readTextColumn(stmt, 5),
                sourceAppName: readTextColumn(stmt, 6),
                isSensitive: sqlite3_column_int(stmt, 7) != 0,
                secretKind: readTextColumn(stmt, 8),
                isPinned: sqlite3_column_int(stmt, 9) != 0,
                createdAt: sqlite3_column_int64(stmt, 10),
                expiresAt: sqlite3_column_type(stmt, 11) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(stmt, 11))),
                ocrText: readTextColumn(stmt, 14),
                rawImageData: nil,
                fileURLPath: readTextColumn(stmt, 13),
                useCount: Int(sqlite3_column_int(stmt, 12)),
                demotedIds: demotedIds,
                promotedIds: promotedIds
            )
            results.append(row)
        }
        return results
    }

    public func updateExpiresAt(id: String, expiresAt: Date?) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "UPDATE clipboard_items SET expires_at = ?1 WHERE id = ?2;", -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        if let expiresAt {
            sqlite3_bind_int64(stmt, 1, Int64(expiresAt.timeIntervalSince1970))
        } else {
            sqlite3_bind_null(stmt, 1)
        }
        bindTextExact(stmt, 2, id)
        _ = sqlite3_step(stmt)
    }

    public func updateSecretStatus(id: String, isSensitive: Bool, contentType: ContentKind, secretKind: String?, expiresAt: Date?) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "UPDATE clipboard_items SET is_sensitive = ?1, content_type = ?2, secret_kind = ?3, expires_at = ?4 WHERE id = ?5;", -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, isSensitive ? 1 : 0)
        sqlite3_bind_int(stmt, 2, contentType.rawValue)
        bindOpt(stmt, 3, secretKind)
        if let expiresAt {
            sqlite3_bind_int64(stmt, 4, Int64(expiresAt.timeIntervalSince1970))
        } else {
            sqlite3_bind_null(stmt, 4)
        }
        bindTextExact(stmt, 5, id)
        _ = sqlite3_step(stmt)
    }

    public func togglePin(id: String) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "UPDATE clipboard_items SET is_pinned = CASE WHEN is_pinned = 1 THEN 0 ELSE 1 END WHERE id = ?1;", -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        bindTextExact(stmt, 1, id)
        _ = sqlite3_step(stmt)
    }

    public func updateItemText(id: String, newText: String, newHash: String, contentType: ContentKind? = nil) throws {
        var stmt: OpaquePointer?
        if let contentType {
            guard sqlite3_prepare_v2(db, "UPDATE clipboard_items SET text_preview = ?1, content_hash = ?2, content_type = ?3 WHERE id = ?4;", -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            bindTextExact(stmt, 1, newText)
            bindTextExact(stmt, 2, newHash)
            sqlite3_bind_int(stmt, 3, contentType.rawValue)
            bindTextExact(stmt, 4, id)
            _ = sqlite3_step(stmt)
        } else {
            guard sqlite3_prepare_v2(db, "UPDATE clipboard_items SET text_preview = ?1, content_hash = ?2 WHERE id = ?3;", -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            bindTextExact(stmt, 1, newText)
            bindTextExact(stmt, 2, newHash)
            bindTextExact(stmt, 3, id)
            _ = sqlite3_step(stmt)
        }
    }

    public func updateContentType(id: String, contentType: ContentKind) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "UPDATE clipboard_items SET content_type = ?1 WHERE id = ?2;", -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, contentType.rawValue)
        bindTextExact(stmt, 2, id)
        _ = sqlite3_step(stmt)
    }

    nonisolated public static func screenshotsDirectoryURL() throws -> URL {
        let supportDir = try Self.pasteVaultSupportDirectory()
        let screenshotsDir = supportDir.appendingPathComponent("Screenshots", isDirectory: true)
        if !FileManager.default.fileExists(atPath: screenshotsDir.path) {
            try FileManager.default.createDirectory(
                at: screenshotsDir,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
        return screenshotsDir
    }

    nonisolated private static func sanitizedClipboardMediaItemId(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains("/"),
              !trimmed.contains("\\"),
              !trimmed.contains(".."),
              !trimmed.contains("\0") else {
            return nil
        }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
        guard trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }), trimmed.count <= 128 else {
            return nil
        }
        return trimmed
    }

    nonisolated public static func isPNGData(_ data: Data) -> Bool {
        let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        return data.count >= 8 && Array(data.prefix(8)) == pngSignature
    }

    nonisolated public static func saveClipboardScreenshotPNG(data: Data, itemId: String) -> String? {
        guard let safeId = sanitizedClipboardMediaItemId(itemId) else {
            NSLog("[PasteVault][DB] saveClipboardScreenshotPNG rejected invalid itemId=%@", itemId)
            return nil
        }
        let screenshotsDir: URL
        do {
            screenshotsDir = try screenshotsDirectoryURL()
        } catch {
            NSLog("[PasteVault][DB] saveClipboardScreenshotPNG failed to access Screenshots dir: %@", error.localizedDescription)
            return nil
        }
        let pngData: Data
        if isPNGData(data) {
            pngData = data
        } else if let rep = NSBitmapImageRep(data: data),
                  let converted = rep.representation(using: .png, properties: [:]) {
            pngData = converted
        } else if let img = NSImage(data: data),
                  let cgImage = img.cgImage(forProposedRect: nil, context: nil, hints: nil),
                  let converted = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) {
            pngData = converted
        } else {
            NSLog("[PasteVault][DB] saveClipboardScreenshotPNG failed to convert image data (%d bytes) for itemId=%@", data.count, safeId)
            return nil
        }
        let targetURL = screenshotsDir.appendingPathComponent("\(safeId).png")
        guard isSafeAllowedClipboardMediaURL(targetURL) else {
            NSLog("[PasteVault][DB] saveClipboardScreenshotPNG rejected unsafe targetURL=%@", targetURL.path)
            return nil
        }
        do {
            try pngData.write(to: targetURL, options: .atomic)
            return "Screenshots/\(safeId).png"
        } catch {
            NSLog("[PasteVault][DB] saveClipboardScreenshotPNG failed to write %@: %@", targetURL.path, error.localizedDescription)
            return nil
        }
    }

    nonisolated public static func safeScreenshotFileURL(for fileURLPath: String?, itemId: String) -> URL? {
        guard let supportDir = try? Self.pasteVaultSupportDirectory() else { return nil }
        let fm = FileManager.default

        if let rawPath = fileURLPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !rawPath.isEmpty,
           !rawPath.contains("\0") {
            let parts = rawPath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            if !parts.contains("..") {
                let candidateURL: URL
                if rawPath.hasPrefix("/") {
                    candidateURL = URL(fileURLWithPath: rawPath)
                } else {
                    candidateURL = supportDir.appendingPathComponent(rawPath)
                }
                if !candidateURL.pathComponents.contains(".."),
                   isSafeAllowedClipboardMediaURL(candidateURL),
                   fm.fileExists(atPath: candidateURL.path) {
                    return candidateURL
                }
            }
        }

        if let safeId = sanitizedClipboardMediaItemId(itemId) {
            let fallbackURL = supportDir
                .appendingPathComponent("Screenshots", isDirectory: true)
                .appendingPathComponent("\(safeId).png")
            if isSafeAllowedClipboardMediaURL(fallbackURL), fm.fileExists(atPath: fallbackURL.path) {
                return fallbackURL
            }
        }
        return nil
    }

    nonisolated public static func isSafeAllowedClipboardMediaURL(_ candidateURL: URL) -> Bool {
        guard let supportDir = try? Self.pasteVaultSupportDirectory() else { return false }
        let fileName = candidateURL.lastPathComponent
        guard !fileName.isEmpty,
              fileName != ".",
              fileName != "..",
              !fileName.hasPrefix("snippet_img_") else {
            return false
        }
        let allowedRoots = ["Screenshots", "Images"].map { dirName -> String in
            let resolved = supportDir
                .appendingPathComponent(dirName, isDirectory: true)
                .resolvingSymlinksInPath()
                .standardized.path
            return resolved.hasSuffix("/") ? resolved : (resolved + "/")
        }
        let parentResolved = candidateURL.deletingLastPathComponent().resolvingSymlinksInPath().standardized.path
        let normalizedFull = parentResolved + "/" + fileName
        return allowedRoots.contains { normalizedFull.hasPrefix($0) }
    }

    nonisolated public static func deleteClipboardMediaFilesIfNeeded(itemId: String, filePath: String?, contentTypeRaw: Int32) {
        guard let supportDir = try? Self.pasteVaultSupportDirectory() else { return }
        let fm = FileManager.default

        // 1. Удаляем явный file_path (только если это не ссылка на пользовательский .file и путь строго в Screenshots/ или Images/)
        if contentTypeRaw != ContentKind.file.rawValue,
           let rawPath = filePath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !rawPath.isEmpty,
           !rawPath.contains("\0") {
            let parts = rawPath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            if !parts.contains("..") {
                let candidateURL = rawPath.hasPrefix("/")
                    ? URL(fileURLWithPath: rawPath)
                    : supportDir.appendingPathComponent(rawPath)
                if !candidateURL.pathComponents.contains(".."),
                   isSafeAllowedClipboardMediaURL(candidateURL),
                   fm.fileExists(atPath: candidateURL.path) {
                    try? fm.removeItem(at: candidateURL)
                }
            }
        }

        // 2. Удаляем ассоциированный файл скриншота/изображения <id>.png из Screenshots/ или Images/
        let trimmedId = itemId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedId.isEmpty,
              !trimmedId.contains("/"),
              !trimmedId.contains("\\"),
              !trimmedId.contains(".."),
              !trimmedId.contains("\0") else { return }

        for dirName in ["Screenshots", "Images"] {
            let candidateURL = supportDir
                .appendingPathComponent(dirName, isDirectory: true)
                .appendingPathComponent("\(trimmedId).png")
            if isSafeAllowedClipboardMediaURL(candidateURL), fm.fileExists(atPath: candidateURL.path) {
                try? fm.removeItem(at: candidateURL)
            }
        }
    }

    private func fetchClipboardMediaTargets(whereClause: String? = nil, boundId: String? = nil) -> [(id: String, contentTypeRaw: Int32, filePath: String?)] {
        guard let db else { return [] }
        let sql: String
        if let whereClause {
            sql = "SELECT id, content_type, file_path FROM clipboard_items WHERE \(whereClause);"
        } else {
            sql = "SELECT id, content_type, file_path FROM clipboard_items;"
        }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        if let boundId {
            bindTextExact(stmt, 1, boundId)
        }
        var rows: [(String, Int32, String?)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let id = readTextColumn(stmt, 0) else { continue }
            let cType = sqlite3_column_int(stmt, 1)
            let path = readTextColumn(stmt, 2)
            rows.append((id, cType, path))
        }
        return rows
    }

    public func deleteItem(id: String) throws {
        let mediaTargets = fetchClipboardMediaTargets(whereClause: "id = ?1", boundId: id)

        func performDelete() -> Int32 {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "DELETE FROM clipboard_items WHERE id = ?1;", -1, &stmt, nil) == SQLITE_OK else {
                return sqlite3_errcode(db)
            }
            defer { sqlite3_finalize(stmt) }
            bindTextExact(stmt, 1, id)
            return sqlite3_step(stmt)
        }

        if performDelete() != SQLITE_DONE {
            _ = try? executeRaw("INSERT INTO clipboard_fts(clipboard_fts) VALUES('rebuild');")
            _ = performDelete()
        }

        for target in mediaTargets {
            Self.deleteClipboardMediaFilesIfNeeded(itemId: target.id, filePath: target.filePath, contentTypeRaw: target.contentTypeRaw)
        }
    }

    public func clearAllHistory() throws {
        let mediaTargets = fetchClipboardMediaTargets()
        if (try? executeRawThrowing("DELETE FROM clipboard_items;")) == nil {
            _ = try? executeRaw("INSERT INTO clipboard_fts(clipboard_fts) VALUES('rebuild');")
            _ = try? executeRawThrowing("DELETE FROM clipboard_items;")
        }
        _ = try? executeRaw("INSERT INTO clipboard_fts(clipboard_fts) VALUES('rebuild');")
        _ = try? executeRaw("VACUUM;")

        for target in mediaTargets {
            Self.deleteClipboardMediaFilesIfNeeded(itemId: target.id, filePath: target.filePath, contentTypeRaw: target.contentTypeRaw)
        }
        if let supportDir = try? Self.pasteVaultSupportDirectory() {
            let screenshotsDir = supportDir.appendingPathComponent("Screenshots", isDirectory: true)
            if let entries = try? FileManager.default.contentsOfDirectory(at: screenshotsDir, includingPropertiesForKeys: [.isSymbolicLinkKey]) {
                for url in entries {
                    let isSymlink = (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) ?? false
                    if !isSymlink, Self.isSafeAllowedClipboardMediaURL(url) {
                        try? FileManager.default.removeItem(at: url)
                    }
                }
            }
        }
    }

    public func clearUnpinnedHistory() throws {
        let mediaTargets = fetchClipboardMediaTargets(whereClause: "is_pinned = 0")
        if (try? executeRawThrowing("DELETE FROM clipboard_items WHERE is_pinned = 0;")) == nil {
            _ = try? executeRaw("INSERT INTO clipboard_fts(clipboard_fts) VALUES('rebuild');")
            try executeRawThrowing("DELETE FROM clipboard_items WHERE is_pinned = 0;")
        }
        for target in mediaTargets {
            Self.deleteClipboardMediaFilesIfNeeded(itemId: target.id, filePath: target.filePath, contentTypeRaw: target.contentTypeRaw)
        }
    }

    func executeRaw(_ sql: String) throws {
        try executeRawThrowing(sql)
    }

    /// Возвращает число совпадений в FTS5-индексе (для проверки триггеров в тестах)
    func countFTSMatches(for query: String) throws -> Int {
        if db == nil {
            try initializeDatabase()
        }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM clipboard_fts WHERE clipboard_fts MATCH ?1;", -1, &stmt, nil) == SQLITE_OK else {
            let msg = db.flatMap { sqlite3_errmsg($0).map { String(cString: $0) } } ?? "Prepare error"
            throw NSError(domain: "PasteVault.SQLite", code: 1, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        defer { sqlite3_finalize(stmt) }
        bindTextExact(stmt, 1, query)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(stmt, 0))
    }

    private func executeRawThrowing(_ sql: String) throws {
        guard let db else {
            throw NSError(domain: "PasteVault.SQLite", code: Int(SQLITE_MISUSE), userInfo: [NSLocalizedDescriptionKey: "Database handle is nil"])
        }
        var errMsg: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &errMsg)
        if let errMsg {
            let message = String(cString: errMsg)
            sqlite3_free(errMsg)
            if rc != SQLITE_OK {
                throw NSError(domain: "PasteVault.SQLite", code: Int(rc), userInfo: [NSLocalizedDescriptionKey: message])
            }
        } else if rc != SQLITE_OK {
            let fallbackMsg = sqlite3_errmsg(db).map { String(cString: $0) } ?? "SQLite error \(rc)"
            throw NSError(domain: "PasteVault.SQLite", code: Int(rc), userInfo: [NSLocalizedDescriptionKey: fallbackMsg])
        }
    }

    private func bindTextExact(_ stmt: OpaquePointer?, _ index: Int32, _ value: String) {
        let bytes = Array(value.utf8)
        if bytes.isEmpty {
            sqlite3_bind_text(stmt, index, "", 0, SQLITE_TRANSIENT)
        } else {
            bytes.withUnsafeBytes { rawBuf in
                let ptr = rawBuf.bindMemory(to: CChar.self).baseAddress
                sqlite3_bind_text(stmt, index, ptr, Int32(bytes.count), SQLITE_TRANSIENT)
            }
        }
    }

    private func readTextColumn(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL else { return nil }
        guard let textPtr = sqlite3_column_text(stmt, index) else { return "" }
        let byteCount = Int(sqlite3_column_bytes(stmt, index))
        if byteCount <= 0 { return "" }
        let data = Data(bytes: textPtr, count: byteCount)
        return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }

    private func bindOpt(_ stmt: OpaquePointer?, _ index: Int32, _ val: String?) {
        if let val { bindTextExact(stmt, index, val) } else { sqlite3_bind_null(stmt, index) }
    }

    // MARK: - Snippet Categories & Snippets CRUD

    public func seedDefaultSnippetCategoriesIfNeeded() {
        if db == nil {
            try? initializeDatabase()
        }
        let initialSeededKey = "pv_initial_categories_seeded_v1"
        guard !AppDefaults.shared.bool(forKey: initialSeededKey) else {
            return
        }

        let defaults: [(String, String, Int)] = [
            ("Работа", "briefcase.fill", 0),
            ("Разработка", "chevron.left.forwardslash.chevron.right", 1),
            ("Шаблоны", "doc.text.fill", 2),
            ("Промпты", "sparkles", 3)
        ]

        let existing = fetchSnippetCategories()
        let existingLowerNames = Set(existing.map { $0.name.lowercased() })

        for (name, icon, order) in defaults {
            if let current = existing.first(where: { $0.name.lowercased() == name.lowercased() }) {
                if current.sortOrder != order || current.iconName != icon {
                    var stmt: OpaquePointer?
                    let sql = "UPDATE snippet_categories SET sort_order = ?1, icon_name = ?2 WHERE id = ?3;"
                    if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                        sqlite3_bind_int(stmt, 1, Int32(order))
                        bindTextExact(stmt, 2, icon)
                        bindTextExact(stmt, 3, current.id.uuidString)
                        _ = sqlite3_step(stmt)
                        sqlite3_finalize(stmt)
                    }
                }
            } else {
                var stmt: OpaquePointer?
                let sql = "INSERT OR IGNORE INTO snippet_categories (id, name, icon_name, sort_order, created_at) VALUES (?1, ?2, ?3, ?4, ?5);"
                if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                    bindTextExact(stmt, 1, UUID().uuidString)
                    bindTextExact(stmt, 2, name)
                    bindTextExact(stmt, 3, icon)
                    sqlite3_bind_int(stmt, 4, Int32(order))
                    sqlite3_bind_double(stmt, 5, Date().timeIntervalSince1970)
                    _ = sqlite3_step(stmt)
                    sqlite3_finalize(stmt)
                }
            }
        }

        // Проверяем существующие сниппеты в AppDefaults
        if let data = AppDefaults.shared.data(forKey: "pasteVaultQuickSnippets"),
           let snippets = try? JSONDecoder().decode([QuickSnippetItem].self, from: data) {
            let defaultCategoryNames = Set(defaults.map { $0.0.lowercased() })
            var nextOrder = 4
            for snippet in snippets {
                let catTrimmed = snippet.category.trimmingCharacters(in: .whitespacesAndNewlines)
                if !catTrimmed.isEmpty && !defaultCategoryNames.contains(catTrimmed.lowercased()) && !existingLowerNames.contains(catTrimmed.lowercased()) {
                    let icon = (catTrimmed == "Поддержка" || catTrimmed == "Контакты") ? "bubble.left.and.bubble.right.fill" : "doc.text.fill"
                    var stmt: OpaquePointer?
                    let sql = "INSERT OR IGNORE INTO snippet_categories (id, name, icon_name, sort_order, created_at) VALUES (?1, ?2, ?3, ?4, ?5);"
                    if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                        bindTextExact(stmt, 1, UUID().uuidString)
                        bindTextExact(stmt, 2, catTrimmed)
                        bindTextExact(stmt, 3, icon)
                        sqlite3_bind_int(stmt, 4, Int32(nextOrder))
                        sqlite3_bind_double(stmt, 5, Date().timeIntervalSince1970)
                        _ = sqlite3_step(stmt)
                        sqlite3_finalize(stmt)
                    }
                    nextOrder += 1
                }
            }
        }

        AppDefaults.shared.set(true, forKey: initialSeededKey)
        AppDefaults.shared.set(true, forKey: "pv_snippet_categories_seeded_v1")
        AppDefaults.shared.set(true, forKey: "pv_snippet_categories_restored_v2")
    }

    public func fetchSnippetCategories() -> [SnippetCategoryRecord] {
        if db == nil {
            try? initializeDatabase()
        }
        var stmt: OpaquePointer?
        let sql = "SELECT id, name, icon_name, sort_order, created_at FROM snippet_categories ORDER BY sort_order ASC, created_at ASC;"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        var results: [SnippetCategoryRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let idStr = readTextColumn(stmt, 0),
                  let name = readTextColumn(stmt, 1),
                  let iconName = readTextColumn(stmt, 2) else { continue }
            let sortOrder = Int(sqlite3_column_int(stmt, 3))
            let createdAtSec = sqlite3_column_double(stmt, 4)

            let id = UUID(uuidString: idStr) ?? UUID()
            let createdAt = Date(timeIntervalSince1970: createdAtSec)
            results.append(SnippetCategoryRecord(id: id, name: name, iconName: iconName, sortOrder: sortOrder, createdAt: createdAt))
        }
        return results
    }

    public func createSnippetCategory(name: String, iconName: String) -> SnippetCategoryRecord? {
        let trimmed = sanitizeCategoryNameInput(name).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let existing = fetchSnippetCategories()
        if existing.contains(where: { $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }) {
            return nil
        }

        let newId = UUID()
        let sortOrder = (existing.map(\.sortOrder).max() ?? -1) + 1
        let now = Date()

        var stmt: OpaquePointer?
        let sql = "INSERT INTO snippet_categories (id, name, icon_name, sort_order, created_at) VALUES (?1, ?2, ?3, ?4, ?5);"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        bindTextExact(stmt, 1, newId.uuidString)
        bindTextExact(stmt, 2, trimmed)
        bindTextExact(stmt, 3, iconName)
        sqlite3_bind_int(stmt, 4, Int32(sortOrder))
        sqlite3_bind_double(stmt, 5, now.timeIntervalSince1970)

        guard sqlite3_step(stmt) == SQLITE_DONE else { return nil }
        return SnippetCategoryRecord(id: newId, name: trimmed, iconName: iconName, sortOrder: sortOrder, createdAt: now)
    }

    public func renameSnippetCategory(id: UUID, newName: String, newIconName: String? = nil) throws {
        let existing = fetchSnippetCategories()
        let icon = newIconName ?? (existing.first(where: { $0.id == id })?.iconName ?? "doc.text.fill")
        try updateSnippetCategory(id: id, newName: newName, newIconName: icon)
    }

    public func updateSnippetCategory(id: UUID, newName: String, newIconName: String) throws {
        let trimmed = sanitizeCategoryNameInput(newName).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let existing = fetchSnippetCategories()
        guard let current = existing.first(where: { $0.id == id }) else { return }

        if current.name.localizedCaseInsensitiveCompare(trimmed) != .orderedSame {
            if existing.contains(where: { $0.id != id && $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }) {
                return
            }
        }

        let oldName = current.name
        let nameChanged = (oldName != trimmed)

        try executeRaw("BEGIN TRANSACTION;")
        do {
            var stmt: OpaquePointer?
            let sql = "UPDATE snippet_categories SET name = ?1, icon_name = ?2 WHERE id = ?3;"
            let prepRC = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
            guard prepRC == SQLITE_OK, let stmt else {
                let msg = db.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "prepare failed (\(prepRC))"
                throw NSError(domain: "PasteVault.SQLite", code: Int(prepRC), userInfo: [NSLocalizedDescriptionKey: msg])
            }
            bindTextExact(stmt, 1, trimmed)
            bindTextExact(stmt, 2, newIconName)
            bindTextExact(stmt, 3, id.uuidString)
            let stepRC = sqlite3_step(stmt)
            sqlite3_finalize(stmt)
            guard stepRC == SQLITE_DONE else {
                let msg = db.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "step failed (\(stepRC))"
                throw NSError(domain: "PasteVault.SQLite", code: Int(stepRC), userInfo: [NSLocalizedDescriptionKey: msg])
            }

            if nameChanged {
                let oldLower = oldName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let allSnippets = fetchSnippets()
                let matchingIds = allSnippets
                    .filter { $0.category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == oldLower }
                    .map(\.id)

                for snippetId in matchingIds {
                    var updateSnippetsStmt: OpaquePointer?
                    let snipSql = "UPDATE snippets SET category = ?1 WHERE id = ?2;"
                    let snipPrep = sqlite3_prepare_v2(db, snipSql, -1, &updateSnippetsStmt, nil)
                    guard snipPrep == SQLITE_OK, let updateSnippetsStmt else {
                        let msg = db.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "prepare failed (\(snipPrep))"
                        throw NSError(domain: "PasteVault.SQLite", code: Int(snipPrep), userInfo: [NSLocalizedDescriptionKey: msg])
                    }
                    bindTextExact(updateSnippetsStmt, 1, trimmed)
                    bindTextExact(updateSnippetsStmt, 2, snippetId)
                    let snipStep = sqlite3_step(updateSnippetsStmt)
                    sqlite3_finalize(updateSnippetsStmt)
                    guard snipStep == SQLITE_DONE else {
                        let msg = db.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "step failed (\(snipStep))"
                        throw NSError(domain: "PasteVault.SQLite", code: Int(snipStep), userInfo: [NSLocalizedDescriptionKey: msg])
                    }
                }

                if let data = AppDefaults.shared.data(forKey: "pasteVaultQuickSnippets"),
                   var snippets = try? JSONDecoder().decode([QuickSnippetItem].self, from: data) {
                    var modified = false
                    for i in 0..<snippets.count {
                        if snippets[i].category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == oldLower {
                            snippets[i].category = trimmed
                            modified = true
                        }
                    }
                    if modified, let encoded = try? JSONEncoder().encode(snippets) {
                        AppDefaults.shared.set(encoded, forKey: "pasteVaultQuickSnippets")
                    }
                }
            }
            try executeRaw("COMMIT;")
        } catch {
            try? executeRaw("ROLLBACK;")
            throw error
        }
    }

    public func deleteSnippetCategoryAndSnippets(id: UUID) throws {
        let existing = fetchSnippetCategories()
        guard let current = existing.first(where: { $0.id == id }) else { return }
        let catLower = current.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let allSnippets = fetchSnippets()
        let toDelete = allSnippets.filter {
            $0.category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == catLower
        }

        try executeRaw("BEGIN TRANSACTION;")
        do {
            for item in toDelete {
                var stmt1: OpaquePointer?
                let sql1 = "DELETE FROM snippets WHERE id = ?1;"
                let prep1 = sqlite3_prepare_v2(db, sql1, -1, &stmt1, nil)
                guard prep1 == SQLITE_OK, let stmt1 else {
                    let msg = db.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "prepare failed (\(prep1))"
                    throw NSError(domain: "PasteVault.SQLite", code: Int(prep1), userInfo: [NSLocalizedDescriptionKey: msg])
                }
                bindTextExact(stmt1, 1, item.id)
                let step1 = sqlite3_step(stmt1)
                sqlite3_finalize(stmt1)
                guard step1 == SQLITE_DONE else {
                    let msg = db.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "step failed (\(step1))"
                    throw NSError(domain: "PasteVault.SQLite", code: Int(step1), userInfo: [NSLocalizedDescriptionKey: msg])
                }
            }

            var stmt2: OpaquePointer?
            let sql2 = "DELETE FROM snippet_categories WHERE id = ?1;"
            let prep2 = sqlite3_prepare_v2(db, sql2, -1, &stmt2, nil)
            guard prep2 == SQLITE_OK, let stmt2 else {
                let msg = db.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "prepare failed (\(prep2))"
                throw NSError(domain: "PasteVault.SQLite", code: Int(prep2), userInfo: [NSLocalizedDescriptionKey: msg])
            }
            bindTextExact(stmt2, 1, id.uuidString)
            let step2 = sqlite3_step(stmt2)
            sqlite3_finalize(stmt2)
            guard step2 == SQLITE_DONE else {
                let msg = db.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "step failed (\(step2))"
                throw NSError(domain: "PasteVault.SQLite", code: Int(step2), userInfo: [NSLocalizedDescriptionKey: msg])
            }

            try executeRaw("COMMIT;")

            for item in toDelete {
                Self.deleteSnippetImageFileIfNeeded(item.imagePath)
            }

            if let data = AppDefaults.shared.data(forKey: "pasteVaultQuickSnippets"),
               var snippets = try? JSONDecoder().decode([QuickSnippetItem].self, from: data) {
                let initialCount = snippets.count
                snippets.removeAll { $0.category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == catLower }
                if snippets.count != initialCount, let encoded = try? JSONEncoder().encode(snippets) {
                    AppDefaults.shared.set(encoded, forKey: "pasteVaultQuickSnippets")
                }
            }
        } catch {
            try? executeRaw("ROLLBACK;")
            throw error
        }
    }

    /// Удаляет фрагменты-сироты, чья категория больше не существует в `snippet_categories` (регистронезависимо, включая кириллицу),
    /// а также любые фрагменты с пустой или фиктивной категорией `"Нет категорий"` / `"No categories"`.
    @discardableResult
    public func cleanupOrphanedSnippets() -> Int {
        let validLowerNames = Set(
            fetchSnippetCategories().map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        )
        let isCategoryValid: (String) -> Bool = { raw in
            let lower = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !lower.isEmpty, lower != "нет категорий", lower != "no categories" else { return false }
            return validLowerNames.contains(lower)
        }
        let allSnippets = fetchSnippets()
        let orphans = allSnippets.filter { !isCategoryValid($0.category) }

        for orphan in orphans {
            var stmt: OpaquePointer?
            let sql = "DELETE FROM snippets WHERE id = ?1;"
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                bindTextExact(stmt, 1, orphan.id)
                _ = sqlite3_step(stmt)
                sqlite3_finalize(stmt)
            }
            Self.deleteSnippetImageFileIfNeeded(orphan.imagePath)
        }

        if let data = AppDefaults.shared.data(forKey: "pasteVaultQuickSnippets"),
           var cached = try? JSONDecoder().decode([QuickSnippetItem].self, from: data) {
            let before = cached.count
            cached.removeAll { !isCategoryValid($0.category) }
            if cached.count != before, let encoded = try? JSONEncoder().encode(cached) {
                AppDefaults.shared.set(encoded, forKey: "pasteVaultQuickSnippets")
            }
        }

        return orphans.count
    }

    nonisolated public static func isSafeAllowedSnippetImageURL(_ candidateURL: URL) -> Bool {
        guard let supportDir = try? Self.pasteVaultSupportDirectory() else { return false }
        let allowedImagesDir = supportDir
            .appendingPathComponent("Images", isDirectory: true)
            .resolvingSymlinksInPath()
            .standardized
        let basePathWithSlash = allowedImagesDir.path.hasSuffix("/") ? allowedImagesDir.path : (allowedImagesDir.path + "/")

        let parentResolved = candidateURL.deletingLastPathComponent().resolvingSymlinksInPath().standardized.path
        let fileName = candidateURL.lastPathComponent
        guard !fileName.isEmpty, fileName != ".", fileName != ".." else { return false }
        let normalizedFull = parentResolved + "/" + fileName
        return normalizedFull.hasPrefix(basePathWithSlash)
    }

    nonisolated public static func deleteSnippetImageFileIfNeeded(_ imagePath: String?) {
        guard let rawPath = imagePath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawPath.isEmpty,
              !rawPath.contains("\0") else { return }

        // Отклоняем любые попытки path traversal ("..")
        let slashParts = rawPath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !slashParts.contains("..") else { return }

        guard let supportDir = try? Self.pasteVaultSupportDirectory() else { return }
        let imagesDir = supportDir.appendingPathComponent("Images", isDirectory: true)
        let candidateURL: URL
        if rawPath.hasPrefix("/") {
            candidateURL = URL(fileURLWithPath: rawPath)
        } else {
            // Относительный путь не должен содержать подкаталогов
            guard !rawPath.contains("/") else { return }
            candidateURL = imagesDir.appendingPathComponent(rawPath)
        }

        guard !candidateURL.pathComponents.contains(".."),
              isSafeAllowedSnippetImageURL(candidateURL) else {
            return
        }

        try? FileManager.default.removeItem(at: candidateURL)
    }

    public func deleteSnippet(id: UUID) throws {
        try deleteSnippet(idString: id.uuidString)
    }

    public func deleteSnippet(idString: String) throws {
        if db == nil { try? initializeDatabase() }
        var selectStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT image_path FROM snippets WHERE id = ?1;", -1, &selectStmt, nil) == SQLITE_OK {
            bindTextExact(selectStmt, 1, idString)
            if sqlite3_step(selectStmt) == SQLITE_ROW, let path = readTextColumn(selectStmt, 0) {
                Self.deleteSnippetImageFileIfNeeded(path)
            }
            sqlite3_finalize(selectStmt)
        }

        var stmt: OpaquePointer?
        let sql = "DELETE FROM snippets WHERE id = ?1;"
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            bindTextExact(stmt, 1, idString)
            _ = sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }

        if let data = AppDefaults.shared.data(forKey: "pasteVaultQuickSnippets"),
           var snippets = try? JSONDecoder().decode([QuickSnippetItem].self, from: data) {
            let initialCount = snippets.count
            snippets.removeAll { $0.id == idString }
            if snippets.count != initialCount, let encoded = try? JSONEncoder().encode(snippets) {
                AppDefaults.shared.set(encoded, forKey: "pasteVaultQuickSnippets")
            }
        }
    }

    /// Удаляет все незакреплённые фрагменты из SQLite и их файлы изображений с диска
    public func deleteUnpinnedSnippets() {
        if db == nil { try? initializeDatabase() }
        var selectStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT image_path FROM snippets WHERE is_pinned = 0 AND image_path IS NOT NULL;", -1, &selectStmt, nil) == SQLITE_OK {
            while sqlite3_step(selectStmt) == SQLITE_ROW {
                if let path = readTextColumn(selectStmt, 0) {
                    Self.deleteSnippetImageFileIfNeeded(path)
                }
            }
            sqlite3_finalize(selectStmt)
        }

        var delStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "DELETE FROM snippets WHERE is_pinned = 0;", -1, &delStmt, nil) == SQLITE_OK {
            _ = sqlite3_step(delStmt)
            sqlite3_finalize(delStmt)
        }

        if let data = AppDefaults.shared.data(forKey: "pasteVaultQuickSnippets"),
           var snippets = try? JSONDecoder().decode([QuickSnippetItem].self, from: data) {
            snippets.removeAll { !$0.isPinned }
            if let encoded = try? JSONEncoder().encode(snippets) {
                AppDefaults.shared.set(encoded, forKey: "pasteVaultQuickSnippets")
            }
        }
    }

    /// Удаляет все фрагменты из SQLite (используется при восстановлении бэкапа в режиме Replace)
    public func deleteAllSnippets() {
        if db == nil { try? initializeDatabase() }
        var selectStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT image_path FROM snippets WHERE image_path IS NOT NULL;", -1, &selectStmt, nil) == SQLITE_OK {
            while sqlite3_step(selectStmt) == SQLITE_ROW {
                if let path = readTextColumn(selectStmt, 0) {
                    Self.deleteSnippetImageFileIfNeeded(path)
                }
            }
            sqlite3_finalize(selectStmt)
        }

        var delStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "DELETE FROM snippets;", -1, &delStmt, nil) == SQLITE_OK {
            _ = sqlite3_step(delStmt)
            sqlite3_finalize(delStmt)
        }
    }

    /// Удаляет осиротевшие файлы snippet_img_* в Application Support/PasteVault/Images/, на которые не ссылается ни один фрагмент в SQLite
    public func cleanupUnusedSnippetImageFiles(activeImagePaths: Set<String>? = nil) {
        if db == nil { try? initializeDatabase() }
        var activePaths = activeImagePaths ?? Set<String>()
        if activeImagePaths == nil {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, "SELECT image_path FROM snippets WHERE image_path IS NOT NULL;", -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    if let rawPath = readTextColumn(stmt, 0) {
                        let path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !path.isEmpty {
                            activePaths.insert(path)
                            activePaths.insert(URL(fileURLWithPath: path).lastPathComponent)
                        }
                    }
                }
                sqlite3_finalize(stmt)
            }
        }

        let fm = FileManager.default
        guard let pasteVaultDir = try? Self.pasteVaultSupportDirectory() else { return }
        let imagesDir = pasteVaultDir.appendingPathComponent("Images")
        guard let contents = try? fm.contentsOfDirectory(at: imagesDir, includingPropertiesForKeys: nil) else { return }

        for fileURL in contents {
            let name = fileURL.lastPathComponent
            guard name.hasPrefix("snippet_img_") else { continue }
            if !activePaths.contains(fileURL.path) && !activePaths.contains(name) {
                try? fm.removeItem(at: fileURL)
            }
        }
    }

    public func insertSnippet(id: String, title: String, content: String, category: String, isPinned: Bool = false, imagePath: String? = nil, useCount: Int = 0, createdAt: Double? = nil) -> Bool {
        let trimmedCat = category.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowerCat = trimmedCat.lowercased()
        guard !trimmedCat.isEmpty, lowerCat != "нет категорий", lowerCat != "no categories" else {
            return false
        }
        if db == nil {
            try? initializeDatabase()
        }
        var stmt: OpaquePointer?
        let sql = """
        INSERT INTO snippets (id, title, content, category, is_pinned, image_path, use_count, created_at)
        VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
        ON CONFLICT(id) DO UPDATE SET
            title = excluded.title,
            content = excluded.content,
            category = excluded.category,
            is_pinned = excluded.is_pinned,
            image_path = excluded.image_path,
            use_count = MAX(snippets.use_count, excluded.use_count);
        """
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }
        bindTextExact(stmt, 1, id)
        bindTextExact(stmt, 2, title)
        bindTextExact(stmt, 3, content)
        bindTextExact(stmt, 4, category)
        sqlite3_bind_int(stmt, 5, isPinned ? 1 : 0)
        bindOpt(stmt, 6, imagePath)
        sqlite3_bind_int(stmt, 7, Int32(max(0, useCount)))
        sqlite3_bind_double(stmt, 8, createdAt ?? Date().timeIntervalSince1970)
        return sqlite3_step(stmt) == SQLITE_DONE
    }

    /// Проверяет наличие реальной категории (при необходимости автоматически создаёт её) и сохраняет фрагмент.
    /// Никогда не сохраняет фрагмент с пустой категорией или `"Нет категорий"` / `"No categories"`.
    public func ensureCategoryAndSaveSnippet(
        id: String,
        title: String,
        content: String,
        categoryName: String,
        iconName: String = "folder.fill",
        isPinned: Bool = false,
        imagePath: String? = nil,
        useCount: Int = 0,
        createdAt: Double? = nil
    ) -> (saved: Bool, resolvedCategory: SnippetCategoryRecord?) {
        let trimmedCat = categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowerCat = trimmedCat.lowercased()
        guard !trimmedCat.isEmpty, lowerCat != "нет категорий", lowerCat != "no categories" else {
            return (false, nil)
        }

        let existingCats = fetchSnippetCategories()
        let resolvedCat: SnippetCategoryRecord?
        if let existing = existingCats.first(where: { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == lowerCat }) {
            resolvedCat = existing
        } else {
            resolvedCat = createSnippetCategory(name: trimmedCat, iconName: iconName)
        }

        guard let finalCat = resolvedCat else {
            return (false, nil)
        }

        let ok = insertSnippet(
            id: id,
            title: title,
            content: content,
            category: finalCat.name,
            isPinned: isPinned,
            imagePath: imagePath,
            useCount: useCount,
            createdAt: createdAt
        )
        return (ok, ok ? finalCat : nil)
    }

    public func incrementSnippetUseCount(id: UUID) {
        incrementSnippetUseCount(idString: id.uuidString)
    }

    public func incrementSnippetUseCount(idString: String) {
        if db == nil {
            try? initializeDatabase()
        }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "UPDATE snippets SET use_count = COALESCE(use_count, 0) + 1 WHERE id = ?1;", -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        bindTextExact(stmt, 1, idString)
        _ = sqlite3_step(stmt)
    }

    public func fetchSnippets() -> [QuickSnippetItem] {
        if db == nil {
            try? initializeDatabase()
        }
        var list: [QuickSnippetItem] = []
        var stmt: OpaquePointer?
        let sql = "SELECT id, title, content, category, is_pinned, image_path, COALESCE(use_count, 0), COALESCE(created_at, 0) FROM snippets ORDER BY is_pinned DESC, rowid DESC;"
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            defer { sqlite3_finalize(stmt) }
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let id = readTextColumn(stmt, 0),
                      let title = readTextColumn(stmt, 1),
                      let content = readTextColumn(stmt, 2),
                      let category = readTextColumn(stmt, 3) else { continue }
                let isPinned = sqlite3_column_int(stmt, 4) != 0
                let imagePath = readTextColumn(stmt, 5)
                let useCount = Int(sqlite3_column_int(stmt, 6))
                let createdAt = sqlite3_column_double(stmt, 7)
                list.append(QuickSnippetItem(id: id, title: title, content: content, category: category, isPinned: isPinned, imagePath: imagePath, useCount: useCount, createdAt: createdAt))
            }
        }
        return list
    }

    public func resetSnippetCategoriesSeededFlagForTesting() {
        AppDefaults.shared.removeObject(forKey: "pv_initial_categories_seeded_v1")
        AppDefaults.shared.removeObject(forKey: "pv_snippet_categories_seeded_v1")
        AppDefaults.shared.removeObject(forKey: "pv_snippet_categories_restored_v2")
        try? executeRaw("DELETE FROM snippet_categories;")
        seedDefaultSnippetCategoriesIfNeeded()
    }

    public func seedStressTest100SnippetsIfNeeded(force: Bool = false) {
        if db == nil {
            try? initializeDatabase()
        }
        let seededKey = "pv_cleaned_to_4_starter_snippets_v1"
        if !force && AppDefaults.shared.bool(forKey: seededKey) {
            return
        }

        // 1. Убеждаемся, что 4 категории по умолчанию существуют в snippet_categories
        seedDefaultSnippetCategoriesIfNeeded()

        // 2. Удаляем старые автоматически сгенерированные стресс-тестовые и 20-карточные шаблоны
        let legacyPrefixes = [
            "Отчёт по спринту #",
            "Ежедневный стендап-отчёт #",
            "Конфигурация деплоя #",
            "Деловой ответ клиенту #",
            "Шаблон ответа клиенту #",
            "Архитектурный ревью кода #"
        ]
        if let db {
            for prefix in legacyPrefixes {
                let sql = "DELETE FROM snippets WHERE title LIKE ?;"
                var stmt: OpaquePointer?
                if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                    bindTextExact(stmt, 1, "\(prefix)%")
                    sqlite3_step(stmt)
                }
                sqlite3_finalize(stmt)
            }
        }

        // 3. Получаем оставшиеся (пользовательские) фрагменты из SQLite
        var allSnippets = fetchSnippets()
        if allSnippets.isEmpty {
            if let data = AppDefaults.shared.data(forKey: "pasteVaultQuickSnippets"),
               let saved = try? JSONDecoder().decode([QuickSnippetItem].self, from: data) {
                let filtered = saved.filter { item in
                    !legacyPrefixes.contains(where: { item.title.hasPrefix($0) })
                }
                for s in filtered {
                    _ = insertSnippet(id: s.id, title: s.title, content: s.content, category: s.category, isPinned: s.isPinned)
                }
                allSnippets = fetchSnippets()
            }
        }

        // 4. Добавляем ровно по 1 красивой стартовой карточке в пустые стандартные категории (все с isPinned = false)
        let starterCards: [(category: String, title: String, content: String)] = [
            (
                "Работа",
                "Ежедневный статус-отчёт",
                """
                📋 Статус по задачам ({{date}}):
                • Выполнено сегодня:
                • В работе сейчас:
                • Блокеры / вопросы:

                Обновлено в {{time}}.
                """
            ),
            (
                "Разработка",
                "Шаблон Pull Request",
                """
                ## Что сделано ({{iso}})
                - Опишите ключевые изменения

                ## Как проверено
                - [ ] `swift test` пройден
                - [ ] Проверено локально в {{app}}
                """
            ),
            (
                "Шаблоны",
                "Деловой ответ клиенту",
                """
                Здравствуйте!

                Благодарим за обращение ({{date}}). Ваш запрос принят в работу и передан специалисту.
                Мы вернёмся с ответом в ближайшее время.

                С уважением,
                {{user}}
                """
            ),
            (
                "Промпты",
                "Ревью кода и архитектуры",
                """
                Ты — ведущий инженер macOS / Swift.
                Проведи краткое ревью фрагмента ниже ({{date}}):
                1. Потокобезопасность и управление памятью.
                2. Граничные случаи (edge cases) и читаемость.
                3. Конкретные рекомендации по улучшению.
                """
            )
        ]

        for starter in starterCards {
            let hasAnyInCat = allSnippets.contains {
                $0.category.localizedCaseInsensitiveCompare(starter.category) == .orderedSame
            }
            guard !hasAnyInCat else { continue }

            let id = UUID().uuidString
            _ = insertSnippet(
                id: id,
                title: starter.title,
                content: starter.content,
                category: starter.category,
                isPinned: false
            )
            allSnippets.append(
                QuickSnippetItem(
                    id: id,
                    title: starter.title,
                    content: starter.content,
                    category: starter.category,
                    isPinned: false
                )
            )
        }

        if let encoded = try? JSONEncoder().encode(allSnippets) {
            AppDefaults.shared.set(encoded, forKey: "pasteVaultQuickSnippets")
        }
        AppDefaults.shared.set(true, forKey: seededKey)
    }

    /// Одноразовая миграция для замены «живого» макроса {{clipboard}} на статический текст во всех ранее сохранённых карточках
    public func fixSavedClipboardMacrosIfNeeded() {
        let key = "pv_fix_saved_clipboard_macros_v1"
        guard !AppDefaults.shared.bool(forKey: key) else { return }
        if db == nil {
            try? initializeDatabase()
        }
        let sampleReplacement = "Скопированный фрагмент кода"
        let snippets = fetchSnippets()
        for s in snippets where s.content.range(of: "{{clipboard}}", options: .caseInsensitive) != nil {
            let regex = try? NSRegularExpression(pattern: "\\{\\{clipboard\\}\\}", options: .caseInsensitive)
            let range = NSRange(location: 0, length: (s.content as NSString).length)
            let fixedContent = regex?.stringByReplacingMatches(
                in: s.content,
                options: [],
                range: range,
                withTemplate: NSRegularExpression.escapedTemplate(for: sampleReplacement)
            ) ?? s.content.replacingOccurrences(of: "{{clipboard}}", with: sampleReplacement, options: .caseInsensitive)

            _ = insertSnippet(id: s.id, title: s.title, content: fixedContent, category: s.category, isPinned: s.isPinned)
        }

        if let data = AppDefaults.shared.data(forKey: "pasteVaultQuickSnippets"),
           var saved = try? JSONDecoder().decode([QuickSnippetItem].self, from: data) {
            var changed = false
            for i in 0..<saved.count {
                if saved[i].content.range(of: "{{clipboard}}", options: .caseInsensitive) != nil {
                    let regex = try? NSRegularExpression(pattern: "\\{\\{clipboard\\}\\}", options: .caseInsensitive)
                    let range = NSRange(location: 0, length: (saved[i].content as NSString).length)
                    saved[i].content = regex?.stringByReplacingMatches(
                        in: saved[i].content,
                        options: [],
                        range: range,
                        withTemplate: NSRegularExpression.escapedTemplate(for: sampleReplacement)
                    ) ?? saved[i].content.replacingOccurrences(of: "{{clipboard}}", with: sampleReplacement, options: .caseInsensitive)
                    changed = true
                }
            }
            if changed, let encoded = try? JSONEncoder().encode(saved) {
                AppDefaults.shared.set(encoded, forKey: "pasteVaultQuickSnippets")
            }
        }

        AppDefaults.shared.set(true, forKey: key)
    }

    /// Нормализует имена всех категорий (максимум 2 слова и 20 символов)
    public func normalizeExistingCategoriesIfNeeded() {
        let key = "pv_normalize_categories_two_words_v1"
        guard !AppDefaults.shared.bool(forKey: key) else { return }
        if db == nil { try? initializeDatabase() }
        let existing = fetchSnippetCategories()
        for cat in existing {
            let normalized = sanitizeCategoryNameInput(cat.name).trimmingCharacters(in: .whitespacesAndNewlines)
            if normalized != cat.name && !normalized.isEmpty {
                try? updateSnippetCategory(id: cat.id, newName: normalized, newIconName: cat.iconName)
            }
        }
        AppDefaults.shared.set(true, forKey: key)
    }

    /// Сохранение изображения фрагмента в Application Support/PasteVault/Images/
    nonisolated public static func saveSnippetImage(_ image: NSImage) -> String? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }
        let fm = FileManager.default
        guard let pasteVaultDir = try? Self.pasteVaultSupportDirectory() else {
            return nil
        }
        let imagesDir = pasteVaultDir.appendingPathComponent("Images")
        if !fm.fileExists(atPath: imagesDir.path) {
            try? fm.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        }
        let filename = "snippet_img_\(UUID().uuidString).png"
        let fileURL = imagesDir.appendingPathComponent(filename)
        do {
            try pngData.write(to: fileURL)
            return fileURL.path
        } catch {
            return nil
        }
    }

    public func saveSnippetImage(_ image: NSImage) -> String? {
        Self.saveSnippetImage(image)
    }

    /// Очистка устаревших тестовых категорий ("New", "__TestCategory_Temp__") и раздутых фрагментов (> 100 000 символов)
    public func cleanupLegacyDataIfNeeded() {
        if db == nil { try? initializeDatabase() }

        // 1. Однократная очистка категорий "New" и "__TestCategory_Temp__"
        let cleanupFlagKey = "didCleanupLegacyNewTestCategory_v1"
        if !AppDefaults.shared.bool(forKey: cleanupFlagKey) {
            _ = try? executeRaw("UPDATE snippets SET category = 'Работа' WHERE category = 'New' OR category = '__TestCategory_Temp__' OR category = '__TestCategory_Temp_' OR category = '__TestCategoryTemp__';")
            _ = try? executeRaw("DELETE FROM snippet_categories WHERE name = 'New' OR name = '__TestCategory_Temp__' OR name = '__TestCategory_Temp_' OR name = '__TestCategoryTemp__';")
            AppDefaults.shared.set(true, forKey: cleanupFlagKey)
        }

        // 1b. Однократная очистка синтетических тестовых записей буфера обмена (остались от автотестов)
        let clipboardCleanupKey = "didCleanupSyntheticClipboardItems_v2"
        if !AppDefaults.shared.bool(forKey: clipboardCleanupKey) {
            _ = try? executeRaw("INSERT INTO clipboard_fts(clipboard_fts) VALUES('rebuild');")
            _ = try? executeRaw("DELETE FROM clipboard_items WHERE source_bundle_id = 'com.pastevault.app.tests';")
            _ = try? executeRaw("DELETE FROM clipboard_items WHERE text_preview IN ('[Файл: Архитектура_Безопасности.pdf]', '[File: Security_Architecture.pdf]') AND source_app_name = 'Finder' AND is_pinned = 0 AND file_path IS NULL AND source_bundle_id IS NULL;")
            _ = try? executeRaw("DELETE FROM clipboard_items WHERE text_preview IN ('sk-live-independent-timer-second-22222222', 'VaultPass2026!#99', 'NEW_COMPLETELY_DIFFERENT_TEXT_999', '[Скриншот 320×180 пкс] #OCR', '[Скриншот 160×90 px • Annotated] #OCR', '[Скриншот 160×90 пкс] #OCR');")
            AppDefaults.shared.set(true, forKey: clipboardCleanupKey)
        }

        // 2. Удаление случайно раздувшихся во время прошлых тестов карточек (> 100 000 символов)
        _ = try? executeRaw("DELETE FROM snippets WHERE length(content) > 100000;")

        // 3. Синхронизируем UserDefaults
        if let data = AppDefaults.shared.data(forKey: "pasteVaultQuickSnippets"),
           var saved = try? JSONDecoder().decode([QuickSnippetItem].self, from: data) {
            var changed = false
            let countBefore = saved.count
            saved.removeAll { $0.content.count > 100_000 }
            if saved.count != countBefore { changed = true }
            for i in 0..<saved.count {
                if saved[i].category == "New" || saved[i].category == "__TestCategory_Temp__" || saved[i].category == "__TestCategory_Temp_" || saved[i].category == "__TestCategoryTemp__" {
                    saved[i].category = "Работа"
                    changed = true
                }
            }
            if changed, let encoded = try? JSONEncoder().encode(saved) {
                AppDefaults.shared.set(encoded, forKey: "pasteVaultQuickSnippets")
            }
        }
    }
}

