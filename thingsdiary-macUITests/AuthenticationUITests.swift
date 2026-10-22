import XCTest

final class AuthenticationUITests: XCTestCase {
	private enum Scenario: String {
		case loginSuccess = "login-success"
		case loginBadRequest = "login-bad-request"
		case registrationSuccess = "registration-success"
		case registrationDuplicate = "registration-duplicate"
		case registrationBadRequest = "registration-bad-request"
	}

	private var launchedApp: XCUIApplication?

	override func tearDown() {
		launchedApp?.terminate()
		launchedApp = nil
		super.tearDown()
	}

	func testSuccessfulLoginOpensDiaryCreation() {
		let app = launchAuthentication(scenario: .loginSuccess)
		let auth = authenticationSurface(in: app)

		typeText("person@example.test", into: auth.textFields["auth.email"])
		typeText("password", into: auth.secureTextFields["auth.password"])
		let secretKey = auth.secureTextFields["auth.secret-key"]
		typeText("TDKV1-000G-40R4-0M30-E209-185G-R38E-1W6", into: secretKey)
		secretKey.typeKey(.return, modifierFlags: [])

		XCTAssertTrue(app.textFields["diary.title"].firstMatch.waitForExistence(timeout: 3))
	}

	func testRegistrationExplainsThatLoginIsOccupied() {
		let app = launchAuthentication(scenario: .registrationDuplicate)
		let auth = authenticationSurface(in: app)
		openRegistration(in: auth)
		fillRegistration(in: auth)

		auth.buttons["auth.register"].click()

		assertError("An account with this email already exists.", in: app)
	}

	func testLoginShowsBadRequestReason() {
		let app = launchAuthentication(scenario: .loginBadRequest)
		let auth = authenticationSurface(in: app)

		typeText("person@example.test", into: auth.textFields["auth.email"])
		typeText("password", into: auth.secureTextFields["auth.password"])
		typeText(
			"TDKV1-000G-40R4-0M30-E209-185G-R38E-1W6",
			into: auth.secureTextFields["auth.secret-key"]
		)
		auth.buttons["auth.sign-in"].click()

		assertError("Sign in failed: login rejected by server", in: app)
	}

	func testSuccessfulRegistrationRequiresMatchingPasswordsAndShowsSecretKey() {
		let app = launchAuthentication(scenario: .registrationSuccess)
		let auth = authenticationSurface(in: app)
		openRegistration(in: auth)

		typeText("person@example.test", into: auth.textFields["auth.email"])
		typeText("password", into: auth.secureTextFields["auth.password"])
		let confirmation = auth.secureTextFields["auth.password-confirmation"]
		let register = auth.buttons["auth.register"]
		XCTAssertFalse(register.isEnabled)

		typeText("different", into: confirmation)
		XCTAssertFalse(register.isEnabled)
		XCTAssertTrue(auth.staticTexts["Passwords do not match."].exists)

		replaceText("password", in: confirmation)
		XCTAssertTrue(register.isEnabled)
		confirmation.typeKey(.return, modifierFlags: [])

		XCTAssertTrue(
			app.staticTexts["auth.generated-secret-key"].firstMatch.waitForExistence(timeout: 3)
		)
		XCTAssertTrue(app.buttons["I Saved My Secret Key"].firstMatch.exists)
	}

	func testRegistrationShowsBadRequestReason() {
		let app = launchAuthentication(scenario: .registrationBadRequest)
		let auth = authenticationSurface(in: app)
		openRegistration(in: auth)
		fillRegistration(in: auth)

		auth.buttons["auth.register"].click()

		assertError("Registration failed: password rejected by server", in: app)
	}

	private func launchAuthentication(scenario: Scenario) -> XCUIApplication {
		guard launchedApp == nil else {
			XCTFail("Each UI test must launch the app only once")
			return launchedApp!
		}
		let app = XCUIApplication()
		launchedApp = app
		app.launchArguments = [
			"-ApplePersistenceIgnoreState",
			"YES",
			"--ui-testing-auth-scenario",
			scenario.rawValue,
		]
		app.launch()
		XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 2))
		return app
	}

	private func authenticationSurface(in app: XCUIApplication) -> XCUIElement {
		let dialog = app.dialogs.firstMatch
		return dialog.exists ? dialog : app.windows.firstMatch
	}

	private func openRegistration(in auth: XCUIElement) {
		let button = auth.buttons["auth.show-registration"]
		XCTAssertTrue(button.waitForExistence(timeout: 2))
		button.click()
		XCTAssertTrue(
			auth.secureTextFields["auth.password-confirmation"].waitForExistence(timeout: 2)
		)
	}

	private func fillRegistration(in auth: XCUIElement) {
		typeText("person@example.test", into: auth.textFields["auth.email"])
		typeText("password", into: auth.secureTextFields["auth.password"])
		typeText("password", into: auth.secureTextFields["auth.password-confirmation"])
	}

	private func typeText(_ text: String, into element: XCUIElement) {
		XCTAssertTrue(element.waitForExistence(timeout: 2))
		element.click()
		element.typeText(text)
	}

	private func replaceText(_ text: String, in element: XCUIElement) {
		element.click()
		element.typeKey("a", modifierFlags: .command)
		element.typeKey(.delete, modifierFlags: [])
		element.typeText(text)
	}

	private func assertError(_ message: String, in app: XCUIApplication) {
		let error = app.staticTexts["auth.error"].firstMatch
		XCTAssertTrue(error.waitForExistence(timeout: 3))
		XCTAssertTrue(app.staticTexts[message].firstMatch.exists)
	}
}
