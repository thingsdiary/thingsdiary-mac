import XCTest

extension XCUIElement {
	fileprivate func waitForValue(_ expectedValue: String, timeout: TimeInterval) -> Bool {
		let predicate = NSPredicate(format: "value == %@", expectedValue)
		let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
		return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
	}

	fileprivate func waitForNonExistence(timeout: TimeInterval) -> Bool {
		let predicate = NSPredicate(format: "exists == false")
		let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
		return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
	}
}

final class DiaryWorkspaceUITests: XCTestCase {
	override func tearDown() {
		XCUIApplication().terminate()
		super.tearDown()
	}

	private func launchWorkspace(additionalArguments: [String] = []) -> XCUIApplication {
		let app = XCUIApplication()
		app.launchArguments =
			[
				"-ApplePersistenceIgnoreState",
				"YES",
				"--ui-testing-workspace",
			] + additionalArguments
		app.launch()
		app.activate()
		let fixtureWindow = app.windows["Entries"]
		XCTAssertTrue(fixtureWindow.waitForExistence(timeout: 2))
		XCTAssertEqual(app.windows.count, 1)
		return app
	}

	private func typeText(_ text: String, into element: XCUIElement) {
		element.click()
		element.typeText(text)
	}

	private func filterEntries(
		in app: XCUIApplication,
		query: String = "19"
	) -> (search: XCUIElement, hiddenEntry: XCUIElement) {
		let workspace = app.dialogs.firstMatch.exists ? app.dialogs.firstMatch : app.windows.firstMatch
		let search = workspace.searchFields["Search Entries"]
		let hiddenEntry = workspace.descendants(matching: .any)["entry.fixture-entry"]
		let matchingEntry = workspace.descendants(matching: .any)["entry.fixture-entry-19"]

		XCTAssertTrue(search.waitForExistence(timeout: 2))
		XCTAssertTrue(hiddenEntry.waitForExistence(timeout: 2))
		app.activate()
		typeText(query, into: search)

		XCTAssertTrue(search.waitForValue(query, timeout: 2))
		XCTAssertTrue(matchingEntry.waitForExistence(timeout: 2))
		XCTAssertFalse(hiddenEntry.exists)
		return (search, hiddenEntry)
	}

	private func assertSearchIsCleared(
		_ search: XCUIElement,
		restoredEntry: XCUIElement
	) {
		XCTAssertTrue(search.waitForValue("", timeout: 2))
		XCTAssertTrue(restoredEntry.waitForExistence(timeout: 2))
	}

