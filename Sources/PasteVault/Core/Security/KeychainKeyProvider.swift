import Foundation
import Security
import CryptoKit

public enum KeychainError: Error, LocalizedError {
    case randomGenerationFailed(OSStatus)
    case unexpectedStatus(OSStatus)
    case invalidKeyData

    public var errorDescription: String? {
        switch self {
        case .randomGenerationFailed(let status):
            return "CSPRNG SecRandomCopyBytes error: \(status)"
        case .unexpectedStatus(let status):
            return "macOS Keychain OSStatus error: \(status)"
        case .invalidKeyData:
            return "Corrupted 256-bit key in Keychain"
        }
    }
}

public enum KeychainKeyProvider {
    private static let keyByteCount = 32

    public static func withMasterKeyPragma<T>(_ body: (String) throws -> T) throws -> T {
        var keyData = fetchOrCreateFileKey()
        defer {
            keyData.resetBytes(in: 0..<keyData.count)
        }
        let hexString = keyData.map { String(format: "%02x", $0) }.joined()
        return try body("x'\(hexString)'")
    }

    private static func fetchOrCreateFileKey() -> Data {
        let appSupport = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ))?.appendingPathComponent("PasteVault", isDirectory: true) ?? URL(fileURLWithPath: "/tmp/PasteVault")

        try? FileManager.default.createDirectory(
            at: appSupport,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let keyURL = appSupport.appendingPathComponent(".master.key")

        if let data = try? Data(contentsOf: keyURL), data.count == keyByteCount {
            return data
        }

        var newKey = Data(count: keyByteCount)
        _ = newKey.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, keyByteCount, $0.baseAddress!) }
        try? newKey.write(to: keyURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyURL.path)
        return newKey
    }
}

