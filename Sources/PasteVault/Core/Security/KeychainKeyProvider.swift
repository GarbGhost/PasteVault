import Foundation
import Security

public enum KeychainError: Error, LocalizedError {
    case randomGenerationFailed(OSStatus)
    case unexpectedStatus(OSStatus)
    case invalidKeyData
    case keyStorageUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case .randomGenerationFailed(let status):
            return "CSPRNG SecRandomCopyBytes error: \(status)"
        case .unexpectedStatus(let status):
            return "macOS Keychain OSStatus error: \(status)"
        case .invalidKeyData:
            return "Corrupted 256-bit key in storage"
        case .keyStorageUnavailable(let detail):
            return "Failed to initialize secure key storage: \(detail)"
        }
    }
}

public enum KeychainKeyProvider {
    private static let keyByteCount = 32
    private static let fileLock = NSLock()

    public static func withMasterKeyPragma<T>(_ body: (String) throws -> T) throws -> T {
        var keyData = try fetchOrCreateFileKey()
        defer {
            if !keyData.isEmpty {
                keyData.resetBytes(in: 0..<keyData.count)
            }
        }
        let hexString = keyData.map { String(format: "%02x", $0) }.joined()
        return try body("x'\(hexString)'")
    }

    private static func fetchOrCreateFileKey() throws -> Data {
        fileLock.lock()
        defer { fileLock.unlock() }

        let supportDir: URL
        if DatabaseManager.isRunningTests {
            supportDir = (try? DatabaseManager.pasteVaultSupportDirectory())
                ?? URL(fileURLWithPath: "/tmp", isDirectory: true)
                    .appendingPathComponent("PasteVault_TestRun_\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        } else {
            do {
                supportDir = try DatabaseManager.pasteVaultSupportDirectory()
            } catch {
                throw KeychainError.keyStorageUnavailable(error.localizedDescription)
            }
        }

        try FileManager.default.createDirectory(
            at: supportDir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let keyURL = supportDir.appendingPathComponent(".master.key")

        if FileManager.default.fileExists(atPath: keyURL.path) {
            let existingData = try Data(contentsOf: keyURL)
            guard existingData.count == keyByteCount else {
                throw KeychainError.invalidKeyData
            }
            return existingData
        }

        var newKey = Data(count: keyByteCount)
        let rngStatus = newKey.withUnsafeMutableBytes { buf -> OSStatus in
            guard let baseAddress = buf.baseAddress else { return errSecParam }
            return SecRandomCopyBytes(kSecRandomDefault, keyByteCount, baseAddress)
        }
        guard rngStatus == errSecSuccess else {
            newKey.resetBytes(in: 0..<newKey.count)
            throw KeychainError.randomGenerationFailed(rngStatus)
        }

        // Атомарное создание временного файла сразу с правами 0o600 без окна TOCTOU и переименование
        let tempURL = supportDir.appendingPathComponent(".master.key.tmp.\(UUID().uuidString)")
        let fd = Darwin.open(tempURL.path, O_WRONLY | O_CREAT | O_EXCL | O_TRUNC, S_IRUSR | S_IWUSR)
        guard fd >= 0 else {
            let errCode = errno
            newKey.resetBytes(in: 0..<newKey.count)
            throw KeychainError.keyStorageUnavailable("open() failed with errno \(errCode)")
        }

        var writeSucceeded = false
        defer {
            Darwin.close(fd)
            if !writeSucceeded {
                try? FileManager.default.removeItem(at: tempURL)
            }
        }

        let written = newKey.withUnsafeBytes { buf -> Int in
            guard let baseAddress = buf.baseAddress else { return -1 }
            var totalWritten = 0
            while totalWritten < keyByteCount {
                let n = Darwin.write(fd, baseAddress.advanced(by: totalWritten), keyByteCount - totalWritten)
                if n <= 0 {
                    if errno == EINTR { continue }
                    return -1
                }
                totalWritten += n
            }
            return totalWritten
        }
        guard written == keyByteCount else {
            newKey.resetBytes(in: 0..<newKey.count)
            throw KeychainError.keyStorageUnavailable("write() failed with errno \(errno)")
        }
        _ = Darwin.fsync(fd)
        Darwin.fchmod(fd, S_IRUSR | S_IWUSR)

        if Darwin.rename(tempURL.path, keyURL.path) != 0 {
            newKey.resetBytes(in: 0..<newKey.count)
            throw KeychainError.keyStorageUnavailable("rename() failed with errno \(errno)")
        }
        writeSucceeded = true
        return newKey
    }
}

