import AppKit
import Testing

@testable import thingsdiary

@MainActor private final class ViewportOutlineFixture: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
	var ids = (1...30).map(String.init)
	var heights: [String: CGFloat] = [:]
	let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
	let outline = NSOutlineView(frame: NSRect(x: 0, y: 0, width: 300, height: 1200))

	override init() {
		super.init()
		outline.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("note")))
		outline.headerView = nil
		outline.dataSource = self
		outline.delegate = self
		outline.intercellSpacing = .zero
		scroll.documentView = outline
		outline.reloadData()
		scroll.layoutSubtreeIfNeeded()
	}

	func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
		item == nil ? ids.count : 0
	}
	func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
		ids[index] as NSString
	}
	func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool { false }
	func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
		heights[item as! String] ?? 40
	}
}

@Test("Bulk height changes keep a list at its original top position")
@MainActor func bulkViewportKeepsTopPinned() {
	let fixture = ViewportOutlineFixture()
	let viewport = WorkspaceListViewport()
	viewport.attach(fixture.outline, order: fixture.ids)
	viewport.beginUpdates(changingIDs: ["1", "2", "3"])
	fixture.heights = ["1": 80, "2": 70, "3": 90]
	fixture.outline.reloadData()
	fixture.scroll.contentView.scroll(to: NSPoint(x: 0, y: 35))
	viewport.finishUpdates(expectedOrder: fixture.ids)
	viewport.restore()
	#expect(abs(fixture.scroll.contentView.bounds.minY) < 1)

	// Once the batch finishes, ordinary user scrolling is no longer overridden.
	fixture.scroll.contentView.scroll(to: NSPoint(x: 0, y: 60))
	viewport.restore()
	#expect(abs(fixture.scroll.contentView.bounds.minY - 60) < 1)
}

@Test("Bulk sorting and height changes preserve an unaffected note's screen position")
@MainActor func bulkViewportKeepsMiddleAnchor() {
	let fixture = ViewportOutlineFixture()
	let viewport = WorkspaceListViewport()
	fixture.scroll.contentView.scroll(to: NSPoint(x: 0, y: 205))
	viewport.attach(fixture.outline, order: fixture.ids)
	let anchor = "6"
	let oldY =
		fixture.outline.rect(ofRow: fixture.ids.firstIndex(of: anchor)!).minY
		- fixture.scroll.contentView.bounds.minY
	viewport.beginUpdates(changingIDs: ["8", "9"])
	fixture.ids.removeAll { ["8", "9"].contains($0) }
	fixture.ids.insert(contentsOf: ["9", "8"], at: 0)
	fixture.heights = ["8": 85, "9": 65]
	fixture.outline.reloadData()
	viewport.attach(fixture.outline, order: fixture.ids)
	viewport.finishUpdates(expectedOrder: fixture.ids)
	viewport.restore()
	let newY =
		fixture.outline.rect(ofRow: fixture.ids.firstIndex(of: anchor)!).minY
		- fixture.scroll.contentView.bounds.minY
	#expect(abs(newY - oldY) < 1)
}

@Test("A batch retains its scroll anchor until the final SwiftUI order arrives")
@MainActor func bulkViewportWaitsForFinalOrder() {
	let fixture = ViewportOutlineFixture()
	let viewport = WorkspaceListViewport()
	fixture.scroll.contentView.scroll(to: NSPoint(x: 0, y: 205))
	viewport.attach(fixture.outline, order: fixture.ids)
	let oldY = fixture.outline.rect(ofRow: 5).minY - fixture.scroll.contentView.bounds.minY
	viewport.beginUpdates(changingIDs: ["8", "9"])
	let finalOrder = ["9", "8"] + fixture.ids.filter { !["8", "9"].contains($0) }
	viewport.finishUpdates(expectedOrder: finalOrder)
	fixture.ids.removeAll { $0 == "8" }
	fixture.ids.insert("8", at: 0)
	fixture.outline.reloadData()
	viewport.attach(fixture.outline, order: fixture.ids)
	viewport.restore()

	fixture.ids = finalOrder
	fixture.heights = ["8": 85, "9": 65]
	fixture.outline.reloadData()
	fixture.scroll.contentView.scroll(to: NSPoint(x: 0, y: 270))
	viewport.attach(fixture.outline, order: fixture.ids)
	viewport.restore()
	let newY =
		fixture.outline.rect(ofRow: fixture.ids.firstIndex(of: "6")!).minY
		- fixture.scroll.contentView.bounds.minY
	#expect(abs(newY - oldY) < 1)
}

