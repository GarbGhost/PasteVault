import XCTest
@testable import PasteVault

final class CardFileExporterTests: XCTestCase {

    // MARK: - 1. Тесты формирования умного имени файла
    func testFileNameGenerationFromWords() {
        let content = "Заметка по проекту PasteVault\nВторая строка заметок"
        let nameDocx = CardFileExporter.defaultFileName(for: content, format: .docx)
        XCTAssertEqual(nameDocx, "Заметка_по_проекту.docx")

        let configContent = "Конфиг сервера базы данных\nport: 5432"
        let nameMd = CardFileExporter.defaultFileName(for: configContent, format: .md)
        XCTAssertEqual(nameMd, "Конфиг_сервера_базы.md")

        let singleWord = "SingleWord"
        let nameTxt = CardFileExporter.defaultFileName(for: singleWord, format: .txt)
        XCTAssertEqual(nameTxt, "SingleWord.txt")
    }

    func testFileNameCleansForbiddenCharacters() {
        let dirty = "File: name? with / and \\ and * and <tag> | pipe \"quoted\" %percent"
        let cleanedName = CardFileExporter.defaultFileName(for: dirty, format: .md)
        XCTAssertFalse(cleanedName.contains(":"))
        XCTAssertFalse(cleanedName.contains("/"))
        XCTAssertFalse(cleanedName.contains("\\"))
        XCTAssertFalse(cleanedName.contains("?"))
        XCTAssertFalse(cleanedName.contains("%"))
        XCTAssertFalse(cleanedName.contains("*"))
        XCTAssertFalse(cleanedName.contains("|"))
        XCTAssertFalse(cleanedName.contains("\""))
        XCTAssertFalse(cleanedName.contains("<"))
        XCTAssertFalse(cleanedName.contains(">"))
        XCTAssertTrue(cleanedName.hasSuffix(".md"))
    }

    func testFileNameFallbackOnEmptyOrSpecialChars() {
        let empty = ""
        let fixedDate = Date(timeIntervalSince1970: 1731220000)
        let nameEmpty = CardFileExporter.defaultFileName(for: empty, format: .txt, date: fixedDate)
        XCTAssertTrue(nameEmpty.hasPrefix("PasteVault_"))
        XCTAssertTrue(nameEmpty.hasSuffix(".txt"))

        let onlySymbols = ":::////???***%%%"
        let nameSymbols = CardFileExporter.defaultFileName(for: onlySymbols, format: .swift, date: fixedDate)
        XCTAssertTrue(nameSymbols.hasPrefix("PasteVault_"))
        XCTAssertTrue(nameSymbols.hasSuffix(".swift"))

        let leadingEmptyLines = "\n   \n\nПервая непустая строка"
        let nameLeading = CardFileExporter.defaultFileName(for: leadingEmptyLines, format: .txt)
        XCTAssertEqual(nameLeading, "Первая_непустая_строка.txt")
    }

    // MARK: - 2. Тест генерации валидного .docx (OOXML с сигнатурой PK)
    func testDocxDataGenerationValidZipSignature() throws {
        let text = "Тестовый документ для экспорта в Microsoft Word из PasteVault."
        let data = try CardFileExporter.generateExportData(from: text, format: .docx, isCode: false)

        XCTAssertFalse(data.isEmpty, "Data .docx не должна быть пустой")
        XCTAssertGreaterThan(data.count, 100, "Размер валидного .docx должен быть больше 100 байт")

        // Сигнатура ZIP / OOXML: байты 0x50, 0x4B ('PK')
        let prefix = data.prefix(2)
        let pkSignature = Data([0x50, 0x4B])
        XCTAssertEqual(prefix, pkSignature, "Файл .docx должен иметь валидный ZIP-заголовок 'PK'")

        // Проверка для режима кода
        let codeText = "func helloWorld() { print(\"Hello\") }"
        let codeData = try CardFileExporter.generateExportData(from: codeText, format: .docx, isCode: true)
        XCTAssertEqual(codeData.prefix(2), pkSignature, "Файл .docx для кода должен иметь валидный ZIP-заголовок 'PK'")
    }

