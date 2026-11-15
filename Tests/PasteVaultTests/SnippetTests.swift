import XCTest
import SwiftUI
@testable import PasteVault

final class SnippetTests: XCTestCase {

    private var originalSnippetsData: Data? = nil

    override func setUp() async throws {
        try await super.setUp()
        originalSnippetsData = AppDefaults.shared.data(forKey: "pasteVaultQuickSnippets")
        try? await DatabaseManager.shared.initializeDatabase()
    }

    override func tearDown() async throws {
        let db = DatabaseManager.shared
        _ = try? await db.executeRaw("DELETE FROM snippet_categories WHERE name = '__TestCategoryTemp__' OR name = '__TestCategory_Temp__' OR name = '__TestCategory_Temp_' OR name = 'New';")
        _ = try? await db.executeRaw("DELETE FROM snippets WHERE category = '__TestCategoryTemp__' OR category = '__TestCategory_Temp__' OR category = '__TestCategory_Temp_' OR category = 'New';")
        await db.seedDefaultSnippetCategoriesIfNeeded()
        await db.seedStressTest100SnippetsIfNeeded()
        if let originalSnippetsData {
            AppDefaults.shared.set(originalSnippetsData, forKey: "pasteVaultQuickSnippets")
        }
        try await super.tearDown()
    }

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

    // MARK: - 6. Подсветка всех 8 динамических макросов
    func testSnippetMacroHighlightingDetectsAllEightMacros() {
        let text = "Отчёт: {{date}}, {{time}}, {{datetime}}, {{weekday}}, {{iso}}, {{app}}, {{user}}, {{uuid}}"

        // 1. Проверяем обнаружение макросов хелпером
        XCTAssertTrue(SearchHighlightHelper.containsSnippetMacro(text), "Строка должна определяться как содержащая макросы")
        XCTAssertFalse(SearchHighlightHelper.containsSnippetMacro("Обычный текст без макросов"), "Обычный текст не должен содержать макросов")

        // 2. Формируем подсветку
        let attributed = SearchHighlightHelper.highlightedSnippetText(
            text,
            query: "",
            accentColor: .blue,
            primaryColor: .primary,
            baseFontSize: 12
        )

        // Текст должен сохраниться неизменным посимвольно без потери символов
        XCTAssertEqual(String(attributed.characters), text, "Текст AttributedString должен полностью совпадать с исходным")

        // 3. Проверяем, что для всех 8 макросов применён акцентный фон и цвет
        for macro in SnippetMacroEngine.macros.map(\.tag) {
            let macroRange = attributed.range(of: macro, options: .caseInsensitive)
            XCTAssertNotNil(macroRange, "Макрос \(macro) обязан присутствовать в AttributedString")
            if let range = macroRange {
                let bg = attributed[range].backgroundColor
                let fg = attributed[range].foregroundColor
                XCTAssertNotNil(bg, "Макрос \(macro) должен иметь цвет фона")
                XCTAssertNotNil(fg, "Макрос \(macro) должен иметь цвет текста")
            }
        }
    }

    // MARK: - 7. Подсветка макросов при одновременном поисковом запросе
    func testSnippetMacroHighlightingWithSearchQuery() {
        let text = "Отчёт от {{date}} в {{time}} ({{datetime}})"
        let query = "Отчёт"

        let attributed = SearchHighlightHelper.highlightedSnippetText(
            text,
            query: query,
            accentColor: .blue,
            primaryColor: .primary,
            baseFontSize: 12
        )

        // Текст должен сохраниться неизменным посимвольно полной длины
        XCTAssertEqual(String(attributed.characters), text, "Длина и символы должны сохраняться при одновременном поиске и макросах")

        // Проверяем наличие подсветки поискового слова
        let queryRange = attributed.range(of: query, options: .caseInsensitive)
        XCTAssertNotNil(queryRange, "Слово поискового запроса обязано присутствовать")
        if let range = queryRange {
            XCTAssertNotNil(attributed[range].backgroundColor, "Поисковый запрос должен иметь цвет фона")
        }

        // И макрос {{date}} также сохраняет свои атрибуты
        let dateRange = attributed.range(of: "{{date}}", options: .caseInsensitive)
        XCTAssertNotNil(dateRange, "Макрос {{date}} обязан присутствовать параллельно с поиском")
        if let range = dateRange {
            XCTAssertNotNil(attributed[range].backgroundColor, "Макрос должен иметь подсветку параллельно с поиском")
        }
    }

    // MARK: - 8. Расшифровка готовых значений всех 8 макросов через SnippetMacroEngine
    func testExpandSnippetMacrosForDisplayReplacesAllMacrosWithLiveValues() {
        let fixedDate = Date(timeIntervalSince1970: 1794300000) // 11.11.2026 ~11:40
        let dateFmt = DateFormatter()
        dateFmt.locale = Locale(identifier: "ru_RU")
        dateFmt.dateFormat = "dd.MM.yyyy"
        let expectedDate = dateFmt.string(from: fixedDate)

        let timeFmt = DateFormatter()
        timeFmt.locale = Locale(identifier: "ru_RU")
        timeFmt.dateFormat = "HH:mm"
        let expectedTime = timeFmt.string(from: fixedDate)

        let weekdayFmt = DateFormatter()
        weekdayFmt.locale = Locale(identifier: "ru_RU")
        weekdayFmt.dateFormat = "EEEE"
        let expectedWeekday = weekdayFmt.string(from: fixedDate).lowercased()

        let isoFmt = DateFormatter()
        isoFmt.locale = Locale(identifier: "en_US_POSIX")
        isoFmt.dateFormat = "yyyy-MM-dd"
        let expectedIso = isoFmt.string(from: fixedDate)

        let rawText = "Заказ от {{date}} в {{time}} ({{datetime}}). День: {{weekday}}. ISO: {{iso}}. App: {{app}}. User: {{user}}. UUID: {{uuid}}."
        let expanded = SnippetMacroEngine.expand(
            rawText,
            targetAppName: "Safari",
            date: fixedDate,
            locale: Locale(identifier: "ru_RU")
        )

        // Сырых макросов не должно остаться
        for m in SnippetMacroEngine.macros {
            XCTAssertFalse(expanded.contains(m.tag), "Макрос \(m.tag) должен быть раскрыт")
        }

        // Должны быть подставлены значения
        XCTAssertTrue(expanded.contains(expectedDate))
        XCTAssertTrue(expanded.contains(expectedTime))
        XCTAssertTrue(expanded.contains("\(expectedDate) \(expectedTime)"))
        XCTAssertTrue(expanded.contains(expectedWeekday))
        XCTAssertTrue(expanded.contains(expectedIso))
        XCTAssertTrue(expanded.contains("Safari"))
        XCTAssertTrue(expanded.contains(NSUserName()))
    }

    func testExpandedAndHighlightedSnippetTextCleanMacroStyleWithoutAccentColor() {
        let fixedDate = Date(timeIntervalSince1970: 1794300000)
        let rawText = "Встреча: {{date}} в {{time}}"

        // 1. Без поискового запроса: подставленные значения не имеют фона и синего цвета
        let plainAttributed = SearchHighlightHelper.expandedAndHighlightedSnippetText(
            rawText,
            query: "",
            accentColor: .blue,
            primaryColor: .primary,
            baseFontSize: 12,
            language: .ru,
            date: fixedDate
        )

        let plainString = String(plainAttributed.characters)
        XCTAssertFalse(plainString.contains("{{date}}"))
        XCTAssertFalse(plainString.contains("{{time}}"))
        XCTAssertTrue(plainString.contains("Встреча:"))

        // Проверяем, что нет акцентного фона на подставленных дате и времени
        if let dateRange = plainAttributed.range(of: "11.11.2026") {
            XCTAssertNil(plainAttributed[dateRange].backgroundColor, "Подставленная дата не должна иметь акцентного фона")
        }

        // 2. С поисковым запросом: подсвечивается ТОЛЬКО поисковое совпадение
        let searchAttributed = SearchHighlightHelper.expandedAndHighlightedSnippetText(
            rawText,
            query: "Встреча",
            accentColor: .blue,
            primaryColor: .primary,
            baseFontSize: 12,
            language: .ru,
            date: fixedDate
        )

        if let queryRange = searchAttributed.range(of: "Встреча") {
            XCTAssertNotNil(searchAttributed[queryRange].backgroundColor, "Поисковый запрос должен иметь подсветку")
        }
    }

