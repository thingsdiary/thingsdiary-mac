import Foundation
import Security
import ThingsDiaryClient

nonisolated struct SavedAuthSession: Codable, Sendable, Equatable {
	let login: String
	let authentication: ThingsDiaryAuthState

	init(login: String, authentication: ThingsDiaryAuthState) {
		self.login = login
		self.authentication = authentication
	}

	private enum CodingKeys: String, CodingKey {
		case login
		case token
		case encryptionPrivateKey
		case encryptionPublicKey
		case signingPrivateKey
		case signingPublicKey
	}

	init(from decoder: any Decoder) throws {
		let values = try decoder.container(keyedBy: CodingKeys.self)
		login = try values.decode(String.self, forKey: .login)
		authentication = ThingsDiaryAuthState(
			token: try values.decode(String.self, forKey: .token),
			credentials: ThingsDiaryCredentials(
				encryptionPrivateKey: try values.decode(Data.self, forKey: .encryptionPrivateKey),
				encryptionPublicKey: try values.decode(Data.self, forKey: .encryptionPublicKey),
				signingPrivateKey: try values.decode(Data.self, forKey: .signingPrivateKey),
				signingPublicKey: try values.decode(Data.self, forKey: .signingPublicKey)
			)
		)
	}

	func encode(to encoder: any Encoder) throws {
		var values = encoder.container(keyedBy: CodingKeys.self)
		try values.encode(login, forKey: .login)
		try values.encode(authentication.token, forKey: .token)
		try values.encode(
			authentication.credentials.encryptionPrivateKey,
			forKey: .encryptionPrivateKey
		)
		try values.encode(
			authentication.credentials.encryptionPublicKey,
			forKey: .encryptionPublicKey
		)
		try values.encode(
			authentication.credentials.signingPrivateKey,
			forKey: .signingPrivateKey
		)
		try values.encode(
			authentication.credentials.signingPublicKey,
			forKey: .signingPublicKey
		)
	}
}

nonisolated protocol AuthSessionStore: Sendable {
	func load() throws -> SavedAuthSession?
	func save(_ session: SavedAuthSession) throws
	func clear() throws
}

nonisolated final class InMemoryAuthSessionStore: AuthSessionStore, @unchecked Sendable {
	private let lock = NSLock()
	private var session: SavedAuthSession?

	func load() throws -> SavedAuthSession? {
		lock.withLock { session }
	}

	func save(_ session: SavedAuthSession) throws {
		lock.withLock { self.session = session }
	}

	func clear() throws {
		lock.withLock { session = nil }
	}
}

nonisolated enum AuthSessionStoreError: Error {
	case unexpectedStatus(OSStatus)
}

nonisolated struct KeychainAuthSessionStore: AuthSessionStore {
	private let service: String
	private let account: String

	init(
		service: String = "io.thingsdiary.thingsdiary-mac",
		account: String = "active-session"
	) {
		self.service = service
		self.account = account
	}

	func load() throws -> SavedAuthSession? {
		var result: CFTypeRef?
		let status = SecItemCopyMatching(
			query(returnData: true) as CFDictionary,
			&result
		)
		if status == errSecItemNotFound {
			return nil
		}
		guard status == errSecSuccess, let data = result as? Data else {
			throw AuthSessionStoreError.unexpectedStatus(status)
		}
		return try JSONDecoder().decode(SavedAuthSession.self, from: data)
	}

	func save(_ session: SavedAuthSession) throws {
		let data = try JSONEncoder().encode(session)
		let status = SecItemUpdate(
			query() as CFDictionary,
			[kSecValueData: data] as CFDictionary
		)
		if status == errSecItemNotFound {
			var item = query()
			item[kSecValueData] = data
			item[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
			let addStatus = SecItemAdd(item as CFDictionary, nil)
			guard addStatus == errSecSuccess else {
				throw AuthSessionStoreError.unexpectedStatus(addStatus)
			}
			return
		}
		guard status == errSecSuccess else {
			throw AuthSessionStoreError.unexpectedStatus(status)
		}
	}

	func clear() throws {
		let status = SecItemDelete(query() as CFDictionary)
		guard status == errSecSuccess || status == errSecItemNotFound else {
			throw AuthSessionStoreError.unexpectedStatus(status)
		}
	}

	private func query(returnData: Bool = false) -> [CFString: Any] {
		var query: [CFString: Any] = [
			kSecClass: kSecClassGenericPassword,
			kSecAttrService: service,
			kSecAttrAccount: account,
		]
		if returnData {
			query[kSecReturnData] = true
			query[kSecMatchLimit] = kSecMatchLimitOne
		}
		return query
	}
}
