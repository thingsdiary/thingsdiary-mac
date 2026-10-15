import XCTest

final class DiaryWorkspaceUITests: XCTestCase {
	private func launchWorkspace() -> XCUIApplication {
		let app = XCUIApplication()
		app.launchArguments = ["--ui-testing-workspace"]
		app.launch()
		return app
	}

	func testSidebarChangesEntrySection() {
		let app = launchWorkspace()

		app.buttons["sidebar.bookmarks"].click()
		XCTAssertTrue(app.staticTexts["No Bookmarks"].waitForExistence(timeout: 2))

		app.buttons["sidebar.archive"].click()
		XCTAssertTrue(app.descendants(matching: .any)["entry.fixture-archived-entry"].waitForExistence(timeout: 2))

		app.buttons["sidebar.trash"].click()
		XCTAssertTrue(app.descendants(matching: .any)["entry.fixture-deleted-entry"].waitForExistence(timeout: 2))
	}

	func testEntryListHeaderAndRowsUseSeparateContainers() {
		let app = launchWorkspace()
		let header = app.descendants(matching: .any)["entry-list.header"].firstMatch
		let rows = app.descendants(matching: .any)["entry-list.scroll"].firstMatch

		XCTAssertTrue(header.waitForExistence(timeout: 2))
		XCTAssertTrue(rows.waitForExistence(timeout: 2))
		XCTAssertFalse(header.frame.intersects(rows.frame))
	}

	func testDiariesPickerCanBeCancelledWithoutLeavingWorkspace() {
		let app = launchWorkspace()

		app.buttons["Diaries"].firstMatch.click()

		let picker = app.descendants(matching: .any)["diary.picker"]
		XCTAssertTrue(picker.waitForExistence(timeout: 2))
		XCTAssertTrue(app.buttons["diary.create"].exists)

		app.buttons["diary.cancel"].click()

		XCTAssertFalse(picker.waitForExistence(timeout: 1))
		XCTAssertTrue(app.buttons["sidebar.entries"].waitForExistence(timeout: 2))
		XCTAssertTrue(app.descendants(matching: .any)["entry-list.scroll"].exists)
	}

	func testDiaryCreationCanOpenFromAndReturnToPicker() {
		let app = launchWorkspace()

		app.buttons["Diaries"].firstMatch.click()
		XCTAssertTrue(app.buttons["diary.create"].waitForExistence(timeout: 2))
		app.buttons["diary.create"].click()

		XCTAssertTrue(app.descendants(matching: .any)["diary.title"].waitForExistence(timeout: 2))
		app.buttons["Cancel"].firstMatch.click()
		XCTAssertTrue(app.descendants(matching: .any)["diary.picker"].waitForExistence(timeout: 2))
		app.buttons["diary.cancel"].click()
	}

	func testDropTargetsAreAccessibleFromWorkspace() {
		let app = launchWorkspace()

		XCTAssertTrue(app.buttons["sidebar.topic.fixture-topic"].waitForExistence(timeout: 2))
		XCTAssertTrue(app.buttons["sidebar.bookmarks"].exists)
		XCTAssertTrue(app.buttons["sidebar.archive"].exists)
		XCTAssertTrue(app.buttons["sidebar.trash"].exists)
	}

	func testEntryCanBeDraggedFromItsCenterToTrash() {
		let app = launchWorkspace()
		let entry = app.buttons["entry.fixture-entry"]
		let trash = app.buttons["sidebar.trash"]

		XCTAssertTrue(entry.waitForExistence(timeout: 2))
		entry.press(forDuration: 0.1, thenDragTo: trash)

		XCTAssertTrue(app.staticTexts["Move Entry to Trash?"].waitForExistence(timeout: 2))
	}

	func testTopicButtonOpensCreationForm() {
		let app = launchWorkspace()

		app.descendants(matching: .any)["topic.create"].click()

		XCTAssertTrue(app.descendants(matching: .any)["topic.title"].waitForExistence(timeout: 2))
		XCTAssertTrue(app.descendants(matching: .any)["topic.description"].exists)
		XCTAssertTrue(app.buttons["Create"].exists)
	}

	func testTopicsHeaderCollapsesAndExpandsItsRows() {
		let app = launchWorkspace()
		let header = app.buttons["topics.toggle"]
		let topic = app.buttons["sidebar.topic.fixture-topic"]

		XCTAssertTrue(header.waitForExistence(timeout: 2))
		XCTAssertTrue(topic.exists)

		header.click()
		XCTAssertFalse(topic.waitForExistence(timeout: 1))
		XCTAssertEqual(header.value as? String, "Collapsed")

		header.click()
		XCTAssertTrue(topic.waitForExistence(timeout: 2))
		XCTAssertEqual(header.value as? String, "Expanded")
	}

	func testEntryActionsAreAvailableFromRowAndEditorToolbar() {
		let app = launchWorkspace()
		let entry = app.descendants(matching: .any)["entry.fixture-entry"]

		entry.rightClick()
		XCTAssertTrue(app.menuItems["Bookmark"].waitForExistence(timeout: 2))
		XCTAssertTrue(app.menuItems["Archive"].exists)
		XCTAssertTrue(app.menuItems["Move to Trash"].exists)
		app.typeKey(.escape, modifierFlags: [])

		entry.click()
		let actions = app.descendants(matching: .any)["entry.actions"]
		XCTAssertTrue(actions.waitForExistence(timeout: 2))
		actions.click()
		XCTAssertTrue(app.menuItems["Bookmark"].waitForExistence(timeout: 2))
		XCTAssertTrue(app.menuItems["Archive"].exists)
		XCTAssertTrue(app.menuItems["Move to Trash"].exists)
	}

	func testNewEntryButtonOpensCreationForm() {
		let app = launchWorkspace()

		app.buttons["entry.create"].click()

		XCTAssertTrue(app.descendants(matching: .any)["entry.new-content"].waitForExistence(timeout: 2))
		XCTAssertTrue(app.buttons["Create"].exists)
	}

	func testMovingNonemptyEntryToTrashRequiresConfirmation() {
		let app = launchWorkspace()
		let entry = app.descendants(matching: .any)["entry.fixture-entry"]

		entry.rightClick()
		app.menuItems["Move to Trash"].click()

		XCTAssertTrue(app.staticTexts["Move Entry to Trash?"].waitForExistence(timeout: 2))
		XCTAssertTrue(app.buttons["Cancel"].exists)
	}

	func testEmptyTrashRequiresConfirmation() {
		let app = launchWorkspace()

		app.buttons["sidebar.trash"].click()
		app.buttons["trash.empty"].firstMatch.click()

		XCTAssertTrue(app.staticTexts["Empty Trash?"].waitForExistence(timeout: 2))
		XCTAssertTrue(app.buttons["Cancel"].exists)
	}

	func testDoubleClickingTopicOpensEditor() {
		let app = launchWorkspace()

		app.buttons["sidebar.topic.fixture-topic"].doubleClick()

		let title = app.descendants(matching: .any)["topic.title"]
		XCTAssertTrue(title.waitForExistence(timeout: 2))
		XCTAssertEqual(title.value as? String, "Work Topic")
	}
}
