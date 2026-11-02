import AppKit
import Combine
import SwiftUI
import Testing

@testable import thingsdiary

@MainActor private final class ListRowRemovalProbeModel: ObservableObject {
	@Published var isRemoving = false
}

@MainActor private final class StructuralListProbeModel: ObservableObject {
	@Published var ids = [1]
	@Published var insertionVisibility: [Int: Bool] = [:]
}

private struct StructuralListProbe: View {
	@ObservedObject var model: StructuralListProbeModel
	let viewport: WorkspaceListViewport

	var body: some View {
		List {
			ForEach(model.ids, id: \.self) { id in
				Text("Row \(id)")
					.frame(maxWidth: .infinity, minHeight: 60)
					.modifier(
						ListRowMembershipMotion(
							insertionVisibility: model.insertionVisibility[id],
							isRemoving: false,
							reduceMotion: false,
							revealInsertion: { model.insertionVisibility[id] = true }
						)
					)
					.listRowInsets(.init())
					.listRowSeparator(.hidden)
			}
		}
		.environment(\.defaultMinListRowHeight, 0)
		.frame(width: 300, height: 200)
		.background(
			WorkspaceListSelectionAppearance(
				order: model.ids.map(String.init),
				selection: [],
				viewport: viewport,
				isUpdating: false
			)
		)
	}
}

private struct ListRowRemovalProbe: View {
	@ObservedObject var model: ListRowRemovalProbeModel

	var body: some View {
		List {
			Text("Removing row")
				.frame(maxWidth: .infinity, minHeight: 60)
				.modifier(
					ListRowMembershipMotion(
						isRemoving: model.isRemoving,
						reduceMotion: false,
						showsSeparator: true
					)
				)
				.listRowInsets(.init())
				.listRowSeparator(.hidden)
			Text("Following row")
				.frame(maxWidth: .infinity, minHeight: 60)
				.listRowInsets(.init())
		}
		.environment(\.defaultMinListRowHeight, 0)
		.frame(width: 300, height: 200)
	}
}

@MainActor private func findOutline(in view: NSView) -> NSOutlineView? {
	if let outline = view as? NSOutlineView { return outline }
	for child in view.subviews {
		if let outline = findOutline(in: child) { return outline }
	}
	return nil
}

@MainActor private func presentationYOffset(of outline: NSOutlineView) -> CGFloat {
	guard let layer = outline.layer else { return 0 }
	return (layer.presentation()?.value(forKeyPath: "transform.translation.y") as? CGFloat)
		?? (layer.value(forKeyPath: "transform.translation.y") as? CGFloat)
		?? 0
}

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