    // MARK: - 3. Тест экспорта текстовых и кодовых форматов (.txt, .conf, .json, .swift, .py, .md, .sh, .js)
    func testTextFormatsDataGeneration() throws {
        let sampleContent = "let greeting = \"Hello PasteVault v1.0.1\""
        let formats: [CardExportFormat] = [.txt, .conf, .json, .swift, .py, .md, .sh, .js]

        for fmt in formats {
            let data = try CardFileExporter.generateExportData(from: sampleContent, format: fmt)
            XCTAssertEqual(
                data,
                Data(sampleContent.utf8),
                "Формат .\(fmt.extensionName) должен сохранять точные UTF-8 байты"
            )
        }
    }

    // MARK: - 3b. Тест экспорта в формат .conf (UTF-8)
    func testConfFormatExportUTF8() throws {
        let confContent = """
        [Server]
        Address = 192.168.1.1
        Port = 8080
        """
        let data = try CardFileExporter.generateExportData(from: confContent, format: .conf)
        XCTAssertEqual(data, Data(confContent.utf8), "Формат .conf должен сохранять чистый UTF-8 текст")
    }

    // MARK: - 3c. Тест умного именования файлов для кодовых форматов (.conf, .json, .sh, .swift, .py, .js)
    func testSmartFileNameGenerationForCodeFormats() {
        // 1. Config с секцией [Server] -> server.conf
        let configSample = "[Server]\nAddress = 10.0.0.1\nPort = 8080"
        let confName = CardFileExporter.defaultFileName(for: configSample, format: .conf)
        XCTAssertEqual(confName, "server.conf")

        // 1a. Config с общей секцией [General] -> config.conf
        let configGeneralSample = "[General]\nAddress = 10.0.0.1\nPort = 8080"
        let confGeneralName = CardFileExporter.defaultFileName(for: configGeneralSample, format: .conf)
        XCTAssertEqual(confGeneralName, "config.conf")

        // 1b. Config с комментарием -> имя из первой секции [Interface], игнорируя комментарии
        let configCommentSample = "# Network Cluster Node\n[Interface]\nAddress = 10.0.0.2"
        let confCommentName = CardFileExporter.defaultFileName(for: configCommentSample, format: .conf)
        XCTAssertEqual(confCommentName, "interface.conf")

        // 2. JSON, начинающийся с {\n "server": "local" -> server.json
        let jsonSample = "{\n  \"server\": \"local\",\n  \"port\": 5432\n}"
        let jsonName = CardFileExporter.defaultFileName(for: jsonSample, format: .json)
        XCTAssertEqual(jsonName, "server.json")

        // 2b. JSON пустой объект {} -> config.json
        let jsonEmptyObj = "{\n}"
        let jsonEmptyName = CardFileExporter.defaultFileName(for: jsonEmptyObj, format: .json)
        XCTAssertEqual(jsonEmptyName, "config.json")

        // 3. Shell-скрипт с #!/bin/bash и комментариями -> пропуск шебанга и комментариев, fallback script.sh
        let shSample = "#!/bin/bash\n# Deploy Application Node\n./run.sh"
        let shName = CardFileExporter.defaultFileName(for: shSample, format: .sh)
        XCTAssertEqual(shName, "script.sh")

        // 3b. Shell-скрипт без функций -> script.sh
        let shDirectCmd = "#!/bin/sh\nexec python3 app.py"
        let shCmdName = CardFileExporter.defaultFileName(for: shDirectCmd, format: .sh)
        XCTAssertEqual(shCmdName, "script.sh")

        // 3c. Shell-скрипт с объявлением функции deploy_prod() -> deploy_prod.sh
        let shFunc = "#!/bin/bash\ndeploy_prod() {\n  echo 'Deploying'\n}"
        let shFuncName = CardFileExporter.defaultFileName(for: shFunc, format: .sh)
        XCTAssertEqual(shFuncName, "deploy_prod.sh")

        // 4. Swift с struct
        let swiftSample = "import SwiftUI\n\nstruct UserManager: View {\n  var body: some View { Text(\"Hi\") }\n}"
        let swiftName = CardFileExporter.defaultFileName(for: swiftSample, format: .swift)
        XCTAssertEqual(swiftName, "UserManager.swift")

        // 5. Python с def
        let pySample = "# Processing utility\ndef parse_data(raw_input):\n    return raw_input.strip()"
        let pyName = CardFileExporter.defaultFileName(for: pySample, format: .py)
        XCTAssertEqual(pyName, "parse_data.py")

        // 6. JavaScript с function
        let jsSample = "function loadConfig() {\n  return { ok: true };\n}"
        let jsName = CardFileExporter.defaultFileName(for: jsSample, format: .js)
        XCTAssertEqual(jsName, "loadConfig.js")
    }

