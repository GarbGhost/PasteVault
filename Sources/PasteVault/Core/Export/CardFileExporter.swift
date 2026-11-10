import Foundation
import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Supported Card Export Formats

public enum CardExportFormat: String, CaseIterable, Identifiable, Sendable {
    case docx
    case txt
    case conf
    case json
    case swift
    case py
    case md
    case sh
    case js

    public var id: String { rawValue }

    public var extensionName: String { rawValue }

    public func title(in language: AppLanguage = .current) -> String {
        switch self {
        case .docx:
            return language == .en ? ".docx (Word Document)" : ".docx (Документ Word)"
        case .txt:
            return language == .en ? ".txt (Text File)" : ".txt (Текстовый файл)"
        case .conf:
            return language == .en ? ".conf (Config)" : ".conf (Конфигурация)"
        case .json:
            return ".json (JSON)"
        case .swift:
            return ".swift (Swift)"
        case .py:
            return ".py (Python)"
        case .md:
            return ".md (Markdown)"
        case .sh:
            return language == .en ? ".sh (Shell Script)" : ".sh (Shell-скрипт)"
        case .js:
            return ".js (JavaScript)"
        }
    }

    public var iconName: String {
        switch self {
        case .docx: return "doc.richtext"
        case .txt: return "doc.plaintext"
        case .conf: return "gearshape"
        case .json: return "curlybraces"
        case .swift: return "swift"
        case .py: return "chevron.left.forwardslash.chevron.right"
        case .md: return "text.badge.checkmark"
        case .sh: return "terminal"
        case .js: return "applescript"
        }
    }
}

// MARK: - Card File Exporter Core Logic

public struct CardFileExporter {
    private static let forbiddenChars = CharacterSet(charactersIn: ":/\\?%*|\"<>")

    /// Проверяет, является ли строка валидным латинским программным идентификатором:
    /// Длина 2...40 символов, начинается с буквы (A-Z, a-z), содержит только латинские буквы, цифры и "_"
    public static func isValidAsciiIdentifier(_ s: String) -> Bool {
        guard s.count >= 2 && s.count <= 40 else { return false }
        guard let first = s.first, (first >= "A" && first <= "Z") || (first >= "a" && first <= "z") else {
            return false
        }
        for ch in s {
            let isLetter = (ch >= "A" && ch <= "Z") || (ch >= "a" && ch <= "z")
            let isDigit = ch >= "0" && ch <= "9"
            let isUnderscore = (ch == "_")
            if !isLetter && !isDigit && !isUnderscore {
                return false
            }
        }
        return true
    }

