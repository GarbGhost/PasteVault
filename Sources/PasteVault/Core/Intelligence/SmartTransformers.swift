import Foundation
import AppKit
import Vision

public enum SmartClassifier {
    private static let hexColorRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$"#
    )
    private static let funcColorRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"^(?:rgb|rgba|hsl|hsla)\s*\([^)]+\)$"#,
        options: [.caseInsensitive]
    )

    public static func classify(text: String, isSensitive: Bool, isImage: Bool = false) -> ContentKind {
        if isImage || text.hasPrefix("[Скриншот") || text.hasPrefix("[Screenshot") { return .image }
        if text.hasPrefix("[Файл") || text.hasPrefix("[File") { return .file }
        if isSensitive { return .secret }

        let sample = String(text.prefix(12_000)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sample.isEmpty else { return .text }

        // 1. Проверка на цвет (#HEX, rgb(), rgba(), hsl(), hsla())
        if isColor(sample) {
            return .color
        }

        // 2. Проверка на URL
        let lower = sample.lowercased()
        if !sample.contains("\n") && !sample.contains(" ") &&
            (lower.hasPrefix("http://") || lower.hasPrefix("https://")) {
            return .url
        }

        // 3. Проверка на валидный JSON
        if isJSON(sample) {
            return .code
        }

        // 4. Проверка на чистый конфигурационный файл (.conf)
        if isConfigFile(sample) {
            return .code
        }

        // 5. Проверка на программный код с учётом естественной прозы (RU / EN)
        if isCode(sample) {
            return .code
        }

        return .text
    }

    /// Частичная визуальная маскировка секрета:
    /// - длина >= 8: первые 3 символа + "••••••••" + последние 3 символа
    /// - длина < 8: первые 2 символа + "••••••"
    public static func maskedSecret(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "••••••" }
        if trimmed.count >= 8 {
            let prefix = String(trimmed.prefix(3))
            let suffix = String(trimmed.suffix(3))
            return "\(prefix)••••••••\(suffix)"
        } else {
            let prefix = String(trimmed.prefix(2))
            return "\(prefix)••••••"
        }
    }

    /// Парсит строку цвета (#HEX, rgb/rgba, hsl/hsla) в NSColor для отрисовки цветного индикатора
    public static func parseNSColor(_ sample: String) -> NSColor? {
        let trimmed = sample.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("#") {
            let hex = String(trimmed.dropFirst())
            var val: UInt64 = 0
            guard Scanner(string: hex).scanHexInt64(&val) else { return nil }
            switch hex.count {
            case 3:
                let r = CGFloat((val >> 8) & 0xF) / 15.0
                let g = CGFloat((val >> 4) & 0xF) / 15.0
                let b = CGFloat(val & 0xF) / 15.0
                return NSColor(srgbRed: r, green: g, blue: b, alpha: 1.0)
            case 6:
                let r = CGFloat((val >> 16) & 0xFF) / 255.0
                let g = CGFloat((val >> 8) & 0xFF) / 255.0
                let b = CGFloat(val & 0xFF) / 255.0
                return NSColor(srgbRed: r, green: g, blue: b, alpha: 1.0)
            case 8:
                let r = CGFloat((val >> 24) & 0xFF) / 255.0
                let g = CGFloat((val >> 16) & 0xFF) / 255.0
                let b = CGFloat((val >> 8) & 0xFF) / 255.0
                let a = CGFloat(val & 0xFF) / 255.0
                return NSColor(srgbRed: r, green: g, blue: b, alpha: a)
            default:
                return nil
            }
        }
        let lower = trimmed.lowercased()
        if lower.hasPrefix("rgb") {
            guard let open = trimmed.firstIndex(of: "("),
                  let close = trimmed.lastIndex(of: ")") else { return nil }
            let inside = trimmed[trimmed.index(after: open)..<close]
            let normalized = inside.replacingOccurrences(of: "/", with: ",")
            let parts: [String]
            if normalized.contains(",") {
                parts = normalized.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            } else {
                parts = normalized.split(whereSeparator: { $0.isWhitespace }).map { String($0) }
            }
            guard parts.count >= 3 else { return nil }

            let parseComponent = { (str: String) -> Double? in
                if str.hasSuffix("%") {
                    return (Double(str.dropLast().trimmingCharacters(in: .whitespaces)) ?? 0) * 2.55
                }
                return Double(str)
            }

            guard let r = parseComponent(parts[0]),
                  let g = parseComponent(parts[1]),
                  let b = parseComponent(parts[2]) else { return nil }

            let a: Double
            if parts.count >= 4 {
                let aStr = parts[3]
                if aStr.hasSuffix("%") {
                    a = (Double(aStr.dropLast().trimmingCharacters(in: .whitespaces)) ?? 100.0) / 100.0
                } else {
                    a = Double(aStr) ?? 1.0
                }
            } else {
                a = 1.0
            }

            let red = CGFloat(max(0.0, min(1.0, r / 255.0)))
            let green = CGFloat(max(0.0, min(1.0, g / 255.0)))
            let blue = CGFloat(max(0.0, min(1.0, b / 255.0)))
            return NSColor(srgbRed: red, green: green, blue: blue, alpha: CGFloat(max(0.0, min(1.0, a))))
        }
        if lower.hasPrefix("hsl") {
            guard let open = trimmed.firstIndex(of: "("),
                  let close = trimmed.lastIndex(of: ")") else { return nil }
            let inside = trimmed[trimmed.index(after: open)..<close]
            let normalized = inside.replacingOccurrences(of: "/", with: ",")
            let rawParts: [String]
            if normalized.contains(",") {
                rawParts = normalized.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            } else {
                rawParts = normalized.split(whereSeparator: { $0.isWhitespace }).map { String($0) }
            }
            guard rawParts.count >= 3 else { return nil }

            var hStr = rawParts[0].lowercased()
            var h: Double = 0
            if hStr.hasSuffix("deg") {
                hStr = String(hStr.dropLast(3))
                h = Double(hStr.trimmingCharacters(in: .whitespaces)) ?? 0
            } else if hStr.hasSuffix("turn") {
                hStr = String(hStr.dropLast(4))
                h = (Double(hStr.trimmingCharacters(in: .whitespaces)) ?? 0) * 360.0
            } else if hStr.hasSuffix("rad") {
                hStr = String(hStr.dropLast(3))
                h = (Double(hStr.trimmingCharacters(in: .whitespaces)) ?? 0) * 180.0 / .pi
            } else {
                h = Double(hStr) ?? 0
            }
            h = h.truncatingRemainder(dividingBy: 360.0)
            if h < 0 { h += 360.0 }

            let sStr = rawParts[1]
            var s: Double = 0
            if sStr.hasSuffix("%") {
                s = (Double(sStr.dropLast().trimmingCharacters(in: .whitespaces)) ?? 0) / 100.0
            } else {
                s = Double(sStr) ?? 0
            }
            s = max(0.0, min(1.0, s))

            let lStr = rawParts[2]
            var l: Double = 0
            if lStr.hasSuffix("%") {
                l = (Double(lStr.dropLast().trimmingCharacters(in: .whitespaces)) ?? 0) / 100.0
            } else {
                l = Double(lStr) ?? 0
            }
            l = max(0.0, min(1.0, l))

            var a: Double = 1.0
            if rawParts.count >= 4 {
                let aStr = rawParts[3]
                if aStr.hasSuffix("%") {
                    a = (Double(aStr.dropLast().trimmingCharacters(in: .whitespaces)) ?? 100.0) / 100.0
                } else {
                    a = Double(aStr) ?? 1.0
                }
                a = max(0.0, min(1.0, a))
            }

            let c = (1.0 - abs(2.0 * l - 1.0)) * s
            let x = c * (1.0 - abs(((h / 60.0).truncatingRemainder(dividingBy: 2.0)) - 1.0))
            let m = l - c / 2.0

            var r1: Double = 0
            var g1: Double = 0
            var b1: Double = 0

            switch h {
            case 0..<60:
                r1 = c; g1 = x; b1 = 0
            case 60..<120:
                r1 = x; g1 = c; b1 = 0
            case 120..<180:
                r1 = 0; g1 = c; b1 = x
            case 180..<240:
                r1 = 0; g1 = x; b1 = c
            case 240..<300:
                r1 = x; g1 = 0; b1 = c
            default:
                r1 = c; g1 = 0; b1 = x
            }

            let red = CGFloat(max(0.0, min(1.0, r1 + m)))
            let green = CGFloat(max(0.0, min(1.0, g1 + m)))
            let blue = CGFloat(max(0.0, min(1.0, b1 + m)))
            return NSColor(srgbRed: red, green: green, blue: blue, alpha: CGFloat(a))
        }
        return nil
    }

    public static func isColor(_ sample: String) -> Bool {
        let trimmed = sample.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 48, !trimmed.contains("\n") else { return false }
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        if let hex = hexColorRegex, hex.firstMatch(in: trimmed, options: [], range: range) != nil {
            return true
        }
        if let fn = funcColorRegex, fn.firstMatch(in: trimmed, options: [], range: range) != nil {
            return true
        }
        return false
    }

    public static func isJSON(_ sample: String) -> Bool {
        let trimmed = sample.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) ||
              (trimmed.hasPrefix("[") && trimmed.hasSuffix("]")) else {
            return false
        }
        guard trimmed.contains(":") || trimmed.contains("\"") else { return false }
        if let data = trimmed.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil {
            return true
        }
        return trimmed.contains("\":")
    }

    /// Определяет долю кириллических букв в тексте вне кавычек и обратных апострофов
    public static func cyrillicLetterRatioOutsideQuotes(in text: String) -> Double {
        var totalLetters = 0
        var cyrillicLetters = 0
        var insideDoubleQuote = false
        var insideSingleQuote = false
        var insideBacktick = false

        for ch in text {
            if ch == "\"" || ch == "«" || ch == "»" {
                insideDoubleQuote.toggle()
                continue
            }
            if ch == "'" {
                insideSingleQuote.toggle()
                continue
            }
            if ch == "`" {
                insideBacktick.toggle()
                continue
            }
            if !insideDoubleQuote && !insideSingleQuote && !insideBacktick && ch.isLetter {
                totalLetters += 1
                if let scalar = ch.unicodeScalars.first,
                   (scalar.value >= 0x0400 && scalar.value <= 0x04FF) ||
                   (scalar.value >= 0x0500 && scalar.value <= 0x052F) {
                    cyrillicLetters += 1
                }
            }
        }
        guard totalLetters > 0 else { return 0 }
        return Double(cyrillicLetters) / Double(totalLetters)
    }

    /// Проверяет, является ли отдельная строка естественной строкой текста (прозы) на русском или английском языке
    public static func isNaturalProseLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }

        // Исключаем комментарии кода и шебанг
        if trimmed.hasPrefix("//") || trimmed.hasPrefix("/*") || trimmed.hasPrefix("*") ||
           trimmed.hasPrefix("#") || trimmed.hasPrefix(";") {
            return false
        }

        // Запрещённые ключевые слова начала строки кода
        let codeStartKeywords = [
            "import ", "func ", "struct ", "class ", "enum ", "protocol ", "extension ",
            "let ", "var ", "const ", "function ", "def ", "return ",
            "if (", "for (", "while (", "#include", "#!/",
            "public ", "private ", "internal "
        ]
        for kw in codeStartKeywords {
            if trimmed.hasPrefix(kw) {
                return false
            }
        }

        // Запрещённые окончания строк кода
        if trimmed.hasSuffix("{") || trimmed.hasSuffix("}") || trimmed.hasSuffix(";") {
            return false
        }

        // Подсчёт обычных слов (из кириллических или латинских букв), разделённых пробелами
        let rawTokens = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        var wordCount = 0
        for token in rawTokens {
            let stripped = token.trimmingCharacters(in: CharacterSet.punctuationCharacters.union(CharacterSet.symbols))
            let clean = stripped.filter { $0 != "-" && $0 != "—" && $0 != "_" }
            if !clean.isEmpty && clean.allSatisfy({ $0.isLetter }) {
                wordCount += 1
            }
        }

        return wordCount >= 5
    }

    /// Проверяет, имеет ли отдельная строка явную структуру программного кода или конфигурационного файла
    public static func isCodeOrConfigLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }

        // Если строка содержит кириллические буквы и не является кодовым комментарием, это строка естественного языка
        let hasCyrillic = trimmed.unicodeScalars.contains {
            ($0.value >= 0x0400 && $0.value <= 0x04FF) || ($0.value >= 0x0500 && $0.value <= 0x052F)
        }
        let isComment = trimmed.hasPrefix("//") || trimmed.hasPrefix("/*") || trimmed.hasPrefix("*") ||
                        trimmed.hasPrefix("#") || trimmed.hasPrefix(";")
        if hasCyrillic && !isComment {
            return false
        }

        // 1. Комментарии кода и конфигов
        if isComment {
            return true
        }

        // 2. Секция конфигурационного файла [Section]
        if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") && trimmed.count >= 3 && !trimmed.contains(" ") {
            return true
        }

        // 3. Параметр конфигурационного файла key = value или key: value
        if let eqIndex = trimmed.firstIndex(of: "=") {
            let key = trimmed[..<eqIndex].trimmingCharacters(in: .whitespaces)
            let val = trimmed[trimmed.index(after: eqIndex)...].trimmingCharacters(in: .whitespaces)
            let keyWords = key.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            let valWords = val.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            if keyWords.count == 1 && valWords.count <= 6 && !key.contains(".") && !key.contains(",") {
                return true
            }
        }

        // 4. Ключевые слова начала строки кода
        let codeStartKeywords = [
            "import ", "func ", "struct ", "class ", "enum ", "protocol ", "extension ",
            "let ", "var ", "const ", "function ", "def ", "return ",
            "if ", "if (", "else ", "else if ", "for ", "for (", "while ", "while (",
            "switch ", "case ", "default:", "guard ", "try ", "catch ", "throw ",
            "typealias ", "public ", "private ", "internal ", "fileprivate ", "open ",
            "static ", "final ", "override ", "mutating ",
            "@State ", "@Published ", "@Binding ", "@ObservedObject ", "@StateObject ",
            "@EnvironmentObject ", "@Environment", "@objc ",
            "#include", "#define", "#!/", "package ", "namespace ", "using ",
            "SELECT ", "INSERT ", "UPDATE ", "DELETE ", "FROM ", "WHERE "
        ]
        for kw in codeStartKeywords {
            if trimmed.hasPrefix(kw) {
                return true
            }
        }

        // 5. Окончания строк кода или закрывающие скобки
        if trimmed.hasSuffix("{") || trimmed.hasSuffix("};") || trimmed.hasSuffix("},") ||
           trimmed.hasSuffix(";") || trimmed.hasSuffix("->") || trimmed.hasSuffix("=>") {
            return true
        }
        if trimmed == "}" || trimmed == "]" || trimmed == ")" || trimmed == "});" || trimmed == "];" {
            return true
        }

        return false
    }

    public static func isConfigFile(_ sample: String) -> Bool {
        let lines = sample.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return false }

        // Если в тексте есть строки естественной прозы (>= 45%), это не файл конфигурации
        let proseCount = lines.filter { isNaturalProseLine($0) }.count
        if Double(proseCount) / Double(lines.count) >= 0.45 {
            return false
        }
        // Если в тексте преобладает кириллица вне кавычек (> 30%), это не файл конфигурации
        if cyrillicLetterRatioOutsideQuotes(in: sample) > 0.30 {
            return false
        }

        var configLineCount = 0
        var hasSection = false
        var keyValueCount = 0

        for line in lines {
            if line.hasPrefix("#") || line.hasPrefix(";") {
                configLineCount += 1
                continue
            }
            if line.hasPrefix("[") && line.hasSuffix("]") && line.count >= 3 && !line.contains(" ") {
                hasSection = true
                configLineCount += 1
                continue
            }
            if let eqIndex = line.firstIndex(of: "=") {
                let key = line[..<eqIndex].trimmingCharacters(in: .whitespaces)
                let val = line[line.index(after: eqIndex)...].trimmingCharacters(in: .whitespaces)
                let keyWords = key.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                let valWords = val.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                if keyWords.count == 1 && valWords.count <= 6 && !key.contains(".") && !key.contains(",") {
                    keyValueCount += 1
                    configLineCount += 1
                    continue
                }
            }
        }

        let configRatio = Double(configLineCount) / Double(lines.count)
        if configRatio >= 0.50 {
            if hasSection && (keyValueCount >= 1 || configLineCount >= 2) {
                return true
            }
            if keyValueCount >= 2 {
                return true
            }
        }
        return false
    }

    public static func isSwiftCode(_ sample: String) -> Bool {
        let lines = sample.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if !lines.isEmpty {
            let proseCount = lines.filter { isNaturalProseLine($0) }.count
            if Double(proseCount) / Double(lines.count) >= 0.45 { return false }
        }
        if cyrillicLetterRatioOutsideQuotes(in: sample) > 0.30 { return false }

        let swiftSignals = [
            "import SwiftUI", "import AppKit", "import Foundation", "@State ", "@Published ",
            "func ", "struct ", "protocol ", "extension ", "guard let ", "if let ", "DispatchQueue."
        ]
        return swiftSignals.filter { sample.contains($0) }.count >= 1 &&
            (sample.contains("{") || sample.contains("import ") || sample.contains("func "))
    }

    public static func isCode(_ sample: String) -> Bool {
        if isConfigFile(sample) { return true }

        let lines = sample.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return false }

        let totalLines = Double(lines.count)
        let proseCount = Double(lines.filter { isNaturalProseLine($0) }.count)
        let proseRatio = proseCount / totalLines

        let codeLinesCount = Double(lines.filter { isCodeOrConfigLine($0) }.count)
        let codeLinesRatio = codeLinesCount / totalLines

        let cyrillicRatio = cyrillicLetterRatioOutsideQuotes(in: sample)

        // Правило 1: Если в тексте доля строк естественной прозы >= 45% -> ВСЕГДА текст
        if proseRatio >= 0.45 {
            return false
        }

        // Правило 2: Если в тексте больше 30% кириллических букв вне кавычек и доля чисто кодовых строк < 40% -> ВСЕГДА текст
        if cyrillicRatio > 0.30 && codeLinesRatio < 0.40 {
            return false
        }

        // Правило 3: Карточка классифицируется как .code только тогда, когда не менее 40% непустых строк имеют явную структуру кода/конфига
        if codeLinesRatio >= 0.40 {
            return true
        }

        // Для ультра-коротких фрагментов (1-2 строки), не являющихся строками прозы
        if lines.count <= 2 && proseCount == 0 {
            let singleLineCodeSignals = [
                "func ", "import ", "struct ", "class ", "enum ", "protocol ",
                "let ", "var ", "const ", "def ", "function ",
                "#!/", "#include", "SELECT ", "public func ", "private func "
            ]
            let trimmed = sample.trimmingCharacters(in: .whitespacesAndNewlines)
            if singleLineCodeSignals.contains(where: { trimmed.hasPrefix($0) || trimmed.contains(" \($0)") }) {
                if cyrillicRatio <= 0.30 {
                    return true
                }
            }
            if sample.contains("{") && sample.contains("}") && (sample.contains(";") || sample.contains("=")) {
                if cyrillicRatio <= 0.30 {
                    return true
                }
            }
        }

        return false
    }

    public static func hasUTMTracking(_ sample: String) -> Bool {
        let lower = sample.lowercased()
        guard lower.hasPrefix("http://") || lower.hasPrefix("https://") else { return false }
        let trackingTokens = ["utm_", "fbclid=", "gclid=", "yclid=", "igshid=", "mc_cid=", "msclkid="]
        return trackingTokens.contains { lower.contains($0) }
    }

    /// Возвращает список динамических тегов для элемента буфера обмена
    public static func tags(for text: String, contentType: ContentKind, isSensitive: Bool) -> [String] {
        var result: [String] = []
        let sample = String(text.prefix(2048)).trimmingCharacters(in: .whitespacesAndNewlines)

        if hasUTMTracking(sample) {
            result.append("#UTM-трекер")
        }
        if isJSON(sample) {
            result.append("#JSON")
        }
        if isSwiftCode(sample) {
            result.append("#Swift")
        }
        if contentType == .image || sample.hasPrefix("[Скриншот") || sample.hasPrefix("[Screenshot") || sample.contains("#OCR") {
            result.append("#OCR")
        }
        if contentType == .color || isColor(sample) {
            result.append("Цвет")
        }
        if contentType == .file || sample.hasPrefix("[Файл") || sample.hasPrefix("[File") {
            result.append("#Файл")
        }
        return result
    }
}