    func testDefaultCategoriesPreservedInDatabase() async throws {
        let db = DatabaseManager.shared
        await db.seedDefaultSnippetCategoriesIfNeeded()
        let categories = await db.fetchSnippetCategories()

        // Тест проверяет дефолтный набор; если пользователь удалил/изменил категории в рабочей базе — пропускаем
        // (тест не должен менять пользовательские данные).
        try XCTSkipUnless(
            Array(categories.prefix(4).map(\.name)) == ["Работа", "Разработка", "Шаблоны", "Промпты"],
            "Дефолтные категории изменены пользователем в рабочей базе"
        )

        XCTAssertGreaterThanOrEqual(categories.count, 4, "В базе должно присутствовать не менее 4 категорий")
        let names = categories.map(\.name)
        XCTAssertTrue(names.contains("Работа"))
        XCTAssertTrue(names.contains("Разработка"))
        XCTAssertTrue(names.contains("Шаблоны"))
        XCTAssertTrue(names.contains("Промпты"))

        // Проверяем точный порядок первых 4 категорий
        if categories.count >= 4 {
            XCTAssertEqual(categories[0].name, "Работа")
            XCTAssertEqual(categories[0].iconName, "briefcase.fill")
            XCTAssertEqual(categories[0].sortOrder, 0)

            XCTAssertEqual(categories[1].name, "Разработка")
            XCTAssertEqual(categories[1].iconName, "chevron.left.forwardslash.chevron.right")
            XCTAssertEqual(categories[1].sortOrder, 1)

            XCTAssertEqual(categories[2].name, "Шаблоны")
            XCTAssertEqual(categories[2].iconName, "doc.text.fill")
            XCTAssertEqual(categories[2].sortOrder, 2)

            XCTAssertEqual(categories[3].name, "Промпты")
            XCTAssertEqual(categories[3].iconName, "sparkles")
            XCTAssertEqual(categories[3].sortOrder, 3)
        }
    }

    // MARK: - 9. Эквивалентность категорий (RU / EN) и динамическая иконка
    func testCategoryEquivalenceHelper() {
        XCTAssertTrue(MainPanelView.isCategoryEquivalent("Шаблоны", "Templates"))
        XCTAssertTrue(MainPanelView.isCategoryEquivalent("Templates", "Шаблоны"))
        XCTAssertTrue(MainPanelView.isCategoryEquivalent("Разработка", "Dev"))
        XCTAssertTrue(MainPanelView.isCategoryEquivalent("Работа", "Work"))
        XCTAssertTrue(MainPanelView.isCategoryEquivalent("Промпты", "Prompts"))
        XCTAssertTrue(MainPanelView.isCategoryEquivalent("Поддержка", "Support"))
        XCTAssertTrue(MainPanelView.isCategoryEquivalent("Контакты", "Support"))
        XCTAssertFalse(MainPanelView.isCategoryEquivalent("Разработка", "Шаблоны"))
        XCTAssertFalse(MainPanelView.isCategoryEquivalent("Работа", "Промпты"))
    }

    func testDeckCalculatedRestPosesMatchSpec() {
        let spec: [(Int, CGFloat, CGFloat, Double, Double, Double, Double)] = [
            (0, 82, 1.0, 0, 30, 0.0, 1.0),
            (1, 34, 0.96, -4, 25, 0.14, 1.0),
            (2, -4, 0.92, -7, 20, 0.26, 1.0),
            (3, -36, 0.88, -10, 15, 0.36, 1.0),
            (4, -64, 0.845, -13, 10, 0.46, 1.0)
        ]
        for (slot, y, scale, rot, z, dark, opacity) in spec {
            let pose = DeckCardCalculatedPose.resting(slot: slot)
            XCTAssertEqual(pose.offsetY, y)
            XCTAssertEqual(pose.scaleX, scale)
            XCTAssertEqual(pose.scaleY, scale)
            XCTAssertEqual(pose.rotateX, rot)
            XCTAssertEqual(pose.zIndex, z)
            XCTAssertEqual(pose.shadowDarkness, dark)
            XCTAssertEqual(pose.opacity, opacity)
        }

        // Lift poses during shuffle
        let upLift = SnippetDeckHelper.calculatePose(
            slot: 0,
            depth: 0,
            isBeingShuffled: true,
            direction: .up,
            phase: .lift,
            total: 5
        )
        XCTAssertEqual(upLift.offsetY, -104)
        XCTAssertEqual(upLift.rotateX, -72)
        XCTAssertEqual(upLift.scaleX, 0.855)
        XCTAssertEqual(upLift.scaleY, 0.72)
        XCTAssertEqual(upLift.zIndex, 38)
        XCTAssertEqual(upLift.shadowDarkness, 0.28)
        XCTAssertEqual(upLift.opacity, 1.0)

        let downLift = SnippetDeckHelper.calculatePose(
            slot: 4,
            depth: 4,
            isBeingShuffled: true,
            direction: .down,
            phase: .lift,
            total: 5
        )
        XCTAssertEqual(downLift.offsetY, -104)
        XCTAssertEqual(downLift.rotateX, -72)
        XCTAssertEqual(downLift.scaleX, 0.88)
        XCTAssertEqual(downLift.scaleY, 0.72)
        XCTAssertEqual(downLift.zIndex, 10) // Keeps zIndex 10 behind stack during lift!
        XCTAssertEqual(downLift.opacity, 1.0)

        // Intermediate wave poses in lift phase
        let waveUp1 = SnippetDeckHelper.calculatePose(slot: 1, depth: 1, isBeingShuffled: false, direction: .up, phase: .lift, total: 5)
        XCTAssertEqual(waveUp1.offsetY, 58)
        XCTAssertEqual(waveUp1.opacity, 1.0)
        let waveUp2 = SnippetDeckHelper.calculatePose(slot: 2, depth: 2, isBeingShuffled: false, direction: .up, phase: .lift, total: 5)
        XCTAssertEqual(waveUp2.offsetY, 15)
        XCTAssertEqual(waveUp2.opacity, 1.0)
        let waveUp3 = SnippetDeckHelper.calculatePose(slot: 3, depth: 3, isBeingShuffled: false, direction: .up, phase: .lift, total: 5)
        XCTAssertEqual(waveUp3.offsetY, -20)
        XCTAssertEqual(waveUp3.opacity, 1.0)
        let waveUp4 = SnippetDeckHelper.calculatePose(slot: 4, depth: 4, isBeingShuffled: false, direction: .up, phase: .lift, total: 5)
        XCTAssertEqual(waveUp4.offsetY, -50)
        XCTAssertEqual(waveUp4.opacity, 1.0)

        // Centering shift test
        XCTAssertEqual(SnippetDeckHelper.centeringShiftUp(forTotal: 0), -68)
        XCTAssertEqual(SnippetDeckHelper.centeringShiftUp(forTotal: 1), -68)
        XCTAssertEqual(SnippetDeckHelper.centeringShiftUp(forTotal: 2), -46)
        XCTAssertEqual(SnippetDeckHelper.centeringShiftUp(forTotal: 3), -28)
        XCTAssertEqual(SnippetDeckHelper.centeringShiftUp(forTotal: 4), -12)
        XCTAssertEqual(SnippetDeckHelper.centeringShiftUp(forTotal: 5), 0)
        XCTAssertEqual(SnippetDeckHelper.centeringShiftUp(forTotal: 10), 0)

        // finalOffsetY test
        let final2 = SnippetDeckHelper.finalOffsetY(baseOffsetY: -104, centeringShiftUp: -46, total: 2, isBeingShuffled: true, phase: .lift)
        XCTAssertEqual(final2, -18)
        let final3 = SnippetDeckHelper.finalOffsetY(baseOffsetY: -104, centeringShiftUp: -28, total: 3, isBeingShuffled: true, phase: .lift)
        XCTAssertEqual(final3, -42)
        let final5 = SnippetDeckHelper.finalOffsetY(baseOffsetY: -104, centeringShiftUp: 0, total: 5, isBeingShuffled: true, phase: .lift)
        XCTAssertEqual(final5, -104)
        let finalResting = SnippetDeckHelper.finalOffsetY(baseOffsetY: 82, centeringShiftUp: -46, total: 2, isBeingShuffled: false, phase: .idle)
        XCTAssertEqual(finalResting, 36)
    }