    /// Преобразует строку в чистый snake_case в нижнем регистре
    private static func toSnakeCase(_ s: String) -> String {
        var result = ""
        for (i, ch) in s.enumerated() {
            if ch.isUppercase {
                if i > 0 && !result.hasSuffix("_") {
                    result.append("_")
                }
                result.append(ch.lowercased())
            } else {
                result.append(ch.lowercased())
            }
        }
        return result.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    /// Формирует эталонное имя файла по умолчанию:
    /// - ГРУППА А (6 кодовых форматов .conf, .json, .swift, .py, .sh, .js): строго латиница [A-Za-z0-9_-], без кириллицы и без знака "#"
    /// - ГРУППА Б (3 текстовых формата .txt, .docx, .md): срез первых 3 слов с очисткой знака "#", номеров списков и отсечением висячих союзов/предлогов
    public static func defaultFileName(for content: String, format: CardExportFormat, date: Date = Date()) -> String {
        let lines = content.components(separatedBy: .newlines)
        let nonEmpties = lines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm"
        let fallbackTimestamp = "PasteVault_\(formatter.string(from: date))"

        guard !nonEmpties.isEmpty else {
            return "\(fallbackTimestamp).\(format.extensionName)"
        }

        let trimmedAll = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedAll.isEmpty && trimmedAll.allSatisfy({ ":/?*!@$%^&+=|~`\\; \t\n\r".contains($0) }) {
            return "\(fallbackTimestamp).\(format.extensionName)"
        }

        switch format {
        // MARK: - ГРУППА А: 6 ПРОГРАММНЫХ И ТЕХНИЧЕСКИХ ФОРМАТОВ
        case .conf:
            let genericConfSections: Set<String> = [
                "general", "rule", "rules", "proxy", "proxy group", "host", "mitm", "url rewrite",
                "script", "main", "default", "settings", "config", "common", "global"
            ]
            var confName = "config"
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("#") || trimmed.hasPrefix(";") || trimmed.hasPrefix("//") || trimmed.hasPrefix("/*") || trimmed.hasPrefix("*") {
                    continue
                }
                if trimmed.hasPrefix("[") && trimmed.contains("]") {
                    if let endIdx = trimmed.firstIndex(of: "]") {
                        let inside = String(trimmed[trimmed.index(after: trimmed.startIndex)..<endIdx]).trimmingCharacters(in: .whitespaces)
                        let lower = inside.lowercased()
                        let isPureAscii = inside.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }
                        if isPureAscii && !genericConfSections.contains(lower) && !inside.isEmpty {
                            let snake = toSnakeCase(inside)
                            if !snake.isEmpty {
                                confName = snake
                                break
                            }
                        }
                    }
                }
            }
            return "\(confName).conf"

        case .json:
            var jsonName = "config"
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("#") || trimmed.hasPrefix("//") || trimmed.hasPrefix("/*") || trimmed.hasPrefix("*") {
                    continue
                }
                if let quoteStart = trimmed.firstIndex(of: "\"") {
                    let afterFirst = trimmed.index(after: quoteStart)
                    if let quoteEnd = trimmed[afterFirst...].firstIndex(of: "\"") {
                        let keyCandidate = String(trimmed[afterFirst..<quoteEnd]).trimmingCharacters(in: .whitespaces)
                        let rest = trimmed[trimmed.index(after: quoteEnd)...].trimmingCharacters(in: .whitespaces)
                        if rest.hasPrefix(":") {
                            let isAsciiKey = keyCandidate.allSatisfy { ($0 >= "A" && $0 <= "Z") || ($0 >= "a" && $0 <= "z") || ($0 >= "0" && $0 <= "9") || $0 == "_" || $0 == "-" }
                            if let firstChar = keyCandidate.first, (firstChar >= "A" && firstChar <= "Z") || (firstChar >= "a" && firstChar <= "z"), isAsciiKey {
                                let lower = keyCandidate.lowercased()
                                if keyCandidate.count >= 3 && lower != "type" && lower != "id" {
                                    jsonName = keyCandidate
                                    break
                                }
                            }
                        }
                    }
                }
            }
            return "\(jsonName).json"

