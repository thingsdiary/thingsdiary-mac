import AppKit
import Carbon.HIToolbox
import XCTest

final class MultiselectionUITests: XCTestCase {
	private var launchedApp: XCUIApplication?
	private var originalInputSource: TISInputSource?

	override func setUp() {
		super.setUp()
		continueAfterFailure = false
		originalInputSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
		let filter = [kTISPropertyInputSourceID as String: "com.apple.keylayout.ABC"] as CFDictionary
		guard let source = (TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource])?.first
		else {
			XCTFail("ABC keyboard input source is unavailable")
			return
		}
		XCTAssertEqual(TISSelectInputSource(source), noErr)
	}

	override func tearDown() {
		launchedApp?.terminate()
		launchedApp = nil
		if let originalInputSource { TISSelectInputSource(originalInputSource) }
		originalInputSource = nil
		super.tearDown()
	}

	private func launchWorkspace(arguments: [String] = []) -> XCUIApplication {
		let app = XCUIApplication()
		launchedApp = app
		app.launchArguments =
			[
				"-ApplePersistenceIgnoreState", "YES", "--ui-testing-workspace",
			] + arguments
		app.launch()
		if !app.windows.firstMatch.waitForExistence(timeout: 3) {
			app.menuBars.menuBarItems["File"].click()
			app.menuItems["New Window"].click()
		}
		XCTAssertTrue(app.windows["Entries"].waitForExistence(timeout: 5))
		return app
	}

	private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
		app.descendants(matching: .any).matching(identifier: identifier).firstMatch
	}

	private func showList(in app: XCUIApplication) {
		app.activate()
		let button = app.buttons["workspace.show-entry-list"].firstMatch
		if button.exists && button.isHittable {
			waitUntil { button.isEnabled }
			button.click()
		}
	}

	private func showDetail(in app: XCUIApplication) {
		app.activate()
		let button = app.buttons["workspace.show-editor"].firstMatch
		if button.exists && button.isHittable {
			waitUntil { button.isEnabled }
			button.click()
		}
	}

	private func entry(_ index: Int, in app: XCUIApplication) -> XCUIElement {
		element(index == 1 ? "entry.fixture-entry" : "entry.fixture-entry-\(index)", in: app)
	}

	private func clickEntry(
		_ index: Int,
		in app: XCUIApplication,
		modifiers: XCUIElement.KeyModifierFlags = []
	) {
		showList(in: app)
		let row = entry(index, in: app)
		XCTAssertTrue(row.waitForExistence(timeout: 5))
		XCUIElement.perform(withKeyModifiers: modifiers) { row.click() }
	}

	private func sendShortcut(_ key: String, modifiers: XCUIElement.KeyModifierFlags, in app: XCUIApplication) {
		app.activate()
		app.typeKey(key, modifierFlags: modifiers)
		Thread.sleep(forTimeInterval: 0.2)
	}

	private func enterDraft(_ text: String, into editor: XCUIElement, in app: XCUIApplication) {
		editor.click()
		waitUntil { NSPredicate(format: "hasKeyboardFocus == true").evaluate(with: editor) }
		app.menuBars.menuBarItems["Edit"].click()
		app.menuItems["Select All"].click()
		var start = text.startIndex
		while start < text.endIndex {
			let end = text.index(start, offsetBy: 4, limitedBy: text.endIndex) ?? text.endIndex
			editor.typeText(String(text[start..<end]))
			Thread.sleep(forTimeInterval: 0.1)
			start = end
		}
		waitUntil { editor.value as? String == text }
	}

	private func waitUntil(
		_ condition: @escaping () -> Bool,
		timeout: TimeInterval = 5,
		file: StaticString = #filePath,
		line: UInt = #line
	) {
		let predicate = NSPredicate { _, _ in condition() }
		let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
		XCTAssertEqual(
			XCTWaiter.wait(for: [expectation], timeout: timeout), .completed,
			file: file, line: line
		)
	}

	private func assertBulkCount(
		_ count: Int,
		kind: String = "entries",
		in app: XCUIApplication,
		file: StaticString = #filePath,
		line: UInt = #line
	) {
		showDetail(in: app)
		let overview = element("bulk.overview", in: app)
		let overviewExists = overview.waitForExistence(timeout: 5)
		if !overviewExists {
			let attachment = XCTAttachment(string: app.debugDescription)
			attachment.name = "Missing bulk overview for \(count) selected \(kind)"
			attachment.lifetime = .keepAlways
			add(attachment)
		}
		XCTAssertTrue(overviewExists, file: file, line: line)
		guard overviewExists else { return }
		let label = element("bulk.count", in: app)
		waitUntil(
			{ label.exists && ((label.value as? String) ?? label.label) == "\(count) \(kind) selected" },
			file: file, line: line
		)
	}

	private func assertSelectedEntry(
		_ index: Int,
		in app: XCUIApplication,
		file: StaticString = #filePath,
		line: UInt = #line
	) {
		showList(in: app)
		let identifier = index == 1 ? "entry.fixture-entry" : "entry.fixture-entry-\(index)"
		let row = app.descendants(matching: .outlineRow)
			.containing(.any, identifier: identifier).firstMatch
		waitUntil({ row.exists && row.isSelected }, file: file, line: line)
	}

	func testShiftClickSelectsEveryEntryInDownwardRange() {
		let app = launchWorkspace()
		clickEntry(1, in: app)
		clickEntry(4, in: app, modifiers: .shift)

		assertBulkCount(4, in: app)
		for index in 1...4 { assertSelectedEntry(index, in: app) }
		showDetail(in: app)
		XCTAssertTrue(app.buttons["bulk.action.bookmark"].exists)
		XCTAssertFalse(app.buttons["bulk.action.archive"].exists)
		XCTAssertLessThan(app.buttons["bulk.action.bookmark"].frame.minY, app.buttons["bulk.action.topic"].frame.minY)
		XCTAssertTrue(app.buttons["bulk.action.trash"].exists)
		XCTAssertFalse(app.textViews["entry.editor"].exists)
	}

	func testShiftClickSelectsUpwardAndContractsAroundOriginalAnchor() {
		let app = launchWorkspace()
		clickEntry(5, in: app)
		clickEntry(2, in: app, modifiers: .shift)
		assertBulkCount(4, in: app)
		for index in 2...5 { assertSelectedEntry(index, in: app) }

		clickEntry(4, in: app, modifiers: .shift)
		assertBulkCount(2, in: app)
		assertSelectedEntry(4, in: app)
		assertSelectedEntry(5, in: app)
	}

	func testCommandDeselectReturnsFromThreeEntriesToOneWithoutLosingDraft() {
		let app = launchWorkspace()
		clickEntry(1, in: app)
		showDetail(in: app)
		let editor = app.textViews["entry.editor"]
		XCTAssertTrue(editor.waitForExistence(timeout: 5))
		enterDraft("Unsaved draft preserved across multiselection", into: editor, in: app)

		clickEntry(3, in: app, modifiers: .shift)
		assertBulkCount(3, in: app)
		clickEntry(2, in: app, modifiers: .command)
		assertBulkCount(2, in: app)
		clickEntry(3, in: app, modifiers: .command)

		showDetail(in: app)
		waitUntil { !self.element("bulk.overview", in: app).exists }
		waitUntil { editor.exists && editor.value as? String == "Unsaved draft preserved across multiselection" }
		XCTAssertTrue(app.buttons["entry-tab.fixture-entry"].exists)
	}

	func testRepeatedShiftDownArrowExtendsSelectionWithNativeKeyboardFocus() {
		let app = launchWorkspace()
		clickEntry(1, in: app)
		sendShortcut(XCUIKeyboardKey.downArrow.rawValue, modifiers: .shift, in: app)
		sendShortcut(XCUIKeyboardKey.downArrow.rawValue, modifiers: .shift, in: app)

		assertBulkCount(3, in: app)
		for index in 1...3 { assertSelectedEntry(index, in: app) }
	}

	func testCommandASelectsVisibleEntriesAndFilteringPrunesHiddenSelection() {
		let app = launchWorkspace()
		clickEntry(1, in: app)
		sendShortcut("a", modifiers: .command, in: app)
		assertBulkCount(19, in: app)

		showList(in: app)
		let search = app.searchFields["Search Entries"]
		XCTAssertTrue(search.waitForExistence(timeout: 5))
		search.click()
		search.typeText("19")
		XCTAssertTrue(entry(19, in: app).waitForExistence(timeout: 5))
		waitUntil { !self.entry(1, in: app).exists }
		showDetail(in: app)
		waitUntil { !self.element("bulk.overview", in: app).exists }
		let editor = app.textViews["entry.editor"]
		waitUntil { editor.exists && editor.value as? String == "Fixture Entry 19\nSample note 19 for UI testing." }
	}

	func testSelectedRowContextMenuDuplicatesWholeSetAndSaveAsTemplateKeepsSourcesSelected() {
		let app = launchWorkspace()
		clickEntry(1, in: app)
		clickEntry(3, in: app, modifiers: .shift)
		assertBulkCount(3, in: app)
		showList(in: app)
		entry(2, in: app).rightClick()
		let duplicate = app.menuItems["Duplicate"]
		XCTAssertTrue(duplicate.waitForExistence(timeout: 5))
		let originalCount = app.descendants(matching: .outlineRow).count
		duplicate.click()
		waitUntil { app.descendants(matching: .outlineRow).count == originalCount + 3 }
		assertBulkCount(3, in: app)
		for index in 1...3 { assertSelectedEntry(index, in: app) }

		showDetail(in: app)
		XCTAssertFalse(app.buttons["bulk.action.save-as-template"].exists)
		app.popUpButtons["bulk.action.more"].click()
		let saveAsTemplate = app.menuItems["Save as Template"]
		XCTAssertTrue(saveAsTemplate.waitForExistence(timeout: 5))
		saveAsTemplate.click()
		waitUntil { app.buttons["bulk.action.topic"].isEnabled }
		XCTAssertFalse(element("bulk.result", in: app).exists)
		assertBulkCount(3, in: app)
		showList(in: app)
		XCTAssertTrue(app.searchFields["Search Entries"].exists)
		app.buttons["sidebar.templates"].click()
		let templateRows = app.descendants(matching: .outlineRow).containing(
			NSPredicate(format: "identifier BEGINSWITH %@", "template.")
		)
		waitUntil { templateRows.count == 3 }
	}

	func testUnselectedRowContextMenuActsOnOnlyItsTarget() {
		let app = launchWorkspace()
		clickEntry(1, in: app)
		clickEntry(3, in: app, modifiers: .shift)
		assertBulkCount(3, in: app)
		showList(in: app)
		entry(5, in: app).rightClick()
		let duplicate = app.menuItems["Duplicate"]
		XCTAssertTrue(duplicate.waitForExistence(timeout: 5))
		let originalCount = app.descendants(matching: .outlineRow).count
		duplicate.click()
		waitUntil { app.descendants(matching: .outlineRow).count == originalCount + 1 }
		assertBulkCount(3, in: app)
		for index in 1...3 { assertSelectedEntry(index, in: app) }
	}

	func testTemplatesUseNativeRangeSelectionAndOnlyTemplateActions() {
		let app = launchWorkspace(arguments: ["--ui-testing-multiple-templates"])
		app.buttons["sidebar.templates"].click()
		let first = element("template.fixture-template", in: app)
		XCTAssertTrue(first.waitForExistence(timeout: 5))
		first.click()
		showList(in: app)
		let third = element("template.fixture-template-3", in: app)
		XCTAssertTrue(third.waitForExistence(timeout: 5))
		XCUIElement.perform(withKeyModifiers: .shift) { third.click() }

		assertBulkCount(3, kind: "templates", in: app)
		XCTAssertTrue(app.buttons["bulk.action.duplicate"].exists)
		XCTAssertTrue(app.buttons["bulk.action.delete-templates"].exists)
		XCTAssertFalse(app.buttons["bulk.action.archive"].exists)
		XCTAssertFalse(app.buttons["bulk.action.topic"].exists)
		XCTAssertFalse(app.buttons["bulk.action.trash"].exists)
	}

	func testEscapeFromMultipleSelectionRestoresExistingPreviewDocument() {
		let app = launchWorkspace()
		clickEntry(1, in: app)
		clickEntry(4, in: app, modifiers: .shift)
		assertBulkCount(4, in: app)
		showList(in: app)
		sendShortcut(XCUIKeyboardKey.escape.rawValue, modifiers: [], in: app)
		showDetail(in: app)
		waitUntil { app.textViews["entry.editor"].exists }
		XCTAssertTrue((app.textViews["entry.editor"].value as? String)?.hasPrefix("Fixture Entry\n") == true)
		XCTAssertFalse(element("bulk.overview", in: app).exists)
		XCTAssertFalse(element("diary.overview", in: app).exists)
		assertSelectedEntry(1, in: app)
		let selectedRows = app.descendants(matching: .outlineRow).matching(NSPredicate(format: "isSelected == YES"))
		XCTAssertEqual(selectedRows.count, 1)
		clickEntry(5, in: app)
		showDetail(in: app)
		XCTAssertFalse(app.buttons["entry-tab.fixture-entry"].exists)
		XCTAssertTrue(app.buttons["entry-tab.fixture-entry-5"].exists)
	}

	func testBookmarkUpdatesPreserveNativeSelectionAndEscapeReturnsToEditor() {
		let app = launchWorkspace()
		clickEntry(1, in: app)
		clickEntry(4, in: app, modifiers: .shift)
		assertBulkCount(4, in: app)
		showList(in: app)
		let before = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
		before.name = "Native selection before bulk bookmarks"
		before.lifetime = .keepAlways
		add(before)
		entry(2, in: app).rightClick()
		app.menuItems["Add Bookmarks"].click()
		showDetail(in: app)
		waitUntil { app.buttons["bulk.action.topic"].isEnabled }
		assertBulkCount(4, in: app)
		for index in 1...4 { assertSelectedEntry(index, in: app) }
		let after = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
		after.name = "Native selection after bulk bookmarks"
		after.lifetime = .keepAlways
		add(after)
		entry(2, in: app).rightClick()
		let remove = app.menuItems["Remove Bookmarks"]
		XCTAssertTrue(remove.waitForExistence(timeout: 5))
		remove.click()
		showDetail(in: app)
		waitUntil { app.buttons["bulk.action.topic"].isEnabled }
		showList(in: app)
		sendShortcut(XCUIKeyboardKey.escape.rawValue, modifiers: [], in: app)
		showDetail(in: app)
		waitUntil { app.textViews["entry.editor"].exists }
		assertSelectedEntry(1, in: app)
	}

	func testPreviewChangesKeepListPinnedToTopAndDoneReturnsToActiveNote() {
		let app = launchWorkspace()
		clickEntry(1, in: app)
		clickEntry(5, in: app, modifiers: .shift)
		assertBulkCount(5, in: app)
		showList(in: app)
		let list = element("entry-list.scroll", in: app)
		let initialGap = app.descendants(matching: .outlineRow).firstMatch.frame.minY - list.frame.minY
		for title in ["Hide Previews", "Show Previews"] {
			showDetail(in: app)
			app.popUpButtons["bulk.action.more"].click()
			app.menuItems[title].click()
			waitUntil { app.buttons["bulk.action.done"].isEnabled }
			showList(in: app)
			let first = app.descendants(matching: .outlineRow).firstMatch
			waitUntil { abs(first.frame.minY - list.frame.minY - initialGap) <= 1 }
			for index in 1...5 { assertSelectedEntry(index, in: app) }
		}
		showDetail(in: app)
		app.buttons["bulk.action.done"].click()
		waitUntil { app.textViews["entry.editor"].exists }
		assertSelectedEntry(1, in: app)
		XCTAssertFalse(element("bulk.overview", in: app).exists)
	}

	func testPreviewChangesInMiddlePreserveUnchangedVisibleNotePosition() {
		let app = launchWorkspace()
		showList(in: app)
		let list = element("entry-list.scroll", in: app)
		list.scroll(byDeltaX: 0, deltaY: -250)
		clickEntry(7, in: app)
		clickEntry(9, in: app, modifiers: .shift)
		assertBulkCount(3, in: app)
		showList(in: app)
		let rows = app.descendants(matching: .outlineRow).allElementsBoundByIndex
		guard
			let anchor = rows.first(where: {
				!$0.isSelected && $0.frame.maxY > list.frame.minY && $0.frame.minY < list.frame.maxY
			})
		else {
			XCTFail("Expected an unchanged visible note")
			return
		}
		let anchorID = anchor.descendants(matching: .any)
			.matching(NSPredicate(format: "identifier BEGINSWITH %@", "entry.")).firstMatch.identifier
		let stableAnchor = app.descendants(matching: .outlineRow).containing(.any, identifier: anchorID).firstMatch
		let originalY = stableAnchor.frame.minY
		let before = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
		before.name = "Middle before preview change"
		before.lifetime = .keepAlways
		add(before)
		showDetail(in: app)
		app.popUpButtons["bulk.action.more"].click()
		app.menuItems["Hide Previews"].click()
		waitUntil { app.buttons["bulk.action.done"].isEnabled }
		showList(in: app)
		let after = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
		after.name = "Middle after preview change"
		after.lifetime = .keepAlways
		add(after)
		waitUntil { abs(stableAnchor.frame.minY - originalY) <= 1 }
		for index in 7...9 { assertSelectedEntry(index, in: app) }
	}

	func testTopicSheetContextMenuCountUsesCurrentSelectionAfterCancel() {
		let app = launchWorkspace()
		clickEntry(1, in: app)
		clickEntry(3, in: app, modifiers: .shift)
		showList(in: app)
		entry(2, in: app).rightClick()
		app.menuItems["Move to Topic…"].click()
		let sheet = app.sheets.firstMatch
		XCTAssertTrue(sheet.waitForExistence(timeout: 5))
		XCTAssertTrue(sheet.staticTexts["Move 3 Entries to Topic"].exists)
		sheet.buttons["Cancel"].click()
		waitUntil { !sheet.exists }
		clickEntry(3, in: app, modifiers: .command)
		assertBulkCount(2, in: app)
		app.buttons["bulk.action.topic"].click()
		XCTAssertTrue(sheet.waitForExistence(timeout: 5))
		XCTAssertTrue(sheet.staticTexts["Move 2 Entries to Topic"].exists)
		sheet.buttons["Cancel"].click()
	}

	func testMoveToTopicSheetCancelPreservesSelectionAndMoveSupportsExplicitNoTopic() {
		let app = launchWorkspace()
		clickEntry(1, in: app)
		clickEntry(3, in: app, modifiers: .shift)
		assertBulkCount(3, in: app)
		app.buttons["bulk.action.topic"].click()

		let sheet = app.sheets.firstMatch
		XCTAssertTrue(sheet.waitForExistence(timeout: 5))
		XCTAssertTrue(sheet.staticTexts["Move 3 Entries to Topic"].exists)
		let move = sheet.buttons["bulk.topic.move"]
		XCTAssertFalse(move.isEnabled)
		let workTopic = sheet.descendants(matching: .any)
			.matching(identifier: "bulk.topic.fixture-topic").firstMatch
		XCTAssertTrue(workTopic.exists)
		workTopic.click()
		waitUntil { move.isEnabled }
		sheet.buttons["Cancel"].click()

		waitUntil { !sheet.exists }
		assertBulkCount(3, in: app)
		for index in 1...3 { assertSelectedEntry(index, in: app) }
		showDetail(in: app)
		app.buttons["bulk.action.topic"].click()
		XCTAssertTrue(sheet.waitForExistence(timeout: 5))
		XCTAssertTrue(sheet.staticTexts["Move 3 Entries to Topic"].exists)
		workTopic.click()
		move.click()
		waitUntil { !sheet.exists && app.buttons["bulk.action.topic"].isEnabled }

		app.buttons["sidebar.topic.fixture-topic"].click()
		showList(in: app)
		for index in 1...3 { XCTAssertTrue(entry(index, in: app).waitForExistence(timeout: 5)) }
		XCTAssertFalse(entry(4, in: app).exists)
		clickEntry(1, in: app)
		clickEntry(3, in: app, modifiers: .shift)
		assertBulkCount(3, in: app)
		app.buttons["bulk.action.topic"].click()
		XCTAssertTrue(sheet.waitForExistence(timeout: 5))
		XCTAssertTrue(sheet.staticTexts["Move 3 Entries to Topic"].exists)
		let noTopic = sheet.descendants(matching: .any)
			.matching(identifier: "bulk.topic.none").firstMatch
		XCTAssertTrue(noTopic.exists)
		noTopic.click()
		waitUntil { move.isEnabled }
		move.click()

		showList(in: app)
		for index in 1...3 { waitUntil { !self.entry(index, in: app).exists } }
		app.buttons["sidebar.entries"].click()
		showList(in: app)
		for index in 1...3 { XCTAssertTrue(entry(index, in: app).waitForExistence(timeout: 5)) }
	}

	func testDraggingSelectedEntriesToArchiveMovesTheWholeSelection() {
		let app = launchWorkspace()
		clickEntry(1, in: app)
		clickEntry(3, in: app, modifiers: .shift)
		assertBulkCount(3, in: app)
		showList(in: app)
		for index in 1...3 { assertSelectedEntry(index, in: app) }

		let archive = app.buttons["sidebar.archive"]
		XCTAssertTrue(archive.waitForExistence(timeout: 5))
		entry(2, in: app).press(forDuration: 0.2, thenDragTo: archive)
		for index in 1...3 { waitUntil { !self.entry(index, in: app).exists } }
		XCTAssertTrue(entry(4, in: app).exists)

		archive.click()
		showList(in: app)
		for index in 1...3 { XCTAssertTrue(entry(index, in: app).waitForExistence(timeout: 5)) }
		XCTAssertFalse(entry(4, in: app).exists)
	}

	func testBulkTrashUsesOneConfirmationAndRestoresEntriesThroughTrashAndArchive() {
		let app = launchWorkspace()
		clickEntry(1, in: app)
		clickEntry(3, in: app, modifiers: .shift)
		assertBulkCount(3, in: app)
		app.buttons["bulk.action.trash"].click()

		let sheet = app.sheets.firstMatch
		XCTAssertTrue(sheet.waitForExistence(timeout: 5))
		XCTAssertEqual(app.sheets.count, 1)
		XCTAssertTrue(app.staticTexts["Move to Trash 3 Entries?"].exists)
		sheet.buttons["Cancel"].click()
		waitUntil { !sheet.exists }
		assertBulkCount(3, in: app)
		for index in 1...3 { assertSelectedEntry(index, in: app) }

		showDetail(in: app)
		app.buttons["bulk.action.trash"].click()
		XCTAssertTrue(sheet.waitForExistence(timeout: 5))
		XCTAssertEqual(app.sheets.count, 1)
		sheet.buttons["Move to Trash"].click()
		waitUntil { !sheet.exists }
		showList(in: app)
		for index in 1...3 { waitUntil { !self.entry(index, in: app).exists } }

		app.buttons["sidebar.trash"].click()
		clickEntry(1, in: app)
		clickEntry(3, in: app, modifiers: .shift)
		assertBulkCount(3, in: app)
		XCTAssertTrue(app.buttons["bulk.action.restore"].exists)
		XCTAssertTrue(app.buttons["bulk.action.delete"].exists)
		XCTAssertFalse(app.buttons["bulk.action.archive"].exists)
		app.buttons["bulk.action.restore"].click()
		showList(in: app)
		for index in 1...3 { waitUntil { !self.entry(index, in: app).exists } }

		app.buttons["sidebar.entries"].click()
		clickEntry(1, in: app)
		clickEntry(3, in: app, modifiers: .shift)
		assertBulkCount(3, in: app)
		app.popUpButtons["bulk.action.more"].click()
		app.menuItems["Archive"].click()
		showList(in: app)
		for index in 1...3 { waitUntil { !self.entry(index, in: app).exists } }

		app.buttons["sidebar.archive"].click()
		clickEntry(1, in: app)
		clickEntry(3, in: app, modifiers: .shift)
		assertBulkCount(3, in: app)
		app.popUpButtons["bulk.action.more"].click()
		let unarchive = app.menuItems["Restore from Archive"]
		XCTAssertTrue(unarchive.waitForExistence(timeout: 5))
		unarchive.click()
		showList(in: app)
		for index in 1...3 { waitUntil { !self.entry(index, in: app).exists } }
		app.buttons["sidebar.entries"].click()
		showList(in: app)
		for index in 1...3 { XCTAssertTrue(entry(index, in: app).waitForExistence(timeout: 5)) }
	}

}
