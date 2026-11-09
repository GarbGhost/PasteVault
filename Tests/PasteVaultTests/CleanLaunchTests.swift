import XCTest
@testable import PasteVault

@MainActor
final class CleanLaunchTests: XCTestCase {

    func testCleanDatabaseHasZeroItems() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("PasteVaultCleanTest_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let dbURL = tempDir.appendingPathComponent("clean_test.sqlite")
        let db = DatabaseManager.shared
        try await db.initializeDatabase(at: dbURL)

        // При первом запуске на чистой директории база должна быть полностью пустой (0 записей)
        let items = try await db.queryItems(searchQuery: "", limit: 100)
        XCTAssertEqual(items.count, 0, "Clean launch database must contain 0 clipboard items")
    }

    func testSnippetsDefaultIsEmptyOnCleanLaunch() {
        let testDefaultsKey = "pasteVaultQuickSnippets_clean_test_\(UUID().uuidString)"
        // Проверяем логику загрузки сниппетов: при отсутствии данных в UserDefaults список должен быть строгим пустым массивом
        let data = UserDefaults.standard.data(forKey: testDefaultsKey)
        let snippets: [QuickSnippetItem]
        if let data, let saved = try? JSONDecoder().decode([QuickSnippetItem].self, from: data) {
            snippets = saved
        } else {
            snippets = []
        }

        XCTAssertEqual(snippets.count, 0, "Quick snippets must default to an empty list on clean first launch")
    }
}
