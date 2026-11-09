import AppKit
import Carbon
import Foundation

// MARK: - Key Combo Model
public struct KeyCombo: Codable, Equatable, Hashable, Sendable {
    public var keyCode: UInt16
    public var modifiers: UInt
    public var displayString: String

    public init(keyCode: UInt16, modifiers: UInt, displayString: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.displayString = displayString
    }

    public var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiers).intersection(.deviceIndependentFlagsMask)
    }

    /// Проверяет, совпадает ли входящее событие клавиатуры с данной комбинацией
    public func matches(event: NSEvent) -> Bool {
        let eventFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.numericPad, .function, .capsLock])
        let targetFlags = modifierFlags.subtracting([.numericPad, .function, .capsLock])

        guard eventFlags == targetFlags else { return false }
        if keyCode == event.keyCode { return true }

        // Дополнительная проверка символов для раскладко-независимости
        if let char = event.charactersIgnoringModifiers?.uppercased(),
           let targetChar = Self.keyName(for: keyCode)?.uppercased(),
           !char.isEmpty, char == targetChar {
            return true
        }
        return false
    }

    public static func keyName(for code: UInt16) -> String? {
        switch code {
        case 49: return "Space"
        case 36, 76: return "Enter"
        case 51, 117: return "⌫"
        case 43: return ","
        case 48: return "Tab"
        case 53: return "Esc"
        case 35: return "P"
        case 34: return "I"
        case 46: return "M"
        case 5: return "G"
        case 1: return "S"
        case 9: return "V"
        case 12: return "Q"
        case 8: return "C"
        case 7: return "X"
        case 0: return "A"
        case 6: return "Z"
        default: return nil
        }
    }
}

// MARK: - 11 Shortcut Commands
public enum ShortcutCommand: String, CaseIterable, Identifiable, Codable, Sendable {
    case togglePanel
    case pasteSelected
    case pastePlainText
    case quickPasteModifier
    case togglePin
    case deleteItem
    case clearHistory
    case togglePause
    case openPassGen
    case openSnippets
    case openSettings

    public var id: String { rawValue }

    public func title(in lang: AppLanguage) -> String {
        switch self {
        case .togglePanel:
            return lang == .en ? "Open / Hide Clipboard Panel" : "Открыть / скрыть меню буфера"
        case .pasteSelected:
            return lang == .en ? "Paste Selected Item" : "Вставить выбранную запись"
        case .pastePlainText:
            return lang == .en ? "Paste Without Formatting" : "Вставить без форматирования"
        case .quickPasteModifier:
            return lang == .en ? "Quick Paste by Number (1–9)" : "Быстрая вставка по номеру (1–9)"
        case .togglePin:
            return lang == .en ? "Pin / Unpin Item" : "Закрепить / открепить запись"
        case .deleteItem:
            return lang == .en ? "Delete Selected Item" : "Удалить выбранную запись"
        case .clearHistory:
            return lang == .en ? "Clear All History (Except Pinned)" : "Очистить всю историю (кроме закрепленных)"
        case .togglePause:
            return lang == .en ? "Pause / Resume Recording" : "Пауза / Включение записи буфера"
        case .openPassGen:
            return lang == .en ? "Open Password Generator (PassGen)" : "Открыть генератор паролей (PassGen)"
        case .openSnippets:
            return lang == .en ? "Open Quick Snippets" : "Открыть быстрые шаблоны (Snippets)"
        case .openSettings:
            return lang == .en ? "Open Settings (Preferences)" : "Открыть окно настроек (Preferences)"
        }
    }

