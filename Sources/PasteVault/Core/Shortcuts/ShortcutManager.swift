import AppKit
import Foundation

public enum ShortcutValidationResult: Equatable {
    case valid
    case systemReserved(String)
    case internalConflict(command: ShortcutCommand, commandName: String)

    public func message(in lang: AppLanguage) -> String {
        switch self {
        case .valid:
            return lang == .en ? "🟢 Available" : "🟢 Свободен"
        case .systemReserved(let sysKey):
            return lang == .en ? "🔴 Reserved by macOS (\(sysKey))" : "🔴 Зарезервировано macOS (\(sysKey))"
        case .internalConflict(_, let cmdName):
            return lang == .en ? "⚠️ Already used in PasteVault for «\(cmdName)»" : "⚠️ Уже используется в PasteVault для «\(cmdName)»"
        }
    }
}

@MainActor
public final class ShortcutManager: ObservableObject {
    public static let shared = ShortcutManager()

    public static let userDefaultsKey = "PasteVault_ShortcutsConfig"

    @Published public var config: ShortcutConfig {
        didSet {
            saveConfig()
            NotificationCenter.default.post(name: Notification.Name("pasteVaultShortcutsDidChange"), object: nil)
        }
    }

    @Published public var recordingCommand: ShortcutCommand? = nil
    @Published public var isRecordingShortcut: Bool = false
    @Published public var validationFeedback: (command: ShortcutCommand, result: ShortcutValidationResult)? = nil

    private var localMonitor: Any?

    public var isRecording: Bool {
        isRecordingShortcut
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.userDefaultsKey),
           let decoded = try? JSONDecoder().decode(ShortcutConfig.self, from: data) {
            self.config = decoded
        } else {
            self.config = .default
        }
    }

    private func saveConfig() {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
        }
    }

    public func resetToDefaults() {
        config = .default
        validationFeedback = nil
        stopRecording()
    }

    // MARK: - Conflict Validation (No third-party process monitoring)
    public func validate(combo: KeyCombo, for command: ShortcutCommand, in lang: AppLanguage) -> ShortcutValidationResult {
        let flags = combo.modifierFlags

        // 1. Системные базовые комбинации macOS (⌘C, ⌘V, ⌘X, ⌘A, ⌘Z, ⌘Q, ⌘Space)
        if flags == .command {
            switch combo.keyCode {
            case 8: return .systemReserved("⌘C")
            case 9: return .systemReserved("⌘V")
            case 7: return .systemReserved("⌘X")
            case 0: return .systemReserved("⌘A")
            case 6: return .systemReserved("⌘Z")
            case 12: return .systemReserved("⌘Q")
            case 49: return .systemReserved("⌘Space")
            default: break
            }
        }

        // 2. Внутренний конфликт внутри Paste Vault
        for otherCmd in ShortcutCommand.allCases where otherCmd != command {
            let otherCombo = config[otherCmd]

            if command == .quickPasteModifier || otherCmd == .quickPasteModifier {
                // Модификатор быстрой вставки сравнивается по модификаторам
                if combo.modifiers == otherCombo.modifiers && (otherCombo.keyCode >= 18 && otherCombo.keyCode <= 28) {
                    return .internalConflict(command: otherCmd, commandName: otherCmd.title(in: lang))
                }
            } else if combo.keyCode == otherCombo.keyCode && combo.modifiers == otherCombo.modifiers {
                return .internalConflict(command: otherCmd, commandName: otherCmd.title(in: lang))
            }
        }

        return .valid
    }

    // MARK: - Key Recording
    public func startRecording(for command: ShortcutCommand) {
        stopRecording()
        recordingCommand = command
        isRecordingShortcut = true
        validationFeedback = nil

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self = self else { return event }

            // 1. Esc (53) без модификаторов — чистая отмена записи БЕЗ закрытия окна Paste Vault
            if event.type == .keyDown && event.keyCode == 53 && event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
                self.stopRecording()
                return nil
            }

            // 2. Для quickPasteModifier — при нажатии любой комбинации с ⌘, ⌥ или ⌃
            if command == .quickPasteModifier {
                let rawFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                    .subtracting([.numericPad, .function, .capsLock])
                let modFlags = rawFlags.intersection([.command, .option, .control, .shift])
                if !modFlags.isEmpty {
                    let modPrefix = self.displayModifierPrefix(flags: modFlags)
                    let combo = KeyCombo(keyCode: 0, modifiers: modFlags.rawValue, displayString: "\(modPrefix)1..\(modPrefix)9")
                    self.config.quickPasteModifier = combo
                    self.validationFeedback = (command, .valid)
                    self.stopRecording()
                    return nil
                }
                return nil
            }

            // 3. Для остальных команд — flagsChanged поглощаем и ждем реальный keyDown
            if event.type == .flagsChanged {
                return nil
            }

            // 4. Реальный keyDown
            self.handleRecordedEvent(event, for: command)
            return nil
        }
    }

    public func stopRecording() {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        recordingCommand = nil
        isRecordingShortcut = false
    }

    private func handleRecordedEvent(_ event: NSEvent, for command: ShortcutCommand) {
        let rawFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.numericPad, .function, .capsLock])

        // Игнорируем нажатия только клавиш-модификаторов (Shift, Ctrl, Alt, Cmd)
        let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
        if modifierKeyCodes.contains(event.keyCode) {
            return
        }

        // Для quickPasteModifier разрешаем нажать модификатор + любую цифру 1-9
        if command == .quickPasteModifier {
            let modPrefix = displayModifierPrefix(flags: rawFlags)
            let combo = KeyCombo(keyCode: 0, modifiers: rawFlags.rawValue, displayString: "\(modPrefix)1..\(modPrefix)9")
            self.config.quickPasteModifier = combo
            self.validationFeedback = (command, .valid)
            self.stopRecording()
            return
        }

        let keyName = KeyCombo.keyName(for: event.keyCode)
            ?? event.charactersIgnoringModifiers?.uppercased()
            ?? "\(event.keyCode)"

        let modPrefix = displayModifierPrefix(flags: rawFlags)
        let displayStr = "\(modPrefix)\(keyName)"

        let newCombo = KeyCombo(
            keyCode: event.keyCode,
            modifiers: rawFlags.rawValue,
            displayString: displayStr
        )

        let lang = AppLanguage.current
        let valResult = validate(combo: newCombo, for: command, in: lang)
        self.validationFeedback = (command, valResult)

        switch valResult {
        case .valid:
            self.config[command] = newCombo
            self.stopRecording()
        case .systemReserved, .internalConflict:
            // Оставляем запись открытой и даем обратную связь
            break
        }
    }

    private func displayModifierPrefix(flags: NSEvent.ModifierFlags) -> String {
        var prefix = ""
        if flags.contains(.control) { prefix += "⌃" }
        if flags.contains(.option) { prefix += "⌥" }
        if flags.contains(.shift) { prefix += "⇧" }
        if flags.contains(.command) { prefix += "⌘" }
        return prefix
    }
}
