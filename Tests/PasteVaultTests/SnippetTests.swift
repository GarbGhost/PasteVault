import XCTest
import SwiftUI
@testable import PasteVault

final class SnippetTests: XCTestCase {

    // MARK: - 1. Обратная совместимость декодирования (без isPinned)
    func testLegacyQuickSnippetItemDecodingWithoutIsPinned() throws {
        let legacyJSON = """
        {
            "id": "legacy-snippet-001",
            "title": "Приветствие техподдержки",
            "content": "Здравствуйте! Чем могу помочь?",
            "category": "Поддержка",
            "shortcutHint": null
        }
        """

        let data = try XCTUnwrap(legacyJSON.data(using: .utf8))
        let decoded = try JSONDecoder().decode(QuickSnippetItem.self, from: data)

        XCTAssertEqual(decoded.id, "legacy-snippet-001")
        XCTAssertEqual(decoded.title, "Приветствие техподдержки")
        XCTAssertEqual(decoded.content, "Здравствуйте! Чем могу помочь?")
        XCTAssertEqual(decoded.category, "Поддержка")
        XCTAssertNil(decoded.shortcutHint)
        // Гарантируем, что старые записи в UserDefaults получают isPinned = false
        XCTAssertFalse(decoded.isPinned, "Старый фрагмент без поля isPinned должен гарантированно декодироваться как false")

        // Проверяем сохранение нового формата с isPinned = true
        var pinnedSnippet = decoded
        pinnedSnippet.isPinned = true
        let encodedData = try JSONEncoder().encode(pinnedSnippet)
        let reDecoded = try JSONDecoder().decode(QuickSnippetItem.self, from: encodedData)
        XCTAssertTrue(reDecoded.isPinned, "Новый фрагмент должен корректно сериализоваться и десериализоваться с isPinned = true")
    }

    // MARK: - 2. Очистка только незакреплённых фрагментов
    func testPreservePinnedSnippetsWhenClearingUnpinned() {
        var snippets: [QuickSnippetItem] = [
            QuickSnippetItem(id: "1", title: "Закрепленный 1", content: "Content 1", category: "Dev", isPinned: true),
            QuickSnippetItem(id: "2", title: "Обычный 1", content: "Content 2", category: "Work", isPinned: false),
            QuickSnippetItem(id: "3", title: "Закрепленный 2", content: "Content 3", category: "Templates", isPinned: true),
            QuickSnippetItem(id: "4", title: "Обычный 2", content: "Content 4", category: "Dev", isPinned: false),
            QuickSnippetItem(id: "5", title: "Обычный 3", content: "Content 5", category: "Work", isPinned: false)
        ]

        XCTAssertEqual(snippets.count, 5)
        let unpinnedCount = snippets.filter { !$0.isPinned }.count
        XCTAssertEqual(unpinnedCount, 3)

        // Имитируем нажатие «Удалить» в диалоге очистки
        snippets.removeAll { !$0.isPinned }

        XCTAssertEqual(snippets.count, 2, "Должны остаться ровно 2 закреплённых фрагмента")
        XCTAssertTrue(snippets.allSatisfy { $0.isPinned }, "Все оставшиеся фрагменты должны быть закреплёнными")
        XCTAssertEqual(snippets.map(\.id), ["1", "3"])
    }

    // MARK: - 3. Приоритетная сортировка поиска (title выше content) и статус pin
    func testPrioritySearchSortTitleOverContent() {
        let snippetA = QuickSnippetItem(
            id: "a",
            title: "Команды терминала Git",
            content: "status, commit, push",
            category: "Dev",
            isPinned: false
        )
        let snippetB = QuickSnippetItem(
            id: "b",
            title: "Памятка разработчика",
            content: "Для проверки состояния репозитория используйте git status в терминале",
            category: "Work",
            isPinned: false
        )

        // Поиск по слову "git"
        let matched = [snippetB, snippetA] // Специфично подаем в обратном порядке
        let sorted = SearchHighlightHelper.sortSnippets(matched, query: "git", scope: .all)

        XCTAssertEqual(sorted.count, 2)
        XCTAssertEqual(sorted.first?.id, "a", "Фрагмент с совпадением в названии (title) должен идти ПЕРВЫМ")
        XCTAssertEqual(sorted.last?.id, "b", "Фрагмент с совпадением только в тексте (content) должен идти ВТОРЫМ")

        // Проверяем, что закрепленный фрагмент ВСЕГДА выше, даже если у незакрепленного совпадение в title
        var pinnedB = snippetB
        pinnedB.isPinned = true
        let sortedWithPin = SearchHighlightHelper.sortSnippets([snippetA, pinnedB], query: "git", scope: .all)
        XCTAssertEqual(sortedWithPin.first?.id, "b", "Закрепленный фрагмент обязан быть на самом верху списка даже при приоритете title у незакрепленного")
    }

    // MARK: - 4. Подсветка поисковых совпадений в AttributedString
    func testSearchHighlightHelperAttributedString() {
        let text = "PasteVault is a native macOS clipboard manager with zero network telemetry."
        let query = "pastevault"

        let attributed = SearchHighlightHelper.highlight(
            text: text,
            query: query,
            baseColor: .primary,
            accentColor: .blue,
            isLight: true,
            bold: true
        )

        // Текст должен сохраниться неизменным посимвольно
        XCTAssertEqual(String(attributed.characters), text)

        // Проверяем, что первое слово "PasteVault" подсвечено фоном
        let firstWordRange = attributed.range(of: "PasteVault", options: .caseInsensitive)
        XCTAssertNotNil(firstWordRange)
        if let range = firstWordRange {
            let bg = attributed[range].backgroundColor
            XCTAssertNotNil(bg, "Совпадение должно иметь установленный цвет фона")
        }

        // Пустой запрос не должен ломать строку
        let emptyQueryAttributed = SearchHighlightHelper.highlight(text: text, query: "")
        XCTAssertEqual(String(emptyQueryAttributed.characters), text)
    }

    // MARK: - 5. Одиночное удаление закрепленного фрагмента vs массовая очистка
    func testPinnedSnippetSingleDeleteVsBulkClear() {
        var snippets: [QuickSnippetItem] = [
            QuickSnippetItem(id: "pin-1", title: "Закрепленный 1", content: "Пин текст 1", category: "Dev", isPinned: true),
            QuickSnippetItem(id: "norm-1", title: "Обычный 1", content: "Обычный текст 1", category: "Work", isPinned: false),
            QuickSnippetItem(id: "pin-2", title: "Закрепленный 2", content: "Пин текст 2", category: "Templates", isPinned: true)
        ]

        // 1. Одиночное удаление закрепленного элемента по ID должно работать беспрепятственно
        let targetId = "pin-1"
        snippets.removeAll { $0.id == targetId }
        XCTAssertEqual(snippets.count, 2)
        XCTAssertFalse(snippets.contains { $0.id == "pin-1" }, "Закрепленный фрагмент pin-1 должен быть успешно удален при одиночном удалении")
        XCTAssertTrue(snippets.contains { $0.id == "pin-2" })

        // 2. Массовая очистка истории удаляет только незакрепленные элементы
        snippets.removeAll { !$0.isPinned }
        XCTAssertEqual(snippets.count, 1)
        XCTAssertEqual(snippets.first?.id, "pin-2", "При массовой очистке закрепленный фрагмент pin-2 должен остаться нетронутым")
    }
}