        case .swift:
            let swiftKeywords = ["struct ", "class ", "enum ", "actor ", "protocol ", "func "]
            var swiftName = "Snippet"
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("//") || trimmed.hasPrefix("/*") || trimmed.hasPrefix("*") || trimmed.hasPrefix("#") {
                    continue
                }
                var found: String? = nil
                for kw in swiftKeywords {
                    if let range = trimmed.range(of: kw) {
                        let after = trimmed[range.upperBound...]
                        let token = after.prefix(while: { ($0 >= "A" && $0 <= "Z") || ($0 >= "a" && $0 <= "z") || ($0 >= "0" && $0 <= "9") || $0 == "_" })
                        let ident = String(token)
                        if isValidAsciiIdentifier(ident) {
                            found = ident
                            break
                        }
                    }
                }
                if let found {
                    swiftName = found
                    break
                }
            }
            return "\(swiftName).swift"

        case .py:
            let pyKeywords = ["def ", "class "]
            var pyName = "script"
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("#") || trimmed.hasPrefix("//") || trimmed.hasPrefix("/*") || trimmed.hasPrefix("*") {
                    continue
                }
                var found: String? = nil
                for kw in pyKeywords {
                    if let range = trimmed.range(of: kw) {
                        let after = trimmed[range.upperBound...]
                        let token = after.prefix(while: { ($0 >= "A" && $0 <= "Z") || ($0 >= "a" && $0 <= "z") || ($0 >= "0" && $0 <= "9") || $0 == "_" })
                        let ident = String(token)
                        if isValidAsciiIdentifier(ident) {
                            found = ident
                            break
                        }
                    }
                }
                if let found {
                    pyName = found
                    break
                }
            }
            return "\(pyName).py"

        case .sh:
            var shName = "script"
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("#!/") || trimmed.hasPrefix("#") || trimmed.hasPrefix("//") {
                    continue
                }
                if let parenIdx = trimmed.firstIndex(of: "(") {
                    let beforeParen = trimmed[..<parenIdx].trimmingCharacters(in: .whitespaces)
                    let fnToken = beforeParen.hasPrefix("function ")
                        ? String(beforeParen.dropFirst(9)).trimmingCharacters(in: .whitespaces)
                        : beforeParen
                    let afterParen = trimmed[trimmed.index(after: parenIdx)...].trimmingCharacters(in: .whitespaces)
                    if afterParen.hasPrefix(")") && isValidAsciiIdentifier(fnToken) {
                        shName = fnToken
                        break
                    }
                }
                break
            }
            return "\(shName).sh"

        case .js:
            let jsKeywords = ["function ", "class ", "const ", "let ", "var "]
            var jsName = "script"
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("//") || trimmed.hasPrefix("/*") || trimmed.hasPrefix("*") || trimmed.hasPrefix("#") {
                    continue
                }
                var found: String? = nil
                for kw in jsKeywords {
                    if let range = trimmed.range(of: kw) {
                        let after = trimmed[range.upperBound...]
                        let token = after.prefix(while: { ($0 >= "A" && $0 <= "Z") || ($0 >= "a" && $0 <= "z") || ($0 >= "0" && $0 <= "9") || $0 == "_" })
                        let ident = String(token)
                        if isValidAsciiIdentifier(ident) {
                            found = ident
                            break
                        }
                    }
                }
                if let found {
                    jsName = found
                    break
                }
            }
            return "\(jsName).js"

        // MARK: - ГРУППА Б: 3 ТЕКСТОВЫХ И ДОКУМЕНТНЫХ ФОРМАТА
        case .txt, .docx, .md:
            guard let rawFirstLine = nonEmpties.first else {
                return "document.\(format.extensionName)"
            }

            var line = rawFirstLine.trimmingCharacters(in: .whitespaces)
            let leadingStripChars = CharacterSet(charactersIn: "#/;*->• \t")
            while !line.isEmpty {
                let before = line
                line = line.trimmingCharacters(in: leadingStripChars)
                if let firstDigit = line.first, firstDigit.isNumber {
                    var idx = line.startIndex
                    while idx < line.endIndex && line[idx].isNumber {
                        idx = line.index(after: idx)
                    }
                    if idx < line.endIndex && (line[idx] == "." || line[idx] == ")") {
                        line = String(line[line.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
                    }
                }
                if line == before { break }
            }

            let words = line.components(separatedBy: CharacterSet.whitespaces)
                .map { token -> String in
                    token.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
                }
                .filter { !$0.isEmpty }

            var selectedWords = Array(words.prefix(3))

            let stopWords: Set<String> = [
                "и", "в", "во", "на", "с", "со", "к", "ко", "по", "из", "за", "от", "до",
                "у", "о", "об", "а", "но", "да", "или", "либо", "не", "ни", "что", "как",
                "для", "при", "про", "без", "над", "под", "через", "между", "же", "бы", "ли",
                "the", "a", "an", "and", "or", "of", "in", "on", "at", "to", "for", "with", "by", "from", "as", "is", "are"
            ]

            while selectedWords.count > 1, let last = selectedWords.last, stopWords.contains(last.lowercased()) {
                selectedWords.removeLast()
            }

            if selectedWords.isEmpty {
                return "document.\(format.extensionName)"
            }

            var base = selectedWords.joined(separator: "_")
            if base.count > 30 {
                base = String(base.prefix(30)).trimmingCharacters(in: CharacterSet(charactersIn: "_- "))
            }
            return "\(base).\(format.extensionName)"
        }
    }

    /// Определяет рекомендуемый формат экспорта для содержимого карточки:
    /// - Для обычного текста (.text): если есть явная разметка Markdown -> .md; во всех остальных случаях ВСЕГДА .txt
    /// - Для кода (.code): .conf, .json, .swift, .py, .sh, .js, .md; fallback .txt
    public static func recommendedFormat(for content: String) -> CardExportFormat? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let kind = SmartClassifier.classify(text: trimmed, isSensitive: false)

        // Проверка на явную многострочную структуру Markdown
        let hasMarkdownHeaders = trimmed.hasPrefix("# ") || trimmed.hasPrefix("## ") || trimmed.contains("\n# ") || trimmed.contains("\n## ")
        let hasMarkdownTasks = trimmed.contains("- [ ]") || trimmed.contains("- [x]") || trimmed.contains("- [X]")
        let hasMarkdownTables = (trimmed.contains("| ---") || trimmed.contains("|:---") || trimmed.contains("|---"))
        let hasMarkdownCodeBlocks = trimmed.contains("```")
        let hasExplicitMarkdownStructure = hasMarkdownHeaders || hasMarkdownTasks || hasMarkdownTables || hasMarkdownCodeBlocks

        if kind == .text {
            if hasExplicitMarkdownStructure {
                return .md
            }
            return .txt
        }

        // Для категории .code:
        // 1. JSON
        if SmartClassifier.isJSON(trimmed) {
            return .json
        }

        // 2. Shell script
        if trimmed.hasPrefix("#!/") || (trimmed.contains("\n") && (trimmed.hasPrefix("#!/bin/bash") || trimmed.hasPrefix("#!/bin/sh") || trimmed.hasPrefix("#!/usr/bin/env bash"))) {
            return .sh
        }

        // 3. Конфигурационный файл
        if SmartClassifier.isConfigFile(trimmed) {
            return .conf
        }

        // 4. Swift
        if SmartClassifier.isSwiftCode(trimmed) {
            return .swift
        }

        // 5. Python
        let nonEmpties = trimmed.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let pySignals = ["def ", "import ", "from ", "class ", "elif ", "print("]
        if nonEmpties.contains(where: { line in pySignals.contains(where: { line.hasPrefix($0) }) }) && (trimmed.contains("def ") || trimmed.contains("import ")) {
            return .py
        }

        // 6. JavaScript
        let jsSignals = ["const ", "let ", "function ", "console.log", "module.exports", "export default"]
        if jsSignals.filter({ trimmed.contains($0) }).count >= 2 {
            return .js
        }

        // 7. Markdown
        if hasExplicitMarkdownStructure {
            return .md
        }

        // Fallback для .code, если язык не распознан
        return .txt
    }

    /// Генерирует сериализованные байты файла.
    /// Для .docx нативно создает Microsoft Word через NSAttributedString (officeOpenXML).
    public static func generateExportData(from text: String, format: CardExportFormat, isCode: Bool = false) throws -> Data {
        switch format {
        case .docx:
            let font = isCode
                ? NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
                : NSFont.systemFont(ofSize: 12)
            let attr = NSAttributedString(
                string: text,
                attributes: [.font: font, .foregroundColor: NSColor.textColor]
            )
            return try attr.data(
                from: NSRange(location: 0, length: attr.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML]
            )
        case .txt, .conf, .json, .swift, .py, .md, .sh, .js:
            return Data(text.utf8)
        }
    }

    /// Открывает системное окно сохранения NSSavePanel как шторку прямо поверх окна FloatingPanel
    @MainActor
    public static func promptSaveCard(
        content: String,
        format: CardExportFormat,
        isCode: Bool = false,
        language: AppLanguage = .current
    ) {
        NSApp.activate(ignoringOtherApps: true)
        let savePanel = NSSavePanel()
        if let utType = UTType(filenameExtension: format.extensionName) {
            savePanel.allowedContentTypes = [utType]
        }
        savePanel.canCreateDirectories = true
        savePanel.nameFieldStringValue = defaultFileName(for: content, format: format)
        savePanel.prompt = language == .en ? "Save" : "Сохранить"
        savePanel.title = language == .en ? "Export to .\(format.extensionName)" : "Экспорт в .\(format.extensionName)"
        savePanel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)) + 1)

        let writeAction: (URL) -> Void = { url in
            do {
                let data = try generateExportData(from: content, format: format, isCode: isCode)
                try data.write(to: url, options: .atomic)
            } catch {
                fputs("[CardFileExporter] Failed to write exported file: \(error.localizedDescription)\n", stderr)
            }
        }

        let hostWindow = NSApp.windows.first(where: { $0.className.contains("FloatingPanel") && $0.isVisible }) ?? NSApp.keyWindow
        if let host = hostWindow {
            savePanel.beginSheetModal(for: host) { response in
                if response == .OK, let url = savePanel.url {
                    writeAction(url)
                }
            }
        } else {
            if savePanel.runModal() == .OK, let url = savePanel.url {
                writeAction(url)
            }
        }
    }
}

