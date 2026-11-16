import XCTest
import Foundation
import AppKit
import SwiftUI
import CryptoKit
@testable import PasteVault

final class BackupManagerTests: XCTestCase {

    // MARK: - 1. Полный цикл сериализации и десериализации архива
    func testArchiveSerializationAndDeserialization() throws {
        let testClipboardItem = BackupClipboardItem(
            id: "clip-001",
            contentType: ContentKind.text.rawValue,
            textPreview: "Secret token: 12345",
            contentHash: "hash-001",
            sourceBundleId: "com.apple.Terminal",
            sourceAppName: "Terminal",
            isSensitive: true,
            secretKind: "API Key",
            isPinned: true,
            createdAt: 1730000000,
            expiresAt: 1730003600,
            ocrText: nil,
            fileURLPath: nil,
            useCount: 3,
            imagePNGDataBase64: nil
        )

        let testSnippet = QuickSnippetItem(
            id: "snip-001",
            title: "Команда сборки",
            content: "swift build -c release",
            category: "Dev",
            shortcutHint: "⌥B",
            isPinned: true
        )

        let testAppearance = BackupAppearanceAndStorage(
            selectedThemeId: "frost",
            userGlassLevel: 0.85,
            selectedFontId: "jetbrainsMono",
            appLanguage: "ru",
            historyLimit: 500,
            saveFiles: true,
            saveImages: false,
            saveText: true
        )

        let testSettings = BackupSettingsPayload(
            blacklistedBundleIDs: ["com.apple.keychainaccess", "com.1password.1password"],
            shortcutsData: Data([0x01, 0x02, 0x03]),
            appearanceAndStorage: testAppearance
        )

        let archive = PasteVaultBackupArchive(
            version: 1,
            createdAt: Date(),
            appVersion: "1.0.0",
            clipboardItems: [testClipboardItem],
            snippets: [testSnippet],
            settings: testSettings
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let encodedData = try encoder.encode(archive)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(PasteVaultBackupArchive.self, from: encodedData)

        XCTAssertEqual(decoded.version, 1)
        XCTAssertEqual(decoded.appVersion, "1.0.0")
        XCTAssertEqual(decoded.clipboardItems?.count, 1)

        let restoredClip = try XCTUnwrap(decoded.clipboardItems?.first)
        XCTAssertEqual(restoredClip.id, "clip-001")
        XCTAssertEqual(restoredClip.textPreview, "Secret token: 12345")
        XCTAssertEqual(restoredClip.contentHash, "hash-001")
        XCTAssertTrue(restoredClip.isSensitive)
        XCTAssertEqual(restoredClip.secretKind, "API Key")
        XCTAssertTrue(restoredClip.isPinned)
        XCTAssertEqual(restoredClip.useCount, 3)

        let restoredSnippet = try XCTUnwrap(decoded.snippets?.first)
        XCTAssertEqual(restoredSnippet.id, "snip-001")
        XCTAssertEqual(restoredSnippet.title, "Команда сборки")
        XCTAssertEqual(restoredSnippet.content, "swift build -c release")
        XCTAssertEqual(restoredSnippet.shortcutHint, "⌥B")
        XCTAssertTrue(restoredSnippet.isPinned)

        let restoredSettings = try XCTUnwrap(decoded.settings)
        XCTAssertEqual(restoredSettings.blacklistedBundleIDs, ["com.apple.keychainaccess", "com.1password.1password"])
        XCTAssertEqual(restoredSettings.shortcutsData, Data([0x01, 0x02, 0x03]))

        let restoredAppearance = try XCTUnwrap(restoredSettings.appearanceAndStorage)
        XCTAssertEqual(restoredAppearance.selectedThemeId, "frost")
        XCTAssertEqual(restoredAppearance.userGlassLevel, 0.85)
        XCTAssertEqual(restoredAppearance.selectedFontId, "jetbrainsMono")
        XCTAssertEqual(restoredAppearance.appLanguage, "ru")
        XCTAssertEqual(restoredAppearance.historyLimit, 500)
        XCTAssertEqual(restoredAppearance.saveFiles, true)
        XCTAssertEqual(restoredAppearance.saveImages, false)
        XCTAssertEqual(restoredAppearance.saveText, true)
    }

    // MARK: - 2. Экспорт только закрепленных записей буфера и фрагментов
    @MainActor
    func testExportPinnedOnlyFiltering() {
        let monitor = ClipboardMonitor.shared

        let row1 = ClipboardItemRow(
            id: "1", rowid: 1, contentType: .text, textPreview: "Item 1", contentHash: "h1",
            sourceBundleId: nil, sourceAppName: nil, isSensitive: false, secretKind: nil,
            isPinned: true, createdAt: 100, expiresAt: nil, ocrText: nil, rawImageData: nil, fileURLPath: nil, useCount: 0
        )
        let row2 = ClipboardItemRow(
            id: "2", rowid: 2, contentType: .text, textPreview: "Item 2", contentHash: "h2",
            sourceBundleId: nil, sourceAppName: nil, isSensitive: false, secretKind: nil,
            isPinned: false, createdAt: 200, expiresAt: nil, ocrText: nil, rawImageData: nil, fileURLPath: nil, useCount: 0
        )
        let row3 = ClipboardItemRow(
            id: "3", rowid: 3, contentType: .text, textPreview: "Item 3", contentHash: "h3",
            sourceBundleId: nil, sourceAppName: nil, isSensitive: false, secretKind: nil,
            isPinned: true, createdAt: 300, expiresAt: nil, ocrText: nil, rawImageData: nil, fileURLPath: nil, useCount: 0
        )

        let snippets = [
            QuickSnippetItem(id: "s1", title: "Snip 1", content: "C1", category: "General", isPinned: false),
            QuickSnippetItem(id: "s2", title: "Snip 2", content: "C2", category: "General", isPinned: true),
            QuickSnippetItem(id: "s3", title: "Snip 3", content: "C3", category: "General", isPinned: false)
        ]

        let archive = BackupManager.buildArchive(
            items: [row1, row2, row3],
            monitor: monitor,
            snippets: snippets,
            includeClipboard: true,
            clipboardPinnedOnly: true,
            includeSnippets: true,
            snippetsPinnedOnly: true,
            includeBlacklist: false,
            includeShortcuts: false,
            includeAppearance: false
        )

        // Проверяем фильтрацию буфера обмена
        let clips = archive.clipboardItems ?? []
        XCTAssertEqual(clips.count, 2, "Должны быть экспортированы только закреплённые записи буфера")
        XCTAssertTrue(clips.allSatisfy { $0.isPinned })
        XCTAssertEqual(clips.map(\.id), ["1", "3"])

        // Проверяем фильтрацию фрагментов
        let snips = archive.snippets ?? []
        XCTAssertEqual(snips.count, 1, "Должны быть экспортированы только закреплённые фрагменты")
        XCTAssertTrue(snips.first?.isPinned == true)
        XCTAssertEqual(snips.first?.id, "s2")

        // Проверяем, что настройки исключены
        XCTAssertNil(archive.settings)
    }

    // MARK: - 3. Режим объединения (Merge) без дубликатов с сохранением закреплений
    @MainActor
    func testRestoreSnippetsMergeMode() async throws {
        let currentSnippets = [
            QuickSnippetItem(id: "s1", title: "Приветствие", content: "Привет!", category: "Chat", isPinned: false),
            QuickSnippetItem(id: "s2", title: "Подпись", content: "С уважением", category: "Mail", isPinned: false)
        ]

        let backupSnippets = [
            QuickSnippetItem(id: "s1", title: "Приветствие", content: "Привет!", category: "Chat", isPinned: true), // Закрепленный в бэкапе
            QuickSnippetItem(id: "s3", title: "Код", content: "print(42)", category: "Dev", isPinned: false)
        ]

        let archive = PasteVaultBackupArchive(
            version: 1,
            createdAt: Date(),
            appVersion: "1.0.0",
            clipboardItems: nil,
            snippets: backupSnippets,
            settings: nil
        )

        var restoredResult: [QuickSnippetItem] = []
        try await BackupManager.restoreArchive(
            archive,
            restoreClipboard: false,
            restoreSnippets: true,
            restoreSettings: false,
            mergeMode: true,
            monitor: ClipboardMonitor.shared,
            currentSnippets: currentSnippets,
            onUpdateSnippets: { updated in
                restoredResult = updated
            }
        )

        XCTAssertEqual(restoredResult.count, 3, "В режиме объединения должно быть 3 уникальных фрагмента")
        let s1 = try XCTUnwrap(restoredResult.first(where: { $0.id == "s1" }))
        XCTAssertTrue(s1.isPinned, "Фрагмент s1 должен обновиться до isPinned == true из бэкапа")
        XCTAssertTrue(restoredResult.contains(where: { $0.id == "s2" }))
        XCTAssertTrue(restoredResult.contains(where: { $0.id == "s3" }))
    }

    // MARK: - 4. Режим полной замены (Replace All)
    @MainActor
    func testRestoreSnippetsReplaceMode() async throws {
        let currentSnippets = [
            QuickSnippetItem(id: "s1", title: "Старый 1", content: "C1", category: "Old", isPinned: true),
            QuickSnippetItem(id: "s2", title: "Старый 2", content: "C2", category: "Old", isPinned: false)
        ]

        let backupSnippets = [
            QuickSnippetItem(id: "new-1", title: "Новый 1", content: "N1", category: "__TestCategory_Temp__", isPinned: true)
        ]

        let archive = PasteVaultBackupArchive(
            version: 1,
            createdAt: Date(),
            appVersion: "1.0.0",
            clipboardItems: nil,
            snippets: backupSnippets,
            settings: nil
        )

        var restoredResult: [QuickSnippetItem] = []
        try await BackupManager.restoreArchive(
            archive,
            restoreClipboard: false,
            restoreSnippets: true,
            restoreSettings: false,
            mergeMode: false,
            monitor: ClipboardMonitor.shared,
            currentSnippets: currentSnippets,
            onUpdateSnippets: { updated in
                restoredResult = updated
            }
        )

        XCTAssertEqual(restoredResult.count, 1, "В режиме полной замены должен остаться ровно 1 фрагмент из бэкапа")
        XCTAssertEqual(restoredResult.first?.id, "new-1")
    }

    // MARK: - 5. Запись и чтение файла архива через файловую систему
    func testExportAndLoadArchiveFileCycle() throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_backup_\(UUID().uuidString).json")
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        let originalArchive = PasteVaultBackupArchive(
            version: 1,
            createdAt: Date(),
            appVersion: "1.0.0",
            clipboardItems: [
                BackupClipboardItem(
                    id: "file-test-clip",
                    contentType: 0,
                    textPreview: "Тест экспорта в файл",
                    contentHash: "hash-file-1",
                    sourceBundleId: nil,
                    sourceAppName: nil,
                    isSensitive: false,
                    secretKind: nil,
                    isPinned: true,
                    createdAt: 1730001000,
                    expiresAt: nil,
                    ocrText: nil,
                    fileURLPath: nil,
                    useCount: 1
                )
            ],
            snippets: [
                QuickSnippetItem(id: "file-test-snip", title: "Тест", content: "Контент", category: "File", isPinned: true)
            ],
            settings: BackupSettingsPayload(blacklistedBundleIDs: ["com.apple.finder"])
        )

        try BackupManager.exportArchiveToFile(archive: originalArchive, to: tempURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempURL.path), "Файл бэкапа должен успешно создаться на диске")