	private func workspace(in app: XCUIApplication) -> XCUIElement {
		let window = app.windows.firstMatch
		XCTAssertTrue(window.waitForExistence(timeout: 2))
		window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02)).click()
		return window
	}

	private func activate(_ workspace: XCUIElement) {
		workspace.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02)).click()
	}

	private func saveFromFileMenu(in app: XCUIApplication) {
		app.menuBars.menuBarItems["File"].click()
		let save = app.menuItems["Save"]
		XCTAssertTrue(save.waitForExistence(timeout: 2))
		XCTAssertTrue(save.isEnabled)
		save.click()
	}

	private func clearText(in editor: XCUIElement) {
		editor.click()
		editor.typeKey("a", modifierFlags: .command)
		editor.typeKey(.delete, modifierFlags: [])
	}

	private func showEntryListIfNeeded(in app: XCUIApplication) {
		let showEntryList = app.buttons["workspace.show-entry-list"].firstMatch
		if showEntryList.exists {
			showEntryList.click()
		}
	}

	private func openTopicMenu(for element: XCUIElement, app: XCUIApplication) {
		element.rightClick()
		let moveToTopic = app.menuItems["Move to Topic"]
		XCTAssertTrue(moveToTopic.waitForExistence(timeout: 2))
		moveToTopic.hover()
	}

	private func chooseTopic(
		_ title: String,
		for element: XCUIElement,
		app: XCUIApplication
	) {
		openTopicMenu(for: element, app: app)
		let topic = app.menuItems[title]
		XCTAssertTrue(topic.waitForExistence(timeout: 2))
		topic.click()
	}

	@discardableResult
	private func createAndSaveTemplate(_ content: String, app: XCUIApplication) -> XCUIElement {
		let workspace = workspace(in: app)
		workspace.buttons["sidebar.templates"].click()
		let newTemplateButton = workspace.buttons["template.create"]
		XCTAssertTrue(newTemplateButton.waitForExistence(timeout: 2))
		newTemplateButton.click()

		XCTAssertTrue(workspace.searchFields["Search Templates"].waitForExistence(timeout: 2))
		let tab = workspace.buttons.matching(
			NSPredicate(
				format: "identifier BEGINSWITH %@ AND NOT identifier BEGINSWITH %@",
				"template-tab.",
				"template-tab.close."
			)
		).firstMatch
		XCTAssertTrue(tab.waitForExistence(timeout: 2))
		let savedTab = workspace.buttons[tab.identifier]

		let editor = workspace.textViews["template.editor"]
		XCTAssertTrue(editor.waitForExistence(timeout: 2))
		typeText(content, into: editor)
		XCTAssertTrue(editor.waitForValue(content, timeout: 2))
		XCTAssertTrue(savedTab.waitForValue("Unsaved changes", timeout: 2))

		app.menuBars.menuBarItems["File"].click()
		app.menuItems["Save"].click()
		XCTAssertTrue(savedTab.waitForValue("Saved", timeout: 2))
		XCTAssertEqual(editor.value as? String, content)
		return savedTab
	}

	private func chooseDefaultTemplate(
		_ content: String,
		workspace: XCUIElement,
		app: XCUIApplication
	) {
		let picker = workspace.descendants(matching: .any)["topic.default-template"]
		XCTAssertTrue(picker.waitForExistence(timeout: 2))
		picker.click()
		let none = app.menuItems["None"]
		XCTAssertTrue(none.waitForExistence(timeout: 2))
		none.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
			.withOffset(CGVector(dx: 0, dy: none.frame.height))
			.click()
		XCTAssertEqual(picker.value as? String, content)
	}

	@discardableResult
	private func createTopic(
		_ title: String,
		app: XCUIApplication
	) -> XCUIElement {
		let topics = app.buttons["topics.toggle"].firstMatch
		XCTAssertTrue(topics.waitForExistence(timeout: 2))
		topics.hover()
		let createTopic = app.descendants(matching: .any)["topic.create"].firstMatch
		XCTAssertTrue(createTopic.waitForExistence(timeout: 2))
		createTopic.click()
		let titleField = app.textFields["topic.title"].firstMatch
		XCTAssertTrue(titleField.waitForExistence(timeout: 2))
		titleField.click()
		titleField.typeText(title)
		app.buttons["Create"].firstMatch.click()
		XCTAssertFalse(titleField.waitForExistence(timeout: 2))

		let topic = app.buttons.matching(
			NSPredicate(
				format: "identifier BEGINSWITH %@ AND NOT (identifier IN %@)",
				"sidebar.topic.",
				["sidebar.topic.fixture-topic", "sidebar.topic.fixture-topic-2"]
			)
		).firstMatch
		XCTAssertTrue(topic.waitForExistence(timeout: 2))
		return topic
	}

	private func newEntryDraft(in workspace: XCUIElement) -> String {
		workspace.buttons["entry.create"].click()
		let tab = workspace.buttons.matching(
			NSPredicate(
				format: "identifier BEGINSWITH %@ AND label == %@",
				"entry-tab.",
				"Untitled"
			)
		).firstMatch
		XCTAssertTrue(tab.waitForExistence(timeout: 2))
		return String(tab.identifier.dropFirst("entry-tab.".count))
	}

	private func closeEntryTab(
		_ entryID: String,
		app: XCUIApplication,
		discardUnsavedChanges: Bool = false
	) {
		let tab = app.buttons["entry-tab.\(entryID)"].firstMatch
		XCTAssertTrue(tab.waitForExistence(timeout: 2))
		tab.rightClick()
		let close = app.menuItems["Close"].firstMatch
		XCTAssertTrue(close.waitForExistence(timeout: 2))
		close.click()
		if discardUnsavedChanges {
			let discard = app.sheets.firstMatch.buttons["Don't Save"]
			XCTAssertTrue(discard.waitForExistence(timeout: 2))
			discard.click()
		}
		XCTAssertTrue(tab.waitForNonExistence(timeout: 2))
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

	func testNewWindowMenuOpensASeparateWindow() {
		let app = launchWorkspace()
		let initialWindowCount = app.windows.count
		XCTAssertGreaterThan(initialWindowCount, 0)

		app.menuBars.menuBarItems["File"].click()
		app.menuItems["New Window"].click()

		let newWindow = app.windows.element(boundBy: initialWindowCount)
		XCTAssertTrue(newWindow.waitForExistence(timeout: 2))
		XCTAssertEqual(app.windows.count, initialWindowCount + 1)
	}

	func testEntryListHeaderAndRowsUseSeparateContainers() {
		let app = launchWorkspace()
		let header = app.descendants(matching: .any)["entry-list.header"].firstMatch
		let rows = app.descendants(matching: .any)["entry-list.scroll"].firstMatch

		XCTAssertTrue(header.waitForExistence(timeout: 2))
		XCTAssertTrue(rows.waitForExistence(timeout: 2))
		XCTAssertFalse(header.frame.intersects(rows.frame))
		let search = app.searchFields["Search Entries"]
		XCTAssertTrue(search.exists)
		XCTAssertGreaterThan(search.frame.width, header.frame.width * 0.8)
		XCTAssertFalse(app.descendants(matching: .any)["entry-list.title"].exists)
		XCTAssertFalse(app.buttons["Newest"].exists)
		XCTAssertEqual(app.windows.firstMatch.title, "Entries")
	}

	func testAppBarBackgroundAndTitleDragWindow() {
		let app = launchWorkspace()
		let window = app.windows.firstMatch
		let listTitlebar = app.descendants(matching: .any)["entry-list.titlebar"].firstMatch
		XCTAssertTrue(listTitlebar.waitForExistence(timeout: 2))

		var originalOrigin = window.frame.origin
		let titleDragStart = listTitlebar.coordinate(
			withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)
		)
		titleDragStart.press(
			forDuration: 0.1,
			thenDragTo: titleDragStart.withOffset(CGVector(dx: 40, dy: 30))
		)
		XCTAssertNotEqual(window.frame.origin, originalOrigin)

		app.buttons["entry.fixture-entry"].click()
		let newTabButton = app.buttons["browser-tab.create"]
		XCTAssertTrue(newTabButton.waitForExistence(timeout: 2))

		let blankX = (newTabButton.frame.maxX + window.frame.maxX - 50) / 2
		let appBarYPositions = [
			newTabButton.frame.minY - 2,
			newTabButton.frame.midY,
			newTabButton.frame.maxY + 2,
		]

		for y in appBarYPositions {
			originalOrigin = window.frame.origin
			let dragStart = window.coordinate(withNormalizedOffset: .zero).withOffset(
				CGVector(dx: blankX - window.frame.minX, dy: y - window.frame.minY)
			)
			dragStart.press(
				forDuration: 0.1,
				thenDragTo: dragStart.withOffset(CGVector(dx: 20, dy: 10))
			)
			XCTAssertNotEqual(window.frame.origin, originalOrigin)
		}
	}

	func testSearchScopeChangesWhenSectionChanges() {
		let app = launchWorkspace()
		let workspace = app.dialogs.firstMatch.exists ? app.dialogs.firstMatch : app.windows.firstMatch
		let search = workspace.searchFields["Search Entries"]

		XCTAssertTrue(search.waitForExistence(timeout: 2))

		workspace.buttons["sidebar.archive"].click()
		let archiveSearch = workspace.searchFields["Search Archive"]
		XCTAssertTrue(archiveSearch.waitForExistence(timeout: 2))
		XCTAssertEqual(archiveSearch.value as? String, "")
		XCTAssertTrue(workspace.descendants(matching: .any)["entry.fixture-archived-entry"].exists)
		XCTAssertEqual(app.windows.firstMatch.title, "Archive")
	}

	func testSearchFiltersEntriesWhileTyping() {
		let app = launchWorkspace()
		_ = filterEntries(in: app)
	}

	func testDeletingSearchTextRestoresFilteredEntries() {
		let app = launchWorkspace()
		let (search, hiddenEntry) = filterEntries(in: app)

		for _ in 0..<2 {
			search.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
			search.typeKey(.delete, modifierFlags: [])
		}

		assertSearchIsCleared(search, restoredEntry: hiddenEntry)
	}

	func testEscapeClearsSearchAndRestoresFilteredEntries() {
		let app = launchWorkspace()
		let (search, hiddenEntry) = filterEntries(in: app)

		search.typeKey(.escape, modifierFlags: [])

		assertSearchIsCleared(search, restoredEntry: hiddenEntry)
	}

	func testSearchClearButtonRestoresFilteredEntries() {
		let app = launchWorkspace()
		let (search, hiddenEntry) = filterEntries(in: app)

		search.click()
		let clearButton = search.buttons["cancel"]
		XCTAssertTrue(clearButton.waitForExistence(timeout: 2))
		search.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).click()

		assertSearchIsCleared(search, restoredEntry: hiddenEntry)
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
			app.staticTexts["Create a new entry here or move an existing entry into this topic."].exists
		)
		XCTAssertTrue(app.buttons["New Entry"].exists)
		XCTAssertFalse(app.descendants(matching: .any)["entry-list.header"].exists)
		XCTAssertFalse(app.searchFields["Search Work Topic"].exists)
	}

	func testCreatingEntryInTopicKeepsTopicSelected() {
		let app = launchWorkspace()

		app.buttons["sidebar.topic.fixture-topic"].click()
		app.buttons["New Entry"].firstMatch.click()

		let editor = app.textViews["template.editor"]
		XCTAssertTrue(editor.waitForExistence(timeout: 2))
		editor.typeText("Topic draft")

		XCTAssertEqual(app.windows.firstMatch.title, "Work Topic")
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

	func testDraggingEntryTabReordersTabsWithoutMovingWindow() {
		let app = launchWorkspace()
		let window = app.windows.firstMatch

		app.buttons["entry.fixture-entry"].doubleClick()
		app.buttons["sidebar.archive"].click()
		app.descendants(matching: .any)["entry.fixture-archived-entry"].doubleClick()
		app.buttons["sidebar.trash"].click()
		app.descendants(matching: .any)["entry.fixture-deleted-entry"].click()

		let firstTab = app.descendants(matching: .any)["entry-tab.fixture-entry"]
		let secondTab = app.descendants(matching: .any)["entry-tab.fixture-archived-entry"]
		XCTAssertTrue(firstTab.waitForExistence(timeout: 2))
		XCTAssertTrue(secondTab.exists)
		let originalWindowFrame = window.frame

		secondTab.press(forDuration: 0.2, thenDragTo: firstTab)

		XCTAssertLessThan(secondTab.frame.minX, firstTab.frame.minX)
		XCTAssertEqual(window.frame.origin.x, originalWindowFrame.origin.x, accuracy: 1)
		XCTAssertEqual(window.frame.origin.y, originalWindowFrame.origin.y, accuracy: 1)
	}

	func testHeaderEntryListDividerResizesListWithoutMovingWindow() {
		let app = launchWorkspace()
		let window = app.windows.firstMatch
		app.buttons["entry.fixture-entry"].click()

		let headerDivider = app.descendants(matching: .any)[
			"workspace.entry-list-divider.header"
		].firstMatch
		XCTAssertTrue(headerDivider.waitForExistence(timeout: 2))

		let originalWindowOrigin = window.frame.origin
		let originalDividerXInWindow = headerDivider.frame.midX - window.frame.minX
		let start = headerDivider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
		let end = start.withOffset(CGVector(dx: 40, dy: 0))
		start.press(forDuration: 0.1, thenDragTo: end)

		let dividerXInWindow = headerDivider.frame.midX - window.frame.minX
		XCTAssertGreaterThan(dividerXInWindow, originalDividerXInWindow + 20)
		XCTAssertEqual(window.frame.origin.x, originalWindowOrigin.x, accuracy: 1)
		XCTAssertEqual(window.frame.origin.y, originalWindowOrigin.y, accuracy: 1)
	}

	func testEntryTabContextMenuOpensOutsideItsText() {
		let app = launchWorkspace()
		app.buttons["entry.fixture-entry"].click()

		let tab = app.descendants(matching: .any)["entry-tab.fixture-entry"]
		XCTAssertTrue(tab.waitForExistence(timeout: 2))

		tab.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5)).rightClick()

		XCTAssertTrue(app.menuItems["Close"].waitForExistence(timeout: 2))
		XCTAssertTrue(app.menuItems["Pin Tab"].exists)
	}

	func testEntryTabContextMenuOpensAtBottomEdge() {
		let app = launchWorkspace()
		app.buttons["entry.fixture-entry"].click()

		let tab = app.descendants(matching: .any)["entry-tab.fixture-entry"]
		XCTAssertTrue(tab.waitForExistence(timeout: 2))

		tab.coordinate(withNormalizedOffset: .zero)
			.withOffset(CGVector(dx: tab.frame.width / 2, dy: tab.frame.height - 1))
			.rightClick()

		XCTAssertTrue(app.menuItems["Close"].waitForExistence(timeout: 2))
		XCTAssertTrue(app.menuItems["Pin Tab"].exists)
	}

	func testEntryCanBeAddedToTopic() {
		let app = launchWorkspace()
		let entry = app.buttons["entry.fixture-entry"]
		XCTAssertTrue(entry.waitForExistence(timeout: 2))

		chooseTopic("Work Topic", for: entry, app: app)
		app.buttons["sidebar.topic.fixture-topic"].click()
		XCTAssertTrue(entry.waitForExistence(timeout: 2))
	}

	func testEntryCanMoveFromOneTopicToAnotherFromTabMenu() {
		let app = launchWorkspace()
		let entry = app.buttons["entry.fixture-entry"]
		XCTAssertTrue(entry.waitForExistence(timeout: 2))
		chooseTopic("Work Topic", for: entry, app: app)
		entry.click()

		let tab = app.descendants(matching: .any)["entry-tab.fixture-entry"]
		XCTAssertTrue(tab.waitForExistence(timeout: 2))
		chooseTopic("Personal Topic", for: tab, app: app)

		app.buttons["sidebar.topic.fixture-topic"].click()
		showEntryListIfNeeded(in: app)
		XCTAssertTrue(entry.waitForNonExistence(timeout: 2))
		app.buttons["sidebar.topic.fixture-topic-2"].click()
		XCTAssertTrue(entry.waitForExistence(timeout: 2))
	}

	func testEntryCanBeRemovedFromTopicFromTabMenu() {
		let app = launchWorkspace()
		let entry = app.buttons["entry.fixture-entry"]
		XCTAssertTrue(entry.waitForExistence(timeout: 2))
		chooseTopic("Work Topic", for: entry, app: app)
		entry.click()

		let tab = app.descendants(matching: .any)["entry-tab.fixture-entry"]
		XCTAssertTrue(tab.waitForExistence(timeout: 2))
		chooseTopic("No Topic", for: tab, app: app)

		app.buttons["sidebar.topic.fixture-topic"].click()
		showEntryListIfNeeded(in: app)
		XCTAssertTrue(entry.waitForNonExistence(timeout: 2))
		app.buttons["sidebar.entries"].click()
		XCTAssertTrue(entry.waitForExistence(timeout: 2))
	}

	func testEntryPreviewIsReusedAndPromotedOnSecondClick() {
		let app = launchWorkspace()

		app.buttons["entry.fixture-entry"].click()
		let firstTab = app.buttons["entry-tab.fixture-entry"]
		XCTAssertTrue(firstTab.waitForExistence(timeout: 2))
		XCTAssertEqual(firstTab.value as? String, "Preview, Saved")

		let showEntryList = app.buttons["workspace.show-entry-list"].firstMatch
		if showEntryList.exists {
			showEntryList.click()
		}
		app.buttons["entry.fixture-entry-2"].click()
		let secondTab = app.buttons["entry-tab.fixture-entry-2"]
		XCTAssertTrue(secondTab.waitForExistence(timeout: 2))
		XCTAssertFalse(firstTab.exists)
		XCTAssertEqual(secondTab.value as? String, "Preview, Saved")

		if showEntryList.exists {
			showEntryList.click()
		}
		app.buttons["entry.fixture-entry-2"].click()
		XCTAssertEqual(secondTab.value as? String, "Saved")
	}

	func testEntryTabActivatesWhenClickingOutsideItsText() {
		let app = launchWorkspace()
		app.buttons["entry.fixture-entry"].doubleClick()
		app.buttons["sidebar.archive"].click()
		app.descendants(matching: .any)["entry.fixture-archived-entry"].click()

		let firstTab = app.buttons["entry-tab.fixture-entry"]
		XCTAssertTrue(firstTab.waitForExistence(timeout: 2))

		firstTab.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5)).click()

		XCTAssertEqual(
			app.textViews.firstMatch.value as? String,
			"Fixture Entry\nA useful preview for UI testing."
		)
	}

	func testTopicButtonOpensCreationForm() {
		let app = launchWorkspace()
		let topics = app.buttons["topics.toggle"]
		XCTAssertTrue(topics.waitForExistence(timeout: 2))
		topics.hover()

		let createTopic = app.descendants(matching: .any)["topic.create"]
		XCTAssertTrue(createTopic.waitForExistence(timeout: 2))
		createTopic.click()

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

	func testEntryActionsStayInRowContextMenuAndAreHiddenFromEditorToolbar() {
		let app = launchWorkspace()
		let entries = app.descendants(matching: .any)
			.matching(identifier: "entry.fixture-entry")
			.allElementsBoundByIndex
		guard let entry = entries.first(where: \.isHittable) else {
			return XCTFail("Expected a visible fixture entry")
		}

		entry.rightClick()
		XCTAssertTrue(app.menuItems["Add Bookmark"].waitForExistence(timeout: 2))
		XCTAssertTrue(app.menuItems["Archive"].exists)
		XCTAssertTrue(app.menuItems["Move to Trash"].exists)
		app.typeKey(.escape, modifierFlags: [])

		entry.click()
		XCTAssertFalse(app.descendants(matching: .any)["entry.actions"].exists)
		XCTAssertFalse(app.buttons["Save"].exists)
	}

	func testNewEntryButtonCreatesDraftAndOpensEditor() {
		let app = launchWorkspace()
		let newEntryButton = app.buttons["New Entry"]

		XCTAssertTrue(newEntryButton.waitForExistence(timeout: 2))
		newEntryButton.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).click()

		XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 2))
		XCTAssertTrue(app.buttons["Untitled"].firstMatch.waitForExistence(timeout: 2))
		XCTAssertFalse(app.buttons["Create"].exists)
	}

	func testClosingEphemeralEntryCreatedInBookmarksDiscardsIt() {
		let app = launchWorkspace()
		let workspace = workspace(in: app)
		workspace.buttons["sidebar.bookmarks"].click()

		let draftID = newEntryDraft(in: workspace)
		XCTAssertEqual(app.windows.firstMatch.title, "Bookmarks")
		let editor = app.textViews["entry.editor"].firstMatch
		editor.click()
		editor.typeText("Discarded bookmark draft")
		let row = app.descendants(matching: .any)["entry.\(draftID)"].firstMatch

		closeEntryTab(
			draftID,
			app: app,
			discardUnsavedChanges: true
		)

		XCTAssertTrue(row.waitForNonExistence(timeout: 2))
		XCTAssertEqual(app.windows.firstMatch.title, "Bookmarks")
	}

	func testSavingEntryCreatedInBookmarksKeepsBookmarkedEntryAfterClosingTab() {
		let app = launchWorkspace()
		let workspace = workspace(in: app)
		workspace.buttons["sidebar.bookmarks"].click()

		let draftID = newEntryDraft(in: workspace)
		XCTAssertEqual(app.windows.firstMatch.title, "Bookmarks")
		let content = "Saved bookmark entry"
		let editor = app.textViews["entry.editor"].firstMatch
		editor.click()
		editor.typeText(content)
		app.typeKey("s", modifierFlags: .command)
		XCTAssertTrue(
			app.buttons["entry-tab.\(draftID)"].firstMatch.waitForValue("Saved", timeout: 2)
		)

		closeEntryTab(draftID, app: app)

		let row = app.descendants(matching: .any)["entry.\(draftID)"].firstMatch
		XCTAssertTrue(row.waitForExistence(timeout: 2))
		row.click()
		XCTAssertTrue(editor.waitForValue(content, timeout: 2))
		XCTAssertEqual(app.windows.firstMatch.title, "Bookmarks")
	}

	func testClosingEphemeralEntryCreatedInNewTopicDiscardsIt() {
		let app = launchWorkspace()
		let workspace = workspace(in: app)
		let topic = createTopic("Ephemeral Topic", app: app)
		let topicTitle = topic.label

		let draftID = newEntryDraft(in: workspace)
		XCTAssertEqual(app.windows.firstMatch.title, topicTitle)
		let editor = app.textViews["entry.editor"].firstMatch
		editor.click()
		editor.typeText("Discarded topic draft")
		let row = app.descendants(matching: .any)["entry.\(draftID)"].firstMatch

		closeEntryTab(
			draftID,
			app: app,
			discardUnsavedChanges: true
		)

		XCTAssertTrue(row.waitForNonExistence(timeout: 2))
		XCTAssertEqual(app.windows.firstMatch.title, topicTitle)
	}

	func testSavingEntryCreatedInNewTopicKeepsEntryAfterClosingTab() {
		let app = launchWorkspace()
		let workspace = workspace(in: app)
		let topic = createTopic("Saved Topic", app: app)
		let topicTitle = topic.label

		let draftID = newEntryDraft(in: workspace)
		XCTAssertEqual(app.windows.firstMatch.title, topicTitle)
		let content = "Saved topic entry"
		let editor = app.textViews["entry.editor"].firstMatch
		editor.click()
		editor.typeText(content)
		app.typeKey("s", modifierFlags: .command)
		XCTAssertTrue(
			app.buttons["entry-tab.\(draftID)"].firstMatch.waitForValue("Saved", timeout: 2)
		)

		closeEntryTab(draftID, app: app)

		let row = app.descendants(matching: .any)["entry.\(draftID)"].firstMatch
		XCTAssertTrue(row.waitForExistence(timeout: 2))
		row.click()
		XCTAssertTrue(editor.waitForValue(content, timeout: 2))
		XCTAssertEqual(app.windows.firstMatch.title, topicTitle)
	}

	func testEmptyEntryCanBeSavedAndLaterCleared() {
		let app = launchWorkspace()
		let workspace = workspace(in: app)
		workspace.buttons["entry.create"].click()

		let draftTab = workspace.buttons.matching(
			NSPredicate(
				format: "identifier BEGINSWITH %@ AND label == %@",
				"entry-tab.",
				"Untitled"
			)
		).firstMatch
		XCTAssertTrue(draftTab.waitForExistence(timeout: 2))
		let entryID = String(draftTab.identifier.dropFirst("entry-tab.".count))
		let editor = workspace.textViews["entry.editor"]
		XCTAssertEqual(editor.value as? String, "")

		saveFromFileMenu(in: app)
		XCTAssertTrue(draftTab.waitForValue("Saved", timeout: 2))
		typeText("x", into: editor)
		saveFromFileMenu(in: app)
		XCTAssertTrue(workspace.buttons["entry-tab.\(entryID)"].waitForValue("Saved", timeout: 2))

		clearText(in: editor)
		XCTAssertEqual(editor.value as? String, "")
		saveFromFileMenu(in: app)
		XCTAssertTrue(workspace.buttons["entry-tab.\(entryID)"].waitForValue("Saved", timeout: 2))

		workspace.buttons["entry-tab.\(entryID)"].hover()
		let closeButton = workspace.buttons["entry-tab.close.\(entryID)"]
		XCTAssertTrue(closeButton.waitForExistence(timeout: 2))
		closeButton.click()
		let row = workspace.descendants(matching: .any).matching(
			NSPredicate(
				format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
				"entry.",
				"Untitled"
			)
		).firstMatch
		XCTAssertTrue(row.waitForExistence(timeout: 2))
		row.click()
		XCTAssertEqual(editor.value as? String, "")
	}

	func testTabBarPlusCreatesDraftThatAppearsAfterTyping() {
		let app = launchWorkspace()
		app.buttons["entry.fixture-entry"].click()
		let newTabButton = app.buttons["browser-tab.create"]

		XCTAssertTrue(newTabButton.waitForExistence(timeout: 2))
		newTabButton.click()

		let editor = app.textViews.firstMatch
		XCTAssertTrue(editor.waitForExistence(timeout: 2))
		editor.typeText("Draft from tab")

		XCTAssertTrue(app.buttons["Draft from tab"].firstMatch.waitForExistence(timeout: 2))
	}

	func testTabBarPlusKeepsSpacingAfterNewDraft() {
		let app = launchWorkspace()
		app.buttons["entry.fixture-entry"].click()
		let newTabButton = app.buttons["browser-tab.create"]

		XCTAssertTrue(newTabButton.waitForExistence(timeout: 2))
		newTabButton.click()

		let draftTab = app.buttons["Untitled"].firstMatch
		XCTAssertTrue(draftTab.waitForExistence(timeout: 2))
		let gap = newTabButton.frame.minX - draftTab.frame.maxX
		XCTAssertGreaterThanOrEqual(gap, 7)
		XCTAssertLessThanOrEqual(gap, 9)
	}

	func testPinnedTabBarPlusKeepsSpacingAfterLastTab() {
		let app = launchWorkspace()

		for index in 1...8 {
			let entry = app.buttons["entry.fixture-entry\(index == 1 ? "" : "-\(index)")"]
			if !entry.exists {
				let showEntryList = app.buttons["workspace.show-entry-list"]
				XCTAssertTrue(showEntryList.waitForExistence(timeout: 2))
				showEntryList.click()
			}
			XCTAssertTrue(entry.waitForExistence(timeout: 2))
			entry.doubleClick()
		}

		let newTabButton = app.buttons["browser-tab.create"]
		let lastTab = app.descendants(matching: .any)["entry-tab.fixture-entry-8"]
		XCTAssertTrue(newTabButton.waitForExistence(timeout: 2))
		XCTAssertTrue(lastTab.waitForExistence(timeout: 2))
		XCTAssertTrue(lastTab.isHittable)

		let gap = newTabButton.frame.minX - lastTab.frame.maxX
		XCTAssertGreaterThanOrEqual(gap, 7)
		XCTAssertLessThanOrEqual(gap, 9)
	}

	func testPendingEntryKeepsSaveShortcutEnabledAfterFurtherEditing() {
		let app = launchWorkspace()
		app.buttons["entry.fixture-entry"].click()
		app.buttons["browser-tab.create"].click()

		let editor = app.textViews.firstMatch
		XCTAssertTrue(editor.waitForExistence(timeout: 2))
		editor.typeText("First edit")
		editor.typeText(" and more")

		app.menuBars.menuBarItems["File"].click()
		let saveItem = app.menuItems["Save"]
		XCTAssertTrue(saveItem.waitForExistence(timeout: 2))
		XCTAssertTrue(saveItem.isEnabled)
	}

	func testCommandAndControlSaveClearDirtyState() {
		let app = launchWorkspace()
		let workspace = app.dialogs.firstMatch.exists ? app.dialogs.firstMatch : app.windows.firstMatch
		workspace.buttons["entry.fixture-entry"].click()
		let editor = workspace.textViews.firstMatch
		let tab = workspace.buttons["entry-tab.fixture-entry"]
		XCTAssertTrue(editor.waitForExistence(timeout: 2))

		editor.click()
		editor.typeText(" Command edit")
		XCTAssertEqual(tab.value as? String, "Unsaved changes")
		app.typeKey("s", modifierFlags: .command)
		XCTAssertTrue(
			tab.waitForValue("Saved", timeout: 2)
		)

		editor.click()
		editor.typeText(" Control edit")
		XCTAssertEqual(tab.value as? String, "Unsaved changes")
		app.typeKey("s", modifierFlags: .control)
		XCTAssertTrue(
			tab.waitForValue("Saved", timeout: 2)
		)
	}

	func testClosingDirtyEntryCanBeCancelledOrDiscarded() {
		let app = launchWorkspace()
		app.buttons["entry.fixture-entry"].click()
		let editor = app.textViews.firstMatch
		let tab = app.buttons["entry-tab.fixture-entry"]
		let closeButton = app.buttons["entry-tab.close.fixture-entry"]

		XCTAssertTrue(editor.waitForExistence(timeout: 2))
		editor.click()
		editor.typeText(" Unsaved")
		XCTAssertTrue(tab.waitForExistence(timeout: 2))
		tab.hover()
		XCTAssertTrue(closeButton.waitForExistence(timeout: 2))
		closeButton.click()

		let closeAlert = app.sheets.firstMatch
		XCTAssertTrue(closeAlert.buttons["Don't Save"].waitForExistence(timeout: 2))
		closeAlert.buttons["Cancel"].click()
		tab.hover()
		XCTAssertTrue(closeButton.waitForExistence(timeout: 2))

		closeButton.click()
		XCTAssertTrue(closeAlert.buttons["Don't Save"].waitForExistence(timeout: 2))
		closeAlert.buttons["Don't Save"].click()
		XCTAssertFalse(closeButton.waitForExistence(timeout: 1))

		app.buttons["entry.fixture-entry"].click()
		XCTAssertEqual(
			app.textViews.firstMatch.value as? String,
			"Fixture Entry\nA useful preview for UI testing."
		)
	}

	func testCloseOtherTabsContinuesAfterSavingDirtyTab() {
		let app = launchWorkspace()
		app.buttons["entry.fixture-entry"].click()
		let dirtyTab = app.buttons["entry-tab.fixture-entry"]
		let editor = app.textViews.firstMatch
		XCTAssertTrue(editor.waitForExistence(timeout: 2))
		editor.click()
		editor.typeText(" Saved before bulk close")

		app.buttons["sidebar.archive"].click()
		app.descendants(matching: .any)["entry.fixture-archived-entry"].doubleClick()
		let followingTab = app.buttons["entry-tab.fixture-archived-entry"]
		app.buttons["sidebar.trash"].click()
		app.descendants(matching: .any)["entry.fixture-deleted-entry"].click()
		let keptTab = app.buttons["entry-tab.fixture-deleted-entry"]

		XCTAssertTrue(dirtyTab.exists)
		XCTAssertTrue(followingTab.exists)
		XCTAssertTrue(keptTab.waitForExistence(timeout: 2))
		keptTab.rightClick()
		app.menuItems["Close Other Tabs"].click()

		let closeAlert = app.sheets.firstMatch
		XCTAssertTrue(closeAlert.buttons["Save"].waitForExistence(timeout: 2))
		closeAlert.buttons["Save"].click()

		XCTAssertFalse(dirtyTab.waitForExistence(timeout: 2))
		XCTAssertFalse(followingTab.exists)
		XCTAssertTrue(keptTab.exists)
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
		let emptyTrash = app.windows.firstMatch.buttons["Empty Trash"].firstMatch
		XCTAssertTrue(emptyTrash.waitForExistence(timeout: 2))
		emptyTrash.click()

		XCTAssertTrue(app.staticTexts["Empty Trash?"].waitForExistence(timeout: 2))
		XCTAssertTrue(app.buttons["Cancel"].exists)
	}

	func testTrashContextMenuDisablesEmptyTrashWhenTrashIsEmpty() {
		let app = launchWorkspace()
		let trash = app.buttons["sidebar.trash"]

		trash.rightClick()
		let emptyTrash = app.menuItems["Empty Trash"]
		XCTAssertTrue(emptyTrash.waitForExistence(timeout: 2))
		XCTAssertTrue(emptyTrash.isEnabled)
		emptyTrash.click()

		XCTAssertTrue(app.staticTexts["Empty Trash?"].waitForExistence(timeout: 2))
		app.sheets.firstMatch.buttons["Cancel"].click()
		app.terminate()

		let emptyApp = launchWorkspace(additionalArguments: ["--ui-testing-empty-trash"])
		emptyApp.buttons["sidebar.trash"].rightClick()
		let disabledEmptyTrash = emptyApp.menuItems["Empty Trash"]
		XCTAssertTrue(disabledEmptyTrash.waitForExistence(timeout: 2))
		XCTAssertFalse(disabledEmptyTrash.isEnabled)
	}

	func testDoubleClickingTopicOpensEditor() {
		let app = launchWorkspace()

		app.buttons["sidebar.topic.fixture-topic"].doubleClick()

		let title = app.descendants(matching: .any)["topic.title"]
		XCTAssertTrue(title.waitForExistence(timeout: 2))
		XCTAssertEqual(title.value as? String, "Work Topic")
	}

	func testCreatingEditingAndSavingTemplate() {
		let app = launchWorkspace()
		let workspace = workspace(in: app)
		let content = "x"

		createAndSaveTemplate(content, app: app)

		XCTAssertEqual(workspace.textViews["template.editor"].value as? String, content)
	}

	func testEmptyTemplateCanBeSavedAndLaterCleared() {
		let app = launchWorkspace()
		let workspace = workspace(in: app)
		workspace.buttons["sidebar.templates"].click()
		workspace.buttons["template.create"].click()

		let draftTab = workspace.buttons.matching(
			NSPredicate(
				format: "identifier BEGINSWITH %@ AND label == %@",
				"template-tab.",
				"Untitled Template"
			)
		).firstMatch
		XCTAssertTrue(draftTab.waitForExistence(timeout: 2))
		let templateID = String(draftTab.identifier.dropFirst("template-tab.".count))
		let row = workspace.buttons["template.\(templateID)"]
		let editor = workspace.textViews["template.editor"]
		XCTAssertEqual(editor.value as? String, "")

		saveFromFileMenu(in: app)
		XCTAssertTrue(draftTab.waitForValue("Saved", timeout: 2))
		typeText("x", into: editor)
		saveFromFileMenu(in: app)
		let savedTab = workspace.buttons["template-tab.\(templateID)"]
		XCTAssertTrue(savedTab.waitForValue("Saved", timeout: 2))

		clearText(in: editor)
		XCTAssertEqual(editor.value as? String, "")
		saveFromFileMenu(in: app)
		XCTAssertTrue(savedTab.waitForValue("Saved", timeout: 2))

		savedTab.hover()
		let closeButton = workspace.buttons["template-tab.close.\(templateID)"]
		XCTAssertTrue(closeButton.waitForExistence(timeout: 2))
		closeButton.click()
		row.click()
		XCTAssertEqual(editor.value as? String, "")
	}

	func testClosingUntitledTemplateDiscardsIt() {
		let app = launchWorkspace()
		let workspace = workspace(in: app)
		workspace.buttons["sidebar.templates"].click()
		workspace.buttons["template.create"].click()

		let template = workspace.buttons.matching(
			NSPredicate(
				format: "identifier BEGINSWITH %@ AND identifier != %@ AND identifier != %@",
				"template.",
				"template.create",
				"template.empty-create"
			)
		).firstMatch
		XCTAssertTrue(template.waitForExistence(timeout: 2))

		let templateID = String(template.identifier.dropFirst("template.".count))
		let templateRow = workspace.buttons["template.\(templateID)"]
		workspace.buttons["template-tab.close.\(templateID)"].click()

		XCTAssertTrue(templateRow.waitForNonExistence(timeout: 2))
		XCTAssertTrue(workspace.descendants(matching: .any)["template.empty-state"].exists)
	}

	func testNewTopicUsesSelectedTemplateForNewEntry() {
		let app = launchWorkspace()
		let workspace = workspace(in: app)
		let content = "n"
		createAndSaveTemplate(content, app: app)

		activate(workspace)
		workspace.buttons["topic.create"].click()
		let title = workspace.textFields["topic.title"]
		XCTAssertTrue(title.waitForExistence(timeout: 2))
		title.typeText("t")
		chooseDefaultTemplate(content, workspace: workspace, app: app)
		workspace.buttons["Create"].click()

		XCTAssertFalse(title.waitForExistence(timeout: 2))
		workspace.buttons["entry.create"].click()

		let editor = workspace.textViews["entry.editor"]
		XCTAssertTrue(editor.waitForExistence(timeout: 2))
		XCTAssertEqual(editor.value as? String, content)
	}

	func testExistingTopicUsesTemplateAddedWhileEditing() {
		let app = launchWorkspace()
		let workspace = workspace(in: app)
		let content = "e"
		createAndSaveTemplate(content, app: app)

		activate(workspace)
		let topic = workspace.buttons["sidebar.topic.fixture-topic"]
		topic.click()
		topic.doubleClick()
		let title = workspace.textFields["topic.title"]
		XCTAssertTrue(title.waitForExistence(timeout: 2))
		chooseDefaultTemplate(content, workspace: workspace, app: app)
		workspace.buttons["Save"].click()

		XCTAssertFalse(title.waitForExistence(timeout: 2))
		workspace.buttons["entry.create"].click()

		let editor = workspace.textViews["entry.editor"]
		XCTAssertTrue(editor.waitForExistence(timeout: 2))
		XCTAssertEqual(editor.value as? String, content)
	}

	func testDeletingTemplateClearsTopicDefaultAndNewEntryStartsEmpty() {
		let app = launchWorkspace()
		let workspace = workspace(in: app)
		let content = "d"
		createAndSaveTemplate(content, app: app)

		activate(workspace)
		let topic = workspace.buttons["sidebar.topic.fixture-topic"]
		topic.doubleClick()
		let title = workspace.textFields["topic.title"]
		XCTAssertTrue(title.waitForExistence(timeout: 2))
		chooseDefaultTemplate(content, workspace: workspace, app: app)
		workspace.buttons["Save"].click()
		XCTAssertFalse(title.waitForExistence(timeout: 2))

		workspace.buttons["sidebar.templates"].click()
		let template = workspace.buttons.matching(
			NSPredicate(
				format: "identifier BEGINSWITH %@ AND identifier != %@ AND identifier != %@",
				"template.",
				"template.create",
				"template.empty-create"
			)
		).firstMatch
		XCTAssertTrue(template.waitForExistence(timeout: 2))
		template.rightClick()
		let deleteTemplate = app.menuItems["Delete Template"]
		XCTAssertTrue(deleteTemplate.waitForExistence(timeout: 2))
		deleteTemplate.click()
		let confirmation = app.staticTexts["Delete Template?"]
		XCTAssertTrue(confirmation.waitForExistence(timeout: 2))
		app.sheets.firstMatch.buttons["Delete"].click()

		topic.doubleClick()
		let defaultTemplate = workspace.descendants(matching: .any)["topic.default-template"]
		XCTAssertTrue(defaultTemplate.waitForExistence(timeout: 2))
		XCTAssertEqual(defaultTemplate.value as? String, "None")
		workspace.buttons["Cancel"].click()
		XCTAssertFalse(defaultTemplate.waitForExistence(timeout: 2))

		topic.click()
		workspace.buttons["entry.create"].click()
		let editor = workspace.textViews["entry.editor"]
		XCTAssertTrue(editor.waitForExistence(timeout: 2))
		XCTAssertEqual(editor.value as? String, "")
	}

	func testNewEntryTabImmediatelyShowsUntitledInListAndTabWithEmptyEditor() {
		let app = launchWorkspace()
		let workspace = workspace(in: app)
		workspace.buttons["entry.fixture-entry"].click()
		let newEntryTab = app.buttons["browser-tab.create"]
		XCTAssertTrue(newEntryTab.waitForExistence(timeout: 2))
		newEntryTab.click()
		app.buttons["Hide Sidebar"].firstMatch.click()

		let untitledRow = workspace.descendants(matching: .any).matching(
			NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "entry.", "Untitled")
		).firstMatch
		let untitledTab = workspace.buttons.matching(
			NSPredicate(
				format: "identifier BEGINSWITH %@ AND label == %@",
				"entry-tab.",
				"Untitled"
			)
		).firstMatch
		let editor = workspace.textViews["entry.editor"]

		XCTAssertTrue(untitledRow.waitForExistence(timeout: 2))
		XCTAssertTrue(untitledTab.waitForExistence(timeout: 2))
		XCTAssertTrue(editor.waitForExistence(timeout: 2))
		XCTAssertEqual(editor.value as? String, "")
	}
}
