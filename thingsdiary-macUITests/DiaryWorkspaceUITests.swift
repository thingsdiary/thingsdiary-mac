import XCTest

final class DiaryWorkspaceUITests: XCTestCase {
	override func tearDown() {
		XCUIApplication().terminate()
		super.tearDown()
	}

	private func launchWorkspace() -> XCUIApplication {
		let app = XCUIApplication()
		app.launchArguments = ["--ui-testing-workspace"]
		app.launch()
		return app
	}

	func testSidebarChangesEntrySection() {
		let app = launchWorkspace()

		app.buttons["sidebar.bookmarks"].click()
		XCTAssertTrue(app.staticTexts["No Bookmarks Yet"].waitForExistence(timeout: 2))
		XCTAssertTrue(app.descendants(matching: .any)["entry-list.empty-state"].exists)
		XCTAssertFalse(app.descendants(matching: .any)["entry-list.header"].exists)

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

	func testOverviewColumnStaysHiddenInCompactWorkspace() {
		let app = launchWorkspace()
		let overview = app.descendants(matching: .any)["diary.overview"]

		XCTAssertFalse(overview.waitForExistence(timeout: 1))
		XCTAssertEqual(app.splitters.count, 1)

		app.buttons["sidebar.bookmarks"].click()
		XCTAssertFalse(overview.waitForExistence(timeout: 1))
		XCTAssertEqual(app.splitters.count, 1)
		XCTAssertEqual(
			app.splitGroups.firstMatch.frame.width,
			app.windows.firstMatch.frame.width,
			accuracy: 2
		)
		app.buttons["sidebar.archive"].click()
		XCTAssertFalse(overview.waitForExistence(timeout: 1))
		XCTAssertEqual(app.splitters.count, 1)
	}

	func testEditorPriorityAndManualFocusMode() {
		let app = launchWorkspace()
		let entryList = app.descendants(matching: .any)["entry-list.scroll"]
		let editor = app.descendants(matching: .any)["entry.editor"]

		app.buttons["entry.fixture-entry"].click()
		XCTAssertTrue(editor.waitForExistence(timeout: 2))
		XCTAssertFalse(entryList.exists)

		app.buttons["workspace.show-entry-list"].firstMatch.click()
		XCTAssertTrue(entryList.waitForExistence(timeout: 2))
		XCTAssertFalse(editor.exists)
		app.buttons["workspace.show-editor"].firstMatch.click()
		XCTAssertTrue(editor.waitForExistence(timeout: 2))

		app.buttons["Hide Sidebar"].firstMatch.click()
		XCTAssertTrue(entryList.waitForExistence(timeout: 2))
		XCTAssertTrue(editor.exists)

		app.buttons["workspace.focus-editor"].firstMatch.click()
		XCTAssertFalse(entryList.waitForExistence(timeout: 1))
		XCTAssertTrue(editor.exists)
		app.buttons["workspace.exit-editor-focus"].firstMatch.click()
		XCTAssertTrue(entryList.waitForExistence(timeout: 2))
		XCTAssertTrue(editor.exists)

		app.buttons["Show Sidebar"].firstMatch.click()
		XCTAssertFalse(entryList.waitForExistence(timeout: 1))
		XCTAssertTrue(editor.exists)
	}

	func testEmptyTopicExplainsHowToAddEntriesWithoutListControls() {
		let app = launchWorkspace()

		app.buttons["sidebar.topic.fixture-topic"].click()

		XCTAssertTrue(app.staticTexts["No Entries in This Topic"].waitForExistence(timeout: 2))
		XCTAssertTrue(
			app.staticTexts["Move an existing entry into this topic to keep related writing together."].exists
		)
		XCTAssertTrue(app.buttons["Browse Entries"].exists)
		XCTAssertFalse(app.descendants(matching: .any)["entry-list.header"].exists)
	}

	func testDiaryMenuClosesWithoutLeavingWorkspace() {
		let app = launchWorkspace()

		let switcher = app.buttons["diary.switcher"]
		XCTAssertTrue(switcher.waitForExistence(timeout: 2))
		switcher.click()

		let selectedDiary = app.buttons["diary.switch.fixture-diary"]
		XCTAssertTrue(selectedDiary.waitForExistence(timeout: 2))
		XCTAssertTrue(app.buttons["diary.create"].exists)
		XCTAssertEqual(
			selectedDiary.value as? String,
			"Selected"
		)

		switcher.click()

		XCTAssertFalse(selectedDiary.waitForExistence(timeout: 1))
		XCTAssertTrue(app.buttons["sidebar.entries"].waitForExistence(timeout: 2))
		XCTAssertTrue(app.descendants(matching: .any)["entry-list.scroll"].exists)
	}

	func testDiaryCreationCanOpenFromSwitcherAndReturnToWorkspace() {
		let app = launchWorkspace()

		app.buttons["diary.switcher"].click()
		XCTAssertTrue(app.buttons["diary.create"].waitForExistence(timeout: 2))
		app.buttons["diary.create"].click()

		let titleField = app.descendants(matching: .any)["diary.title"]
		XCTAssertTrue(titleField.waitForExistence(timeout: 2))
		app.buttons["Cancel"].firstMatch.click()
		XCTAssertTrue(app.buttons["diary.switcher"].waitForExistence(timeout: 2))
		XCTAssertTrue(app.buttons["sidebar.entries"].exists)
	}

	func testDiarySettingsAppearOnHover() {
		let app = launchWorkspace()

		app.buttons["diary.switcher"].click()
		let diaryRow = app.buttons["diary.switch.fixture-diary"]
		XCTAssertTrue(diaryRow.waitForExistence(timeout: 2))
		diaryRow.hover()

		let settings = app.buttons["diary.settings.fixture-diary"]
		XCTAssertTrue(settings.waitForExistence(timeout: 2))
		settings.click()

		XCTAssertTrue(app.staticTexts["Topics & Templates"].waitForExistence(timeout: 2))
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
		let chevron = app.buttons["topics.chevron"]
		let topic = app.buttons["sidebar.topic.fixture-topic"]

		XCTAssertTrue(header.waitForExistence(timeout: 2))
		XCTAssertTrue(chevron.exists)
		XCTAssertTrue(topic.exists)

		header.click()
		XCTAssertFalse(topic.waitForExistence(timeout: 1))
		XCTAssertEqual(header.value as? String, "Collapsed")

		chevron.click()
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
		let newEntryButton = app.buttons["entry.create"]

		XCTAssertTrue(newEntryButton.waitForExistence(timeout: 2))
		newEntryButton.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).click()

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
