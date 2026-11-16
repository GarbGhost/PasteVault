import AppKit
import Foundation

public enum ShortcutValidationResult: Equatable {
    case valid
    case missingModifier(String)
    case systemReserved(String)
    case internalConflict(combo: String, command: ShortcutCommand, commandName: String)

    public func message(in lang: AppLanguage) -> String {
        switch self {
        case .valid:
            return lang == .en ? "Available" : "Свободен"
        case .missingModifier(let keyDisplay):
            return lang == .en
                ? "[\(keyDisplay)] requires a modifier key (⌘, ⌥, or ⌃)"
                : "Клавиша [\(keyDisplay)] не подходит — добавьте ⌘, ⌥ или ⌃"
        case .systemReserved(let sysKey):
            return lang == .en
                ? "\(sysKey) is reserved by macOS"
                : "Комбинация \(sysKey) занята системой macOS"
        case .internalConflict(let comboDisplay, let cmd, _):
            let localizedCmdName = cmd.title(in: lang)
            return lang == .en
                ? "\(comboDisplay) is already assigned to \"\(localizedCmdName)\""
                : "Комбинация \(comboDisplay) уже используется для «\(localizedCmdName)»"
        }
    }
}

@MainActor
public final class ShortcutManager: ObservableObject {
    public static let shared = ShortcutManager()

