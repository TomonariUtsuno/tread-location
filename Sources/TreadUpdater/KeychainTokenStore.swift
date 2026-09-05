import Foundation
import Security

@MainActor
protocol TokenStoring: AnyObject {
    func token(for target: RepositoryTarget) throws -> String?
    func save(_ token: String, for target: RepositoryTarget) throws
    func deleteToken(for target: RepositoryTarget) throws
}

enum KeychainTokenStoreError: LocalizedError {
    case invalidToken
    case unexpectedData
    case operationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidToken: "トークンを入力してください。"
        case .unexpectedData: "Keychainから認証情報を読み取れませんでした。"
        case .operationFailed: "Keychainの認証情報を更新できませんでした。"
        }
    }
}

final class KeychainTokenStore: TokenStoring {
    private let service = "jp.tomonariutsuno.tread-updater.github-token"

    func token(for target: RepositoryTarget) throws -> String? {
        var query = baseQuery(target)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainTokenStoreError.operationFailed(status) }
        guard let data = result as? Data, let token = String(data: data, encoding: .utf8) else {
            throw KeychainTokenStoreError.unexpectedData
        }
        return token
    }

    func save(_ token: String, for target: RepositoryTarget) throws {
        let normalized = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw KeychainTokenStoreError.invalidToken }
        let data = Data(normalized.utf8)
        let query = baseQuery(target)
        let update: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainTokenStoreError.operationFailed(addStatus) }
        } else if updateStatus != errSecSuccess {
            throw KeychainTokenStoreError.operationFailed(updateStatus)
        }
    }

    func deleteToken(for target: RepositoryTarget) throws {
        let status = SecItemDelete(baseQuery(target) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainTokenStoreError.operationFailed(status)
        }
    }

    private func baseQuery(_ target: RepositoryTarget) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: target.identifier,
        ]
    }
}
