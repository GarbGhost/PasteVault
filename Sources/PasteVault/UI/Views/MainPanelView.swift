import SwiftUI
import AppKit
import ApplicationServices
import CoreText
import UniformTypeIdentifiers
import AVFoundation
import Combine

extension Notification.Name {
    public static let pasteVaultDidCaptureItem = Notification.Name("pasteVaultDidCaptureItem")
}

// MARK: - Localization System (RU / EN)
public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case ru = "ru"
    case en = "en"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .ru: return "Русский"
        case .en: return "English"
        }
    }

    public var displayName: String { title }

    public var flagEmoji: String {
        shortCode
    }

    public var flagAndTitle: String {
        title
    }

    public var shortCode: String {
        switch self {
        case .ru: return "RU"
        case .en: return "EN"
        }
    }

    public static var current: AppLanguage {
        let raw = UserDefaults.standard.string(forKey: "appLanguage") ?? AppLanguage.ru.rawValue
        return AppLanguage(rawValue: raw) ?? .ru
    }
}

@inline(__always)
public func tr(_ ru: String, _ en: String, lang: AppLanguage = AppLanguage.current) -> String {
    lang == .en ? en : ru
}

// MARK: - Navigation Tabs
public enum AppTab: String, CaseIterable, Identifiable {
    case clipboard = "Буфер обмена"
    case snippets = "Фрагменты"
    case passgen = "Пароли"
    case settings = "Настройки"

    public var id: String { rawValue }

    public func title(in lang: AppLanguage) -> String {
        switch self {
        case .clipboard: return lang == .en ? "Clipboard" : "Буфер обмена"
        case .snippets: return lang == .en ? "Snippets" : "Фрагменты"
        case .passgen: return lang == .en ? "PassGen" : "Пароли"
        case .settings: return lang == .en ? "Settings" : "Настройки"
        }
    }

    public var icon: String {
        switch self {
        case .clipboard: return "doc.on.clipboard.fill"
        case .snippets: return "bolt.fill"
        case .passgen: return "key.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

// MARK: - Filter Categories
public enum FilterCategory: String, CaseIterable, Identifiable {
    case all = "Все типы"
    case pinned = "Избранные"
    case text = "Текст"
    case file = "Файлы"
    case url = "Ссылки"
    case code = "Код и JSON"
    case image = "Скриншоты"
    case secret = "Пароли и ключи"
    case color = "Цвета"

    public var id: String { rawValue }

    public func title(in lang: AppLanguage) -> String {
        switch self {
        case .all: return lang == .en ? "All Types" : "Все типы"
        case .pinned: return lang == .en ? "Pinned / Favorites" : "Избранные (Закреплённые)"
        case .text: return lang == .en ? "Text" : "Текст"
        case .file: return lang == .en ? "Files" : "Файлы"
        case .url: return lang == .en ? "Links" : "Ссылки"
        case .code: return lang == .en ? "Code & JSON" : "Код и JSON"
        case .image: return lang == .en ? "Screenshots" : "Скриншоты"
        case .secret: return lang == .en ? "Passwords & Keys" : "Пароли и ключи"
        case .color: return lang == .en ? "Colors" : "Цвета"
        }
    }

    public var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .pinned: return "pin.fill"
        case .text: return "text.alignleft"
        case .file: return "doc.fill"
        case .url: return "link"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .image: return "photo"
        case .secret: return "key.fill"
        case .color: return "paintpalette.fill"
        }
    }
}

// MARK: - Settings Sidebar Navigation
public enum SettingsSidebarSection: String, CaseIterable, Identifiable {
    case system = "system"
    case appearance = "appearance"
    case memory = "memory"
    case blacklist = "blacklist"
    case hotkeys = "hotkeys"

    public var id: String { rawValue }

    public func title(in lang: AppLanguage) -> String {
        switch self {
        case .system: return lang == .en ? "System" : "Система"
        case .appearance: return lang == .en ? "Appearance" : "Оформление"
        case .memory: return lang == .en ? "Memory" : "Память"
        case .blacklist: return lang == .en ? "Blacklist" : "Чёрный список"
        case .hotkeys: return lang == .en ? "Hotkeys" : "Клавиши"
        }
    }

    public var icon: String {
        switch self {
        case .system: return "gearshape.2"
        case .appearance: return "paintpalette"
        case .memory: return "memorychip"
        case .blacklist: return "hand.raised"
        case .hotkeys: return "command"
        }
    }
}

public enum ClipboardFilterSelection: Hashable {
    case category(FilterCategory)
    case tag(String)

    public var title: String {
        title(in: AppLanguage.current)
    }

    public func title(in lang: AppLanguage) -> String {
        switch self {
        case .category(let cat):
            return cat.title(in: lang)
        case .tag(let tag):
            return Self.localizedTag(tag, in: lang)
        }
    }

    public static func localizedTag(_ tag: String, in lang: AppLanguage) -> String {
        guard lang == .en else { return tag }
        switch tag {
        case "#UTM-трекер": return "#UTM-Tracker"
        case "Цвет": return "Color"
        default: return tag
        }
    }

    public var icon: String {
        switch self {
        case .category(let cat): return cat.icon
        case .tag: return "tag.fill"
        }
    }
}

// MARK: - App Theme & Visual System
public enum AppTheme: String, CaseIterable, Identifiable {
    // 5 стеклянных тем (с прозрачностью и размытием)
    case obsidian = "obsidian"
    case midnight = "midnight"
    case emerald = "emerald"
    case amber = "amber"
    case frost = "frost"

    // 5 тем Solid Matte (Монолитные плотные матовые без прозрачности)
    case nordicSlate = "nordicSlate"
    case tokyoNight = "tokyoNight"
    case catppuccinMocha = "catppuccinMocha"
    case solarizedPaper = "solarizedPaper"
    case carbonBrutalist = "carbonBrutalist"

    public var id: String { rawValue }

    public var title: String {
        title(in: AppLanguage.current)
    }

    public func title(in lang: AppLanguage) -> String {
        switch self {
        case .obsidian: return lang == .en ? "Obsidian" : "Обсидиан"
        case .midnight: return lang == .en ? "Midnight" : "Полночь"
        case .emerald: return lang == .en ? "Emerald" : "Изумруд"
        case .amber: return lang == .en ? "Amber" : "Янтарь"
        case .frost: return lang == .en ? "Frost" : "Иней"
        case .nordicSlate: return lang == .en ? "Slate" : "Сланец"
        case .tokyoNight: return lang == .en ? "Tokyo" : "Токио"
        case .catppuccinMocha: return lang == .en ? "Mocha" : "Мокко"
        case .solarizedPaper: return lang == .en ? "Paper" : "Бумага"
        case .carbonBrutalist: return lang == .en ? "Carbon" : "Карбон"
        }
    }

    public var subtitle: String {
        switch self {
        case .obsidian: return "Obsidian Dark"
        case .midnight: return "Midnight Purple"
        case .emerald: return "Emerald Matrix"
        case .amber: return "Warm Amber"
        case .frost: return "Frost Light"
        case .nordicSlate: return "Nordic Slate (Matte)"
        case .tokyoNight: return "Tokyo Night (Matte)"
        case .catppuccinMocha: return "Catppuccin Mocha (Matte)"
        case .solarizedPaper: return "Solarized Paper (Matte)"
        case .carbonBrutalist: return "Carbon Brutalist (Matte)"
        }
    }

    public var usesLiquidGlass: Bool {
        switch self {
        case .obsidian, .midnight, .emerald, .amber, .frost:
            return true
        case .nordicSlate, .tokyoNight, .catppuccinMocha, .solarizedPaper, .carbonBrutalist:
            return false
        }
    }

    public var isLight: Bool {
        switch self {
        case .frost, .solarizedPaper:
            return true
        default:
            return false
        }
    }

    public var isDark: Bool {
        !isLight
    }

    public var backgroundHex: String {
        switch self {
        case .obsidian: return "#0F172A"
        case .midnight: return "#13111C"
        case .emerald: return "#0A1612"
        case .amber: return "#1C1917"
        case .frost: return "#F1F5F9"
        case .nordicSlate: return "#2E3440"
        case .tokyoNight: return "#1A1B26"
        case .catppuccinMocha: return "#1E1E2E"
        case .solarizedPaper: return "#FDF6E3"
        case .carbonBrutalist: return "#121212"
        }
    }

    public var accentHex: String {
        switch self {
        case .obsidian: return "#38BDF8"
        case .midnight: return "#A855F7"
        case .emerald: return "#10B981"
        case .amber: return "#F59E0B"
        case .frost: return "#0284C7"
        case .nordicSlate: return "#88C0D0"
        case .tokyoNight: return "#7AA2F7"
        case .catppuccinMocha: return "#CBA6F7"
        case .solarizedPaper: return "#268BD2"
        case .carbonBrutalist: return "#FF5722"
        }
    }

    public var cardHex: String {
        switch self {
        case .obsidian: return "#1E293B"
        case .midnight: return "#1F1A2E"
        case .emerald: return "#13231D"
        case .amber: return "#292524"
        case .frost: return "#E2E8F0"
        case .nordicSlate: return "#3B4252"
        case .tokyoNight: return "#24283B"
        case .catppuccinMocha: return "#313244"
        case .solarizedPaper: return "#EEE8D5"
        case .carbonBrutalist: return "#1E1E1E"
        }
    }

    public var borderHex: String {
        switch self {
        case .nordicSlate: return "#4C566A"
        case .tokyoNight: return "#414868"
        case .catppuccinMocha: return "#45475A"
        case .solarizedPaper: return "#D3CBB7"
        case .carbonBrutalist: return "#333333"
        default: return ""
        }
    }

    public var backgroundColor: Color {
        Color(nsColor: SmartClassifier.parseNSColor(backgroundHex) ?? .windowBackgroundColor)
    }

    public var accentColor: Color {
        Color(nsColor: SmartClassifier.parseNSColor(accentHex) ?? .systemCyan)
    }

    public var cardColor: Color {
        Color(nsColor: SmartClassifier.parseNSColor(cardHex) ?? .controlBackgroundColor)
    }

    public var primaryText: Color {
        switch self {
        case .nordicSlate: return Color(nsColor: SmartClassifier.parseNSColor("#ECEFF4")!)
        case .tokyoNight: return Color(nsColor: SmartClassifier.parseNSColor("#C0CAF5")!)
        case .catppuccinMocha: return Color(nsColor: SmartClassifier.parseNSColor("#CDD6F4")!)
        case .solarizedPaper: return Color(nsColor: SmartClassifier.parseNSColor("#073642")!)
        case .carbonBrutalist: return Color(nsColor: SmartClassifier.parseNSColor("#F5F5F5")!)
        default:
            return isLight ? Color(red: 0.06, green: 0.09, blue: 0.16) : Color.white
        }
    }

    public var secondaryText: Color {
        switch self {
        case .nordicSlate: return Color(nsColor: SmartClassifier.parseNSColor("#D8DEE9")!)
        case .tokyoNight: return Color(nsColor: SmartClassifier.parseNSColor("#9AA5CE")!)
        case .catppuccinMocha: return Color(nsColor: SmartClassifier.parseNSColor("#BAC2DE")!)
        case .solarizedPaper: return Color(nsColor: SmartClassifier.parseNSColor("#586E75")!)
        case .carbonBrutalist: return Color(nsColor: SmartClassifier.parseNSColor("#A0A0A0")!)
        default:
            return isLight ? Color(red: 0.20, green: 0.25, blue: 0.33) : Color(red: 0.82, green: 0.86, blue: 0.92)
        }
    }

    public var mutedText: Color {
        isLight
            ? Color(red: 0.30, green: 0.36, blue: 0.45)
            : Color(red: 0.68, green: 0.74, blue: 0.82)
    }

    public func cardFill(opacity: Double) -> Color {
        if !usesLiquidGlass {
            return cardColor
        }
        if isLight {
            return Color(red: 0.97, green: 0.98, blue: 1.0).opacity(0.06 + opacity * 0.68)
        } else {
            return backgroundColor.opacity(0.06 + opacity * 0.55)
        }
    }

    public func panelFill(opacity: Double) -> Color {
        if !usesLiquidGlass {
            return backgroundColor
        }
        if isLight {
            return Color(red: 0.95, green: 0.97, blue: 1.0).opacity(opacity * 0.75)
        } else {
            return backgroundColor.opacity(opacity * 0.75)
        }
    }

    public var badgeFill: Color {
        isLight ? accentColor.opacity(0.16) : accentColor.opacity(0.24)
    }

    public var badgeText: Color {
        isLight ? Color(red: 0.01, green: 0.36, blue: 0.62) : accentColor
    }

    public var cardBackground: Color {
        cardFill(opacity: 0.85)
    }

    public var selectedCardBackground: Color {
        accentColor.opacity(isLight ? 0.20 : 0.26)
    }

    public var borderColor: Color {
        if !usesLiquidGlass, let col = SmartClassifier.parseNSColor(borderHex) {
            return Color(nsColor: col)
        }
        return isLight ? Color(red: 0.06, green: 0.09, blue: 0.16).opacity(0.18) : Color.white.opacity(0.16)
    }
}

public struct VisualEffectBlur: NSViewRepresentable {
    public var material: NSVisualEffectView.Material
    public var blendingMode: NSVisualEffectView.BlendingMode

    public init(
        material: NSVisualEffectView.Material = .hudWindow,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    ) {
        self.material = material
        self.blendingMode = blendingMode
    }

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.wantsLayer = true
        view.layer?.cornerRadius = 20
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.isEmphasized = true
        view.appearance = NSAppearance(named: material == .hudWindow ? .darkAqua : .aqua)
        return view
    }

    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        if nsView.layer?.cornerRadius != 20 {
            nsView.wantsLayer = true
            nsView.layer?.cornerRadius = 20
            nsView.layer?.cornerCurve = .continuous
            nsView.layer?.masksToBounds = true
        }
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = .active
        nsView.isEmphasized = true
        nsView.appearance = NSAppearance(named: material == .hudWindow ? .darkAqua : .aqua)
    }
}

// MARK: - 6 Free Fonts System (Inter default) & FontManager
public enum AppFont: String, CaseIterable, Identifiable, Sendable {
    case inter = "inter"
    case manrope = "manrope"
    case jetBrainsMono = "jetBrainsMono"
    case jura = "jura"
    case tektur = "tektur"
    case comfortaa = "comfortaa"

    public static let `default`: AppFont = .inter

    public static var current: AppFont {
        AppFont(fromRaw: UserDefaults.standard.string(forKey: "selectedFontId"))
    }

    public init(fromRaw: String?) {
        guard let fromRaw = fromRaw else {
            self = .inter
            return
        }
        if fromRaw == "jetbrains" {
            self = .jetBrainsMono
            return
        }
        self = AppFont(rawValue: fromRaw) ?? .inter
    }

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .inter: return "Inter"
        case .manrope: return "Manrope"
        case .jetBrainsMono: return "JetBrains Mono"
        case .jura: return "Jura"
        case .tektur: return "Tektur"
        case .comfortaa: return "Comfortaa"
        }
    }

    public var subtitle: String {
        subtitle(in: AppLanguage.current)
    }

    public func subtitle(in lang: AppLanguage) -> String {
        switch self {
        case .inter: return lang == .en ? "Modern UI Standard" : "Современный UI-стандарт"
        case .manrope: return lang == .en ? "Geometric Cyrillic & Latin" : "Геометрический, кириллица"
        case .jetBrainsMono: return lang == .en ? "Monospace for Code" : "Моноширинный для кода"
        case .jura: return lang == .en ? "Cosmic Sci-Fi Interface" : "Космический Sci-Fi интерфейс"
        case .tektur: return lang == .en ? "Cyberpunk 45° Chamfered" : "Киберпанк с гранёными углами"
        case .comfortaa: return lang == .en ? "Soft Teardrop Geo-Art" : "Мягкий каплевидный гео-арт"
        }
    }

    public var isUnusual: Bool {
        switch self {
        case .jura, .tektur, .comfortaa:
            return true
        default:
            return false
        }
    }

    /// Локальный системный fallback macOS, если веб-шрифт ещё скачивается
    private var macOSFallbackFamily: String? {
        switch self {
        case .inter: return "Helvetica Neue"
        case .manrope: return "Avenir Next"
        case .jetBrainsMono: return "Menlo"
        case .jura: return "Didot"
        case .tektur: return "Copperplate"
        case .comfortaa: return "Avenir Next"
        }
    }

    @MainActor
    public func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if let psName = FontManager.shared.resolvedPostScriptNames[self] {
            return Font.custom(psName, size: size).weight(weight)
        }
        if let fallback = macOSFallbackFamily {
            return Font.custom(fallback, size: size).weight(weight)
        }
        return .system(size: size, weight: weight, design: .default)
    }

    @MainActor
    public func nsFont(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        if let psName = FontManager.shared.resolvedPostScriptNames[self],
           let customFont = NSFont(name: psName, size: size) {
            return customFont
        }
        if let fallback = macOSFallbackFamily,
           let fallbackFont = NSFont(name: fallback, size: size) {
            return fallbackFont
        }
        return NSFont.systemFont(ofSize: size, weight: weight)
    }
}

@MainActor
public final class FontManager: ObservableObject {
    public static let shared = FontManager()

    @Published public var resolvedPostScriptNames: [AppFont: String] = [:]

    private struct RemoteFontSpec: Sendable {
        let appFont: AppFont
        let filename: String
        let legacyFilename: String
        let urlString: String
    }

    private let specs: [RemoteFontSpec] = [
        RemoteFontSpec(
            appFont: .inter,
            filename: "Inter.ttf",
            legacyFilename: "PasteVault-Inter.ttf",
            urlString: "https://raw.githubusercontent.com/google/fonts/main/ofl/inter/Inter%5Bopsz%2Cwght%5D.ttf"
        ),
        RemoteFontSpec(
            appFont: .manrope,
            filename: "Manrope.ttf",
            legacyFilename: "PasteVault-Manrope.ttf",
            urlString: "https://raw.githubusercontent.com/google/fonts/main/ofl/manrope/Manrope%5Bwght%5D.ttf"
        ),
        RemoteFontSpec(
            appFont: .jetBrainsMono,
            filename: "JetBrainsMono.ttf",
            legacyFilename: "PasteVault-JetBrainsMono.ttf",
            urlString: "https://raw.githubusercontent.com/google/fonts/main/ofl/jetbrainsmono/JetBrainsMono%5Bwght%5D.ttf"
        ),
        RemoteFontSpec(
            appFont: .jura,
            filename: "Jura.ttf",
            legacyFilename: "PasteVault-Jura.ttf",
            urlString: "https://raw.githubusercontent.com/google/fonts/main/ofl/jura/Jura%5Bwght%5D.ttf"
        ),
        RemoteFontSpec(
            appFont: .tektur,
            filename: "Tektur.ttf",
            legacyFilename: "PasteVault-Tektur.ttf",
            urlString: "https://raw.githubusercontent.com/google/fonts/main/ofl/tektur/Tektur%5Bwdth%2Cwght%5D.ttf"
        ),
        RemoteFontSpec(
            appFont: .comfortaa,
            filename: "Comfortaa.ttf",
            legacyFilename: "PasteVault-Comfortaa.ttf",
            urlString: "https://raw.githubusercontent.com/google/fonts/main/ofl/comfortaa/Comfortaa%5Bwght%5D.ttf"
        )
    ]

    private init() {
        registerExistingFontsSynchronously()
    }

    nonisolated private static func registerAndExtractPostScriptName(at fileURL: URL) -> String? {
        CTFontManagerRegisterFontsForURL(fileURL as CFURL, .process, nil)
        if let descriptors = CTFontManagerCreateFontDescriptorsFromURL(fileURL as CFURL) as? [CTFontDescriptor],
           let first = descriptors.first {
            if let familyName = CTFontDescriptorCopyAttribute(first, kCTFontFamilyNameAttribute) as? String,
               !familyName.isEmpty,
               NSFont(name: familyName, size: 13) != nil {
                return familyName
            }
            if let psName = CTFontDescriptorCopyAttribute(first, kCTFontNameAttribute) as? String,
               !psName.isEmpty {
                return psName
            }
        }
        guard let provider = CGDataProvider(url: fileURL as CFURL),
              let cgFont = CGFont(provider),
              let psName = cgFont.postScriptName as String? else {
            return nil
        }
        return psName
    }

    private func candidateFontDirectories() -> [URL] {
        var dirs: [URL] = []
        if let bundleFonts = Bundle.main.resourceURL?.appendingPathComponent("Fonts", isDirectory: true) {
            dirs.append(bundleFonts)
        }
        dirs.append(Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/Fonts", isDirectory: true))
        dirs.append(URL(fileURLWithPath: "/Applications/Paste Vault.app/Contents/Resources/Fonts", isDirectory: true))
        // Локальный путь исходников (только для прогона swift test при разработке, без привязки к /Users/...)
        let sourceRepoFonts = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/Fonts", isDirectory: true)
        dirs.append(sourceRepoFonts)
        let vaultFontsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Fonts/PasteVaultFonts", isDirectory: true)
        dirs.append(vaultFontsDir)
        return dirs
    }

    private func registerExistingFontsSynchronously() {
        let baseFontsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Fonts", isDirectory: true)
        let vaultFontsDir = baseFontsDir.appendingPathComponent("PasteVaultFonts", isDirectory: true)
        try? FileManager.default.createDirectory(at: vaultFontsDir, withIntermediateDirectories: true)

        let searchDirs = candidateFontDirectories()
        var updatedMap = resolvedPostScriptNames
        for spec in specs {
            var resolvedURL: URL? = nil
            for dir in searchDirs {
                let candidate = dir.appendingPathComponent(spec.filename)
                if FileManager.default.fileExists(atPath: candidate.path) {
                    resolvedURL = candidate
                    break
                }
            }
            if resolvedURL == nil {
                let legacyURL = baseFontsDir.appendingPathComponent(spec.legacyFilename)
                if FileManager.default.fileExists(atPath: legacyURL.path) {
                    let vaultCopy = vaultFontsDir.appendingPathComponent(spec.filename)
                    try? FileManager.default.copyItem(at: legacyURL, to: vaultCopy)
                    resolvedURL = FileManager.default.fileExists(atPath: vaultCopy.path) ? vaultCopy : legacyURL
                }
            }
            if let fileURL = resolvedURL,
               let psName = Self.registerAndExtractPostScriptName(at: fileURL) {
                updatedMap[spec.appFont] = psName
                // Если шрифт найден в бандле, но ещё не скопирован в локальный кэш пользователя — синхронизируем
                let userCacheURL = vaultFontsDir.appendingPathComponent(spec.filename)
                if !FileManager.default.fileExists(atPath: userCacheURL.path) && fileURL != userCacheURL {
                    try? FileManager.default.copyItem(at: fileURL, to: userCacheURL)
                }
            }
        }
        if updatedMap != resolvedPostScriptNames {
            resolvedPostScriptNames = updatedMap
        }
    }

    public func ensureFontsInstalled() {
        registerExistingFontsSynchronously()

        let vaultFontsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Fonts/PasteVaultFonts", isDirectory: true)
        try? FileManager.default.createDirectory(at: vaultFontsDir, withIntermediateDirectories: true)

        let missingSpecs = specs.filter { spec in
            let fileURL = vaultFontsDir.appendingPathComponent(spec.filename)
            return !FileManager.default.fileExists(atPath: fileURL.path) || resolvedPostScriptNames[spec.appFont] == nil
        }

        guard !missingSpecs.isEmpty else { return }

        Task.detached(priority: .utility) {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 8.0
            config.timeoutIntervalForResource = 16.0
            let session = URLSession(configuration: config)

            var newlyResolved: [(AppFont, String)] = []
            for spec in missingSpecs {
                let destURL = vaultFontsDir.appendingPathComponent(spec.filename)
                if FileManager.default.fileExists(atPath: destURL.path),
                   let psName = Self.registerAndExtractPostScriptName(at: destURL) {
                    newlyResolved.append((spec.appFont, psName))
                    continue
                }
                guard let url = URL(string: spec.urlString) else { continue }
                do {
                    let (data, response) = try await session.data(from: url)
                    if let http = response as? HTTPURLResponse, http.statusCode == 200, data.count > 10_000 {
                        try data.write(to: destURL, options: .atomic)
                        if let psName = Self.registerAndExtractPostScriptName(at: destURL) {
                            newlyResolved.append((spec.appFont, psName))
                        }
                    }
                } catch {
                    // Используем системный fallback при отсутствии сети
                }
            }

            if !newlyResolved.isEmpty {
                let itemsToUpdate = newlyResolved
                await MainActor.run {
                    for (appFont, psName) in itemsToUpdate {
                        FontManager.shared.resolvedPostScriptNames[appFont] = psName
                    }
                    NotificationCenter.default.post(name: Notification.Name("pasteVaultFontsUpdated"), object: nil)
                }
            }
        }
    }
}

// MARK: - Isolated 1s Countdown Subview (Zero Global Redraws)
public struct SecretCountdownLabel: View {
    public let expiresAt: Date
    public let compact: Bool
    public let language: AppLanguage

    public init(expiresAt: Date, compact: Bool, language: AppLanguage = AppLanguage.current) {
        self.expiresAt = expiresAt
        self.compact = compact
        self.language = language
    }

    public var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { context in
            let remaining = max(0, Int(ceil(expiresAt.timeIntervalSince(context.date))))
            if compact {
                HStack(spacing: 3) {
                    Image(systemName: "timer")
                        .symbolRenderingMode(.monochrome)
                        .font(.system(size: 9, weight: .bold))
                    Text(tr("\(remaining) сек ✕", "\(remaining)s ✕", lang: language))
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                }
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            } else {
                HStack(spacing: 5) {
                    Image(systemName: "timer")
                        .symbolRenderingMode(.monochrome)
                        .font(.system(size: 11, weight: .bold))
                    Text(tr("Удалится через \(remaining) сек", "Purges in \(remaining)s", lang: language))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
        }
    }
}

// MARK: - Native QR Code Generator Popover (CoreImage CIQRCodeGenerator ~180x180)
public struct QRCodePopoverView: View {
    public let url: String
    public let theme: AppTheme
    public let language: AppLanguage
    @AppStorage("selectedFontId") private var selectedFontId: String = AppFont.default.rawValue

    private var currentFont: AppFont {
        AppFont(fromRaw: selectedFontId)
    }

    private var qrImage: NSImage? {
        guard let data = url.data(using: .utf8) else { return nil }
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let outputCI = filter.outputImage else { return nil }

        let extent = outputCI.extent
        guard extent.width > 0, extent.height > 0 else { return nil }
        let scale = 180.0 / extent.width
        let transformed = outputCI.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext()
        guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: 180, height: 180))
    }

    public var body: some View {
        VStack(spacing: 12) {
            Text(tr("Сканируйте QR-код", "Scan QR Code", lang: language))
                .font(currentFont.font(size: 13, weight: .bold))
                .foregroundStyle(theme.primaryText)

            if let img = qrImage {
                Image(nsImage: img)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 180, height: 180)
                    .padding(8)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(theme.primaryText.opacity(0.15), lineWidth: 1)
                    )
            } else {
                Text(tr("Не удалось создать QR-код", "Could not generate QR code", lang: language))
                    .font(currentFont.font(size: 11, weight: .regular))
                    .foregroundStyle(theme.secondaryText)
                    .frame(width: 180, height: 180)
            }

            Text(url)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(theme.secondaryText)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 200)
        }
        .padding(14)
        .background(theme.panelFill(opacity: 0.96))
    }
}

// MARK: - Mechanical Taptic Audio & Haptic Feedback Synthesizer
public final class TapticSoundAndHaptics {
    public static let shared = TapticSoundAndHaptics()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var tickBuffer: AVAudioPCMBuffer?
    private var confirmBuffer: AVAudioPCMBuffer?
    private let queue = DispatchQueue(label: "com.pastevault.tapticsound", qos: .userInteractive)
    private let lock = NSLock()

    /// Минимальный интервал между микро-щелчками (строгий debounce >= 85 мс для защиты от двойного щелчка)
    public static let minTickInterval: TimeInterval = 0.085
    /// Время последнего щелчка — защищено lock по monotonic clock
    private var lastTickTime: TimeInterval = 0
    /// Время последнего тактильного отклика — изменяется ТОЛЬКО на главном потоке
    private var lastHapticTime: TimeInterval = 0

    private init() {
        // Аудио-движок поднимается один раз и асинхронно — первый клик в UI не блокирует @MainActor
        queue.async { [weak self] in
            self?.setupAudio()
        }
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { [weak self] _ in
            self?.queue.async {
                try? self?.engine.start()
                self?.player.play()
            }
        }
    }

    /// Прогрев синглтона при запуске приложения (setup выполняется в фоне)
    public static func warmUp() {
        _ = shared
    }

    private func setupAudio() {
        let mixerFormat = engine.mainMixerNode.outputFormat(forBus: 0)
        let sampleRate: Double = mixerFormat.sampleRate > 8000 ? mixerFormat.sampleRate : 44100.0
        let channels: AVAudioChannelCount = max(1, mixerFormat.channelCount)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels) else { return }

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.90

        // 1. Короткий 10-миллисекундный сухой механический тактильный микрощелчок
        let tickFrames = AVAudioFrameCount(sampleRate * 0.010)
        if let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: tickFrames) {
            buf.frameLength = tickFrames
            if let channelData = buf.floatChannelData {
                for i in 0..<Int(tickFrames) {
                    let t = Double(i) / sampleRate
                    let decay = exp(-t * 700.0)
                    let freq = 1800.0 * (1.0 - t * 45.0)
                    let sample = Float(sin(2.0 * .pi * freq * t) * decay * 0.85)
                    for ch in 0..<Int(channels) {
                        channelData[ch][i] = sample
                    }
                }
            }
            tickBuffer = buf
        }

        // 2. Двойной тактильный щелчок подтверждения (два микро-импульса через 18 мс)
        let confirmFrames = AVAudioFrameCount(sampleRate * 0.035)
        if let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: confirmFrames) {
            buf.frameLength = confirmFrames
            if let channelData = buf.floatChannelData {
                for i in 0..<Int(confirmFrames) {
                    let t = Double(i) / sampleRate
                    var sample = 0.0
                    if t < 0.009 {
                        let d = exp(-t * 750.0)
                        sample += sin(2.0 * .pi * 1500.0 * t) * d * 0.80
                    }
                    if t >= 0.018 && t < 0.027 {
                        let t2 = t - 0.018
                        let d = exp(-t2 * 750.0)
                        sample += sin(2.0 * .pi * 2200.0 * t2) * d * 0.85
                    }
                    let sampleF = Float(sample)
                    for ch in 0..<Int(channels) {
                        channelData[ch][i] = sampleF
                    }
                }
            }
            confirmBuffer = buf
        }

        do {
            try engine.start()
            player.play()
        } catch {}
    }

    private func ensureEngineRunning() {
        if !engine.isRunning {
            try? engine.start()
        }
        if !player.isPlaying {
            player.play()
        }
    }

    public static var isAudioFeedbackEnabled: Bool {
        if UserDefaults.standard.object(forKey: "tapticAudioFeedbackEnabled") == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: "tapticAudioFeedbackEnabled")
    }

    public func playTick() {
        performDialTick()
    }

    public func playClick() {
        performDialTick()
    }

    public func performDialTick() {
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock()
        guard now - lastTickTime >= Self.minTickInterval else {
            lock.unlock()
            return
        }
        lastTickTime = now
        lock.unlock()

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.lastHapticTime = now
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }

        guard Self.isAudioFeedbackEnabled else { return }
        queue.async { [weak self] in
            guard let self = self, let buf = self.tickBuffer else { return }
            self.ensureEngineRunning()
            self.player.stop()
            self.player.scheduleBuffer(buf, at: nil, options: [], completionHandler: nil)
            self.player.play()
        }
    }

    public func playConfirmClick() {
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock()
        guard now - lastTickTime >= Self.minTickInterval else {
            lock.unlock()
            return
        }
        lastTickTime = now
        lock.unlock()

        guard Self.isAudioFeedbackEnabled else { return }
        queue.async { [weak self] in
            guard let self = self, let buf = self.confirmBuffer else { return }
            self.ensureEngineRunning()
            self.player.stop()
            self.player.scheduleBuffer(buf, at: nil, options: [], completionHandler: nil)
            self.player.play()
        }
    }

    public func performDialClickConfirm() {
        DispatchQueue.main.async {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.018) {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
        }
        playConfirmClick()
    }

    public func performTriplePurgePulse() {
        DispatchQueue.main.async {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        playTick()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            self.playTick()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            self.playConfirmClick()
        }
    }
}

// MARK: - Format Timer MM:SS
public func formatTimerMMSS(seconds: Int) -> String {
    let s = max(0, seconds)
    let m = s / 60
    let rem = s % 60
    return String(format: "%02d:%02d", m, rem)
}

// MARK: - Timer Capsule Icon Button (Square 24x24 pt with 6 pt corner radius)
public struct TimerCapsuleIconButton: View {
    public let icon: String
    public let iconSize: CGFloat
    public let isEnabled: Bool
    public let isActiveState: Bool
    public let theme: AppTheme
    public let tooltip: String
    public let action: () -> Void

    @State private var isHovered: Bool = false

    public init(
        icon: String,
        iconSize: CGFloat = 11,
        isEnabled: Bool = true,
        isActiveState: Bool = false,
        theme: AppTheme,
        tooltip: String = "",
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.iconSize = iconSize
        self.isEnabled = isEnabled
        self.isActiveState = isActiveState
        self.theme = theme
        self.tooltip = tooltip
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .symbolRenderingMode(.monochrome)
                .font(.system(size: iconSize, weight: .bold))
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(buttonBackground)
                )
                .foregroundStyle(buttonForeground)
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(buttonBorder, lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .scaleEffect(isHovered && isEnabled ? 1.05 : 1.0)
                .animation(.easeOut(duration: 0.12), value: isHovered)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled && !isActiveState)
        .opacity(isEnabled ? 1.0 : (isActiveState ? 0.95 : 0.35))
        .onHover { h in
            guard isEnabled else { return }
            isHovered = h
            if h { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
        .help(tooltip)
    }

    private var buttonForeground: Color {
        if isActiveState {
            return theme.accentColor
        }
        return theme.primaryText
    }

    private var buttonBackground: Color {
        if isHovered && isEnabled {
            return theme.accentColor.opacity(isActiveState ? 0.32 : 0.18)
        }
        if isActiveState {
            return theme.accentColor.opacity(0.22)
        }
        return theme.primaryText.opacity(0.06)
    }

    private var buttonBorder: Color {
        if isActiveState {
            return theme.accentColor.opacity(isHovered && isEnabled ? 0.8 : 0.55)
        }
        if isHovered && isEnabled {
            return theme.accentColor.opacity(0.5)
        }
        return theme.borderColor.opacity(0.4)
    }
}

// MARK: - Taptic Circular Timer Popover (Apple Watch / Taptic Engine Aesthetics)
public struct TapticCircularTimerPopover: View {
    public let item: ClipboardItemRow
    @ObservedObject public var monitor: ClipboardMonitor
    public let currentTheme: AppTheme
    public let currentFont: AppFont
    public let language: AppLanguage
    public var onClose: () -> Void

    @State private var hoverPoint: CGPoint? = nil
    @State private var isHovering: Bool = false
    @State private var isDragging: Bool = false
    @State private var lastHapticStep: Int = -1
    @State private var lastCountdown10s: Int = -1

    @State private var clickedStep: Int? = nil
    @State private var isClickImpulseActive: Bool = false
    @State private var impulseWaveScale: CGFloat = 0.98
    @State private var impulseWaveOpacity: Double = 0.0
    @State private var centerBounceScale: CGFloat = 1.0

