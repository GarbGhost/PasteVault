import Foundation
import Security

public struct SecretAnalysis: Sendable {
    public let isSensitive: Bool
    public let secretKind: String?
    public let recommendedTTLSeconds: Int64?
    public let shannonEntropy: Double
}

public enum SecretDetector {
    private static let patterns: [(name: String, regex: NSRegularExpression, ttl: Int64)] = {
        let specs: [(String, String, Int64)] = [
            ("JWT Token (RFC 7519)", #"^eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}$"#, 120),
            ("Private SSH / PEM Key", #"-----BEGIN (?:OPENSSH|RSA|EC|DSA|PGP) PRIVATE KEY-----"#, 60),
            ("AWS IAM Access Key", #"\b(?:AKIA|ASIA|ABIA|ACCA)[0-9A-Z]{16}\b"#, 90),
            ("GitHub Personal Token", #"\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9_]{24,}\b"#, 90),
            ("Production API Secret", #"\b(?:sk_live_|rk_live_|sk-live-|rk-live-|sk-proj-|xox[baprs]-)[A-Za-z0-9_-]{16,}\b"#, 60)
        ]
        return specs.compactMap { name, pattern, ttl in
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
            return (name, regex, ttl)
        }
    }()

    /// Проверяет, является ли строка вероятным именем файла с расширением
    public static func isLikelyFileName(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard !trimmed.contains(" ") && !trimmed.contains("\t") && !trimmed.contains("\n") && !trimmed.contains("\r") else {
            return false
        }
        guard trimmed.contains(".") else { return false }

        let lower = trimmed.lowercased()
        let knownExtensions: [String] = [
            ".conf", ".txt", ".docx", ".doc", ".json", ".swift", ".py", ".md", ".sh", ".js", ".ts",
            ".tsx", ".jsx", ".html", ".css", ".scss", ".xml", ".yaml", ".yml", ".toml", ".ini",
            ".cfg", ".env", ".plist", ".sql", ".db", ".sqlite", ".csv", ".log", ".pdf", ".png",
            ".jpg", ".jpeg", ".gif", ".webp", ".svg", ".icns", ".mp4", ".mov", ".mp3", ".wav",
            ".zip", ".tar", ".gz", ".dmg", ".pkg", ".app", ".command", ".pastevaultbackup"
        ]
        return knownExtensions.contains { lower.hasSuffix($0) }
    }

    /// Проверяет, содержит ли одиночная строка кириллические буквы и не содержит цифр (русский snake_case/kebab-case)
    public static func isCyrillicSnakeOrKebabWithoutDigits(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let hasCyrillic = trimmed.unicodeScalars.contains {
            ($0.value >= 0x0400 && $0.value <= 0x04FF) || ($0.value >= 0x0500 && $0.value <= 0x052F)
        }
        let hasDigits = trimmed.contains { $0 >= "0" && $0 <= "9" }
        return hasCyrillic && !hasDigits
    }

    public static func inspect(_ rawText: String) -> SecretAnalysis {
        // Ограничение O(1): строки длиннее 512 символов отсекаются мгновенно
        guard rawText.count <= 512 else {
            return SecretAnalysis(
                isSensitive: false,
                secretKind: nil,
                recommendedTTLSeconds: nil,
                shannonEntropy: 0
            )
        }

        let sample = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sample.isEmpty else {
            return SecretAnalysis(
                isSensitive: false,
                secretKind: nil,
                recommendedTTLSeconds: nil,
                shannonEntropy: 0
            )
        }

        let entropy = calculateShannonEntropy(sample)

        // Имена файлов с расширениями никогда не являются паролями
        if isLikelyFileName(sample) {
            return SecretAnalysis(
                isSensitive: false,
                secretKind: nil,
                recommendedTTLSeconds: nil,
                shannonEntropy: entropy
            )
        }

        // Кириллическая строка без цифр (например, слова через _) никогда не является паролем
        if isCyrillicSnakeOrKebabWithoutDigits(sample) {
            return SecretAnalysis(
                isSensitive: false,
                secretKind: nil,
                recommendedTTLSeconds: nil,
                shannonEntropy: entropy
            )
        }

        let range = NSRange(sample.startIndex..<sample.endIndex, in: sample)

        for rule in patterns {
            if rule.regex.firstMatch(in: sample, options: [], range: range) != nil {
                return SecretAnalysis(
                    isSensitive: true,
                    secretKind: rule.name,
                    recommendedTTLSeconds: rule.ttl,
                    shannonEntropy: entropy
                )
            }
        }

        // Проверка на пароли и секреты от 8 до 128 символов без пробелов
        let hasNoWhitespace = !sample.contains(" ") && !sample.contains("\t") && !sample.contains("\n") && !sample.contains("\r")
        let lower = sample.lowercased()
        let isURLOrPath = lower.hasPrefix("http://") || lower.hasPrefix("https://") ||
                          lower.hasPrefix("file://") || lower.hasPrefix("/users/") ||
                          sample.hasPrefix("~/") || sample.hasPrefix("/")
        let isHexColor = sample.hasPrefix("#")
        let isStructuredData = sample.hasPrefix("{") || sample.hasPrefix("[")
        let isFilename = isLikelyFileName(sample)

        if hasNoWhitespace && !isURLOrPath && !isHexColor && !isStructuredData && !isFilename && !isCyrillicSnakeOrKebabWithoutDigits(sample) && (8...128).contains(sample.count) {
            let specialChars = Set("!@#$%^&*()_+-=[]{}|;:'\",.<>?/`~")
            let hasLower = sample.contains { $0.isLowercase }
            let hasUpper = sample.contains { $0.isUppercase }
            let hasDigit = sample.contains { $0.isNumber }
            let hasSymbol = sample.contains { specialChars.contains($0) || $0.isPunctuation || $0.isSymbol }

            var classCount = 0
            if hasLower { classCount += 1 }
            if hasUpper { classCount += 1 }
            if hasDigit { classCount += 1 }
            if hasSymbol { classCount += 1 }

            // в) Мнемоническая фраза из 3–6 слов через дефис без пробелов
            let hyphenParts = sample.split(separator: "-", omittingEmptySubsequences: false)
            let isMnemonic = (3...6).contains(hyphenParts.count) && hyphenParts.allSatisfy { $0.count >= 2 && $0.allSatisfy { $0.isLetter } }

            // б) Буквы + цифры + хотя бы 1 спецсимвол
            let hasLettersDigitsAndSymbol = (hasLower || hasUpper) && hasDigit && sample.contains { specialChars.contains($0) }

            // а) Как минимум 3 из 4 классов символов
            let hasThreeClasses = (classCount >= 3)

            if (8...15).contains(sample.count) {
                if hasThreeClasses || hasLettersDigitsAndSymbol || isMnemonic {
                    return SecretAnalysis(
                        isSensitive: true,
                        secretKind: "Пароль",
                        recommendedTTLSeconds: 60,
                        shannonEntropy: entropy
                    )
                }
            } else if (16...128).contains(sample.count) {
                if (entropy >= 3.55 && classCount >= 2) || hasThreeClasses || hasLettersDigitsAndSymbol || isMnemonic {
                    return SecretAnalysis(
                        isSensitive: true,
                        secretKind: "Пароль",
                        recommendedTTLSeconds: 60,
                        shannonEntropy: entropy
                    )
                }
            }
        }

        return SecretAnalysis(
            isSensitive: false,
            secretKind: nil,
            recommendedTTLSeconds: nil,
            shannonEntropy: entropy
        )
    }

    public static func calculateShannonEntropy(_ text: String) -> Double {
        guard !text.isEmpty else { return 0.0 }
        var frequencies: [Character: Int] = [:]
        for char in text {
            frequencies[char, default: 0] += 1
        }
        let length = Double(text.count)
        return frequencies.values.reduce(0.0) { acc, count in
            let p = Double(count) / length
            return acc - p * log2(p)
        }
    }
}