@Test("Realtime can supersede a batch order without leaving the scroll anchor active")
@MainActor func bulkViewportReleasesSupersededOrder() {
	let fixture = ViewportOutlineFixture()
	let viewport = WorkspaceListViewport()
	viewport.attach(fixture.outline, order: fixture.ids)
	viewport.beginUpdates(changingIDs: ["1"])
	viewport.finishUpdates(expectedOrder: fixture.ids)
	fixture.ids.insert("new-remote-note", at: 0)
	fixture.outline.reloadData()
	viewport.attach(fixture.outline, order: fixture.ids)
	#expect(viewport.restore())
	#expect(!viewport.restore())
	fixture.scroll.contentView.scroll(to: NSPoint(x: 0, y: 60))
	viewport.restore()
	#expect(abs(fixture.scroll.contentView.bounds.minY - 60) < 1)
}

@Test("Matching row IDs do not release an anchor while the batch is still rendering")
@MainActor func bulkViewportWaitsForCompletionAcknowledgment() {
	let fixture = ViewportOutlineFixture()
	let viewport = WorkspaceListViewport()
	viewport.attach(fixture.outline, order: fixture.ids)
	viewport.beginUpdates(changingIDs: ["1"])
	viewport.finishUpdates(expectedOrder: fixture.ids)
	viewport.restore(isUpdating: true)
	fixture.heights = ["1": 80]
	fixture.outline.reloadData()
	fixture.scroll.contentView.scroll(to: NSPoint(x: 0, y: 35))
	viewport.restore(isUpdating: false)
	#expect(abs(fixture.scroll.contentView.bounds.minY) < 1)
}

@Test("Inserting a row keeps a list pinned to the top through its settling layout")
@MainActor func insertionKeepsTopPinned() {
	let fixture = ViewportOutlineFixture()
	let viewport = WorkspaceListViewport()
	viewport.attach(fixture.outline, order: fixture.ids)
	viewport.pinTopForInsertion(of: "new")
	fixture.ids.insert("new", at: 0)
	fixture.outline.reloadData()
	fixture.scroll.contentView.scroll(to: NSPoint(x: 0, y: 40))
	viewport.attach(fixture.outline, order: fixture.ids)
	#expect(viewport.restore())
	#expect(abs(fixture.scroll.contentView.bounds.minY) < 1)

	fixture.scroll.contentView.scroll(to: NSPoint(x: 0, y: 40))
	#expect(!viewport.restore())
	#expect(abs(fixture.scroll.contentView.bounds.minY) < 1)

	fixture.scroll.contentView.scroll(to: NSPoint(x: 0, y: 60))
	viewport.restore()
	#expect(abs(fixture.scroll.contentView.bounds.minY - 60) < 1)
}

@Test("Each consecutive insertion can pin the list to the top")
@MainActor func consecutiveInsertionsKeepTopPinned() {
	let fixture = ViewportOutlineFixture()
	let viewport = WorkspaceListViewport()
	viewport.attach(fixture.outline, order: fixture.ids)

	for id in ["new-1", "new-2"] {
		viewport.pinTopForInsertion(of: id)
		fixture.ids.insert(id, at: 0)
		fixture.outline.reloadData()
		fixture.scroll.contentView.scroll(to: NSPoint(x: 0, y: 40))
		viewport.attach(fixture.outline, order: fixture.ids)
		#expect(viewport.restore())
		#expect(!viewport.restore())
		#expect(abs(fixture.scroll.contentView.bounds.minY) < 1)
	}
}

@Test("An insertion does not move a list that was scrolled away from the top")
@MainActor func insertionDoesNotPinScrolledList() {
	let fixture = ViewportOutlineFixture()
	let viewport = WorkspaceListViewport()
	fixture.scroll.contentView.scroll(to: NSPoint(x: 0, y: 120))
	viewport.attach(fixture.outline, order: fixture.ids)
	viewport.pinTopForInsertion(of: "new")
	fixture.ids.insert("new", at: 0)
	fixture.outline.reloadData()
	fixture.scroll.contentView.scroll(to: NSPoint(x: 0, y: 160))
	viewport.attach(fixture.outline, order: fixture.ids)
	#expect(!viewport.restore())
	#expect(abs(fixture.scroll.contentView.bounds.minY - 160) < 1)
}