    public func tooltip(in lang: AppLanguage) -> String {
        switch self {
        case .togglePanel:
            return lang == .en
                ? "Global system shortcut that opens or hides the PasteVault floating panel above any active application."
                : "Глобальная системная комбинация клавиш, которая открывает или скрывает плавающее окно PasteVault поверх любых приложений macOS."
        case .pasteSelected:
            return lang == .en
                ? "Immediately pastes the currently selected item into the active target application window."
                : "Мгновенно вставляет текущую выбранную запись в активное целевое приложение."
        case .pastePlainText:
            return lang == .en
                ? "Strips rich text styles and formatting, inserting clean plain text into the target window."
                : "Очищает форматирование и стили текста перед вставкой в целевое окно."
        case .quickPasteModifier:
            return lang == .en
                ? "Modifier key held while pressing numbers 1 through 9 to instantly paste items from the list."
                : "Модификатор клавиши для мгновенной вставки первых 9 записей списка буфера обмена."
        case .togglePin:
            return lang == .en
                ? "Pins an important record to the top of the list and protects it from auto-cleaning."
                : "Закрепляет важную запись вверху списка и защищает её от автоматической очистки."
        case .deleteItem:
            return lang == .en
                ? "Permanently deletes the currently selected item from the local encrypted database."
                : "Безвозвратно удаляет выбранный элемент из локальной зашифрованной базы данных."
        case .clearHistory:
            return lang == .en
                ? "Removes all unpinned entries from clipboard history while preserving your pinned records."
                : "Удаляет все незакрепленные записи из истории буфера обмена, сохраняя закрепленные."
        case .togglePause:
            return lang == .en
                ? "Pauses or resumes clipboard recording (Incognito mode)."
                : "Включает или выключает режим «Инкогнито», приостанавливая перехват новых копирований."
        case .openPassGen:
            return lang == .en
                ? "Switches to the built-in cryptographically secure password generator."
                : "Мгновенно переключает окно на встроенный генератор надежных паролей."
        case .openSnippets:
            return lang == .en
                ? "Switches to the library of ready-to-use text snippets and code templates."
                : "Переключает окно на библиотеку готовых текстовых шаблонов и фрагментов кода."
        case .openSettings:
            return lang == .en
                ? "Switches to the settings tab for appearance, shortcuts, and database management."
                : "Переходит на вкладку настроек оформления, горячих клавиш и базы данных."
        }
    }

