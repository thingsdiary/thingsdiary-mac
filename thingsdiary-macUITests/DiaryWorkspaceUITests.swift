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

    func testNoteActionsAreAvailableFromRowAndEditorToolbar() {
        let app = launchWorkspace()
        let note = app.descendants(matching: .any)["entry.fixture-entry"]

        note.rightClick()
        XCTAssertTrue(app.menuItems["Bookmark"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.menuItems["Archive"].exists)
        XCTAssertTrue(app.menuItems["Move to Trash"].exists)
        app.typeKey(.escape, modifierFlags: [])

        note.click()
        let actions = app.descendants(matching: .any)["entry.actions"]
        XCTAssertTrue(actions.waitForExistence(timeout: 2))
        actions.click()
        XCTAssertTrue(app.menuItems["Bookmark"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.menuItems["Archive"].exists)
        XCTAssertTrue(app.menuItems["Move to Trash"].exists)
    }
}
