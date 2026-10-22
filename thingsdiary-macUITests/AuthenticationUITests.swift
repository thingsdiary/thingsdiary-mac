import XCTest

final class AuthenticationUITests: XCTestCase {
	private enum Scenario: String {
		case loginSuccess = "login-success"
		case loginBadRequest = "login-bad-request"
		case registrationSuccess = "registration-success"
		case registrationMismatch = "registration-mismatch"
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

		let secretKey = auth.secureTextFields["auth.secret-key"]
		XCTAssertTrue(secretKey.waitForExistence(timeout: 2))
		secretKey.click()
		secretKey.typeKey(.return, modifierFlags: [])

		XCTAssertTrue(app.textFields["diary.title"].firstMatch.waitForExistence(timeout: 3))
		XCTAssertFalse(app.staticTexts["Something Went Wrong"].firstMatch.exists)
	}

	func testRegistrationExplainsThatLoginIsOccupied() {
		let app = launchAuthentication(scenario: .registrationDuplicate)
		let auth = authenticationSurface(in: app)

		auth.buttons["auth.register"].click()

		assertError("An account with this email already exists.", in: app)
	}

	func testLoginShowsBadRequestReason() {
		let app = launchAuthentication(scenario: .loginBadRequest)
		let auth = authenticationSurface(in: app)

		auth.buttons["auth.sign-in"].click()

		assertError("Sign in failed: login rejected by server", in: app)
	}

	func testMismatchedRegistrationPasswordsShowWarningAndKeepButtonDisabled() {
		let app = launchAuthentication(scenario: .registrationMismatch)
		let auth = authenticationSurface(in: app)
		let register = auth.buttons["auth.register"]
		XCTAssertTrue(register.waitForExistence(timeout: 2))
		XCTAssertFalse(register.isEnabled)
		let mismatch = auth.staticTexts["auth.password-mismatch"]
		XCTAssertTrue(mismatch.waitForExistence(timeout: 2))
		XCTAssertTrue(auth.staticTexts["Passwords do not match."].exists)
	}

	func testSuccessfulRegistrationShowsSecretKeyAndOpensDiaryCreation() {
		let app = launchAuthentication(scenario: .registrationSuccess)
		let auth = authenticationSurface(in: app)

		let confirmation = auth.secureTextFields["auth.password-confirmation"]
		XCTAssertTrue(auth.buttons["auth.register"].isEnabled)
		confirmation.click()
		confirmation.typeKey(.return, modifierFlags: [])

		XCTAssertTrue(
			app.staticTexts["auth.generated-secret-key"].firstMatch.waitForExistence(timeout: 3)
		)
		let continueButton = app.buttons["I Saved My Secret Key"].firstMatch
		XCTAssertTrue(continueButton.exists)
		continueButton.click()

		XCTAssertTrue(app.textFields["diary.title"].firstMatch.waitForExistence(timeout: 3))
		XCTAssertFalse(app.staticTexts["Something Went Wrong"].firstMatch.exists)
	}

	func testRegistrationShowsBadRequestReason() {
		let app = launchAuthentication(scenario: .registrationBadRequest)
		let auth = authenticationSurface(in: app)

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
		app.windows.firstMatch
	}

	private func assertError(_ message: String, in app: XCUIApplication) {
		let error = app.staticTexts["auth.error"].firstMatch
		XCTAssertTrue(error.waitForExistence(timeout: 3))
		XCTAssertTrue(app.staticTexts[message].firstMatch.exists)
	}
}