    /// Пресет-комбинации для выбора пользователем из списка
    public var presetCombos: [KeyCombo] {
        switch self {
        case .togglePanel:
            return [
                KeyCombo(keyCode: 49, modifiers: NSEvent.ModifierFlags.option.rawValue, displayString: "⌥Space"),
                KeyCombo(keyCode: 49, modifiers: NSEvent.ModifierFlags.control.rawValue, displayString: "⌃Space"),
                KeyCombo(keyCode: 9, modifiers: (NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue), displayString: "⌘⇧V"),
                KeyCombo(keyCode: 9, modifiers: NSEvent.ModifierFlags.option.rawValue, displayString: "⌥V")
            ]
        case .pasteSelected:
            return [
                KeyCombo(keyCode: 36, modifiers: 0, displayString: "↵ Enter"),
                KeyCombo(keyCode: 36, modifiers: NSEvent.ModifierFlags.command.rawValue, displayString: "⌘↵"),
                KeyCombo(keyCode: 36, modifiers: NSEvent.ModifierFlags.option.rawValue, displayString: "⌥↵")
            ]
        case .pastePlainText:
            return [
                KeyCombo(keyCode: 36, modifiers: (NSEvent.ModifierFlags.option.rawValue | NSEvent.ModifierFlags.shift.rawValue), displayString: "⌥⇧↵"),
                KeyCombo(keyCode: 36, modifiers: (NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue), displayString: "⌘⇧↵"),
                KeyCombo(keyCode: 36, modifiers: NSEvent.ModifierFlags.control.rawValue, displayString: "⌃↵")
            ]
        case .quickPasteModifier:
            return [
                KeyCombo(keyCode: 0, modifiers: NSEvent.ModifierFlags.option.rawValue, displayString: "⌥1..⌥9"),
                KeyCombo(keyCode: 0, modifiers: NSEvent.ModifierFlags.command.rawValue, displayString: "⌘1..⌘9"),
                KeyCombo(keyCode: 0, modifiers: NSEvent.ModifierFlags.control.rawValue, displayString: "⌃1..⌃9")
            ]
        case .togglePin:
            return [
                KeyCombo(keyCode: 35, modifiers: NSEvent.ModifierFlags.option.rawValue, displayString: "⌥P"),
                KeyCombo(keyCode: 35, modifiers: NSEvent.ModifierFlags.command.rawValue, displayString: "⌘P"),
                KeyCombo(keyCode: 35, modifiers: NSEvent.ModifierFlags.control.rawValue, displayString: "⌃P")
            ]
        case .deleteItem:
            return [
                KeyCombo(keyCode: 51, modifiers: NSEvent.ModifierFlags.option.rawValue, displayString: "⌥⌫"),
                KeyCombo(keyCode: 51, modifiers: NSEvent.ModifierFlags.command.rawValue, displayString: "⌘⌫"),
                KeyCombo(keyCode: 51, modifiers: NSEvent.ModifierFlags.control.rawValue, displayString: "⌃⌫")
            ]
        case .clearHistory:
            return [
                KeyCombo(keyCode: 51, modifiers: (NSEvent.ModifierFlags.option.rawValue | NSEvent.ModifierFlags.command.rawValue), displayString: "⌥⌘⌫"),
                KeyCombo(keyCode: 51, modifiers: (NSEvent.ModifierFlags.control.rawValue | NSEvent.ModifierFlags.command.rawValue), displayString: "⌃⌘⌫"),
                KeyCombo(keyCode: 51, modifiers: (NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue), displayString: "⌘⇧⌫")
            ]
        case .togglePause:
            return [
                KeyCombo(keyCode: 34, modifiers: NSEvent.ModifierFlags.option.rawValue, displayString: "⌥I"),
                KeyCombo(keyCode: 46, modifiers: NSEvent.ModifierFlags.option.rawValue, displayString: "⌥M"),
                KeyCombo(keyCode: 34, modifiers: NSEvent.ModifierFlags.control.rawValue, displayString: "⌃I")
            ]
        case .openPassGen:
            return [
                KeyCombo(keyCode: 5, modifiers: NSEvent.ModifierFlags.option.rawValue, displayString: "⌥G"),
                KeyCombo(keyCode: 5, modifiers: NSEvent.ModifierFlags.command.rawValue, displayString: "⌘G"),
                KeyCombo(keyCode: 5, modifiers: NSEvent.ModifierFlags.control.rawValue, displayString: "⌃G")
            ]
        case .openSnippets:
            return [
                KeyCombo(keyCode: 1, modifiers: NSEvent.ModifierFlags.option.rawValue, displayString: "⌥S"),
                KeyCombo(keyCode: 1, modifiers: NSEvent.ModifierFlags.command.rawValue, displayString: "⌘S"),
                KeyCombo(keyCode: 1, modifiers: NSEvent.ModifierFlags.control.rawValue, displayString: "⌃S")
            ]
        case .openSettings:
            return [
                KeyCombo(keyCode: 43, modifiers: NSEvent.ModifierFlags.command.rawValue, displayString: "⌘,"),
                KeyCombo(keyCode: 43, modifiers: NSEvent.ModifierFlags.option.rawValue, displayString: "⌥,")
            ]
        }
    }
}

// MARK: - Shortcut Configuration
public struct ShortcutConfig: Codable, Equatable, Sendable {
    public var togglePanel: KeyCombo
    public var pasteSelected: KeyCombo
    public var pastePlainText: KeyCombo
    public var quickPasteModifier: KeyCombo
    public var togglePin: KeyCombo
    public var deleteItem: KeyCombo
    public var clearHistory: KeyCombo
    public var togglePause: KeyCombo
    public var openPassGen: KeyCombo
    public var openSnippets: KeyCombo
    public var openSettings: KeyCombo

