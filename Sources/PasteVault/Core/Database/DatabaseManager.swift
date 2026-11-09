import Foundation
import SQLite3
import CryptoKit

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
    public let ocrText: String?
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
        useCount: Int = 0
    ) {
        let isDemoted = ClipboardMonitor.manuallyDemotedTextIds.contains(id)
        let isPromoted = ClipboardMonitor.manuallyPromotedSecretIds.contains(id)

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
            effectiveSecretKind = secretKind ?? "Пароль"
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
            self.displayPreviewText = String(textPreview.prefix(300)).replacingOccurrences(of: "\n", with: " ")
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

    public func initializeDatabase(at customURL: URL? = nil) throws {
        if db != nil { return }

        let dbURL: URL
        if let customURL {
            dbURL = customURL
        } else {
            let appSupport = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appendingPathComponent("PasteVault", isDirectory: true)

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
            dbURL = appSupport.appendingPathComponent("pastevault_v2.sqlite")
        }
        self.databaseFileURL = dbURL

        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(dbURL.path, &db, flags, nil) == SQLITE_OK else {
            return
        }

        try executeRaw("""
            PRAGMA journal_mode = WAL;
            PRAGMA synchronous = NORMAL;
            PRAGMA foreign_keys = ON;
            PRAGMA temp_store = MEMORY;
        """)

        try migrateSchema()
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
            expires_at INTEGER
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
        """
        try executeRaw(schemaSQL)
        _ = try? executeRaw("ALTER TABLE clipboard_items ADD COLUMN use_count INTEGER NOT NULL DEFAULT 0;")
        _ = try? executeRaw("ALTER TABLE clipboard_items ADD COLUMN file_path TEXT;")
    }

    public func incrementUseCount(id: String) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "UPDATE clipboard_items SET use_count = use_count + 1 WHERE id = ?1;", -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
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
        fileURLPath: String? = nil
    ) throws -> String {
        if db == nil {
            try? initializeDatabase()
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
            is_pinned, created_at, expires_at, file_path
        ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, 0, ?9, ?10, ?11)
        ON CONFLICT(content_hash) DO UPDATE SET
            id = excluded.id,
            created_at = excluded.created_at,
            expires_at = excluded.expires_at,
            source_bundle_id = COALESCE(excluded.source_bundle_id, clipboard_items.source_bundle_id),
            source_app_name = COALESCE(excluded.source_app_name, clipboard_items.source_app_name),
            file_path = COALESCE(excluded.file_path, clipboard_items.file_path);
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, upsertSQL, -1, &stmt, nil) == SQLITE_OK else { return itemId }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, itemId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 2, contentType.rawValue)
        sqlite3_bind_text(stmt, 3, String(textPreview.prefix(16384)), -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 4, contentHash, -1, SQLITE_TRANSIENT)
        bindOpt(stmt, 5, sourceBundleId)
        bindOpt(stmt, 6, sourceAppName)
        sqlite3_bind_int(stmt, 7, isSensitive ? 1 : 0)
        bindOpt(stmt, 8, secretKind)
        sqlite3_bind_int64(stmt, 9, now)
        if let expiresAt { sqlite3_bind_int64(stmt, 10, expiresAt) } else { sqlite3_bind_null(stmt, 10) }
        bindOpt(stmt, 11, fileURLPath)

        _ = sqlite3_step(stmt)
        return itemId
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
        useCount: Int = 0
    ) throws {
        if db == nil {
            try? initializeDatabase()
        }

        let sql = """
        INSERT INTO clipboard_items (
            id, content_type, text_preview, content_hash,
            source_bundle_id, source_app_name, is_sensitive, secret_kind,
            is_pinned, created_at, expires_at, file_path, use_count
        ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13)
        ON CONFLICT(content_hash) DO UPDATE SET
            is_pinned = CASE WHEN excluded.is_pinned = 1 THEN 1 ELSE clipboard_items.is_pinned END,
            source_bundle_id = COALESCE(excluded.source_bundle_id, clipboard_items.source_bundle_id),
            source_app_name = COALESCE(excluded.source_app_name, clipboard_items.source_app_name),
            file_path = COALESCE(excluded.file_path, clipboard_items.file_path);
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 2, contentType.rawValue)
        sqlite3_bind_text(stmt, 3, String(textPreview.prefix(16384)), -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 4, contentHash, -1, SQLITE_TRANSIENT)
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
               is_pinned, created_at, expires_at, use_count, file_path
        FROM clipboard_items
        WHERE expires_at IS NULL OR expires_at > ?1
        ORDER BY is_pinned DESC, created_at DESC
        LIMIT ?2;
        """ : """
        SELECT rowid, id, content_type, text_preview, content_hash,
               source_bundle_id, source_app_name, is_sensitive, secret_kind,
               is_pinned, created_at, expires_at, use_count, file_path
        FROM clipboard_items
        WHERE (expires_at IS NULL OR expires_at > ?1)
          AND (text_preview LIKE ?3 OR COALESCE(source_app_name, '') LIKE ?3)
        ORDER BY is_pinned DESC, created_at DESC
        LIMIT ?2;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, now)
        sqlite3_bind_int(stmt, 2, limit)
        if !trimmed.isEmpty {
            let likePattern = "%\(trimmed)%"
            sqlite3_bind_text(stmt, 3, likePattern, -1, SQLITE_TRANSIENT)
        }

        var results: [ClipboardItemRow] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let row = ClipboardItemRow(
                id: String(cString: sqlite3_column_text(stmt, 1)),
                rowid: sqlite3_column_int64(stmt, 0),
                contentType: ContentKind(rawValue: sqlite3_column_int(stmt, 2)) ?? .text,
                textPreview: String(cString: sqlite3_column_text(stmt, 3)),
                contentHash: String(cString: sqlite3_column_text(stmt, 4)),
                sourceBundleId: sqlite3_column_text(stmt, 5).map { String(cString: $0) },
                sourceAppName: sqlite3_column_text(stmt, 6).map { String(cString: $0) },
                isSensitive: sqlite3_column_int(stmt, 7) != 0,
                secretKind: sqlite3_column_text(stmt, 8).map { String(cString: $0) },
                isPinned: sqlite3_column_int(stmt, 9) != 0,
                createdAt: sqlite3_column_int64(stmt, 10),
                expiresAt: sqlite3_column_type(stmt, 11) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(stmt, 11))),
                ocrText: nil,
                rawImageData: nil,
                fileURLPath: sqlite3_column_type(stmt, 13) == SQLITE_NULL ? nil : sqlite3_column_text(stmt, 13).map { String(cString: $0) },
                useCount: Int(sqlite3_column_int(stmt, 12))
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
        sqlite3_bind_text(stmt, 2, id, -1, SQLITE_TRANSIENT)
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
        sqlite3_bind_text(stmt, 5, id, -1, SQLITE_TRANSIENT)
        _ = sqlite3_step(stmt)
    }

    public func togglePin(id: String) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "UPDATE clipboard_items SET is_pinned = CASE WHEN is_pinned = 1 THEN 0 ELSE 1 END WHERE id = ?1;", -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
        _ = sqlite3_step(stmt)
    }

    public func updateItemText(id: String, newText: String, newHash: String, contentType: ContentKind? = nil) throws {
        var stmt: OpaquePointer?
        if let contentType {
            guard sqlite3_prepare_v2(db, "UPDATE clipboard_items SET text_preview = ?1, content_hash = ?2, content_type = ?3 WHERE id = ?4;", -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, newText, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, newHash, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(stmt, 3, contentType.rawValue)
            sqlite3_bind_text(stmt, 4, id, -1, SQLITE_TRANSIENT)
            _ = sqlite3_step(stmt)
        } else {
            guard sqlite3_prepare_v2(db, "UPDATE clipboard_items SET text_preview = ?1, content_hash = ?2 WHERE id = ?3;", -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, newText, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, newHash, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, id, -1, SQLITE_TRANSIENT)
            _ = sqlite3_step(stmt)
        }
    }

    public func deleteItem(id: String) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "DELETE FROM clipboard_items WHERE id = ?1;", -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
        _ = sqlite3_step(stmt)
    }

    public func clearAllHistory() throws {
        try executeRaw("DELETE FROM clipboard_items;")
        _ = try? executeRaw("DELETE FROM clipboard_fts;")
        _ = try? executeRaw("VACUUM;")
    }

    public func clearUnpinnedHistory() throws {
        try executeRaw("DELETE FROM clipboard_items WHERE is_pinned = 0;")
        _ = try? executeRaw("DELETE FROM clipboard_fts WHERE id NOT IN (SELECT id FROM clipboard_items);")
    }

    private func executeRaw(_ sql: String) throws {
        var errMsg: UnsafeMutablePointer<CChar>?
        sqlite3_exec(db, sql, nil, nil, &errMsg)
        if let errMsg { sqlite3_free(errMsg) }
    }

    private func bindOpt(_ stmt: OpaquePointer?, _ index: Int32, _ val: String?) {
        if let val { sqlite3_bind_text(stmt, index, val, -1, SQLITE_TRANSIENT) } else { sqlite3_bind_null(stmt, index) }
    }
}