    // MARK: - 3d. Тест классификации конфигурационного текста как .code в SmartClassifier
    func testConfigFileClassifiedAsCode() {
        let confSample = """
        [Server]
        Address = 10.0.0.1
        Port = 9000
        """
        XCTAssertTrue(SmartClassifier.isConfigFile(confSample), "Текст с секцией [...] и key = value должен распознаваться как конфиг")
        let kind = SmartClassifier.classify(text: confSample, isSensitive: false, isImage: false)
        XCTAssertEqual(kind, .code, "Конфигурационный файл должен классифицироваться как .code")

        let rec = CardFileExporter.recommendedFormat(for: confSample)
        XCTAssertEqual(rec, .conf, "Для конфигурационного файла рекомендуемым форматом должен быть .conf")
    }

    // MARK: - 4. Тест защиты от двойного щелчка в TapticSoundAndHaptics (debounce 250 мс и One-Click-Per-MouseDown Gate)
    func testTapticSingleClickDebounceWindow() {
        XCTAssertEqual(
            TapticSoundAndHaptics.clickDebounceInterval,
            0.25,
            "clickDebounceInterval должен быть равен 250 мс (0.25 с)"
        )
        XCTAssertEqual(
            TapticSoundAndHaptics.wheelTickInterval,
            0.035,
            "wheelTickInterval должен быть равен 35 мс (0.035 с)"
        )
        XCTAssertGreaterThanOrEqual(
            TapticSoundAndHaptics.minTickInterval,
            0.085,
            "minTickInterval должен быть >= 0.085 для обратной совместимости"
        )

        TapticSoundAndHaptics.shared.resetMouseCycle()

        // Первый вызов
        let first = TapticSoundAndHaptics.shared.playClick()
        // Немедленный повторный вызов (интервал ~0 мс < 250 мс) должен быть подавлен
        let secondImmediate = TapticSoundAndHaptics.shared.playClick()

        XCTAssertTrue(first, "Первый вызов playClick() должен успешно выполниться")
        XCTAssertFalse(secondImmediate, "Второй вызов playClick() в окне < 250 мс должен быть подавлен")
    }

    // MARK: - 5. Тест физической мыши с задержкой 200 мс между mouseDown и mouseUp (One-Click-Per-MouseDown Gate)
    func testPhysicalMouseHold200msProducesStrictlySingleClick() {
        TapticSoundAndHaptics.shared.resetMouseCycle()

        // 1. Симулируем физическое нажатие кнопки мыши (mouseDown)
        TapticSoundAndHaptics.shared.simulateMouseDown()

        // 2. Первый щелчок срабатывает (например, в ButtonStyle при нажатии)
        let firstClick = TapticSoundAndHaptics.shared.playClick()
        XCTAssertTrue(firstClick, "Первый щелчок при нажатии кнопки мыши должен успешно воспроизвестись")

        // 3. Пользователь удерживает кнопку мыши 200 мс (типичное удержание на физической мыши)
        Thread.sleep(forTimeInterval: 0.20)

        // 4. Симулируем физическое отпускание кнопки мыши (mouseUp)
        TapticSoundAndHaptics.shared.simulateMouseUp()

        // 5. В action кнопки на отпускании мыши вызывается playClick()
        let secondClickOnMouseUp = TapticSoundAndHaptics.shared.playClick()
        XCTAssertFalse(
            secondClickOnMouseUp,
            "Повторный щелчок на отпускании мыши (через 200 мс) должен быть строго заблокирован гейтом One-Click-Per-MouseDown Gate"
        )
    }

