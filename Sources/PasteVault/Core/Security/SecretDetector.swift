import Foundation

public struct SecretAnalysis: Sendable {
    public let isSensitive: Bool
    public let secretKind: String?
    public let recommendedTTLSeconds: Int64?
    public let shannonEntropy: Double
}

public enum SecretDetector {
    private static let patterns: [(name: String, regex: NSRegularExpression, ttl: Int64)] = {
        let specs: [(String, String, Int64)] = [
            ("JWT Token (RFC 7519)", #"^(?:[Bb][Ee][Aa][Rr][Ee][Rr]\s+)?eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}$"#, 120),
            ("Private SSH / PEM Key", #"-----BEGIN (?:OPENSSH |RSA |EC |DSA |PGP |ENCRYPTED )?PRIVATE KEY(?: BLOCK)?-----"#, 60),
            ("AWS IAM Access Key", #"\b(?:AKIA|ASIA|ABIA|ACCA)[0-9A-Z]{16}\b"#, 90),
            ("GitHub Personal Token", #"\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9_]{24,}\b"#, 90),
            ("Production API Secret", #"\b(?:sk_live_|rk_live_|sk-live-|rk-live-|sk-proj-|xox[baprs]-)[A-Za-z0-9_-]{16,}\b"#, 60)
        ]
        return specs.compactMap { name, pattern, ttl in
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
            return (name, regex, ttl)
        }
    }()

    private static let emailRegex = try? NSRegularExpression(pattern: #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#)
    private static let hostPortRegex = try? NSRegularExpression(pattern: #"^(?:localhost|(?:\d{1,3}\.){3}\d{1,3}|[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+):\d{1,5}(?:/\S*)?$"#)
    private static let hexColorRegex = try? NSRegularExpression(pattern: #"^#(?:[0-9A-Fa-f]{3}|[0-9A-Fa-f]{4}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$"#)

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

    public static func inspect(_ rawText: String, language: AppLanguage? = nil) -> SecretAnalysis {
        let sample = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sample.isEmpty else {
            return SecretAnalysis(
                isSensitive: false,
                secretKind: nil,
                recommendedTTLSeconds: nil,
                shannonEntropy: 0
            )
        }

        // Проверяем PEM/SSH/PGP ключи и известные паттерны ДО ограничения длины 512 символов,
        // чтобы длинные RSA/OpenSSH/EC/PGP приватные ключи (1600–3200+ символов) всегда распознавались как секреты.
        let patternScanSample = sample.count > 32_768 ? String(sample.prefix(32_768)) : sample
        let patternRange = NSRange(patternScanSample.startIndex..<patternScanSample.endIndex, in: patternScanSample)
        let entropySample = sample.count > 512 ? String(sample.prefix(512)) : sample
        let entropy = calculateShannonEntropy(entropySample)

        for rule in patterns {
            if rule.regex.firstMatch(in: patternScanSample, options: [], range: patternRange) != nil {
                return SecretAnalysis(
                    isSensitive: true,
                    secretKind: rule.name,
                    recommendedTTLSeconds: rule.ttl,
                    shannonEntropy: entropy
                )
            }
        }

        // Ограничение O(1) для эвристики паролей: строки длиннее 512 символов отсекаются мгновенно
        guard rawText.count <= 512 else {
            return SecretAnalysis(
                isSensitive: false,
                secretKind: nil,
                recommendedTTLSeconds: nil,
                shannonEntropy: 0
            )
        }

        // Имена файлов с расширениями и кириллические фразы без цифр никогда не являются паролями
        if isLikelyFileName(sample) || isCyrillicSnakeOrKebabWithoutDigits(sample) {
            return SecretAnalysis(
                isSensitive: false,
                secretKind: nil,
                recommendedTTLSeconds: nil,
                shannonEntropy: entropy
            )
        }

        let range = NSRange(sample.startIndex..<sample.endIndex, in: sample)
        let hasNoWhitespace = !sample.contains(" ") && !sample.contains("\t") && !sample.contains("\n") && !sample.contains("\r")
        let lower = sample.lowercased()
        let isKnownAbsPath = lower.hasPrefix("/users/") || lower.hasPrefix("/applications/") ||
                             lower.hasPrefix("/library/") || lower.hasPrefix("/system/") ||
                             lower.hasPrefix("/private/") || lower.hasPrefix("/volumes/") ||
                             lower.hasPrefix("/opt/") || lower.hasPrefix("/usr/") ||
                             lower.hasPrefix("/var/") || lower.hasPrefix("/etc/") ||
                             lower.hasPrefix("/bin/") || lower.hasPrefix("/sbin/")
        let pathComponents = sample.split(separator: "/")
        let isGenericUnixPath = sample.hasPrefix("/") &&
                                pathComponents.count >= 2 &&
                                sample.allSatisfy { $0.isLetter || $0.isNumber || $0 == "/" || $0 == "." || $0 == "_" || $0 == "-" }
        let isURLOrPath = lower.hasPrefix("http://") || lower.hasPrefix("https://") ||
                          lower.hasPrefix("file://") || sample.hasPrefix("~/") ||
                          isKnownAbsPath || isGenericUnixPath
        let isHexColor = hexColorRegex?.firstMatch(in: sample, options: [], range: range) != nil
        let isStructuredData = (sample.hasPrefix("{") && sample.hasSuffix("}") && (sample.contains(":") || sample.contains("\""))) ||
                               (sample.hasPrefix("[") && sample.hasSuffix("]") && (sample.contains(",") || sample.contains("\"") || sample.contains(":")))
        let isEmail = emailRegex?.firstMatch(in: sample, options: [], range: range) != nil
        let isHostPort = hostPortRegex?.firstMatch(in: sample, options: [], range: range) != nil

        // Проверка на пароли и секреты от 8 до 128 символов без пробелов
        if hasNoWhitespace && !isURLOrPath && !isHexColor && !isStructuredData && !isEmail && !isHostPort && (8...128).contains(sample.count) {
            let hyphenParts = sample.split(separator: "-", omittingEmptySubsequences: false)
            let isPureLettersHyphenated = hyphenParts.count >= 2
                && hyphenParts.allSatisfy { part in
                    !part.isEmpty && part.allSatisfy { $0.isLetter && !$0.isUppercase }
                }

            let specialChars = Set("!@#$%^&*()_+-=[]{}|;:'\",.<>?/`~")
            let hasLower = sample.contains { $0.isLowercase }
            let hasUpper = sample.contains { $0.isUppercase }
            let hasDigit = sample.contains { $0.isNumber }
            let hasSymbol = isPureLettersHyphenated
                ? false
                : sample.contains { specialChars.contains($0) || $0.isPunctuation || $0.isSymbol }

            var classCount = 0
            if hasLower { classCount += 1 }
            if hasUpper { classCount += 1 }
            if hasDigit { classCount += 1 }
            if hasSymbol { classCount += 1 }

            // б) Буквы + цифры + хотя бы 1 спецсимвол
            let hasLettersDigitsAndSymbol = (hasLower || hasUpper) && hasDigit && sample.contains { specialChars.contains($0) }

            // а) Как минимум 3 из 4 классов символов
            let hasThreeClasses = (classCount >= 3)

            let resolvedLang = language ?? AppLanguage.current
            let passwordLabel = (resolvedLang == .en) ? "Password" : "Пароль"

            if (8...15).contains(sample.count) {
                if hasThreeClasses || hasLettersDigitsAndSymbol {
                    return SecretAnalysis(
                        isSensitive: true,
                        secretKind: passwordLabel,
                        recommendedTTLSeconds: 60,
                        shannonEntropy: entropy
                    )
                }
            } else if (16...128).contains(sample.count) {
                if (entropy >= 3.55 && classCount >= 2) || hasThreeClasses || hasLettersDigitsAndSymbol {
                    return SecretAnalysis(
                        isSensitive: true,
                        secretKind: passwordLabel,
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