// MARK: - Card Export Format Picker Popover View

public struct CardExportFormatPicker: View {
    public let theme: AppTheme
    public let currentFont: AppFont
    public let language: AppLanguage
    public let recommendedFormat: CardExportFormat?
    public let onSelect: (CardExportFormat) -> Void

    public init(
        theme: AppTheme,
        currentFont: AppFont,
        language: AppLanguage = .current,
        recommendedFormat: CardExportFormat? = nil,
        onSelect: @escaping (CardExportFormat) -> Void
    ) {
        self.theme = theme
        self.currentFont = currentFont
        self.language = language
        self.recommendedFormat = recommendedFormat
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down.doc")
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(theme.accentColor)
                Text(language == .en ? "Export Format" : "Формат экспорта")
                    .font(currentFont.font(size: 11, weight: .bold))
                    .foregroundStyle(theme.secondaryText)
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)
            .padding(.bottom, 2)

            Divider()
                .background(theme.borderColor.opacity(0.5))

            ForEach(CardExportFormat.allCases) { format in
                FormatPickerRow(
                    format: format,
                    isRecommended: format == recommendedFormat,
                    theme: theme,
                    font: currentFont,
                    language: language,
                    onSelect: {
                        onSelect(format)
                    }
                )
            }
        }
        .padding(6)
        .frame(width: 236)
        .background(theme.cardColor)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(theme.borderColor, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.25), radius: 10, x: 0, y: 4)
        .environment(\.colorScheme, theme.isLight ? .light : .dark)
    }

    private struct FormatPickerRow: View {
        let format: CardExportFormat
        let isRecommended: Bool
        let theme: AppTheme
        let font: AppFont
        let language: AppLanguage
        let onSelect: () -> Void

        @State private var isHovered: Bool = false

        var body: some View {
            Button(action: onSelect) {
                HStack(spacing: 8) {
                    Image(systemName: format.iconName)
                        .symbolRenderingMode(.monochrome)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isHovered ? theme.accentColor : theme.primaryText.opacity(0.75))
                        .frame(width: 18)

                    Text(format.title(in: language))
                        .font(font.font(size: 12, weight: isHovered ? .semibold : .medium))
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    if isRecommended {
                        Image(systemName: "checkmark.circle.fill")
                            .symbolRenderingMode(.monochrome)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(theme.accentColor)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isHovered ? theme.accentColor.opacity(0.18) : (isRecommended ? theme.accentColor.opacity(0.06) : Color.clear))
                )
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
            .onHover { h in
                isHovered = h
                if h { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
            }
        }
    }
}