    // MARK: - 6. Тест очистки описания релиза для попапа обновления (formattedPopupReleaseNotes)
    func testFormattedPopupReleaseNotesCleansMarkdownAndRemovesInstallation() {
        let rawRelease = """
        Вышел PasteVault 1.0.1. В этом обновлении мы добавили быстрый экспорт карточек текста и кода в файлы разных форматов прямо из окна предпросмотра.

        ### ✨ Новое

        💾 **Быстрый экспорт карточек в файл.** В правом инспекторе рядом с кнопкой «Редактировать» появилась кнопка **«Сохранить»** с выбором из 8 форматов (`.docx`, `.txt`, `.json`, `.swift`, `.py`, `.md`, `.sh`, `.js`) и автоматической подстановкой имени файла из первых слов текста.

        ### 📦 Установка

        Перетащите **Paste Vault** в папку **Applications**...
        """

        let formatted = UpdateService.formattedPopupReleaseNotes(from: rawRelease)
        XCTAssertFalse(formatted.contains("### 📦 Установка"))
        XCTAssertFalse(formatted.contains("Перетащите"))
        XCTAssertFalse(formatted.contains("**"))
        XCTAssertFalse(formatted.contains("`"))
        XCTAssertTrue(formatted.hasPrefix("• "))
        XCTAssertTrue(formatted.contains("Быстрый экспорт карточек в файл."))
    }

    // MARK: - 7. Тест сравнения версий UpdateService (1.0.1 новее 1.0.0)
    @MainActor
    func testUpdateServiceVersion101NewerThan100() {
        XCTAssertTrue(
            UpdateService.isVersion("1.0.1", newerThan: "1.0.0"),
            "Версия 1.0.1 должна определяться как более новая, чем 1.0.0"
        )
        XCTAssertTrue(
            UpdateService.isVersion("v1.0.1", newerThan: "v1.0.0"),
            "Версия v1.0.1 с префиксом 'v' должна быть новее v1.0.0"
        )
        XCTAssertFalse(
            UpdateService.isVersion("1.0.0", newerThan: "1.0.1"),
            "Версия 1.0.0 не должна определяться как более новая, чем 1.0.1"
        )
        XCTAssertEqual(
            UpdateService.shared.currentVersion,
            "1.0.1",
            "Текущая версия приложения в UpdateService должна быть 1.0.1"
        )
    }

    // MARK: - 8. Тест классификации русского отчёта с упоминанием функций как .text
    func testRussianMultiLineReportWithCodeMentionsClassifiedAsText() {
        let russianReport = """
        Отчёт о тестировании PasteVault
        В TapticSoundAndHaptics внедрить аппаратный гейт для физической мыши:
        1. Монитор событий NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp])
        2. Проверка состояния кнопок через NSEvent.pressedMouseButtons & 1 != 0
        3. Метод playClick() теперь вызывается строго один раз за нажатие
        Все автоматические тесты завершились успешно.
        """
        let kind = SmartClassifier.classify(text: russianReport, isSensitive: false, isImage: false)
        XCTAssertEqual(kind, .text, "Русский отчёт с упоминанием функций и выражений кода должен классифицироваться как .text, а НЕ .code")
    }

    // MARK: - 9. Тест классификации английского отчёта с упоминанием функций как .text
    func testEnglishMultiLineArticleWithCodeMentionsClassifiedAsText() {
        let englishArticle = """
        Release testing report for PasteVault
        We verified that NSEvent.pressedMouseButtons != 0 correctly filters double clicks on physical mice.
        In addition, the function func playClick() is now called strictly once per mouse down event.
        All 62 unit tests passed with zero failures on macOS Sonoma and Sequoia.
        """
        let kind = SmartClassifier.classify(text: englishArticle, isSensitive: false, isImage: false)
        XCTAssertEqual(kind, .text, "Английский отчёт из обычных предложений с упоминанием кода должен классифицироваться как .text, а НЕ .code")
    }

