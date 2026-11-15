import Foundation
import AppKit

public struct SnippetMacroDefinition: Identifiable, Sendable {
    public let id: String
    public let tag: String
    public let icon: String
    public let title: String
    public let titleEN: String
    public let exampleValue: String

    public init(id: String, tag: String, icon: String, title: String, titleEN: String = "", exampleValue: String) {
        self.id = id
        self.tag = tag
        self.icon = icon
        self.title = title
        self.titleEN = titleEN.isEmpty ? title : titleEN
        self.exampleValue = exampleValue
    }

    public func title(isEnglish: Bool) -> String {
        isEnglish ? titleEN : title
    }
}

public final class SnippetMacroEngine: @unchecked Sendable {

    public static var currentAppLocale: Locale {
        let isEn = AppDefaults.shared.string(forKey: "appLanguage") == "en"
        return Locale(identifier: isEn ? "en_US" : "ru_RU")
    }

    public static let macros: [SnippetMacroDefinition] = [
        SnippetMacroDefinition(id: "date", tag: "{{date}}", icon: "calendar", title: "Текущая дата", titleEN: "Current date", exampleValue: "12.11.2026"),
        SnippetMacroDefinition(id: "time", tag: "{{time}}", icon: "clock", title: "Текущее время", titleEN: "Current time", exampleValue: "13:17"),
        SnippetMacroDefinition(id: "datetime", tag: "{{datetime}}", icon: "calendar.badge.clock", title: "Дата и время", titleEN: "Date & time", exampleValue: "12.11.2026 13:17"),
        SnippetMacroDefinition(id: "weekday", tag: "{{weekday}}", icon: "calendar.day.timeline.left", title: "День недели", titleEN: "Day of week", exampleValue: "четверг"),
        SnippetMacroDefinition(id: "iso", tag: "{{iso}}", icon: "number", title: "Дата ISO (для кода)", titleEN: "ISO Date (for code)", exampleValue: "2026-11-12"),
        SnippetMacroDefinition(id: "app", tag: "{{app}}", icon: "macwindow", title: "Активное приложение", titleEN: "Active application", exampleValue: "Xcode"),
        SnippetMacroDefinition(id: "user", tag: "{{user}}", icon: "person.fill", title: "Имя пользователя", titleEN: "Username", exampleValue: NSUserName()),
        SnippetMacroDefinition(id: "uuid", tag: "{{uuid}}", icon: "key.horizontal.fill", title: "Уникальный ID (UUID)", titleEN: "Unique ID (UUID)", exampleValue: "a1b2c3d4-e5f6-...")
    ]

    /// Проверяет наличие любых поддерживаемых макросов
    public static func containsMacro(_ text: String) -> Bool {
        guard text.contains("{{") else { return false }
        for macro in macros {
            if text.range(of: macro.tag, options: .caseInsensitive) != nil {
                return true
            }
        }
        return false
    }

    /// Раскрывает все 8 макросов в живые динамические значения
    public static func expand(
        _ text: String,
        targetAppName: String? = nil,
        date: Date = Date(),
        locale: Locale = SnippetMacroEngine.currentAppLocale
    ) -> String {
        guard text.contains("{{") else { return text }

        let dateFmt = DateFormatter()
        dateFmt.locale = locale
        dateFmt.dateFormat = "dd.MM.yyyy"
        let dateStr = dateFmt.string(from: date)

        let timeFmt = DateFormatter()
        timeFmt.locale = locale
        timeFmt.dateFormat = "HH:mm"
        let timeStr = timeFmt.string(from: date)

        let dateTimeStr = "\(dateStr) \(timeStr)"

        let weekdayFmt = DateFormatter()
        weekdayFmt.locale = locale
        weekdayFmt.dateFormat = "EEEE"
        let weekdayStr = weekdayFmt.string(from: date).lowercased()

        let isoFmt = DateFormatter()
        isoFmt.locale = Locale(identifier: "en_US_POSIX")
        isoFmt.dateFormat = "yyyy-MM-dd"
        let isoStr = isoFmt.string(from: date)

        let resolvedAppName: String = {
            if let name = targetAppName?.trimmingCharacters(in: .whitespacesAndNewlines),
               !name.isEmpty,
               name.lowercased() != "активное окно",
               name.lowercased() != "active window" {
                return name
            }
            if let frontApp = NSWorkspace.shared.frontmostApplication?.localizedName,
               frontApp != "Paste Vault", frontApp != "PasteVault", !frontApp.isEmpty {
                return frontApp
            }
            if let deviceName = Host.current().localizedName?.trimmingCharacters(in: .whitespacesAndNewlines),
               !deviceName.isEmpty {
                return deviceName
            }
            return AppLanguage.current == .en ? "Mac" : "Мак"
        }()

        let userStr = NSUserName()
        let uuidStr = UUID().uuidString.lowercased()

        // Порядок замены: datetime должен быть раньше date и time!
        let replacements: [(String, String)] = [
            ("{{datetime}}", dateTimeStr),
            ("{{date}}", dateStr),
            ("{{time}}", timeStr),
            ("{{weekday}}", weekdayStr),
            ("{{iso}}", isoStr),
            ("{{app}}", resolvedAppName),
            ("{{user}}", userStr),
            ("{{uuid}}", uuidStr)
        ]

        var expanded = text
        for (tag, val) in replacements {
            if let regex = try? NSRegularExpression(pattern: NSRegularExpression.escapedPattern(for: tag), options: .caseInsensitive) {
                let range = NSRange(location: 0, length: (expanded as NSString).length)
                expanded = regex.stringByReplacingMatches(in: expanded, options: [], range: range, withTemplate: NSRegularExpression.escapedTemplate(for: val))
            } else {
                expanded = expanded.replacingOccurrences(of: tag, with: val, options: .caseInsensitive)
            }
        }

        return expanded
    }

    /// Возвращает пример раскрытия конкретного макроса для плашки предпросмотра.
    /// Для `{{uuid}}` показывает только первые 8 символов + многоточие (при реальной вставке — полный 36-символьный UUID).
    public static func previewValue(for tag: String, targetAppName: String? = nil, date: Date = Date(), locale: Locale = SnippetMacroEngine.currentAppLocale) -> String {
        let expanded = expand(tag, targetAppName: targetAppName, date: date, locale: locale)
        if tag.lowercased() == "{{uuid}}" {
            return String(expanded.prefix(8)) + "…"
        }
        return expanded
    }
}
