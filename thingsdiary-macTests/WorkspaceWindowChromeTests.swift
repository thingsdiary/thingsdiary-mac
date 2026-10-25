import AppKit
import CoreGraphics
import Foundation
import Testing
import ThingsDiaryClient
import XCTest

@testable import thingsdiary

@Test("Window controls use the workspace titlebar center in either coordinate system")
func windowControlsUseWorkspaceTitlebarCenter() {
	let bounds = CGRect(x: 0, y: 10, width: 900, height: 600)

	#expect(
		workspaceTitlebarCenterY(in: bounds, isFlipped: true)
			== bounds.minY + workspaceTitlebarHeight / 2
	)
	#expect(
		workspaceTitlebarCenterY(in: bounds, isFlipped: false)
			== bounds.maxY - workspaceTitlebarHeight / 2
	)
}

@Test("Window controls keep a small inset from the leading edge")
func windowControlsKeepLeadingInset() {
	#expect(workspaceTrafficLightsHorizontalOffset(closeButtonMinX: 16) == 4)
}

@MainActor
final class WorkspaceWindowChromeMenuTests: XCTestCase {
	func testTabContextMenusRenderDestructiveActionsInRed() {
		for title in ["Delete Template", "Move to Trash"] {
			for enabled in [false, true] {
				let view = WorkspaceTabContextMenuAreaView()
				var invoked = false
				view.items = [
					WorkspaceTabMenuItem(title: "Close", action: {}),
					.separator,
					WorkspaceTabMenuItem(
						title: title, isEnabled: enabled, isDestructive: true, action: { invoked = true }
					),
				]
				let menu = view.makeMenu()
				let item = menu.items[2]
				XCTAssertEqual(item.title, title)
				XCTAssertEqual(item.isEnabled, enabled)
				XCTAssertEqual(
					item.attributedTitle?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor,
					NSColor.systemRed
				)
				XCTAssertNil(menu.items[0].attributedTitle)
				XCTAssertTrue(menu.items[1].isSeparatorItem)
				if let action = item.action { view.perform(action, with: item) }
				XCTAssertEqual(invoked, enabled)
			}
		}
	}

	func testEntryContextMenusMarkMoveToTrashAsDestructive() {
		for topicID in [nil, "topic-1"] as [String?] {
			let view = WorkspaceEntryContextMenuAreaView()
			view.entry = ThingsDiaryEntry(
				id: "entry-1",
				diaryID: "diary-1",
				content: "Entry",
				topicID: topicID,
				createdAt: Date(timeIntervalSince1970: 1),
				updatedAt: Date(timeIntervalSince1970: 1),
				version: 1
			)

			let item = view.makeMenu().items.first { $0.title == "Move to Trash" }

			XCTAssertEqual(item?.title, "Move to Trash")
			XCTAssertEqual(item?.isEnabled, true)
			XCTAssertNil(item?.image)
			XCTAssertEqual(
				item?.attributedTitle?.attribute(
					.foregroundColor,
					at: 0,
					effectiveRange: nil
				) as? NSColor,
				NSColor.systemRed,
				"Expected a red Move to Trash item for topicID \(String(describing: topicID))"
			)
		}
	}

	func testEntryPreviewMenuRespectsTopicAndEntrySettings() {
		for topicHidden in [false, true] {
			for entryHidden in [false, true] {
				let view = WorkspaceEntryContextMenuAreaView()
				view.entry = ThingsDiaryEntry(
					id: "entry-1", diaryID: "diary-1", content: "Entry", topicID: "topic-1",
					previewHidden: entryHidden,
					createdAt: Date(timeIntervalSince1970: 1), updatedAt: Date(timeIntervalSince1970: 1), version: 1
				)
				view.topics = [
					ThingsDiaryTopic(
						id: "topic-1", diaryID: "diary-1", title: "Private", description: "", color: "blue",
						entryPreviewable: !topicHidden,
						createdAt: Date(timeIntervalSince1970: 1), updatedAt: Date(timeIntervalSince1970: 1), version: 1
					)
				]
				var toggled = false
				var editedTopicID: String?
				view.togglePreview = { toggled = true }
				view.editTopic = { editedTopicID = $0.id }
				let menu = view.makeMenu()
				let title =
					topicHidden
					? (entryHidden ? "Preview Hidden by Entry and Topic" : "Preview Hidden by Topic")
					: (entryHidden ? "Show Preview" : "Hide Preview")
				let item = menu.items.first { $0.title == title }
				XCTAssertNotNil(item)
				XCTAssertEqual(item?.isEnabled, !topicHidden)
				// The action itself must also respect the topic restriction.
				if let item, let action = item.action { view.perform(action, with: item) }
				XCTAssertEqual(toggled, !topicHidden)
				let settings = menu.items.first { $0.title == "Topic Settings…" }
				XCTAssertEqual(settings != nil, topicHidden)
				if let settings, let action = settings.action { view.perform(action, with: settings) }
				XCTAssertEqual(editedTopicID, topicHidden ? "topic-1" : nil)
			}
		}
	}

	func testTemplateListContextMenuMarksDeleteAsDestructive() {
		let view = WorkspaceTemplateContextMenuAreaView()

		let item = view.makeMenu().items.first { $0.title == "Delete" }

		XCTAssertEqual(item?.title, "Delete")
		XCTAssertEqual(item?.isEnabled, true)
		XCTAssertNil(item?.image)
		XCTAssertEqual(
			item?.attributedTitle?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor,
			NSColor.systemRed
		)
	}

	func testTrashContextMenuMarksEmptyTrashAsDestructive() {
		let view = WorkspaceContextMenuAreaView()
		view.title = "Empty Trash"
		view.isMenuItemEnabled = true

		let item = view.makeMenu().items.first {
			$0.title == "Empty Trash" && $0.action == NSSelectorFromString("performMenuAction")
		}

		XCTAssertEqual(item?.title, "Empty Trash")
		XCTAssertEqual(item?.isEnabled, true)
		XCTAssertEqual(
			item?.attributedTitle?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor,
			NSColor.systemRed
		)
	}

	func testTopicContextMenuMarksDeleteAsDestructive() {
		let view = WorkspaceTopicContextMenuAreaView()

		let item = view.makeMenu().items.first {
			$0.title == "Delete" && $0.action == NSSelectorFromString("performDeleteAction")
		}

		XCTAssertEqual(item?.title, "Delete")
		XCTAssertEqual(item?.isEnabled, true)
		XCTAssertEqual(
			item?.attributedTitle?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor,
			NSColor.systemRed
		)
	}
}