    private let dialSize: CGFloat = 175.0
    private let centerSize: CGFloat = 86.0
    private let dialRadius: CGFloat = 68.0
    private let centerCircleRadius: CGFloat = 44.0

    public init(
        item: ClipboardItemRow,
        monitor: ClipboardMonitor,
        currentTheme: AppTheme,
        currentFont: AppFont,
        language: AppLanguage = .current,
        onClose: @escaping () -> Void
    ) {
        self.item = item
        self.monitor = monitor
        self.currentTheme = currentTheme
        self.currentFont = currentFont
        self.language = language
        self.onClose = onClose
    }

    private func cursorAngleAndSeconds(at point: CGPoint) -> (deg: Double, seconds: Int) {
        let cx = dialSize / 2
        let cy = dialSize / 2
        let dx = point.x - cx
        let dy = point.y - cy
        var rad = atan2(dx, -dy)
        if rad < 0 { rad += 2 * .pi }
        let deg = rad * 180.0 / .pi
        let step = Int(round(deg / 10.0))
        var sec = step * 10
        if sec == 0 {
            sec = (deg > 180.0) ? 360 : 10
        }
        sec = max(10, min(360, sec))
        return (deg, sec)
    }

    private func isPointOnTickRing(at point: CGPoint) -> Bool {
        let cx = dialSize / 2
        let cy = dialSize / 2
        let dx = point.x - cx
        let dy = point.y - cy
        let dist = hypot(dx, dy)
        // Внутренний центральный круг изолирован (dist < centerCircleRadius),
        // а снаружи границы кружка (dist >= centerCircleRadius && dist <= 108.0) кольцо таймера мгновенно активно
        return dist >= centerCircleRadius && dist <= 108.0
    }

    private func triggerClickImpulse(for seconds: Int) {
        let step = (seconds / 10) % 36
        clickedStep = step
        isClickImpulseActive = true
        impulseWaveScale = 0.98
        impulseWaveOpacity = 0.55
        centerBounceScale = 0.92

        withAnimation(.spring(response: 0.24, dampingFraction: 0.65)) {
            centerBounceScale = 1.0
        }

        withAnimation(.easeOut(duration: 0.35)) {
            impulseWaveScale = 1.12
            impulseWaveOpacity = 0.0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            clickedStep = nil
            isClickImpulseActive = false
        }
    }

    public var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { context in
            let pausedSec = monitor.pausedTimerSeconds[item.id]
            let isPaused = (pausedSec != nil && pausedSec! > 0)
            let remainingSeconds = isPaused ? (pausedSec ?? 0) : max(0, Int(ceil((item.expiresAt ?? .distantPast).timeIntervalSince(context.date))))

            VStack(spacing: 8) {
                // Верхняя шапка поповера
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: isPaused ? "pause.fill" : "timer")
                            .symbolRenderingMode(.monochrome)
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundStyle(isPaused ? currentTheme.accentColor.opacity(0.85) : (remainingSeconds > 0 ? currentTheme.accentColor : currentTheme.primaryText))
                        Text(tr("Таймер автоудаления", "Auto-Purge Timer", lang: language))
                            .font(currentFont.font(size: 11.5, weight: .bold))
                            .foregroundStyle(currentTheme.primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }

                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)

                // Круговой циферблат Apple Watch / Taptic Engine
                ZStack {
                    let cursorInfo = hoverPoint.map { cursorAngleAndSeconds(at: $0) }
                    let cursorDeg = cursorInfo?.deg ?? 0.0
                    let hoverSec = cursorInfo?.seconds ?? 60
                    let cx = dialSize / 2
                    let cy = dialSize / 2

                    // Расходящаяся деликатная импульсная волна при клике
                    Circle()
                        .stroke(currentTheme.accentColor.opacity(0.45), lineWidth: 1.5)
                        .frame(width: dialSize, height: dialSize)
                        .scaleEffect(impulseWaveScale)
                        .opacity(impulseWaveOpacity)

                    // 36 штрихов-делений по кругу по часовой стрелке
                    ForEach(0..<36, id: \.self) { i in
                        let tickDeg = Double(i) * 10.0
                        let isMajor = (i % 6 == 0)
                        let isClicked = (clickedStep == i && isClickImpulseActive)
                        let tickNumber = (i == 0) ? 36 : i

                        // 3D-волна Гаусса (смягченная на 35–40%)
                        let waveFactor: CGFloat = {
                            if isClicked { return 1.0 }
                            guard isHovering || isDragging else { return 0.0 }
                            var diff = abs(tickDeg - cursorDeg)
                            if diff > 180.0 { diff = 360.0 - diff }
                            return CGFloat(exp(-pow(diff / 16.5, 2)))
                        }()

                        let baseLength: CGFloat = isMajor ? 9.5 : 6.0
                        let baseWidth: CGFloat = isMajor ? 2.2 : 1.3

                        // Живой отсчет при активном таймере (ШАГ 4)
                        let (extraActiveLength, extraActiveLift, liveTickOpacity): (CGFloat, CGFloat, Double) = {
                            guard !(isHovering || isDragging) && remainingSeconds > 0 else {
                                return (0.0, 0.0, 1.0)
                            }
                            let totalActiveTicks = min(36, Int(ceil(Double(remainingSeconds) / 10.0)))
                            if tickNumber < totalActiveTicks {
                                return (2.5, 1.8, 1.0)
                            } else if tickNumber == totalActiveTicks {
                                let fraction = Double(remainingSeconds % 10 == 0 ? 10 : (remainingSeconds % 10)) / 10.0
                                return (2.5 * CGFloat(fraction), 1.8 * CGFloat(fraction), 0.25 + 0.75 * fraction)
                            } else {
                                return (0.0, 0.0, 0.3)
                            }
                        }()

                        let totalLength = baseLength + (5.2 * waveFactor) + extraActiveLength
                        let totalWidth = baseWidth + (1.25 * waveFactor) + (isClicked ? 0.35 : 0.0)
                        let radialLift = (3.5 * waveFactor) + extraActiveLift

                        let rad = tickDeg * .pi / 180.0
                        let ux = sin(rad)
                        let uy = -cos(rad)

                        let rInner = (dialRadius - totalLength / 2) + radialLift
                        let rOuter = (dialRadius + totalLength / 2) + radialLift

                        let p1 = CGPoint(x: cx + CGFloat(ux) * rInner, y: cy + CGFloat(uy) * rInner)
                        let p2 = CGPoint(x: cx + CGFloat(ux) * rOuter, y: cy + CGFloat(uy) * rOuter)

                        // Определение цвета деления (ШАГ 1, ШАГ 3, ШАГ 4)
                        let tickColor: Color = {
                            if isClicked {
                                return currentTheme.accentColor.opacity(0.85)
                            }
                            if isHovering || isDragging {
                                let isInHoverRange: Bool = {
                                    if hoverSec == 360 { return true }
                                    if i == 0 { return false }
                                    return (i * 10) <= hoverSec
                                }()
                                if isInHoverRange {
                                    return currentTheme.accentColor.opacity(Double(0.55 + 0.35 * waveFactor))
                                } else {
                                    return currentTheme.primaryText.opacity(Double(0.18 + 0.25 * waveFactor))
                                }
                            } else if remainingSeconds > 0 {
                                let totalActiveTicks = min(36, Int(ceil(Double(remainingSeconds) / 10.0)))
                                if tickNumber <= totalActiveTicks {
                                    let baseColor = isPaused ? currentTheme.accentColor.opacity(0.65) : currentTheme.accentColor
                                    return baseColor.opacity(liveTickOpacity)
                                } else {
                                    return isMajor ? currentTheme.primaryText.opacity(0.35) : currentTheme.primaryText.opacity(0.16)
                                }
                            } else {
                                return isMajor ? currentTheme.primaryText.opacity(0.40) : currentTheme.primaryText.opacity(0.18)
                            }
                        }()

                        Path { p in
                            p.move(to: p1)
                            p.addLine(to: p2)
                        }
                        .stroke(tickColor, style: StrokeStyle(lineWidth: totalWidth, lineCap: .round))
                        .animation(.linear(duration: 0.95), value: remainingSeconds)
                    }

                    // Центральный интерактивный дисплей
                    Circle()
                        .fill(currentTheme.cardBackground.opacity(0.88))
                        .frame(width: centerSize, height: centerSize)
                        .overlay(
                            Circle()
                                .stroke(isPaused ? currentTheme.accentColor.opacity(0.55) : (isHovering || isDragging ? currentTheme.accentColor.opacity(0.5) : currentTheme.borderColor.opacity(0.5)), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)

                    VStack(spacing: 3) {
                        Text(isPaused ? tr("ПАУЗА", "PAUSED", lang: language) : tr("ТАЙМЕР", "TIMER", lang: language))
                            .font(currentFont.font(size: 8.5, weight: .bold))
                            .foregroundStyle(isPaused ? currentTheme.accentColor.opacity(0.85) : currentTheme.secondaryText)
                            .tracking(0.8)

                        if isHovering || isDragging {
                            Text(formatTimerMMSS(seconds: hoverSec))
                                .font(.system(size: 18.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(currentTheme.accentColor)
                                .lineLimit(1)
                        } else if remainingSeconds > 0 {
                            Text(formatTimerMMSS(seconds: remainingSeconds))
                                .font(.system(size: 18.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(currentTheme.primaryText)
                                .lineLimit(1)
                        } else {
                            Image(systemName: "infinity")
                                .font(.system(size: 26, weight: .semibold))
                                .foregroundStyle(currentTheme.primaryText)
                        }
                    }
                    .frame(width: centerSize, height: centerSize)
                    .contentShape(Circle())
                    .scaleEffect(centerBounceScale)
                }
                .frame(width: dialSize, height: dialSize)
                .contentShape(Circle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        guard isPointOnTickRing(at: location) else {
                            if isHovering {
                                isHovering = false
                                hoverPoint = nil
                                lastHapticStep = -1
                                NSCursor.arrow.set()
                            }
                            return
                        }
                        if !isHovering {
                            NSApp.activate(ignoringOtherApps: true)
                        }
                        isHovering = true
                        hoverPoint = location
                        NSCursor.pointingHand.set()
                        let cursor = cursorAngleAndSeconds(at: location)
                        let step = cursor.seconds / 10
                        if step != lastHapticStep {
                            lastHapticStep = step
                            TapticSoundAndHaptics.shared.performDialTick()
                        }
                    case .ended:
                        isHovering = false
                        hoverPoint = nil
                        lastHapticStep = -1
                        NSCursor.arrow.set()
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard isPointOnTickRing(at: value.location) else {
                                if isDragging {
                                    isDragging = false
                                    hoverPoint = nil
                                    lastHapticStep = -1
                                    NSCursor.arrow.set()
                                }
                                return
                            }
                            if !isDragging {
                                NSApp.activate(ignoringOtherApps: true)
                            }
                            isDragging = true
                            hoverPoint = value.location
                            NSCursor.pointingHand.set()
                            let cursor = cursorAngleAndSeconds(at: value.location)
                            let step = cursor.seconds / 10
                            if step != lastHapticStep {
                                lastHapticStep = step
                                TapticSoundAndHaptics.shared.performDialTick()
                            }
                        }
                        .onEnded { value in
                            guard isDragging || isPointOnTickRing(at: value.location) else {
                                isDragging = false
                                hoverPoint = nil
                                lastHapticStep = -1
                                NSCursor.arrow.set()
                                return
                            }
                            isDragging = false
                            let cursor = cursorAngleAndSeconds(at: value.location)
                            monitor.startTimerForItem(id: item.id, seconds: cursor.seconds)
                            monitor.autoPurgeSecretsSeconds = cursor.seconds
                            triggerClickImpulse(for: cursor.seconds)
                            TapticSoundAndHaptics.shared.performDialClickConfirm()
                        }
                )
                .padding(.bottom, 14)
            }
            .frame(width: 260, height: 236)
            .background(currentTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(currentTheme.borderColor, lineWidth: 1)
            )
            .onAppear {
                NSApp.activate(ignoringOtherApps: true)
            }
            .onChange(of: remainingSeconds) { _, newRem in
                if !isPaused && newRem > 0 && newRem % 10 == 0 && newRem != lastCountdown10s {
                    lastCountdown10s = newRem
                    TapticSoundAndHaptics.shared.performDialTick()
                }
            }
        }
    }
}

// MARK: - Interactive Info Tooltip Badge (!) with 0.15s Hover Delay
public struct InfoTooltipBadge: View {
    public let title: String
    public let message: String
    public let theme: AppTheme

    @State private var isShowingPopover: Bool = false
    @State private var isHovering: Bool = false
    @State private var hoverTask: Task<Void, Never>? = nil
    @AppStorage("selectedFontId") private var selectedFontId: String = AppFont.default.rawValue

    private var currentFont: AppFont {
        AppFont(fromRaw: selectedFontId)
    }

    public init(title: String, message: String, theme: AppTheme) {
        self.title = title
        self.message = message
        self.theme = theme
    }

    public var body: some View {
        Button {
            hoverTask?.cancel()
            isShowingPopover.toggle()
        } label: {
            Image(systemName: "exclamationmark.circle.fill")
                .symbolRenderingMode(.monochrome)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle((isHovering || isShowingPopover) ? theme.primaryText : theme.secondaryText)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .onHover { hovering in
            isHovering = hovering
            hoverTask?.cancel()
            if hovering {
                hoverTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 150_000_000) // 0.15s задержка против случайного задевания мышью
                    guard !Task.isCancelled, isHovering else { return }
                    isShowingPopover = true
                }
            } else {
                isShowingPopover = false
            }
        }
        .popover(isPresented: $isShowingPopover, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .symbolRenderingMode(.monochrome)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(theme.primaryText)
                    Text(title)
                        .font(currentFont.font(size: 12, weight: .bold))
                        .foregroundStyle(theme.primaryText)
                }
                Text(message)
                    .font(currentFont.font(size: 11, weight: .regular))
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }
            .padding(12)
            .frame(width: 280, alignment: .leading)
            .background(theme.isLight ? Color(red: 0.97, green: 0.98, blue: 1.0) : theme.backgroundColor)
            .environment(\.colorScheme, theme.isLight ? .light : .dark)
        }
    }
}

public struct LiquidGlassCardModifier: ViewModifier {
    public let theme: AppTheme
    public let windowOpacity: Double
    public let cornerRadius: CGFloat
    public let isSelected: Bool
    /// Наведение курсора: ТОЛЬКО лёгкое осветление фона (+~0.04), без акцентной рамки — рамка есть лишь у выбранной карточки
    public var isHovered: Bool = false

    private var hoverTint: Color {
        (isHovered && !isSelected) ? theme.primaryText.opacity(0.04) : Color.clear
    }

    public func body(content: Content) -> some View {
        if !theme.usesLiquidGlass {
            content
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(isSelected ? theme.selectedCardBackground : theme.cardColor)
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(hoverTint)
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(isSelected ? theme.accentColor : theme.borderColor, lineWidth: isSelected ? 1.5 : 1.0)
                        .allowsHitTesting(false)
                )
        } else {
            let baseFill: Color = isSelected
                ? theme.accentColor.opacity(0.12 + windowOpacity * 0.20)
                : theme.cardFill(opacity: windowOpacity)
            let specularTopOpacity: Double = theme.isLight ? (0.24 + windowOpacity * 0.34) : (0.10 + windowOpacity * 0.14)
            let rimTopOpacity: Double = isSelected ? 0.78 : (theme.isLight ? 0.62 : 0.45)
            let rimAccentOpacity: Double = isSelected ? 0.65 : 0.35
            let rimBottomOpacity: Double = isSelected ? 0.35 : (theme.isLight ? 0.24 : 0.08)

            content
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(baseFill)

                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(hoverTint)

                        // Спекулярный блик (Specular Reflection)
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(specularTopOpacity),
                                        Color.clear,
                                        theme.accentColor.opacity(isSelected ? 0.18 : 0.12)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .allowsHitTesting(false)
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    // Кристаллическая грань преломления (Refraction Rim Border — без тяжёлого Gaussian shadow на карточках списка)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(rimTopOpacity),
                                    theme.accentColor.opacity(rimAccentOpacity),
                                    Color.white.opacity(rimBottomOpacity)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: isSelected ? 1.5 : 1.2
                        )
                        .allowsHitTesting(false)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: max(1, cornerRadius - 1), style: .continuous)
                        .strokeBorder(
                            Color.white.opacity(theme.isLight ? 0.35 : 0.08),
                            lineWidth: 0.6
                        )
                        .allowsHitTesting(false)
                )
        }
    }
}

public struct LiquidGlassWindowModifier: ViewModifier {
    public let theme: AppTheme
    public let windowOpacity: Double

    public func body(content: Content) -> some View {
        if !theme.usesLiquidGlass {
            content
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(theme.backgroundColor)
                )
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(
                            theme.isLight
                                ? (SmartClassifier.parseNSColor(theme.borderHex).map { Color(nsColor: $0) } ?? Color.black.opacity(0.06))
                                : theme.borderColor,
                            lineWidth: 1.0
                        )
                        .allowsHitTesting(false)
                )
        } else {
            content
                .background(
                    ZStack {
                        VisualEffectBlur(
                            material: theme.isLight ? .underWindowBackground : .hudWindow,
                            blendingMode: .behindWindow
                        )
                        .opacity(windowOpacity)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(theme.panelFill(opacity: windowOpacity))

                        // Спекулярный блик по всей стеклянной линзе окна
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity((theme.isLight ? 0.55 : 0.22) * (0.35 + windowOpacity * 0.65)),
                                        Color.clear,
                                        theme.accentColor.opacity(0.12 * (0.35 + windowOpacity * 0.65))
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .allowsHitTesting(false)
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(theme.isLight ? 0.72 : 0.48),
                                    theme.accentColor.opacity(0.38),
                                    Color.white.opacity(theme.isLight ? 0.28 : 0.10)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.0
                        )
                        .allowsHitTesting(false)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 19, style: .continuous)
                        .strokeBorder(
                            Color.white.opacity(theme.isLight ? 0.42 : 0.10),
                            lineWidth: 0.6
                        )
                        .allowsHitTesting(false)
                )
        }
    }
}

extension View {
    public func liquidGlassCard(
        theme: AppTheme,
        windowOpacity: Double,
        cornerRadius: CGFloat = 14,
        isSelected: Bool = false,
        isHovered: Bool = false
    ) -> some View {
        modifier(
            LiquidGlassCardModifier(
                theme: theme,
                windowOpacity: windowOpacity,
                cornerRadius: cornerRadius,
                isSelected: isSelected,
                isHovered: isHovered
            )
        )
    }

    public func liquidGlassWindow(
        theme: AppTheme,
        windowOpacity: Double
    ) -> some View {
        modifier(
            LiquidGlassWindowModifier(
                theme: theme,
                windowOpacity: windowOpacity
            )
        )
    }
}

// MARK: - Unified Design System: PVButtonStyle
public enum PVButtonVariant: Equatable, Sendable {
    case primary
    case secondary
    case destructive
    case success
    case toggle(isActive: Bool)
}

public enum PVButtonSize: Equatable, Sendable {
    case small
    case regular

    public var horizontalPadding: CGFloat {
        switch self {
        case .small: return 10
        case .regular: return 14
        }
    }

    public var verticalPadding: CGFloat {
        switch self {
        case .small: return 5
        case .regular: return 7
        }
    }

    public var fontSize: CGFloat {
        switch self {
        case .small: return 12
        case .regular: return 13
        }
    }
}

public struct PVButtonStyle: ButtonStyle {
    public let variant: PVButtonVariant
    public let size: PVButtonSize
    public let theme: AppTheme
    public let fixedWidth: CGFloat?
    public let fixedHeight: CGFloat?
    public let customBorderColor: Color?

    public init(
        variant: PVButtonVariant = .secondary,
        size: PVButtonSize = .small,
        theme: AppTheme,
        fixedWidth: CGFloat? = nil,
        fixedHeight: CGFloat? = nil,
        customBorderColor: Color? = nil
    ) {
        self.variant = variant
        self.size = size
        self.theme = theme
        self.fixedWidth = fixedWidth
        self.fixedHeight = fixedHeight
        self.customBorderColor = customBorderColor
    }

    public func makeBody(configuration: Configuration) -> some View {
        PVButtonBody(
            configuration: configuration,
            variant: variant,
            size: size,
            theme: theme,
            fixedWidth: fixedWidth,
            fixedHeight: fixedHeight,
            customBorderColor: customBorderColor
        )
    }
}

private struct PVButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let variant: PVButtonVariant
    let size: PVButtonSize
    let theme: AppTheme
    let fixedWidth: CGFloat?
    let fixedHeight: CGFloat?
    let customBorderColor: Color?

    @State private var isHovered: Bool = false
    @AppStorage("selectedFontId") private var selectedFontId: String = AppFont.default.rawValue
    @ObservedObject private var fontManager = FontManager.shared

    private var currentFont: AppFont {
        AppFont(fromRaw: selectedFontId)
    }

    var body: some View {
        let _ = fontManager.resolvedPostScriptNames.count
        configuration.label
            .font(currentFont.font(size: size.fontSize, weight: isSemibold ? .semibold : .medium))
            .foregroundStyle(foregroundColor)
            .symbolRenderingMode(.monochrome)
            .padding(.horizontal, fixedWidth != nil ? 0 : size.horizontalPadding)
            .padding(.vertical, fixedHeight != nil ? 0 : size.verticalPadding)
            .frame(width: fixedWidth, height: fixedHeight)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: borderWidth)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .shadow(color: (variant == .success ? Color(red: 0.10, green: 0.78, blue: 0.45).opacity(0.45) : Color.clear), radius: (variant == .success ? 6 : 0))
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .onHover { hovering in
                isHovered = hovering
                if hovering {
                    NSCursor.pointingHand.set()
                } else {
                    NSCursor.arrow.set()
                }
            }
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed {
                    TapticSoundAndHaptics.shared.performDialTick()
                }
            }
    }

    private var isSemibold: Bool {
        switch variant {
        case .primary, .destructive, .success: return true
        case .secondary: return false
        case .toggle(let isActive): return isActive
        }
    }

    private var foregroundColor: Color {
        switch variant {
        case .primary:
            return theme.isLight ? Color.white : Color.black
        case .destructive, .success:
            return Color.white
        case .secondary:
            return theme.primaryText
        case .toggle(let isActive):
            return isActive ? theme.primaryText : theme.secondaryText
        }
    }

    private var backgroundColor: Color {
        switch variant {
        case .primary:
            return isHovered ? theme.accentColor.opacity(0.88) : theme.accentColor
        case .destructive:
            return isHovered ? Color.red.opacity(0.88) : Color.red.opacity(0.72)
        case .success:
            return isHovered ? Color(red: 0.08, green: 0.70, blue: 0.40) : Color(red: 0.10, green: 0.78, blue: 0.45)
        case .secondary:
            return theme.primaryText.opacity(isHovered ? 0.12 : 0.06)
        case .toggle(let isActive):
            if isActive {
                return theme.primaryText.opacity(isHovered ? 0.22 : 0.16)
            } else {
                return theme.primaryText.opacity(isHovered ? 0.12 : 0.06)
            }
        }
    }

    private var borderColor: Color {
        if let customBorderColor {
            return customBorderColor
        }
        switch variant {
        case .primary:
            return theme.primaryText.opacity(0.2)
        case .destructive:
            return Color.red.opacity(0.4)
        case .success:
            return Color(red: 0.10, green: 0.78, blue: 0.45)
        case .secondary:
            return theme.primaryText.opacity(isHovered ? 0.35 : 0.15)
        case .toggle(let isActive):
            if isActive {
                return theme.primaryText.opacity(0.55)
            } else {
                return theme.primaryText.opacity(isHovered ? 0.35 : 0.15)
            }
        }
    }

    private var borderWidth: CGFloat {
        switch variant {
        case .primary, .secondary, .destructive, .success:
            return 1.0
        case .toggle(let isActive):
            return isActive ? 1.5 : 1.0
        }
    }
}

extension View {
    public func pvButton(
        variant: PVButtonVariant = .secondary,
        size: PVButtonSize = .small,
        theme: AppTheme,
        fixedWidth: CGFloat? = nil,
        fixedHeight: CGFloat? = nil,
        customBorderColor: Color? = nil
    ) -> some View {
        self.buttonStyle(PVButtonStyle(
            variant: variant,
            size: size,
            theme: theme,
            fixedWidth: fixedWidth,
            fixedHeight: fixedHeight,
            customBorderColor: customBorderColor
        ))
    }
}

// MARK: - Quick Snippet Model
public struct QuickSnippetItem: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var content: String
    public var category: String
    public var shortcutHint: String?
    public var isPinned: Bool = false

    public init(id: String = UUID().uuidString, title: String, content: String, category: String, shortcutHint: String? = nil, isPinned: Bool = false) {
        self.id = id
        self.title = title
        self.content = content
        self.category = category
        self.shortcutHint = shortcutHint
        self.isPinned = isPinned
    }

    enum CodingKeys: String, CodingKey {
        case id, title, content, category, shortcutHint, isPinned
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.title = try container.decode(String.self, forKey: .title)
        self.content = try container.decode(String.self, forKey: .content)
        self.category = try container.decode(String.self, forKey: .category)
        self.shortcutHint = try container.decodeIfPresent(String.self, forKey: .shortcutHint)
        self.isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(content, forKey: .content)
        try container.encode(category, forKey: .category)
        try container.encodeIfPresent(shortcutHint, forKey: .shortcutHint)
        try container.encode(isPinned, forKey: .isPinned)
    }
}

// MARK: - Single-Hover Coordinator (максимум ОДНА наведённая карточка в любой момент времени)
/// Лёгкий координатор наведения без @Published: каждая карточка хранит локальный `isHovered`,
/// но при наведении на новую карточку предыдущая гасится через PassthroughSubject.
/// Родительский MainPanelView при этом НЕ перерисовывается (нет пересчёта filteredItems на hover).
@MainActor
public final class CardHoverCoordinator {
    public static let shared = CardHoverCoordinator()
    public let subject = PassthroughSubject<String?, Never>()
    public private(set) var hoveredId: String?

    private init() {}

    public func setHovered(_ id: String?) {
        guard hoveredId != id else { return }
        hoveredId = id
        subject.send(id)
    }

    public func clear(ifCurrent id: String) {
        if hoveredId == id {
            setHovered(nil)
        }
    }
}

// MARK: - Мгновенный детектор двойного клика (без ожидания disambiguation у .onTapGesture(count: 2))
@MainActor
public enum CardClickDetector {
    private static var lastTapItemId: String?
    private static var lastTapTime: CFTimeInterval = 0

    /// Возвращает true, если текущий клик — второй клик двойного щелчка по той же карточке
    public static func registerTap(itemId: String, now: CFTimeInterval = CACurrentMediaTime(), eventClickCount: Int? = nil) -> Bool {
        let interval = NSEvent.doubleClickInterval
        let isDouble: Bool
        if let count = eventClickCount, count >= 2, lastTapItemId == itemId {
            isDouble = true
        } else {
            isDouble = (lastTapItemId == itemId) && (now - lastTapTime) <= interval
        }
        if isDouble {
            // Сбрасываем, чтобы третий клик не считался повторным двойным
            lastTapItemId = nil
            lastTapTime = 0
        } else {
            lastTapItemId = itemId
            lastTapTime = now
        }
        return isDouble
    }

    public static func reset() {
        lastTapItemId = nil
        lastTapTime = 0
    }
}

// MARK: - Isolated Clipboard Row Card View (Zero Parent Redraws on Hover)
@MainActor
public struct ClipboardRowCardView: View {
    public let item: ClipboardItemRow
    public let index: Int
    public let isSelected: Bool
    public let previewImage: NSImage?
    public let targetAppName: String
    public let currentTheme: AppTheme
    public let currentFont: AppFont
    public let language: AppLanguage
    public let windowOpacity: Double
    public let monitor: ClipboardMonitor
    public var isPastedToast: Bool = false
    public var searchQuery: String = ""
    public let onSelect: () -> Void
    public let onPaste: () -> Void
    public let onDelete: () -> Void
    public let onTogglePin: () -> Void
    public var onToggleSecret: (() -> Void)? = nil
    public let onStartTimer: () -> Void
    public let onCancelTimer: () -> Void

    @State private var isHovered: Bool = false
    @State private var isKeyHovered: Bool = false
    @State private var isPinHovered: Bool = false
    @State private var isPasteHovered: Bool = false
    @State private var isDeleteHovered: Bool = false
    @State private var isRowTimerPopoverPresented: Bool = false

    private var isSecretItem: Bool {
        item.isSensitive || item.effectiveContentType == .secret
    }

    public static func isPasswordCandidate(_ item: ClipboardItemRow) -> Bool {
        // 1. Если запись уже является паролем
        if item.isSensitive || item.contentType == .secret || item.effectiveContentType == .secret {
            return true
        }

        // 2. Только для текстовых и кодовых записей
        let kind = item.effectiveContentType
        guard kind == .text || kind == .code else {
            return false
        }

        // 3. O(1) отсечка по байтам БЕЗ аллокаций: длинные логи/код (десятки КБ) отбрасываются мгновенно,
        //    до любых trimmingCharacters/lowercased, которые копируют строку на каждом рендере
        let byteCount = item.textPreview.utf8.count
        guard byteCount >= 4 && byteCount <= 80 else {
            return false
        }

        // 4. Анализ текстового содержимого (только для коротких строк ≤ 80 байт)
        let trimmed = item.textPreview.trimmingCharacters(in: .whitespacesAndNewlines)

        // Фразы и предложения с пробелами/табуляцией/переносами строк никогда не являются кандидатами
        if trimmed.contains(where: { $0.isWhitespace || $0.isNewline }) {
            return false
        }

        // Длина строки строго 4...64 символа
        guard (4...64).contains(trimmed.count) else {
            return false
        }

        // Отсекаем ссылки, пути и хештеги
        let lower = trimmed.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("file://") ||
           lower.hasPrefix("/") || lower.hasPrefix("~/") || lower.hasPrefix("#") {
            return false
        }

        // Считать строку кандидатом, если в ней есть хотя бы один символ латиницы (A-Z, a-z),
        // цифра (0-9) или спецсимвол
        let hasLatinOrDigitOrSpecial = trimmed.contains { char in
            (char >= "a" && char <= "z") ||
            (char >= "A" && char <= "Z") ||
            (char >= "0" && char <= "9") ||
            char.isPunctuation ||
            char.isSymbol
        }

        return hasLatinOrDigitOrSpecial
    }

    private var iconName: String {
        switch item.effectiveContentType {
        case .file: return "doc.fill"
        case .url: return "link"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .image: return "photo"
        case .secret: return "key.fill"
        case .color: return "paintpalette.fill"
        case .text: return "text.alignleft"
        }
    }

