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
        if isImage || text.hasPrefix("[Скриншот") { return .image }
        if text.hasPrefix("[Файл") { return .file }
        if isSensitive { return .secret }

        let sample = String(text.prefix(1024)).trimmingCharacters(in: .whitespacesAndNewlines)
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

        // 3. Проверка на JSON или исходный код
        if isJSON(sample) || isCode(sample) {
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

    public static func isSwiftCode(_ sample: String) -> Bool {
        let swiftSignals = [
            "import SwiftUI", "import AppKit", "import Foundation", "@State ", "@Published ",
            "func ", "struct ", "protocol ", "extension ", "guard let ", "if let ", "DispatchQueue."
        ]
        return swiftSignals.filter { sample.contains($0) }.count >= 1 &&
            (sample.contains("{") || sample.contains("import ") || sample.contains("func "))
    }

    public static func isCode(_ sample: String) -> Bool {
        let codeSignals = [
            "func ", "import ", "struct ", "class ", "let ", "var ", "const ", "return ",
            "SELECT ", "FROM ", "WHERE ", "def ", "public ", "private ", "{", "}", "=>", "</"
        ]
        let matchCount = codeSignals.filter { sample.contains($0) }.count
        return matchCount >= 2 || (sample.contains("\n") && (sample.contains("{") || sample.contains(";")))
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
        if contentType == .image || sample.hasPrefix("[Скриншот") || sample.contains("#OCR") {
            result.append("#OCR")
        }
        if contentType == .color || isColor(sample) {
            result.append("Цвет")
        }
        if contentType == .file || sample.hasPrefix("[Файл") {
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


