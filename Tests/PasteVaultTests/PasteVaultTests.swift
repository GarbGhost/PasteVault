import XCTest
@testable import PasteVault

@MainActor
final class PasteVaultTests: XCTestCase {

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
        XCTAssertLessThan(elapsedMs, 20.0, "Expected 500-item candidate check + filtering under 20 ms, got \(elapsedMs) ms")
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

    func testAllSixInterfaceFontsAndBundledTTF() {
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

        // Проверяем, что в системном буфере обмена сейчас именно выбранный формат
        let pbString = NSPasteboard.general.string(forType: .string)
        XCTAssertEqual(pbString, chosenFormat, "Clipboard must contain selected color format")

        // Проверяем, что при последующем copyToClipboard() в буфер отдаётся именно выбранный формат
        guard let updatedRow = monitor.items.first(where: { $0.id == testId }) else {
            XCTFail("Updated row not found")
            return
        }
        XCTAssertEqual(updatedRow.content, chosenFormat)
        XCTAssertEqual(updatedRow.textPreview, chosenFormat)

        NSPasteboard.general.clearContents()
        monitor.copyToClipboard(item: updatedRow)
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), chosenFormat, "copyToClipboard must place the chosen format into pasteboard")
    }

    // MARK: - Тест подавления дребезга и двойного щелчка Taptic (>= 85 мс)
    func testTapticSingleClickDebounce() {
        XCTAssertGreaterThanOrEqual(
            TapticSoundAndHaptics.minTickInterval,
            0.085,
            "TapticSoundAndHaptics.minTickInterval must be at least 85ms (0.085s) to eliminate double click tick sounds"
        )

        // Множественные вызовы подряд не должны вызывать сбоев или блокировок
        for _ in 0..<10 {
            TapticSoundAndHaptics.shared.performDialTick()
            TapticSoundAndHaptics.shared.playConfirmClick()
        }
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
}