    private var typeBadgeLabel: String {
        switch item.effectiveContentType {
        case .file: return tr("Файл", "File", lang: language)
        case .text: return tr("Текст", "Text", lang: language)
        case .url: return tr("Ссылка", "Link", lang: language)
        case .code: return tr("Код", "Code", lang: language)
        case .image: return tr("Скриншот", "Image", lang: language)
        case .secret: return tr("Пароль", "Secret", lang: language)
        case .color: return tr("Цвет", "Color", lang: language)
        }
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(currentTheme.primaryText.opacity(0.08))
                    .frame(width: 28, height: 28)

                if item.effectiveContentType == .color,
                   let nsColor = SmartClassifier.parseNSColor(item.textPreview) {
                    Circle()
                        .fill(Color(nsColor: nsColor))
                        .frame(width: 18, height: 18)
                        .overlay(Circle().stroke(currentTheme.primaryText.opacity(0.45), lineWidth: 1.5))
                } else if (item.effectiveContentType == .image || item.effectiveContentType == .file),
                          let previewImg = previewImage {
                    Image(nsImage: previewImg)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                } else {
                    Image(systemName: iconName)
                        .symbolRenderingMode(.monochrome)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(currentTheme.primaryText)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                // Строка 1: Название источника -> Spacer() -> Ключик (для паролей/кандидатов) -> Закрепить -> Вставить ⌥N -> Удалить ✕
                HStack(spacing: 5) {
                    Text(displaySourceAppName(item.sourceAppName))
                        .font(currentFont.font(size: 10.5, weight: .bold))
                        .foregroundStyle(currentTheme.secondaryText)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    if Self.isPasswordCandidate(item) {
                        let isSec = item.isSensitive || item.effectiveContentType == .secret
                        Button {
                            TapticSoundAndHaptics.shared.performDialTick()
                            if let onToggleSecret {
                                onToggleSecret()
                            } else {
                                monitor.toggleSecretStatus(for: item.id)
                            }
                        } label: {
                            Image(systemName: isSec ? "key.fill" : "key")
                                .symbolRenderingMode(.monochrome)
                                .font(.system(size: 10, weight: isSec ? .bold : .medium))
                                .foregroundStyle(isKeyHovered ? currentTheme.accentColor : (isSec ? currentTheme.accentColor : currentTheme.primaryText))
                                .padding(3)
                                .background(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(isKeyHovered ? currentTheme.accentColor.opacity(0.22) : (isSec ? currentTheme.accentColor.opacity(0.18) : Color.clear))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .strokeBorder(isKeyHovered ? currentTheme.accentColor.opacity(0.5) : (isSec ? currentTheme.accentColor.opacity(0.35) : Color.clear), lineWidth: 1)
                                )
                                .scaleEffect(isKeyHovered ? 1.04 : 1.0)
                                .animation(.easeOut(duration: 0.12), value: isKeyHovered)
                        }
                        .buttonStyle(.plain)
                        .help(isSec ? tr("Сделать обычным текстом", "Make Plain Text", lang: language) : tr("Скрыть как пароль", "Mark as Password", lang: language))
                        .onHover { hovering in
                            isKeyHovered = hovering
                            if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
                        }
                    }

                    Button {
                        TapticSoundAndHaptics.shared.performDialTick()
                        onTogglePin()
                    } label: {
                        Image(systemName: item.isPinned ? "pin.fill" : "pin")
                            .symbolRenderingMode(.monochrome)
                            .font(.system(size: 10, weight: item.isPinned ? .bold : .medium))
                            .foregroundStyle(isPinHovered ? currentTheme.accentColor : currentTheme.primaryText)
                            .padding(3)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(isPinHovered ? currentTheme.accentColor.opacity(0.22) : (item.isPinned ? currentTheme.primaryText.opacity(0.18) : Color.clear))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .strokeBorder(isPinHovered ? currentTheme.accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
                            )
                            .scaleEffect(isPinHovered ? 1.04 : 1.0)
                            .animation(.easeOut(duration: 0.12), value: isPinHovered)
                    }
                    .buttonStyle(.plain)
                    .help(item.isPinned ? tr("Открепить (⌥P)", "Unpin (⌥P)", lang: language) : tr("Закрепить (⌥P)", "Pin (⌥P)", lang: language))
                    .onHover { hovering in
                        isPinHovered = hovering
                        if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
                    }

                    Button {
                        TapticSoundAndHaptics.shared.performDialTick()
                        onPaste()
                    } label: {
                        HStack(spacing: 3) {
                            if isPastedToast {
                                Image(systemName: "checkmark")
                                    .symbolRenderingMode(.monochrome)
                                    .font(.system(size: 8, weight: .bold))
                                Text(tr("Вставлено", "Pasted", lang: language))
                                    .font(currentFont.font(size: 9, weight: .semibold))
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                            } else {
                                Image(systemName: "arrow.turn.down.left")
                                    .symbolRenderingMode(.monochrome)
                                    .font(.system(size: 8, weight: .bold))
                                Text(index < 9 ? tr("Вставить \(ShortcutManager.shared.config.quickPastePrefix)\(index + 1)", "Paste \(ShortcutManager.shared.config.quickPastePrefix)\(index + 1)", lang: language) : tr("Вставить", "Paste", lang: language))
                                    .font(currentFont.font(size: 9, weight: .semibold))
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(isPastedToast ? Color(red: 0.10, green: 0.78, blue: 0.45) : (isPasteHovered ? currentTheme.accentColor : (isSelected ? currentTheme.badgeFill : currentTheme.primaryText.opacity(0.08))))
                        )
                        .foregroundStyle(isPastedToast ? Color.white : (isPasteHovered ? Color.white : (isSelected ? currentTheme.badgeText : currentTheme.primaryText.opacity(0.85))))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .strokeBorder(isPastedToast ? Color(red: 0.10, green: 0.78, blue: 0.45) : (isPasteHovered ? currentTheme.accentColor : Color.clear), lineWidth: 1)
                        )
                        .shadow(color: Color(red: 0.10, green: 0.78, blue: 0.45).opacity(isPastedToast ? 0.55 : 0), radius: isPastedToast ? 6 : 0)
                        .scaleEffect(isPasteHovered ? 1.03 : 1.0)
                        .animation(.easeInOut(duration: 0.18), value: isPastedToast)
                    }
                    .buttonStyle(.plain)
                    .help(tr("Мгновенно вставить в \(targetAppName)", "Instantly paste into \(targetAppName)", lang: language))
                    .onHover { hovering in
                        isPasteHovered = hovering
                        if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
                    }

                    Button {
                        TapticSoundAndHaptics.shared.performDialTick()
                        onDelete()
                    } label: {
                        Image(systemName: "xmark")
                            .symbolRenderingMode(.monochrome)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(isDeleteHovered ? Color.red : currentTheme.secondaryText)
                            .frame(width: 22, height: 22)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(isDeleteHovered ? Color.red.opacity(0.16) : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(isDeleteHovered ? Color.red.opacity(0.45) : Color.clear, lineWidth: 1)
                            )
                            .scaleEffect(isDeleteHovered ? 1.05 : 1.0)
                            .animation(.easeOut(duration: 0.12), value: isDeleteHovered)
                    }
                    .buttonStyle(.plain)
                    .help(tr("Удалить запись", "Delete item", lang: language))
                    .onHover { hovering in
                        isDeleteHovered = hovering
                        if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
                    }
                }

                // Строка 2: Бейдж типа (+ теги) + компактный индикатор таймера
                HStack(spacing: 4) {
                    Text(typeBadgeLabel)
                        .font(currentFont.font(size: 9, weight: .semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(currentTheme.primaryText.opacity(0.08))
                        .foregroundStyle(currentTheme.secondaryText)
                        .clipShape(Capsule())

                    ForEach(item.detectedTags, id: \.self) { tag in
                        Text(ClipboardFilterSelection.localizedTag(tag, in: language))
                            .font(currentFont.font(size: 9, weight: .semibold))
                            .lineLimit(1)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(currentTheme.badgeFill)
                            .foregroundStyle(currentTheme.badgeText)
                            .clipShape(Capsule())
                    }

                    if isSecretItem {
                        TimelineView(.periodic(from: .now, by: 1.0)) { context in
                            let paused = monitor.pausedTimerSeconds[item.id]
                            let isPaused = (paused != nil && paused! > 0)
                            let remaining = isPaused ? (paused ?? 0) : max(0, Int(ceil((item.expiresAt ?? .distantPast).timeIntervalSince(context.date))))
                            let isActive = !isPaused && item.expiresAt != nil && remaining > 0

                            Button {
                                isRowTimerPopoverPresented.toggle()
                            } label: {
                                if isPaused {
                                    HStack(spacing: 3) {
                                        Image(systemName: "pause.fill")
                                            .symbolRenderingMode(.monochrome)
                                            .font(.system(size: 8, weight: .bold))
                                        Text(formatTimerMMSS(seconds: remaining))
                                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    }
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(currentTheme.accentColor.opacity(0.14))
                                    .foregroundStyle(currentTheme.accentColor.opacity(0.85))
                                    .clipShape(Capsule())
                                    .overlay(Capsule().strokeBorder(currentTheme.accentColor.opacity(0.35), lineWidth: 0.8))
                                } else if isActive {
                                    HStack(spacing: 3) {
                                        Image(systemName: "timer")
                                            .symbolRenderingMode(.monochrome)
                                            .font(.system(size: 8.5, weight: .bold))
                                        Text(formatTimerMMSS(seconds: remaining))
                                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    }
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(currentTheme.accentColor.opacity(0.18))
                                    .foregroundStyle(currentTheme.accentColor)
                                    .clipShape(Capsule())
                                    .overlay(Capsule().strokeBorder(currentTheme.accentColor.opacity(0.4), lineWidth: 0.8))
                                } else {
                                    HStack(spacing: 3) {
                                        Image(systemName: "timer")
                                            .symbolRenderingMode(.monochrome)
                                            .font(.system(size: 8.5, weight: .bold))
                                        Image(systemName: "infinity")
                                            .symbolRenderingMode(.monochrome)
                                            .font(.system(size: 8.5, weight: .bold))
                                    }
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(currentTheme.primaryText.opacity(0.08))
                                    .foregroundStyle(currentTheme.secondaryText)
                                    .clipShape(Capsule())
                                }
                            }
                            .buttonStyle(.plain)
                            .help(isPaused
                                  ? tr("Таймер на паузе (клик для настройки)", "Timer paused (click to configure)", lang: language)
                                  : (isActive
                                     ? tr("Нажмите для настройки кругового таймера автоудаления", "Click to configure auto-purge timer", lang: language)
                                     : tr("Автоудаление выключено (клик для настройки таймера)", "Auto-purge disabled (click to configure timer)", lang: language)))
                            .popover(isPresented: $isRowTimerPopoverPresented, arrowEdge: .trailing) {
                                TapticCircularTimerPopover(
                                    item: item,
                                    monitor: monitor,
                                    currentTheme: currentTheme,
                                    currentFont: currentFont,
                                    language: language,
                                    onClose: { isRowTimerPopoverPresented = false }
                                )
                            }
                        }
                    }
                }

                // Строка 3: Текстовое превью контента (с подсветкой поискового запроса для не-секретных записей)
                if !searchQuery.isEmpty && !isSecretItem {
                    Text(SearchHighlightHelper.highlight(
                        text: item.displayPreviewText,
                        query: searchQuery,
                        baseFont: currentFont.font(size: 12, weight: .regular),
                        baseColor: currentTheme.primaryText,
                        accentColor: currentTheme.accentColor,
                        isLight: currentTheme.isLight,
                        bold: true
                    ))
                    .lineLimit(2)
                    .truncationMode(.tail)
                } else {
                    Text(item.displayPreviewText)
                        .font(currentFont.font(size: 12, weight: .regular))
                        .foregroundStyle(currentTheme.primaryText)
                        .lineLimit(2)
                        .truncationMode(.tail)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassCard(
            theme: currentTheme,
            windowOpacity: windowOpacity,
            cornerRadius: 10,
            isSelected: isSelected,
            isHovered: isHovered
        )
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(item.isPinned ? currentTheme.accentColor.opacity(0.10) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    isPastedToast
                        ? Color(red: 0.10, green: 0.78, blue: 0.45)
                        : (item.isPinned ? currentTheme.accentColor.opacity(0.45) : Color.clear),
                    lineWidth: isPastedToast ? 2.0 : (item.isPinned ? 1.5 : 0)
                )
                .shadow(
                    color: Color(red: 0.10, green: 0.78, blue: 0.45).opacity(isPastedToast ? 0.45 : 0),
                    radius: isPastedToast ? 6 : 0
                )
                .animation(.easeInOut(duration: 0.18), value: isPastedToast)
        )
        .clipped()
        .contentShape(Rectangle())
        .onHover { hovering in
            let coordinator = CardHoverCoordinator.shared
            if hovering {
                coordinator.setHovered(item.id)
                if !isHovered { isHovered = true }
            } else {
                coordinator.clear(ifCurrent: item.id)
                if isHovered { isHovered = false }
            }
        }
        .onReceive(CardHoverCoordinator.shared.subject) { hoveredId in
            // Гасим залипшую подсветку, как только наведение ушло на другую карточку
            let shouldHover = (hoveredId == item.id)
            if isHovered != shouldHover {
                isHovered = shouldHover
            }
        }
        // Один распознаватель тапа: выбор срабатывает МГНОВЕННО (без ожидания интервала двойного клика),
        // а второй клик двойного щелчка распознаётся по времени/clickCount и выполняет вставку
        .onTapGesture {
            let clickCount = NSApp.currentEvent.map { ($0.type == .leftMouseUp || $0.type == .leftMouseDown) ? $0.clickCount : 1 }
            let isDouble = CardClickDetector.registerTap(itemId: item.id, eventClickCount: clickCount)
            TapticSoundAndHaptics.shared.performDialTick()
            if isDouble {
                onPaste()
            } else {
                onSelect()
            }
        }
    }

    private func displaySourceAppName(_ name: String?) -> String {
        guard let name = name, !name.isEmpty else {
            return tr("Буфер", "Clipboard", lang: language)
        }
        if name == "Paste Vault (PassGen)" {
            return "PasteVault (PassGen)"
        }
        if name == "Paste Vault" {
            return "PasteVault"
        }
        return name
    }
}

// MARK: - Quick Snippet Card Row View
@MainActor
public struct QuickSnippetCardRowView: View {
    public let snippet: QuickSnippetItem
    public let targetAppName: String
    public let currentTheme: AppTheme
    public let currentFont: AppFont
    public let language: AppLanguage
    public let windowOpacity: Double
    public let searchQuery: String
    public let isTitleMatched: Bool
    public let isContentMatched: Bool
    public let isPastedToast: Bool
    public let isCopiedToast: Bool
    public let onTogglePin: () -> Void
    public let onEdit: () -> Void
    public let onPaste: () -> Void
    public let onCopy: () -> Void
    public let onDelete: () -> Void

    @State private var isPinHovered: Bool = false
    @State private var isEditHovered: Bool = false
    @State private var isPasteHovered: Bool = false
    @State private var isCopyHovered: Bool = false
    @State private var isDeleteHovered: Bool = false

    public var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Левая колонка: название, бейдж категории, плашка «Совпадение в тексте» и превью содержимого
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if snippet.isPinned {
                        Image(systemName: "pin.fill")
                            .symbolRenderingMode(.monochrome)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(currentTheme.accentColor)
                            .help(tr("Закреплённый фрагмент (всегда сверху)", "Pinned snippet (always on top)", lang: language))
                    }

                    let titleText = MainPanelView.localizedSnippetTitle(snippet.title, lang: language)
                    if !searchQuery.isEmpty {
                        Text(SearchHighlightHelper.highlight(
                            text: titleText,
                            query: searchQuery,
                            baseFont: currentFont.font(size: 13, weight: .bold),
                            baseColor: currentTheme.primaryText,
                            accentColor: currentTheme.accentColor,
                            isLight: currentTheme.isLight,
                            bold: true
                        ))
                    } else {
                        Text(titleText)
                            .font(currentFont.font(size: 13, weight: .bold))
                            .foregroundStyle(currentTheme.primaryText)
                    }

                    Text(MainPanelView.localizedSnippetCategory(snippet.category, lang: language))
                        .font(currentFont.font(size: 9, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(currentTheme.badgeFill)
                        .foregroundStyle(currentTheme.badgeText)
                        .clipShape(Capsule())

                    // Бейдж «Совпадение в тексте», если запрос найден только в content, а не в title
                    if !searchQuery.isEmpty && !isTitleMatched && isContentMatched {
                        HStack(spacing: 3) {
                            Image(systemName: "text.magnifyingglass")
                                .font(.system(size: 8.5, weight: .semibold))
                            Text(tr("Совпадение в тексте", "Match in text", lang: language))
                                .font(currentFont.font(size: 9, weight: .semibold))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(currentTheme.accentColor.opacity(0.18))
                        .foregroundStyle(currentTheme.accentColor)
                        .clipShape(Capsule())
                    }

                    Spacer()
                }

                let contentText = MainPanelView.localizedSnippetContent(snippet.content, lang: language)
                if !searchQuery.isEmpty {
                    Text(SearchHighlightHelper.highlight(
                        text: contentText,
                        query: searchQuery,
                        baseFont: currentFont.font(size: 11, weight: .regular),
                        baseColor: currentTheme.primaryText.opacity(0.9),
                        accentColor: currentTheme.accentColor,
                        isLight: currentTheme.isLight,
                        bold: true
                    ))
                    .lineLimit(2)
                } else {
                    Text(contentText)
                        .font(currentFont.font(size: 11, weight: .regular))
                        .foregroundStyle(currentTheme.primaryText.opacity(0.9))
                        .lineLimit(2)
                }
            }

            // Правая часть: органичный ряд из 5 элементов единой высоты (30 pt) со скруглением 8 pt
            HStack(spacing: 6) {
                // 1) Кнопка «Закрепить» (30x30 pt)
                Button {
                    TapticSoundAndHaptics.shared.playClick()
                    onTogglePin()
                } label: {
                    Image(systemName: snippet.isPinned ? "pin.fill" : "pin")
                        .symbolRenderingMode(.monochrome)
                        .font(.system(size: 11, weight: snippet.isPinned ? .bold : .medium))
                        .foregroundStyle(snippet.isPinned ? Color.white : (isPinHovered ? currentTheme.accentColor : currentTheme.primaryText))
                        .frame(width: 30, height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(snippet.isPinned
                                      ? (isPinHovered ? currentTheme.accentColor.opacity(0.85) : currentTheme.accentColor)
                                      : (isPinHovered ? currentTheme.accentColor.opacity(0.12) : currentTheme.primaryText.opacity(0.06)))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(snippet.isPinned ? Color.white.opacity(0.3) : (isPinHovered ? currentTheme.accentColor.opacity(0.35) : Color.clear), lineWidth: 1)
                        )
                        .scaleEffect(isPinHovered ? 1.04 : 1.0)
                        .animation(.easeOut(duration: 0.12), value: isPinHovered)
                }
                .buttonStyle(.plain)
                .help(snippet.isPinned
                      ? tr("Открепить фрагмент", "Unpin snippet", lang: language)
                      : tr("Закрепить фрагмент (всегда сверху)", "Pin snippet (always on top)", lang: language))
                .onHover { hovering in
                    isPinHovered = hovering
                    if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
                }

                // 2) Кнопка «Редактировать» (30x30 pt)
                Button {
                    TapticSoundAndHaptics.shared.playClick()
                    onEdit()
                } label: {
                    Image(systemName: "pencil")
                        .symbolRenderingMode(.monochrome)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isEditHovered ? currentTheme.accentColor : currentTheme.primaryText)
                        .frame(width: 30, height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(isEditHovered ? currentTheme.accentColor.opacity(0.16) : currentTheme.primaryText.opacity(0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(isEditHovered ? currentTheme.accentColor.opacity(0.35) : Color.clear, lineWidth: 1)
                        )
                        .scaleEffect(isEditHovered ? 1.04 : 1.0)
                        .animation(.easeOut(duration: 0.12), value: isEditHovered)
                }
                .buttonStyle(.plain)
                .help(tr("Редактировать фрагмент", "Edit snippet", lang: language))
                .onHover { hovering in
                    isEditHovered = hovering
                    if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
                }

                // 3) Главная акцентная кнопка «↩ Вставить в <targetApp>» (высота 30 pt, скругление 8 pt)
                Button {
                    onPaste()
                } label: {
                    HStack(spacing: 5) {
                        if isPastedToast {
                            Image(systemName: "checkmark")
                                .symbolRenderingMode(.monochrome)
                                .font(.system(size: 11, weight: .bold))
                            Text(tr("Вставлено", "Pasted", lang: language))
                                .font(currentFont.font(size: 11, weight: .bold))
                                .lineLimit(1)
                        } else {
                            Image(systemName: "arrow.turn.down.left")
                                .symbolRenderingMode(.monochrome)
                                .font(.system(size: 11, weight: .semibold))
                            Text(tr("Вставить в \(targetAppName)", "Paste to \(targetAppName)", lang: language))
                                .font(currentFont.font(size: 11, weight: .semibold))
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isPastedToast
                                  ? Color(red: 0.10, green: 0.78, blue: 0.45)
                                  : (isPasteHovered ? currentTheme.accentColor.opacity(0.88) : currentTheme.accentColor))
                    )
                    .foregroundStyle(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(isPastedToast ? Color.white.opacity(0.3) : Color.white.opacity(0.15), lineWidth: 1)
                    )
                    .shadow(color: isPastedToast ? Color(red: 0.10, green: 0.78, blue: 0.45).opacity(0.4) : Color.clear, radius: 4)
                    .scaleEffect(isPasteHovered && !isPastedToast ? 1.02 : 1.0)
                    .animation(.easeInOut(duration: 0.15), value: isPastedToast)
                    .animation(.easeOut(duration: 0.12), value: isPasteHovered)
                }
                .buttonStyle(.plain)
                .help(tr("Вставить фрагмент в активное окно \(targetAppName)", "Paste snippet into active window of \(targetAppName)", lang: language))
                .onHover { hovering in
                    isPasteHovered = hovering
                    if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
                }

                // 4) Кнопка «Скопировать» (30x30 pt)
                Button {
                    onCopy()
                } label: {
                    Image(systemName: isCopiedToast ? "checkmark" : "doc.on.doc")
                        .symbolRenderingMode(.monochrome)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isCopiedToast
                                         ? Color(red: 0.10, green: 0.78, blue: 0.45)
                                         : (isCopyHovered ? currentTheme.accentColor : currentTheme.primaryText))
                        .frame(width: 30, height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(isCopiedToast
                                      ? Color(red: 0.10, green: 0.78, blue: 0.45).opacity(0.18)
                                      : (isCopyHovered ? currentTheme.accentColor.opacity(0.16) : currentTheme.primaryText.opacity(0.06)))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(isCopiedToast
                                              ? Color(red: 0.10, green: 0.78, blue: 0.45).opacity(0.4)
                                              : (isCopyHovered ? currentTheme.accentColor.opacity(0.35) : Color.clear), lineWidth: 1)
                        )
                        .scaleEffect(isCopyHovered ? 1.04 : 1.0)
                        .animation(.easeOut(duration: 0.12), value: isCopyHovered)
                }
                .buttonStyle(.plain)
                .help(tr("Скопировать фрагмент", "Copy snippet", lang: language))
                .onHover { hovering in
                    isCopyHovered = hovering
                    if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
                }

                // 5) Кнопка «Удалить» (30x30 pt)
                Button {
                    TapticSoundAndHaptics.shared.performDialTick()
                    onDelete()
                } label: {
                    Image(systemName: "xmark")
                        .symbolRenderingMode(.monochrome)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(isDeleteHovered ? Color.red : currentTheme.secondaryText)
                        .frame(width: 30, height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(isDeleteHovered ? Color.red.opacity(0.16) : currentTheme.primaryText.opacity(0.04))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(isDeleteHovered ? Color.red.opacity(0.45) : Color.clear, lineWidth: 1)
                        )
                        .scaleEffect(isDeleteHovered ? 1.04 : 1.0)
                        .animation(.easeOut(duration: 0.12), value: isDeleteHovered)
                }
                .buttonStyle(.plain)
                .help(tr("Удалить фрагмент", "Delete snippet", lang: language))
                .onHover { hovering in
                    isDeleteHovered = hovering
                    if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
                }
            }
        }
        .padding(12)
        .liquidGlassCard(theme: currentTheme, windowOpacity: windowOpacity, cornerRadius: 11)
    }
}

// MARK: - Main Panel View
@MainActor
public struct MainPanelView: View {
    @ObservedObject var monitor: ClipboardMonitor
    @ObservedObject private var fontManager = FontManager.shared
    @State private var selectedTab: AppTab = .clipboard

    // Clipboard State
    @State private var searchQuery: String = ""
    @State private var selectedFilter: ClipboardFilterSelection = .category(.all)
    @State private var selectedItemId: String?
    @State private var keyboardScrollTargetId: String? = nil
    @State private var revealedSecretItemId: String? = nil
    @State private var copiedItemToastId: String?
    @State private var copiedOCRToastId: String?
    @State private var pastedItemToastId: String? = nil
    @State private var lastPastedItemId: String? = nil
    @State private var isShowingQRPopover: Bool = false
    @State private var copiedColorChip: String? = nil
    @AppStorage("tapticAudioFeedbackEnabled") private var tapticAudioFeedbackEnabled: Bool = true
    @AppStorage("autoCheckUpdates") private var autoCheckUpdates: Bool = false
    @FocusState private var isSearchFocused: Bool
    @State private var isFilterDropdownPresented: Bool = false
    @State private var isSortDropdownPresented: Bool = false

    // Snippets State
    @State private var snippetsSearch: String = ""
    @State private var snippetSearchScope: SnippetSearchScope = .all
    @State private var selectedSnippetCategory: String = "Все"
    @State private var snippetsList: [QuickSnippetItem] = []
    @State private var isAddingSnippet: Bool = false
    @State private var editingSnippet: QuickSnippetItem? = nil
    @State private var newSnippetTitle: String = ""
    @State private var newSnippetContent: String = ""
    @State private var newSnippetCategory: String = "Разработка"
    @State private var showClearSnippetsConfirmation: Bool = false
    @State private var pastedSnippetToastId: String? = nil
    @State private var copiedSnippetToastId: String? = nil

    // Lightbox, Screenshot Editor & Quick Text Editing State
    @State private var isImageLightboxPresented: Bool = false
    @State private var zoomedImage: NSImage? = nil
    @State private var zoomedItem: ClipboardItemRow? = nil
    @State private var lightboxScaleToFit: Bool = true
    @State private var lightboxZoomScale: CGFloat = 1.0
    @State private var isScreenshotEditingMode: Bool = false
    @State private var editorCanvasSize: CGSize = .zero
    @State private var editorPanOffset: CGSize = .zero
    @State private var isLightboxCopiedToastVisible: Bool = false
    @StateObject private var screenshotEditorEngine = ScreenshotEditorEngine()
    @State private var editingItemId: String? = nil
    @State private var editingItemText: String = ""

    // Clear History Confirmation Modal State
    @State private var showClearHistoryConfirmation: Bool = false

    // Backup & Restore State
    @State private var backupToastMessage: String? = nil
    @State private var backupToastIsError: Bool = false
    @State private var showExportModal: Bool = false
    @State private var exportIncludeClipboard: Bool = true
    @State private var exportClipboardPinnedOnly: Bool = false
    @State private var exportIncludeSnippets: Bool = true
    @State private var exportSnippetsPinnedOnly: Bool = false
    @State private var exportIncludeSettings: Bool = true
    @State private var exportIncludeBlacklist: Bool = true
    @State private var exportIncludeShortcuts: Bool = true
    @State private var exportIncludeAppearance: Bool = true

    @State private var showImportConfirmationModal: Bool = false
    @State private var importArchive: PasteVaultBackupArchive? = nil
    @State private var importFileName: String = ""
    @State private var importRestoreClipboard: Bool = true
    @State private var importRestoreSnippets: Bool = true
    @State private var importRestoreSettings: Bool = true
    @State private var importMergeMode: Bool = true

    // Settings, Theme, Font, Shortcuts & Language State
    @ObservedObject private var shortcutManager = ShortcutManager.shared
    @StateObject private var updateService = UpdateService.shared
    @State private var selectedSettingsSection: SettingsSidebarSection = .system
    @State private var isFontDropdownExpanded: Bool = false
    @State private var isFontButtonHovered: Bool = false
    @State private var isInspectorTimerPopoverPresented: Bool = false
    @State private var isShortcutsExpanded: Bool = true
    @State private var hoveredFont: AppFont? = nil
    @State private var isRunningAppsMenuHovered: Bool = false
    @State private var isRunningAppsDropdownPresented: Bool = false
    @AppStorage("selectedThemeId") private var selectedThemeId: String = AppTheme.obsidian.rawValue
    @AppStorage("userGlassLevel") private var userGlassLevel: Double = 0.70
    @AppStorage("selectedFontId") private var selectedFontId: String = AppFont.inter.rawValue
    @AppStorage("appLanguage") private var appLanguageRaw: String = AppLanguage.ru.rawValue
    @State private var fontRefreshTick: Int = 0

    // Hover States for Visual Feedback & Pointer Hand
    @State private var hoveredTab: AppTab? = nil
    @State private var hoveredSidebarSection: SettingsSidebarSection? = nil
    @State private var hoveredThemeId: String? = nil
    @State private var hoveredOpacityPreset: Double? = nil
    @State private var hoveredLanguage: AppLanguage? = nil
    @State private var hoveredHistoryLimit: Int? = nil
    @State private var hoveredShortcutRecordCommand: ShortcutCommand? = nil
    @State private var isZoomHovered: Bool = false
    @State private var isSaveHovered: Bool = false
    @State private var isLightboxSaveHovered: Bool = false
    @State private var isLightboxCloseHovered: Bool = false

    public static func isPasswordCandidate(_ item: ClipboardItemRow) -> Bool {
        ClipboardRowCardView.isPasswordCandidate(item)
    }

    private func isPasswordCandidate(_ item: ClipboardItemRow) -> Bool {
        ClipboardRowCardView.isPasswordCandidate(item)
    }

    public static func computeActualOpacity(level: Double) -> Double {
        0.50 + (min(max(level, 0.0), 1.0) * 0.50)
    }

    public var actualWindowOpacity: Double {
        Self.computeActualOpacity(level: userGlassLevel)
    }

    private var windowOpacity: Double {
        actualWindowOpacity
    }

    private var currentLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRaw) ?? .ru
    }

    private func tr(_ ru: String, _ en: String) -> String {
        currentLanguage == .en ? en : ru
    }

    private var currentTheme: AppTheme {
        AppTheme(rawValue: selectedThemeId) ?? .obsidian
    }

    private var currentFont: AppFont {
        _ = fontRefreshTick
        _ = fontManager.resolvedPostScriptNames.count
        if let font = AppFont(rawValue: selectedFontId) {
            return font
        }
        if selectedFontId == "jetbrains" {
            return .jetBrainsMono
        }
        return .inter
    }

    // Всегда вычисляем актуальный выбранный элемент напрямую из живого массива monitor.items
    private var selectedItem: ClipboardItemRow? {
        if let id = selectedItemId,
           let direct = monitor.items.first(where: { $0.id == id }) {
            return direct
        }
        return filteredItems.first
    }

    // PassGen State
    @State private var passLength: Double = 18
    @State private var passIncludeSymbols: Bool = true
    @State private var passIncludeDigits: Bool = true
    @State private var passIncludeUppercase: Bool = true
    @State private var passIsMnemonic: Bool = false
    @State private var passGeneratedSecret: String = ""
    @State private var passEntropyBits: Int = 92
    @State private var passCopiedNotification: Bool = false

    public init(monitor: ClipboardMonitor) {
        self.monitor = monitor
    }

