import SwiftUI
import Foundation

public enum SnippetSearchScope: String, CaseIterable, Identifiable {
    case all
    case titleOnly

    public var id: String { rawValue }
}

public enum SearchHighlightHelper {
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

        return snippets.sorted { (a, b) in
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
