import AppKit
import ApplicationServices
import Foundation

public struct AccessibilityDiagnosticReport: Sendable {
    public let axIsProcessTrusted: Bool
    public let bundleIdentifier: String
    public let bundlePath: String
    public let executablePath: String
    public let isRunningFromAppBundle: Bool
    public let duplicateAppPaths: [String]

    public init(
        axIsProcessTrusted: Bool,
        bundleIdentifier: String,
        bundlePath: String,
        executablePath: String,
        isRunningFromAppBundle: Bool,
        duplicateAppPaths: [String]
    ) {
        self.axIsProcessTrusted = axIsProcessTrusted
        self.bundleIdentifier = bundleIdentifier
        self.bundlePath = bundlePath
        self.executablePath = executablePath
        self.isRunningFromAppBundle = isRunningFromAppBundle
        self.duplicateAppPaths = duplicateAppPaths
    }

    public var isFullyOperational: Bool {
        axIsProcessTrusted
    }

    public func diagnosticString(in lang: AppLanguage = .ru) -> String {
        if axIsProcessTrusted {
            return lang == .en
                ? "TCC Kernel Status: Granted (AXIsProcessTrusted = true)"
                : "Статус ядра TCC: Разрешено (AXIsProcessTrusted = true)"
        } else {
            return lang == .en
                ? "TCC Kernel Status: Waiting for toggle (AXIsProcessTrusted = false)"
                : "Статус ядра TCC: Ожидает включения тумблера (AXIsProcessTrusted = false)"
        }
    }
}

public enum AccessibilityService {
    /// Проверка реального доступа в TCC ядра macOS: проверяет ТОЛЬКО AXIsProcessTrusted()
    public static func isAccessibilityTrusted() -> Bool {
        return AXIsProcessTrusted()
    }

    /// Точная пассивная диагностика состояния (без SystemWide-запросов и без авто-добавления в TCC)
    public static func runDiagnostics() -> AccessibilityDiagnosticReport {
        let trusted = AXIsProcessTrusted()
        let bId = Bundle.main.bundleIdentifier ?? "com.pastevault.app"
        let bPath = Bundle.main.bundlePath
        let execPath = Bundle.main.executablePath ?? "unknown"
        let isAppBundle = bPath.hasSuffix(".app")

        var foundDuplicates: [String] = []
        let candidatePaths = [
            "/Applications/Paste Vault.app",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Paste Vault.app").path
        ]
        let currentStandardPath = URL(fileURLWithPath: bPath).resolvingSymlinksInPath().standardized.path
        for path in candidatePaths {
            let std = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardized.path
            if FileManager.default.fileExists(atPath: std) && std != currentStandardPath && !foundDuplicates.contains(std) {
                foundDuplicates.append(std)
            }
        }

        return AccessibilityDiagnosticReport(
            axIsProcessTrusted: trusted,
            bundleIdentifier: bId,
            bundlePath: bPath,
            executablePath: execPath,
            isRunningFromAppBundle: isAppBundle,
            duplicateAppPaths: foundDuplicates
        )
    }

    /// Сбрасывает старую запись TCC для приложения через tccutil
    public static func resetTCCRecord() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        task.arguments = ["reset", "Accessibility", "com.pastevault.app"]
        try? task.run()
        task.waitUntilExit()
    }

    /// Вызывает ТОЛЬКО нативный системный вызов macOS для регистрации и показа окна запроса Apple
    public static func requestAccessPrompt() {
        resetTCCRecord()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.UniversalAccessAuthWarn").first?.activate(options: [.activateAllWindows])
            }
        }
    }

    /// Открывает системные настройки ровно на странице «Конфиденциальность → Универсальный доступ» БЕЗ prompt
    public static func openSystemSettingsOnly() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Вызывает системный запрос Apple без принудительного открытия Системных настроек
    public static func requestAndOpenAccessibility() {
        requestAccessPrompt()
    }

    /// Открывает системные настройки ровно на странице «Конфиденциальность → Универсальный доступ» или запрашивает доступ.
    public static func openAccessibilitySettings(triggerSystemPrompt: Bool = false) {
        if triggerSystemPrompt {
            requestAccessPrompt()
        } else {
            openSystemSettingsOnly()
        }
    }
}
