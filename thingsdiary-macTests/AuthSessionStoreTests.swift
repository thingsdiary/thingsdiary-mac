import Foundation
import LocalAuthentication
import Security
import Testing

@testable import thingsdiary

@Test("Saved sessions use the data-protection keychain with user presence")
func savedSessionsRequireUserPresence() {
	let store = KeychainAuthSessionStore(
		service: "test.\(UUID().uuidString)",
		account: "session"
	)
	let query = store.query(returnData: true, requiresAuthentication: true)

	#expect(query[kSecUseDataProtectionKeychain] as? Bool == true)
	let context = query[kSecUseAuthenticationContext] as? LAContext
	#expect(context?.localizedReason == "Unlock your ThingsDiary session")
	#expect(KeychainAuthSessionStore.accessControlFlags == .userPresence)
}
