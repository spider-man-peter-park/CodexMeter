import CommonCrypto
import Foundation
import Security
import SQLite3

enum CursorCredentialFailure: Error {
    case missingDatabase, unavailableDatabase, missingToken, invalidToken, protectedToken
}

enum CursorLocalCredentials {
    static func read(database: URL) throws -> String? {
        guard FileManager.default.fileExists(atPath: database.path) else { throw CursorCredentialFailure.missingDatabase }
        let wal = database.path + "-wal"
        let shm = database.path + "-shm"
        let hasWAL = FileManager.default.fileExists(atPath: wal)
        let hasSHM = FileManager.default.fileExists(atPath: shm)
        // An immutable handle must never discard a live WAL. Do not create a missing shared-memory sidecar.
        guard !hasWAL || hasSHM else { throw CursorCredentialFailure.unavailableDatabase }
        let immutable = !hasWAL && !hasSHM
        let uri = database.absoluteURL.absoluteString + (immutable ? "?mode=ro&immutable=1" : "?mode=ro")
        var connection: OpaquePointer?
        guard sqlite3_open_v2(uri, &connection, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else {
            if connection != nil { sqlite3_close(connection) }
            throw CursorCredentialFailure.unavailableDatabase
        }
        defer { sqlite3_close(connection) }
        sqlite3_busy_timeout(connection, 250)
        var statement: OpaquePointer?
        let query = "SELECT value FROM ItemTable WHERE key = 'cursorAuth/accessToken' LIMIT 1"
        guard sqlite3_prepare_v2(connection, query, -1, &statement, nil) == SQLITE_OK else {
            throw CursorCredentialFailure.unavailableDatabase
        }
        defer { sqlite3_finalize(statement) }
        let result = sqlite3_step(statement)
        guard result == SQLITE_ROW else {
            if result == SQLITE_DONE { return nil }
            throw CursorCredentialFailure.unavailableDatabase
        }
        guard let bytes = sqlite3_column_blob(statement, 0) else { return nil }
        let count = Int(sqlite3_column_bytes(statement, 0))
        guard count <= 65_536 else { throw CursorCredentialFailure.invalidToken }
        let data = Data(bytes: bytes, count: count)
        if immutable && (FileManager.default.fileExists(atPath: wal) || FileManager.default.fileExists(atPath: shm)) {
            throw CursorCredentialFailure.unavailableDatabase
        }
        if count.isMultiple(of: 2), count > 0,
           stride(from: 0, to: count, by: 2).allSatisfy({ data[$0] > 0 && data[$0] < 128 && data[$0 + 1] == 0 }) {
            return String(data: data, encoding: .utf16LittleEndian)
        }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16LittleEndian)
    }

    static func decode(_ stored: String, passwordReader: @Sendable (String) -> String?) throws -> String {
        let prefix = "cursor-safe-storage:v1:"
        guard stored.hasPrefix("cursor-safe-storage:") else { return stored }
        guard stored.hasPrefix(prefix), let encrypted = Data(base64Encoded: String(stored.dropFirst(prefix.count))),
              encrypted.starts(with: Data("v10".utf8)), encrypted.count > 3,
              (encrypted.count - 3).isMultiple(of: kCCBlockSizeAES128) else {
            throw CursorCredentialFailure.protectedToken
        }
        for account in ["Cursor Key", "Cursor"] {
            guard let password = passwordReader(account), let data = decrypt(encrypted, password: password),
                  let token = String(data: data, encoding: .utf8) else { continue }
            return token
        }
        throw CursorCredentialFailure.protectedToken
    }

    static func password(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Cursor Safe Storage",
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func decrypt(_ encrypted: Data, password: String) -> Data? {
        let salt = Data("saltysalt".utf8)
        var key = Data(count: kCCKeySizeAES128)
        let keyCount = key.count
        let derived = key.withUnsafeMutableBytes { keyBytes in
            password.utf8CString.withUnsafeBytes { passwordBytes in
                salt.withUnsafeBytes { saltBytes in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), passwordBytes.bindMemory(to: Int8.self).baseAddress,
                        passwordBytes.count - 1, saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), 1003,
                        keyBytes.bindMemory(to: UInt8.self).baseAddress, keyCount)
                }
            }
        }
        guard derived == kCCSuccess else { return nil }
        let payload = Data(encrypted.dropFirst(3))
        let iv = Data(repeating: 0x20, count: kCCBlockSizeAES128)
        var output = Data(count: payload.count + kCCBlockSizeAES128)
        let capacity = output.count
        var written = 0
        let status = output.withUnsafeMutableBytes { outBytes in
            payload.withUnsafeBytes { payloadBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress, key.count, ivBytes.baseAddress,
                            payloadBytes.baseAddress, payload.count, outBytes.baseAddress, capacity, &written)
                    }
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        output.count = written
        return output
    }
}
