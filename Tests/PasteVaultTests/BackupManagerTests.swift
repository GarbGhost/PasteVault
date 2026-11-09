import XCTest
import Foundation
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
            QuickSnippetItem(id: "new-1", title: "Новый 1", content: "N1", category: "New", isPinned: true)
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
}