    // MARK: - 10. Тест классификации настоящего кода (Swift, Python, JS, JSON, .conf) как .code
    func testRealCodeAndConfigSnippetsClassifiedAsCode() {
        // Swift
        let swiftCode = """
        import SwiftUI

        struct ContentView: View {
            @State private var counter = 0

            func increment() {
                counter += 1
            }

            var body: some View {
                Text("\\(counter)")
            }
        }
        """
        XCTAssertEqual(SmartClassifier.classify(text: swiftCode, isSensitive: false), .code, "Настоящий Swift-код должен классифицироваться как .code")

        // Python
        let pythonCode = """
        def fetch_records(limit=100):
            records = []
            for item in get_items():
                if item.is_active:
                    records.append(item.data)
            return records
        """
        XCTAssertEqual(SmartClassifier.classify(text: pythonCode, isSensitive: false), .code, "Настоящий Python-код должен классифицироваться как .code")

        // JavaScript
        let jsCode = """
        function setupEventListener() {
            const btn = document.getElementById("action-btn");
            btn.addEventListener("click", () => {
                console.log("Button clicked");
            });
            return true;
        }
        """
        XCTAssertEqual(SmartClassifier.classify(text: jsCode, isSensitive: false), .code, "Настоящий JavaScript-код должен классифицироваться как .code")

        // JSON
        let jsonSample = """
        {
          "name": "PasteVault",
          "version": "1.0.1",
          "offline": true
        }
        """
        XCTAssertEqual(SmartClassifier.classify(text: jsonSample, isSensitive: false), .code, "Валидный JSON должен классифицироваться как .code")

        // .conf
        let confSample = """
        [Interface]
        Address = 10.0.0.1/24
        Port = 51820
        """
        XCTAssertEqual(SmartClassifier.classify(text: confSample, isSensitive: false), .code, "Конфигурационный файл .conf должен классифицироваться как .code")
    }

    // MARK: - 11. Тест рекомендуемого формата для обычного текста (.txt)
    func testRecommendedFormatForPlainTextIsTxt() {
        let plainRussian = "Обычный связный текст на русском языке без сложной маркдаун-разметки."
        XCTAssertEqual(
            CardFileExporter.recommendedFormat(for: plainRussian),
            .txt,
            "Для обычного русского текста без маркдауна должен рекомендоваться .txt"
        )

        let plainEnglish = "Just a regular English paragraph without markdown tables, code blocks, or tasks."
        XCTAssertEqual(
            CardFileExporter.recommendedFormat(for: plainEnglish),
            .txt,
            "Для обычного английского текста должен рекомендоваться .txt"
        )

        // Текст с заголовком Markdown и списком задач -> .md
        let markdownDoc = """
        # Roadmap Project
        - [ ] Task 1
        - [x] Task 2
        """
        XCTAssertEqual(
            CardFileExporter.recommendedFormat(for: markdownDoc),
            .md,
            "Для текста с Markdown структурой должен рекомендоваться .md"
        )
    }

    // MARK: - 12. Тест: кодовые форматы никогда не используют кириллицу или '#' из комментариев
    func testCodeFormatsNeverUseCyrillicOrHashFromComments() {
        let sample = """
        # Настройки сервера и маршрутизации
        [Server_Settings]
        host = 192.168.1.100
        """

        let confName = CardFileExporter.defaultFileName(for: sample, format: .conf)
        XCTAssertEqual(confName, "server_settings.conf", ".conf должен брать имя секции [Server_Settings]")

        let jsonName = CardFileExporter.defaultFileName(for: sample, format: .json)
        XCTAssertEqual(jsonName, "config.json", ".json должен использовать fallback config.json")

        let swiftName = CardFileExporter.defaultFileName(for: sample, format: .swift)
        XCTAssertEqual(swiftName, "Snippet.swift", ".swift должен использовать fallback Snippet.swift")

        let pyName = CardFileExporter.defaultFileName(for: sample, format: .py)
        XCTAssertEqual(pyName, "script.py", ".py должен использовать fallback script.py")

        let shName = CardFileExporter.defaultFileName(for: sample, format: .sh)
        XCTAssertEqual(shName, "script.sh", ".sh должен использовать fallback script.sh")

        let jsName = CardFileExporter.defaultFileName(for: sample, format: .js)
        XCTAssertEqual(jsName, "script.js", ".js должен использовать fallback script.js")

        // Проверяем, что ни в одном кодовом имени нет знака '#' или русских букв
        for name in [confName, jsonName, swiftName, pyName, shName, jsName] {
            XCTAssertFalse(name.contains("#"), "Имя файла \(name) не должно содержать знак '#'")
            let hasCyrillic = name.unicodeScalars.contains { scalar in
                (0x0400...0x04FF).contains(scalar.value)
            }
            XCTAssertFalse(hasCyrillic, "Имя файла \(name) не должно содержать кириллицу")
        }
    }