        let loadedArchive = try BackupManager.loadArchiveFromFile(from: tempURL)
        XCTAssertEqual(loadedArchive.version, 1)
        XCTAssertEqual(loadedArchive.clipboardItems?.count, 1)
        XCTAssertEqual(loadedArchive.clipboardItems?.first?.id, "file-test-clip")
        XCTAssertEqual(loadedArchive.clipboardItems?.first?.isPinned, true)
        XCTAssertEqual(loadedArchive.snippets?.count, 1)
        XCTAssertEqual(loadedArchive.snippets?.first?.id, "file-test-snip")
        XCTAssertEqual(loadedArchive.snippets?.first?.isPinned, true)
        XCTAssertEqual(loadedArchive.settings?.blacklistedBundleIDs, ["com.apple.finder"])
    }

    // MARK: - 6. Парольное шифрование PVENC2 (PBKDF2 + AES-GCM) и синхронизация фрагментов в SQLite
    @MainActor
    func testEncryptedArchiveAndSQLiteSnippetPersistence() async throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_enc_backup_\(UUID().uuidString).pvault")
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        let secretText = "SuperSecretPassword_XYZ_98765"
        let snippetId = "__test_restore_sqlite_\(UUID().uuidString)"
        let password = "StrongBackupPass!2026"
        let archive = PasteVaultBackupArchive(
            version: 2,
            createdAt: Date(),
            appVersion: "1.0.1",
            clipboardItems: [
                BackupClipboardItem(
                    id: "enc-clip-1",
                    contentType: 4,
                    textPreview: secretText,
                    contentHash: "hash-enc-1",
                    sourceBundleId: nil,
                    sourceAppName: "PassGen",
                    isSensitive: true,
                    secretKind: "Пароль",
                    isPinned: false,
                    createdAt: 1730002000,
                    expiresAt: nil,
                    ocrText: nil,
                    fileURLPath: nil,
                    useCount: 0
                )
            ],
            snippets: [
                QuickSnippetItem(id: snippetId, title: "Восстановленный SQLite", content: "Тест", category: "Работа", isPinned: true)
            ],
            settings: nil
        )

        try BackupManager.exportArchiveToFile(archive: archive, to: tempURL, password: password)
        let rawBytes = try Data(contentsOf: tempURL)
        XCTAssertTrue(rawBytes.starts(with: Data("PVENC2:".utf8)), "Парольный бэкап должен иметь заголовок PVENC2:")
        XCTAssertTrue(BackupManager.fileRequiresPassword(at: tempURL))
        XCTAssertNil(rawBytes.range(of: Data(secretText.utf8)), "Секреты не должны храниться в файле бэкапа в открытом виде")

        XCTAssertThrowsError(try BackupManager.loadArchiveFromFile(from: tempURL, password: nil)) { error in
            guard case BackupManager.BackupArchiveError.passwordRequired = error else {
                XCTFail("Ожидалась ошибка .passwordRequired, получено: \(error)")
                return
            }
        }
        XCTAssertThrowsError(try BackupManager.loadArchiveFromFile(from: tempURL, password: "WrongPassword")) { error in
            guard case BackupManager.BackupArchiveError.incorrectPasswordOrCorrupted = error else {
                XCTFail("Ожидалась ошибка .incorrectPasswordOrCorrupted, получено: \(error)")
                return
            }
        }

        let decoded = try BackupManager.loadArchiveFromFile(from: tempURL, password: password)
        XCTAssertEqual(decoded.clipboardItems?.first?.textPreview, secretText)

        let existingSnippets = await DatabaseManager.shared.fetchSnippets()
        try await BackupManager.restoreArchive(
            decoded,
            restoreClipboard: false,
            restoreSnippets: true,
            restoreSettings: false,
            mergeMode: true,
            monitor: ClipboardMonitor.shared,
            currentSnippets: existingSnippets,
            onUpdateSnippets: { _ in }
        )

        let dbSnippets = await DatabaseManager.shared.fetchSnippets()
        XCTAssertTrue(dbSnippets.contains(where: { $0.id == snippetId }), "Восстановленный фрагмент должен быть сохранён в SQLite")
        try? await DatabaseManager.shared.deleteSnippet(idString: snippetId)
    }

    // MARK: - 7. Экспорт без пароля (открытый JSON v2) и обратная совместимость с PVENC1 + v1 JSON
    func testPasswordlessExportAndLegacyV1Compatibility() throws {
        let tempPlainURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_plain_v2_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempPlainURL) }

        let archiveV2 = PasteVaultBackupArchive(
            version: 2,
            createdAt: Date(timeIntervalSince1970: 1730005000),
            appVersion: "1.0.1",
            clipboardItems: [
                BackupClipboardItem(
                    id: "plain-clip-1",
                    contentType: 0,
                    textPreview: "Plaintext item without password",
                    contentHash: "hash-plain-1",
                    sourceBundleId: nil,
                    sourceAppName: nil,
                    isSensitive: false,
                    secretKind: nil,
                    isPinned: false,
                    createdAt: 1730005000,
                    expiresAt: nil,
                    ocrText: nil,
                    fileURLPath: nil,
                    useCount: 1
                )
            ],
            snippets: nil,
            settings: nil
        )

        try BackupManager.exportArchiveToFile(archive: archiveV2, to: tempPlainURL, password: "")
        let plainBytes = try Data(contentsOf: tempPlainURL)
        XCTAssertFalse(plainBytes.starts(with: Data("PVENC2:".utf8)))
        XCTAssertFalse(BackupManager.fileRequiresPassword(at: tempPlainURL))
        let plainLoaded = try BackupManager.loadArchiveFromFile(from: tempPlainURL)
        XCTAssertEqual(plainLoaded.clipboardItems?.first?.id, "plain-clip-1")

        // Обратная совместимость: устаревший PVENC1: + числовые timestamp v1
        let legacyEncoder = JSONEncoder()
        legacyEncoder.dateEncodingStrategy = .secondsSince1970
        let numericJSON = try legacyEncoder.encode(archiveV2)
        let numericDecoded = try BackupManager.decodeArchiveData(numericJSON)
        XCTAssertEqual(Int(numericDecoded.createdAt.timeIntervalSince1970), 1730005000)

        let legacyMaterial = Data("com.pastevault.app.backup.aesgcm.v1".utf8)
        let legacyKey = SymmetricKey(data: SHA256.hash(data: legacyMaterial))
        let legacySealed = try AES.GCM.seal(numericJSON, using: legacyKey)
        let legacyCombined = try XCTUnwrap(legacySealed.combined)
        var pvenc1Data = Data("PVENC1:".utf8)
        pvenc1Data.append(legacyCombined.base64EncodedData())

        let decodedPVENC1 = try BackupManager.decodeArchiveData(pvenc1Data)
        XCTAssertEqual(decodedPVENC1.clipboardItems?.first?.id, "plain-clip-1")
    }

    // MARK: - 8. Санитизация path traversal в именах файлов и синхронная очистка при Replace
    @MainActor
    func testReplaceModeCleanupAndTraversalSanitization() async throws {
        try await DatabaseManager.shared.initializeDatabase()
        try await DatabaseManager.shared.restoreItem(
            id: "old-item-before-replace",
            contentType: .text,
            textPreview: "Old text to be replaced",
            contentHash: "hash-old-replace",
            sourceBundleId: nil,
            sourceAppName: nil,
            isSensitive: false,
            secretKind: nil,
            isPinned: false,
            createdAt: 1730000100,
            expiresAt: nil,
            fileURLPath: nil,
            useCount: 0
        )

        let maliciousId = "../../evil_backup_escape"
        let tinyPNG = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=")!
        let archive = PasteVaultBackupArchive(
            version: 2,
            createdAt: Date(),
            appVersion: "1.0.1",
            clipboardItems: [
                BackupClipboardItem(
                    id: maliciousId,
                    contentType: ContentKind.image.rawValue,
                    textPreview: "[Screenshot]",
                    contentHash: "hash-safe-sanitized",
                    sourceBundleId: nil,
                    sourceAppName: nil,
                    isSensitive: false,
                    secretKind: nil,
                    isPinned: false,
                    createdAt: 1730000200,
                    expiresAt: nil,
                    ocrText: nil,
                    fileURLPath: "/tmp/../../../etc/passwd",
                    useCount: 0,
                    imagePNGDataBase64: tinyPNG.base64EncodedString()
                )
            ],
            snippets: nil,
            settings: nil
        )

        try await BackupManager.restoreArchive(
            archive,
            restoreClipboard: true,
            restoreSnippets: false,
            restoreSettings: false,
            mergeMode: false,
            monitor: ClipboardMonitor.shared,
            currentSnippets: [],
            onUpdateSnippets: { _ in }
        )

        let items = try await DatabaseManager.shared.queryItems(searchQuery: "", limit: 50)
        XCTAssertFalse(items.contains(where: { $0.id == "old-item-before-replace" }), "В режиме полной замены старая запись должна быть удалена")
        XCTAssertEqual(items.count, 1)
        let restored = try XCTUnwrap(items.first)
        XCTAssertFalse(restored.id.contains(".."))
        XCTAssertFalse(restored.id.contains("/"))
        let screenshotsDir = try DatabaseManager.pasteVaultSupportDirectory().appendingPathComponent("Screenshots").path
        if let path = restored.fileURLPath {
            XCTAssertTrue(path.hasPrefix(screenshotsDir), "Восстановленный скриншот не должен покидать каталог Screenshots")
        }

        try? await DatabaseManager.shared.clearAllHistory()
        ClipboardMonitor.shared.clearAllHistoryInMemory()
    }

    // MARK: - 10. Итерация 30.37: Защита клавиш в NSSavePanel / NSTextView, глазик пароля и декодер импорта PVENC2
    @MainActor
    func testFloatingPanelKeyEventInterceptionAllowsFilePanelsAndTextEditing() {
        let panel = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let otherWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 220),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 30))

        // 1) События чужого окна (NSSavePanel / NSOpenPanel / стороннее окно) не перехватываются
        XCTAssertFalse(
            FloatingPanel<EmptyView>.shouldInterceptKeyEvent(
                eventWindow: otherWindow,
                panel: panel,
                isShowingFilePanel: false,
                hasModalWindow: false,
                hasAttachedSheet: false,
                firstResponder: nil,
                keyCode: 51,
                modifierFlags: []
            )
        )

        // 2) Активный файловый диалог / модальное окно / sheet полностью отключают перехват
        XCTAssertFalse(
            FloatingPanel<EmptyView>.shouldInterceptKeyEvent(
                eventWindow: panel,
                panel: panel,
                isShowingFilePanel: true,
                hasModalWindow: false,
                hasAttachedSheet: false,
                firstResponder: nil,
                keyCode: 51,
                modifierFlags: []
            )
        )
        XCTAssertFalse(
            FloatingPanel<EmptyView>.shouldInterceptKeyEvent(
                eventWindow: panel,
                panel: panel,
                isShowingFilePanel: false,
                hasModalWindow: true,
                hasAttachedSheet: false,
                firstResponder: nil,
                keyCode: 51,
                modifierFlags: []
            )
        )
        XCTAssertFalse(
            FloatingPanel<EmptyView>.shouldInterceptKeyEvent(
                eventWindow: panel,
                panel: panel,
                isShowingFilePanel: false,
                hasModalWindow: false,
                hasAttachedSheet: true,
                firstResponder: nil,
                keyCode: 51,
                modifierFlags: []
            )
        )

        // 3) Внутри NSTextView не перехватываются Backspace (51), Delete (117), стрелки (123..126) и Cmd+A/C/V/X/Z
        let editingKeyCodes: [UInt16] = [51, 117, 123, 124, 125, 126]
        for code in editingKeyCodes {
            XCTAssertFalse(
                FloatingPanel<EmptyView>.shouldInterceptKeyEvent(
                    eventWindow: panel,
                    panel: panel,
                    isShowingFilePanel: false,
                    hasModalWindow: false,
                    hasAttachedSheet: false,
                    firstResponder: textView,
                    keyCode: code,
                    modifierFlags: []
                ),
                "KeyCode \(code) не должен перехватываться в NSTextView"
            )
        }
        let commandEditCodes: [UInt16] = [0, 8, 9, 7, 6]
        for code in commandEditCodes {
            XCTAssertFalse(
                FloatingPanel<EmptyView>.shouldInterceptKeyEvent(
                    eventWindow: panel,
                    panel: panel,
                    isShowingFilePanel: false,
                    hasModalWindow: false,
                    hasAttachedSheet: false,
                    firstResponder: textView,
                    keyCode: code,
                    modifierFlags: .command
                ),
                "Cmd + keyCode \(code) не должен перехватываться в NSTextView"
            )
        }

        // 4) Обычное нажатие в самой панели без диалогов и текстового поля перехватывается штатно
        XCTAssertTrue(
            FloatingPanel<EmptyView>.shouldInterceptKeyEvent(
                eventWindow: panel,
                panel: panel,
                isShowingFilePanel: false,
                hasModalWindow: false,
                hasAttachedSheet: false,
                firstResponder: nil,
                keyCode: 53,
                modifierFlags: []
            )
        )
    }

    @MainActor
    func testBackupPasswordAccessoryControllerToggleAndWidth() {
        let controller = BackupPasswordAccessoryController(
            title: "Пароль шифрования (необязательно):",
            placeholder: "Оставьте пустым для открытого JSON",
            warning: "Без пароля бэкап сохранится в открытом виде (небезопасно)."
        )

        XCTAssertGreaterThanOrEqual(controller.container.frame.width, 380)
        XCTAssertTrue(controller.eyeButton.target === controller)
        XCTAssertEqual(controller.eyeButton.action, #selector(BackupPasswordAccessoryController.togglePasswordVisibility))
        XCTAssertFalse(controller.isPasswordVisible)
        XCTAssertFalse(controller.secureField.isHidden)
        XCTAssertTrue(controller.plainField.isHidden)

        controller.setPasswordText("My$ecret123")
        XCTAssertEqual(controller.currentPassword, "My$ecret123")

        controller.togglePasswordVisibility()
        XCTAssertTrue(controller.isPasswordVisible)
        XCTAssertTrue(controller.secureField.isHidden)
        XCTAssertFalse(controller.plainField.isHidden)
        XCTAssertEqual(controller.plainField.stringValue, "My$ecret123")
        XCTAssertEqual(controller.currentPassword, "My$ecret123")

        controller.plainField.stringValue = "EditedPwd!"
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: controller.plainField))
        XCTAssertEqual(controller.secureField.stringValue, "EditedPwd!")
        XCTAssertEqual(controller.currentPassword, "EditedPwd!")

        controller.togglePasswordVisibility()
        XCTAssertFalse(controller.isPasswordVisible)
        XCTAssertFalse(controller.secureField.isHidden)
        XCTAssertTrue(controller.plainField.isHidden)
        XCTAssertEqual(controller.currentPassword, "EditedPwd!")
    }

    @MainActor
    func testImportPasswordDecryptionHelperForWrongAndCorrectPassword() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PasteVault_ImportTest_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let archive = PasteVaultBackupArchive(
            version: 2,
            createdAt: Date(),
            appVersion: "1.0.2",
            clipboardItems: [
                BackupClipboardItem(
                    id: "import-enc-1",
                    contentType: ContentKind.text.rawValue,
                    textPreview: "Encrypted backup check",
                    contentHash: "hash-enc-1",
                    sourceBundleId: nil,
                    sourceAppName: nil,
                    isSensitive: false,
                    secretKind: nil,
                    isPinned: true,
                    createdAt: 1730000300,
                    expiresAt: nil,
                    ocrText: nil,
                    fileURLPath: nil,
                    useCount: 1,
                    imagePNGDataBase64: nil
                )
            ],
            snippets: nil,
            settings: nil
        )

        try BackupManager.exportArchiveToFile(archive: archive, to: tempURL, password: "RightPass#2026")
        XCTAssertTrue(BackupManager.fileRequiresPassword(at: tempURL))

        let wrongResult = MainPanelView.decryptBackupArchiveForImport(from: tempURL, password: "WrongPassword")
        if case .success = wrongResult {
            XCTFail("Неверный пароль не должен успешно расшифровывать PVENC2-файл")
        }

        let correctResult = MainPanelView.decryptBackupArchiveForImport(from: tempURL, password: "RightPass#2026")
        switch correctResult {
        case .success(let decoded):
            XCTAssertEqual(decoded.clipboardItems?.count, 1)
            XCTAssertEqual(decoded.clipboardItems?.first?.textPreview, "Encrypted backup check")
        case .failure(let error):
            XCTFail("Правильный пароль должен расшифровывать архив: \(error)")
        }
    }

    // MARK: - 11. Диагностика: Экспорт и Импорт (Merge/Replace) 2 категорий фрагментов (вкл. пустую и переименованную)
    @MainActor
    func testDiagnosticCategoryBackupExportImportMergeAndReplace() async throws {
        let monitor = ClipboardMonitor.shared
        let tempDir = FileManager.default.temporaryDirectory
        let encURL1 = tempDir.appendingPathComponent("diag_cats_both_\(UUID().uuidString).json")
        let encURL2 = tempDir.appendingPathComponent("diag_cats_one_empty_\(UUID().uuidString).json")
        let encURL3 = tempDir.appendingPathComponent("diag_cats_renamed_\(UUID().uuidString).json")
        defer {
            try? FileManager.default.removeItem(at: encURL1)
            try? FileManager.default.removeItem(at: encURL2)
            try? FileManager.default.removeItem(at: encURL3)
        }

        let cleanDBAndSeedDefaults: () async -> Void = {
            await DatabaseManager.shared.deleteAllSnippets()
            let allCats = await DatabaseManager.shared.fetchSnippetCategories()
            for cat in allCats {
                _ = try? await DatabaseManager.shared.deleteSnippetCategoryAndSnippets(id: cat.id)
            }
            await DatabaseManager.shared.resetSnippetCategoriesSeededFlagForTesting()
        }

        let deleteAllCategories: () async -> Void = {
            await DatabaseManager.shared.deleteAllSnippets()
            let allCats = await DatabaseManager.shared.fetchSnippetCategories()
            for cat in allCats {
                _ = try? await DatabaseManager.shared.deleteSnippetCategoryAndSnippets(id: cat.id)
            }
        }

        let password = "DiagCatsPass!2026"

        // --- Сценарий А: 2 пользовательские категории, обе с фрагментами ---
        await deleteAllCategories()
        let catA1 = await DatabaseManager.shared.createSnippetCategory(name: "Альфа Коды", iconName: "chevron.left.forwardslash.chevron.right")
        let catA2 = await DatabaseManager.shared.createSnippetCategory(name: "Бета Промпты", iconName: "sparkles")
        XCTAssertNotNil(catA1)
        XCTAssertNotNil(catA2)

        let snipA1 = QuickSnippetItem(id: "diag-a1", title: "Сниппет 1", content: "echo 1", category: "Альфа Коды", isPinned: false)
        let snipA2 = QuickSnippetItem(id: "diag-a2", title: "Сниппет 2", content: "Prompt 2", category: "Бета Промпты", isPinned: true)
        _ = await DatabaseManager.shared.insertSnippet(id: snipA1.id, title: snipA1.title, content: snipA1.content, category: snipA1.category, isPinned: snipA1.isPinned)
        _ = await DatabaseManager.shared.insertSnippet(id: snipA2.id, title: snipA2.title, content: snipA2.content, category: snipA2.category, isPinned: snipA2.isPinned)

        let exportedCatsA = await DatabaseManager.shared.fetchSnippetCategories()
        let exportedSnipsA = await DatabaseManager.shared.fetchSnippets()
        XCTAssertEqual(exportedCatsA.count, 2)

        let archiveA = BackupManager.buildArchive(
            items: [],
            monitor: monitor,
            snippets: exportedSnipsA,
            snippetCategories: exportedCatsA,
            includeClipboard: false,
            clipboardPinnedOnly: false,
            includeSnippets: true,
            snippetsPinnedOnly: false,
            includeBlacklist: false,
            includeShortcuts: false,
            includeAppearance: false
        )
        XCTAssertEqual(archiveA.snippetCategories?.count, 2)
        try BackupManager.exportArchiveToFile(archive: archiveA, to: encURL1, password: password)

        // Сброс в чистую базу (симулируем чистый старт с 4 дефолтными категориями) -> Replace
        await cleanDBAndSeedDefaults()
        let decodedA = try BackupManager.loadArchiveFromFile(from: encURL1, password: password)
        var uiSnippetsA: [QuickSnippetItem] = []
        try await BackupManager.restoreArchive(
            decodedA,
            restoreClipboard: false,
            restoreSnippets: true,
            restoreSettings: false,
            mergeMode: false,
            monitor: monitor,
            currentSnippets: [],
            onUpdateSnippets: { uiSnippetsA = $0 }
        )
        let catsAfterAReplace = await DatabaseManager.shared.fetchSnippetCategories()
        XCTAssertEqual(catsAfterAReplace.count, 2, "Сценарий А (Replace): в БД должно быть ровно 2 категории")
        XCTAssertEqual(Set(catsAfterAReplace.map(\.name)), ["Альфа Коды", "Бета Промпты"])
        XCTAssertEqual(uiSnippetsA.count, 2)

        // Проверка повторного сидинга (имитация перезапуска)
        await DatabaseManager.shared.seedDefaultSnippetCategoriesIfNeeded()
        let catsAfterARestart = await DatabaseManager.shared.fetchSnippetCategories()
        XCTAssertEqual(catsAfterARestart.count, 2, "После перезапуска 4 базовые категории не должны пересидиться")

        // Сброс в чистую базу -> Merge
        await cleanDBAndSeedDefaults()
        try await BackupManager.restoreArchive(
            decodedA,
            restoreClipboard: false,
            restoreSnippets: true,
            restoreSettings: false,
            mergeMode: true,
            monitor: monitor,
            currentSnippets: [],
            onUpdateSnippets: { uiSnippetsA = $0 }
        )
        let catsAfterAMerge = await DatabaseManager.shared.fetchSnippetCategories()
        XCTAssertEqual(catsAfterAMerge.count, 6, "Сценарий А (Merge поверх чистой БД с 4 дефолтными): ожидается 4 + 2 = 6 категорий")

        // --- Сценарий Б: 2 категории, 1-я с фрагментом, 2-я пустая (0 фрагментов) ---
        await deleteAllCategories()
        _ = await DatabaseManager.shared.createSnippetCategory(name: "С Фрагментом", iconName: "folder.fill")
        _ = await DatabaseManager.shared.createSnippetCategory(name: "Пустая Категория", iconName: "tray.fill")
        _ = await DatabaseManager.shared.insertSnippet(id: "diag-b1", title: "Единственный", content: "Body", category: "С Фрагментом", isPinned: false)

        let exportedCatsB = await DatabaseManager.shared.fetchSnippetCategories()
        let exportedSnipsB = await DatabaseManager.shared.fetchSnippets()
        XCTAssertEqual(exportedCatsB.count, 2)

        let archiveB = BackupManager.buildArchive(
            items: [],
            monitor: monitor,
            snippets: exportedSnipsB,
            snippetCategories: exportedCatsB,
            includeClipboard: false,
            clipboardPinnedOnly: false,
            includeSnippets: true,
            snippetsPinnedOnly: false,
            includeBlacklist: false,
            includeShortcuts: false,
            includeAppearance: false
        )
        XCTAssertEqual(archiveB.snippetCategories?.count, 2, "buildArchive обязан сохранить и пустую категорию тоже")
        try BackupManager.exportArchiveToFile(archive: archiveB, to: encURL2, password: password)

        // Чистая база -> Replace
        await cleanDBAndSeedDefaults()
        let decodedB = try BackupManager.loadArchiveFromFile(from: encURL2, password: password)
        var uiSnippetsB: [QuickSnippetItem] = []
        try await BackupManager.restoreArchive(
            decodedB,
            restoreClipboard: false,
            restoreSnippets: true,
            restoreSettings: false,
            mergeMode: false,
            monitor: monitor,
            currentSnippets: [],
            onUpdateSnippets: { uiSnippetsB = $0 }
        )
        let catsAfterBReplace = await DatabaseManager.shared.fetchSnippetCategories()
        XCTAssertEqual(catsAfterBReplace.count, 2, "Сценарий Б (Replace): пустая категория должна сохраниться")
        XCTAssertEqual(Set(catsAfterBReplace.map(\.name)), ["С Фрагментом", "Пустая Категория"])
        XCTAssertEqual(uiSnippetsB.count, 1)

        // Чистая база -> Merge
        await cleanDBAndSeedDefaults()
        try await BackupManager.restoreArchive(
            decodedB,
            restoreClipboard: false,
            restoreSnippets: true,
            restoreSettings: false,
            mergeMode: true,
            monitor: monitor,
            currentSnippets: [],
            onUpdateSnippets: { uiSnippetsB = $0 }
        )
        let catsAfterBMerge = await DatabaseManager.shared.fetchSnippetCategories()
        XCTAssertEqual(catsAfterBMerge.count, 6, "Сценарий Б (Merge): 4 дефолтные + 2 из архива (вкл. пустую) = 6")

        // --- Сценарий В: Стандартная переименованная категория + удаление остальных дефолтных ---
        await cleanDBAndSeedDefaults() // старт с 4 дефолтными
        let initialDefaults = await DatabaseManager.shared.fetchSnippetCategories()
        XCTAssertEqual(initialDefaults.count, 4)
        // Оставляем «Работа», переименовываем «Разработка» -> «Мои Скрипты», удаляем «Шаблоны» и «Промпты»
        if let devCat = initialDefaults.first(where: { $0.name == "Разработка" }) {
            try await DatabaseManager.shared.updateSnippetCategory(id: devCat.id, newName: "Мои Скрипты", newIconName: "terminal.fill")
        }
        for cat in initialDefaults where cat.name == "Шаблоны" || cat.name == "Промпты" {
            try await DatabaseManager.shared.deleteSnippetCategoryAndSnippets(id: cat.id)
        }
        _ = await DatabaseManager.shared.insertSnippet(id: "diag-v1", title: "Скрипт", content: "ls -la", category: "Мои Скрипты", isPinned: false)

        let exportedCatsV = await DatabaseManager.shared.fetchSnippetCategories()
        let exportedSnipsV = await DatabaseManager.shared.fetchSnippets()
        XCTAssertEqual(exportedCatsV.count, 2)
        let archiveV = BackupManager.buildArchive(
            items: [],
            monitor: monitor,
            snippets: exportedSnipsV,
            snippetCategories: exportedCatsV,
            includeClipboard: false,
            clipboardPinnedOnly: false,
            includeSnippets: true,
            snippetsPinnedOnly: false,
            includeBlacklist: false,
            includeShortcuts: false,
            includeAppearance: false
        )
        try BackupManager.exportArchiveToFile(archive: archiveV, to: encURL3, password: password)

        // Чистая база -> Replace
        await cleanDBAndSeedDefaults()
        let decodedV = try BackupManager.loadArchiveFromFile(from: encURL3, password: password)
        var uiSnippetsV: [QuickSnippetItem] = []
        try await BackupManager.restoreArchive(
            decodedV,
            restoreClipboard: false,
            restoreSnippets: true,
            restoreSettings: false,
            mergeMode: false,
            monitor: monitor,
            currentSnippets: [],
            onUpdateSnippets: { uiSnippetsV = $0 }
        )
        let catsAfterVReplace = await DatabaseManager.shared.fetchSnippetCategories()
        XCTAssertEqual(catsAfterVReplace.count, 2, "Сценарий В (Replace): ровно 2 категории без удалённых дефолтных")
        XCTAssertEqual(Set(catsAfterVReplace.map(\.name)), ["Работа", "Мои Скрипты"])
        XCTAssertEqual(uiSnippetsV.count, 1)

        // Чистая база -> Merge (в UI выбран по умолчанию!)
        await cleanDBAndSeedDefaults()
        try await BackupManager.restoreArchive(
            decodedV,
            restoreClipboard: false,
            restoreSnippets: true,
            restoreSettings: false,
            mergeMode: true,
            monitor: monitor,
            currentSnippets: [],
            onUpdateSnippets: { uiSnippetsV = $0 }
        )
        let catsAfterVMerge = await DatabaseManager.shared.fetchSnippetCategories()
        XCTAssertEqual(catsAfterVMerge.count, 5, "Сценарий В (Merge): 4 дефолтные + «Мои Скрипты» (Работа совпала) = 5 категорий")
        XCTAssertEqual(uiSnippetsV.count, 1)

        // Финальная уборка тестовой БД
        await cleanDBAndSeedDefaults()
    }

    // MARK: - 12. Полный round-trip всех настроек + обратная совместимость со старым JSON
    @MainActor
    func testFullSettingsRoundTripAndLegacyCompatibility() async throws {
        try await DatabaseManager.shared.initializeDatabase()
        let monitor = ClipboardMonitor.shared
        let defaults = AppDefaults.shared

        // Сохраняем текущее состояние и восстанавливаем в defer
        let prevTheme = defaults.string(forKey: "selectedThemeId")
        let prevLegacyTheme = defaults.string(forKey: "pasteVaultTheme")
        let prevFont = defaults.string(forKey: "selectedFontId")
        let prevGlass = defaults.object(forKey: "userGlassLevel")
        let prevLang = defaults.string(forKey: "appLanguage")
        let prevSound = defaults.object(forKey: "tapticAudioFeedbackEnabled")
        let prevAutoUpdates = defaults.object(forKey: "autoCheckUpdates")
        let prevServiceAutoUpdates = UpdateService.shared.autoCheckUpdates
        let prevLaunchAtLogin = monitor.isLaunchAtLoginEnabled

        defer {
            if let prevTheme { defaults.set(prevTheme, forKey: "selectedThemeId") } else { defaults.removeObject(forKey: "selectedThemeId") }
            if let prevLegacyTheme { defaults.set(prevLegacyTheme, forKey: "pasteVaultTheme") } else { defaults.removeObject(forKey: "pasteVaultTheme") }
            if let prevFont { defaults.set(prevFont, forKey: "selectedFontId") } else { defaults.removeObject(forKey: "selectedFontId") }
            if let prevGlass { defaults.set(prevGlass, forKey: "userGlassLevel") } else { defaults.removeObject(forKey: "userGlassLevel") }
            if let prevLang { defaults.set(prevLang, forKey: "appLanguage") } else { defaults.removeObject(forKey: "appLanguage") }
            if let prevSound { defaults.set(prevSound, forKey: "tapticAudioFeedbackEnabled") } else { defaults.removeObject(forKey: "tapticAudioFeedbackEnabled") }
            if let prevAutoUpdates { defaults.set(prevAutoUpdates, forKey: "autoCheckUpdates") } else { defaults.removeObject(forKey: "autoCheckUpdates") }
            UpdateService.shared.autoCheckUpdates = prevServiceAutoUpdates
            monitor.isLaunchAtLoginEnabled = prevLaunchAtLogin
        }

        // 1. Проверяем, что при отсутствии userGlassLevel экспорт сохраняет 0.70, а не 0.0
        defaults.removeObject(forKey: "userGlassLevel")
        let defaultArchive = BackupManager.buildArchive(
            items: [],
            monitor: monitor,
            snippets: [],
            includeClipboard: false,
            clipboardPinnedOnly: false,
            includeSnippets: false,
            snippetsPinnedOnly: false,
            includeBlacklist: false,
            includeShortcuts: false,
            includeAppearance: true
        )
        XCTAssertEqual(defaultArchive.settings?.appearanceAndStorage?.userGlassLevel ?? -1, 0.70, accuracy: 0.001)

        // 2. Выставляем все настройки, экспортируем -> сбрасываем -> импортируем
        defaults.set("catppuccinMocha", forKey: "selectedThemeId")
        defaults.set("catppuccinMocha", forKey: "pasteVaultTheme")
        defaults.set("jura", forKey: "selectedFontId")
        defaults.set(0.42, forKey: "userGlassLevel")
        defaults.set("en", forKey: "appLanguage")
        defaults.set(false, forKey: "tapticAudioFeedbackEnabled")
        defaults.set(true, forKey: "autoCheckUpdates")
        UpdateService.shared.autoCheckUpdates = true
        monitor.isLaunchAtLoginEnabled = true

        let archive = BackupManager.buildArchive(
            items: [],
            monitor: monitor,
            snippets: [],
            includeClipboard: false,
            clipboardPinnedOnly: false,
            includeSnippets: false,
            snippetsPinnedOnly: false,
            includeBlacklist: true,
            includeShortcuts: true,
            includeAppearance: true
        )

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("full_settings_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        try BackupManager.exportArchiveToFile(archive: archive, to: tempURL, password: "TestSettingsPwd#1")

        // Сбрасываем локальные настройки на противоположные
        defaults.set("obsidian", forKey: "selectedThemeId")
        defaults.set("obsidian", forKey: "pasteVaultTheme")
        defaults.set("inter", forKey: "selectedFontId")
        defaults.set(0.95, forKey: "userGlassLevel")
        defaults.set("ru", forKey: "appLanguage")
        defaults.set(true, forKey: "tapticAudioFeedbackEnabled")
        defaults.set(false, forKey: "autoCheckUpdates")
        UpdateService.shared.autoCheckUpdates = false
        monitor.isLaunchAtLoginEnabled = false

        let loaded = try BackupManager.loadArchiveFromFile(from: tempURL, password: "TestSettingsPwd#1")
        try await BackupManager.restoreArchive(
            loaded,
            restoreClipboard: false,
            restoreSnippets: false,
            restoreSettings: true,
            mergeMode: false,
            monitor: monitor,
            currentSnippets: [],
            onUpdateSnippets: { _ in }
        )

        XCTAssertEqual(defaults.string(forKey: "selectedThemeId"), "catppuccinMocha")
        XCTAssertEqual(defaults.string(forKey: "pasteVaultTheme"), "catppuccinMocha")
        XCTAssertEqual(defaults.string(forKey: "selectedFontId"), "jura")
        XCTAssertEqual(defaults.double(forKey: "userGlassLevel"), 0.42, accuracy: 0.001)
        XCTAssertEqual(defaults.string(forKey: "appLanguage"), "en")
        XCTAssertEqual(defaults.bool(forKey: "tapticAudioFeedbackEnabled"), false)
        XCTAssertEqual(defaults.bool(forKey: "autoCheckUpdates"), true)
        XCTAssertTrue(UpdateService.shared.autoCheckUpdates)
        XCTAssertTrue(monitor.isLaunchAtLoginEnabled)

        // 3. Обратная совместимость со старым JSON (без soundEnabled, autoCheckUpdates, launchAtLogin)
        let legacyJSON = """
        {
          "version": 1,
          "appVersion": "1.0.1",
          "settings": {
            "appearanceAndStorage": {
              "selectedThemeId": "frost",
              "userGlassLevel": 0.65,
              "selectedFontId": "manrope",
              "appLanguage": "ru",
              "historyLimit": 250,
              "saveFiles": true,
              "saveImages": true,
              "saveText": true
            }
          }
        }
        """
        let legacyArchive = try BackupManager.decodeArchiveData(Data(legacyJSON.utf8))
        let legacyAppearance = try XCTUnwrap(legacyArchive.settings?.appearanceAndStorage)
        XCTAssertEqual(legacyAppearance.selectedThemeId, "frost")
        XCTAssertEqual(legacyAppearance.selectedFontId, "manrope")
        XCTAssertNil(legacyAppearance.soundEnabled)
        XCTAssertNil(legacyAppearance.autoCheckUpdates)
        XCTAssertNil(legacyAppearance.launchAtLogin)
    }
}
