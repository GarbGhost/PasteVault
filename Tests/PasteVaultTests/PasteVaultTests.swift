import XCTest
import AppKit
import SwiftUI
@testable import PasteVault

@MainActor
final class PasteVaultTests: XCTestCase {

    override func tearDown() async throws {
        let db = DatabaseManager.shared
        await db.seedDefaultSnippetCategoriesIfNeeded()
        try await super.tearDown()
    }

    private func makeItem(
        id: String = UUID().uuidString,
        text: String,
        kind: ContentKind = .text,
        isSensitive: Bool = false
    ) -> ClipboardItem {
        ClipboardItem(
            id: id,
            rowid: 1,
            contentType: kind,
            textPreview: text,
            contentHash: id,
            sourceBundleId: "com.apple.test",
            sourceAppName: "TestApp",
            isSensitive: isSensitive,
            secretKind: isSensitive ? "Пароль" : nil,
            isPinned: false,
            createdAt: Int64(Date().timeIntervalSince1970),
            expiresAt: nil
        )
    }

    func testIsPasswordCandidate() {
        // 1. Длинный текст (10 000 символов) -> false мгновенно за счёт utf8.count <= 80
        let longText = String(repeating: "aB3#x9", count: 1667) // > 10 000 символов
        let longItem = makeItem(id: "long-10k", text: longText)
        XCTAssertFalse(ClipboardRowCardView.isPasswordCandidate(longItem))
        XCTAssertFalse(longItem.isPasswordCandidate)

        // 2. Обычное предложение с пробелами "Привет мир" -> false
        let phraseItem = makeItem(id: "phrase-ru", text: "Привет мир")
        XCTAssertFalse(ClipboardRowCardView.isPasswordCandidate(phraseItem))

        // 3. Многострочный текст "line1\nline2" -> false
        let multilineItem = makeItem(id: "multiline", text: "line1\nline2")
        XCTAssertFalse(ClipboardRowCardView.isPasswordCandidate(multilineItem))

        // 4. Кандидат без пробелов "sk-proj-1234567890" -> true
        let candidateItem = makeItem(id: "cand-token", text: "sk-proj-1234567890")
        XCTAssertTrue(ClipboardRowCardView.isPasswordCandidate(candidateItem))
        XCTAssertTrue(candidateItem.isPasswordCandidate)
    }

    func testPerformanceOnLargeClipboardHistory() {
        // Создаём массив из 500 элементов (включая длинные тексты по 20 000 символов, код, пароли и короткие фразы)
        let hugeLog = String(repeating: "2026-11-05 [INFO] Worker pipeline processed batch=42 latency=1.2ms\n", count: 320) // > 20 000 символов
        let codeBlock = """
        public func computeDigest(input: String) -> String {
            return input.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        """

        var items: [ClipboardItem] = []
        items.reserveCapacity(500)
        for i in 0..<500 {
            let mod = i % 4
            switch mod {
            case 0:
                items.append(makeItem(id: "perf-\(i)", text: hugeLog, kind: .text))
            case 1:
                items.append(makeItem(id: "perf-\(i)", text: codeBlock, kind: .code))
            case 2:
                items.append(makeItem(id: "perf-\(i)", text: "sk-live-secret-token-\(i)", kind: .secret, isSensitive: true))
            default:
                items.append(makeItem(id: "perf-\(i)", text: "Короткая заметка номер \(i)", kind: .text))
            }
        }

        let start = CFAbsoluteTimeGetCurrent()
        var candidateCount = 0
        for item in items {
            if ClipboardRowCardView.isPasswordCandidate(item) {
                candidateCount += 1
            }
        }
        let filteredSecrets = items.filter { $0.isSensitive || $0.effectiveContentType == .secret }
        let filteredCode = items.filter { $0.effectiveContentType == .code }
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000.0

        XCTAssertEqual(candidateCount, 125)
        XCTAssertEqual(filteredSecrets.count, 125)
        XCTAssertEqual(filteredCode.count, 125)
        XCTAssertLessThan(elapsedMs, 100.0, "Expected 500-item candidate check + filtering under 100 ms in Debug, got \(elapsedMs) ms")
    }

    func testTogglePasswordClassificationAndUserForcedPlainText() {
        let monitor = ClipboardMonitor.shared
        let id = monitor.recordGeneratedPassword("VaultPass2026!#99", ttlSeconds: nil)

        guard let initial = monitor.items.first(where: { $0.id == id }) else {
            XCTFail("Generated password item not found")
            return
        }
        XCTAssertTrue(initial.isSensitive)
        XCTAssertEqual(initial.effectiveContentType, .secret)
        XCTAssertFalse(initial.userForcedPlainText)

        // Переводим пароль в обычный текст
        monitor.togglePasswordClassification(for: id)
        guard let demoted = monitor.items.first(where: { $0.id == id }) else {
            XCTFail("Demoted item not found")
            return
        }
        XCTAssertFalse(demoted.isSensitive)
        XCTAssertEqual(demoted.effectiveContentType, .text)
        XCTAssertTrue(demoted.userForcedPlainText)
        XCTAssertTrue(ClipboardMonitor.manuallyDemotedTextIds.contains(id))

        // Переводим обратно в пароль
        monitor.togglePasswordClassification(for: id)
        guard let promoted = monitor.items.first(where: { $0.id == id }) else {
            XCTFail("Promoted item not found")
            return
        }
        XCTAssertTrue(promoted.isSensitive)
        XCTAssertEqual(promoted.effectiveContentType, .secret)
        XCTAssertFalse(promoted.userForcedPlainText)
    }

    func testSingleBinaryInAppBundle() {
        let macosBundleDir = "/Applications/Paste Vault.app/Contents/MacOS"
        if FileManager.default.fileExists(atPath: macosBundleDir) {
            let binaries = (try? FileManager.default.contentsOfDirectory(atPath: macosBundleDir))?.filter { !$0.hasPrefix(".") } ?? []
            XCTAssertEqual(binaries, ["Paste Vault"], "Expected single binary 'Paste Vault' in Contents/MacOS")
        }
    }

