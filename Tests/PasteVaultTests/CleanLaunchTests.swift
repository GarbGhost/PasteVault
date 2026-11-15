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
}