    private var activeItemsList: [ClipboardItemRow] {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return monitor.items }
        return monitor.items.filter { item in
            item.textPreview.localizedCaseInsensitiveContains(trimmed) ||
            (item.sourceAppName?.localizedCaseInsensitiveContains(trimmed) == true) ||
            item.tags.contains(where: { $0.localizedCaseInsensitiveContains(trimmed) })
        }
    }

    private var filteredItems: [ClipboardItemRow] {
        activeItemsList.filter { item in
            let kind = item.effectiveContentType
            switch selectedFilter {
            case .category(let category):
                switch category {
                case .all:
                    return true
                case .pinned:
                    return item.isPinned
                case .text:
                    return kind == .text && !item.isSensitive
                case .file:
                    return kind == .file
                case .url:
                    return kind == .url
                case .code:
                    return kind == .code
                case .image:
                    return kind == .image
                case .secret:
                    return item.isSensitive || kind == .secret
                case .color:
                    return kind == .color
                }
            case .tag(let tagName):
                return item.tags.contains(tagName)
            }
        }
    }

    private var dynamicTagCounts: [(tag: String, count: Int)] {
        let canonicalOrder = ["#UTM-трекер", "#Swift", "#JSON", "#OCR", "Цвет"]
        var counts: [String: Int] = [:]
        for item in activeItemsList {
            for tag in item.tags {
                counts[tag, default: 0] += 1
            }
        }
        var result: [(String, Int)] = []
        for tag in canonicalOrder {
            if let c = counts[tag], c > 0 {
                result.append((tag, c))
            } else if case .tag(let selectedTag) = selectedFilter, selectedTag == tag {
                result.append((tag, 0))
            }
        }
        return result
    }

    private var isAccessibilityGranted: Bool {
        monitor.isAccessibilityGranted
    }
    @AppStorage("isAccessibilityBannerDismissed") private var isAccessibilityBannerDismissed: Bool = false
    @State private var accessibilityToastMessage: String? = nil
    @State private var accessibilityToastIsSuccess: Bool = false
    @State private var syntheticTestToastMessage: String? = nil
    @State private var isPasteBlockedToastVisible: Bool = false
    @State private var pasteBlockedToastTask: Task<Void, Never>? = nil

    public var body: some View {
        VStack(spacing: 0) {
            topHeaderWithTabs

            if isPasteBlockedToastVisible {
                pasteBlockedToastBanner
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if !isAccessibilityGranted && !isAccessibilityBannerDismissed && !isPasteBlockedToastVisible {
                accessibilityNoticeBanner
            }

            if let toastMessage = accessibilityToastMessage {
                accessibilityStatusToastBanner(message: toastMessage, isSuccess: accessibilityToastIsSuccess)
            }

            if let annotatedToast = monitor.annotatedCopyToastMessage {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.green)
                    Text(annotatedToast)
                        .font(currentFont.font(size: 11.5, weight: .semibold))
                        .foregroundStyle(currentTheme.primaryText)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        monitor.annotatedCopyToastMessage = nil
                    } label: {
                        Image(systemName: "xmark")
                            .symbolRenderingMode(.monochrome)
                            .font(.system(size: 9, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(currentTheme.secondaryText)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 7)
                .background(currentTheme.accentColor.opacity(0.14))
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            if let testToast = syntheticTestToastMessage {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(currentTheme.primaryText)
                    Text(testToast)
                        .font(currentFont.font(size: 11, weight: .semibold))
                        .foregroundStyle(currentTheme.primaryText)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        syntheticTestToastMessage = nil
                    } label: {
                        Image(systemName: "xmark")
                            .symbolRenderingMode(.monochrome)
                            .font(.system(size: 9, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(currentTheme.secondaryText)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
                .background(currentTheme.primaryText.opacity(0.08))
            }

            Divider()
                .background(currentTheme.borderColor)

            Group {
                switch selectedTab {
                case .clipboard:
                    clipboardTabView
                case .snippets:
                    snippetsTabView
                case .passgen:
                    passgenTabView
                case .settings:
                    settingsTabView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
                .background(currentTheme.borderColor)

            bottomStatusBar
        }
        .allowsHitTesting(!isImageLightboxPresented && !updateService.isUpdateModalPresented && !updateService.isUpToDateModalPresented && !showClearHistoryConfirmation && !showClearSnippetsConfirmation && !showExportModal && !showImportConfirmationModal)
        .overlay {
            clearHistoryModalOverlay
        }
        .overlay {
            clearSnippetsModalOverlay
        }
        .overlay {
            exportModalOverlay
        }
        .overlay {
            importConfirmationModalOverlay
        }
        .overlay {
            appUpdateModalOverlay
        }
        .overlay {
            appUpToDateModalOverlay
        }
        .overlay {
            if isImageLightboxPresented,
               let img = zoomedImage ?? (selectedItem.flatMap { monitor.imageForItem($0) }) ?? (selectedItem?.rawImageData.flatMap { NSImage(data: $0) }),
               let item = zoomedItem ?? selectedItem {
                imageLightboxOverlay(for: item, image: img)
                    .zIndex(1000)
            }
        }
        .font(currentFont.font(size: 13, weight: .regular))
        .frame(minWidth: 900, idealWidth: 900, maxWidth: .infinity, minHeight: 650, idealHeight: 650, maxHeight: .infinity)
        .liquidGlassWindow(theme: currentTheme, windowOpacity: windowOpacity)
        .tint(currentTheme.accentColor)
        .environment(\.colorScheme, currentTheme.isLight ? .light : .dark)
        .preferredColorScheme(currentTheme.isLight ? .light : .dark)
        .onAppear {
            revealedSecretItemId = nil
            syncWindowAppearance()
            FontManager.shared.ensureFontsInstalled()
            monitor.refreshAccessibilityStatus()
            isSearchFocused = true
            loadDefaultSnippetsIfNeeded()
            if selectedItemId == nil {
                selectedItemId = filteredItems.first?.id
            }
            generatePass()
        }
        .onChange(of: selectedTab) { _, _ in
            revealedSecretItemId = nil
        }
        .onChange(of: selectedThemeId) { _, _ in
            syncWindowAppearance()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("pasteVaultFontsUpdated"))) { _ in
            fontRefreshTick += 1
        }
        .onChange(of: monitor.items.count) { _, _ in
            revealedSecretItemId = nil
            if selectedItemId == nil || !filteredItems.contains(where: { $0.id == selectedItemId }) {
                selectedItemId = filteredItems.first?.id
            }
        }
        .onChange(of: monitor.items.first?.id) { _, _ in
            revealedSecretItemId = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .pasteVaultDidCaptureItem)) { _ in
            revealedSecretItemId = nil
        }
        .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
            refreshAccessibilityStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            refreshAccessibilityStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshAccessibilityStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("pasteVaultAccessibilityDidChange"))) { _ in
            refreshAccessibilityStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: ClipboardMonitor.pasteBlockedNotification)) { _ in
            refreshAccessibilityStatus()
            withAnimation(.easeOut(duration: 0.2)) {
                isPasteBlockedToastVisible = true
            }
            pasteBlockedToastTask?.cancel()
            pasteBlockedToastTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 9_000_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(.easeIn(duration: 0.2)) {
                    isPasteBlockedToastVisible = false
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("pasteVaultDidCaptureItem"))) { note in
            if let newId = note.object as? String {
                selectedItemId = newId
            } else if selectedItemId == nil {
                selectedItemId = filteredItems.first?.id
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("pasteVaultMoveSelectionDown"))) { _ in
            moveSelection(delta: 1)
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("pasteVaultMoveSelectionUp"))) { _ in
            moveSelection(delta: -1)
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("pasteVaultPasteSelected"))) { _ in
            if isImageLightboxPresented {
                if isScreenshotEditingMode {
                    screenshotEditorEngine.triggerShortcutHighlight("save")
                    if screenshotEditorEngine.editingTextAnnotationId != nil {
                        screenshotEditorEngine.commitActiveTextEditing()
                    } else if let img = zoomedImage ?? (selectedItem.flatMap { monitor.imageForItem($0) }) ?? (selectedItem?.rawImageData.flatMap { NSImage(data: $0) }),
                              let item = zoomedItem ?? selectedItem {
                        saveAnnotatedScreenshotAndClose(originalItem: item, sourceImage: img)
                    }
                }
                return
            }
            guard !isAddingSnippet else { return }
            switch selectedTab {
            case .clipboard:
                if let current = selectedItem {
                    pasteItem(current)
                }
            case .snippets:
                let filteredSnippets = snippetsList.filter {
                    snippetsSearch.isEmpty ||
                    $0.title.localizedCaseInsensitiveContains(snippetsSearch) ||
                    $0.content.localizedCaseInsensitiveContains(snippetsSearch)
                }
                if let firstSnippet = filteredSnippets.first {
                    instantCopyAndPaste(text: prepareSnippetForAction(firstSnippet))
                }
            case .passgen:
                if !passGeneratedSecret.isEmpty {
                    _ = monitor.recordGeneratedPassword(passGeneratedSecret, ttlSeconds: nil)
                    instantCopyAndPaste(text: passGeneratedSecret, ttl: nil)
                }
            case .settings:
                break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("pasteVaultPasteByIndex"))) { note in
            if let index = note.object as? Int,
               index >= 0, index < filteredItems.count {
                pasteItem(filteredItems[index])
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("pasteVaultPastePlainText"))) { _ in
            guard !isAddingSnippet else { return }
            switch selectedTab {
            case .clipboard:
                if let current = selectedItem {
                    monitor.pasteIntoTargetAppPlainText(current)
                }
            case .snippets:
                let filteredSnippets = snippetsList.filter {
                    snippetsSearch.isEmpty ||
                    $0.title.localizedCaseInsensitiveContains(snippetsSearch) ||
                    $0.content.localizedCaseInsensitiveContains(snippetsSearch)
                }
                if let firstSnippet = filteredSnippets.first {
                    instantCopyAndPaste(text: prepareSnippetForAction(firstSnippet))
                }
            case .passgen:
                if !passGeneratedSecret.isEmpty {
                    _ = monitor.recordGeneratedPassword(passGeneratedSecret, ttlSeconds: nil)
                    instantCopyAndPaste(text: passGeneratedSecret, ttl: nil)
                }
            case .settings:
                break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("pasteVaultTogglePin"))) { _ in
            if selectedTab == .clipboard, let current = selectedItem {
                togglePin(item: current)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("pasteVaultDeleteItem"))) { _ in
            if selectedTab == .clipboard, let current = selectedItem {
                deleteItem(current)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("pasteVaultClearHistory"))) { _ in
            clearUnpinnedHistory()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("pasteVaultTogglePause"))) { _ in
            monitor.isIncognitoPaused.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("pasteVaultOpenPassGen"))) { _ in
            TapticSoundAndHaptics.shared.performDialTick()
            selectedTab = .passgen
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("pasteVaultOpenSnippets"))) { _ in
            TapticSoundAndHaptics.shared.performDialTick()
            selectedTab = .snippets
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("pasteVaultOpenSettings"))) { _ in
            TapticSoundAndHaptics.shared.performDialTick()
            selectedTab = (selectedTab == .settings) ? .clipboard : .settings
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("pasteVaultCheckForUpdates"))) { _ in
            TapticSoundAndHaptics.shared.performDialTick()
            selectedTab = .settings
            selectedSettingsSection = .system
            Task {
                await updateService.checkForUpdates(manual: true)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("pasteVaultModalEscape"))) { _ in
            if showExportModal {
                showExportModal = false
                ClipboardMonitor.shared.isModalOverlayActive = false
                return
            }
            if showImportConfirmationModal {
                showImportConfirmationModal = false
                ClipboardMonitor.shared.isModalOverlayActive = false
                return
            }
            guard isImageLightboxPresented else { return }
            screenshotEditorEngine.triggerShortcutHighlight("escape")
            if isScreenshotEditingMode, screenshotEditorEngine.editingTextAnnotationId != nil {
                screenshotEditorEngine.commitActiveTextEditing()
            } else if isScreenshotEditingMode, screenshotEditorEngine.selectedAnnotationId != nil || screenshotEditorEngine.activeSubmenu != nil {
                screenshotEditorEngine.selectedAnnotationId = nil
                screenshotEditorEngine.activeSubmenu = nil
            } else {
                closeImageLightbox()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("pasteVaultEditorUndo"))) { _ in
            guard isImageLightboxPresented && isScreenshotEditingMode else { return }
            screenshotEditorEngine.triggerShortcutHighlight("undo")
            screenshotEditorEngine.undo()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("pasteVaultEditorZoomIn"))) { _ in
            guard isImageLightboxPresented else { return }
            screenshotEditorEngine.triggerShortcutHighlight("zoom")
            lightboxZoomScale = min(3.0, lightboxZoomScale + 0.25)
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("pasteVaultEditorZoomOut"))) { _ in
            guard isImageLightboxPresented else { return }
            screenshotEditorEngine.triggerShortcutHighlight("zoom")
            lightboxZoomScale = max(1.0, lightboxZoomScale - 0.25)
            if lightboxZoomScale <= 1.001 {
                editorPanOffset = .zero
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("pasteVaultEditorZoomReset"))) { _ in
            guard isImageLightboxPresented else { return }
            screenshotEditorEngine.triggerShortcutHighlight("zoom")
            lightboxScaleToFit = true
            lightboxZoomScale = 1.0
            editorPanOffset = .zero
        }
    }

    // MARK: - Header & Tab Bar
    private var topHeaderWithTabs: some View {
        HStack(spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                // Логотип PasteVault (Вариант №5 — Геометрический Форсаж Heavy Oblique, слитный без иконки)
                HStack(spacing: 0) {
                    Text("Paste")
                        .foregroundStyle(currentTheme.primaryText)
                    Text("Vault")
                        .foregroundStyle(currentTheme.accentColor)
                }
                .font(Font.custom("AvenirNext-HeavyItalic", size: 19))
                .tracking(-0.6)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

                // Индикатор целевого приложения (макс. ширина бейджа 120pt)
                HStack(spacing: 4) {
                    if let appIcon = monitor.targetAppIcon {
                        Image(nsImage: appIcon)
                            .resizable()
                            .frame(width: 12, height: 12)
                    } else {
                        Image(systemName: "arrow.up.forward.app.fill")
                            .font(.system(size: 9))
                    }
                    Text("→ \(monitor.targetAppName)")
                        .font(currentFont.font(size: 10, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .frame(maxWidth: 120, alignment: .leading)
                .background(currentTheme.badgeFill)
                .foregroundStyle(currentTheme.badgeText)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(currentTheme.accentColor.opacity(0.35), lineWidth: 0.8))
                .help(tr(
                    "При нажатии «Вставить» или Enter текст будет автоматически вставлен в \(monitor.targetAppName)",
                    "Pressing 'Paste' or Enter will automatically paste into \(monitor.targetAppName)"
                ))
            }

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                ForEach(AppTab.allCases) { tab in
                    let isSelected = (selectedTab == tab)
                    Button {
                        selectedTab = tab
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: tab.icon)
                                .symbolRenderingMode(.monochrome)
                                .font(.system(size: 13, weight: .medium))
                            Text(tab.title(in: currentLanguage))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                            if tab == .clipboard {
                                Text("\(monitor.items.count)")
                                    .font(currentFont.font(size: 9, weight: .bold))
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(isSelected ? currentTheme.accentColor.opacity(0.32) : currentTheme.primaryText.opacity(0.12))
                                    .foregroundStyle(currentTheme.primaryText)
                                    .clipShape(Capsule())
                            }
                        }
                        .frame(height: 28)
                    }
                    .buttonStyle(PVButtonStyle(variant: .toggle(isActive: isSelected), size: .small, theme: currentTheme, fixedHeight: 28))
                }
            }
            .padding(3)
            .liquidGlassCard(theme: currentTheme, windowOpacity: windowOpacity, cornerRadius: 10)

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                // Кнопка режима Запись / Инкогнито со светодиодным индикатором
                Button {
                    monitor.isIncognitoPaused.toggle()
                } label: {
                    HStack(spacing: 6) {
                        if monitor.isIncognitoPaused {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 8, height: 8)
                                .shadow(color: Color.orange.opacity(0.55), radius: 3)
                        } else {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                                .shadow(color: Color.green.opacity(0.65), radius: 3)
                        }
                        Text(monitor.isIncognitoPaused ? tr("Инкогнито", "Incognito") : tr("Запись", "Recording"))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .frame(height: 28)
                }
                .buttonStyle(PVButtonStyle(
                    variant: .secondary,
                    size: .small,
                    theme: currentTheme,
                    fixedHeight: 28,
                    customBorderColor: monitor.isIncognitoPaused ? Color.orange.opacity(0.55) : nil
                ))
                .help(tr(
                    "Нажмите, чтобы включить/выключить режим инкогнито (паузу сохранения)",
                    "Click to toggle Incognito mode (pause clipboard capture)"
                ))

                // Кнопка закрытия окна (Esc)
                Button {
                    NotificationCenter.default.post(name: Notification.Name("pasteVaultDismissPanel"), object: nil)
                } label: {
                    Image(systemName: "xmark")
                        .symbolRenderingMode(.monochrome)
                        .font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(PVButtonStyle(variant: .secondary, size: .small, theme: currentTheme, fixedWidth: 28, fixedHeight: 28))
                .help(tr(
                    "Закрыть окно и вернуться в \(monitor.targetAppName) (Esc)",
                    "Close window and return to \(monitor.targetAppName) (Esc)"
                ))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(
            ZStack {
                WindowDragHandle()
                if currentTheme.usesLiquidGlass {
                    // Хроматический стеклянный рефлекс в верхней шапке (macOS Tahoe / VisionOS)
                    LinearGradient(
                        colors: [
                            Color.white.opacity((currentTheme.isLight ? 0.45 : 0.14) * (0.25 + windowOpacity * 0.75)),
                            currentTheme.accentColor.opacity(0.08 * (0.25 + windowOpacity * 0.75)),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .allowsHitTesting(false)
                }
            }
        )
    }

    // MARK: - Accessibility Notice Banner
    private var accessibilityNoticeBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
                .font(.system(size: 13, weight: .medium))

            Text(tr(
                "Для прямой автовставки в \(monitor.targetAppName) по клику/Enter включите Универсальный доступ:",
                "Enable Accessibility in macOS Settings for direct auto-paste into \(monitor.targetAppName):"
            ))
                .font(currentFont.font(size: 11, weight: .regular))
                .foregroundStyle(currentTheme.primaryText.opacity(0.92))

            Spacer()

            Button {
                requestAccessibilityAccess()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "shield")
                        .symbolRenderingMode(.monochrome)
                    Text(tr("Разрешить доступ", "Grant Access"))
                }
            }
            .buttonStyle(PVButtonStyle(variant: .primary, size: .small, theme: currentTheme))

            Button {
                isAccessibilityBannerDismissed = true
            } label: {
                Image(systemName: "xmark")
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(PVButtonStyle(variant: .secondary, size: .small, theme: currentTheme))
            .help(tr("Скрыть подсказку (больше не показывать при запуске)", "Dismiss banner (do not show on launch)"))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
        .background(currentTheme.primaryText.opacity(0.08))
    }

    private func accessibilityStatusToastBanner(message: String, isSuccess: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: isSuccess ? "checkmark.circle.fill" : "info.circle.fill")
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(currentTheme.primaryText)
                .font(.system(size: 13, weight: .medium))

            Text(message)
                .font(currentFont.font(size: 11, weight: .semibold))
                .foregroundStyle(currentTheme.primaryText)
                .lineLimit(1)

            Spacer()

            if !isSuccess {
                Button(tr("Скрыть плашку", "Hide Banner")) {
                    isAccessibilityBannerDismissed = true
                    accessibilityToastMessage = nil
                }
                .buttonStyle(PVButtonStyle(variant: .secondary, size: .small, theme: currentTheme))
            }

            Button {
                accessibilityToastMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(PVButtonStyle(variant: .secondary, size: .small, theme: currentTheme))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 7)
        .background(currentTheme.primaryText.opacity(0.10))
    }

    private func requestAccessibilityPermission(triggerPrompt: Bool = false) {
        openAccessibilitySettings(triggerSystemPrompt: triggerPrompt)
    }

    /// Обновляет живой статус Универсального доступа
    private func refreshAccessibilityStatus() {
        monitor.refreshAccessibilityStatus()
        if monitor.isAccessibilityGranted && isPasteBlockedToastVisible {
            isPasteBlockedToastVisible = false
        }
    }

    /// Вызывает системный запрос Apple на предоставление Универсального доступа со сбросом старой записи TCC
    private func requestAccessibilityAccess() {
        // 1) Сначала сними окна Paste Vault с экрана
        NSApp.windows.forEach { $0.orderOut(nil) }
        NSApp.deactivate()

        // 2) Запусти синхронно процесс очистки старой записи TCC
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        task.arguments = ["reset", "Accessibility", "com.pastevault.app"]
        try? task.run()
        task.waitUntilExit()

        // 3) Через 0.15 секунды вызови системное окно запроса Apple
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)

            // 4) Ещё через 0.2 секунды подними системное окно Apple на передний план
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.UniversalAccessAuthWarn").first?.activate(options: [.activateAllWindows])
            }
        }
    }

    private func requestAndOpenAccessibility() {
        requestAccessibilityAccess()
    }

    private func openAccessibilitySettings(triggerSystemPrompt: Bool = false) {
        if triggerSystemPrompt {
            requestAccessibilityAccess()
        } else {
            AccessibilityService.openSystemSettingsOnly()
        }
    }

    // MARK: - Accessibility Status Card (Settings)
    private var accessibilityPermissionStatusCard: some View {
        let granted = monitor.isAccessibilityGranted
        let statusColor: Color = granted ? .green : Color(red: 0.95, green: 0.25, blue: 0.2)

        return HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.18))
                    .frame(width: 38, height: 38)
                Image(systemName: granted ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(statusColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(tr("Универсальный доступ", "Accessibility"))
                        .font(currentFont.font(size: 13, weight: .bold))
                        .foregroundStyle(currentTheme.primaryText)

                    // Капсула статуса
                    HStack(spacing: 5) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 6, height: 6)
                        Text(granted
                             ? tr("Активен", "Active")
                             : tr("Выключен", "Disabled"))
                            .font(currentFont.font(size: 10.5, weight: .bold))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(statusColor.opacity(0.16))
                    .foregroundStyle(statusColor)
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(statusColor.opacity(0.6), lineWidth: 1))
                }

                Text(tr(
                    "Необходим для прямой автовставки записей из буфера в активное окно по клику и клавише Enter.",
                    "Required for direct auto-paste of clipboard items into active windows on click and Enter key."
                ))
                .font(currentFont.font(size: 11, weight: .regular))
                .foregroundStyle(currentTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            if !granted {
                Button {
                    requestAccessibilityAccess()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.shield")
                            .symbolRenderingMode(.monochrome)
                        Text(tr("Разрешить доступ", "Grant Access"))
                    }
                }
                .buttonStyle(PVButtonStyle(variant: .primary, size: .small, theme: currentTheme))
            } else {
                Button {
                    AccessibilityService.openSystemSettingsOnly()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "gearshape")
                            .symbolRenderingMode(.monochrome)
                        Text(tr("Открыть настройки macOS", "Open macOS Settings"))
                    }
                }
                .buttonStyle(PVButtonStyle(variant: .secondary, size: .small, theme: currentTheme))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(statusColor.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(statusColor.opacity(0.35), lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.25), value: granted)
    }

    // MARK: - Paste Blocked Toast (no Accessibility)
    private var pasteBlockedToastBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.monochrome)
                .font(.system(size: 14))
                .foregroundStyle(currentTheme.primaryText)

            Text(tr(
                "Для прямой вставки требуется доступ в Настройках macOS. Текст скопирован в буфер — вставьте его вручную (⌘V) или откройте Настройки.",
                "Direct paste requires Accessibility access in macOS Settings. Text was copied to the clipboard — paste it manually (⌘V) or open Settings."
            ))
                .font(currentFont.font(size: 11, weight: .semibold))
                .foregroundStyle(currentTheme.primaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 6)

            Button {
                isPasteBlockedToastVisible = false
                requestAccessibilityAccess()
            } label: {
                Text(tr("Разрешить доступ", "Grant Access"))
            }
            .buttonStyle(PVButtonStyle(variant: .primary, size: .small, theme: currentTheme))

            Button {
                pasteBlockedToastTask?.cancel()
                isPasteBlockedToastVisible = false
            } label: {
                Image(systemName: "xmark")
                    .symbolRenderingMode(.monochrome)
            }
            .buttonStyle(PVButtonStyle(variant: .secondary, size: .small, theme: currentTheme))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(currentTheme.panelFill(opacity: 0.95))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(currentTheme.borderColor),
            alignment: .bottom
        )
    }

    // MARK: - Tab 1: Clipboard Tab View
    private var clipboardTabView: some View {
        VStack(spacing: 0) {
            // Верхняя панель: поиск, сортировка, типы и кнопка очистки строго в одну линию
            HStack(alignment: .center, spacing: 10) {
                // 1) Слева: поле «Поиск в истории буфера...» (355pt, ровно по карточкам)
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(currentTheme.secondaryText)

                    ZStack(alignment: .leading) {
                        if searchQuery.isEmpty {
                            Text(tr("Поиск в истории буфера...", "Search clipboard history..."))
                                .font(currentFont.font(size: 13, weight: .medium))
                                .foregroundStyle(currentTheme.secondaryText)
                                .allowsHitTesting(false)
                        }
                        TextField("", text: $searchQuery)
                            .textFieldStyle(.plain)
                            .font(currentFont.font(size: 13, weight: .medium))
                            .foregroundStyle(currentTheme.primaryText)
                            .focused($isSearchFocused)
                            .onChange(of: searchQuery) { _, _ in
                                selectedItemId = filteredItems.first?.id
                            }
                    }

                    if !searchQuery.isEmpty {
                        Button {
                            searchQuery = ""
                            selectedItemId = filteredItems.first?.id
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(currentTheme.secondaryText)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .frame(width: 355, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(currentTheme.isLight ? Color.white.opacity(0.75) : Color.clear)
                )
                .liquidGlassCard(theme: currentTheme, windowOpacity: windowOpacity, cornerRadius: 8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(currentTheme.primaryText.opacity(currentTheme.isLight ? 0.18 : 0.08), lineWidth: 1)
                )

                // 2) Сразу правее: СНАЧАЛА выпадающий список сортировки («Новые сверху»)
                compactSortOrderMenu

                // 3) Правее сортировки: выпадающий список фильтра типов («Все типы (X)»)
                compactCategoryFilterMenu

                Spacer()

                // 4) В правом конце этой же линии — кнопка «Очистить»
                if !monitor.items.isEmpty {
                    Button {
                        showClearHistoryConfirmation = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                                .symbolRenderingMode(.monochrome)
                            Text(tr("Очистить", "Clear"))
                        }
                    }
                    .buttonStyle(PVButtonStyle(variant: .secondary, size: .small, theme: currentTheme, fixedHeight: 30))
                    .help(tr("Удалить незакреплённые записи из истории (закреплённые сохраняются)", "Delete unpinned items from clipboard history (pinned are preserved)"))
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 16)
            .padding(.vertical, 8)

            Divider()
                .background(currentTheme.borderColor)

            HStack(spacing: 0) {
                leftHistoryColumn
                    .frame(width: 375)

                Divider()
                    .background(currentTheme.borderColor)

                rightInspectorColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: selectedFilter) { _, _ in
            selectedItemId = filteredItems.first?.id
        }
    }

    // MARK: - Custom Themed Dropdown Item Row
    private struct CustomDropdownItemRow: View {
        let title: String
        let icon: String
        let isSelected: Bool
        let currentTheme: AppTheme
        let currentFont: AppFont
        let action: () -> Void

        @State private var isHovered: Bool = false

        var body: some View {
            Button {
                TapticSoundAndHaptics.shared.performDialTick()
                action()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .symbolRenderingMode(.monochrome)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isSelected ? currentTheme.accentColor : currentTheme.secondaryText)
                        .frame(width: 16, alignment: .center)

                    Text(title)
                        .font(currentFont.font(size: 12, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? currentTheme.accentColor : currentTheme.primaryText)
                        .lineLimit(1)

                    Spacer(minLength: 16)

                    if isSelected {
                        Image(systemName: "checkmark")
                            .symbolRenderingMode(.monochrome)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(currentTheme.accentColor)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isHovered ? currentTheme.accentColor.opacity(0.16) : Color.clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .animation(.easeOut(duration: 0.12), value: isHovered)
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isHovered = hovering
                if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
            }
        }
    }

    // MARK: - Compact Dropdown Plate
    private struct CompactDropdownPlate: View {
        let icon: String
        let title: String
        let theme: AppTheme
        let font: AppFont
        @State private var isHovered: Bool = false

        var body: some View {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.accentColor)

                Text(title)
                    .font(font.font(size: 11.5, weight: .medium))
                    .foregroundStyle(theme.accentColor)
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(theme.accentColor.opacity(0.85))
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovered ? theme.accentColor.opacity(0.14) : theme.cardColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isHovered ? theme.accentColor.opacity(0.55) : theme.borderColor, lineWidth: 1)
            )
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .onHover { hovering in
                isHovered = hovering
                if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
            }
        }
    }

    // MARK: - Compact Category Filter Menu
    private var compactCategoryFilterMenu: some View {
        Button {
            TapticSoundAndHaptics.shared.performDialTick()
            isFilterDropdownPresented.toggle()
        } label: {
            CompactDropdownPlate(
                icon: "square.grid.2x2",
                title: "\(selectedFilter.title(in: currentLanguage)) (\(filterSelectionCount(selectedFilter)))",
                theme: currentTheme,
                font: currentFont
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isFilterDropdownPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(FilterCategory.allCases) { category in
                    let count = categoryCount(for: category)
                    let isSelected = (selectedFilter == .category(category))
                    CustomDropdownItemRow(
                        title: "\(category.title(in: currentLanguage)) (\(count))",
                        icon: category.icon,
                        isSelected: isSelected,
                        currentTheme: currentTheme,
                        currentFont: currentFont
                    ) {
                        selectedFilter = .category(category)
                        selectedItemId = filteredItems.first?.id
                        isFilterDropdownPresented = false
                    }
                }

                if !dynamicTagCounts.isEmpty {
                    Divider()
                        .background(currentTheme.borderColor.opacity(0.5))
                        .padding(.vertical, 3)

                    ForEach(dynamicTagCounts, id: \.tag) { entry in
                        let isSelected = (selectedFilter == .tag(entry.tag))
                        let displayTag = ClipboardFilterSelection.localizedTag(entry.tag, in: currentLanguage)
                        CustomDropdownItemRow(
                            title: "\(displayTag) (\(entry.count))",
                            icon: "tag.fill",
                            isSelected: isSelected,
                            currentTheme: currentTheme,
                            currentFont: currentFont
                        ) {
                            selectedFilter = .tag(entry.tag)
                            selectedItemId = filteredItems.first?.id
                            isFilterDropdownPresented = false
                        }
                    }
                }
            }
            .padding(6)
            .frame(minWidth: 230)
            .background(currentTheme.cardColor)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(currentTheme.borderColor, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 3)
            .environment(\.colorScheme, currentTheme.isLight ? .light : .dark)
        }
    }

    // MARK: - Compact Sort Order Menu
    private var compactSortOrderMenu: some View {
        Button {
            TapticSoundAndHaptics.shared.performDialTick()
            isSortDropdownPresented.toggle()
        } label: {
            CompactDropdownPlate(
                icon: "arrow.up.arrow.down",
                title: currentSortOrderTitle,
                theme: currentTheme,
                font: currentFont
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isSortDropdownPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                CustomDropdownItemRow(
                    title: tr("Новые сверху", "Newest first"),
                    icon: "arrow.down",
                    isSelected: monitor.historySortOrder == "lastCopied",
                    currentTheme: currentTheme,
                    currentFont: currentFont
                ) {
                    monitor.historySortOrder = "lastCopied"
                    monitor.applySortOrder()
                    isSortDropdownPresented = false
                }

                CustomDropdownItemRow(
                    title: tr("Старые сверху", "Oldest first"),
                    icon: "arrow.up",
                    isSelected: monitor.historySortOrder == "firstCopied",
                    currentTheme: currentTheme,
                    currentFont: currentFont
                ) {
                    monitor.historySortOrder = "firstCopied"
                    monitor.applySortOrder()
                    isSortDropdownPresented = false
                }

                CustomDropdownItemRow(
                    title: tr("По частоте", "Most used"),
                    icon: "chart.bar",
                    isSelected: monitor.historySortOrder == "mostUsed",
                    currentTheme: currentTheme,
                    currentFont: currentFont
                ) {
                    monitor.historySortOrder = "mostUsed"
                    monitor.applySortOrder()
                    isSortDropdownPresented = false
                }
            }
            .padding(6)
            .frame(minWidth: 175)
            .background(currentTheme.cardColor)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(currentTheme.borderColor, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 3)
            .environment(\.colorScheme, currentTheme.isLight ? .light : .dark)
        }
    }

    private var currentSortOrderTitle: String {
        switch monitor.historySortOrder {
        case "firstCopied":
            return tr("Старые сверху", "Oldest first")
        case "mostUsed":
            return tr("По частоте", "Most used")
        default:
            return tr("Новые сверху", "Newest first")
        }
    }

    // MARK: - Left History Column
    private func selectCardImmediately(_ id: String) {
        guard selectedItemId != id || revealedSecretItemId != nil else { return }
        TapticSoundAndHaptics.shared.performDialTick()
        var tx = Transaction()
        tx.disablesAnimations = true
        withTransaction(tx) {
            selectedItemId = id
            revealedSecretItemId = nil
        }
    }

    private var leftHistoryColumn: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    let items = filteredItems
                    if items.isEmpty {
                        if selectedFilter != .category(.all) && !activeItemsList.isEmpty {
                            // В выбранной категории или теге пусто, но в общем списке записи есть
                            VStack(spacing: 12) {
                                Image(systemName: selectedFilter.icon)
                                    .font(.system(size: 28))
                                    .foregroundStyle(currentTheme.secondaryText)
                                Text(tr(
                                    "В категории «\(selectedFilter.title(in: currentLanguage))» пока нет записей",
                                    "No items in category '\(selectedFilter.title(in: currentLanguage))'"
                                ))
                                    .font(currentFont.font(size: 13, weight: .semibold))
                                    .foregroundStyle(currentTheme.primaryText.opacity(0.88))
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 20)
                                Button(tr("Показать все записи (\(activeItemsList.count))", "Show All Items (\(activeItemsList.count))")) {
                                    selectedFilter = .category(.all)
                                    selectedItemId = filteredItems.first?.id
                                }
                                .pvButton(variant: .primary, size: .small, theme: currentTheme)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 48)
                        } else {
                            VStack(spacing: 12) {
                                Image(systemName: "doc.on.clipboard")
                                    .symbolRenderingMode(.monochrome)
                                    .font(.system(size: 28))
                                    .foregroundStyle(currentTheme.secondaryText)
                                Text(searchQuery.isEmpty
                                     ? tr("История буфера обмена пуста", "Clipboard history is empty")
                                     : tr("Ничего не найдено", "No matching items"))
                                    .font(currentFont.font(size: 13, weight: .semibold))
                                    .foregroundStyle(currentTheme.primaryText.opacity(0.88))
                                Text(tr(
                                    "Скопируйте любой текст или ссылку (⌘ + C) в любом приложении — они мгновенно появятся здесь.",
                                    "Copy any text or link (⌘ + C) in any application — it will appear here instantly."
                                ))
                                    .font(currentFont.font(size: 11, weight: .regular))
                                    .foregroundStyle(currentTheme.secondaryText)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 20)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 48)
                        }
                    } else {
                        let currentSelectedId = selectedItemId ?? items.first?.id
                        let pinnedItems = items.filter { $0.isPinned }
                        let unpinnedItems = items.filter { !$0.isPinned }

                        if !pinnedItems.isEmpty {
                            // 1. Блок: ЗАКРЕПЛЁННЫЕ (N)
                            HStack(spacing: 6) {
                                Image(systemName: "pin.fill")
                                    .symbolRenderingMode(.monochrome)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(currentTheme.primaryText)
                                Text(tr("ЗАКРЕПЛЁННЫЕ (\(pinnedItems.count))", "PINNED (\(pinnedItems.count))"))
                                    .font(currentFont.font(size: 10, weight: .bold))
                                    .foregroundStyle(currentTheme.primaryText.opacity(0.9))
                                    .tracking(0.5)
                                Spacer()
                            }
                            .padding(.horizontal, 6)
                            .padding(.top, 4)

                            ForEach(Array(pinnedItems.enumerated()), id: \.element.id) { index, item in
                                ClipboardRowCardView(
                                    item: item,
                                    index: index,
                                    isSelected: currentSelectedId == item.id,
                                    previewImage: monitor.imageForItem(item),
                                    targetAppName: monitor.targetAppName,
                                    currentTheme: currentTheme,
                                    currentFont: currentFont,
                                    language: currentLanguage,
                                    windowOpacity: windowOpacity,
                                    monitor: monitor,
                                    isPastedToast: (pastedItemToastId == item.id),
                                    searchQuery: searchQuery,
                                    onSelect: {
                                        selectCardImmediately(item.id)
                                    },
                                    onPaste: {
                                        pasteItem(item)
                                    },
                                    onDelete: {
                                        deleteItem(item)
                                    },
                                    onTogglePin: {
                                        togglePin(item: item)
                                    },
                                    onToggleSecret: {
                                        monitor.toggleSecretStatus(for: item.id)
                                        if revealedSecretItemId == item.id {
                                            revealedSecretItemId = nil
                                        }
                                    },
                                    onStartTimer: {
                                        let ttl = monitor.autoPurgeSecretsSeconds > 0 ? monitor.autoPurgeSecretsSeconds : 60
                                        monitor.startTimerForItem(id: item.id, seconds: ttl)
                                    },
                                    onCancelTimer: {
                                        monitor.cancelTimerForItem(id: item.id)
                                    }
                                )
                                .id(item.id)
                            }

                            if !unpinnedItems.isEmpty {
                                // Чёткий визуальный разделитель перед остальным списком
                                HStack(spacing: 8) {
                                    Rectangle()
                                        .fill(currentTheme.borderColor.opacity(0.6))
                                        .frame(height: 1)
                                    Text(tr("ИСТОРИЯ БУФЕРА (\(unpinnedItems.count))", "CLIPBOARD HISTORY (\(unpinnedItems.count))"))
                                        .font(currentFont.font(size: 9.5, weight: .bold))
                                        .foregroundStyle(currentTheme.secondaryText)
                                        .tracking(0.5)
                                        .fixedSize()
                                    Rectangle()
                                        .fill(currentTheme.borderColor.opacity(0.6))
                                        .frame(height: 1)
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 8)

                                ForEach(Array(unpinnedItems.enumerated()), id: \.element.id) { index, item in
                                    ClipboardRowCardView(
                                        item: item,
                                        index: pinnedItems.count + index,
                                        isSelected: currentSelectedId == item.id,
                                        previewImage: monitor.imageForItem(item),
                                        targetAppName: monitor.targetAppName,
                                        currentTheme: currentTheme,
                                        currentFont: currentFont,
                                        language: currentLanguage,
                                        windowOpacity: windowOpacity,
                                        monitor: monitor,
                                        isPastedToast: (pastedItemToastId == item.id),
                                        onSelect: {
                                            selectCardImmediately(item.id)
                                        },
                                        onPaste: {
                                            pasteItem(item)
                                        },
                                        onDelete: {
                                            deleteItem(item)
                                        },
                                        onTogglePin: {
                                            togglePin(item: item)
                                        },
                                        onToggleSecret: {
                                            monitor.toggleSecretStatus(for: item.id)
                                            if revealedSecretItemId == item.id {
                                                revealedSecretItemId = nil
                                            }
                                        },
                                        onStartTimer: {
                                            let ttl = monitor.autoPurgeSecretsSeconds > 0 ? monitor.autoPurgeSecretsSeconds : 60
                                            monitor.startTimerForItem(id: item.id, seconds: ttl)
                                        },
                                        onCancelTimer: {
                                            monitor.cancelTimerForItem(id: item.id)
                                        }
                                    )
                                    .id(item.id)
                                }
                            }
                        } else {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                ClipboardRowCardView(
                                    item: item,
                                    index: index,
                                    isSelected: currentSelectedId == item.id,
                                    previewImage: monitor.imageForItem(item),
                                    targetAppName: monitor.targetAppName,
                                    currentTheme: currentTheme,
                                    currentFont: currentFont,
                                    language: currentLanguage,
                                    windowOpacity: windowOpacity,
                                    monitor: monitor,
                                    isPastedToast: (pastedItemToastId == item.id),
                                    searchQuery: searchQuery,
                                    onSelect: {
                                        selectCardImmediately(item.id)
                                    },
                                    onPaste: {
                                        pasteItem(item)
                                    },
                                    onDelete: {
                                        deleteItem(item)
                                    },
                                    onTogglePin: {
                                        togglePin(item: item)
                                    },
                                    onToggleSecret: {
                                        monitor.toggleSecretStatus(for: item.id)
                                        if revealedSecretItemId == item.id {
                                            revealedSecretItemId = nil
                                        }
                                    },
                                    onStartTimer: {
                                        let ttl = monitor.autoPurgeSecretsSeconds > 0 ? monitor.autoPurgeSecretsSeconds : 60
                                        monitor.startTimerForItem(id: item.id, seconds: ttl)
                                    },
                                    onCancelTimer: {
                                        monitor.cancelTimerForItem(id: item.id)
                                    }
                                )
                                .id(item.id)
                            }
                        }
                    }
                }
                .padding(10)
            }
            .scrollContentBackground(.hidden)
            .background(currentTheme.panelFill(opacity: windowOpacity * 0.25))
            .onHover { hovering in
                if !hovering {
                    CardHoverCoordinator.shared.setHovered(nil)
                }
            }
            .onChange(of: selectedItemId) { _, _ in
                revealedSecretItemId = nil
            }
            .onChange(of: keyboardScrollTargetId) { _, targetId in
                if let targetId {
                    proxy.scrollTo(targetId, anchor: .center)
                }
            }
        }
    }

    // MARK: - Right Inspector Column
    private var rightInspectorColumn: some View {
        VStack(spacing: 0) {
            if let currentItem = selectedItem {
                let isSecret = currentItem.isSensitive || currentItem.effectiveContentType == .secret
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("\(tr("Источник:", "Source:")) \(displaySourceAppName(currentItem.sourceAppName))")
                                    .font(currentFont.font(size: 13, weight: .bold))
                                    .foregroundStyle(currentTheme.primaryText)
                            }

                            Text(formatTimestamp(currentItem.createdAt))
                                .font(currentFont.font(size: 11, weight: .regular))
                                .foregroundStyle(currentTheme.secondaryText)
                        }

                        Spacer()

                        // Кнопка «⏱ Таймер» / Капсула управления (ТОЛЬКО для паролей/секретов)
                        if isSecret {
                            TimelineView(.periodic(from: .now, by: 1.0)) { _ in
                                let paused = monitor.pausedTimerSeconds[currentItem.id]
                                let isPaused = (paused != nil && paused! > 0)
                                let remaining = isPaused ? (paused ?? 0) : (currentItem.expiresAt.map { max(0, Int(ceil($0.timeIntervalSinceNow))) } ?? 0)
                                let isRunning = !isPaused && currentItem.expiresAt != nil && remaining > 0
                                let isExpanded = isRunning || isPaused || isInspectorTimerPopoverPresented

                                ZStack(alignment: .trailing) {
                                    // Фиксированный невидимый якорь для привязки поповера на правом краю (24x24 pt)
                                    Color.clear
                                        .frame(width: 24, height: 24)
                                        .padding(.trailing, isExpanded ? 6 : 8)
                                        .popover(isPresented: $isInspectorTimerPopoverPresented, arrowEdge: .bottom) {
                                            TapticCircularTimerPopover(
                                                item: currentItem,
                                                monitor: monitor,
                                                currentTheme: currentTheme,
                                                currentFont: currentFont,
                                                language: currentLanguage,
                                                onClose: {
                                                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                                                        isInspectorTimerPopoverPresented = false
                                                    }
                                                }
                                            )
                                        }

                                    if isExpanded {
                                        // Развёрнутая капсула с 4 кнопками-иконками + моноширинным статусом/временем
                                        HStack(spacing: 5) {
                                            // Кнопка 1: «Пуск» ▶
                                            TimerCapsuleIconButton(
                                                icon: "play.fill",
                                                iconSize: 10,
                                                isEnabled: !isRunning,
                                                isActiveState: false,
                                                theme: currentTheme,
                                                tooltip: isPaused
                                                    ? tr("Возобновить отсчёт таймера", "Resume timer countdown")
                                                    : tr("Запустить таймер", "Start timer")
                                            ) {
                                                if isPaused {
                                                    monitor.resumeTimerForItem(id: currentItem.id)
                                                } else {
                                                    let defaultSec = monitor.autoPurgeSecretsSeconds > 0 ? monitor.autoPurgeSecretsSeconds : 60
                                                    monitor.startTimerForItem(id: currentItem.id, seconds: defaultSec)
                                                }
                                                TapticSoundAndHaptics.shared.performDialClickConfirm()
                                            }

                                            // Кнопка 2: «Пауза» ⏸
                                            TimerCapsuleIconButton(
                                                icon: "pause.fill",
                                                iconSize: 10,
                                                isEnabled: isRunning,
                                                isActiveState: isPaused,
                                                theme: currentTheme,
                                                tooltip: tr("Приостановить таймер", "Pause timer")
                                            ) {
                                                monitor.pauseTimerForItem(id: currentItem.id, remainingSeconds: remaining)
                                                TapticSoundAndHaptics.shared.performDialTick()
                                            }

                                            // Кнопка 3: «Стоп» ■
                                            TimerCapsuleIconButton(
                                                icon: "stop.fill",
                                                iconSize: 9,
                                                isEnabled: true,
                                                isActiveState: false,
                                                theme: currentTheme,
                                                tooltip: tr("Сбросить и выключить таймер", "Reset and stop timer")
                                            ) {
                                                monitor.cancelTimerForItem(id: currentItem.id)
                                                withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                                                    isInspectorTimerPopoverPresented = false
                                                }
                                                TapticSoundAndHaptics.shared.performDialClickConfirm()
                                            }

                                            // Тонкий вертикальный разделитель
                                            Rectangle()
                                                .fill(currentTheme.borderColor.opacity(0.5))
                                                .frame(width: 1, height: 16)
                                                .padding(.horizontal, 1)

                                            // Текстовый индикатор состояния и времени
                                            let statusText: String = {
                                                if isPaused {
                                                    return tr("Пауза · \(formatTimerMMSS(seconds: remaining))", "Paused · \(formatTimerMMSS(seconds: remaining))")
                                                } else if isRunning {
                                                    return formatTimerMMSS(seconds: remaining)
                                                } else {
                                                    return tr("Выбор", "Select")
                                                }
                                            }()

                                            Text(statusText)
                                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                                .monospacedDigit()
                                                .foregroundStyle(isPaused ? currentTheme.accentColor : (isRunning ? currentTheme.accentColor : currentTheme.primaryText))
                                                .lineLimit(1)
                                                .frame(minWidth: isPaused ? 92 : 46, alignment: .center)

                                            // Кнопка 4: «Таймер» ⏱ (переключение поповера с колесом)
                                            TimerCapsuleIconButton(
                                                icon: "timer",
                                                iconSize: 12,
                                                isEnabled: true,
                                                isActiveState: isInspectorTimerPopoverPresented,
                                                theme: currentTheme,
                                                tooltip: tr("Открыть / закрыть круговой таймер", "Toggle circular timer dial")
                                            ) {
                                                withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                                                    isInspectorTimerPopoverPresented.toggle()
                                                }
                                            }
                                        }
                                        .padding(3)
                                        .background(
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .fill(currentTheme.cardBackground.opacity(0.92))
                                        )
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .strokeBorder(isPaused ? currentTheme.accentColor.opacity(0.35) : currentTheme.borderColor.opacity(0.7), lineWidth: 1)
                                        )
                                        .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 1)
                                        .transition(.asymmetric(
                                            insertion: .scale(scale: 0.95).combined(with: .opacity),
                                            removal: .scale(scale: 0.95).combined(with: .opacity)
                                        ))
                                    } else {
                                        // Одиночная аккуратная кнопка «⏱ Таймер» в свёрнутом виде
                                        Button {
                                            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                                                isInspectorTimerPopoverPresented = true
                                            }
                                        } label: {
                                            HStack(spacing: 4) {
                                                Image(systemName: "timer")
                                                    .symbolRenderingMode(.monochrome)
                                                Text(tr("Таймер", "Timer"))
                                            }
                                            .frame(height: 28)
                                        }
                                        .pvButton(variant: .secondary, size: .small, theme: currentTheme, fixedHeight: 28)
                                        .help(tr("Настроить таймер автоудаления", "Configure auto-purge timer"))
                                        .transition(.opacity)
                                    }
                                }
                                .animation(.spring(response: 0.32, dampingFraction: 0.78), value: isExpanded)
                            }
                        }
                    }

                    // Быстрые трансформации для ссылок с UTM и JSON
                    if currentItem.effectiveContentType == .url && currentItem.tags.contains("#UTM-трекер") {
                        HStack(spacing: 8) {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(currentTheme.badgeText)
                            Text(tr("Обнаружены маркетинговые UTM-трекеры", "Marketing UTM tracking parameters detected"))
                                .font(currentFont.font(size: 11, weight: .medium))
                                .foregroundStyle(currentTheme.secondaryText)
                            Spacer()
                            Button {
                                stripUTMParameters(from: currentItem)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "sparkles")
                                        .symbolRenderingMode(.monochrome)
                                    Text(tr("Очистить UTM-метки", "Strip UTM Tags"))
                                }
                            }
                            .pvButton(variant: .secondary, size: .small, theme: currentTheme)
                        }
                        .padding(9)
                        .liquidGlassCard(theme: currentTheme, windowOpacity: windowOpacity, cornerRadius: 10)
                    } else if currentItem.tags.contains("#JSON") || SmartClassifier.isJSON(currentItem.textPreview) {
                        HStack(spacing: 8) {
                            Image(systemName: "curlybraces")
                                .symbolRenderingMode(.monochrome)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(currentTheme.badgeText)
                            Text("JSON")
                                .font(currentFont.font(size: 11, weight: .semibold))
                                .foregroundStyle(currentTheme.secondaryText)
                            Spacer()
                            Button {
                                transformJSON(for: currentItem, pretty: true)
                            } label: {
                                Text(tr("Форматировать JSON", "Format JSON"))
                            }
                            .pvButton(variant: .secondary, size: .small, theme: currentTheme)

                            Button {
                                transformJSON(for: currentItem, pretty: false)
                            } label: {
                                Text(tr("В одну строку", "Minify JSON"))
                            }
                            .pvButton(variant: .secondary, size: .small, theme: currentTheme)
                        }
                        .padding(9)
                        .liquidGlassCard(theme: currentTheme, windowOpacity: windowOpacity, cornerRadius: 10)
                    }

                    Divider()
                        .background(currentTheme.borderColor)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            if currentItem.effectiveContentType == .image {
                                let img = monitor.imageForItem(currentItem) ?? (currentItem.rawImageData.flatMap { NSImage(data: $0) }) ?? ClipboardMonitor.generateSyntheticScreenshotImage(label: currentItem.textPreview)

                                HStack(spacing: 8) {
                                    Button {
                                        zoomedImage = img
                                        zoomedItem = currentItem
                                        lightboxScaleToFit = true
                                        lightboxZoomScale = 1.0
                                        editorPanOffset = .zero
                                        screenshotEditorEngine.clearAll()
                                        isScreenshotEditingMode = true
                                        isImageLightboxPresented = true
                                    } label: {
                                        HStack(spacing: 5) {
                                            Text("✎")
                                                .font(.system(size: 13, weight: .bold))
                                            Text(tr("Редактировать", "Edit"))
                                        }
                                        .frame(height: 28)
                                    }
                                    .pvButton(variant: .primary, size: .small, theme: currentTheme, fixedHeight: 28)

                                    Button {
                                        saveImageToDisk(img: img, defaultName: "Screenshot-\(currentItem.id.prefix(8)).png")
                                    } label: {
                                        HStack(spacing: 5) {
                                            Image(systemName: "square.and.arrow.down")
                                                .symbolRenderingMode(.monochrome)
                                            Text(tr("Сохранить PNG", "Save PNG"))
                                        }
                                        .frame(height: 28)
                                    }
                                    .pvButton(variant: .secondary, size: .small, theme: currentTheme, fixedHeight: 28)

                                    Spacer()
                                }

                                // Контейнер-холст предпросмотра скриншота с чёткой контрастной рамкой вокруг самой картинки
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color.black.opacity(currentTheme.isLight ? 0.06 : 0.35))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .strokeBorder(currentTheme.borderColor, lineWidth: 1)
                                        )

                                    Image(nsImage: img)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(maxHeight: 220)
                                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                .strokeBorder(Color.white.opacity(0.28), lineWidth: 1)
                                        )
                                        .shadow(color: Color.black.opacity(0.55), radius: 10, x: 0, y: 4)
                                        .padding(12)
                                }
                                .frame(maxWidth: .infinity)
                                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .onHover { hovering in
                                    guard !isImageLightboxPresented else { return }
                                    if hovering {
                                        NSCursor.pointingHand.set()
                                    } else {
                                        NSCursor.arrow.set()
                                    }
                                }
                                .onDisappear {
                                    NSCursor.arrow.set()
                                }
                                .onTapGesture {
                                    NSCursor.arrow.set()
                                    zoomedImage = img
                                    zoomedItem = currentItem
                                    lightboxScaleToFit = true
                                    lightboxZoomScale = 1.0
                                    editorPanOffset = .zero
                                    screenshotEditorEngine.clearAll()
                                    isScreenshotEditingMode = true
                                    isImageLightboxPresented = true
                                }

                                if let ocr = currentItem.ocrText, !ocr.isEmpty {
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack(alignment: .top) {
                                            HStack(spacing: 4) {
                                                Image(systemName: "text.viewfinder")
                                                    .symbolRenderingMode(.monochrome)
                                                Text(tr("Распознанный текст (OCR)", "Recognized Text (OCR)"))
                                            }
                                            .font(currentFont.font(size: 11, weight: .semibold))
                                            .foregroundStyle(currentTheme.badgeText)
                                            .padding(.top, 4)

                                            Spacer()

                                            VStack(alignment: .trailing, spacing: 6) {
                                                Button {
                                                    monitor.copyToPasteboardImmediately(text: ocr)
                                                    copiedOCRToastId = currentItem.id
                                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                                        if copiedOCRToastId == currentItem.id {
                                                            copiedOCRToastId = nil
                                                        }
                                                    }
                                                } label: {
                                                    HStack(spacing: 4) {
                                                        Image(systemName: copiedOCRToastId == currentItem.id ? "checkmark" : "doc.on.doc")
                                                            .symbolRenderingMode(.monochrome)
                                                            .font(.system(size: 12, weight: .semibold))
                                                        Text(copiedOCRToastId == currentItem.id ? tr("Скопировано!", "Copied!") : tr("Скопировать OCR-текст", "Copy OCR Text"))
                                                            .font(currentFont.font(size: 12, weight: .semibold))
                                                            .lineLimit(1)
                                                    }
                                                    .frame(width: 200, height: 30)
                                                }
                                                .pvButton(variant: .secondary, size: .small, theme: currentTheme, fixedWidth: 200, fixedHeight: 30)
                                                .frame(width: 200, height: 30)

                                                Button {
                                                    if monitor.checkAccessibilityPermission() {
                                                        isPasteBlockedToastVisible = false
                                                    }
                                                    monitor.pasteIntoTargetApp(text: ocr)
                                                } label: {
                                                    HStack(spacing: 4) {
                                                        Image(systemName: "arrow.turn.down.left")
                                                            .symbolRenderingMode(.monochrome)
                                                            .font(.system(size: 12, weight: .semibold))
                                                        Text(tr("Вставить OCR-текст", "Paste OCR Text"))
                                                            .font(currentFont.font(size: 12, weight: .semibold))
                                                            .lineLimit(1)
                                                    }
                                                    .frame(width: 200, height: 30)
                                                }
                                                .pvButton(variant: .primary, size: .small, theme: currentTheme, fixedWidth: 200, fixedHeight: 30)
                                                .frame(width: 200, height: 30)
                                            }
                                        }
                                        Text(ocr)
                                            .font(currentFont.font(size: 11, weight: .regular))
                                            .foregroundStyle(currentTheme.primaryText)
                                            .textSelection(.enabled)
                                            .padding(8)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .liquidGlassCard(theme: currentTheme, windowOpacity: windowOpacity, cornerRadius: 8)
                                    }
                                    .padding(9)
                                    .liquidGlassCard(theme: currentTheme, windowOpacity: windowOpacity, cornerRadius: 10)
                                }
                            } else if currentItem.effectiveContentType == .color,
                                      let colorFormats = monitor.colorFormats(for: currentItem) {
                                let nsColor = colorFormats.color
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack(spacing: 12) {
                                        Circle()
                                            .fill(Color(nsColor: nsColor))
                                            .frame(width: 36, height: 36)
                                            .overlay(Circle().stroke(currentTheme.primaryText.opacity(0.55), lineWidth: 2))
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(tr("Цветовой код", "Color Value"))
                                                .font(currentFont.font(size: 11, weight: .semibold))
                                                .foregroundStyle(currentTheme.secondaryText)
                                            Text(currentItem.textPreview)
                                                .font(currentFont.font(size: 16, weight: .bold))
                                                .foregroundStyle(currentTheme.primaryText)
                                        }
                                        Spacer()
                                    }

                                    HStack(spacing: 8) {
                                        let hex = colorFormats.hex
                                        let rgb = colorFormats.rgb
                                        let hsl = colorFormats.hsl

                                        colorFormatChip(for: currentItem, format: "HEX", value: hex)
                                        colorFormatChip(for: currentItem, format: "RGB", value: rgb)
                                        colorFormatChip(for: currentItem, format: "HSL", value: hsl)
                                    }
                                }
                                .padding(12)
                                .liquidGlassCard(theme: currentTheme, windowOpacity: windowOpacity, cornerRadius: 11)
                            } else if currentItem.effectiveContentType == .url,
                                      let rawUrl = URL(string: currentItem.textPreview.trimmingCharacters(in: .whitespacesAndNewlines)) {
                                HStack(spacing: 10) {
                                    Button {
                                        NSWorkspace.shared.open(rawUrl)
                                    } label: {
                                        HStack(spacing: 5) {
                                            Image(systemName: "safari")
                                                .symbolRenderingMode(.monochrome)
                                                .font(.system(size: 12, weight: .semibold))
                                            Text(tr("Открыть в браузере", "Open in Browser"))
                                                .font(currentFont.font(size: 12, weight: .semibold))
                                                .lineLimit(1)
                                        }
                                        .frame(height: 28)
                                    }
                                    .pvButton(variant: .secondary, size: .small, theme: currentTheme, fixedHeight: 28)
                                    .help(tr("Открыть ссылку в браузере по умолчанию", "Open URL in default browser"))

                                    Button {
                                        isShowingQRPopover.toggle()
                                    } label: {
                                        HStack(spacing: 5) {
                                            Image(systemName: "qrcode")
                                                .symbolRenderingMode(.monochrome)
                                                .font(.system(size: 12, weight: .semibold))
                                            Text(tr("QR-код", "QR Code"))
                                                .font(currentFont.font(size: 12, weight: .semibold))
                                                .lineLimit(1)
                                        }
                                        .frame(height: 28)
                                    }
                                    .pvButton(variant: .secondary, size: .small, theme: currentTheme, fixedHeight: 28)
                                    .help(tr("Показать QR-код для сканирования смартфоном", "Show QR code to scan with phone"))
                                    .popover(isPresented: $isShowingQRPopover, arrowEdge: .bottom) {
                                        QRCodePopoverView(
                                            url: currentItem.textPreview.trimmingCharacters(in: .whitespacesAndNewlines),
                                            theme: currentTheme,
                                            language: currentLanguage
                                        )
                                    }

                                    Spacer()
                                }
                                .padding(12)
                                .liquidGlassCard(theme: currentTheme, windowOpacity: windowOpacity, cornerRadius: 11)
                            } else if currentItem.effectiveContentType == .file {
                                HStack(spacing: 12) {
                                    if let icon = monitor.imageForItem(currentItem) {
                                        Image(nsImage: icon)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 44, height: 44)
                                    } else {
                                        Image(systemName: "doc.fill")
                                            .symbolRenderingMode(.monochrome)
                                            .font(.system(size: 32))
                                            .foregroundStyle(currentTheme.primaryText)
                                    }
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(currentItem.fileURLs.first?.lastPathComponent ?? currentItem.textPreview)
                                            .font(currentFont.font(size: 13, weight: .semibold))
                                            .foregroundStyle(currentTheme.primaryText)
                                        if let path = currentItem.fileURLPath {
                                            Text(path)
                                                .font(.system(size: 11, design: .monospaced))
                                                .foregroundStyle(currentTheme.secondaryText)
                                                .lineLimit(2)
                                                .textSelection(.enabled)
                                        }
                                    }
                                    Spacer()
                                }
                                .padding(12)
                                .liquidGlassCard(theme: currentTheme, windowOpacity: windowOpacity, cornerRadius: 11)
                            }

                            if currentItem.effectiveContentType != .image && currentItem.effectiveContentType != .file {
                                if editingItemId == currentItem.id {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Label(tr("Редактирование текста перед вставкой", "Edit Text Before Pasting"), systemImage: "pencil")
                                                .font(currentFont.font(size: 11, weight: .semibold))
                                                .foregroundStyle(currentTheme.accentColor)
                                            Spacer()
                                        }

                                        TextEditor(text: $editingItemText)
                                            .font(currentFont.font(size: 13, weight: .regular))
                                            .foregroundStyle(currentTheme.primaryText)
                                            .frame(minHeight: 120, maxHeight: 220)
                                            .padding(6)
                                            .background(currentTheme.panelFill(opacity: windowOpacity * 0.4))
                                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                    .strokeBorder(currentTheme.accentColor.opacity(0.6), lineWidth: 1)
                                            )

                                        HStack(spacing: 8) {
                                            Button {
                                                monitor.updateItemText(id: currentItem.id, newText: editingItemText)
                                                editingItemId = nil
                                            } label: {
                                                HStack(spacing: 4) {
                                                    Image(systemName: "checkmark")
                                                        .symbolRenderingMode(.monochrome)
                                                    Text(tr("Сохранить", "Save"))
                                                }
                                            }
                                            .pvButton(variant: .secondary, size: .small, theme: currentTheme)

                                            Button {
                                                monitor.updateItemText(id: currentItem.id, newText: editingItemText)
                                                editingItemId = nil
                                                if let updated = monitor.items.first(where: { $0.id == currentItem.id }) {
                                                    pasteItem(updated)
                                                }
                                            } label: {
                                                HStack(spacing: 4) {
                                                    Image(systemName: "bolt.fill")
                                                        .symbolRenderingMode(.monochrome)
                                                    Text(tr("Сохранить и вставить", "Save & Paste"))
                                                }
                                            }
                                            .pvButton(variant: .primary, size: .small, theme: currentTheme)

                                            Button {
                                                editingItemId = nil
                                            } label: {
                                                Text(tr("Отмена", "Cancel"))
                                            }
                                            .pvButton(variant: .secondary, size: .small, theme: currentTheme)

                                            Spacer()
                                        }
                                    }
                                    .padding(12)
                                    .liquidGlassCard(theme: currentTheme, windowOpacity: windowOpacity, cornerRadius: 11)
                                } else {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack(alignment: .center, spacing: 8) {
                                            if isSecret {
                                                HStack(spacing: 5) {
                                                    Image(systemName: "key.fill")
                                                        .symbolRenderingMode(.monochrome)
                                                    Text(tr("Скрытый пароль", "Hidden Secret"))
                                                }
                                                .font(currentFont.font(size: 11, weight: .semibold))
                                                .foregroundStyle(currentTheme.badgeText)
                                            }

                                            Spacer()

                                            HStack(spacing: 8) {
                                                Button {
                                                    editingItemId = currentItem.id
                                                    editingItemText = currentItem.textPreview
                                                } label: {
                                                    HStack(spacing: 4) {
                                                        Image(systemName: "pencil")
                                                            .symbolRenderingMode(.monochrome)
                                                            .font(.system(size: 12, weight: .semibold))
                                                        Text(tr("Редактировать", "Edit"))
                                                            .font(currentFont.font(size: 12, weight: .semibold))
                                                            .lineLimit(1)
                                                    }
                                                    .padding(.horizontal, 4)
                                                    .frame(height: 28)
                                                }
                                                .pvButton(variant: .secondary, size: .small, theme: currentTheme, fixedHeight: 28)
                                                .fixedSize(horizontal: true, vertical: false)

                                                if isSecret {
                                                    let isRevealed = (revealedSecretItemId == currentItem.id)
                                                    Button {
                                                        if isRevealed {
                                                            revealedSecretItemId = nil
                                                        } else {
                                                            revealedSecretItemId = currentItem.id
                                                        }
                                                    } label: {
                                                        HStack(spacing: 4) {
                                                            Image(systemName: isRevealed ? "eye.slash.fill" : "eye.fill")
                                                                .symbolRenderingMode(.monochrome)
                                                                .font(.system(size: 12, weight: .semibold))
                                                            Text(isRevealed ? tr("Скрыть пароль", "Hide Password") : tr("Показать пароль", "Show Password"))
                                                                .font(currentFont.font(size: 12, weight: .semibold))
                                                                .lineLimit(1)
                                                        }
                                                        .padding(.horizontal, 4)
                                                        .frame(height: 28)
                                                    }
                                                    .pvButton(variant: .toggle(isActive: isRevealed), size: .small, theme: currentTheme, fixedHeight: 28)
                                                    .fixedSize(horizontal: true, vertical: false)
                                                    .help(tr("Показать / скрыть пароль", "Show / hide password"))
                                                }
                                            }
                                        }

                                        if isSecret && (revealedSecretItemId != currentItem.id) {
                                            Text(SmartClassifier.maskedSecret(currentItem.textPreview))
                                                .font(currentFont.font(size: 13, weight: .semibold))
                                                .foregroundStyle(currentTheme.badgeText)
                                                .textSelection(.enabled)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        } else if !searchQuery.isEmpty {
                                            Text(SearchHighlightHelper.highlight(
                                                text: String(currentItem.textPreview.prefix(4096)),
                                                query: searchQuery,
                                                baseFont: currentFont.font(size: 13, weight: .regular),
                                                baseColor: currentTheme.primaryText,
                                                accentColor: currentTheme.accentColor,
                                                isLight: currentTheme.isLight,
                                                bold: true
                                            ))
                                            .textSelection(.enabled)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        } else {
                                            Text(String(currentItem.textPreview.prefix(4096)))
                                                .font(currentFont.font(size: 13, weight: .regular))
                                                .foregroundStyle(currentTheme.primaryText)
                                                .textSelection(.enabled)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                    }
                                    .padding(12)
                                    .liquidGlassCard(theme: currentTheme, windowOpacity: windowOpacity, cornerRadius: 11)
                                }
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)

                    HStack(spacing: 10) {
                        Button {
                            pasteItem(currentItem)
                        } label: {
                            HStack(spacing: 4) {
                                if pastedItemToastId == currentItem.id {
                                    Image(systemName: "checkmark")
                                        .symbolRenderingMode(.monochrome)
                                        .font(.system(size: 13, weight: .semibold))
                                    Text(tr("Вставлено", "Pasted"))
                                        .font(currentFont.font(size: 13, weight: .semibold))
                                        .lineLimit(1)
                                } else {
                                    Image(systemName: "arrow.turn.down.left")
                                        .symbolRenderingMode(.monochrome)
                                        .font(.system(size: 13, weight: .semibold))
                                    Text(tr("Вставить в \(monitor.targetAppName)", "Paste to \(monitor.targetAppName)"))
                                        .font(currentFont.font(size: 13, weight: .semibold))
                                        .lineLimit(1)
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .pvButton(variant: (pastedItemToastId == currentItem.id) ? .success : .primary, size: .regular, theme: currentTheme, fixedHeight: 34)
                        .animation(.easeInOut(duration: 0.18), value: pastedItemToastId)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)

                        Button {
                            if currentItem.effectiveContentType == .image || currentItem.effectiveContentType == .file {
                                monitor.copyToClipboard(item: currentItem)
                            } else {
                                monitor.copyToPasteboardImmediately(text: currentItem.textPreview)
                            }
                            copiedItemToastId = currentItem.id
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                if copiedItemToastId == currentItem.id {
                                    copiedItemToastId = nil
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: copiedItemToastId == currentItem.id ? "checkmark" : "doc.on.doc")
                                    .symbolRenderingMode(.monochrome)
                                    .font(.system(size: 13, weight: .semibold))
                                Text(copiedItemToastId == currentItem.id ? tr("Скопировано!", "Copied!") : tr("Скопировать", "Copy"))
                                    .font(currentFont.font(size: 13, weight: .semibold))
                                    .lineLimit(1)
                            }
                            .frame(maxHeight: .infinity)
                        }
                        .pvButton(variant: .secondary, size: .regular, theme: currentTheme, fixedHeight: 34)
                        .frame(height: 34)

                        Button {
                            deleteItem(currentItem)
                        } label: {
                            Image(systemName: "trash")
                                .symbolRenderingMode(.monochrome)
                                .font(.system(size: 13, weight: .semibold))
                                .frame(maxHeight: .infinity)
                        }
                        .pvButton(variant: .secondary, size: .regular, theme: currentTheme, fixedHeight: 34)
                        .frame(height: 34)
                        .help(tr("Удалить из истории", "Delete from history"))
                    }
                }
                .padding(16)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "cursorarrow.click.2")
                        .font(.system(size: 32))
                        .foregroundStyle(currentTheme.secondaryText)
                    Text(tr("Выберите элемент из списка слева", "Select an item from the list on the left"))
                        .font(currentFont.font(size: 13, weight: .regular))
                        .foregroundStyle(currentTheme.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(
            ZStack {
                WindowDragHandle()
                currentTheme.panelFill(opacity: currentTheme.usesLiquidGlass ? windowOpacity * 0.35 : 1.0)
            }
        )
    }

    // MARK: - Tab 2: Snippets Tab View
    private var snippetsTabView: some View {
        let trimmedSearch = snippetsSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        let filteredSnippets: [QuickSnippetItem] = {
            if trimmedSearch.isEmpty {
                return snippetsList.sorted { $0.isPinned && !$1.isPinned }
            } else {
                let matched = snippetsList.filter { snippet in
                    let titleMatch = snippet.title.localizedCaseInsensitiveContains(trimmedSearch) ||
                                     localizedSnippetTitle(snippet.title).localizedCaseInsensitiveContains(trimmedSearch)
                    if snippetSearchScope == .titleOnly {
                        return titleMatch
                    } else {
                        let contentMatch = snippet.content.localizedCaseInsensitiveContains(trimmedSearch) ||
                                          localizedSnippetContent(snippet.content).localizedCaseInsensitiveContains(trimmedSearch)
                        return titleMatch || contentMatch
                    }
                }
                return SearchHighlightHelper.sortSnippets(matched, query: trimmedSearch, scope: snippetSearchScope)
            }
        }()

        let unpinnedCount = snippetsList.filter { !$0.isPinned }.count

        return VStack(spacing: 0) {
            // Верхняя панель: поиск, переключатель режима поиска, кнопка очистки и кнопка создания
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(currentTheme.secondaryText)

                    ZStack(alignment: .leading) {
                        if snippetsSearch.isEmpty {
                            Text(tr("Поиск быстрых фрагментов (Snippets)...", "Search quick snippets..."))
                                .font(currentFont.font(size: 13, weight: .medium))
                                .foregroundStyle(currentTheme.secondaryText)
                                .allowsHitTesting(false)
                        }
                        TextField("", text: $snippetsSearch)
                            .textFieldStyle(.plain)
                            .font(currentFont.font(size: 13, weight: .medium))
                            .foregroundStyle(currentTheme.primaryText)
                    }

                    if !snippetsSearch.isEmpty {
                        Button {
                            snippetsSearch = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(currentTheme.secondaryText)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(currentTheme.isLight ? Color.white.opacity(0.75) : Color.clear)
                )
                .liquidGlassCard(theme: currentTheme, windowOpacity: windowOpacity, cornerRadius: 8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(currentTheme.primaryText.opacity(currentTheme.isLight ? 0.18 : 0.08), lineWidth: 1)
                )

                // Переключатель режима поиска «Заголовок + Текст» / «Только название» при наличии запроса
                if !trimmedSearch.isEmpty {
                    HStack(spacing: 2) {
                        Button {
                            snippetSearchScope = .all
                            TapticSoundAndHaptics.shared.performDialTick()
                        } label: {
                            Text(tr("Заголовок + Текст", "Title + Text"))
                                .font(currentFont.font(size: 10.5, weight: snippetSearchScope == .all ? .semibold : .medium))
                                .padding(.horizontal, 8)
                                .frame(height: 26)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(snippetSearchScope == .all ? currentTheme.accentColor.opacity(currentTheme.isLight ? 0.22 : 0.32) : Color.clear)
                                )
                                .foregroundStyle(snippetSearchScope == .all ? currentTheme.accentColor : currentTheme.secondaryText)
                        }
                        .buttonStyle(.plain)

                        Button {
                            snippetSearchScope = .titleOnly
                            TapticSoundAndHaptics.shared.performDialTick()
                        } label: {
                            Text(tr("Только название", "Title Only"))
                                .font(currentFont.font(size: 10.5, weight: snippetSearchScope == .titleOnly ? .semibold : .medium))
                                .padding(.horizontal, 8)
                                .frame(height: 26)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(snippetSearchScope == .titleOnly ? currentTheme.accentColor.opacity(currentTheme.isLight ? 0.22 : 0.32) : Color.clear)
                                )
                                .foregroundStyle(snippetSearchScope == .titleOnly ? currentTheme.accentColor : currentTheme.secondaryText)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(2)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(currentTheme.primaryText.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(currentTheme.borderColor, lineWidth: 1)
                    )
                }

                Spacer()

                // Кнопка очистки незакрепленных фрагментов
                if unpinnedCount > 0 {
                    Button {
                        showClearSnippetsConfirmation = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                                .symbolRenderingMode(.monochrome)
                            Text(tr("Очистить (\(unpinnedCount))", "Clear (\(unpinnedCount))"))
                        }
                    }
                    .buttonStyle(PVButtonStyle(variant: .secondary, size: .small, theme: currentTheme, fixedHeight: 30))
                    .help(tr("Удалить все незакрепленные фрагменты (закрепленные сохраняются)", "Delete all unpinned snippets (pinned are preserved)"))
                }

                Button {
                    isAddingSnippet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .symbolRenderingMode(.monochrome)
                        Text(tr("Новый фрагмент", "New Snippet"))
                    }
                }
                .buttonStyle(PVButtonStyle(variant: .primary, size: .small, theme: currentTheme, fixedHeight: 30))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()
                .background(currentTheme.borderColor)

            ScrollView {
                LazyVStack(spacing: 8) {
                    if filteredSnippets.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "text.quote")
                                .symbolRenderingMode(.monochrome)
                                .font(.system(size: 32))
                                .foregroundStyle(currentTheme.secondaryText)
                            Text(tr("Фрагментов пока нет", "No snippets yet"))
                                .font(currentFont.font(size: 13, weight: .regular))
                                .foregroundStyle(currentTheme.secondaryText)
                        }
                        .padding(.top, 40)
                    } else {
                        ForEach(filteredSnippets) { snippet in
                            let titleMatch = snippet.title.localizedCaseInsensitiveContains(trimmedSearch) || localizedSnippetTitle(snippet.title).localizedCaseInsensitiveContains(trimmedSearch)
                            let contentMatch = snippet.content.localizedCaseInsensitiveContains(trimmedSearch) || localizedSnippetContent(snippet.content).localizedCaseInsensitiveContains(trimmedSearch)

                            QuickSnippetCardRowView(
                                snippet: snippet,
                                targetAppName: monitor.targetAppName,
                                currentTheme: currentTheme,
                                currentFont: currentFont,
                                language: currentLanguage,
                                windowOpacity: windowOpacity,
                                searchQuery: trimmedSearch,
                                isTitleMatched: titleMatch,
                                isContentMatched: contentMatch,
                                isPastedToast: (pastedSnippetToastId == snippet.id),
                                isCopiedToast: (copiedSnippetToastId == snippet.id),
                                onTogglePin: {
                                    if let idx = snippetsList.firstIndex(where: { $0.id == snippet.id }) {
                                        snippetsList[idx].isPinned.toggle()
                                        saveSnippets()
                                    }
                                },
                                onEdit: {
                                    editingSnippet = snippet
                                    newSnippetTitle = snippet.title
                                    newSnippetCategory = snippet.category
                                    newSnippetContent = snippet.content
                                },
                                onPaste: {
                                    pastedSnippetToastId = snippet.id
                                    TapticSoundAndHaptics.shared.playClick()
                                    instantCopyAndPaste(text: prepareSnippetForAction(snippet))
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                        if pastedSnippetToastId == snippet.id {
                                            pastedSnippetToastId = nil
                                        }
                                    }
                                },
                                onCopy: {
                                    monitor.copyToPasteboardImmediately(text: prepareSnippetForAction(snippet))
                                    copiedSnippetToastId = snippet.id
                                    TapticSoundAndHaptics.shared.playClick()
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                        if copiedSnippetToastId == snippet.id {
                                            copiedSnippetToastId = nil
                                        }
                                    }
                                },
                                onDelete: {
                                    snippetsList.removeAll { $0.id == snippet.id }
                                    saveSnippets()
                                }
                            )
                            .id(snippet.id)
                        }
                    }
                }
                .padding(16)
            }
            .scrollContentBackground(.hidden)
        }
        .sheet(isPresented: Binding(
            get: { isAddingSnippet || editingSnippet != nil },
            set: { if !$0 { isAddingSnippet = false; editingSnippet = nil } }
        )) {
            addSnippetSheetView
        }
    }

    private var addSnippetSheetView: some View {
        let isEditing = editingSnippet != nil
        return VStack(alignment: .leading, spacing: 14) {
            Text(isEditing ? tr("Редактирование фрагмента", "Edit Snippet") : tr("Новый фрагмент", "New Snippet"))
                .font(currentFont.font(size: 15, weight: .bold))
                .foregroundStyle(currentTheme.primaryText)

            VStack(alignment: .leading, spacing: 4) {
                Text(tr("Название фрагмента", "Snippet Title"))
                    .font(currentFont.font(size: 11, weight: .medium))
                    .foregroundStyle(currentTheme.secondaryText)
                TextField(tr("Название фрагмента", "Snippet Title"), text: $newSnippetTitle)
                    .textFieldStyle(.plain)
                    .font(currentFont.font(size: 13, weight: .medium))
                    .foregroundStyle(currentTheme.primaryText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(currentTheme.isLight ? Color.white : currentTheme.primaryText.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(currentTheme.borderColor, lineWidth: 1)
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(tr("Категория", "Category"))
                    .font(currentFont.font(size: 11, weight: .medium))
                    .foregroundStyle(currentTheme.secondaryText)
                Picker("", selection: $newSnippetCategory) {
                    Text(tr("Разработка", "Dev")).tag("Разработка")
                    Text(tr("Работа", "Work")).tag("Работа")
                    Text(tr("Поддержка", "Support")).tag("Контакты")
                    Text(tr("Шаблоны", "Templates")).tag("Шаблоны")
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(tr("Текст фрагмента...", "Snippet content..."))
                    .font(currentFont.font(size: 11, weight: .medium))
                    .foregroundStyle(currentTheme.secondaryText)

                TextEditor(text: $newSnippetContent)
                    .font(currentFont.font(size: 12, weight: .regular))
                    .foregroundStyle(currentTheme.primaryText)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(currentTheme.isLight ? Color.white : currentTheme.primaryText.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(currentTheme.borderColor, lineWidth: 1)
                    )
                    .frame(height: 110)

                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("Доступные макросы: {{date}}, {{time}}, {{datetime}}, {{clipboard}}", "Available macros: {{date}}, {{time}}, {{datetime}}, {{clipboard}}"))
                        .font(currentFont.font(size: 10, weight: .medium))
                        .foregroundStyle(currentTheme.secondaryText)

                    HStack(spacing: 6) {
                        ForEach(["{{date}}", "{{time}}", "{{datetime}}", "{{clipboard}}"], id: \.self) { macro in
                            Button {
                                newSnippetContent.append(macro)
                            } label: {
                                Text(macro)
                                    .font(.system(size: 10, design: .monospaced))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(currentTheme.primaryText.opacity(0.08))
                                    .foregroundStyle(currentTheme.primaryText)
                                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                                            .strokeBorder(currentTheme.borderColor, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                            .help(tr("Вставить макрос \(macro)", "Insert macro \(macro)"))
                        }
                    }
                }
                .padding(.top, 2)
            }

            HStack {
                Button {
                    isAddingSnippet = false
                    editingSnippet = nil
                    newSnippetTitle = ""
                    newSnippetContent = ""
                } label: {
                    Text(tr("Отмена", "Cancel"))
                }
                .pvButton(variant: .secondary, size: .regular, theme: currentTheme)
                .keyboardShortcut(.cancelAction)

                if isEditing, let editing = editingSnippet {
                    Button {
                        snippetsList.removeAll { $0.id == editing.id }
                        saveSnippets()
                        isAddingSnippet = false
                        editingSnippet = nil
                        newSnippetTitle = ""
                        newSnippetContent = ""
                        TapticSoundAndHaptics.shared.performDialTick()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                                .symbolRenderingMode(.monochrome)
                            Text(tr("Удалить", "Delete"))
                        }
                    }
                    .pvButton(variant: .destructive, size: .regular, theme: currentTheme)
                    .help(tr("Удалить этот фрагмент", "Delete this snippet"))
                }

                Spacer()

                Button {
                    if !newSnippetTitle.isEmpty && !newSnippetContent.isEmpty {
                        if let existing = editingSnippet, let idx = snippetsList.firstIndex(where: { $0.id == existing.id }) {
                            snippetsList[idx].title = newSnippetTitle
                            snippetsList[idx].category = newSnippetCategory
                            snippetsList[idx].content = newSnippetContent
                        } else {
                            let item = QuickSnippetItem(
                                title: newSnippetTitle,
                                content: newSnippetContent,
                                category: newSnippetCategory
                            )
                            snippetsList.insert(item, at: 0)
                        }
                        saveSnippets()
                        newSnippetTitle = ""
                        newSnippetContent = ""
                        isAddingSnippet = false
                        editingSnippet = nil
                    }
                } label: {
                    Text(tr("Сохранить", "Save"))
                }
                .pvButton(variant: .primary, size: .regular, theme: currentTheme)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
        .background(currentTheme.isLight ? Color.white : currentTheme.cardColor)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(currentTheme.borderColor, lineWidth: 1)
        )
        .environment(\.colorScheme, currentTheme.isLight ? .light : .dark)
        .preferredColorScheme(currentTheme.isLight ? .light : .dark)
    }

    // MARK: - Tab 3: PassGen Tab View
    private var passgenTabView: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        HStack(spacing: 6) {
                            Label(tr("Криптографический CSPRNG генератор", "Cryptographic CSPRNG Generator"), systemImage: "key.fill")
                                .font(currentFont.font(size: 14, weight: .bold))
                                .foregroundStyle(currentTheme.primaryText)

                            InfoTooltipBadge(
                                title: tr("Аппаратная криптостойкость", "Hardware Cryptographic Security"),
                                message: tr(
                                    "Пароли генерируются локально через системный криптогенератор Apple SecRandomCopyBytes. Энтропия свыше 100 бит гарантирует защиту от перебора.",
                                    "Passwords are generated locally using Apple's SecRandomCopyBytes CSPRNG. Entropy above 100 bits guarantees protection against brute-force attacks."
                                ),
                                theme: currentTheme
                            )
                        }

                        Spacer()

                        Button {
                            generatePass()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise")
                                    .symbolRenderingMode(.monochrome)
                                Text(tr("Сгенерировать", "Regenerate"))
                            }
                        }
                        .pvButton(variant: .secondary, size: .small, theme: currentTheme)
                    }

                    HStack {
                        Text(passGeneratedSecret.isEmpty ? tr("Генерация...", "Generating...") : passGeneratedSecret)
                            .font(currentFont.font(size: 15, weight: .bold))
                            .foregroundStyle(currentTheme.badgeText)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(14)
                    .liquidGlassCard(theme: currentTheme, windowOpacity: windowOpacity, cornerRadius: 10)

                    HStack {
                        Text(tr("Энтропия: \(passEntropyBits) бит", "Entropy: \(passEntropyBits) bits"))
                            .font(currentFont.font(size: 11, weight: .semibold))
                            .foregroundStyle(passEntropyBits >= 80 ? .green : .orange)

                        Spacer()
                    }

                    Divider()
                        .background(currentTheme.borderColor)

                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Button {
                                passIsMnemonic = false
                                generatePass()
                            } label: {
                                Text(tr("Символьный (CSPRNG)", "Character (CSPRNG)"))
                            }
                            .pvButton(variant: .toggle(isActive: !passIsMnemonic), size: .small, theme: currentTheme)

                            Button {
                                passIsMnemonic = true
                                generatePass()
                            } label: {
                                Text(tr("Мнемоническая фраза", "Memorable Passphrase"))
                            }
                            .pvButton(variant: .toggle(isActive: passIsMnemonic), size: .small, theme: currentTheme)
                        }

                        if !passIsMnemonic {
                            HStack {
                                Text(tr("Длина: \(Int(passLength)) символов", "Length: \(Int(passLength)) chars"))
                                    .font(currentFont.font(size: 12, weight: .regular))
                                    .foregroundStyle(currentTheme.primaryText)
                                    .frame(width: 150, alignment: .leading)

                                Slider(value: $passLength, in: 8...48, step: 1)
                                    .onChange(of: passLength) { _, _ in
                                        generatePass()
                                    }
                            }

                            HStack(spacing: 16) {
                                Toggle(tr("Спецсимволы (!@#$)", "Symbols (!@#$)"), isOn: $passIncludeSymbols)
                                    .font(currentFont.font(size: 12, weight: .regular))
                                    .foregroundStyle(currentTheme.primaryText)
                                    .onChange(of: passIncludeSymbols) { _, _ in generatePass() }

                                Toggle(tr("Цифры (0-9)", "Numbers (0-9)"), isOn: $passIncludeDigits)
                                    .font(currentFont.font(size: 12, weight: .regular))
                                    .foregroundStyle(currentTheme.primaryText)
                                    .onChange(of: passIncludeDigits) { _, _ in generatePass() }

                                Toggle(tr("Прописные (A-Z)", "Uppercase (A-Z)"), isOn: $passIncludeUppercase)
                                    .font(currentFont.font(size: 12, weight: .regular))
                                    .foregroundStyle(currentTheme.primaryText)
                                    .onChange(of: passIncludeUppercase) { _, _ in generatePass() }
                            }
                        }
                    }

                    HStack(spacing: 12) {
                        Button {
                            _ = monitor.recordGeneratedPassword(passGeneratedSecret, ttlSeconds: nil)
                            instantCopyAndPaste(text: passGeneratedSecret, ttl: nil)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "bolt.fill")
                                    .symbolRenderingMode(.monochrome)
                                Text(tr("Вставить в \(monitor.targetAppName)", "Paste into \(monitor.targetAppName)"))
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .pvButton(variant: .primary, size: .regular, theme: currentTheme)

                        Button {
                            _ = monitor.recordGeneratedPassword(passGeneratedSecret, ttlSeconds: nil)
                            passCopiedNotification = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                passCopiedNotification = false
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: passCopiedNotification ? "checkmark" : "doc.on.doc")
                                    .symbolRenderingMode(.monochrome)
                                Text(passCopiedNotification ? tr("Скопировано!", "Copied!") : tr("Скопировать", "Copy"))
                            }
                        }
                        .pvButton(variant: .secondary, size: .regular, theme: currentTheme)
                    }
                }
                .padding(20)
                .liquidGlassCard(theme: currentTheme, windowOpacity: windowOpacity, cornerRadius: 14)
            }
            .padding(20)
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: - Row Plate Helper for Clean Settings
    private func settingRowPlate<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack {
            content()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(currentTheme.isLight ? Color.black.opacity(0.035) : Color.white.opacity(0.045))
        )
    }

    // MARK: - Tab 4: Settings Tab View (Two-column Sidebar Architecture)
    private var settingsTabView: some View {
        HStack(spacing: 0) {
            // Левая колонка (Sidebar шириной 200pt)
            settingsSidebarView

            Divider()
                .background(currentTheme.borderColor)

            // Правая основная область с карточками выбранного раздела
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch selectedSettingsSection {
                    case .system:
                        systemSectionView
                    case .appearance:
                        appearanceSectionView
                    case .memory:
                        memorySectionView
                    case .blacklist:
                        blacklistSectionView
                    case .hotkeys:
                        hotkeysSectionView
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .scrollContentBackground(.hidden)
        }
    }

    // MARK: - Settings Left Sidebar Navigation (215pt)
    private var settingsSidebarView: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(SettingsSidebarSection.allCases) { section in
                let isSelected = (selectedSettingsSection == section)
                Button {
                    selectedSettingsSection = section
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: section.icon)
                            .symbolRenderingMode(.monochrome)
                            .font(.system(size: 13, weight: .semibold))

                        Text(section.title(in: currentLanguage))
                            .lineLimit(1)

                        Spacer()

                        if isSelected {
                            Image(systemName: "chevron.right")
                                .symbolRenderingMode(.monochrome)
                                .font(.system(size: 10, weight: .bold))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .pvButton(variant: .toggle(isActive: isSelected), size: .regular, theme: currentTheme)
            }

            Spacer()

            // Нижняя карточка сайдбара: единственная кнопка статуса / проверки обновлений
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    if case .updateAvailable = updateService.state {
                        updateService.showModal()
                    } else if updateService.state != .checking {
                        Task {
                            await updateService.checkForUpdates(manual: true)
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        if updateService.state == .checking {
                            // Состояние Б: Идет проверка
                            ProgressView()
                                .controlSize(.mini)
                                .scaleEffect(0.82)
                                .frame(width: 14, height: 14)
                            Text(tr("Проверка...", "Checking..."))
                                .font(currentFont.font(size: 11.5, weight: .medium))
                                .foregroundStyle(currentTheme.accentColor)
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                        } else if case .updateAvailable = updateService.state {
                            // Состояние В: Обнаружена новая версия
                            Image(systemName: "exclamationmark.circle.fill")
                                .symbolRenderingMode(.monochrome)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.orange)
                            Text(tr("Новая версия", "New Version"))
                                .font(currentFont.font(size: 11.5, weight: .semibold))
                                .foregroundStyle(Color.orange)
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                        } else {
                            // Состояние А: Обновлений нет / По умолчанию (Актуальная версия)
                            Image(systemName: "checkmark.circle.fill")
                                .symbolRenderingMode(.monochrome)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color(red: 0.16, green: 0.80, blue: 0.34))
                            Text(tr("Актуальная версия", "Up to Date"))
                                .font(currentFont.font(size: 11.5, weight: .medium))
                                .foregroundStyle(Color(red: 0.16, green: 0.80, blue: 0.34))
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                        }

                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .pvButton(variant: .secondary, size: .regular, theme: currentTheme)
                .disabled(updateService.state == .checking)
                .help(tr("Проверить наличие новой версии PasteVault на GitHub", "Check for new PasteVault version on GitHub"))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(currentTheme.primaryText.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(currentTheme.borderColor, lineWidth: 0.8)
            )
        }
        .padding(14)
        .frame(width: 215)
        .fixedSize(horizontal: true, vertical: false)
    }

    // MARK: - Section 1: System (Система)
    private var systemSectionView: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Карточка 1: Язык интерфейса
            settingsSection(
                title: tr("Язык интерфейса", "Interface Language"),
                icon: "globe"
            ) {
                settingRowPlate {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tr("Язык приложения", "Application Language"))
                                .font(currentFont.font(size: 12, weight: .regular))
                                .foregroundStyle(currentTheme.primaryText)
                            Text(tr("Выберите язык для интерфейса и подсказок", "Choose language for interface and tooltips"))
                                .font(currentFont.font(size: 11, weight: .regular))
                                .foregroundStyle(currentTheme.secondaryText)
                        }

                        Spacer()

                        HStack(spacing: 6) {
                            ForEach(AppLanguage.allCases) { lang in
                                let isSelectedLang = (currentLanguage == lang)
                                Button {
                                    appLanguageRaw = lang.rawValue
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "globe")
                                            .symbolRenderingMode(.monochrome)
                                        Text(lang.displayName)
                                        if isSelectedLang {
                                            Image(systemName: "checkmark")
                                                .symbolRenderingMode(.monochrome)
                                                .font(.system(size: 9, weight: .bold))
                                        }
                                    }
                                }
                                .pvButton(variant: .toggle(isActive: isSelectedLang), size: .small, theme: currentTheme)
                            }
                        }
                    }
                }
            }

            // Карточка 2: Системные разрешения macOS (Универсальный доступ / Accessibility)
            settingsSection(
                title: tr("Системные разрешения macOS", "macOS System Permissions"),
                icon: "slider.horizontal.3"
            ) {
                accessibilityPermissionStatusCard
            }

            // Карточка 3: Режим работы и приватность
            privacyAndCaptureSectionCard

            // Карточка 4: Автоматическое обновление (самый низ раздела «Система»)
            autoUpdateSectionCard
        }
    }

    // MARK: - Auto Update Section Card (Самый низ раздела «Система»)
    private var autoUpdateSectionCard: some View {
        settingsSection(
            title: tr("Автоматическое обновление", "Automatic Updates"),
            icon: "arrow.triangle.2.circlepath"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                settingRowPlate {
                    HStack(spacing: 12) {
                        Text(tr("Автоматически проверять обновления при запуске", "Automatically check for updates on launch"))
                            .font(currentFont.font(size: 12, weight: .regular))
                            .foregroundStyle(currentTheme.primaryText)

                        Spacer()

                        Toggle("", isOn: $autoCheckUpdates)
                            .toggleStyle(.switch)
                            .tint(currentTheme.accentColor)
                            .labelsHidden()
                            .onChange(of: autoCheckUpdates) { _, newValue in
                                updateService.autoCheckUpdates = newValue
                                TapticSoundAndHaptics.shared.performDialTick()
                            }
                    }
                }

                // Перенесенная из сайдбара строка с версией и ссылкой на репозиторий GitHub
                HStack(alignment: .center, spacing: 6) {
                    Button {
                        updateService.openProjectPage()
                    } label: {
                        HStack(alignment: .center, spacing: 6) {
                            Image(systemName: "checkmark.seal.fill")
                                .symbolRenderingMode(.monochrome)
                                .font(.system(size: 11))
                                .foregroundStyle(currentTheme.accentColor.opacity(0.85))
                                .frame(height: 16)

                            Text("PasteVault v\(updateService.currentVersion)")
                                .font(currentFont.font(size: 11.5, weight: .semibold))
                                .foregroundStyle(currentTheme.primaryText)

                            Image(systemName: "arrow.up.forward.square")
                                .symbolRenderingMode(.monochrome)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(currentTheme.secondaryText.opacity(0.75))
                                .frame(height: 16)
                        }
                    }
                    .buttonStyle(.plain)
                    .help(tr("Открыть страницу проекта PasteVault на GitHub", "Open PasteVault project page on GitHub"))
                    .onHover { hovering in
                        if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
                    }

                    Spacer()
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Privacy & Capture Mode Card
    private var privacyAndCaptureSectionCard: some View {
        settingsSection(
            title: tr("Режим работы и приватность", "Privacy & Capture Mode"),
            icon: "shield.fill"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                // Автозапуск при входе в macOS (Launch at Login)
                settingRowPlate {
                    Toggle(
                        tr("Запускать автоматически при входе в macOS", "Launch automatically at macOS login"),
                        isOn: $monitor.isLaunchAtLoginEnabled
                    )
                    .font(currentFont.font(size: 12, weight: .regular))
                    .foregroundStyle(currentTheme.primaryText)
                    .onChange(of: monitor.isLaunchAtLoginEnabled) { _, _ in
                        TapticSoundAndHaptics.shared.performDialTick()
                    }
                }

                settingRowPlate {
                    Toggle(
                        tr("Режим «Инкогнито» (приостановить перехват буфера)", "Incognito Mode (pause clipboard capture)"),
                        isOn: $monitor.isIncognitoPaused
                    )
                    .font(currentFont.font(size: 12, weight: .regular))
                    .foregroundStyle(currentTheme.primaryText)
                    .onChange(of: monitor.isIncognitoPaused) { _, _ in
                        TapticSoundAndHaptics.shared.performDialTick()
                    }
                }

                settingRowPlate {
                    Toggle(
                        tr("Тактильный звуковой отклик (Audio-Taptic)", "Taptic Audio Micro-Clicks"),
                        isOn: $tapticAudioFeedbackEnabled
                    )
                    .font(currentFont.font(size: 12, weight: .regular))
                    .foregroundStyle(currentTheme.primaryText)
                    .onChange(of: tapticAudioFeedbackEnabled) { _, _ in
                        TapticSoundAndHaptics.shared.performDialTick()
                    }
                }


                settingRowPlate {
                    HStack(spacing: 6) {
                        Label(
                            tr("Zero-Network Policy (Нулевой сетевой доступ)", "Zero-Network Policy"),
                            systemImage: "network.slash"
                        )
                        .font(currentFont.font(size: 12, weight: .semibold))
                        .foregroundStyle(currentTheme.badgeText)

                        Spacer()
                        Text(tr("Приложение выходит в сеть только для проверки обновлений на GitHub", "The app connects to the network only to check for updates on GitHub"))
                            .font(currentFont.font(size: 11, weight: .regular))
                            .foregroundStyle(currentTheme.secondaryText)
                    }
                }
            }
        }
    }

    // MARK: - Section 1: Appearance (Темы и прозрачность + Отдельная карточка шрифта)
    private var appearanceSectionView: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Карточка 1: Темы и прозрачность
            settingsSection(
                title: tr("Темы и прозрачность", "Themes & Opacity"),
                icon: "paintpalette.fill"
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    // Стеклянные темы
                    settingRowPlate {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(tr("Стеклянные темы:", "Glass Themes:"))
                                .font(currentFont.font(size: 11, weight: .semibold))
                                .foregroundStyle(currentTheme.secondaryText)

                            HStack(spacing: 8) {
                                ForEach(AppTheme.allCases.filter { $0.usesLiquidGlass }) { theme in
                                    themeOptionCard(theme: theme)
                                }
                            }
                        }
                    }

                    // Прозрачность фона окна
                    settingRowPlate {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Text(tr("Прозрачность фона окна:", "Window Background Opacity:"))
                                    .font(currentFont.font(size: 12, weight: .medium))
                                    .foregroundStyle(currentTheme.primaryText)

                                InfoTooltipBadge(
                                    title: tr("Эффект стекла", "Glass Effect"),
                                    message: tr(
                                        "Регулирует плотность подложки окна и карточек: от 0% (прозрачное стекло с реальной плотностью 0.50) до 100% (полностью плотный фон 1.00).",
                                        "Adjusts the opacity of the window and cards: from 0% (translucent glass with actual density 0.50) to 100% (solid surface 1.00)."
                                    ),
                                    theme: currentTheme
                                )

                                Spacer()
                                Text("\(Int(round(userGlassLevel * 100)))%")
                                    .font(currentFont.font(size: 11, weight: .bold))
                                    .foregroundStyle(currentTheme.badgeText)
                            }

                            Slider(value: $userGlassLevel, in: 0.0...1.0)
                                .tint(currentTheme.accentColor)

                            HStack(spacing: 8) {
                                opacityPresetButton(title: tr("0% Стекло", "0% Glass"), value: 0.0)
                                opacityPresetButton(title: tr("35% Мягкое", "35% Soft"), value: 0.35)
                                opacityPresetButton(title: tr("70% Стандарт", "70% Standard"), value: 0.70)
                                opacityPresetButton(title: tr("100% Плотный", "100% Solid"), value: 1.0)
                            }
                        }
                    }

                    // Матовые темы
                    settingRowPlate {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(tr("Матовые темы:", "Matte Themes:"))
                                .font(currentFont.font(size: 11, weight: .semibold))
                                .foregroundStyle(currentTheme.secondaryText)

                            HStack(spacing: 8) {
                                ForEach(AppTheme.allCases.filter { !$0.usesLiquidGlass }) { theme in
                                    themeOptionCard(theme: theme)
                                }
                            }
                        }
                    }
                }
            }

            // Карточка 2: Шрифт интерфейса (ОТДЕЛЬНАЯ карточка ниже через отступ 18pt)
            settingsSection(
                title: tr("Шрифт интерфейса", "Interface Font"),
                icon: "textformat",
                iconSize: 14,
                iconWeight: .bold,
                trailing: {
                    Text("\(tr("Активен:", "Active:")) \(currentFont.title)")
                        .font(currentFont.font(size: 11, weight: .bold))
                        .foregroundStyle(currentTheme.badgeText)
                }
            ) {
                customFontDropdownView
            }
        }
    }

    // MARK: - Custom Font Dropdown View
    private var customFontDropdownView: some View {
        Button {
            TapticSoundAndHaptics.shared.performDialTick()
            isFontDropdownExpanded.toggle()
        } label: {
            HStack(spacing: 8) {
                Text("Aa")
                    .font(currentFont.font(size: 13, weight: .bold))
                    .foregroundStyle(currentTheme.accentColor)
                    .frame(width: 22, alignment: .leading)

                Text("\(currentFont.title) — \(currentFont.subtitle(in: currentLanguage))")
                    .font(currentFont.font(size: 12, weight: .semibold))
                    .foregroundStyle(currentTheme.primaryText)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Image(systemName: "chevron.down")
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(currentTheme.secondaryText)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isFontButtonHovered ? currentTheme.accentColor.opacity(0.14) : currentTheme.cardColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isFontButtonHovered ? currentTheme.accentColor.opacity(0.55) : currentTheme.borderColor, lineWidth: 1)
            )
            .animation(.easeOut(duration: 0.12), value: isFontButtonHovered)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .onHover { hovering in
                isFontButtonHovered = hovering
                if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
            }
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isFontDropdownExpanded, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(AppFont.allCases) { fontOption in
                    let isSelected = (currentFont == fontOption)
                    CustomDropdownItemRow(
                        title: "\(fontOption.title) — \(fontOption.subtitle(in: currentLanguage))",
                        icon: "textformat",
                        isSelected: isSelected,
                        currentTheme: currentTheme,
                        currentFont: fontOption
                    ) {
                        selectedFontId = fontOption.rawValue
                        FontManager.shared.ensureFontsInstalled()
                        isFontDropdownExpanded = false
                    }
                }
            }
            .padding(6)
            .frame(minWidth: 280)
            .background(currentTheme.cardColor)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(currentTheme.borderColor, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 3)
            .environment(\.colorScheme, currentTheme.isLight ? .light : .dark)
        }
    }

    // MARK: - Section 3: Memory (Память и лимиты)
    private var memorySectionView: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsSection(
                title: tr("Хранение и типы данных", "Storage & Content Types"),
                icon: "memorychip"
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    // Плашка: Сохранять:
                    settingRowPlate {
                        HStack(alignment: .center, spacing: 10) {
                            Text(tr("Сохранять:", "Save:"))
                                .font(currentFont.font(size: 12, weight: .semibold))
                                .foregroundStyle(currentTheme.primaryText)
                                .frame(width: 105, alignment: .leading)

                            HStack(spacing: 8) {
                                capsuleTypeToggle(
                                    title: tr("Файлы", "Files"),
                                    icon: "doc.fill",
                                    isOn: $monitor.saveFilesEnabled
                                )

                                capsuleTypeToggle(
                                    title: tr("Изображения", "Images"),
                                    icon: "photo.fill",
                                    isOn: $monitor.saveImagesEnabled
                                )

                                capsuleTypeToggle(
                                    title: tr("Текст", "Text"),
                                    icon: "text.alignleft",
                                    isOn: $monitor.saveTextEnabled
                                )
                            }
                            Spacer()
                        }
                    }

                    // Плашка: Лимит записей:
                    settingRowPlate {
                        HStack(alignment: .center, spacing: 10) {
                            Text(tr("Лимит записей:", "History limit:"))
                                .font(currentFont.font(size: 12, weight: .semibold))
                                .foregroundStyle(currentTheme.primaryText)
                                .frame(width: 105, alignment: .leading)

                            HStack(spacing: 6) {
                                ForEach([100, 250, 500, 1000], id: \.self) { limit in
                                    let isSelected = (monitor.maxHistoryLimit == limit)
                                    Button {
                                        monitor.maxHistoryLimit = limit
                                        monitor.enforceHistoryLimit()
                                    } label: {
                                        Text("\(limit)")
                                    }
                                    .pvButton(variant: .toggle(isActive: isSelected), size: .small, theme: currentTheme)
                                }
                            }

                            Spacer()

                            HStack(spacing: 5) {
                                Image(systemName: "cylinder.split.1x2")
                                    .symbolRenderingMode(.monochrome)
                                    .font(.system(size: 11))
                                    .foregroundStyle(currentTheme.accentColor)
                                Text(
                                    tr(
                                        "Записей: \(monitor.items.count) из \(monitor.maxHistoryLimit) · Занято: \(monitor.formattedStorageSize)",
                                        "Items: \(monitor.items.count) of \(monitor.maxHistoryLimit) · Used: \(monitor.formattedStorageSize)"
                                    )
                                )
                                .font(currentFont.font(size: 11, weight: .semibold))
                                .foregroundStyle(currentTheme.primaryText.opacity(0.9))
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4.5)
                            .liquidGlassCard(theme: currentTheme, windowOpacity: windowOpacity, cornerRadius: 6)
                        }
                    }

                    // Плашка: Очистка истории
                    settingRowPlate {
                        HStack(alignment: .center) {
                            Button {
                                showClearHistoryConfirmation = true
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "trash")
                                        .symbolRenderingMode(.monochrome)
                                    Text(tr("Очистить всю историю буфера", "Clear All Clipboard History"))
                                }
                            }
                            .pvButton(variant: .secondary, size: .small, theme: currentTheme)

                            Spacer()

                            InfoTooltipBadge(
                                title: tr("Хранилище базы данных", "Database Storage"),
                                message: tr(
                                    "База данных хранится локально в ~/Library/Application Support/PasteVault в зашифрованном виде. При очистке выполняется сжатие VACUUM.",
                                    "Database is stored locally in ~/Library/Application Support/PasteVault. Clearing history performs SQLite VACUUM compaction."
                                ),
                                theme: currentTheme
                            )
                        }
                    }
                }
            }

            // Новая карточка: Резервное копирование и перенос данных
            settingsSection(
                title: tr("Резервное копирование и перенос данных", "Backup & Data Transfer"),
                icon: "externaldrive.badge.timemachine"
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    settingRowPlate {
                        HStack(alignment: .center, spacing: 14) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(tr("Сохранение и перенос", "Export & Import"))
                                    .font(currentFont.font(size: 12.5, weight: .semibold))
                                    .foregroundStyle(currentTheme.primaryText)
                                Text(tr(
                                    "Сохранение и восстановление истории буфера, быстрых фрагментов и настроек в файл.",
                                    "Export and restore clipboard history, snippets, and settings to a local file."
                                ))
                                .font(currentFont.font(size: 11, weight: .regular))
                                .foregroundStyle(currentTheme.secondaryText)
                            }

                            Spacer()

                            HStack(spacing: 8) {
                                Button {
                                    ClipboardMonitor.shared.isModalOverlayActive = true
                                    showExportModal = true
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: "arrow.up.doc")
                                            .symbolRenderingMode(.monochrome)
                                        Text(tr("↑ Экспорт...", "↑ Export..."))
                                    }
                                }
                                .pvButton(variant: .secondary, size: .small, theme: currentTheme)

                                Button {
                                    openImportFilePicker()
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: "arrow.down.doc")
                                            .symbolRenderingMode(.monochrome)
                                        Text(tr("↓ Импорт...", "↓ Import..."))
                                    }
                                }
                                .pvButton(variant: .secondary, size: .small, theme: currentTheme)
                            }
                        }
                    }

                    if let toast = backupToastMessage {
                        HStack(spacing: 8) {
                            Image(systemName: backupToastIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                                .symbolRenderingMode(.monochrome)
                                .foregroundStyle(backupToastIsError ? Color.red : Color.green)
                            Text(toast)
                                .font(currentFont.font(size: 11.5, weight: .medium))
                                .foregroundStyle(currentTheme.primaryText)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill((backupToastIsError ? Color.red : Color.green).opacity(0.12))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder((backupToastIsError ? Color.red : Color.green).opacity(0.3), lineWidth: 1)
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    }
                }
            }
        }
    }

    private struct BlacklistMenuTriggerPlate: View {
        let title: String
        let theme: AppTheme
        let font: AppFont
        @State private var isHovered: Bool = false

        var body: some View {
            HStack(spacing: 7) {
                Image(systemName: "plus.square.on.square")
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.primaryText)

                Text(title)
                    .font(font.font(size: 11.5, weight: .medium))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)

                Spacer(minLength: 6)

                Image(systemName: "chevron.down")
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(theme.secondaryText)
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovered ? theme.accentColor.opacity(0.14) : theme.cardColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isHovered ? theme.accentColor.opacity(0.55) : theme.borderColor, lineWidth: 1)
            )
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .onHover { hovering in
                isHovered = hovering
                if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
            }
        }
    }

    private struct RunningAppDropdownRow: View {
        let name: String
        let icon: NSImage?
        let currentTheme: AppTheme
        let currentFont: AppFont
        let action: () -> Void

        @State private var isHovered: Bool = false

        var body: some View {
            Button(action: action) {
                HStack(spacing: 8) {
                    if let icon = icon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "app")
                            .symbolRenderingMode(.monochrome)
                            .font(.system(size: 12))
                            .foregroundStyle(currentTheme.primaryText)
                            .frame(width: 16, height: 16)
                    }

                    Text(name)
                        .font(currentFont.font(size: 12, weight: .medium))
                        .foregroundStyle(currentTheme.primaryText)
                        .lineLimit(1)

                    Spacer(minLength: 8)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isHovered ? currentTheme.accentColor.opacity(0.16) : Color.clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .animation(.easeOut(duration: 0.12), value: isHovered)
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isHovered = hovering
                if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
            }
        }
    }

    // MARK: - Section 4: Blacklist (Чёрный список приложений)
    private var blacklistSectionView: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsSection(
                title: tr("Игнорируемые приложения: \(monitor.blacklistedBundleIDs.count)", "Ignored Applications: \(monitor.blacklistedBundleIDs.count)"),
                icon: "hand.raised.fill",
                trailing: {
                    Button {
                        monitor.resetBlacklistedAppsToDefaults()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.counterclockwise")
                                .symbolRenderingMode(.monochrome)
                            Text(tr("Вернуть стандартные", "Reset Defaults"))
                        }
                    }
                    .pvButton(variant: .secondary, size: .small, theme: currentTheme)
                }
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    // Список добавленных приложений
                    VStack(spacing: 6) {
                        ForEach(monitor.blacklistedBundleIDs, id: \.self) { bundleId in
                            let info = appDisplayInfo(for: bundleId)
                            settingRowPlate {
                                HStack(spacing: 8) {
                                    if let icon = info.icon {
                                        Image(nsImage: icon)
                                            .resizable()
                                            .frame(width: 16, height: 16)
                                    } else {
                                        Image(systemName: "lock.shield.fill")
                                            .symbolRenderingMode(.monochrome)
                                            .font(.system(size: 12))
                                            .foregroundStyle(currentTheme.primaryText)
                                    }

                                    HStack(spacing: 6) {
                                        Text(info.name)
                                            .font(currentFont.font(size: 11, weight: .semibold))
                                            .foregroundStyle(currentTheme.primaryText)
                                        if info.name != bundleId {
                                            Text("(\(bundleId))")
                                                .font(.system(size: 10, weight: .regular, design: .monospaced))
                                                .foregroundStyle(currentTheme.secondaryText)
                                        }
                                    }

                                    Spacer()

                                    Button {
                                        monitor.removeBlacklistedApp(bundleID: bundleId)
                                    } label: {
                                        Image(systemName: "xmark")
                                            .symbolRenderingMode(.monochrome)
                                    }
                                    .pvButton(variant: .secondary, size: .small, theme: currentTheme)
                                }
                            }
                        }
                    }

                    // Кнопки добавления
                    HStack(spacing: 10) {
                        Button {
                            isRunningAppsDropdownPresented.toggle()
                        } label: {
                            BlacklistMenuTriggerPlate(
                                title: tr("Из открытых приложений", "From Running Apps"),
                                theme: currentTheme,
                                font: currentFont
                            )
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $isRunningAppsDropdownPresented, arrowEdge: .bottom) {
                            let running = NSWorkspace.shared.runningApplications
                                .filter { $0.activationPolicy == .regular }
                                .filter { app in
                                    guard let bid = app.bundleIdentifier else { return false }
                                    return !monitor.isAppBlacklisted(bid) && bid != Bundle.main.bundleIdentifier
                                }

                            VStack(alignment: .leading, spacing: 2) {
                                if running.isEmpty {
                                    Text(tr("Все открытые приложения уже в списке", "All open applications already in blacklist"))
                                        .font(currentFont.font(size: 11, weight: .regular))
                                        .foregroundStyle(currentTheme.secondaryText)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 8)
                                } else {
                                    ForEach(running, id: \.processIdentifier) { app in
                                        if let bid = app.bundleIdentifier {
                                            RunningAppDropdownRow(
                                                name: app.localizedName ?? bid,
                                                icon: app.icon,
                                                currentTheme: currentTheme,
                                                currentFont: currentFont
                                            ) {
                                                monitor.addBlacklistedApp(bundleID: bid)
                                                isRunningAppsDropdownPresented = false
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(6)
                            .frame(minWidth: 240)
                            .background(currentTheme.cardColor)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(currentTheme.borderColor, lineWidth: 1)
                            )
                            .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 3)
                            .environment(\.colorScheme, currentTheme.isLight ? .light : .dark)
                        }

                        Button {
                            selectAppFromApplicationsFolder()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "folder.badge.plus")
                                    .symbolRenderingMode(.monochrome)
                                    .font(.system(size: 12, weight: .medium))
                                Text(tr("Выбрать в Программах...", "Choose in Applications..."))
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(PVButtonStyle(variant: .secondary, size: .small, theme: currentTheme, fixedHeight: 32))
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    // MARK: - Section 5: Hotkeys (Горячие клавиши)
    private var hotkeysSectionView: some View {
        VStack(alignment: .leading, spacing: 18) {
            shortcutsConfigurationSection
        }
    }

    private struct CapsuleTypeToggleButton: View {
        let title: String
        let icon: String
        @Binding var isOn: Bool
        let currentTheme: AppTheme
        let currentFont: AppFont

        var body: some View {
            Button {
                isOn.toggle()
            } label: {
                HStack(spacing: 5) {
                    if isOn {
                        Image(systemName: "checkmark")
                            .symbolRenderingMode(.monochrome)
                            .font(.system(size: 10, weight: .bold))
                    }
                    Image(systemName: icon)
                        .symbolRenderingMode(.monochrome)
                        .font(.system(size: 11))
                    Text(title)
                }
            }
            .pvButton(variant: .toggle(isActive: isOn), size: .small, theme: currentTheme)
        }
    }

    private func capsuleTypeToggle(title: String, icon: String, isOn: Binding<Bool>) -> some View {
        CapsuleTypeToggleButton(
            title: title,
            icon: icon,
            isOn: isOn,
            currentTheme: currentTheme,
            currentFont: currentFont
        )
    }

    private func themeOptionCard(theme: AppTheme) -> some View {
        let isSelected = (currentTheme == theme)
        let isHovered = (hoveredThemeId == theme.rawValue)

        return Button {
            TapticSoundAndHaptics.shared.performDialTick()
            selectedThemeId = theme.rawValue
            UserDefaults.standard.set(theme.rawValue, forKey: "selectedThemeId")
            UserDefaults.standard.set(theme.rawValue, forKey: "pasteVaultTheme")
            NSApp.windows.first(where: { $0 is NSPanel })?.appearance = NSAppearance(named: theme.isLight ? .aqua : .darkAqua)
        } label: {
            VStack(spacing: 5) {
                HStack(spacing: -6) {
                    Circle()
                        .fill(theme.backgroundColor)
                        .frame(width: 18, height: 18)
                        .overlay(Circle().stroke(Color.primary.opacity(0.20), lineWidth: 1))
                        .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                    Circle()
                        .fill(theme.accentColor)
                        .frame(width: 18, height: 18)
                        .overlay(Circle().stroke(Color.primary.opacity(0.20), lineWidth: 1))
                        .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                }
                Text(theme.title(in: currentLanguage))
                    .font(currentFont.font(size: 11, weight: isSelected ? .bold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .foregroundStyle(currentTheme.primaryText)

                Text(theme.usesLiquidGlass ? tr("Стекло", "Glass") : tr("Матовая", "Solid"))
                    .font(currentFont.font(size: 9, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(theme.usesLiquidGlass ? currentTheme.badgeFill : currentTheme.accentColor.opacity(0.22))
                    .foregroundStyle(currentTheme.badgeText)
                    .clipShape(Capsule())
            }
            .frame(maxWidth: .infinity, minHeight: 86, maxHeight: 86)
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        isSelected
                            ? theme.accentColor.opacity(0.18)
                            : (isHovered ? theme.accentColor.opacity(0.10) : currentTheme.primaryText.opacity(0.05))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? theme.accentColor
                            : (isHovered ? theme.accentColor.opacity(0.50) : currentTheme.primaryText.opacity(0.14)),
                        lineWidth: isSelected ? 2 : (isHovered ? 1.5 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredThemeId = hovering ? theme.rawValue : nil
            if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
    }

    private func opacityPresetButton(title: String, value: Double) -> some View {
        let isCurrent = abs(userGlassLevel - value) < 0.03

        return Button {
            userGlassLevel = value
        } label: {
            Text(title)
                .frame(maxWidth: .infinity)
        }
        .pvButton(variant: .toggle(isActive: isCurrent), size: .small, theme: currentTheme)
    }

    private struct AppDisplayInfo {
        let name: String
        let icon: NSImage?
    }

    private func appDisplayInfo(for bundleID: String) -> AppDisplayInfo {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let name = FileManager.default.displayName(atPath: appURL.path)
            let icon = NSWorkspace.shared.icon(forFile: appURL.path)
            return AppDisplayInfo(name: name, icon: icon)
        }
        switch bundleID.lowercased() {
        case "com.apple.keychainaccess":
            return AppDisplayInfo(name: tr("Связка ключей", "Keychain Access"), icon: nil)
        case "com.1password.1password", "com.agilebits.onepassword7":
            return AppDisplayInfo(name: "1Password", icon: nil)
        case "com.bitwarden.desktop":
            return AppDisplayInfo(name: "Bitwarden", icon: nil)
        case "org.keepassxc.keepassxc":
            return AppDisplayInfo(name: "KeePassXC", icon: nil)
        default:
            return AppDisplayInfo(name: bundleID, icon: nil)
        }
    }

    private func selectAppFromApplicationsFolder() {
        guard let hostWindow = NSApp.windows.first(where: { $0.isVisible && ($0 is NSPanel || $0.className.contains("FloatingPanel")) }) ?? NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }) else { return }

        ClipboardMonitor.shared.isModalOverlayActive = true
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle, .application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = tr("Выбрать", "Select")
        panel.message = tr("Выберите приложение для добавления в Чёрный список", "Choose an application to blacklist")

        let targetLevel = NSWindow.Level(rawValue: max(Int(CGWindowLevelForKey(.popUpMenuWindow)), hostWindow.level.rawValue) + 2)
        panel.level = targetLevel

        let handleResponse: (NSApplication.ModalResponse) -> Void = { response in
            ClipboardMonitor.shared.isModalOverlayActive = false
            hostWindow.makeKeyAndOrderFront(nil)
            if response == .OK, let selectedURL = panel.url {
                if let bundle = Bundle(url: selectedURL), let bid = bundle.bundleIdentifier {
                    self.monitor.addBlacklistedApp(bundleID: bid)
                }
            }
        }

        if hostWindow.attachedSheet == nil {
            panel.beginSheetModal(for: hostWindow, completionHandler: handleResponse)
        } else {
            let response = panel.runModal()
            handleResponse(response)
        }
    }

    // MARK: - Shortcuts Configuration Section (Collapsible Accordion)
    private var shortcutsConfigurationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Компактная кликабельная шапка (в стиле выбора шрифта)
            Button {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    isShortcutsExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "keyboard.fill")
                        .symbolRenderingMode(.monochrome)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(currentTheme.accentColor)

                    Text(tr("Горячие клавиши приложения", "Application Keyboard Shortcuts"))
                        .font(currentFont.font(size: 12, weight: .bold))
                        .foregroundStyle(currentTheme.primaryText)

                    Spacer(minLength: 8)

                    if isShortcutsExpanded {
                        Button {
                            var transaction = Transaction()
                            transaction.disablesAnimations = true
                            withTransaction(transaction) {
                                shortcutManager.resetToDefaults()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.counterclockwise")
                                    .symbolRenderingMode(.monochrome)
                                    .font(.system(size: 10, weight: .bold))
                                Text(tr("Сбросить", "Reset"))
                            }
                        }
                        .pvButton(variant: .secondary, size: .small, theme: currentTheme)
                        .help(tr("Сбросить все комбинации клавиш к стандартным", "Reset all shortcuts to defaults"))
                    }

                    Image(systemName: "chevron.down")
                        .symbolRenderingMode(.monochrome)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(currentTheme.secondaryText)
                        .rotationEffect(.degrees(isShortcutsExpanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
            }

            // Развернутый список ровно из 11 клавиш (мгновенно без лагов ScrollView)
            if isShortcutsExpanded {
                VStack(spacing: 6) {
                    ForEach(ShortcutCommand.allCases) { command in
                        shortcutRow(command: command)
                    }
                }
                .padding(.trailing, 2)
                .clipped()
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassCard(theme: currentTheme, windowOpacity: windowOpacity, cornerRadius: 14)
    }

    private func shortcutRow(command: ShortcutCommand) -> some View {
        let combo = shortcutManager.config[command]
        let isRecordingThis = shortcutManager.recordingCommand == command
        let validation = (shortcutManager.validationFeedback?.command == command) ? shortcutManager.validationFeedback?.result : nil

        return HStack(spacing: 8) {
            // Название команды
            Text(command.title(in: currentLanguage))
                .font(currentFont.font(size: 11, weight: .medium))
                .foregroundStyle(currentTheme.primaryText)
                .lineLimit(1)

            // Индикация конфликта
            if let validation, validation != .valid {
                HStack(spacing: 3) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .symbolRenderingMode(.monochrome)
                        .font(.system(size: 9))
                    Text(validation.message(in: currentLanguage))
                        .font(currentFont.font(size: 10, weight: .semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(currentTheme.primaryText)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(currentTheme.primaryText.opacity(0.08))
                .clipShape(Capsule())
                .help(validation.message(in: currentLanguage))
            }

            Spacer(minLength: 8)

            // 1. Чистый аккуратный бейдж текущей установленной комбинации (без Menu и без стрелочек)
            Text(combo.displayString)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(currentTheme.primaryText)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .liquidGlassCard(theme: currentTheme, windowOpacity: windowOpacity, cornerRadius: 6)
                .fixedSize()

            // 2. Интерактивная кнопка [ Задать ] (при записи: ● [ Нажмите клавиши... ])
            Button {
                if isRecordingThis {
                    shortcutManager.stopRecording()
                } else {
                    shortcutManager.startRecording(for: command)
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: isRecordingThis ? "circle.fill" : "record.circle")
                        .symbolRenderingMode(.monochrome)
                        .font(.system(size: 10, weight: .semibold))
                    Text(isRecordingThis ? tr("Нажмите клавиши...", "Press keys...") : tr("Задать", "Record"))
                }
            }
            .pvButton(variant: .toggle(isActive: isRecordingThis), size: .small, theme: currentTheme)
            .help(isRecordingThis ? tr("Нажмите любое сочетание клавиш или Esc для отмены", "Press any key combo or Esc to cancel") : tr("Записать новое сочетание клавиш для этой команды", "Record a new shortcut combo for this command"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .liquidGlassCard(theme: currentTheme, windowOpacity: windowOpacity, cornerRadius: 8)
    }

    private func settingsSection<Content: View, Trailing: View>(
        title: String,
        icon: String,
        iconSize: CGFloat = 12,
        iconWeight: Font.Weight = .regular,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: iconSize, weight: iconWeight))
                    .foregroundStyle(currentTheme.badgeText)
                Text(title)
                    .font(currentFont.font(size: 12, weight: .bold))
                    .foregroundStyle(currentTheme.primaryText)
                Spacer()
                trailing()
            }
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassCard(theme: currentTheme, windowOpacity: windowOpacity, cornerRadius: 14)
    }

    private func settingsSection<Content: View>(
        title: String,
        icon: String,
        iconSize: CGFloat = 12,
        iconWeight: Font.Weight = .regular,
        @ViewBuilder content: () -> Content
    ) -> some View {
        settingsSection(title: title, icon: icon, iconSize: iconSize, iconWeight: iconWeight, trailing: { EmptyView() }, content: content)
    }

    // MARK: - Bottom Status Bar
    private var bottomStatusBar: some View {
        HStack(spacing: 10) {
            hotkeyHint(key: shortcutManager.config.togglePanel.displayString, label: tr("Открыть", "Toggle"))
            hotkeyHint(key: "↑↓", label: tr("Навигация", "Navigate"))
            hotkeyHint(key: shortcutManager.config.pasteSelected.displayString, label: tr("Вставить в \(shortTargetAppName)", "Paste into \(shortTargetAppName)"))
            hotkeyHint(key: shortcutManager.config.quickPasteModifier.displayString, label: tr("Быстрый выбор", "Quick Paste"))
            hotkeyHint(key: "Esc", label: tr("Закрыть", "Close"))

            Spacer(minLength: 6)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "power")
                        .symbolRenderingMode(.monochrome)
                    Text(tr("Выход", "Quit"))
                }
            }
            .pvButton(variant: .secondary, size: .small, theme: currentTheme)
            .keyboardShortcut("q", modifiers: [.command])
            .help(tr("Полностью закрыть PasteVault (⌘Q)", "Quit PasteVault completely (⌘Q)"))
        }
        .lineLimit(1)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(
            ZStack {
                WindowDragHandle()
                if currentTheme.usesLiquidGlass {
                    // Нижний стеклянный рефлекс подвала
                    LinearGradient(
                        colors: [
                            Color.clear,
                            currentTheme.accentColor.opacity(0.06 * (0.25 + windowOpacity * 0.75)),
                            Color.white.opacity((currentTheme.isLight ? 0.35 : 0.10) * (0.25 + windowOpacity * 0.75))
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .allowsHitTesting(false)
                }
            }
        )
    }

    /// Укороченное имя целевого приложения для однострочного подвала
    private var shortTargetAppName: String {
        let name = monitor.targetAppName
        return name.count > 14 ? String(name.prefix(13)) + "…" : name
    }

    private func hotkeyHint(key: String, label: String, keyFontSize: CGFloat = 9) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: keyFontSize, weight: .bold, design: .monospaced))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, keyFontSize >= 12 ? 6 : 5)
                .padding(.vertical, 2)
                .foregroundStyle(currentTheme.primaryText)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(currentTheme.isLight ? Color.black.opacity(0.10) : Color.white.opacity(0.14))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(currentTheme.primaryText.opacity(currentTheme.isLight ? 0.18 : 0.16), lineWidth: 0.8)
                )
            Text(label)
                .font(currentFont.font(size: 10, weight: .medium))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(currentTheme.secondaryText)
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    // MARK: - Helpers
    private func syncWindowAppearance() {
        let appearance = NSAppearance(named: currentTheme.isLight ? .aqua : .darkAqua)
        for window in NSApp.windows where window is NSPanel {
            window.appearance = appearance
        }
    }

    private func moveSelection(delta: Int) {
        let list = filteredItems
        guard !list.isEmpty else { return }
        let targetId: String?
        if let currentId = selectedItemId,
           let idx = list.firstIndex(where: { $0.id == currentId }) {
            let nextIdx = max(0, min(list.count - 1, idx + delta))
            targetId = list[nextIdx].id
        } else {
            targetId = list.first?.id
        }
        if let targetId {
            selectCardImmediately(targetId)
            keyboardScrollTargetId = targetId
        }
    }

    private func categoryCount(for category: FilterCategory) -> Int {
        switch category {
        case .all: return activeItemsList.count
        case .pinned: return activeItemsList.filter { $0.isPinned }.count
        case .text: return activeItemsList.filter { $0.effectiveContentType == .text && !$0.isSensitive }.count
        case .file: return activeItemsList.filter { $0.effectiveContentType == .file }.count
        case .url: return activeItemsList.filter { $0.effectiveContentType == .url }.count
        case .code: return activeItemsList.filter { $0.effectiveContentType == .code }.count
        case .image: return activeItemsList.filter { $0.effectiveContentType == .image }.count
        case .secret: return activeItemsList.filter { $0.isSensitive || $0.effectiveContentType == .secret }.count
        case .color: return activeItemsList.filter { $0.effectiveContentType == .color }.count
        }
    }

    private func filterSelectionCount(_ selection: ClipboardFilterSelection) -> Int {
        switch selection {
        case .category(let cat):
            return categoryCount(for: cat)
        case .tag(let tagName):
            return activeItemsList.filter { $0.tags.contains(tagName) }.count
        }
    }

    private func iconName(for item: ClipboardItemRow) -> String {
        switch item.effectiveContentType {
        case .file: return "doc.fill"
        case .url: return "link"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .image: return "photo"
        case .secret: return "key.fill"
        case .color: return "paintpalette.fill"
        case .text: return "text.alignleft"
        }
    }

    private func displaySourceAppName(_ name: String?) -> String {
        guard let name = name, !name.isEmpty else {
            return tr("Системный буфер", "System Clipboard")
        }
        if name == "Paste Vault (PassGen)" {
            return "PasteVault (PassGen)"
        }
        if name == "Paste Vault" {
            return "PasteVault"
        }
        return name
    }

    private func formatTimestamp(_ timestamp: Int64) -> String {
        let now = Int64(Date().timeIntervalSince1970)
        let elapsed = max(0, now - timestamp)
        if elapsed < 5 {
            return tr("только что", "just now")
        } else if elapsed < 60 {
            return tr("\(elapsed) сек. назад", "\(elapsed)s ago")
        } else if elapsed < 3600 {
            let mins = elapsed / 60
            return tr("\(mins) мин. назад", "\(mins)m ago")
        } else if elapsed < 86400 {
            let hours = elapsed / 3600
            return tr("\(hours) ч. назад", "\(hours)h ago")
        } else {
            let days = elapsed / 86400
            return tr("\(days) дн. назад", "\(days)d ago")
        }
    }

    private func stripUTMParameters(from item: ClipboardItemRow) {
        let trimmed = item.textPreview.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed) else { return }
        let blockedPrefixes = ["utm_", "fbclid", "gclid", "yclid", "mc_cid", "mc_eid", "_ga"]
        if let queryItems = components.queryItems {
            let filtered = queryItems.filter { q in
                let lower = q.name.lowercased()
                return !blockedPrefixes.contains(where: { lower.hasPrefix($0) })
            }
            components.queryItems = filtered.isEmpty ? nil : filtered
        }
        guard let cleanedURL = components.url?.absoluteString else { return }
        if let idx = monitor.items.firstIndex(where: { $0.id == item.id }) {
            monitor.items[idx] = ClipboardItemRow(
                id: item.id,
                rowid: item.rowid,
                contentType: item.contentType,
                textPreview: cleanedURL,
                contentHash: item.contentHash,
                sourceBundleId: item.sourceBundleId,
                sourceAppName: item.sourceAppName,
                isSensitive: item.isSensitive,
                secretKind: item.secretKind,
                isPinned: item.isPinned,
                createdAt: item.createdAt,
                expiresAt: item.expiresAt,
                ocrText: item.ocrText,
                rawImageData: item.rawImageData,
                fileURLPath: item.fileURLPath,
                useCount: item.useCount
            )
            monitor.copyToPasteboardImmediately(text: cleanedURL)
        }
    }

    private func transformJSON(for item: ClipboardItemRow, pretty: Bool) {
        guard let data = item.textPreview.data(using: .utf8),
              let jsonObj = try? JSONSerialization.jsonObject(with: data, options: []),
              let outData = try? JSONSerialization.data(
                  withJSONObject: jsonObj,
                  options: pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
              ),
              let outString = String(data: outData, encoding: .utf8) else {
            return
        }
        monitor.updateItemText(id: item.id, newText: outString)
        monitor.copyToPasteboardImmediately(text: outString)
    }

    private func colorFormatChip(for item: ClipboardItemRow, format: String, value: String) -> some View {
        let trimmedCurrent = item.textPreview.trimmingCharacters(in: .whitespacesAndNewlines)
        let isActive: Bool = {
            if trimmedCurrent.caseInsensitiveCompare(value) == .orderedSame { return true }
            if format == "HEX" && trimmedCurrent.hasPrefix("#") { return true }
            if format == "RGB" && trimmedCurrent.lowercased().hasPrefix("rgb") { return true }
            if format == "HSL" && trimmedCurrent.lowercased().hasPrefix("hsl") { return true }
            return false
        }()
        let chipKey = "\(item.id)_\(format)"
        let isCopied = (copiedColorChip == chipKey)

        return Button {
            TapticSoundAndHaptics.shared.performDialTick()
            monitor.selectColorFormat(for: item.id, newText: value)
            withAnimation(.easeInOut(duration: 0.15)) {
                copiedColorChip = chipKey
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                if copiedColorChip == chipKey {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        copiedColorChip = nil
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isCopied ? "checkmark" : (isActive ? "checkmark.circle.fill" : "doc.on.doc"))
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: 9, weight: (isCopied || isActive) ? .bold : .medium))
                Text(isCopied ? tr("✓ \(format)", "✓ \(format)") : "\(format): \(value)")
                    .font(currentFont.font(size: 11, weight: (isCopied || isActive) ? .semibold : .medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isCopied ? currentTheme.accentColor.opacity(0.24) : (isActive ? currentTheme.accentColor.opacity(0.14) : currentTheme.primaryText.opacity(0.08)))
            )
            .foregroundStyle((isCopied || isActive) ? currentTheme.accentColor : currentTheme.primaryText)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder((isCopied || isActive) ? currentTheme.accentColor : currentTheme.borderColor, lineWidth: (isCopied || isActive) ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .help(tr("Выбрать и скопировать формат \(format)", "Select and copy \(format) format"))
    }

    public static func localizedSnippetCategory(_ category: String, lang: AppLanguage = .ru) -> String {
        switch category {
        case "Разработка", "Dev": return PasteVault.tr("Разработка", "Dev", lang: lang)
        case "Работа", "Work": return PasteVault.tr("Работа", "Work", lang: lang)
        case "Контакты", "Поддержка", "Support": return PasteVault.tr("Поддержка", "Support", lang: lang)
        case "Шаблоны", "Templates": return PasteVault.tr("Шаблоны", "Templates", lang: lang)
        default: return category
        }
    }

    public static func localizedSnippetTitle(_ title: String, lang: AppLanguage = .ru) -> String {
        switch title {
        case "Рабочая подпись": return PasteVault.tr("Рабочая подпись", "Work Signature", lang: lang)
        case "Приветствие техподдержки": return PasteVault.tr("Приветствие техподдержки", "Support Greeting", lang: lang)
        default: return title
        }
    }

    public static func localizedSnippetContent(_ content: String, lang: AppLanguage = .ru) -> String {
        if content == "С уважением,\nКоманда разработки PasteVault\nhttps://pastevault.app" || content == "С уважением,\nКоманда разработки Paste Vault\nhttps://pastevault.app" {
            return PasteVault.tr(
                "С уважением,\nКоманда разработки PasteVault\nhttps://pastevault.app",
                "Best regards,\nPasteVault Engineering Team\nhttps://pastevault.app",
                lang: lang
            )
        } else if content == "Здравствуйте! Спасибо за обращение. Мы уже изучаем ваш вопрос и вернемся с ответом в ближайшее время." {
            return PasteVault.tr(
                "Здравствуйте! Спасибо за обращение. Мы уже изучаем ваш вопрос и вернемся с ответом в ближайшее время.",
                "Hello! Thank you for reaching out. We are reviewing your request and will get back to you shortly.",
                lang: lang
            )
        }
        return content
    }

    private func localizedSnippetCategory(_ category: String) -> String {
        Self.localizedSnippetCategory(category, lang: currentLanguage)
    }

    private func localizedSnippetTitle(_ title: String) -> String {
        Self.localizedSnippetTitle(title, lang: currentLanguage)
    }

    private func localizedSnippetContent(_ content: String) -> String {
        Self.localizedSnippetContent(content, lang: currentLanguage)
    }

    private func expandSnippetMacros(_ text: String) -> String {
        guard text.contains("{{") else { return text }
        let now = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd.MM.yyyy"
        let dateStr = dateFormatter.string(from: now)

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        let timeStr = timeFormatter.string(from: now)

        let dateTimeFormatter = DateFormatter()
        dateTimeFormatter.dateFormat = "dd.MM.yyyy HH:mm"
        let dateTimeStr = dateTimeFormatter.string(from: now)

        let clipboardStr = NSPasteboard.general.string(forType: .string) ?? ""

        var expanded = text
        expanded = expanded.replacingOccurrences(of: "{{date}}", with: dateStr)
        expanded = expanded.replacingOccurrences(of: "{{time}}", with: timeStr)
        expanded = expanded.replacingOccurrences(of: "{{datetime}}", with: dateTimeStr)
        expanded = expanded.replacingOccurrences(of: "{{clipboard}}", with: clipboardStr)
        return expanded
    }

    private func prepareSnippetForAction(_ snippet: QuickSnippetItem) -> String {
        let localized = localizedSnippetContent(snippet.content)
        return expandSnippetMacros(localized)
    }

    private func instantCopyAndPaste(text: String, ttl: TimeInterval? = nil) {
        if monitor.checkAccessibilityPermission() {
            isPasteBlockedToastVisible = false
        }
        monitor.pasteIntoTargetApp(text: text, selfDestructAfterSeconds: ttl)
    }

    private func pasteItem(_ item: ClipboardItemRow) {
        if monitor.checkAccessibilityPermission() {
            isPasteBlockedToastVisible = false
        }
        lastPastedItemId = item.id
        pastedItemToastId = item.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if self.pastedItemToastId == item.id {
                self.pastedItemToastId = nil
            }
        }
        monitor.pasteIntoTargetApp(item)
    }

    private func deleteItem(_ item: ClipboardItemRow) {
        monitor.items.removeAll { $0.id == item.id }
        monitor.evictImage(for: item.id)
        monitor.evictCanonicalColor(for: item.id)
        monitor.pausedTimerSeconds.removeValue(forKey: item.id)
        if revealedSecretItemId == item.id {
            revealedSecretItemId = nil
        }
        if selectedItemId == item.id {
            selectedItemId = filteredItems.first?.id
        }
        Task {
            try? await DatabaseManager.shared.deleteItem(id: item.id)
        }
    }

    private func clearAllHistory() {
        monitor.clearAllHistory()
        selectedItemId = nil
        revealedSecretItemId = nil
    }

    private func togglePin(item: ClipboardItemRow) {
        monitor.togglePin(for: item.id)
    }

    private func saveImageToDisk(img: NSImage, defaultName: String) {
        NSApp.activate(ignoringOtherApps: true)
        let savePanel = NSSavePanel()
        if let pngType = UTType(filenameExtension: "png") {
            savePanel.allowedContentTypes = [pngType]
        }
        savePanel.canCreateDirectories = true
        savePanel.nameFieldStringValue = defaultName
        savePanel.prompt = tr("Сохранить", "Save")
        savePanel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.floatingWindow)) + 5)

        let writePNG: (URL) -> Void = { url in
            if let tiff = img.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiff),
               let pngData = bitmap.representation(using: .png, properties: [:]) {
                try? pngData.write(to: url)
            }
        }

        let targetWindow = NSApp.windows.first(where: { $0.isVisible && !($0 is NSPanel && $0.className.contains("Popup")) }) ?? NSApp.keyWindow
        if let window = targetWindow {
            savePanel.beginSheetModal(for: window) { response in
                if response == .OK, let url = savePanel.url {
                    writePNG(url)
                }
            }
        } else {
            if savePanel.runModal() == .OK, let url = savePanel.url {
                writePNG(url)
            }
        }
    }

    private struct LightboxTopButton<Content: View>: View {
        let action: () -> Void
        let isActive: Bool
        let theme: AppTheme
        let content: () -> Content
        @State private var isHovered: Bool = false
        @AppStorage("selectedFontId") private var selectedFontId: String = AppFont.default.rawValue

        private var currentFont: AppFont {
            AppFont(fromRaw: selectedFontId)
        }

        init(
            isActive: Bool = false,
            theme: AppTheme = .obsidian,
            action: @escaping () -> Void,
            @ViewBuilder content: @escaping () -> Content
        ) {
            self.action = action
            self.isActive = isActive
            self.theme = theme
            self.content = content
        }

        var body: some View {
            Button(action: action) {
                content()
                    .font(currentFont.font(size: 11.5, weight: isActive ? .semibold : .medium))
                    .foregroundStyle(isActive ? Color.white : theme.primaryText)
                    .symbolRenderingMode(.monochrome)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        isActive
                            ? theme.accentColor
                            : (isHovered ? theme.primaryText.opacity(0.14) : theme.primaryText.opacity(0.08))
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(
                                isActive
                                    ? theme.accentColor.opacity(0.85)
                                    : (isHovered ? theme.accentColor.opacity(0.45) : theme.borderColor),
                                lineWidth: 1
                            )
                    )
            }
            .buttonStyle(.plain)
            .fixedSize(horizontal: true, vertical: false)
            .onHover { hovering in
                isHovered = hovering
                if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
            }
        }
    }

    // MARK: - Custom Clear History Confirmation Modal
    @ViewBuilder
    private var clearHistoryModalOverlay: some View {
        if showClearHistoryConfirmation {
            let unpinnedCount = monitor.items.filter { !$0.isPinned }.count
            let pinnedCount = monitor.items.filter { $0.isPinned }.count

            ZStack {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .onTapGesture {
                        showClearHistoryConfirmation = false
                    }

                VStack(spacing: 16) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.red.opacity(0.15))
                                .frame(width: 36, height: 36)
                            Image(systemName: "trash")
                                .symbolRenderingMode(.monochrome)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.red)
                        }

                        Text(tr("Очистить историю буфера?", "Clear Clipboard History?"))
                            .font(currentFont.font(size: 15, weight: .bold))
                            .foregroundStyle(currentTheme.primaryText)

                        Spacer()
                    }

                    Text(tr(
                        "Все незакреплённые записи из истории буфера (\(unpinnedCount) шт.) будут безвозвратно удалены. Закреплённые записи (\(pinnedCount) шт.) будут сохранены.",
                        "All unpinned items from clipboard history (\(unpinnedCount) items) will be permanently deleted. Pinned items (\(pinnedCount) items) will be preserved."
                    ))
                    .font(currentFont.font(size: 12.5, weight: .regular))
                    .foregroundStyle(currentTheme.secondaryText)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        Button {
                            showClearHistoryConfirmation = false
                        } label: {
                            Text(tr("Отмена", "Cancel"))
                                .frame(maxWidth: .infinity)
                        }
                        .pvButton(variant: .secondary, size: .small, theme: currentTheme)
                        .keyboardShortcut(.cancelAction)

                        Button {
                            showClearHistoryConfirmation = false
                            clearUnpinnedHistory()
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "trash")
                                    .symbolRenderingMode(.monochrome)
                                Text(tr("Очистить кроме закреплённых", "Clear except pinned"))
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .pvButton(variant: .destructive, size: .small, theme: currentTheme)
                    }
                    .padding(.top, 4)
                }
                .padding(20)
                .frame(width: 380)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(currentTheme.cardColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(currentTheme.borderColor, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.35), radius: 20, x: 0, y: 10)
            }
            .transition(.opacity)
            .zIndex(500)
        }
    }

    // MARK: - Clear Unpinned Snippets Confirmation Modal Overlay
    @ViewBuilder
    private var clearSnippetsModalOverlay: some View {
        if showClearSnippetsConfirmation {
            let unpinnedCount = snippetsList.filter { !$0.isPinned }.count
            let pinnedCount = snippetsList.filter { $0.isPinned }.count

            ZStack {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .onTapGesture {
                        showClearSnippetsConfirmation = false
                    }

                VStack(spacing: 16) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.red.opacity(0.15))
                                .frame(width: 36, height: 36)
                            Image(systemName: "trash")
                                .symbolRenderingMode(.monochrome)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.red)
                        }

                        Text(tr("Удалить незакрепленные фрагменты?", "Clear unpinned snippets?"))
                            .font(currentFont.font(size: 15, weight: .bold))
                            .foregroundStyle(currentTheme.primaryText)

                        Spacer()
                    }

                    Text(tr(
                        "Все незакрепленные фрагменты (\(unpinnedCount) шт.) будут удалены. Закрепленные булавкой шаблоны (\(pinnedCount) шт.) останутся в сохранности.",
                        "All unpinned snippets (\(unpinnedCount) items) will be deleted. Pinned templates (\(pinnedCount) items) will be kept safe."
                    ))
                    .font(currentFont.font(size: 12.5, weight: .regular))
                    .foregroundStyle(currentTheme.secondaryText)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        Button {
                            showClearSnippetsConfirmation = false
                        } label: {
                            Text(tr("Отмена", "Cancel"))
                                .frame(maxWidth: .infinity)
                        }
                        .pvButton(variant: .secondary, size: .small, theme: currentTheme)
                        .keyboardShortcut(.cancelAction)

                        Button {
                            showClearSnippetsConfirmation = false
                            snippetsList.removeAll { !$0.isPinned }
                            saveSnippets()
                            TapticSoundAndHaptics.shared.performDialTick()
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "trash")
                                    .symbolRenderingMode(.monochrome)
                                Text(tr("Удалить", "Delete"))
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .pvButton(variant: .destructive, size: .small, theme: currentTheme)
                    }
                    .padding(.top, 4)
                }
                .padding(20)
                .frame(width: 380)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(currentTheme.cardColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(currentTheme.borderColor, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.35), radius: 20, x: 0, y: 10)
            }
            .transition(.opacity)
            .zIndex(501)
        }
    }

    // MARK: - Export Backup Modal Overlay
    @ViewBuilder
    private var exportModalOverlay: some View {
        if showExportModal {
            ZStack {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .onTapGesture {
                        showExportModal = false
                        ClipboardMonitor.shared.isModalOverlayActive = false
                    }

                VStack(spacing: 16) {
                    // Header
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(currentTheme.accentColor.opacity(0.15))
                                .frame(width: 36, height: 36)
                            Image(systemName: "arrow.up.doc.fill")
                                .symbolRenderingMode(.monochrome)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(currentTheme.accentColor)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(tr("Экспорт резервной копии", "Export Backup Archive"))
                                .font(currentFont.font(size: 15, weight: .bold))
                                .foregroundStyle(currentTheme.primaryText)
                            Text(tr("Выберите данные для сохранения в локальный файл", "Select data categories to save locally"))
                                .font(currentFont.font(size: 11, weight: .regular))
                                .foregroundStyle(currentTheme.secondaryText)
                        }

                        Spacer()
                    }

                    VStack(spacing: 10) {
                        // Блок 1: История буфера обмена
                        VStack(alignment: .leading, spacing: 8) {
                            modalCheckboxRow(
                                isOn: $exportIncludeClipboard,
                                title: tr("История буфера обмена", "Clipboard History"),
                                badge: "\(monitor.items.count)"
                            )

                            if exportIncludeClipboard {
                                HStack(spacing: 6) {
                                    Button {
                                        exportClipboardPinnedOnly = false
                                    } label: {
                                        Text(tr("Вся история (\(monitor.items.count))", "All History (\(monitor.items.count))"))
                                    }
                                    .pvButton(variant: .toggle(isActive: !exportClipboardPinnedOnly), size: .small, theme: currentTheme)

                                    let pinnedCount = monitor.items.filter { $0.isPinned }.count
                                    Button {
                                        exportClipboardPinnedOnly = true
                                    } label: {
                                        Text(tr("Только закрепленные 📌 (\(pinnedCount))", "Pinned Only 📌 (\(pinnedCount))"))
                                    }
                                    .pvButton(variant: .toggle(isActive: exportClipboardPinnedOnly), size: .small, theme: currentTheme)
                                }
                                .padding(.leading, 27)
                            }
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(currentTheme.isLight ? Color.black.opacity(0.03) : Color.white.opacity(0.04))
                        )

                        // Блок 2: Быстрые фрагменты (Snippets)
                        VStack(alignment: .leading, spacing: 8) {
                            modalCheckboxRow(
                                isOn: $exportIncludeSnippets,
                                title: tr("Быстрые фрагменты (Snippets)", "Quick Snippets"),
                                subtitle: tr("Включая статус закрепления 📌", "Including pin status 📌"),
                                badge: "\(snippetsList.count)"
                            )

                            if exportIncludeSnippets {
                                HStack(spacing: 6) {
                                    Button {
                                        exportSnippetsPinnedOnly = false
                                    } label: {
                                        Text(tr("Все фрагменты (\(snippetsList.count))", "All Snippets (\(snippetsList.count))"))
                                    }
                                    .pvButton(variant: .toggle(isActive: !exportSnippetsPinnedOnly), size: .small, theme: currentTheme)

                                    let pinnedSnippets = snippetsList.filter { $0.isPinned }.count
                                    Button {
                                        exportSnippetsPinnedOnly = true
                                    } label: {
                                        Text(tr("Только закрепленные 📌 (\(pinnedSnippets))", "Pinned Only 📌 (\(pinnedSnippets))"))
                                    }
                                    .pvButton(variant: .toggle(isActive: exportSnippetsPinnedOnly), size: .small, theme: currentTheme)
                                }
                                .padding(.leading, 27)
                            }
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(currentTheme.isLight ? Color.black.opacity(0.03) : Color.white.opacity(0.04))
                        )

                        // Блок 3: Настройки и Чёрный список приложений
                        VStack(alignment: .leading, spacing: 8) {
                            modalCheckboxRow(
                                isOn: $exportIncludeSettings,
                                title: tr("Настройки и Чёрный список приложений", "Settings & App Blacklist")
                            )

                            if exportIncludeSettings {
                                HStack(spacing: 8) {
                                    capsuleTypeToggle(
                                        title: tr("Чёрный список", "App Blacklist"),
                                        icon: "nosign",
                                        isOn: $exportIncludeBlacklist
                                    )
                                    capsuleTypeToggle(
                                        title: tr("Горячие клавиши", "Shortcuts"),
                                        icon: "keyboard",
                                        isOn: $exportIncludeShortcuts
                                    )
                                    capsuleTypeToggle(
                                        title: tr("Тема и лимиты", "Theme & Limits"),
                                        icon: "paintbrush",
                                        isOn: $exportIncludeAppearance
                                    )
                                }
                                .padding(.leading, 27)
                            }
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(currentTheme.isLight ? Color.black.opacity(0.03) : Color.white.opacity(0.04))
                        )
                    }

                    // Bottom Buttons
                    HStack(spacing: 10) {
                        Button {
                            showExportModal = false
                            ClipboardMonitor.shared.isModalOverlayActive = false
                        } label: {
                            Text(tr("Отмена", "Cancel"))
                                .frame(maxWidth: .infinity)
                        }
                        .pvButton(variant: .secondary, size: .small, theme: currentTheme)
                        .keyboardShortcut(.cancelAction)

                        let canExport = exportIncludeClipboard || exportIncludeSnippets || (exportIncludeSettings && (exportIncludeBlacklist || exportIncludeShortcuts || exportIncludeAppearance))
                        Button {
                            performExportSavePanel()
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "square.and.arrow.down")
                                    .symbolRenderingMode(.monochrome)
                                Text(tr("Выбрать папку и сохранить...", "Choose Folder & Save..."))
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .pvButton(variant: .primary, size: .small, theme: currentTheme)
                        .disabled(!canExport)
                        .opacity(canExport ? 1.0 : 0.5)
                    }
                    .padding(.top, 4)
                }
                .padding(20)
                .frame(width: 440)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(currentTheme.cardColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(currentTheme.borderColor, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.35), radius: 20, x: 0, y: 10)
            }
            .transition(.opacity)
            .zIndex(502)
        }
    }

    // MARK: - Import Confirmation Modal Overlay
    @ViewBuilder
    private var importConfirmationModalOverlay: some View {
        if showImportConfirmationModal, let archive = importArchive {
            let clipCount = archive.clipboardItems?.count ?? 0
            let clipPinned = archive.clipboardItems?.filter { $0.isPinned }.count ?? 0
            let snipCount = archive.snippets?.count ?? 0
            let snipPinned = archive.snippets?.filter { $0.isPinned }.count ?? 0
            let hasSettings = archive.settings != nil

            ZStack {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .onTapGesture {
                        showImportConfirmationModal = false
                        ClipboardMonitor.shared.isModalOverlayActive = false
                    }

                VStack(spacing: 16) {
                    // Header
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(currentTheme.accentColor.opacity(0.15))
                                .frame(width: 36, height: 36)
                            Image(systemName: "arrow.down.doc.fill")
                                .symbolRenderingMode(.monochrome)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(currentTheme.accentColor)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(tr("Импорт из резервной копии", "Import Backup Archive"))
                                .font(currentFont.font(size: 15, weight: .bold))
                                .foregroundStyle(currentTheme.primaryText)
                            HStack(spacing: 4) {
                                Image(systemName: "doc.text")
                                    .font(.system(size: 10))
                                Text(importFileName)
                                    .font(currentFont.font(size: 11, weight: .medium))
                            }
                            .foregroundStyle(currentTheme.secondaryText)
                        }

                        Spacer()
                    }

                    // Found Sections
                    VStack(spacing: 8) {
                        modalCheckboxRow(
                            isOn: $importRestoreClipboard,
                            title: tr("История буфера обмена", "Clipboard History"),
                            badge: clipCount > 0 ? "\(clipCount) (📌 \(clipPinned))" : tr("Нет записей", "No items"),
                            disabled: clipCount == 0
                        )
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(currentTheme.isLight ? Color.black.opacity(0.03) : Color.white.opacity(0.04))
                        )

                        modalCheckboxRow(
                            isOn: $importRestoreSnippets,
                            title: tr("Быстрые фрагменты (Snippets)", "Quick Snippets"),
                            badge: snipCount > 0 ? "\(snipCount) (📌 \(snipPinned))" : tr("Нет фрагментов", "No snippets"),
                            disabled: snipCount == 0
                        )
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(currentTheme.isLight ? Color.black.opacity(0.03) : Color.white.opacity(0.04))
                        )

                        modalCheckboxRow(
                            isOn: $importRestoreSettings,
                            title: tr("Настройки, клавиши и Чёрный список", "Settings, Keys & Blacklist"),
                            badge: hasSettings ? tr("Присутствуют", "Included") : tr("Нет в архиве", "Not in file"),
                            disabled: !hasSettings
                        )
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(currentTheme.isLight ? Color.black.opacity(0.03) : Color.white.opacity(0.04))
                        )
                    }

                    // Режим восстановления: две карточки
                    HStack(spacing: 10) {
                        Button {
                            importMergeMode = true
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Image(systemName: importMergeMode ? "checkmark.circle.fill" : "circle")
                                        .symbolRenderingMode(.monochrome)
                                        .foregroundStyle(importMergeMode ? currentTheme.accentColor : currentTheme.secondaryText)
                                    Text(tr("Объединить (Безопасно)", "Merge (Safe)"))
                                        .font(currentFont.font(size: 11.5, weight: .bold))
                                        .foregroundStyle(currentTheme.primaryText)
                                }
                                Text(tr("Добавить без дубликатов", "Add without duplicates"))
                                    .font(currentFont.font(size: 10, weight: .regular))
                                    .foregroundStyle(currentTheme.secondaryText)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(importMergeMode ? currentTheme.accentColor.opacity(0.12) : currentTheme.isLight ? Color.black.opacity(0.03) : Color.white.opacity(0.04))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(importMergeMode ? currentTheme.accentColor : currentTheme.borderColor.opacity(0.6), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)

                        Button {
                            importMergeMode = false
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Image(systemName: !importMergeMode ? "checkmark.circle.fill" : "circle")
                                        .symbolRenderingMode(.monochrome)
                                        .foregroundStyle(!importMergeMode ? Color.red : currentTheme.secondaryText)
                                    Text(tr("Заменить полностью", "Replace All"))
                                        .font(currentFont.font(size: 11.5, weight: .bold))
                                        .foregroundStyle(currentTheme.primaryText)
                                }
                                Text(tr("Очистить и восстановить 1-в-1", "Clear & overwrite 1-to-1"))
                                    .font(currentFont.font(size: 10, weight: .regular))
                                    .foregroundStyle(currentTheme.secondaryText)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(!importMergeMode ? Color.red.opacity(0.12) : currentTheme.isLight ? Color.black.opacity(0.03) : Color.white.opacity(0.04))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(!importMergeMode ? Color.red : currentTheme.borderColor.opacity(0.6), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    // Bottom Buttons
                    HStack(spacing: 10) {
                        Button {
                            showImportConfirmationModal = false
                            ClipboardMonitor.shared.isModalOverlayActive = false
                        } label: {
                            Text(tr("Отмена", "Cancel"))
                                .frame(maxWidth: .infinity)
                        }
                        .pvButton(variant: .secondary, size: .small, theme: currentTheme)
                        .keyboardShortcut(.cancelAction)

                        let canRestore = (importRestoreClipboard && clipCount > 0) || (importRestoreSnippets && snipCount > 0) || (importRestoreSettings && hasSettings)
                        Button {
                            performRestoreAction()
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.clockwise")
                                    .symbolRenderingMode(.monochrome)
                                Text(tr("Восстановить данные", "Restore Data"))
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .pvButton(variant: .primary, size: .small, theme: currentTheme)
                        .disabled(!canRestore)
                        .opacity(canRestore ? 1.0 : 0.5)
                    }
                    .padding(.top, 4)
                }
                .padding(20)
                .frame(width: 440)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(currentTheme.cardColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(currentTheme.borderColor, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.35), radius: 20, x: 0, y: 10)
            }
            .transition(.opacity)
            .zIndex(503)
        }
    }

    // MARK: - Backup UI Helpers & Actions
    private func modalCheckboxRow(
        isOn: Binding<Bool>,
        title: String,
        subtitle: String? = nil,
        badge: String? = nil,
        disabled: Bool = false
    ) -> some View {
        Button {
            if !disabled {
                isOn.wrappedValue.toggle()
            }
        } label: {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isOn.wrappedValue && !disabled ? currentTheme.accentColor : Color.primary.opacity(0.08))
                        .frame(width: 18, height: 18)
                    if isOn.wrappedValue && !disabled {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.white)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(isOn.wrappedValue && !disabled ? currentTheme.accentColor : currentTheme.borderColor, lineWidth: 1)
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(currentFont.font(size: 12.5, weight: .semibold))
                        .foregroundStyle(disabled ? currentTheme.secondaryText.opacity(0.5) : currentTheme.primaryText)
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(currentFont.font(size: 10.5, weight: .regular))
                            .foregroundStyle(currentTheme.secondaryText)
                    }
                }

                Spacer()

                if let badge = badge {
                    Text(badge)
                        .font(currentFont.font(size: 10.5, weight: .medium))
                        .foregroundStyle(disabled ? currentTheme.secondaryText.opacity(0.5) : currentTheme.accentColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill((disabled ? currentTheme.secondaryText : currentTheme.accentColor).opacity(0.12))
                        )
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private func showBackupToast(_ message: String, isError: Bool = false) {
        backupToastMessage = message
        backupToastIsError = isError
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.25)) {
                    backupToastMessage = nil
                }
            }
        }
    }

    private func performExportSavePanel() {
        guard let hostWindow = NSApp.windows.first(where: { $0.isVisible && ($0 is NSPanel || $0.className.contains("FloatingPanel")) }) ?? NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }) else { return }

        showExportModal = false
        ClipboardMonitor.shared.isModalOverlayActive = true
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSSavePanel()
        panel.title = tr("Сохранить резервную копию", "Save Backup Archive")
        panel.prompt = tr("Сохранить", "Save")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        panel.nameFieldStringValue = "PasteVault_Backup_\(formatter.string(from: Date())).json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true

        let targetLevel = NSWindow.Level(rawValue: max(Int(CGWindowLevelForKey(.popUpMenuWindow)), hostWindow.level.rawValue) + 2)
        panel.level = targetLevel

        let handleResponse: (NSApplication.ModalResponse) -> Void = { response in
            ClipboardMonitor.shared.isModalOverlayActive = false
            hostWindow.makeKeyAndOrderFront(nil)

            if response == .OK, let targetURL = panel.url {
                let archive = BackupManager.buildArchive(
                    items: self.monitor.items,
                    monitor: self.monitor,
                    snippets: self.snippetsList,
                    includeClipboard: self.exportIncludeClipboard,
                    clipboardPinnedOnly: self.exportClipboardPinnedOnly,
                    includeSnippets: self.exportIncludeSnippets,
                    snippetsPinnedOnly: self.exportSnippetsPinnedOnly,
                    includeBlacklist: self.exportIncludeSettings && self.exportIncludeBlacklist,
                    includeShortcuts: self.exportIncludeSettings && self.exportIncludeShortcuts,
                    includeAppearance: self.exportIncludeSettings && self.exportIncludeAppearance
                )

                do {
                    try BackupManager.exportArchiveToFile(archive: archive, to: targetURL)
                    self.showExportModal = false
                    self.showBackupToast(self.tr("Резервная копия успешно сохранена", "Backup successfully saved"))
                } catch {
                    self.showBackupToast(self.tr("Ошибка при экспорте: \(error.localizedDescription)", "Export error: \(error.localizedDescription)"), isError: true)
                }
            }
        }

        if hostWindow.attachedSheet == nil {
            panel.beginSheetModal(for: hostWindow, completionHandler: handleResponse)
        } else {
            let response = panel.runModal()
            handleResponse(response)
        }
    }

    private func openImportFilePicker() {
        guard let hostWindow = NSApp.windows.first(where: { $0.isVisible && ($0 is NSPanel || $0.className.contains("FloatingPanel")) }) ?? NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }) else { return }

        ClipboardMonitor.shared.isModalOverlayActive = true
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.title = tr("Выбрать файл резервной копии", "Select Backup Archive")
        panel.prompt = tr("Открыть", "Open")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]

        let targetLevel = NSWindow.Level(rawValue: max(Int(CGWindowLevelForKey(.popUpMenuWindow)), hostWindow.level.rawValue) + 2)
        panel.level = targetLevel

        let handleResponse: (NSApplication.ModalResponse) -> Void = { response in
            if response == .OK, let fileURL = panel.url {
                do {
                    let archive = try BackupManager.loadArchiveFromFile(from: fileURL)
                    self.importArchive = archive
                    self.importFileName = fileURL.lastPathComponent

                    let hasClipboard = (archive.clipboardItems?.count ?? 0) > 0
                    let hasSnippets = (archive.snippets?.count ?? 0) > 0
                    let hasSettings = archive.settings != nil

                    self.importRestoreClipboard = hasClipboard
                    self.importRestoreSnippets = hasSnippets
                    self.importRestoreSettings = hasSettings
                    self.importMergeMode = true

                    self.showImportConfirmationModal = true
                    ClipboardMonitor.shared.isModalOverlayActive = true
                    hostWindow.makeKeyAndOrderFront(nil)
                } catch {
                    ClipboardMonitor.shared.isModalOverlayActive = false
                    hostWindow.makeKeyAndOrderFront(nil)
                    self.showBackupToast(self.tr("Не удалось прочитать файл резервной копии", "Failed to parse backup archive"), isError: true)
                }
            } else {
                ClipboardMonitor.shared.isModalOverlayActive = false
                hostWindow.makeKeyAndOrderFront(nil)
            }
        }

        if hostWindow.attachedSheet == nil {
            panel.beginSheetModal(for: hostWindow, completionHandler: handleResponse)
        } else {
            let response = panel.runModal()
            handleResponse(response)
        }
    }

    private func performRestoreAction() {
        guard let archive = importArchive else { return }
        showImportConfirmationModal = false
        ClipboardMonitor.shared.isModalOverlayActive = false

        Task {
            do {
                try await BackupManager.restoreArchive(
                    archive,
                    restoreClipboard: importRestoreClipboard,
                    restoreSnippets: importRestoreSnippets,
                    restoreSettings: importRestoreSettings,
                    mergeMode: importMergeMode,
                    monitor: monitor,
                    currentSnippets: snippetsList,
                    onUpdateSnippets: { updated in
                        self.snippetsList = updated
                    }
                )
                await MainActor.run {
                    showBackupToast(tr("Данные успешно восстановлены", "Data successfully restored"))
                }
            } catch {
                await MainActor.run {
                    showBackupToast(tr("Ошибка при восстановлении: \(error.localizedDescription)", "Restore error: \(error.localizedDescription)"), isError: true)
                }
            }
        }
    }

    // MARK: - Up To Date Modal Overlay (Maccy-style compact alert)
    @ViewBuilder
    private var appUpToDateModalOverlay: some View {
        if updateService.isUpToDateModalPresented {
            let currentVer = updateService.currentVersion
            ZStack {
                Color.black.opacity(0.40)
                    .ignoresSafeArea()
                    .onTapGesture {
                        updateService.dismissUpToDateModal()
                    }

                VStack(spacing: 16) {
                    // 1. Иконка приложения (AppIcon 56x56)
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .shadow(color: Color.black.opacity(0.20), radius: 6, x: 0, y: 3)
                        .padding(.top, 4)

                    // 2. Заголовок и подзаголовок
                    VStack(spacing: 6) {
                        Text(tr("У вас всё обновлено!", "You’re up to date!"))
                            .font(currentFont.font(size: 15, weight: .bold))
                            .foregroundStyle(currentTheme.primaryText)
                            .multilineTextAlignment(.center)

                        Text(tr("В настоящий момент PasteVault v\(currentVer) является новейшей версией.", "PasteVault v\(currentVer) is currently the newest version available."))
                            .font(currentFont.font(size: 12, weight: .regular))
                            .foregroundStyle(currentTheme.secondaryText)
                            .multilineTextAlignment(.center)
                            .lineSpacing(2)
                    }
                    .padding(.horizontal, 8)

                    // 3. Широкая акцентная кнопка «ОК»
                    Button {
                        TapticSoundAndHaptics.shared.performDialTick()
                        updateService.dismissUpToDateModal()
                    } label: {
                        Text(tr("ОК", "OK"))
                            .frame(maxWidth: .infinity)
                    }
                    .pvButton(variant: .primary, size: .regular, theme: currentTheme)
                    .keyboardShortcut(.defaultAction)
                    .keyboardShortcut(.cancelAction)
                    .padding(.top, 4)
                }
                .padding(22)
                .frame(width: 320)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(currentTheme.cardColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(currentTheme.borderColor, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.35), radius: 24, x: 0, y: 12)
            }
            .transition(.opacity)
            .zIndex(560)
        }
    }

    // MARK: - In-App Update Modal Overlay
    @ViewBuilder
    private var appUpdateModalOverlay: some View {
        if updateService.isUpdateModalPresented {
            let currentVer = updateService.currentVersion
            let latestVer: String = {
                if case .updateAvailable(let ver, _, _, _) = updateService.state {
                    return ver
                }
                return ""
            }()
            let downloadURL: URL? = {
                if case .updateAvailable(_, let url, _, _) = updateService.state {
                    return url
                }
                return nil
            }()
            let notes: String = {
                if case .updateAvailable(_, _, _, let releaseNotes) = updateService.state {
                    return releaseNotes
                }
                return ""
            }()

            ZStack {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .onTapGesture {
                        if !updateService.isInstallingUpdate {
                            updateService.dismissModal()
                        }
                    }

                VStack(alignment: .leading, spacing: 14) {
                    // Header: Иконка приложения, заголовок и бейдж версий
                    HStack(spacing: 12) {
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .shadow(color: Color.black.opacity(0.18), radius: 4, x: 0, y: 2)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(tr("Доступно обновление PasteVault", "PasteVault Update Available"))
                                .font(currentFont.font(size: 15, weight: .bold))
                                .foregroundStyle(currentTheme.primaryText)

                            HStack(spacing: 6) {
                                Text("v\(currentVer)")
                                    .font(currentFont.font(size: 11, weight: .semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(currentTheme.primaryText.opacity(0.08))
                                    .clipShape(Capsule())
                                    .foregroundStyle(currentTheme.secondaryText)

                                Image(systemName: "arrow.right")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(currentTheme.secondaryText)

                                Text("v\(latestVer)")
                                    .font(currentFont.font(size: 11, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.20))
                                    .clipShape(Capsule())
                                    .foregroundStyle(Color.orange)
                            }
                        }

                        Spacer()

                        if !updateService.isInstallingUpdate {
                            Button {
                                updateService.dismissModal()
                            } label: {
                                Image(systemName: "xmark")
                                    .symbolRenderingMode(.monochrome)
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .buttonStyle(PVButtonStyle(variant: .secondary, size: .small, theme: currentTheme, fixedWidth: 26, fixedHeight: 26))
                        }
                    }

                    // Release Notes plate
                    VStack(alignment: .leading, spacing: 6) {
                        Text(tr("Что нового:", "What's New:"))
                            .font(currentFont.font(size: 11, weight: .semibold))
                            .foregroundStyle(currentTheme.secondaryText)

                        ScrollView(.vertical) {
                            Text(notes.isEmpty ? tr("Описание релиза доступно на странице GitHub Releases.", "Release notes are available on GitHub Releases.") : notes)
                                .font(currentFont.font(size: 12, weight: .regular))
                                .foregroundStyle(currentTheme.primaryText)
                                .lineSpacing(3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                        }
                        .frame(height: 120)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(currentTheme.backgroundColor.opacity(0.60))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(currentTheme.borderColor, lineWidth: 0.8)
                        )
                    }

                    // Индикатор установки (если запущена)
                    if updateService.isInstallingUpdate {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(tr("Загрузка и установка обновления...", "Downloading and installing update..."))
                                .font(currentFont.font(size: 11.5, weight: .medium))
                                .foregroundStyle(currentTheme.accentColor)

                            ProgressView(value: updateService.installProgress)
                                .progressViewStyle(.linear)
                                .tint(currentTheme.accentColor)
                        }
                        .padding(.vertical, 4)
                    } else {
                        // Чёткий вопрос: Установить обновление автоматически?
                        Text(tr("Установить обновление автоматически?", "Install update automatically?"))
                            .font(currentFont.font(size: 13, weight: .semibold))
                            .foregroundStyle(currentTheme.primaryText)
                            .padding(.top, 2)

                        // Две кнопки: «Да» и «Нет»
                        HStack(spacing: 10) {
                            Button {
                                TapticSoundAndHaptics.shared.performDialTick()
                                updateService.dismissModal()
                            } label: {
                                Text(tr("Нет", "No"))
                                    .frame(maxWidth: .infinity)
                            }
                            .pvButton(variant: .secondary, size: .regular, theme: currentTheme)
                            .keyboardShortcut(.cancelAction)

                            Button {
                                TapticSoundAndHaptics.shared.performDialClickConfirm()
                                if let url = downloadURL {
                                    Task {
                                        await updateService.downloadAndInstallUpdate(from: url, silent: false)
                                    }
                                }
                            } label: {
                                Text(tr("Да", "Yes"))
                                    .frame(maxWidth: .infinity)
                            }
                            .pvButton(variant: .primary, size: .regular, theme: currentTheme)
                            .keyboardShortcut(.defaultAction)
                        }

                        // Аккуратная кликабельная ссылка под кнопками
                        Button {
                            TapticSoundAndHaptics.shared.performDialTick()
                            updateService.openReleasePage()
                        } label: {
                            HStack(spacing: 4) {
                                Text(tr("Скачать новую версию самостоятельно по ссылке с GitHub", "Download manually from GitHub"))
                                    .font(currentFont.font(size: 11, weight: .medium))
                                Image(systemName: "arrow.up.forward.square")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundStyle(currentTheme.secondaryText.opacity(0.85))
                        }
                        .buttonStyle(.plain)
                        .onHover { hovering in
                            if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 2)
                    }
                }
                .padding(20)
                .frame(width: 440)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(currentTheme.cardColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(currentTheme.borderColor, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.35), radius: 24, x: 0, y: 12)
            }
            .transition(.opacity)
            .zIndex(550)
        }
    }

    private func saveAnnotatedScreenshotAndClose(originalItem: ClipboardItemRow, sourceImage: NSImage) {
        TapticSoundAndHaptics.shared.performDialClickConfirm()
        if let rendered = screenshotEditorEngine.renderAnnotatedImage(
            baseImage: sourceImage,
            canvasSize: editorCanvasSize,
            zoomScale: lightboxZoomScale,
            panOffset: editorPanOffset
        ) {
            let newItem = monitor.saveAnnotatedCopy(from: originalItem, annotatedImage: rendered)
            selectedItemId = newItem.id
        }
        closeImageLightbox()
    }

    private func closeImageLightbox() {
        screenshotEditorEngine.commitActiveTextEditing()
        isScreenshotEditingMode = false
        isImageLightboxPresented = false
        zoomedImage = nil
        zoomedItem = nil
        monitor.isModalOverlayActive = false
        monitor.isEditingScreenshotText = false
    }

    private func imageLightboxOverlay(for item: ClipboardItemRow, image: NSImage) -> some View {
        ZStack {
            ZStack {
                if currentTheme.usesLiquidGlass {
                    VisualEffectBlur(
                        material: currentTheme.isLight ? .underWindowBackground : .hudWindow,
                        blendingMode: .withinWindow
                    )
                }
                currentTheme.backgroundColor.opacity(currentTheme.usesLiquidGlass ? 0.94 : 0.98)
            }
            .ignoresSafeArea()
            .onTapGesture {
                guard !isScreenshotEditingMode else { return }
                closeImageLightbox()
            }

            VStack(spacing: 0) {
                // Верхняя панель управления лайтбоксом и редактором скриншотов
                HStack(spacing: 8) {
                    let displayedW = max(1, Int(round(image.size.width / max(1.0, lightboxZoomScale))))
                    let displayedH = max(1, Int(round(image.size.height / max(1.0, lightboxZoomScale))))
                    let sourceTitle: String = {
                        guard let raw = item.sourceAppName, !raw.isEmpty else {
                            return tr("Скриншот", "Screenshot")
                        }
                        return raw == "Paste Vault" ? "PasteVault" : raw
                    }()

                    // Левая часть шапки: компактный двухстрочный блок (источник сверху, разрешение снизу)
                    HStack(spacing: 8) {
                        Image(systemName: "photo")
                            .symbolRenderingMode(.monochrome)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(currentTheme.accentColor)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(sourceTitle)
                                .font(currentFont.font(size: 12.5, weight: .bold))
                                .foregroundStyle(currentTheme.primaryText)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: 150, alignment: .leading)

                            Text("\(displayedW) × \(displayedH) \(tr("пкс", "px"))")
                                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(currentTheme.secondaryText)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 12)

                    // Блок масштабирования [- 100% +] по центру (жёстко без переноса строки)
                    HStack(spacing: 4) {
                        LightboxTopButton(
                            theme: currentTheme,
                            action: {
                                lightboxZoomScale = max(1.0, lightboxZoomScale - 0.25)
                                if lightboxZoomScale <= 1.001 {
                                    editorPanOffset = .zero
                                }
                            }
                        ) {
                            Text("−")
                                .font(.system(size: 13, weight: .bold))
                        }

                        LightboxTopButton(
                            isActive: abs(lightboxZoomScale - 1.0) < 0.01,
                            theme: currentTheme,
                            action: {
                                lightboxScaleToFit = true
                                lightboxZoomScale = 1.0
                                editorPanOffset = .zero
                            }
                        ) {
                            Text("\(Int(round(lightboxZoomScale * 100)))%")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .lineLimit(1)
                                .frame(minWidth: 46)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .help(tr("Сбросить масштаб до 100%", "Reset zoom to 100%"))

                        LightboxTopButton(
                            theme: currentTheme,
                            action: {
                                lightboxZoomScale = min(3.0, lightboxZoomScale + 0.25)
                            }
                        ) {
                            Text("+")
                                .font(.system(size: 13, weight: .bold))
                        }
                    }
                    .fixedSize(horizontal: true, vertical: false)

                    Spacer(minLength: 12)

                    if isScreenshotEditingMode {
                        // Правая часть верхней панели в режиме редактирования скриншота (без дублирующей кнопки Отменить)
                        HStack(spacing: 8) {
                            LightboxTopButton(
                                theme: currentTheme,
                                action: {
                                    screenshotEditorEngine.clearAll()
                                }
                            ) {
                                Text(tr("Очистить всё", "Clear All"))
                            }
                            .opacity(screenshotEditorEngine.annotations.isEmpty ? 0.45 : 1.0)
                            .disabled(screenshotEditorEngine.annotations.isEmpty)

                            LightboxTopButton(
                                theme: currentTheme,
                                action: {
                                    let imgToSave = screenshotEditorEngine.renderAnnotatedImage(
                                        baseImage: image,
                                        canvasSize: editorCanvasSize,
                                        zoomScale: lightboxZoomScale,
                                        panOffset: editorPanOffset
                                    ) ?? image
                                    saveImageToDisk(img: imgToSave, defaultName: "Screenshot-\(item.id.prefix(8)).png")
                                }
                            ) {
                                HStack(spacing: 5) {
                                    Image(systemName: "square.and.arrow.down")
                                        .symbolRenderingMode(.monochrome)
                                    Text(tr("Сохранить PNG", "Save PNG"))
                                }
                            }

                            LightboxTopButton(
                                theme: currentTheme,
                                action: {
                                    closeImageLightbox()
                                }
                            ) {
                                Text(tr("Отмена", "Cancel"))
                            }
                            .keyboardShortcut(.cancelAction)

                            let canSaveCopy = !screenshotEditorEngine.annotations.isEmpty || lightboxZoomScale > 1.001
                            LightboxTopButton(
                                isActive: true,
                                theme: currentTheme,
                                action: {
                                    saveAnnotatedScreenshotAndClose(originalItem: item, sourceImage: image)
                                }
                            ) {
                                HStack(spacing: 5) {
                                    Text("✓")
                                        .font(.system(size: 12, weight: .bold))
                                    Text(tr("Сохранить копию", "Save Copy"))
                                }
                            }
                            .opacity(canSaveCopy ? 1.0 : 0.92)
                            .keyboardShortcut("s", modifiers: [.command])
                            .help(tr("Сохранить копию (с разметкой и/или приближением) в буфер обмена (⌘ + S / Enter)", "Save copy (annotated and/or zoomed) to clipboard (⌘ + S / Enter)"))
                        }
                    } else {
                        LightboxTopButton(
                            isActive: true,
                            theme: currentTheme,
                            action: {
                                isSearchFocused = false
                                monitor.isEditingScreenshotText = false
                                screenshotEditorEngine.clearAll()
                                withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                                    isScreenshotEditingMode = true
                                }
                                DispatchQueue.main.async {
                                    NSApp.keyWindow?.makeFirstResponder(nil)
                                }
                            }
                        ) {
                            HStack(spacing: 5) {
                                Text("✎")
                                    .font(.system(size: 12.5, weight: .bold))
                                Text(tr("Редактировать", "Edit"))
                            }
                        }

                        LightboxTopButton(
                            theme: currentTheme,
                            action: {
                                monitor.copyToClipboard(item: item)
                                isLightboxCopiedToastVisible = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    isLightboxCopiedToastVisible = false
                                }
                            }
                        ) {
                            HStack(spacing: 5) {
                                Image(systemName: isLightboxCopiedToastVisible ? "checkmark" : "doc.on.doc")
                                    .symbolRenderingMode(.monochrome)
                                Text(isLightboxCopiedToastVisible ? tr("Скопировано", "Copied") : tr("Копировать", "Copy"))
                            }
                        }

                        LightboxTopButton(
                            theme: currentTheme,
                            action: {
                                saveImageToDisk(img: image, defaultName: "Screenshot-\(item.id.prefix(8)).png")
                            }
                        ) {
                            HStack(spacing: 5) {
                                Image(systemName: "square.and.arrow.down")
                                    .symbolRenderingMode(.monochrome)
                                Text(tr("Сохранить PNG", "Save PNG"))
                            }
                        }

                        LightboxTopButton(
                            theme: currentTheme,
                            action: {
                                closeImageLightbox()
                            }
                        ) {
                            Image(systemName: "xmark")
                                .symbolRenderingMode(.monochrome)
                                .font(.system(size: 11, weight: .bold))
                        }
                        .keyboardShortcut(.cancelAction)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(currentTheme.cardColor.opacity(currentTheme.usesLiquidGlass ? 0.90 : 0.98))

                Divider()
                    .background(currentTheme.borderColor)

                // Рабочая область просмотра или векторного редактора скриншотов
                if isScreenshotEditingMode {
                    ScreenshotEditorWorkspaceView(
                        engine: screenshotEditorEngine,
                        sourceImage: image,
                        theme: currentTheme,
                        currentFont: currentFont,
                        windowOpacity: windowOpacity,
                        scaleToFit: lightboxScaleToFit,
                        zoomScale: lightboxZoomScale,
                        lastCanvasSize: $editorCanvasSize,
                        panOffset: $editorPanOffset
                    )
                    .transition(.opacity)
                } else {
                    ZStack {
                        if lightboxScaleToFit && abs(lightboxZoomScale - 1.0) < 0.01 {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .padding(24)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        } else {
                            ScrollView([.horizontal, .vertical]) {
                                Image(nsImage: image)
                                    .resizable()
                                    .frame(
                                        width: max(60, image.size.width * lightboxZoomScale),
                                        height: max(60, image.size.height * lightboxZoomScale)
                                    )
                                    .padding(24)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }

                Divider()
                    .background(currentTheme.borderColor)

                // Нижняя строка подсказок по горячим клавишам редактора (в едином стиле с подвалом главного окна)
                screenshotEditorBottomBar
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .clipped()
        .transition(.opacity)
        .zIndex(1000)
        .onAppear {
            isSearchFocused = false
            monitor.isModalOverlayActive = true
            monitor.isEditingScreenshotText = false
            DispatchQueue.main.async {
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
        }
        .onDisappear {
            monitor.isModalOverlayActive = false
            monitor.isEditingScreenshotText = false
        }
    }

    private var screenshotEditorBottomBar: some View {
        ScreenshotEditorBottomShortcutBar(
            engine: screenshotEditorEngine,
            theme: currentTheme,
            currentFont: currentFont,
            windowOpacity: windowOpacity,
            onUndo: {
                if isScreenshotEditingMode {
                    screenshotEditorEngine.undo()
                }
            },
            onSelectHand: {
                if isScreenshotEditingMode {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                        screenshotEditorEngine.selectedTool = .hand
                        screenshotEditorEngine.activeSubmenu = nil
                    }
                }
            },
            onDeleteSelected: {
                if isScreenshotEditingMode {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                        screenshotEditorEngine.deleteSelectedAnnotation()
                    }
                }
            },
            onStepZoom: {
                let nextZoom = lightboxZoomScale >= 3.0 ? 1.0 : min(3.0, lightboxZoomScale + 0.25)
                lightboxZoomScale = nextZoom
                if nextZoom <= 1.001 {
                    editorPanOffset = .zero
                }
            },
            onSaveCopy: {
                if isScreenshotEditingMode,
                   let img = zoomedImage ?? (selectedItem.flatMap { monitor.imageForItem($0) }) ?? (selectedItem?.rawImageData.flatMap { NSImage(data: $0) }),
                   let item = zoomedItem ?? selectedItem {
                    saveAnnotatedScreenshotAndClose(originalItem: item, sourceImage: img)
                }
            },
            onEscape: {
                if isScreenshotEditingMode, screenshotEditorEngine.editingTextAnnotationId != nil {
                    screenshotEditorEngine.commitActiveTextEditing()
                } else if isScreenshotEditingMode, screenshotEditorEngine.selectedAnnotationId != nil || screenshotEditorEngine.activeSubmenu != nil {
                    screenshotEditorEngine.selectedAnnotationId = nil
                    screenshotEditorEngine.activeSubmenu = nil
                } else {
                    closeImageLightbox()
                }
            }
        )
    }

    private func clearUnpinnedHistory() {
        monitor.clearUnpinnedHistory()
        if let selected = selectedItemId, !monitor.items.contains(where: { $0.id == selected }) {
            selectedItemId = filteredItems.first?.id
        }
    }

    private func generatePass() {
        TapticSoundAndHaptics.shared.performDialTick()
        if passIsMnemonic {
            let words = ["anchor", "arctic", "beacon", "binary", "cipher", "cosmos", "delta", "falcon", "granite", "kepler", "monolith", "nebula", "obsidian", "plasma", "quantum", "sapphire", "trident", "zenith"]
            let selected = (0..<4).map { _ in words.randomElement() ?? "vault" }
            self.passGeneratedSecret = selected.joined(separator: "-")
            self.passEntropyBits = 52
        } else {
            var chars = "abcdefghijklmnopqrstuvwxyz"
            if passIncludeUppercase { chars += "ABCDEFGHIJKLMNOPQRSTUVWXYZ" }
            if passIncludeDigits { chars += "0123456789" }
            if passIncludeSymbols { chars += "!@#$%^&*()-_=+" }

            let length = Int(passLength)
            let result = String((0..<length).map { _ in chars.randomElement() ?? "x" })
            self.passGeneratedSecret = result
            self.passEntropyBits = Int(Double(length) * log2(Double(chars.count)))
        }
    }

    private func loadDefaultSnippetsIfNeeded() {
        if let data = UserDefaults.standard.data(forKey: "pasteVaultQuickSnippets"),
           let saved = try? JSONDecoder().decode([QuickSnippetItem].self, from: data) {
            self.snippetsList = saved
        } else {
            self.snippetsList = []
        }
    }

    private func saveSnippets() {
        if let encoded = try? JSONEncoder().encode(snippetsList) {
            UserDefaults.standard.set(encoded, forKey: "pasteVaultQuickSnippets")
        }
    }
}