    func testDeckCircularDepthAndVisibleSlots() {
        let total = 11
        let activeSnippetIndex = 0
        let idx = 10
        let depth = SnippetDeckHelper.circularDepth(index: idx, activeIndex: activeSnippetIndex, total: total)
        XCTAssertEqual(depth, 10)
        XCTAssertFalse(SnippetDeckHelper.isCardVisible(depth: depth, total: total, isShuffling: false))
        XCTAssertTrue(SnippetDeckHelper.isCardVisible(depth: depth, total: total, isShuffling: true))
        XCTAssertTrue(SnippetDeckHelper.isCardVisible(depth: 4, total: total, isShuffling: false))
        let slot = SnippetDeckHelper.visualSlot(forDepth: depth, total: total)
        XCTAssertEqual(slot, 4)

        // Slot 4 overlap prevention
        XCTAssertFalse(
            SnippetDeckHelper.isCardVisible(
                depth: 4,
                total: 11,
                isShuffling: false,
                isShufflingActive: true,
                shufflingCardDepth: 10
            )
        )
        XCTAssertTrue(
            SnippetDeckHelper.isCardVisible(
                depth: 10,
                total: 11,
                isShuffling: true,
                isShufflingActive: true,
                shufflingCardDepth: 10
            )
        )
    }

    func testDeckCyclicDepth() {
        let total = 6, active = 4
        let depths = (0..<total).map { SnippetDeckHelper.circularDepth(index: $0, activeIndex: active, total: total) }
        XCTAssertEqual(depths, [2, 3, 4, 5, 0, 1])
    }

    func testStressTest100SnippetsSeeding() async {
        let db = DatabaseManager.shared
        try? await db.initializeDatabase()
        await db.seedStressTest100SnippetsIfNeeded(force: true)
        let snippets = await db.fetchSnippets()
        XCTAssertGreaterThanOrEqual(snippets.count, 4)
        let workCount = snippets.filter { $0.category.localizedCaseInsensitiveCompare("Работа") == .orderedSame }.count
        let devCount = snippets.filter { $0.category.localizedCaseInsensitiveCompare("Разработка") == .orderedSame }.count
        let tplCount = snippets.filter { $0.category.localizedCaseInsensitiveCompare("Шаблоны") == .orderedSame }.count
        let promptCount = snippets.filter { $0.category.localizedCaseInsensitiveCompare("Промпты") == .orderedSame }.count
        XCTAssertGreaterThanOrEqual(workCount, 1)
        XCTAssertGreaterThanOrEqual(devCount, 1)
        XCTAssertGreaterThanOrEqual(tplCount, 1)
        XCTAssertGreaterThanOrEqual(promptCount, 1)
        let seededByCategory = ["Работа", "Разработка", "Шаблоны", "Промпты"].flatMap { cat in
            snippets.filter { $0.category.localizedCaseInsensitiveCompare(cat) == .orderedSame }
        }
        XCTAssertFalse(seededByCategory.isEmpty)
        XCTAssertTrue(seededByCategory.contains { !$0.isPinned })
    }

    func testDeleteUnpinnedSnippetsRemovesFromSQLite() async throws {
        let db = DatabaseManager.shared
        try? await db.initializeDatabase()
        let unpinnedId = "__test_unpinned_\(UUID().uuidString)"
        let pinnedId = "__test_pinned_\(UUID().uuidString)"
        let insertedUnpinned = await db.insertSnippet(id: unpinnedId, title: "Tmp Unpinned", content: "U", category: "Работа", isPinned: false)
        let insertedPinned = await db.insertSnippet(id: pinnedId, title: "Tmp Pinned", content: "P", category: "Работа", isPinned: true)
        XCTAssertTrue(insertedUnpinned)
        XCTAssertTrue(insertedPinned)

        await db.deleteUnpinnedSnippets()
        let after = await db.fetchSnippets()
        XCTAssertFalse(after.contains(where: { $0.id == unpinnedId }), "Незакреплённый фрагмент должен удаляться из SQLite")
        XCTAssertTrue(after.contains(where: { $0.id == pinnedId }), "Закреплённый фрагмент должен сохраняться в SQLite")

        try? await db.deleteSnippet(idString: pinnedId)
    }

    func testDeleteUnpinnedSnippetsRemovesImageFilesFromDisk() async throws {
        let db = DatabaseManager.shared
        try await db.initializeDatabase()

        func makeTestImage(_ color: NSColor) -> NSImage {
            let img = NSImage(size: NSSize(width: 20, height: 20))
            img.lockFocus()
            color.setFill()
            NSRect(x: 0, y: 0, width: 20, height: 20).fill()
            img.unlockFocus()
            return img
        }

        let unpinnedPath = try XCTUnwrap(DatabaseManager.saveSnippetImage(makeTestImage(.systemOrange)))
        let pinnedPath = try XCTUnwrap(DatabaseManager.saveSnippetImage(makeTestImage(.systemBlue)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unpinnedPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: pinnedPath))
        XCTAssertTrue(URL(fileURLWithPath: unpinnedPath).lastPathComponent.hasPrefix("snippet_img_"))
        XCTAssertTrue(URL(fileURLWithPath: pinnedPath).lastPathComponent.hasPrefix("snippet_img_"))

        let unpinnedId = "__test_unpinned_img_\(UUID().uuidString)"
        let pinnedId = "__test_pinned_img_\(UUID().uuidString)"
        defer {
            try? FileManager.default.removeItem(atPath: unpinnedPath)
            try? FileManager.default.removeItem(atPath: pinnedPath)
            Task {
                try? await db.deleteSnippet(idString: unpinnedId)
                try? await db.deleteSnippet(idString: pinnedId)
            }
        }

        let ok1 = await db.insertSnippet(id: unpinnedId, title: "UnpinnedImg", content: "U", category: "Работа", isPinned: false, imagePath: unpinnedPath)
        let ok2 = await db.insertSnippet(id: pinnedId, title: "PinnedImg", content: "P", category: "Работа", isPinned: true, imagePath: pinnedPath)
        XCTAssertTrue(ok1)
        XCTAssertTrue(ok2)

        await db.deleteUnpinnedSnippets()

        XCTAssertFalse(FileManager.default.fileExists(atPath: unpinnedPath), "snippet_img_*.png незакреплённого фрагмента должен удаляться с диска")
        XCTAssertTrue(FileManager.default.fileExists(atPath: pinnedPath), "snippet_img_*.png закреплённого фрагмента должен сохраняться на диске")
        try? await db.deleteSnippet(idString: pinnedId)
    }

    func testMostUsedSortingDoesNotPrioritizePinnedAndSnapshotPreservesOrder() {
        let now = Date().timeIntervalSince1970
        let a = QuickSnippetItem(id: "a", title: "Alpha", content: "1", category: "Работа", isPinned: false, useCount: 10, createdAt: now)
        let b = QuickSnippetItem(id: "b", title: "Beta", content: "2", category: "Работа", isPinned: true, useCount: 2, createdAt: now)
        let mostUsed = SnippetDeckHelper.sortSnippets([b, a], order: "mostUsed")
        XCTAssertEqual(mostUsed.map(\.id), ["a", "b"])

        let pinnedWithSnapshot = SnippetDeckHelper.sortSnippets([b, a], order: "pinned", pinnedSnapshotIds: ["a", "b"])
        XCTAssertEqual(pinnedWithSnapshot.map(\.id), ["a", "b"])
    }