public enum SmartTransformers {
    private static let trackingParams: Set<String> = [
        "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content", "utm_id",
        "fbclid", "gclid", "yclid", "dclid", "msclkid", "twclid", "igshid",
        "si", "_hsenc", "_hsmi", "mc_cid", "mc_eid", "rb_clickid"
    ]

    public static func sanitizeURL(_ rawURLString: String) -> String {
        let trimmed = rawURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let items = components.queryItems, !items.isEmpty else {
            return trimmed
        }

        let filtered = items.filter { item in
            let key = item.name.lowercased()
            return !trackingParams.contains(key) && !key.hasPrefix("utm_")
        }

        components.queryItems = filtered.isEmpty ? nil : filtered
        return components.url?.absoluteString ?? trimmed
    }

    public static func cleanPasteText(_ input: String) -> String {
        let forbiddenScalars: Set<Unicode.Scalar> = [
            "\u{200B}", "\u{200C}", "\u{200D}", "\u{FEFF}", "\u{00AD}", "\u{2060}"
        ]
        let strippedScalars = input.unicodeScalars.filter { !forbiddenScalars.contains($0) }
        var normalized = String(String.UnicodeScalarView(strippedScalars))
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\r\n", with: "\n")

        normalized = normalized.replacingOccurrences(
            of: #"[ \t]+"#,
            with: " ",
            options: .regularExpression
        )
        return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Color Formats Extension (HEX, RGB, HSL)
extension NSColor {
    public var hexString: String {
        guard let srgb = usingColorSpace(.sRGB) else { return "#000000" }
        let r = Int(round(srgb.redComponent * 255.0))
        let g = Int(round(srgb.greenComponent * 255.0))
        let b = Int(round(srgb.blueComponent * 255.0))
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    public var rgbString: String {
        guard let srgb = usingColorSpace(.sRGB) else { return "rgb(0, 0, 0)" }
        let r = Int(round(srgb.redComponent * 255.0))
        let g = Int(round(srgb.greenComponent * 255.0))
        let b = Int(round(srgb.blueComponent * 255.0))
        return "rgb(\(r), \(g), \(b))"
    }

    public var hslString: String {
        guard let srgb = usingColorSpace(.sRGB) else { return "hsl(0, 0%, 0%)" }
        let r = Double(srgb.redComponent)
        let g = Double(srgb.greenComponent)
        let b = Double(srgb.blueComponent)
        let maxVal = max(r, g, b)
        let minVal = min(r, g, b)
        var h: Double = 0
        var s: Double = 0
        let l: Double = (maxVal + minVal) / 2.0

        if maxVal != minVal {
            let d = maxVal - minVal
            s = l > 0.5 ? d / (2.0 - maxVal - minVal) : d / (maxVal + minVal)
            switch maxVal {
            case r:
                h = ((g - b) / d) + (g < b ? 6.0 : 0.0)
            case g:
                h = ((b - r) / d) + 2.0
            default:
                h = ((r - g) / d) + 4.0
            }
            h /= 6.0
        }

        let hDeg = Int(round(h * 360.0))
        let sPct = Int(round(s * 100.0))
        let lPct = Int(round(l * 100.0))
        return "hsl(\(hDeg), \(sPct)%, \(lPct)%)"
    }
}