@Test("Workspace lists remove native vertical intercell spacing")
@MainActor func workspaceListRemovesVerticalIntercellSpacing() {
	let outline = NSOutlineView()
	outline.intercellSpacing = NSSize(width: 3, height: 7)
	configureWorkspaceListOutline(outline)
	#expect(outline.intercellSpacing.width == 3)
	#expect(outline.intercellSpacing.height == 0)
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
	#expect(viewport.pinTopForInsertion(of: "new"))
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

@Test("Inserting a row while scrolled preserves the visible anchor")
@MainActor func insertionPreservesScrolledAnchor() {
	let fixture = ViewportOutlineFixture()
	let viewport = WorkspaceListViewport()
	fixture.scroll.contentView.scroll(to: NSPoint(x: 0, y: 205))
	viewport.attach(fixture.outline, order: fixture.ids)
	let anchor = "6"
	let oldY =
		fixture.outline.rect(ofRow: fixture.ids.firstIndex(of: anchor)!).minY
		- fixture.scroll.contentView.bounds.minY

	#expect(!viewport.pinTopForInsertion(of: "new", animationDuration: listRowMembershipDuration))
	fixture.ids.insert("new", at: 0)
	fixture.outline.reloadData()
	viewport.finishInsertion(expectedOrder: fixture.ids)
	viewport.attach(fixture.outline, order: fixture.ids)
	viewport.restore()

	let newY =
		fixture.outline.rect(ofRow: fixture.ids.firstIndex(of: anchor)!).minY
		- fixture.scroll.contentView.bounds.minY
	#expect(abs(newY - oldY) < 1)
}

@Suite(.serialized)
struct ListRowMembershipMotionTests {
	@Test("Structural insertion moves the following row progressively")
	@MainActor func structuralInsertionMovesFollowingRowProgressively() async throws {
		let model = StructuralListProbeModel()
		let viewport = WorkspaceListViewport()
		let hostingView = NSHostingView(rootView: StructuralListProbe(model: model, viewport: viewport))
		let window = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
			styleMask: .borderless,
			backing: .buffered,
			defer: false
		)
		window.contentView = hostingView
		window.orderFrontRegardless()
		defer { window.close() }

		try await Task.sleep(for: .milliseconds(120))
		let outline = try #require(findOutline(in: hostingView))
		let clip = try #require(outline.enclosingScrollView?.contentView)
		let initialY = outline.rect(ofRow: 0).minY - clip.bounds.minY

		viewport.pinTopForInsertion(of: "0", animationDuration: listRowMembershipDuration)
		model.insertionVisibility[0] = false
		model.ids.insert(0, at: 0)
		try await Task.sleep(for: .milliseconds(100))
		let intermediateY =
			outline.rect(ofRow: 1).minY - clip.bounds.minY + presentationYOffset(of: outline)
		try await Task.sleep(for: .milliseconds(600))
		let finalY = outline.rect(ofRow: 1).minY - clip.bounds.minY + presentationYOffset(of: outline)

		#expect(intermediateY > initialY + 1)
		#expect(intermediateY < finalY - 1)
	}

	@Test("Inserting a row animates the viewport through intermediate positions")
	@MainActor func insertionAnimatesViewportProgressively() async throws {
		let fixture = ViewportOutlineFixture()
		let window = NSWindow(
			contentRect: fixture.scroll.frame, styleMask: .borderless, backing: .buffered, defer: false)
		window.contentView = fixture.scroll
		window.orderFrontRegardless()
		defer { window.close() }

		let viewport = WorkspaceListViewport()
		viewport.attach(fixture.outline, order: fixture.ids)
		viewport.pinTopForInsertion(of: "new", animationDuration: 0.26)
		fixture.ids.insert("new", at: 0)
		fixture.outline.reloadData()
		viewport.attach(fixture.outline, order: fixture.ids)
		#expect(!viewport.restore())

		try await Task.sleep(for: .milliseconds(130))
		let intermediateY = presentationYOffset(of: fixture.outline)
		#expect(intermediateY > -39 && intermediateY < -1)

		try await Task.sleep(for: .milliseconds(220))
		#expect(abs(presentationYOffset(of: fixture.outline)) < 1)
	}

	@Test("Removing a SwiftUI list row collapses its AppKit height progressively")
	@MainActor func removalCollapsesListRowProgressively() async throws {
		let model = ListRowRemovalProbeModel()
		let hostingView = NSHostingView(rootView: ListRowRemovalProbe(model: model))
		let window = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
			styleMask: .borderless,
			backing: .buffered,
			defer: false
		)
		window.contentView = hostingView
		window.orderFrontRegardless()
		defer { window.close() }

		try await Task.sleep(for: .milliseconds(120))
		let outline = try #require(findOutline(in: hostingView))
		let fullHeight = outline.rect(ofRow: 0).height
		#expect(fullHeight > 50)

		withAnimation(.easeInOut(duration: listRowMembershipDuration)) {
			model.isRemoving = true
		}
		for _ in 0..<25 {
			try await Task.sleep(for: .milliseconds(24))
		}
		try await Task.sleep(for: .milliseconds(100))
		#expect(outline.rect(ofRow: 0).height <= 1)
	}

	@Test("List membership layout interpolates insertion and removal heights")
	func listMembershipLayoutInterpolatesHeight() {
		#expect(listRowMembershipHeight(fullHeight: 60, progress: 0) == 0)
		#expect(listRowMembershipHeight(fullHeight: 60, progress: 0.5) == 30)
		#expect(listRowMembershipHeight(fullHeight: 60, progress: 1) == 60)
	}

	@Test("A row cannot stay collapsed after its insertion finishes")
	func completedInsertionForcesVisibleProgress() {
		#expect(
			listRowMembershipProgress(
				isInserted: false,
				isVisible: false,
				isRemoving: false,
				reduceMotion: false
			) == 1
		)
		#expect(
			listRowMembershipProgress(
				isInserted: true,
				isVisible: false,
				isRemoving: false,
				reduceMotion: false
			) == 0
		)
	}
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