    // MARK: - 13. Тест сохранения и извлечения фрагмента с imagePath
    func testSnippetSaveAndFetchWithImagePath() async throws {
        let testImage = NSImage(size: NSSize(width: 100, height: 100))
        testImage.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 100, height: 100).fill()
        testImage.unlockFocus()

        let savedPath = DatabaseManager.saveSnippetImage(testImage)
        let imagePath = try XCTUnwrap(savedPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: imagePath))

        defer {
            try? FileManager.default.removeItem(atPath: imagePath)
        }

        let snippetId = "test-image-snippet-\(UUID().uuidString)"
        let saved = await DatabaseManager.shared.insertSnippet(
            id: snippetId,
            title: "Фрагмент со скриншотом",
            content: "Пояснительный текст к картинке",
            category: "Работа",
            isPinned: false,
            imagePath: imagePath
        )
        XCTAssertTrue(saved)

        defer {
            Task {
                try? await DatabaseManager.shared.deleteSnippet(idString: snippetId)
            }
        }

        let fetched = await DatabaseManager.shared.fetchSnippets()
        let target = try XCTUnwrap(fetched.first(where: { $0.id == snippetId }))
        XCTAssertEqual(target.title, "Фрагмент со скриншотом")
        XCTAssertEqual(target.content, "Пояснительный текст к картинке")
        XCTAssertEqual(target.imagePath, imagePath)
    }

    // MARK: - 14. Тест работы с временной категорией __TestCategoryTemp__ и удаление
    func testTemporaryCategoryLifecycle() async throws {
        let tempCatName = "__TestCategoryTemp__"
        let created = await DatabaseManager.shared.createSnippetCategory(name: tempCatName, iconName: "folder.fill")
        let cat = try XCTUnwrap(created)
        XCTAssertEqual(cat.name, tempCatName)

        defer {
            Task {
                try? await DatabaseManager.shared.deleteSnippetCategoryAndSnippets(id: cat.id)
            }
        }

        let categories = await DatabaseManager.shared.fetchSnippetCategories()
        XCTAssertTrue(categories.contains(where: { $0.name == tempCatName }))

        // Удаление
        try await DatabaseManager.shared.deleteSnippetCategoryAndSnippets(id: cat.id)
        let afterDelete = await DatabaseManager.shared.fetchSnippetCategories()
        XCTAssertFalse(afterDelete.contains(where: { $0.name == tempCatName }))
    }

    // MARK: - 15. Сохранение сырого текста фрагмента 1:1 без автозамены макросов на этапе сохранения
    func testSnippetRawContentSavedWithoutBaking() async throws {
        let rawContent = "Промпт: {{date}} - {{time}} - {{app}}"
        let snippetId = "test-raw-snippet-\(UUID().uuidString)"
        let saved = await DatabaseManager.shared.insertSnippet(
            id: snippetId,
            title: "Сырой макрос фрагмент",
            content: rawContent,
            category: "Работа",
            isPinned: false
        )
        XCTAssertTrue(saved)

        defer {
            Task {
                try? await DatabaseManager.shared.deleteSnippet(idString: snippetId)
            }
        }

        let fetched = await DatabaseManager.shared.fetchSnippets()
        let target = try XCTUnwrap(fetched.first(where: { $0.id == snippetId }))
        XCTAssertEqual(target.content, rawContent, "Контент должен сохраняться 1:1 со всеми макросами")

        // Проверяем, что раскрытие происходит при вызове expand
        let expanded = SnippetMacroEngine.expand(target.content, targetAppName: "Xcode")
        XCTAssertFalse(expanded.contains("{{date}}"))
        XCTAssertFalse(expanded.contains("{{time}}"))
        XCTAssertFalse(expanded.contains("{{app}}"))
        XCTAssertTrue(expanded.contains("Xcode"))
    }

    // MARK: - 16. Ограничение названия категории до 2 слов и 20 символов
    func testCategoryNameSanitizationMaxTwoWordsAnd20Chars() async throws {
        // 1. Проверка sanitizeCategoryNameInput
        XCTAssertEqual(sanitizeCategoryNameInput("Разработка"), "Разработка")
        XCTAssertEqual(sanitizeCategoryNameInput("  Разработка ПО  "), "Разработка ПО")
        XCTAssertEqual(sanitizeCategoryNameInput("Разработка ПО для мака"), "Разработка ПО", "Должно остаться максимум 2 слова")
        XCTAssertEqual(sanitizeCategoryNameInput("Разработка ПО   "), "Разработка ПО", "Третий пробел после двух слов должен отсекаться")
        XCTAssertEqual(sanitizeCategoryNameInput("СуперДлинноеНазваниеКатегории"), "СуперДлинноеНазвание", "Ограничение до 20 символов")
        XCTAssertEqual(sanitizeCategoryNameInput("СуперДлинноеНазваниеКатегории").count, 20)
        XCTAssertEqual(sanitizeCategoryNameInput(""), "")
        XCTAssertEqual(sanitizeCategoryNameInput("   "), "")

        // 2. Проверка создания в DatabaseManager с длинным именем
        let suffix = String(UUID().uuidString.prefix(4))
        let longName = "Очень длинное_\(suffix) название категории из пяти слов"
        guard let created = await DatabaseManager.shared.createSnippetCategory(name: longName, iconName: "star.fill") else {
            XCTFail("Expected category to be created in DatabaseManager")
            return
        }
        let words = created.name.split(separator: " ")
        XCTAssertLessThanOrEqual(words.count, 2, "В базе имя должно содержать не более 2 слов")
        XCTAssertLessThanOrEqual(created.name.count, 20, "В базе имя должно быть не длиннее 20 символов")
        XCTAssertEqual(created.name, "Очень длинное_\(suffix)")

        // 3. Проверка нормализации существующих категорий и очистки
        AppDefaults.shared.removeObject(forKey: "pv_normalize_categories_two_words_v1")
        await DatabaseManager.shared.normalizeExistingCategoriesIfNeeded()
        let postNormalize = await DatabaseManager.shared.fetchSnippetCategories()
        XCTAssertTrue(postNormalize.contains(where: { $0.id == created.id && $0.name.split(separator: " ").count <= 2 }))
        try? await DatabaseManager.shared.deleteSnippetCategoryAndSnippets(id: created.id)
    }

    // MARK: - 16. Маркеры [[img:...]]: порядок текста и картинок, совместимость с imagePath
    func testInlineImageMarkerSegmentsPreserveOrder() {
        let segs = SnippetInlineContent.segments(of: "Сверху\n[[img:a.png]]\nСнизу")
        XCTAssertEqual(segs, [.text("Сверху\n"), .image("a.png"), .text("\nСнизу")])
        XCTAssertEqual(SnippetInlineContent.plainText(of: "A[[img:a.png]]B"), "AB")
        XCTAssertTrue(SnippetInlineContent.containsMarker("x [[img:b.png]]"))
        XCTAssertFalse(SnippetInlineContent.containsMarker("просто [[текст]]"))

        // Старый фрагмент с imagePath без маркера: картинка после текста
        let legacy = SnippetInlineContent.segments(of: "Текст", legacyImagePath: "/tmp/x.png")
        XCTAssertEqual(legacy, [.text("Текст"), .image("/tmp/x.png")])
    }

    // MARK: - 17. Кодек NSTextAttachment ⇄ строка с маркерами
    func testInlineCodecRoundTripWithAttachment() {
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12)]
        let raw = "Привет [[img:snippet_img_test.png]] мир"
        let attr = SnippetInlineTextCodec.attributedString(from: raw, attributes: attrs)
        XCTAssertEqual(attr.length, "Привет ".count + 1 + " мир".count, "Маркер заменяется одним вложением")
        XCTAssertFalse(attr.string.contains("[[img:"), "В поле никогда не виден текстовый маркер")
        XCTAssertEqual(SnippetInlineTextCodec.rawString(from: attr), raw)

        // Удаление вложения убирает маркер
        let mutable = NSMutableAttributedString(attributedString: attr)
        mutable.deleteCharacters(in: NSRange(location: "Привет ".count, length: 1))
        XCTAssertEqual(SnippetInlineTextCodec.rawString(from: mutable), "Привет  мир")
    }

    // MARK: - 18. {{uuid}}: в превью 8 символов + «…», при вставке полный UUID
    func testUUIDPreviewShortButExpansionFull() {
        let preview = SnippetMacroEngine.previewValue(for: "{{uuid}}")
        XCTAssertEqual(preview.count, 9)
        XCTAssertTrue(preview.hasSuffix("…"))
        let full = SnippetMacroEngine.expand("{{uuid}}")
        XCTAssertEqual(full.count, 36)
        XCTAssertEqual(full, full.lowercased())
    }

    // MARK: - 19. Счётчик использований useCount: декодирование без поля и инкремент в БД
    func testSnippetUseCountPersistenceAndIncrement() async throws {
        let legacyJSON = """
        {
            "id": "legacy-usecount-1",
            "title": "Legacy",
            "content": "Body",
            "category": "Работа"
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(QuickSnippetItem.self, from: legacyJSON)
        XCTAssertEqual(decoded.useCount, 0)

        let tempUUID = UUID()
        let tempId = tempUUID.uuidString
        let inserted = await DatabaseManager.shared.insertSnippet(
            id: tempId,
            title: "UseCountTemp",
            content: "Text",
            category: "Работа",
            isPinned: false,
            imagePath: nil,
            useCount: 2
        )
        XCTAssertTrue(inserted)

        await DatabaseManager.shared.incrementSnippetUseCount(id: tempUUID)
        let fetched = await DatabaseManager.shared.fetchSnippets()
        let found = fetched.first(where: { $0.id == tempId })
        XCTAssertEqual(found?.useCount, 3)

        try? await DatabaseManager.shared.deleteSnippet(idString: tempId)
    }

    // MARK: - 20. PointingHandCursorCoordinator & PointingHandNSView
    @MainActor
    func testPointingHandCursorCoordinatorRegistrationHitTestingAndClickProtection() async {
        let coordinator = PointingHandCursorCoordinator.shared
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        let hostView = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        window.contentView = hostView

        let cursorView = PointingHandCursorView.PointingHandNSView(frame: NSRect(x: 50, y: 60, width: 120, height: 40))
        hostView.addSubview(cursorView)
        cursorView.layout()

        XCTAssertTrue(coordinator.containsMouseLocation(NSPoint(x: 100, y: 80), in: window))
        XCTAssertFalse(coordinator.containsMouseLocation(NSPoint(x: 10, y: 10), in: window))
        XCTAssertNil(cursorView.hitTest(NSPoint(x: 10, y: 10)), "PointingHandNSView не должен перехватывать клики и скролл")

        // Скрытый view не должен срабатывать
        cursorView.isHidden = true
        XCTAssertFalse(coordinator.containsMouseLocation(NSPoint(x: 100, y: 80), in: window))
        cursorView.isHidden = false

        // Имитируем сброс курсора в стрелку и одиночный клик внутри view
        NSCursor.arrow.set()
        coordinator.handleMouseClick(in: window, pointInWindow: NSPoint(x: 100, y: 80))
        XCTAssertEqual(NSCursor.current, NSCursor.pointingHand)

        // Удаление из окна должно дерегистрировать view
        cursorView.removeFromSuperview()
        XCTAssertFalse(coordinator.containsMouseLocation(NSPoint(x: 100, y: 80), in: window))
    }

    // MARK: - 21. Все 5 режимов сортировки фрагментов (для всех и внутри категории)
    func testAllFiveSnippetSortModesAllAndByCategory() {
        let t1: Double = 1000
        let t2: Double = 2000
        let t3: Double = 3000
        let t4: Double = 4000

        let items = [
            QuickSnippetItem(id: "s1", title: "Бета", content: "c1", category: "Работа", isPinned: false, useCount: 10, createdAt: t1),
            QuickSnippetItem(id: "s2", title: "Альфа", content: "c2", category: "Работа", isPinned: true, useCount: 2, createdAt: t2),
            QuickSnippetItem(id: "s3", title: "Гамма", content: "c3", category: "Код", isPinned: false, useCount: 25, createdAt: t4),
            QuickSnippetItem(id: "s4", title: "Дельта", content: "c4", category: "Работа", isPinned: false, useCount: 5, createdAt: t3)
        ]

        // 1. По закреплённым (pinned first, затем newest)
        let byPinned = SnippetDeckHelper.sortSnippets(items, order: "pinned")
        XCTAssertEqual(byPinned.map(\.id), ["s2", "s3", "s4", "s1"])

        // 2. Часто используемые (useCount desc)
        let byMostUsed = SnippetDeckHelper.sortSnippets(items, order: "mostUsed")
        XCTAssertEqual(byMostUsed.map(\.id), ["s3", "s1", "s4", "s2"])

        // 3. Сначала новые
        let byNewest = SnippetDeckHelper.sortSnippets(items, order: "newest")
        XCTAssertEqual(byNewest.map(\.id), ["s3", "s4", "s2", "s1"])

        // 4. Сначала старые
        let byOldest = SnippetDeckHelper.sortSnippets(items, order: "oldest")
        XCTAssertEqual(byOldest.map(\.id), ["s1", "s2", "s4", "s3"])

        // 5. По алфавиту А–Я
        let byAlpha = SnippetDeckHelper.sortSnippets(items, order: "alphabetical")
        XCTAssertEqual(byAlpha.map(\.id), ["s2", "s1", "s3", "s4"])

        // Внутри отдельной категории «Работа»
        let workOnly = items.filter { $0.category == "Работа" }
        XCTAssertEqual(SnippetDeckHelper.sortSnippets(workOnly, order: "pinned").map(\.id), ["s2", "s4", "s1"])
        XCTAssertEqual(SnippetDeckHelper.sortSnippets(workOnly, order: "mostUsed").map(\.id), ["s1", "s4", "s2"])
        XCTAssertEqual(SnippetDeckHelper.sortSnippets(workOnly, order: "newest").map(\.id), ["s4", "s2", "s1"])
        XCTAssertEqual(SnippetDeckHelper.sortSnippets(workOnly, order: "oldest").map(\.id), ["s1", "s2", "s4"])
        XCTAssertEqual(SnippetDeckHelper.sortSnippets(workOnly, order: "alphabetical").map(\.id), ["s2", "s1", "s4"])
    }

    // MARK: - 22. Правило «1 фрагмент = 1 картинка», очистка [[img:...]] и сохранение в BackupArchive
    func testSingleImagePerSnippetRuleAndBackupRoundTrip() throws {
        let rawWithMarker = "Текст до [[img:snippet_old_1.png]] и после [[img:snippet_old_2.png]]"
        let cleaned = SnippetInlineContent.plainText(of: rawWithMarker)
        XCTAssertFalse(cleaned.contains("[[img:"))
        XCTAssertEqual(cleaned, "Текст до  и после ")

        let snippet = QuickSnippetItem(
            id: "snip-img-rule-1",
            title: "OneImage",
            content: cleaned,
            category: "Работа",
            isPinned: true,
            imagePath: "snippet_single_photo.png",
            imageDataBase64: "AQID",
            useCount: 17
        )

        let archive = PasteVaultBackupArchive(
            version: 1,
            createdAt: Date(),
            appVersion: "1.0.0",
            clipboardItems: [],
            snippets: [snippet],
            settings: BackupSettingsPayload(
                blacklistedBundleIDs: [],
                shortcutsData: nil,
                appearanceAndStorage: BackupAppearanceAndStorage(
                    selectedThemeId: "frost",
                    userGlassLevel: 0.8,
                    selectedFontId: "system",
                    appLanguage: "ru",
                    historyLimit: 500,
                    saveFiles: true,
                    saveImages: true,
                    saveText: true
                )
            )
        )

        let data = try JSONEncoder().encode(archive)
        let decoded = try JSONDecoder().decode(PasteVaultBackupArchive.self, from: data)
        let restored = try XCTUnwrap(decoded.snippets?.first)
        XCTAssertEqual(restored.imagePath, "snippet_single_photo.png")
        XCTAssertEqual(restored.imageDataBase64, "AQID")
        XCTAssertEqual(restored.useCount, 17)
    }

    // MARK: - 23. Все 8 макросов в SnippetMacroEngine
    func testAllEightMacrosExpansionAndUUIDPreview() {
        XCTAssertEqual(SnippetMacroEngine.macros.count, 8)

        for macro in SnippetMacroEngine.macros {
            let expanded = SnippetMacroEngine.expand(macro.tag)
            XCTAssertFalse(expanded.isEmpty, "Макрос \(macro.tag) должен раскрываться")
            XCTAssertFalse(expanded.contains("{{"), "Макрос \(macro.tag) не должен оставаться нераскрытым")
        }

        let uuidPreview = SnippetMacroEngine.previewValue(for: "{{uuid}}")
        XCTAssertEqual(uuidPreview.count, 9)
        XCTAssertTrue(uuidPreview.hasSuffix("…"))

        let uuidFull = SnippetMacroEngine.expand("{{uuid}}")
        XCTAssertEqual(uuidFull.count, 36)
        XCTAssertNotNil(UUID(uuidString: uuidFull))
    }

    // MARK: - 24. Scrubber target index calculation & 3-digit counter formatting
    func testDeckScrubberIndexCalculationAndThreeDigitCounter() {
        let total = 114
        let height: CGFloat = 180

        XCTAssertEqual(SnippetDeckHelper.scrubberTargetIndex(locationY: -20, capsuleHeight: height, total: total), 0)
        XCTAssertEqual(SnippetDeckHelper.scrubberTargetIndex(locationY: 0, capsuleHeight: height, total: total), 0)
        XCTAssertEqual(SnippetDeckHelper.scrubberTargetIndex(locationY: 90, capsuleHeight: height, total: total), 57)
        XCTAssertEqual(SnippetDeckHelper.scrubberTargetIndex(locationY: 180, capsuleHeight: height, total: total), 113)
        XCTAssertEqual(SnippetDeckHelper.scrubberTargetIndex(locationY: 250, capsuleHeight: height, total: total), 113)

        // Краевой случай с 1 карточкой
        XCTAssertEqual(SnippetDeckHelper.scrubberTargetIndex(locationY: 50, capsuleHeight: height, total: 1), 0)

        // Трёхзначный счётчик
        XCTAssertEqual(SnippetDeckHelper.counterText(activeIndex: 0, total: 114), "1/114")
        XCTAssertEqual(SnippetDeckHelper.counterText(activeIndex: 113, total: 114), "114/114")
    }

    // MARK: - 25. Continuous Riffle Scroll: ускорение шага и граничные индексы
    func testContinuousRiffleScrollAccelerationAndBoundaryWrapping() {
        // Первые 5 шагов: 0.11 сек (~9/сек), с 5-го шага: 0.065 сек (~15/сек)
        for step in 0..<5 {
            XCTAssertEqual(SnippetDeckHelper.continuousStepInterval(stepCount: step), 0.11, accuracy: 0.0001)
        }
        for step in 5..<20 {
            XCTAssertEqual(SnippetDeckHelper.continuousStepInterval(stepCount: step), 0.065, accuracy: 0.0001)
        }

        // Граничные переходы 0 <-> total - 1
        let total = 114
        XCTAssertEqual(SnippetDeckHelper.wrappedDeckIndex(currentIndex: 0, direction: .down, total: total), 113)
        XCTAssertEqual(SnippetDeckHelper.wrappedDeckIndex(currentIndex: 113, direction: .up, total: total), 0)
        XCTAssertEqual(SnippetDeckHelper.wrappedDeckIndex(currentIndex: 5, direction: .up, total: total), 6)
        XCTAssertEqual(SnippetDeckHelper.wrappedDeckIndex(currentIndex: 5, direction: .down, total: total), 4)

        // Краевой случай 0 или 1 карточка
        XCTAssertEqual(SnippetDeckHelper.wrappedDeckIndex(currentIndex: 0, direction: .up, total: 1), 0)
        XCTAssertEqual(SnippetDeckHelper.wrappedDeckIndex(currentIndex: 0, direction: .down, total: 0), 0)
    }

    // MARK: - 26. Удаление категории с кириллическим именем в разном регистре («Тест» vs «тест») и очистка сирот
    func testCyrillicCaseInsensitiveCategoryDeletionAndOrphanCleanup() async throws {
        let catNameUpper = "__ТестКат_\(UUID().uuidString.prefix(6))"
        let catNameLower = catNameUpper.lowercased()

        // 1. Создаём категорию в верхнем регистре и добавляем 3 фрагмента (включая разный регистр)
        let rawCreated1 = await DatabaseManager.shared.createSnippetCategory(name: catNameUpper, iconName: "folder.fill")
        let created1 = try XCTUnwrap(rawCreated1)
        let ids = [UUID().uuidString, UUID().uuidString, UUID().uuidString]
        for (idx, id) in ids.enumerated() {
            let catForSnippet = (idx == 2) ? catNameLower : catNameUpper
            let ok = await DatabaseManager.shared.insertSnippet(
                id: id,
                title: "CyrillicTest \(idx)",
                content: "Body \(idx)",
                category: catForSnippet,
                isPinned: false,
                imagePath: nil,
                useCount: 0
            )
            XCTAssertTrue(ok)
        }

        // 2. Удаляем категорию — все 3 фрагмента (включая другой регистр кириллицы) должны удалиться
        try await DatabaseManager.shared.deleteSnippetCategoryAndSnippets(id: created1.id)

        // 3. Создаём заново категорию с тем же именем в нижнем регистре — внутри должно быть 0 фрагментов
        let rawCreated2 = await DatabaseManager.shared.createSnippetCategory(name: catNameLower, iconName: "folder.fill")
        let created2 = try XCTUnwrap(rawCreated2)
        let allAfterRecreate = await DatabaseManager.shared.fetchSnippets()
        let snippetsInNewCategory = allAfterRecreate.filter {
            $0.category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == catNameLower
        }
        XCTAssertEqual(snippetsInNewCategory.count, 0, "Ни одна карточка из удалённой категории не должна вернуться!")

        // 4. Проверяем cleanupOrphanedSnippets для осиротевшей записи
        let orphanId = UUID().uuidString
        _ = await DatabaseManager.shared.insertSnippet(
            id: orphanId,
            title: "Orphan",
            content: "Orphan body",
            category: "__OrphanCat_Temp",
            isPinned: false,
            imagePath: nil,
            useCount: 0
        )
        let removedOrphans = await DatabaseManager.shared.cleanupOrphanedSnippets()
        XCTAssertGreaterThanOrEqual(removedOrphans, 1)
        let afterCleanup = await DatabaseManager.shared.fetchSnippets()
        XCTAssertFalse(afterCleanup.contains(where: { $0.id == orphanId }))

        // Чистим временную категорию после теста
        try? await DatabaseManager.shared.deleteSnippetCategoryAndSnippets(id: created2.id)
    }

    func testGlobalSnippetNumberingRecalculationAndNumberSearch() {
        let s1 = QuickSnippetItem(id: "id-a", title: "Alpha", content: "One", category: "CatA", createdAt: 100)
        let s2 = QuickSnippetItem(id: "id-b", title: "Beta", content: "Two", category: "CatB", createdAt: 200)
        let s3 = QuickSnippetItem(id: "id-c", title: "Gamma", content: "Three", category: "CatA", createdAt: 300)
        let s4 = QuickSnippetItem(id: "id-d", title: "Delta", content: "Four", category: "CatB", createdAt: 300) // tie-break by id

        let initialNumbers = SnippetDeckHelper.computeGlobalNumbers(for: [s3, s1, s4, s2])
        XCTAssertEqual(initialNumbers["id-a"], 1)
        XCTAssertEqual(initialNumbers["id-b"], 2)
        XCTAssertEqual(initialNumbers["id-c"], 3)
        XCTAssertEqual(initialNumbers["id-d"], 4)

        // Фильтрация по категории не меняет сквозной номер карточки
        let catBFiltered = [s2, s4]
        XCTAssertEqual(catBFiltered.map { initialNumbers[$0.id] }, [2, 4])

        // Удаление карточки #2 пересчитывает номера без дыр: 1...3
        let afterDelete = SnippetDeckHelper.computeGlobalNumbers(for: [s1, s3, s4])
        XCTAssertEqual(afterDelete["id-a"], 1)
        XCTAssertEqual(afterDelete["id-c"], 2)
        XCTAssertEqual(afterDelete["id-d"], 3)
        XCTAssertNil(afterDelete["id-b"])

        // Поиск по номеру "#2" / "2" / "#12" / "12"
        XCTAssertTrue(SnippetDeckHelper.matchesNumberQuery(globalNumber: 2, query: "#2"))
        XCTAssertTrue(SnippetDeckHelper.matchesNumberQuery(globalNumber: 2, query: "2"))
        XCTAssertTrue(SnippetDeckHelper.matchesNumberQuery(globalNumber: 12, query: "#12"))
        XCTAssertTrue(SnippetDeckHelper.matchesNumberQuery(globalNumber: 12, query: "2"))
        XCTAssertFalse(SnippetDeckHelper.matchesNumberQuery(globalNumber: 3, query: "#2"))
        XCTAssertFalse(SnippetDeckHelper.matchesNumberQuery(globalNumber: 3, query: "#"))
        XCTAssertFalse(SnippetDeckHelper.matchesNumberQuery(globalNumber: 3, query: "abc"))
    }

    func testDeckVisibleDotsWindowTenDots() {
        // Меньше 10 карточек — отображаются все точки
        XCTAssertEqual(SnippetDeckHelper.visibleDotIndices(total: 6, activeIndex: 2), [0, 1, 2, 3, 4, 5])
        // Ровно 10 карточек
        XCTAssertEqual(SnippetDeckHelper.visibleDotIndices(total: 10, activeIndex: 5).count, 10)
        // Больше 10 карточек (105) — окно из 10 точек в начале, середине и конце
        XCTAssertEqual(SnippetDeckHelper.visibleDotIndices(total: 105, activeIndex: 0), Array(0..<10))
        XCTAssertEqual(SnippetDeckHelper.visibleDotIndices(total: 105, activeIndex: 50), Array(46..<56))
        XCTAssertEqual(SnippetDeckHelper.visibleDotIndices(total: 105, activeIndex: 104), Array(95..<105))
    }

    func testForbidNoCategoriesAndAutoCreateCategoryOnSnippetSave() async throws {
        let badId1 = UUID().uuidString
        let badId2 = UUID().uuidString
        let badId3 = UUID().uuidString

        let savedEmpty = await DatabaseManager.shared.insertSnippet(
            id: badId1,
            title: "BadEmpty",
            content: "Body",
            category: ""
        )
        let savedNoCatRu = await DatabaseManager.shared.insertSnippet(
            id: badId2,
            title: "BadNoCatRu",
            content: "Body",
            category: "Нет категорий"
        )
        let savedNoCatEn = await DatabaseManager.shared.insertSnippet(
            id: badId3,
            title: "BadNoCatEn",
            content: "Body",
            category: "No categories"
        )
        XCTAssertFalse(savedEmpty)
        XCTAssertFalse(savedNoCatRu)
        XCTAssertFalse(savedNoCatEn)

        let autoRejected = await DatabaseManager.shared.ensureCategoryAndSaveSnippet(
            id: badId2,
            title: "BadAuto",
            content: "Body",
            categoryName: "Нет категорий"
        )
        XCTAssertFalse(autoRejected.saved)
        XCTAssertNil(autoRejected.resolvedCategory)

        let autoCatName = "__AutoCat_\(Int(Date().timeIntervalSince1970) % 100000)"
        let snippetId = UUID().uuidString
        let autoResult = await DatabaseManager.shared.ensureCategoryAndSaveSnippet(
            id: snippetId,
            title: "AutoCatSnippet",
            content: "Hello AutoCat",
            categoryName: autoCatName,
            iconName: "bolt.fill"
        )
        XCTAssertTrue(autoResult.saved)
        let createdCat = try XCTUnwrap(autoResult.resolvedCategory)
        XCTAssertEqual(createdCat.name, autoCatName)

        let fetchedSnippets = await DatabaseManager.shared.fetchSnippets()
        XCTAssertTrue(fetchedSnippets.contains(where: { $0.id == snippetId && $0.category == autoCatName }))

        // Чистим временную категорию и фрагмент после теста
        try? await DatabaseManager.shared.deleteSnippetCategoryAndSnippets(id: createdCat.id)
    }

    // MARK: - Этап 1: FTS5 AFTER UPDATE триггеры, честный throw в executeRaw/ROLLBACK и защита path traversal для картинок сниппетов
    func testSQLiteFTS5AfterUpdateTriggersAndExecuteRawRollback() async throws {
        let db = DatabaseManager.shared
        try await db.initializeDatabase()

        let token = "UNIQUEFTSTOKEN_\(UUID().uuidString.replacingOccurrences(of: "-", with: "_"))"
        let itemId = "fts-trigger-test-\(UUID().uuidString)"
        defer {
            Task { try? await db.deleteItem(id: itemId) }
        }

        try await db.restoreItem(
            id: itemId,
            contentType: .text,
            textPreview: "Payload containing \(token)",
            contentHash: "hash-\(token)",
            sourceBundleId: nil,
            sourceAppName: "Notes",
            isSensitive: false,
            secretKind: nil,
            isPinned: false,
            createdAt: Int64(Date().timeIntervalSince1970),
            expiresAt: nil,
            fileURLPath: nil,
            useCount: 0
        )

        let initialMatches = try await db.countFTSMatches(for: token)
        XCTAssertEqual(initialMatches, 1, "Нечувствительная запись должна сразу попадать в FTS5")

        try await db.updateSecretStatus(id: itemId, isSensitive: true, contentType: .secret, secretKind: "Token", expiresAt: nil)
        let sensitiveMatches = try await db.countFTSMatches(for: token)
        XCTAssertEqual(sensitiveMatches, 0, "AFTER UPDATE триггер должен удалять запись из FTS5 при is_sensitive = 1")

        try await db.updateSecretStatus(id: itemId, isSensitive: false, contentType: .text, secretKind: nil, expiresAt: nil)
        let restoredMatches = try await db.countFTSMatches(for: token)
        XCTAssertEqual(restoredMatches, 1, "AFTER UPDATE триггер должен возвращать запись в FTS5 при снятии is_sensitive")

        // Проверяем реальный throw из executeRaw и рабочий ROLLBACK
        try await db.executeRaw("BEGIN TRANSACTION;")
        do {
            try await db.executeRaw("INSERT INTO nonexistent_table_stage1 VALUES (1);")
            XCTFail("executeRaw должен выбрасывать ошибку на невалидном SQL")
        } catch {
            try await db.executeRaw("ROLLBACK;")
        }
        try? await db.deleteItem(id: itemId)
    }

    func testDeleteSnippetImageFileIfNeededBlocksTraversalAndOutsidePaths() throws {
        let supportDir = try DatabaseManager.pasteVaultSupportDirectory()
        let imagesDir = supportDir.appendingPathComponent("Images", isDirectory: true)
        try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)

        let outsideURL = FileManager.default.temporaryDirectory.appendingPathComponent("outside_do_not_delete_\(UUID().uuidString).png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: outsideURL)
        defer { try? FileManager.default.removeItem(at: outsideURL) }

        DatabaseManager.deleteSnippetImageFileIfNeeded(outsideURL.path)
        DatabaseManager.deleteSnippetImageFileIfNeeded("../\(outsideURL.lastPathComponent)")
        DatabaseManager.deleteSnippetImageFileIfNeeded("nested/sub/evil.png")
        DatabaseManager.deleteSnippetImageFileIfNeeded("/etc/hosts")
        XCTAssertTrue(FileManager.default.fileExists(atPath: outsideURL.path), "Файлы вне активной папки Images не должны удаляться")

        let safeImageURL = imagesDir.appendingPathComponent("snippet_img_safe_\(UUID().uuidString).png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: safeImageURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: safeImageURL.path))
        DatabaseManager.deleteSnippetImageFileIfNeeded(safeImageURL.path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: safeImageURL.path), "Безопасный файл внутри Images/ должен удаляться")
    }

    // MARK: - 25. Stage 3: Валидация категорий (NFC/NFD, резерв, переименование)
    func testStage3SnippetCategoryValidatorBlocksReservedAndCanonicalDuplicates() {
        let workId = UUID()
        let yogaNFC = "Йога"
        let existing = [
            SnippetCategoryRecord(id: workId, name: "Work", iconName: "briefcase.fill"),
            SnippetCategoryRecord(name: yogaNFC, iconName: "sparkles")
        ]

        XCTAssertFalse(SnippetCategoryValidator.validateCandidate("   ", existingCategories: existing).isValid)
        for reserved in ["Все", "Все категории", "All", "All Categories", "Нет категорий", "No Categories", "Uncategorized"] {
            let res = SnippetCategoryValidator.validateCandidate(reserved, existingCategories: existing)
            XCTAssertFalse(res.isValid)
            XCTAssertTrue(res.isReserved, "Expected '\(reserved)' to be marked reserved")
        }

        let yogaNFD = "И\u{0306}ога"
        let nfdCheck = SnippetCategoryValidator.validateCandidate(yogaNFD, existingCategories: existing)
        XCTAssertFalse(nfdCheck.isValid)
        XCTAssertTrue(nfdCheck.isDuplicate, "NFD canonical equivalent must conflict with NFC category name")

        let sameRename = SnippetCategoryValidator.validateCandidate("work", existingCategories: existing, excludingCategoryId: workId)
        XCTAssertTrue(sameRename.isValid, "Renaming category to itself (case change) must be allowed")

        let conflictRename = SnippetCategoryValidator.validateCandidate(yogaNFD, existingCategories: existing, excludingCategoryId: workId)
        XCTAssertFalse(conflictRename.isValid)
        XCTAssertTrue(conflictRename.isDuplicate)
    }

    // MARK: - 26. Stage 3: Вставка изображения в SnippetNSTextView маршрутизируется в миниатюру
    @MainActor
    func testStage3SnippetNSTextViewImagePasteRoutesToSlotWithoutTextFallback() {
        let textView = SnippetNSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 80))
        var pastedImageCount = 0
        var plainTextFallbackCount = 0
        textView.onPasteImage = { _ in
            pastedImageCount += 1
        }

        let pb = NSPasteboard.withUniqueName()
        defer { pb.releaseGlobally() }

        let image = NSImage(size: NSSize(width: 24, height: 24))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 24, height: 24).fill()
        image.unlockFocus()
        pb.clearContents()
        XCTAssertTrue(pb.writeObjects([image]))

        textView.handlePaste(from: pb) {
            plainTextFallbackCount += 1
        }
        XCTAssertEqual(pastedImageCount, 1)
        XCTAssertEqual(plainTextFallbackCount, 0)

        pb.clearContents()
        pb.setString("plain snippet body", forType: .string)
        textView.handlePaste(from: pb) {
            plainTextFallbackCount += 1
        }
        XCTAssertEqual(pastedImageCount, 1)
        XCTAssertEqual(plainTextFallbackCount, 1)
    }

    // MARK: - 27. Stage 3: EN-локализация SnippetMacroEngine и стабильность snapshot mostUsed
    func testStage3MacroEnglishLocalizationAndMostUsedSnapshotStability() {
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000) // Tue Nov 14 2023 UTC
        let enExpanded = SnippetMacroEngine.expand(
            "App={{app}} Day={{weekday}}",
            targetAppName: "active window",
            date: fixedDate,
            locale: Locale(identifier: "en_US")
        )
        XCTAssertFalse(enExpanded.lowercased().contains("active window"), "Placeholder 'active window' must fall back to resolved frontmost/device name")
        XCTAssertFalse(enExpanded.contains("активное окно"))
        XCTAssertTrue(enExpanded.contains("Day=tuesday") || enExpanded.contains("Day=wednesday"))

        var s1 = QuickSnippetItem(id: "s1", title: "Alpha", content: "1", category: "Work", isPinned: false, useCount: 10)
        var s2 = QuickSnippetItem(id: "s2", title: "Beta", content: "2", category: "Work", isPinned: false, useCount: 2)
        let snapshot = ["s2", "s1", "s1"] // содержит дубликат — не должен падать
        s1.useCount = 999
        s2.useCount = 0
        let sorted = SnippetDeckHelper.sortSnippets([s1, s2], order: "mostUsed", pinnedSnapshotIds: snapshot)
        XCTAssertEqual(sorted.map(\.id), ["s2", "s1"], "Snapshot must freeze order on live useCount edits and tolerate duplicate IDs")
    }

    // MARK: - 28. Итерация 30.34: Геометрия DeckScrollWheelCatcher.frontTextRect для 4 и 5+ карточек
    func testDeckScrollWheelCatcherFrontTextRectCoversBottomAndEdges() {
        let bounds = NSRect(x: 0, y: 0, width: 520, height: 430)
        let centerY = bounds.height / 2

        for visibleCount in [4, 5, 8] {
            let frontOffsetY = DeckCardCalculatedPose.resting(slot: 0).offsetY + SnippetDeckHelper.centeringShiftUp(forTotal: visibleCount)
            let cardTop = centerY + frontOffsetY - 125
            let cardBottom = cardTop + 250
            let rect = DeckScrollWheelCatcher.frontTextRect(in: bounds, visibleCardCount: visibleCount)

            // Нижняя полоса внутри самой карточки (cardBottom - 5) должна быть внутри текстовой зоны (не листает колоду)
            XCTAssertTrue(rect.contains(NSPoint(x: bounds.midX, y: cardBottom - 5)))
            // Левый и правый край внутри карточки (+5 / -5 pt от боков) — внутри текстовой зоны
            XCTAssertTrue(rect.contains(NSPoint(x: bounds.minX + 5, y: cardBottom - 5)))
            XCTAssertTrue(rect.contains(NSPoint(x: bounds.maxX - 5, y: cardBottom - 5)))
            XCTAssertTrue(rect.contains(NSPoint(x: bounds.minX + 5, y: cardTop + 60)))

            // Шапка передней карточки (cardTop + 15) и зоны выше/ниже карточки — снаружи (листают колоду)
            XCTAssertFalse(rect.contains(NSPoint(x: bounds.midX, y: cardTop + 15)))
            XCTAssertFalse(rect.contains(NSPoint(x: bounds.midX, y: cardTop - 20)))
            XCTAssertFalse(rect.contains(NSPoint(x: bounds.midX, y: cardBottom + 10)))
            if cardBottom + 4 < bounds.height {
                XCTAssertFalse(rect.contains(NSPoint(x: bounds.midX, y: cardBottom + 4)))
            }
        }
    }
}
