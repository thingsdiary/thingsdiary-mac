import SwiftUI

/// Refresh AppKit's grouped selection after SwiftUI moves existing rows to new positions.
/// NSTableRowView's neighbor-selection properties do not invalidate its drawing themselves.
struct WorkspaceListSelectionAppearance: NSViewRepresentable {
	let order: [String]
	let selection: Set<WorkspaceTabID>
	let viewport: WorkspaceListViewport
	let isUpdating: Bool

	func makeNSView(context: Context) -> SelectionAppearanceView { SelectionAppearanceView() }

	func updateNSView(_ view: SelectionAppearanceView, context: Context) {
		view.viewport = viewport
		view.viewportOrder = order
		view.isUpdating = isUpdating
		view.scheduleRefresh()
	}
}

final class SelectionAppearanceView: NSView {
	private var refreshPending = false
	weak var viewport: WorkspaceListViewport?
	var viewportOrder: [String] = []
	var isUpdating = false

	override func hitTest(_ point: NSPoint) -> NSView? { nil }

	override func viewDidMoveToWindow() {
		super.viewDidMoveToWindow()
		scheduleRefresh()
	}

	func scheduleRefresh() {
		guard !refreshPending else { return }
		refreshPending = true
		// SwiftUI must finish moving the native row views before their neighbors are read.
		DispatchQueue.main.async { [weak self] in
			guard let self else { return }
			refreshPending = false
			var container = superview
			while let ancestor = container {
				if let outline = findOutline(in: ancestor) {
					viewport?.attach(outline, order: viewportOrder)
					outline.layoutSubtreeIfNeeded()
					if viewport?.restore(isUpdating: isUpdating) == true { scheduleRefresh() }
					outline.enumerateAvailableRowViews { row, index in
						row.isPreviousRowSelected = index > 0 && outline.isRowSelected(index - 1)
						row.isNextRowSelected = index + 1 < outline.numberOfRows && outline.isRowSelected(index + 1)
						row.needsDisplay = true
					}
					return
				}
				container = ancestor.superview
			}
		}
	}

	private func findOutline(in view: NSView) -> NSOutlineView? {
		if let outline = view as? NSOutlineView { return outline }
		for child in view.subviews {
			if let outline = findOutline(in: child) { return outline }
		}
		return nil
	}
}

/// Keep the reading position stable while rows are inserted, resized, or reordered.
@MainActor final class WorkspaceListViewport {
	private weak var outline: NSOutlineView?
	private var order: [String] = []
	private var snapshot: Snapshot?
	private var expectedFinalOrder: [String]?
	private var settlingPassRequested = false
	private var topInsertionID: String?
	private var topInsertionSettlingPassRequested = false

	private struct Snapshot {
		let atTop: Bool
		let originalOrder: [String]
		let anchorIndex: Int
		let offset: CGFloat
	}

	func attach(_ outline: NSOutlineView, order: [String]) {
		self.outline = outline
		self.order = order
	}

	/// Keep a newly inserted first row visible when the list was already at the top.
	func pinTopForInsertion(of id: String) {
		guard snapshot == nil,
			let outline,
			let clip = outline.enclosingScrollView?.contentView,
			clip.bounds.minY <= 1,
			!order.contains(id)
		else { return }
		topInsertionID = id
		topInsertionSettlingPassRequested = false
	}

	func beginUpdates(changingIDs: Set<String>) {
		guard let outline, let clip = outline.enclosingScrollView?.contentView, !order.isEmpty else { return }
		let range = outline.rows(in: clip.documentVisibleRect)
		guard range.location != NSNotFound, range.location < order.count else { return }
		let visible = range.location..<min(NSMaxRange(range), order.count)
		let anchor = visible.first { !changingIDs.contains(order[$0]) } ?? range.location
		snapshot = Snapshot(
			atTop: clip.bounds.minY <= 1, originalOrder: order, anchorIndex: anchor,
			offset: outline.rect(ofRow: anchor).minY - clip.bounds.minY)
		expectedFinalOrder = nil
		settlingPassRequested = false
	}

	// A finished request can still have intermediate SwiftUI row updates in flight.
	func finishUpdates(expectedOrder: [String]) {
		expectedFinalOrder = expectedOrder
		if expectedOrder.isEmpty { snapshot = nil }
	}

	@discardableResult
	func restore(isUpdating: Bool = false) -> Bool {
		if restoreTopInsertion() { return true }
		guard let snapshot, let outline, let scroll = outline.enclosingScrollView else { return false }
		let clip = scroll.contentView
		var bounds = clip.bounds
		if snapshot.atTop {
			bounds.origin.y = 0
		} else {
			// Prefer the original anchor; if it disappeared, use its nearest surviving neighbor.
			let anchorID = snapshot.originalOrder[snapshot.anchorIndex]
			let index =
				order.firstIndex(of: anchorID)
				?? snapshot.originalOrder.indices.sorted {
					abs($0 - snapshot.anchorIndex) < abs($1 - snapshot.anchorIndex)
				}.lazy.compactMap { self.order.firstIndex(of: snapshot.originalOrder[$0]) }.first
			if let index,
				index < outline.numberOfRows
			{
				bounds.origin.y = outline.rect(ofRow: index).minY - snapshot.offset
			}
		}
		clip.scroll(to: clip.constrainBoundsRect(bounds).origin)
		scroll.reflectScrolledClipView(clip)
		if let expectedFinalOrder, !isUpdating {
			// Realtime may supersede the exact final order. Allow one settling layout pass,
			// then release the anchor so later user scrolling cannot be overridden.
			if expectedFinalOrder != order && !settlingPassRequested {
				settlingPassRequested = true
				return true
			}
			self.snapshot = nil
			self.expectedFinalOrder = nil
			settlingPassRequested = false
		}
		return false
	}

	private func restoreTopInsertion() -> Bool {
		guard let topInsertionID,
			order.contains(topInsertionID),
			let outline,
			let scroll = outline.enclosingScrollView
		else { return false }
		let clip = scroll.contentView
		var bounds = clip.bounds
		bounds.origin.y = 0
		clip.scroll(to: clip.constrainBoundsRect(bounds).origin)
		scroll.reflectScrolledClipView(clip)
		if !topInsertionSettlingPassRequested {
			topInsertionSettlingPassRequested = true
			return true
		}
		self.topInsertionID = nil
		topInsertionSettlingPassRequested = false
		return false
	}
}
