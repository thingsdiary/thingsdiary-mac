import AppKit
import Carbon.HIToolbox
import XCTest

private extension XCUIElement {
	func waitForKeyboardFocus(timeout: TimeInterval) -> Bool {
		let predicate = NSPredicate(format: "hasKeyboardFocus == true")
		let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
		return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
	}

	func waitUntilEnabled(timeout: TimeInterval) -> Bool {
		let predicate = NSPredicate(format: "isEnabled == true")
		let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
		return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
	}

	func waitForValue(_ expectedValue: String, timeout: TimeInterval) -> Bool {
		let predicate = NSPredicate(format: "value == %@", expectedValue)
		let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
		return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
	}
}

final class AuthenticationUITests: XCTestCase {
	private let email = "person@example.test"
	private let password = "password"
	private let secretKey = "TDKV1-000G-40R4-0M30-E209-185G-R38E-1W6"

	private enum Scenario: String {
		case loginSuccess = "login-success"
		case loginBadRequest = "login-bad-request"
		case registrationSuccess = "registration-success"
		case registrationMismatch = "registration-mismatch"
		case registrationDuplicate = "registration-duplicate"
		case registrationBadRequest = "registration-bad-request"
	}

	private var launchedApp: XCUIApplication?
	private var originalInputSource: TISInputSource?

	override func setUp() {
		super.setUp()
		continueAfterFailure = false
		originalInputSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
		guard let abcInputSource = inputSource(identifier: "com.apple.keylayout.ABC") else {
			XCTFail("ABC keyboard input source is unavailable")
			return
		}
		XCTAssertEqual(TISSelectInputSource(abcInputSource), noErr)
	}

	override func tearDown() {
		launchedApp?.terminate()
		launchedApp = nil
		if let originalInputSource {
			TISSelectInputSource(originalInputSource)
		}
		originalInputSource = nil
		super.tearDown()
	}

	func testSuccessfulLoginOpensDiaryCreation() {
		let app = launchAuthentication(scenario: .loginSuccess)
		let auth = authenticationSurface(in: app)
		enterLoginCredentials(in: auth, app: app)

		let secretKey = auth.secureTextFields["auth.secret-key"]
		XCTAssertTrue(auth.buttons["auth.sign-in"].waitUntilEnabled(timeout: 2))
		secretKey.typeKey(.return, modifierFlags: [])

		XCTAssertTrue(app.textFields["diary.title"].firstMatch.waitForExistence(timeout: 3))
		XCTAssertFalse(app.staticTexts["Something Went Wrong"].firstMatch.exists)
	}

	func testRegistrationExplainsThatLoginIsOccupied() {
		let app = launchAuthentication(scenario: .registrationDuplicate)
		let auth = authenticationSurface(in: app)
		enterRegistrationCredentials(in: auth, app: app)

		auth.buttons["auth.register"].click()

		assertError("An account with this email already exists.", in: app)
	}

	func testLoginShowsBadRequestReason() {
		let app = launchAuthentication(scenario: .loginBadRequest)
		let auth = authenticationSurface(in: app)
		enterLoginCredentials(in: auth, app: app)

		auth.buttons["auth.sign-in"].click()

		assertError("Sign in failed: login rejected by server", in: app)
	}

	func testMismatchedRegistrationPasswordsShowWarningAndKeepButtonDisabled() {
		let app = launchAuthentication(scenario: .registrationMismatch)
		let auth = authenticationSurface(in: app)
		enterText(email, into: auth.textFields["auth.email"], app: app, verifyValue: true)
		enterText(password, into: auth.secureTextFields["auth.password"], app: app)
		enterText("different", into: auth.secureTextFields["auth.password-confirmation"], app: app)
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
		enterRegistrationCredentials(in: auth, app: app)

		let confirmation = auth.secureTextFields["auth.password-confirmation"]
		XCTAssertTrue(auth.buttons["auth.register"].waitUntilEnabled(timeout: 2))
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
		enterRegistrationCredentials(in: auth, app: app)

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
		app.activate()
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

	private func enterLoginCredentials(in auth: XCUIElement, app: XCUIApplication) {
		enterText(email, into: auth.textFields["auth.email"], app: app, verifyValue: true)
		enterText(password, into: auth.secureTextFields["auth.password"], app: app)
		enterText(secretKey, into: auth.secureTextFields["auth.secret-key"], app: app)
	}

	private func enterRegistrationCredentials(in auth: XCUIElement, app: XCUIApplication) {
		enterText(email, into: auth.textFields["auth.email"], app: app, verifyValue: true)
		enterText(password, into: auth.secureTextFields["auth.password"], app: app)
		enterText(password, into: auth.secureTextFields["auth.password-confirmation"], app: app)
		XCTAssertTrue(auth.buttons["auth.register"].waitUntilEnabled(timeout: 2))
	}

	private func enterText(
		_ text: String,
		into field: XCUIElement,
		app: XCUIApplication,
		verifyValue: Bool = false
	) {
		app.activate()
		XCTAssertTrue(field.waitForExistence(timeout: 2))
		field.click()
		XCTAssertTrue(field.waitForKeyboardFocus(timeout: 2))
		var chunkStart = text.startIndex
		while chunkStart < text.endIndex {
			let chunkEnd = text.index(
				chunkStart,
				offsetBy: 4,
				limitedBy: text.endIndex
			) ?? text.endIndex
			field.typeText(String(text[chunkStart..<chunkEnd]))
			Thread.sleep(forTimeInterval: 0.1)
			chunkStart = chunkEnd
		}
		if verifyValue {
			XCTAssertTrue(
				field.waitForValue(text, timeout: 2),
				"Expected \(text), got \(String(describing: field.value))"
			)
		}
	}

	private func inputSource(identifier: String) -> TISInputSource? {
		let filter = [kTISPropertyInputSourceID as String: identifier] as CFDictionary
		return (TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource])?
			.first
	}
}