    public static let userDefaultsKey = "PasteVault_ShortcutsConfig"
    public static let recordingDidStartNotification = Notification.Name("pasteVaultShortcutRecordingDidStart")
    public static let recordingDidStopNotification = Notification.Name("pasteVaultShortcutRecordingDidStop")

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
        if let data = AppDefaults.shared.data(forKey: Self.userDefaultsKey),
           let decoded = try? JSONDecoder().decode(ShortcutConfig.self, from: data) {
            self.config = decoded
        } else {
            self.config = .default
        }
    }

    private func saveConfig() {
        if let data = try? JSONEncoder().encode(config) {
            AppDefaults.shared.set(data, forKey: Self.userDefaultsKey)
        }
    }

    public func resetToDefaults() {
        config = .default
        stopRecording(clearFeedback: true)
    }

    // MARK: - Conflict Validation (No third-party process monitoring)
    public func validate(combo: KeyCombo, for command: ShortcutCommand, in lang: AppLanguage) -> ShortcutValidationResult {
        let flags = combo.modifierFlags

        let cleanedFlags = flags.subtracting([.numericPad, .function, .capsLock])
        let comboDisplay = formattedDisplayString(for: combo)
        let isAllowedEnterForPaste = (command == .pasteSelected) && (combo.keyCode == 36 || combo.keyCode == 76)
        if !isAllowedEnterForPaste && cleanedFlags.intersection([.command, .option, .control]).isEmpty {
            return .missingModifier(comboDisplay)
        }

        // 1. Системные комбинации macOS
        if cleanedFlags == .command {
            switch combo.keyCode {
            case 8: return .systemReserved("⌘C")
            case 9: return .systemReserved("⌘V")
            case 7: return .systemReserved("⌘X")
            case 0: return .systemReserved("⌘A")
            case 6: return .systemReserved("⌘Z")
            case 12: return .systemReserved("⌘Q")
            case 13: return .systemReserved("⌘W")
            case 4: return .systemReserved("⌘H")
            case 46: return .systemReserved("⌘M")
            case 48: return .systemReserved("⌘Tab")
            case 49: return .systemReserved("⌘Space")
            default: break
            }
        }
        if cleanedFlags == [.command, .option] {
            switch combo.keyCode {
            case 4: return .systemReserved("⌘⌥H")
            case 53: return .systemReserved("⌘⌥Esc")
            default: break
            }
        }

        // 2. Внутренний конфликт внутри Paste Vault
        let normalizedComboMods = cleanedFlags.rawValue
        for otherCmd in ShortcutCommand.allCases where otherCmd != command {
            let otherCombo = config[otherCmd]
            let normalizedOtherMods = otherCombo.modifierFlags.subtracting([.numericPad, .function, .capsLock]).rawValue

            if command == .quickPasteModifier || otherCmd == .quickPasteModifier {
                // Проверяем конкретную клавишу НЕ-quickPaste команды на совпадение с цифрами 1..9
                let specificKeyCode = (command == .quickPasteModifier) ? otherCombo.keyCode : combo.keyCode
                if normalizedComboMods == normalizedOtherMods && KeyCombo.digitKeyCodeMap[specificKeyCode] != nil {
                    return .internalConflict(combo: comboDisplay, command: otherCmd, commandName: otherCmd.title(in: lang))
                }
            } else if combo.keyCode == otherCombo.keyCode && normalizedComboMods == normalizedOtherMods {
                return .internalConflict(combo: comboDisplay, command: otherCmd, commandName: otherCmd.title(in: lang))
            }
        }

        return .valid
    }

    private func formattedDisplayString(for combo: KeyCombo) -> String {
        let trimmed = combo.displayString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        let cleanedFlags = combo.modifierFlags.subtracting([.numericPad, .function, .capsLock])
        let prefix = displayModifierPrefix(flags: cleanedFlags)
        let keyName = KeyCombo.keyName(for: combo.keyCode) ?? "\(combo.keyCode)"
        return "\(prefix)\(keyName)"
    }

    private var pendingQuickPasteModifiers: NSEvent.ModifierFlags = []

    // MARK: - Key Recording
    public func startRecording(for command: ShortcutCommand) {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        pendingQuickPasteModifiers = []
        recordingCommand = command
        isRecordingShortcut = true
        validationFeedback = nil

        prepareWindowForRecording()
        NotificationCenter.default.post(name: Self.recordingDidStartNotification, object: command)

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self = self else { return event }
            return self.handleRecordingMonitorEvent(event)
        }
    }

    private func prepareWindowForRecording() {
        let isSyntheticCLI = CommandLine.arguments.contains("--run-synthetic-tests")
        guard !DatabaseManager.isRunningTests, !isSyntheticCLI else { return }

        guard let targetWindow = NSApp.windows.first(where: {
            $0.isVisible && ($0 is NSPanel || $0.className.contains("FloatingPanel"))
        }) ?? NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }) else {
            return
        }

        NSTextInputContext.current?.discardMarkedText()
        targetWindow.makeFirstResponder(nil)
        NSApp.activate(ignoringOtherApps: true)
        targetWindow.makeKeyAndOrderFront(nil)
    }

    @discardableResult
    public func handleRecordingMonitorEvent(_ event: NSEvent) -> NSEvent? {
        guard isRecordingShortcut, let command = recordingCommand else {
            return event
        }

        // 1. Esc (53) без модификаторов — чистая отмена записи БЕЗ закрытия окна Paste Vault
        let cleanEscFlags = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.numericPad, .function, .capsLock])
        if event.type == .keyDown && event.keyCode == 53 && cleanEscFlags.isEmpty {
            self.stopRecording(clearFeedback: true)
            return nil
        }

        // 2. Для quickPasteModifier — поддерживаем 1 или 2+ модификатора (например ⌥ или ⌥⇧):
        //    накапливаем модификаторы при удержании и фиксируем при отпускании всех модификаторов или при нажатии цифры 1..9
        if command == .quickPasteModifier {
            let rawFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                .subtracting([.numericPad, .function, .capsLock])
            let modFlags = rawFlags.intersection([.command, .option, .control, .shift])

            if event.type == .flagsChanged {
                if !modFlags.isEmpty {
                    self.pendingQuickPasteModifiers.formUnion(modFlags)
                } else if !self.pendingQuickPasteModifiers.isEmpty {
                    let chosen = self.pendingQuickPasteModifiers
                    self.pendingQuickPasteModifiers = []
                    let modPrefix = self.displayModifierPrefix(flags: chosen)
                    let combo = KeyCombo(keyCode: 0, modifiers: chosen.rawValue, displayString: "\(modPrefix)1..\(modPrefix)9")
                    let valResult = self.validate(combo: combo, for: .quickPasteModifier, in: AppLanguage.current)
                    self.validationFeedback = (.quickPasteModifier, valResult)
                    if case .valid = valResult {
                        self.config.quickPasteModifier = combo
                        self.stopRecording(clearFeedback: true)
                    }
                }
                return nil
            }
        }

        // 3. Для остальных команд — flagsChanged поглощаем и ждём реальный keyDown
        if event.type == .flagsChanged {
            return nil
        }

        // 4. Реальный keyDown
        self.handleRecordedEvent(event, for: command)
        return nil
    }

    public func stopRecording(clearFeedback: Bool = true) {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        let wasRecording = isRecordingShortcut || (recordingCommand != nil)
        pendingQuickPasteModifiers = []
        recordingCommand = nil
        isRecordingShortcut = false
        if clearFeedback {
            validationFeedback = nil
        }
        if wasRecording {
            NotificationCenter.default.post(name: Self.recordingDidStopNotification, object: nil)
        }
    }

    private func handleRecordedEvent(_ event: NSEvent, for command: ShortcutCommand) {
        let rawFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.numericPad, .function, .capsLock])

        // Игнорируем нажатия только клавиш-модификаторов (Shift, Ctrl, Alt, Cmd)
        let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
        if modifierKeyCodes.contains(event.keyCode) {
            return
        }

        // Для quickPasteModifier разрешаем нажать модификатор(ы) + любую цифру 1-9
        if command == .quickPasteModifier {
            let modFlags = rawFlags.intersection([.command, .option, .control, .shift])
            if modFlags.isEmpty {
                let keyName = KeyCombo.keyName(for: event.keyCode)
                    ?? event.charactersIgnoringModifiers?.uppercased()
                    ?? "\(event.keyCode)"
                self.validationFeedback = (command, .missingModifier(keyName))
                return
            }
            let modPrefix = displayModifierPrefix(flags: modFlags)
            let combo = KeyCombo(keyCode: 0, modifiers: modFlags.rawValue, displayString: "\(modPrefix)1..\(modPrefix)9")
            let valResult = validate(combo: combo, for: .quickPasteModifier, in: AppLanguage.current)
            self.validationFeedback = (command, valResult)
            if case .valid = valResult {
                self.config.quickPasteModifier = combo
                self.stopRecording(clearFeedback: true)
            }
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
            self.stopRecording(clearFeedback: true)
        case .missingModifier, .systemReserved, .internalConflict:
            // Оставляем запись открытой и даем понятную обратную связь
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
