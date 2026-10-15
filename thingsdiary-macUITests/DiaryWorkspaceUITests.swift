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
        XCTAssertEqual(app.staticTexts["entry-list.title"].value as? String, "Bookmarks")

        app.buttons["sidebar.archive"].click()
        XCTAssertEqual(app.staticTexts["entry-list.title"].value as? String, "Archive")

        app.buttons["sidebar.trash"].click()
        XCTAssertEqual(app.staticTexts["entry-list.title"].value as? String, "Trash")
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
