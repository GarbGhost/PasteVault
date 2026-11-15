import SwiftUI
import Foundation

public enum SnippetSearchScope: String, CaseIterable, Identifiable {
    case all
    case titleOnly

    public var id: String { rawValue }
}

public enum SearchHighlightHelper {
    public static let supportedSnippetMacros = [
        "{{datetime}}", "{{date}}", "{{time}}", "{{weekday}}", "{{iso}}", "{{app}}", "{{user}}", "{{uuid}}"
    ]

    /// Проверяет наличие хотя бы одного динамического макроса в тексте
    public static func containsSnippetMacro(_ text: String) -> Bool {
        return SnippetMacroEngine.containsMacro(text)
    }

    /// Формирует AttributedString с акцентной подсветкой динамических макросов
    /// и опциональной подсветкой поискового запроса.
    public static func highlightedSnippetText(
        _ text: String,
        query: String = "",
        accentColor: Color = .accentColor,
        primaryColor: Color = .primary,
        baseFontSize: CGFloat = 12,
        baseFont: Font? = nil,
        isLight: Bool = false
    ) -> AttributedString {
        var attributed = AttributedString(text)
        if let baseFont {
            attributed.font = baseFont
        } else {
            attributed.font = .system(size: baseFontSize)
        }
        attributed.foregroundColor = primaryColor

        guard !text.isEmpty else { return attributed }

        // 1. Подсветка поддерживаемых макросов
        let macroBg = accentColor.opacity(0.16)
        let macroFont = Font.system(size: baseFontSize, weight: .bold, design: .monospaced)

        for macro in supportedSnippetMacros {
            var searchRange = attributed.startIndex..<attributed.endIndex
            while let matchRange = attributed[searchRange].range(of: macro, options: .caseInsensitive) {
                attributed[matchRange].font = macroFont
                attributed[matchRange].foregroundColor = accentColor
                attributed[matchRange].backgroundColor = macroBg
                if matchRange.upperBound < attributed.endIndex {
                    searchRange = matchRange.upperBound..<attributed.endIndex
                } else {
                    break
                }
            }
        }

        // 2. Если одновременно задан непустой поисковый запрос, накладываем подсветку поиска поверх
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedQuery.isEmpty {
            let searchBg = accentColor.opacity(isLight ? 0.28 : 0.40)
            var searchRange = attributed.startIndex..<attributed.endIndex
            while let matchRange = attributed[searchRange].range(of: trimmedQuery, options: .caseInsensitive) {
                attributed[matchRange].backgroundColor = searchBg
                attributed[matchRange].inlinePresentationIntent = .stronglyEmphasized
                if matchRange.upperBound < attributed.endIndex {
                    searchRange = matchRange.upperBound..<attributed.endIndex
                } else {
                    break
                }
            }
        }

        return attributed
    }

    /// Разворачивает макросы в живые значения
    public static func expandSnippetMacrosForDisplay(
        _ text: String,
        date: Date = Date(),
        targetAppName: String? = nil,
        language: AppLanguage = .ru
    ) -> (expandedText: String, replacedRanges: [Range<String.Index>]) {
        guard containsSnippetMacro(text) else {
            return (text, [])
        }

        let locale = Locale(identifier: language == .en ? "en_US" : "ru_RU")
        let expanded = SnippetMacroEngine.expand(text, targetAppName: targetAppName, date: date, locale: locale)
        return (expanded, [])
    }

    /// Формирует AttributedString с уже расшифрованными готовыми значениями макросов,
    /// отображая их чистым цветом темы без синего цвета и без подчёркивания, накладывая подсветку только на совпадения поискового запроса.
    public static func expandedAndHighlightedSnippetText(
        _ text: String,
        query: String = "",
        accentColor: Color = .accentColor,
        primaryColor: Color = .primary,
        baseFontSize: CGFloat = 12,
        baseFont: Font? = nil,
        isLight: Bool = false,
        language: AppLanguage = .ru,
        date: Date = Date(),
        targetAppName: String? = nil
    ) -> AttributedString {
        let (expandedText, _) = expandSnippetMacrosForDisplay(
            text,
            date: date,
            targetAppName: targetAppName,
            language: language
        )

        var attributed = AttributedString(expandedText)
        if let baseFont {
            attributed.font = baseFont
        } else {
            attributed.font = .system(size: baseFontSize)
        }
        attributed.foregroundColor = primaryColor

        guard !expandedText.isEmpty else { return attributed }

        // Подставленные значения макросов отображаются обычным чистым цветом темы (primaryColor)
        // без цветового фона и без нижнего подчеркивания.
        // Подсветка накладывается только если пользователь ввел непустой поисковый запрос.
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedQuery.isEmpty {
            let searchBg = accentColor.opacity(isLight ? 0.28 : 0.40)
            var searchRange = attributed.startIndex..<attributed.endIndex
            while let matchRange = attributed[searchRange].range(of: trimmedQuery, options: .caseInsensitive) {
                attributed[matchRange].backgroundColor = searchBg
                attributed[matchRange].inlinePresentationIntent = .stronglyEmphasized
                if matchRange.upperBound < attributed.endIndex {
                    searchRange = matchRange.upperBound..<attributed.endIndex
                } else {
                    break
                }
            }
        }

        return attributed
    }

    /// Формирует AttributedString с подсветкой всех нечувствительных к регистру вхождений `query` в `text`.
    public static func highlight(
        text: String,
        query: String,
        baseFont: Font? = nil,
        baseColor: Color = .primary,
        accentColor: Color = .accentColor,
        isLight: Bool = false,
        bold: Bool = true
    ) -> AttributedString {
        var attributed = AttributedString(text)
        if let baseFont {
            attributed.font = baseFont
        }
        attributed.foregroundColor = baseColor

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty, !text.isEmpty else {
            return attributed
        }

        let highlightBg = accentColor.opacity(isLight ? 0.25 : 0.38)
        var searchRange = attributed.startIndex..<attributed.endIndex

        while let matchRange = attributed[searchRange].range(of: trimmedQuery, options: .caseInsensitive) {
            attributed[matchRange].backgroundColor = highlightBg
            attributed[matchRange].foregroundColor = baseColor
            if bold {
                attributed[matchRange].inlinePresentationIntent = .stronglyEmphasized
            }
            if matchRange.upperBound < attributed.endIndex {
                searchRange = matchRange.upperBound..<attributed.endIndex
            } else {
                break
            }
        }

        return attributed
    }

    /// Сортирует фрагменты: закрепленные всегда выше; при поиске — совпадение в title выше совпадения в content.
    public static func sortSnippets(
        _ snippets: [QuickSnippetItem],
        query: String,
        scope: SnippetSearchScope = .all
    ) -> [QuickSnippetItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            // Без поиска — закрепленные наверху, остальные в стабильном порядке
            return snippets.sorted { (a, b) in
                if a.isPinned != b.isPinned {
                    return a.isPinned && !b.isPinned
                }
                return false
            }
        }

        let source = (scope == .titleOnly)
            ? snippets.filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
            : snippets

        return source.sorted { (a, b) in
            // 1. Закрепленные всегда выше незакрепленных
            if a.isPinned != b.isPinned {
                return a.isPinned && !b.isPinned
            }

            // 2. Совпадение в названии (title) приоритетнее совпадения только в тексте (content)
            let aTitleMatch = a.title.localizedCaseInsensitiveContains(trimmed)
            let bTitleMatch = b.title.localizedCaseInsensitiveContains(trimmed)

            if aTitleMatch != bTitleMatch {
                return aTitleMatch && !bTitleMatch
            }

            return false
        }
    }
}