    // MARK: - 13. Тест: текстовые форматы отсекают '#' и висячие предлоги
    func testTextFormatsStripHashAndTrailingPrepositions() {
        let sample = "# Настройки сервера и маршрутизации"

        let txtName = CardFileExporter.defaultFileName(for: sample, format: .txt)
        XCTAssertEqual(txtName, "Настройки_сервера.txt", "Висячий предлог 'и' должен быть отсечен, а '#' удален")

        let docxName = CardFileExporter.defaultFileName(for: sample, format: .docx)
        XCTAssertEqual(docxName, "Настройки_сервера.docx", "Висячий предлог 'и' должен быть отсечен для .docx")

        let mdName = CardFileExporter.defaultFileName(for: sample, format: .md)
        XCTAssertEqual(mdName, "Настройки_сервера.md", "Висячий предлог 'и' должен быть отсечен для .md")
    }

    // MARK: - 14. Тест: имена файлов не классифицируются как пароли (SecretDetector)
    func testFileNamesAreNotClassifiedAsSecrets() {
        let fileNames = [
            "Настройки_сервера_и.conf",
            "server_settings.conf",
            "PasteVault_v1.0.1_Universal.dmg",
            "config.json"
        ]

        for fileName in fileNames {
            let secretResult = SecretDetector.inspect(fileName)
            XCTAssertFalse(
                secretResult.isSensitive,
                "Имя файла '\(fileName)' не должно определяться как пароль/секрет"
            )
            let kind = SmartClassifier.classify(text: fileName, isSensitive: false)
            XCTAssertNotEqual(
                kind,
                .secret,
                "Имя файла '\(fileName)' не должно иметь категорию .secret"
            )
        }
    }

    // MARK: - 15. Тест: сохранение большого документа из 20 секций (> 25 000 символов)
    func testLarge20ItemRoadmapStoredCompletely() {
        var sections: [String] = []
        for i in 1...20 {
            let body = String(repeating: "Детальное описание пункта \(i) дорожной карты развития архитектуры PasteVault. ", count: 25)
            sections.append("### \(i). Раздел номер \(i)\n\n\(body)\n")
        }
        let largeRoadmap = sections.joined(separator: "\n---\n\n")

        XCTAssertGreaterThan(largeRoadmap.count, 25_000, "Тестовый документ должен быть длиннее 25 000 символов")

        let item = ClipboardItemRow(
            id: UUID().uuidString,
            rowid: 1,
            contentType: .text,
            textPreview: largeRoadmap,
            contentHash: "hash-roadmap-test",
            sourceBundleId: "com.apple.dt.Xcode",
            sourceAppName: "Xcode",
            isSensitive: false,
            secretKind: nil,
            isPinned: false,
            createdAt: Int64(Date().timeIntervalSince1970),
            expiresAt: nil
        )

        XCTAssertEqual(item.textPreview.count, largeRoadmap.count, "Длина сохранённого контента должна в точности совпадать")
        XCTAssertTrue(item.textPreview.contains("### 19. Раздел номер 19"), "Документ должен содержать пункт 19 без усечения")
        XCTAssertTrue(item.textPreview.contains("### 20. Раздел номер 20"), "Документ должен содержать пункт 20 без усечения")
    }
}
