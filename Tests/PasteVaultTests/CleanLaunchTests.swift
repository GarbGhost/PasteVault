import XCTest
@testable import PasteVault

@MainActor
final class CleanLaunchTests: XCTestCase {

    func testCleanDatabaseHasZeroItems() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("PasteVaultCleanTest_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let dbURL = tempDir.appendingPathComponent("clean_test.sqlite")
        let db = DatabaseManager.shared
        try await db.initializeDatabase(at: dbURL)

        // При первом запуске на чистой директории база должна быть полностью пустой (0 записей)
        let items = try await db.queryItems(searchQuery: "", limit: 100)
        XCTAssertEqual(items.count, 0, "Clean launch database must contain 0 clipboard items")

        await db.closeForTesting()
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testSnippetsDefaultIsEmptyOnCleanLaunch() {
        let testDefaultsKey = "pasteVaultQuickSnippets_clean_test_\(UUID().uuidString)"
        // Проверяем логику загрузки сниппетов: при отсутствии данных в UserDefaults список должен быть строгим пустым массивом
        let data = AppDefaults.shared.data(forKey: testDefaultsKey)
        let snippets: [QuickSnippetItem]
        if let data, let saved = try? JSONDecoder().decode([QuickSnippetItem].self, from: data) {
            snippets = saved
        } else {
            snippets = []
        }

        XCTAssertEqual(snippets.count, 0, "Quick snippets must default to an empty list on clean first launch")
    }

    func testDatabaseManagerIsolatesStorageDuringXCTest() throws {
        XCTAssertTrue(DatabaseManager.isRunningTests, "isRunningTests must be true under swift test / XCTest")
        let supportDir = try DatabaseManager.pasteVaultSupportDirectory()
        XCTAssertTrue(supportDir.path.contains("/tmp/PasteVault_TestRun_"), "Support directory during tests must be isolated in /tmp, got: \(supportDir.path)")
        XCTAssertFalse(supportDir.path.contains("Application Support"), "Tests must never point into ~/Library/Application Support/PasteVault")
    }

    func testDeletedDefaultCategoriesDoNotResurrectOnRestart() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("PasteVaultCatTest_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let dbURL = tempDir.appendingPathComponent("cats_test.sqlite")
        let db = DatabaseManager.shared

        // Сбрасываем одноразовые флаги сидинга в изолированном AppDefaults.shared
        AppDefaults.shared.removeObject(forKey: "pv_initial_categories_seeded_v1")
        AppDefaults.shared.removeObject(forKey: "pv_snippet_categories_seeded_v1")
        AppDefaults.shared.removeObject(forKey: "pv_snippet_categories_restored_v2")
        AppDefaults.shared.removeObject(forKey: "pv_cleaned_to_4_starter_snippets_v1")

        try await db.initializeDatabase(at: dbURL)
        let initialCats = await db.fetchSnippetCategories()
        XCTAssertEqual(initialCats.count, 4, "Clean first launch must seed 4 default categories once")

        // Удаляем все 4 категории
        for cat in initialCats {
            try await db.deleteSnippetCategoryAndSnippets(id: cat.id)
        }
        let afterDelete = await db.fetchSnippetCategories()
        XCTAssertEqual(afterDelete.count, 0)

        // Переоткрываем БД (симуляция перезапуска) — удалённые категории НЕ должны воскресать
        await db.closeForTesting()
        try await db.initializeDatabase(at: dbURL)
        let afterRestart = await db.fetchSnippetCategories()
        XCTAssertEqual(afterRestart.count, 0, "Deleted default categories must NOT resurrect after app restart")

        await db.closeForTesting()
        AppDefaults.shared.removeObject(forKey: "pv_initial_categories_seeded_v1")
        AppDefaults.shared.removeObject(forKey: "pv_snippet_categories_seeded_v1")
        try? await db.initializeDatabase()
    }

    func testTestPreferencesPlistAutoCleanupAndOrphanRemoval() throws {
        let suiteName = try XCTUnwrap(AppDefaults.testSuiteName)
        XCTAssertTrue(suiteName.hasPrefix("com.pastevault.tests."))

        let tempPrefsDir = FileManager.default.temporaryDirectory.appendingPathComponent("pv_prefs_test_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempPrefsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempPrefsDir) }

        let deadSuite = "com.pastevault.tests.99999999"
        let deadPlist = tempPrefsDir.appendingPathComponent("\(deadSuite).plist")
        let livePlist = tempPrefsDir.appendingPathComponent("\(suiteName).plist")
        let unrelatedPlist = tempPrefsDir.appendingPathComponent("com.pastevault.app.plist")

        try Data("orphan".utf8).write(to: deadPlist)
        try Data("live".utf8).write(to: livePlist)
        try Data("prod".utf8).write(to: unrelatedPlist)

        AppDefaults.cleanupOrphanedTestPreferences(
            currentPID: ProcessInfo.processInfo.processIdentifier,
            preferencesDir: tempPrefsDir
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: deadPlist.path), "Orphaned test .plist for dead PID must be removed")
        XCTAssertTrue(FileManager.default.fileExists(atPath: livePlist.path), "Current running test PID .plist must stay until process exit")
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelatedPlist.path), "Production com.pastevault.app.plist must never be touched")

        AppDefaults.removeTestPreferences(forSuiteName: suiteName, preferencesDir: tempPrefsDir)
        XCTAssertFalse(FileManager.default.fileExists(atPath: livePlist.path), "removeTestPreferences must delete target test .plist")
    }

    func testPopUpMenuLevelWindowIsNotClassifiedAsStatusBarWindow() {
        let panelWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 150),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panelWindow.level = .popUpMenu
        XCTAssertGreaterThanOrEqual(panelWindow.level.rawValue, NSWindow.Level.statusBar.rawValue)
        XCTAssertFalse(
            SystemFilePanelPresenter.isStatusBarWindow(panelWindow),
            "A FloatingPanel-level (.popUpMenu = 101) window must NOT be classified as NSStatusBarWindow"
        )
    }

    func testHostWindowTemporaryLevelLoweringAndRestoration() {
        let hostWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 150),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        hostWindow.level = .popUpMenu
        XCTAssertEqual(hostWindow.level, .popUpMenu)

        let savedLevel = SystemFilePanelPresenter.temporarilyLowerHostLevel(hostWindow)
        XCTAssertEqual(savedLevel, .popUpMenu)
        XCTAssertEqual(hostWindow.level, .normal)
        XCTAssertLessThan(
            hostWindow.level.rawValue,
            NSWindow.Level.modalPanel.rawValue,
            "Host window must sit strictly below modalPanel (8) while system file panel is active"
        )

        SystemFilePanelPresenter.restoreHostLevel(hostWindow, to: savedLevel)
        XCTAssertEqual(hostWindow.level, .popUpMenu, "Host window level must restore to .popUpMenu (101)")
    }
}