    public static let `default` = ShortcutConfig(
        togglePanel: KeyCombo(keyCode: 49, modifiers: NSEvent.ModifierFlags.option.rawValue, displayString: "⌥Space"),
        pasteSelected: KeyCombo(keyCode: 36, modifiers: 0, displayString: "↵ Enter"),
        pastePlainText: KeyCombo(keyCode: 36, modifiers: (NSEvent.ModifierFlags.option.rawValue | NSEvent.ModifierFlags.shift.rawValue), displayString: "⌥⇧↵"),
        quickPasteModifier: KeyCombo(keyCode: 0, modifiers: NSEvent.ModifierFlags.option.rawValue, displayString: "⌥1..⌥9"),
        togglePin: KeyCombo(keyCode: 35, modifiers: NSEvent.ModifierFlags.option.rawValue, displayString: "⌥P"),
        deleteItem: KeyCombo(keyCode: 51, modifiers: NSEvent.ModifierFlags.option.rawValue, displayString: "⌥⌫"),
        clearHistory: KeyCombo(keyCode: 51, modifiers: (NSEvent.ModifierFlags.option.rawValue | NSEvent.ModifierFlags.command.rawValue), displayString: "⌥⌘⌫"),
        togglePause: KeyCombo(keyCode: 34, modifiers: NSEvent.ModifierFlags.option.rawValue, displayString: "⌥I"),
        openPassGen: KeyCombo(keyCode: 5, modifiers: NSEvent.ModifierFlags.option.rawValue, displayString: "⌥G"),
        openSnippets: KeyCombo(keyCode: 1, modifiers: NSEvent.ModifierFlags.option.rawValue, displayString: "⌥S"),
        openSettings: KeyCombo(keyCode: 43, modifiers: NSEvent.ModifierFlags.command.rawValue, displayString: "⌘,")
    )

    public subscript(command: ShortcutCommand) -> KeyCombo {
        get {
            switch command {
            case .togglePanel: return togglePanel
            case .pasteSelected: return pasteSelected
            case .pastePlainText: return pastePlainText
            case .quickPasteModifier: return quickPasteModifier
            case .togglePin: return togglePin
            case .deleteItem: return deleteItem
            case .clearHistory: return clearHistory
            case .togglePause: return togglePause
            case .openPassGen: return openPassGen
            case .openSnippets: return openSnippets
            case .openSettings: return openSettings
            }
        }
        set {
            switch command {
            case .togglePanel: togglePanel = newValue
            case .pasteSelected: pasteSelected = newValue
            case .pastePlainText: pastePlainText = newValue
            case .quickPasteModifier: quickPasteModifier = newValue
            case .togglePin: togglePin = newValue
            case .deleteItem: deleteItem = newValue
            case .clearHistory: clearHistory = newValue
            case .togglePause: togglePause = newValue
            case .openPassGen: openPassGen = newValue
            case .openSnippets: openSnippets = newValue
            case .openSettings: openSettings = newValue
            }
        }
    }

    /// Проверяет совпадение модификатора быстрой вставки (1..9)
    public func matchesQuickPaste(event: NSEvent) -> Bool {
        let eventFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.numericPad, .function, .capsLock])
        let targetFlags = quickPasteModifier.modifierFlags.subtracting([.numericPad, .function, .capsLock])
        guard eventFlags == targetFlags else { return false }
        guard let chars = event.charactersIgnoringModifiers,
              let digit = Int(chars), (1...9).contains(digit) else {
            return false
        }
        return true
    }

    public func quickPasteDigit(event: NSEvent) -> Int? {
        guard matchesQuickPaste(event: event),
              let chars = event.charactersIgnoringModifiers,
              let digit = Int(chars), (1...9).contains(digit) else {
            return nil
        }
        return digit
    }

    public var quickPastePrefix: String {
        let flags = quickPasteModifier.modifierFlags
        var prefix = ""
        if flags.contains(.control) { prefix += "⌃" }
        if flags.contains(.option) { prefix += "⌥" }
        if flags.contains(.shift) { prefix += "⇧" }
        if flags.contains(.command) { prefix += "⌘" }
        return prefix.isEmpty ? "⌥" : prefix
    }
}