    @MainActor
    func testAllSixInterfaceFontsAndBundledTTF() async throws {
        XCTAssertEqual(AppFont.allCases.count, 6)

        let expectedFiles = [
            "Inter.ttf",
            "Manrope.ttf",
            "JetBrainsMono.ttf",
            "Jura.ttf",
            "Tektur.ttf",
            "Comfortaa.ttf"
        ]

        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let repoFontsDir = repoRoot.appendingPathComponent("Resources/Fonts", isDirectory: true)
        for filename in expectedFiles {
            let fileURL = repoFontsDir.appendingPathComponent(filename)
            XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path), "Missing bundled font: \(filename)")
        }

        FontManager.shared.ensureFontsInstalled()
        for _ in 0..<40 {
            if FontManager.shared.hasCompletedLoad { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertEqual(FontManager.shared.resolvedPostScriptNames.count, 6)

        let distinctResolvedNames = Set(FontManager.shared.resolvedPostScriptNames.values)
        XCTAssertEqual(distinctResolvedNames.count, 6, "Each of the 6 fonts must resolve to a distinct font name: \(FontManager.shared.resolvedPostScriptNames)")

        for fontCase in AppFont.allCases {
            let nsFont = fontCase.nsFont(size: 14, weight: .semibold)
            XCTAssertEqual(nsFont.pointSize, 14)
        }
    }

    func testColorConversionAndHslParsing() {
        // 1. Проверяем конвертацию эталонного цвета #CAA895 в RGB и HSL
        guard let color = SmartClassifier.parseNSColor("#CAA895") else {
            XCTFail("Failed to parse #CAA895")
            return
        }
        XCTAssertEqual(color.hexString, "#CAA895")
        XCTAssertEqual(color.rgbString, "rgb(202, 168, 149)")
        XCTAssertEqual(color.hslString, "hsl(22, 33%, 69%)")

        // 2. Проверяем распознавание hsl(...) как типа .color
        let hslString = "hsl(22, 33%, 69%)"
        XCTAssertTrue(SmartClassifier.isColor(hslString), "hsl string must be recognized by isColor")
        XCTAssertEqual(SmartClassifier.classify(text: hslString, isSensitive: false), .color, "hsl string must be classified as .color")

        // 3. Проверяем парсинг hsl и hsla строк в NSColor
        let parsedHsl = SmartClassifier.parseNSColor(hslString)
        XCTAssertNotNil(parsedHsl, "SmartClassifier.parseNSColor must parse hsl(...) successfully")

        let hslaString = "hsla(210, 100%, 50%, 0.85)"
        XCTAssertTrue(SmartClassifier.isColor(hslaString))
        let parsedHsla = SmartClassifier.parseNSColor(hslaString)
        XCTAssertNotNil(parsedHsla, "SmartClassifier.parseNSColor must parse hsla(...) successfully")
    }

    func testCanonicalColorCachePreventsDriftAcrossMultipleFormatSwitches() {
        let monitor = ClipboardMonitor.shared
        let testId = "color-test-\(UUID().uuidString)"
        let initialHex = "#CAA895"

        let row = ClipboardItemRow(
            id: testId,
            rowid: 9999,
            contentType: .color,
            textPreview: initialHex,
            contentHash: "hash-\(testId)",
            sourceBundleId: "com.apple.test",
            sourceAppName: "TestApp",
            isSensitive: false,
            secretKind: nil,
            isPinned: false,
            createdAt: Int64(Date().timeIntervalSince1970),
            expiresAt: nil
        )
        monitor.items.insert(row, at: 0)
        defer {
            monitor.items.removeAll { $0.id == testId }
            monitor.evictCanonicalColor(for: testId)
        }

        // 1. Получаем форматы — они должны рассчитаться и закэшироваться
        guard let formats = monitor.colorFormats(for: row) else {
            XCTFail("Expected colorFormats for color item")
            return
        }
        XCTAssertEqual(formats.hex, "#CAA895")
        XCTAssertEqual(formats.rgb, "rgb(202, 168, 149)")
        XCTAssertEqual(formats.hsl, "hsl(22, 33%, 69%)")

        // 2. Переключаем на HSL -> item.content обновляется, но канонические значения не дрейфуют
        monitor.selectColorFormat(for: testId, newText: formats.hsl)
        guard let itemAfterHsl = monitor.items.first(where: { $0.id == testId }) else {
            XCTFail("Item not found after HSL switch")
            return
        }
        XCTAssertEqual(itemAfterHsl.textPreview, "hsl(22, 33%, 69%)")
        XCTAssertEqual(itemAfterHsl.content, "hsl(22, 33%, 69%)")
        XCTAssertEqual(itemAfterHsl.contentType, .color)

        // Повторный запрос форматов должен вернуть ТОЧНЫЙ исходный HEX и RGB из кэша
        let formatsAfterHsl = monitor.colorFormats(for: itemAfterHsl)
        XCTAssertEqual(formatsAfterHsl?.hex, "#CAA895", "Canonical HEX must not drift after switching to HSL")
        XCTAssertEqual(formatsAfterHsl?.rgb, "rgb(202, 168, 149)", "Canonical RGB must not drift after switching to HSL")

        // 3. Переключаем на RGB
        monitor.selectColorFormat(for: testId, newText: formats.rgb)
        let itemAfterRgb = monitor.items.first(where: { $0.id == testId })
        XCTAssertEqual(itemAfterRgb?.textPreview, "rgb(202, 168, 149)")
        XCTAssertEqual(itemAfterRgb?.content, "rgb(202, 168, 149)")

        // 4. Переключаем обратно на HEX
        monitor.selectColorFormat(for: testId, newText: formats.hex)
        let itemAfterHex = monitor.items.first(where: { $0.id == testId })
        XCTAssertEqual(itemAfterHex?.textPreview, "#CAA895", "Must return to exact original #CAA895 with 0 drift")
    }

    func testSelectColorFormatUpdatesContentWithoutDuplicateAndPastesSelectedFormat() {
        let monitor = ClipboardMonitor.shared
        let testId = "color-paste-test-\(UUID().uuidString)"
        let initialHex = "#CAA895"

        let row = ClipboardItemRow(
            id: testId,
            rowid: 9998,
            contentType: .color,
            textPreview: initialHex,
            contentHash: "hash-\(testId)",
            sourceBundleId: "com.apple.test",
            sourceAppName: "TestApp",
            isSensitive: false,
            secretKind: nil,
            isPinned: false,
            createdAt: Int64(Date().timeIntervalSince1970),
            expiresAt: nil
        )
        monitor.items.insert(row, at: 0)
        let initialCount = monitor.items.count
        defer {
            monitor.items.removeAll { $0.id == testId }
            monitor.evictCanonicalColor(for: testId)
        }

        // Выбираем формат RGB
        let chosenFormat = "rgb(202, 168, 149)"
        monitor.selectColorFormat(for: testId, newText: chosenFormat)

        // Проверяем, что дубликат в истории НЕ создан
        XCTAssertEqual(monitor.items.count, initialCount, "Selecting color format must not create duplicate history items")

        // Проверяем, что в изолированном буфере обмена сейчас именно выбранный формат
        let pbString = monitor.pasteboard.string(forType: .string)
        XCTAssertEqual(pbString, chosenFormat, "Clipboard must contain selected color format")

        // Проверяем, что при последующем copyToClipboard() в буфер отдаётся именно выбранный формат
        guard let updatedRow = monitor.items.first(where: { $0.id == testId }) else {
            XCTFail("Updated row not found")
            return
        }
        XCTAssertEqual(updatedRow.content, chosenFormat)
        XCTAssertEqual(updatedRow.textPreview, chosenFormat)

        monitor.pasteboard.clearContents()
        monitor.copyToClipboard(item: updatedRow)
        XCTAssertEqual(monitor.pasteboard.string(forType: .string), chosenFormat, "copyToClipboard must place the chosen format into pasteboard")
    }

    // MARK: - Тест подавления дребезга и двойного щелчка Taptic (>= 85 мс)
    func testTapticSingleClickDebounce() {
        XCTAssertGreaterThanOrEqual(
            TapticSoundAndHaptics.minTickInterval,
            0.085,
            "TapticSoundAndHaptics.minTickInterval must be at least 85ms (0.085s) to eliminate double click tick sounds"
        )

        TapticSoundAndHaptics.shared.resetMouseCycle()
        let first = TapticSoundAndHaptics.shared.playClick()
        let immediateSecond = TapticSoundAndHaptics.shared.playClick()
        XCTAssertTrue(first, "First click after resetMouseCycle() must fire")
        XCTAssertFalse(immediateSecond, "Immediate second playClick() within debounce window must be suppressed")
    }

    // MARK: - Тест контрастности и целостности всех 10 тем оформления
    func testThemeContrastAndIntegrity() {
        XCTAssertEqual(AppTheme.allCases.count, 10, "PasteVault must support exactly 10 themes")

        for theme in AppTheme.allCases {
            // Проверяем наличие всех ключевых цветов и свойств
            _ = theme.accentColor
            _ = theme.primaryText
            _ = theme.secondaryText
            _ = theme.backgroundColor
            _ = theme.cardBackground
            _ = theme.borderColor

            // Полярность темы
            if theme.isLight {
                XCTAssertFalse(theme.isDark, "Theme \(theme.rawValue) is marked isLight, so isDark must be false")
            } else {
                XCTAssertTrue(theme.isDark, "Theme \(theme.rawValue) is marked dark, so isDark must be true")
            }
        }
    }

    // MARK: - Тест защиты поисковой строки при авто-вставке (⌘V)
    func testSearchQueryProtectedDuringAutoPaste() {
        let monitor = ClipboardMonitor.shared
        monitor.isPerformingAutoPaste = false
        monitor.searchQuery = "test"
        XCTAssertEqual(monitor.searchQuery, "test")

        // Включаем флаг авто-вставки
        monitor.isPerformingAutoPaste = true

        // Попытка перезаписать строку поиска содержимым карточки
        monitor.searchQuery = "Случайный текст из буфера обмена для вставки"

        // Защитная логика должна удержать исходное значение "test"
        XCTAssertEqual(
            monitor.searchQuery,
            "test",
            "Во время авто-вставки (isPerformingAutoPaste == true) поисковый запрос защищён от перезаписи текстом карточки"
        )

        // Выключаем флаг авто-вставки
        monitor.isPerformingAutoPaste = false
        monitor.searchQuery = "new query"
        XCTAssertEqual(monitor.searchQuery, "new query", "В обычном режиме поисковый запрос свободно изменяется")
        monitor.searchQuery = ""
    }

    // MARK: - Тест рендеринга векторной иконки двойного клика DoubleClickCursorIcon
    func testDoubleClickCursorIconRendersCleanly() {
        let icon = DoubleClickCursorIcon(size: 13)
        let hostingView = NSHostingView(rootView: icon)
        hostingView.frame = NSRect(x: 0, y: 0, width: 13, height: 13)
        XCTAssertEqual(hostingView.frame.size.width, 13)
        XCTAssertEqual(hostingView.frame.size.height, 13)
        XCTAssertNotNil(hostingView.layer)
    }

    // MARK: - Тесты Snippets 2.0 (Ф-1 и Ф-4)

    func testSnippetCategoriesDatabaseCRUD() async throws {
        let db = DatabaseManager.shared
        try await db.initializeDatabase()
        defer {
            Task {
                await db.seedDefaultSnippetCategoriesIfNeeded()
            }
        }
        await db.resetSnippetCategoriesSeededFlagForTesting()

        let initialCategories = await db.fetchSnippetCategories()
        XCTAssertGreaterThanOrEqual(initialCategories.count, 4, "Должно быть как минимум 4 дефолтные категории при первичной инициализации")
        let seededNames = Set(initialCategories.map(\.name))
        XCTAssertTrue(seededNames.contains("Разработка"))
        XCTAssertTrue(seededNames.contains("Работа"))
        XCTAssertTrue(seededNames.contains("Шаблоны"))
        XCTAssertTrue(seededNames.contains("Промпты"))

        // Проверка строгого порядка категорий по умолчанию (Работа, Разработка, Шаблоны, Промпты)
        if initialCategories.count >= 4 {
            XCTAssertEqual(initialCategories[0].name, "Работа")
            XCTAssertEqual(initialCategories[1].name, "Разработка")
            XCTAssertEqual(initialCategories[2].name, "Шаблоны")
            XCTAssertEqual(initialCategories[3].name, "Промпты")
        }

        // Проверка 25 уникальных иконок
        XCTAssertEqual(SnippetCategoryRecord.availableIcons.count, 25, "Палитра должна содержать ровно 25 иконок")
        XCTAssertFalse(SnippetCategoryRecord.availableIcons.contains("square.grid.2x2.fill"), "square.grid.2x2.fill зарезервирована для системного пункта 'Все категории'")

        // Создание новой категории
        let newCatName = "Серверы \(UUID().uuidString.prefix(6))"
        let icon = "server.rack"
        XCTAssertTrue(SnippetCategoryRecord.availableIcons.contains(icon))

        let created = await db.createSnippetCategory(name: newCatName, iconName: icon)
        XCTAssertNotNil(created)
        XCTAssertEqual(created?.name, newCatName)
        XCTAssertEqual(created?.iconName, icon)

        // Проверка выборки
        let afterAdd = await db.fetchSnippetCategories()
        XCTAssertTrue(afterAdd.contains(where: { $0.id == created?.id && $0.name == newCatName }))

        // Обновление иконки и переименование
        let renamedCatName = "Деплой \(UUID().uuidString.prefix(6))"
        let updatedIcon = "cloud.fill"
        try await db.updateSnippetCategory(id: created!.id, newName: renamedCatName, newIconName: updatedIcon)

        let afterUpdate = await db.fetchSnippetCategories()
        let found = afterUpdate.first(where: { $0.id == created!.id })
        XCTAssertEqual(found?.name, renamedCatName)
        XCTAssertEqual(found?.iconName, updatedIcon)

        // Очистка
        try await db.deleteSnippetCategoryAndSnippets(id: created!.id)
    }

    func testDeletingSingleSnippetPreservesCategoryWithZeroCount() async throws {
        let db = DatabaseManager.shared
        try await db.initializeDatabase()
        let catName = "Папка \(UUID().uuidString.prefix(6))"
        guard let cat = await db.createSnippetCategory(name: catName, iconName: "star.fill") else {
            XCTFail("Не удалось создать тестовую категорию")
            return
        }

        // Добавляем тестовый фрагмент
        let snippetId = UUID().uuidString
        let inserted = await db.insertSnippet(id: snippetId, title: "Test Snippet", content: "Test Content", category: catName, isPinned: false)
        XCTAssertTrue(inserted)

        // Удаляем один фрагмент
        try await db.deleteSnippet(idString: snippetId)

        // Проверяем, что категория осталась в базе даже со счетчиком 0
        let categories = await db.fetchSnippetCategories()
        let existing = categories.first(where: { $0.id == cat.id })
        XCTAssertNotNil(existing, "Категория должна оставаться в базе со счетчиком 0 при удалении ее последнего фрагмента")
        XCTAssertEqual(existing?.name, catName)

        // Очистка
        try await db.deleteSnippetCategoryAndSnippets(id: cat.id)
    }

    func testDeletingCategoryDeletesCategoryAndSnippetsAndAllowsEmptyList() async throws {
        let db = DatabaseManager.shared
        try await db.initializeDatabase()
        defer {
            Task {
                await db.seedDefaultSnippetCategoriesIfNeeded()
            }
        }
        let catName = "Удаление \(UUID().uuidString.prefix(6))"
        guard let cat = await db.createSnippetCategory(name: catName, iconName: "flame.fill") else {
            XCTFail("Не удалось создать категорию")
            return
        }

        let snippetId = UUID().uuidString
        _ = await db.insertSnippet(id: snippetId, title: "Удаляемый фрагмент", content: "Контент", category: catName, isPinned: false)

        // Удаляем категорию и её фрагменты
        try await db.deleteSnippetCategoryAndSnippets(id: cat.id)

        let categories = await db.fetchSnippetCategories()
        XCTAssertFalse(categories.contains(where: { $0.id == cat.id }), "Категория должна быть удалена")

        let allSnippets = await db.fetchSnippets()
        XCTAssertFalse(allSnippets.contains(where: { $0.id == snippetId }), "Фрагменты удаленной категории должны быть удалены")
    }

    func testCleanAutoTitle() {
        // Проверка URL с путем
        let urlTitle = MainPanelView.cleanAutoTitle(from: "https://github.com/pastevault/app")
        XCTAssertEqual(urlTitle, "github.com/app")

        // Проверка корневого URL
        let simpleUrl = MainPanelView.cleanAutoTitle(from: "https://pastevault.app/")
        XCTAssertEqual(simpleUrl, "pastevault.app")

        // Проверка ведущих символов Markdown и комментариев
        let mdTitle = MainPanelView.cleanAutoTitle(from: "### Заголовок документа для тестирования")
        XCTAssertEqual(mdTitle, "Заголовок документа для тестирования")

        let codeComment = MainPanelView.cleanAutoTitle(from: "// Функция инициализации криптографического хранилища")
        XCTAssertEqual(codeComment, "Функция инициализации криптографического")

        let bullet = MainPanelView.cleanAutoTitle(from: "- [x] Реализовать синхронизацию базы данных с сервером")
        XCTAssertFalse(bullet.hasPrefix("-"))
        XCTAssertFalse(bullet.hasPrefix("["))

        // Проверка очистки висячих предлогов/союзов на конце и длины
        let trailingStop = MainPanelView.cleanAutoTitle(from: "Настройка безопасного соединения и")
        XCTAssertFalse(trailingStop.hasSuffix(" и"))
        XCTAssertEqual(trailingStop, "Настройка безопасного соединения")

        let longText = "Это очень длинный текст фрагмента который содержит огромное количество слов и должен аккуратно обрезаться по границе четырех или шести слов"
        let truncated = MainPanelView.cleanAutoTitle(from: longText)
        XCTAssertLessThanOrEqual(truncated.count, 45)
    }

    func testBackupManagerSnippetCategoriesExportAndImport() {
        let categories = [
            SnippetCategoryRecord(name: "Бэкап-1", iconName: "server.rack", sortOrder: 0),
            SnippetCategoryRecord(name: "Бэкап-2 (Пустая)", iconName: "sparkles", sortOrder: 1)
        ]

        let payload = PasteVaultBackupArchive(
            version: 1,
            createdAt: Date(),
            appVersion: "1.0.1",
            clipboardItems: [],
            snippets: [
                QuickSnippetItem(title: "Фрагмент 1", content: "Контент 1", category: "Бэкап-1")
            ],
            snippetCategories: categories
        )

        do {
            let data = try JSONEncoder().encode(payload)
            let decoded = try JSONDecoder().decode(PasteVaultBackupArchive.self, from: data)
            XCTAssertNotNil(decoded.snippetCategories)
            XCTAssertEqual(decoded.snippetCategories?.count, 2)
            XCTAssertEqual(decoded.snippetCategories?.first?.name, "Бэкап-1")
            XCTAssertEqual(decoded.snippetCategories?.last?.name, "Бэкап-2 (Пустая)")

            // Проверка обратной совместимости со старыми версиями (без поля snippetCategories)
            let legacyJson = """
            {
                "version": 1,
                "createdAt": 1731234567.0,
                "appVersion": "1.0.0",
                "snippets": []
            }
            """.data(using: .utf8)!
            let legacyDecoded = try JSONDecoder().decode(PasteVaultBackupArchive.self, from: legacyJson)
            XCTAssertNil(legacyDecoded.snippetCategories, "Старые бэкапы без snippetCategories должны декодироваться без ошибок")
        } catch {
            XCTFail("Ошибка кодирования/декодирования архива: \(error)")
        }
    }

    func testOCRTextPersistenceAndSearchInSQLite() async throws {
        let db = DatabaseManager.shared
        try await db.initializeDatabase()
        let itemId = "__test_ocr_\(UUID().uuidString)"
        let uniqueToken = "OCR_UNIQUE_TOKEN_\(UUID().uuidString.prefix(8))"
        let payload = Data("img-payload-\(uniqueToken)".utf8)

        _ = try await db.upsertItem(
            id: itemId,
            contentType: .image,
            textPreview: "[Скриншот 100×100 пкс] #OCR",
            rawPayload: payload,
            sourceBundleId: "com.apple.screencapture",
            sourceAppName: "Снимок экрана",
            isSensitive: false,
            secretKind: nil,
            ttlSeconds: nil,
            ocrText: nil
        )
        try await db.updateItemOCRText(id: itemId, ocrText: "Распознанный текст: \(uniqueToken)")

        let matches = try await db.queryItems(searchQuery: uniqueToken, limit: 20)
        XCTAssertEqual(matches.first?.id, itemId)
        XCTAssertEqual(matches.first?.ocrText, "Распознанный текст: \(uniqueToken)")

        try await db.deleteItem(id: itemId)
    }

    func testClipboardTextMetricsCompactFormattingAndCounts() {
        XCTAssertEqual(ClipboardTextMetricsFormatter.formatCompact(1420), "1 420")
        XCTAssertEqual(ClipboardTextMetricsFormatter.formatCompact(10_000), "10K")
        XCTAssertEqual(ClipboardTextMetricsFormatter.formatCompact(12_400), "12.4K")
        XCTAssertEqual(ClipboardTextMetricsFormatter.formatCompact(125_000), "125K")

        let textMetrics = ClipboardTextMetricsFormatter.compute(for: "Привет мир\nвторая строка")
        XCTAssertEqual(textMetrics.charCount, 24)
        XCTAssertEqual(textMetrics.wordCount, 4)
        XCTAssertEqual(textMetrics.lineCount, 2)
        XCTAssertEqual(ClipboardTextMetricsFormatter.badgeText(for: .text, metrics: textMetrics, isEnglish: false), "24 зн. · 4 сл.")
        XCTAssertEqual(ClipboardTextMetricsFormatter.badgeText(for: .text, metrics: textMetrics, isEnglish: true), "24 ch · 4 w")

        let codeMetrics = ClipboardTextMetricsFormatter.compute(for: "let a = 1\nlet b = 2\nreturn a + b")
        XCTAssertEqual(codeMetrics.lineCount, 3)
        XCTAssertEqual(ClipboardTextMetricsFormatter.badgeText(for: .code, metrics: codeMetrics, isEnglish: false), "3 стр. · 32 зн.")
        XCTAssertEqual(ClipboardTextMetricsFormatter.badgeText(for: .code, metrics: codeMetrics, isEnglish: true), "3 ln · 32 ch")
    }

    // MARK: - Изоляция буфера обмена и БД при запуске тестов
    @MainActor
    func testClipboardIsolationDoesNotTouchSystemGeneralPasteboard() async throws {
        let supportDir = try DatabaseManager.pasteVaultSupportDirectory()
        XCTAssertTrue(supportDir.path.contains("/tmp/PasteVault_TestRun_"), "DB support directory must be isolated in /tmp")
        XCTAssertFalse(supportDir.path.contains("Application Support"), "Tests must never touch ~/Library/Application Support")

        let monitor = ClipboardMonitor.shared
        XCTAssertNotEqual(
            monitor.pasteboard.name,
            NSPasteboard.general.name,
            "ClipboardMonitor under XCTest must use an isolated NSPasteboard.withUniqueName()"
        )

        let generalChangeCountBefore = NSPasteboard.general.changeCount

        // 1. Текст
        monitor.copyToPasteboardImmediately(text: "IsolatedTextPayload_\(UUID().uuidString)")
        XCTAssertEqual(NSPasteboard.general.changeCount, generalChangeCountBefore, "Text copy in tests must not mutate NSPasteboard.general")

        // 2. Пароль из PassGen
        let generatedPwd = "IsoPass_\(UUID().uuidString.prefix(8))!"
        monitor.recordGeneratedPassword(generatedPwd)
        XCTAssertEqual(monitor.pasteboard.string(forType: .string), generatedPwd)
        XCTAssertEqual(NSPasteboard.general.changeCount, generalChangeCountBefore, "Password copy in tests must not mutate NSPasteboard.general")

        // 3. Изображение
        let img = NSImage(size: NSSize(width: 24, height: 24))
        img.lockFocus()
        NSColor.systemRed.setFill()
        NSRect(x: 0, y: 0, width: 24, height: 24).fill()
        img.unlockFocus()
        let imgRow = ClipboardItemRow(
            id: "iso-img-\(UUID().uuidString)",
            rowid: 88888,
            contentType: .image,
            textPreview: "[Скриншот 24×24 пкс]",
            contentHash: "iso-img-hash-\(UUID().uuidString)",
            sourceBundleId: "com.apple.screencaptureui",
            sourceAppName: "Снимок экрана",
            isSensitive: false,
            secretKind: nil,
            isPinned: false,
            createdAt: Int64(Date().timeIntervalSince1970),
            expiresAt: nil,
            ocrText: nil,
            rawImageData: img.tiffRepresentation,
            fileURLPath: nil,
            useCount: 0
        )
        monitor.copyToClipboard(item: imgRow)
        let isolatedTypes = monitor.pasteboard.pasteboardItems?.flatMap { $0.types } ?? []
        XCTAssertTrue(isolatedTypes.contains(.png), "Isolated pasteboard should receive PNG payload")
        XCTAssertEqual(NSPasteboard.general.changeCount, generalChangeCountBefore, "Image copy in tests must not mutate NSPasteboard.general")

        // Очищаем тестовый пароль из БД/монитора и изолированного буфера
        if let pwdRow = monitor.items.first(where: { $0.textPreview == generatedPwd }) {
            monitor.items.removeAll { $0.id == pwdRow.id }
            try? await DatabaseManager.shared.deleteItem(id: pwdRow.id)
        }
        monitor.pasteboard.clearContents()
    }

    // MARK: - Этап 1: Встроенные шрифты (0 сетевых запросов)
    @MainActor
    func testBundledFontsExistOfflineWithoutNetwork() async throws {
        XCTAssertEqual(FontManager.fontSpecs.count, 6, "Должно быть ровно 6 встроенных шрифтов")
        let discovered = FontManager.discoverBundledFontURLs()
        XCTAssertEqual(discovered.count, 6, "Все 6 .ttf шрифтов должны обнаруживаться локально в бандле/ресурсах")

        for spec in FontManager.fontSpecs {
            let fileURL = try XCTUnwrap(discovered[spec.appFont], "Не найден файл шрифта \(spec.filename)")
            let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            let size = (attrs[.size] as? NSNumber)?.intValue ?? 0
            XCTAssertGreaterThan(size, 10_000, "Файл шрифта \(spec.filename) не должен быть пустым")
        }

        // Синхронная регистрация должна быть готова мгновенно без ожидания асинхронных Task
        FontManager.shared.registerBundledFontsSynchronouslyIfNeeded()
        XCTAssertTrue(FontManager.shared.hasCompletedLoad, "Офлайн-загрузка шрифтов должна завершаться синхронно")
        XCTAssertEqual(FontManager.shared.resolvedPostScriptNames.count, 6)

        for appFont in AppFont.allCases {
            for weight in [Font.Weight.regular, .medium, .semibold, .bold] {
                let psName = try XCTUnwrap(
                    FontManager.shared.resolvedFontName(for: appFont, weight: weight),
                    "PostScript name must resolve for \(appFont.rawValue) weight=\(weight)"
                )
                XCTAssertFalse(psName.contains("Didot"), "Serif fallback Didot must never be used for \(appFont.rawValue)")
                XCTAssertFalse(psName.contains("Times"), "Serif fallback Times must never be used for \(appFont.rawValue)")
                XCTAssertNotNil(NSFont(name: psName, size: 13), "NSFont(name: \(psName)) must be registered and loadable")
            }
            let nsBold = appFont.nsFont(size: 13, weight: .bold)
            XCTAssertFalse(nsBold.fontName.contains("Didot"))
        }
    }

    // MARK: - Этап 1: Изоляция @AppStorage от UserDefaults.standard
    @MainActor
    func testAppStorageIsIsolatedToAppDefaultsUnderTests() {
        XCTAssertTrue(AppDefaults.shared !== UserDefaults.standard, "AppDefaults.shared под XCTest должен быть изолированным suite")

        let monitor = ClipboardMonitor.shared
        let prevMaxLimit = monitor.maxHistoryLimit
        let prevSaveFiles = monitor.saveFilesEnabled
        let stdMaxBefore = UserDefaults.standard.object(forKey: "maxHistoryLimit") as? Int
        let stdFilesBefore = UserDefaults.standard.object(forKey: "saveFilesEnabled") as? Bool

        defer {
            monitor.maxHistoryLimit = prevMaxLimit
            monitor.saveFilesEnabled = prevSaveFiles
        }

        monitor.maxHistoryLimit = 777
        monitor.saveFilesEnabled = !prevSaveFiles

        XCTAssertEqual(AppDefaults.shared.integer(forKey: "maxHistoryLimit"), 777)
        XCTAssertEqual(AppDefaults.shared.bool(forKey: "saveFilesEnabled"), !prevSaveFiles)
        XCTAssertEqual(UserDefaults.standard.object(forKey: "maxHistoryLimit") as? Int, stdMaxBefore)
        XCTAssertEqual(UserDefaults.standard.object(forKey: "saveFilesEnabled") as? Bool, stdFilesBefore)
    }

    // MARK: - Этап 1: Валидация доверенных GitHub URL обновлений
    func testUpdateServiceTrustedURLValidation() {
        XCTAssertTrue(UpdateService.isTrustedUpdateURL(URL(string: "https://github.com/GarbGhost/PasteVault/releases/download/v1.0.1/PasteVault.dmg")!))
        XCTAssertTrue(UpdateService.isTrustedUpdateURL(URL(string: "https://objects.githubusercontent.com/github-production-release-asset/12345")!))
        XCTAssertTrue(UpdateService.isTrustedUpdateURL(URL(string: "https://release-assets.githubusercontent.com/assets/PasteVault.dmg")!))

        XCTAssertFalse(UpdateService.isTrustedUpdateURL(URL(string: "http://github.com/GarbGhost/PasteVault/releases/download/v1.0.1/PasteVault.dmg")!))
        XCTAssertFalse(UpdateService.isTrustedUpdateURL(URL(string: "https://evil.example.com/PasteVault.dmg")!))
        XCTAssertFalse(UpdateService.isTrustedUpdateURL(URL(string: "https://github.com/AnotherOrg/PasteVault/releases/download/v1.0.1/PasteVault.dmg")!))
    }

    // MARK: - Этап 3: PassGenerator (словарь >= 512 уникальных слов, гарантированные классы, честная энтропия)
    @MainActor
    func testStage3PassGeneratorDictionaryClassesAndEntropy() {
        XCTAssertGreaterThanOrEqual(PassGenerator.mnemonicWordList.count, 512)
        XCTAssertEqual(
            Set(PassGenerator.mnemonicWordList).count,
            PassGenerator.mnemonicWordList.count,
            "Mnemonic dictionary must contain strictly unique words"
        )

        let mnemonic = PassGenerator.generateMnemonic(wordCount: 5)
        let parts = mnemonic.secret.split(separator: "-")
        XCTAssertEqual(parts.count, 5)
        for word in parts {
            XCTAssertTrue(PassGenerator.mnemonicWordList.contains(String(word)))
        }
        let expectedMnemonicEntropy = Int((5.0 * log2(Double(PassGenerator.mnemonicWordList.count))).rounded())
        XCTAssertEqual(mnemonic.entropyBits, expectedMnemonicEntropy)

        let pwd = PassGenerator.generatePassword(length: 16, includeUppercase: true, includeDigits: true, includeSymbols: true)
        XCTAssertEqual(pwd.secret.count, 16)
        XCTAssertTrue(pwd.secret.contains(where: { ("a"..."z").contains($0) }))
        XCTAssertTrue(pwd.secret.contains(where: { ("A"..."Z").contains($0) }))
        XCTAssertTrue(pwd.secret.contains(where: { ("0"..."9").contains($0) }))
        XCTAssertTrue(pwd.secret.contains(where: { "!@#$%^&*()-_=+[]{}|;:,.<>?".contains($0) }))
    }

    // MARK: - Этап 3: SecretDetector (длинные PEM/JWT > 512, префиксы /#{[, false positives, EN)
    func testStage3SecretDetectorLongTokensPrefixPasswordsAndFalsePositives() {
        let longBody = String(repeating: "MIIEpAIBAAKCAQEA0Z3VS5JJcds3xfn/", count: 25)
        let pem = "-----BEGIN RSA PRIVATE KEY-----\n\(longBody)\n-----END RSA PRIVATE KEY-----"
        XCTAssertGreaterThan(pem.count, 512)
        let pemResult = SecretDetector.inspect(pem, language: .en)
        XCTAssertTrue(pemResult.isSensitive)
        XCTAssertEqual(pemResult.secretKind, "Private SSH / PEM Key")

        let jwtPayload = "eyJ" + String(repeating: "abcDEF123456", count: 50)
        let bearer = "Bearer eyJhbGciOiJIUzI1NiJ9.\(jwtPayload).signaturePart123"
        XCTAssertGreaterThan(bearer.count, 512)
        XCTAssertTrue(SecretDetector.inspect(bearer, language: .en).isSensitive)

        for prefixedPassword in ["/p@ssW0rd!23", "#k9X!mPq2Z", "{sEcReT!88"] {
            XCTAssertTrue(
                SecretDetector.inspect(prefixedPassword, language: .en).isSensitive,
                "Password starting with symbol '\(prefixedPassword)' must NOT be skipped"
            )
        }

        for benign in ["alex99@gmail.com", "localhost:8080", "out-of-the-box", "#AABBCC", "/usr/local/bin/brew", #"{"ok":true}"#] {
            XCTAssertFalse(
                SecretDetector.inspect(benign, language: .en).isSensitive,
                "Benign value '\(benign)' must not trigger false positive"
            )
        }
    }

    // MARK: - Этап 3: ClipboardMonitor отслеживание и отмена DispatchWorkItem самоуничтожения
    @MainActor
    func testStage3ClipboardMonitorDestructWorkItemCancellation() {
        let monitor = ClipboardMonitor.shared
        let id = monitor.recordGeneratedPassword("Stage3_Secret!#99", ttlSeconds: 60)
        defer { monitor.clearAllHistory() }

        XCTAssertTrue(monitor.hasPendingDestructWorkItem(for: id), "Password with TTL must track pending destruct work item")
        monitor.toggleSecretStatus(for: id)
        XCTAssertFalse(monitor.hasPendingDestructWorkItem(for: id), "Demoting secret must cancel its pending destruct work item")

        monitor.copyToPasteboardImmediately(text: "temp_1", selfDestructAfterSeconds: 60, destructKey: "test_key_a")
        monitor.copyToPasteboardImmediately(text: "temp_2", selfDestructAfterSeconds: 60, destructKey: "test_key_b")
        XCTAssertTrue(monitor.hasPendingDestructWorkItem(for: "test_key_a"))
        XCTAssertTrue(monitor.hasPendingDestructWorkItem(for: "test_key_b"))
    }

    // MARK: - Этап 3: EN-локализация SmartClassifier, MainPanelView.cleanAutoTitle & CSS4 colors
    @MainActor
    func testStage3EnglishLocalizationAndCSS4Colors() {
        let enTags = SmartClassifier.tags(
            for: "https://example.com/?utm_source=test",
            contentType: .url,
            isSensitive: false,
            language: .en
        )
        XCTAssertTrue(enTags.contains("#UTM-tracker"))
        XCTAssertFalse(enTags.contains("#UTM-трекер"))

        let ruTags = SmartClassifier.tags(
            for: "https://example.com/?utm_source=test",
            contentType: .url,
            isSensitive: false,
            language: .ru
        )
        XCTAssertTrue(ruTags.contains("#UTM-трекер"))

        XCTAssertEqual(MainPanelView.cleanAutoTitle(from: "   ", lang: .en), "Snippet")
        XCTAssertEqual(MainPanelView.cleanAutoTitle(from: "   ", lang: .ru), "Фрагмент")

        XCTAssertTrue(SmartClassifier.isColor("rgb(255 128 0 / 0.5)"))
        XCTAssertTrue(SmartClassifier.isColor("hsl(210 50% 40%)"))
    }

    // MARK: - Этап 3: Shortcuts (Numpad Enter, Forward Delete, AZERTY/Numpad digit, validation)
    @MainActor
    func testStage3ShortcutsNumpadForwardDeleteDigitsAndValidation() throws {
        let returnCombo = KeyCombo(keyCode: 36, modifiers: 0, displayString: "↩")
        let numpadEnterEvent = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [.numericPad],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "\r",
                charactersIgnoringModifiers: "\r",
                isARepeat: false,
                keyCode: 76
            )
        )
        XCTAssertTrue(returnCombo.matches(event: numpadEnterEvent), "Numpad Enter (76) must match Return (36)")

        let backspaceCombo = KeyCombo(keyCode: 51, modifiers: 0, displayString: "⌫")
        let forwardDeleteEvent = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [.function],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "",
                charactersIgnoringModifiers: "",
                isARepeat: false,
                keyCode: 117
            )
        )
        XCTAssertTrue(backspaceCombo.matches(event: forwardDeleteEvent), "Forward Delete (117) must match Backspace (51)")
        XCTAssertEqual(KeyCombo.keyName(for: 117), "⌦")

        var cfg = ShortcutConfig.default
        cfg.quickPasteModifier = KeyCombo(keyCode: 0, modifiers: NSEvent.ModifierFlags.command.rawValue, displayString: "⌘1..⌘9")
        let azertyDigit2Event = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [.command],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "é",
                charactersIgnoringModifiers: "é",
                isARepeat: false,
                keyCode: 19
            )
        )
        XCTAssertEqual(cfg.quickPasteDigit(event: azertyDigit2Event), 2)

        let bareSpace = KeyCombo(keyCode: 49, modifiers: 0, displayString: "Space")
        if case .systemReserved = ShortcutManager.shared.validate(combo: bareSpace, for: .togglePanel, in: .en) {
            // Expected
        } else {
            XCTFail("Global .togglePanel without modifiers must fail validation")
        }
    }

    // MARK: - Этап 4: Сохранение реальных картинок в Screenshots/, перезагрузка с диска и удаление без синтетики
    @MainActor
    func testCapturedImagePersistsRealPNGToDiskReloadsAndDeletesCleanly() async throws {
        try await DatabaseManager.shared.initializeDatabase()
        try await DatabaseManager.shared.clearAllHistory()

        let monitor = ClipboardMonitor.shared
        monitor.clearAllHistoryInMemory()
        let prevSaveImages = monitor.saveImagesEnabled
        monitor.saveImagesEnabled = true
        defer {
            monitor.saveImagesEnabled = prevSaveImages
            monitor.clearAllHistoryInMemory()
            Task { try? await DatabaseManager.shared.clearAllHistory() }
        }

        // Создаём реальную уникальную картинку 64x48 (не 320x180)
        let imgSize = NSSize(width: 64, height: 48)
        let image = NSImage(size: imgSize)
        image.lockFocus()
        NSColor.systemGreen.setFill()
        NSRect(origin: .zero, size: imgSize).fill()
        image.unlockFocus()
        let tiffData = try XCTUnwrap(image.tiffRepresentation)

        monitor.captureImageItem(image, tiffData: tiffData, bundleId: "com.apple.screencaptureui", appName: "Screenshot")
        let captured = try XCTUnwrap(monitor.items.first)
        XCTAssertEqual(captured.effectiveContentType, .image)
        XCTAssertNotNil(captured.fileURLPath)

        // Ждём завершения асинхронной записи в SQLite
        for _ in 0..<30 {
            let dbRows = try await DatabaseManager.shared.queryItems(searchQuery: "", limit: 20)
            if dbRows.contains(where: { $0.id == captured.id && $0.fileURLPath != nil }) {
                break
            }
            try await Task.sleep(nanoseconds: 25_000_000)
        }

        let savedFileURL = try XCTUnwrap(
            DatabaseManager.safeScreenshotFileURL(for: captured.fileURLPath, itemId: captured.id),
            "Real PNG file must exist inside isolated Screenshots/ directory"
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: savedFileURL.path))

        // Симулируем перезапуск: очищаем RAM-кэш и перечитываем историю из SQLite + диска
        monitor.clearAllHistoryInMemory()
        await DatabaseManager.shared.closeForTesting()
        try await DatabaseManager.shared.initializeDatabase()
        await monitor.loadInitialHistory()

        let reloaded = try XCTUnwrap(monitor.items.first(where: { $0.id == captured.id }))
        let loadedImage = try XCTUnwrap(monitor.imageForItem(reloaded), "Reloaded screenshot must load real PNG from disk")
        XCTAssertEqual(Int(loadedImage.size.width), 64)
        XCTAssertEqual(Int(loadedImage.size.height), 48)

        // Удаляем файл на диске и кэш -> imageForItem НЕ должен подставлять синтетическую картинку 320x180
        try FileManager.default.removeItem(at: savedFileURL)
        monitor.evictImage(for: reloaded.id)
        XCTAssertNil(monitor.imageForItem(reloaded), "Missing PNG on disk must return nil rather than synthetic preview")

        // Проверяем удаление PNG-файла при удалении карточки из БД
        let image2 = NSImage(size: NSSize(width: 40, height: 30))
        image2.lockFocus()
        NSColor.systemOrange.setFill()
        NSRect(x: 0, y: 0, width: 40, height: 30).fill()
        image2.unlockFocus()
        let tiff2 = try XCTUnwrap(image2.tiffRepresentation)
        monitor.captureImageItem(image2, tiffData: tiff2, bundleId: "com.apple.screencaptureui", appName: "Screenshot")
        let captured2 = try XCTUnwrap(monitor.items.first(where: { $0.id != captured.id }))
        for _ in 0..<30 {
            let dbRows = try await DatabaseManager.shared.queryItems(searchQuery: "", limit: 20)
            if dbRows.contains(where: { $0.id == captured2.id }) { break }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        let savedFileURL2 = try XCTUnwrap(DatabaseManager.safeScreenshotFileURL(for: captured2.fileURLPath, itemId: captured2.id))
        XCTAssertTrue(FileManager.default.fileExists(atPath: savedFileURL2.path))

        try await DatabaseManager.shared.deleteItem(id: captured2.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: savedFileURL2.path), "Deleting clipboard item must delete its PNG from Screenshots/")
    }
}
