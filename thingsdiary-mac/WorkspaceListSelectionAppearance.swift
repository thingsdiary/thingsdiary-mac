import SwiftUI

@MainActor func configureWorkspaceListOutline(_ outline: NSOutlineView) {
	var spacing = outline.intercellSpacing
	spacing.height = 0
	outline.intercellSpacing = spacing
}

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
					configureWorkspaceListOutline(outline)
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
	private var pendingTopInsertions: [String: TimeInterval] = [:]
	private var topInsertionSettlingPassRequested = false
	private var topInsertionAnimationInFlight = false
	private var topInsertionAnimationGeneration = 0
	private var scrolledInsertionInFlight = false

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
	/// Returns whether the inserted row itself should animate. Offscreen insertions
	/// preserve the current anchor but must not mutate row height in the background.
	@discardableResult
	func pinTopForInsertion(of id: String, animationDuration: TimeInterval = 0) -> Bool {
		guard !order.contains(id) else { return false }
		guard let outline,
			let clip = outline.enclosingScrollView?.contentView
		else {
			// The first row can be created while the empty state still owns the pane.
			return true
		}
		if snapshot != nil { return false }
		if clip.bounds.minY <= 1 || topInsertionAnimationInFlight {
			pendingTopInsertions[id] = animationDuration
			return true
		} else {
			beginUpdates(changingIDs: [id])
			scrolledInsertionInFlight = snapshot != nil
			return false
		}
	}

	func finishInsertion(expectedOrder: [String]) {
		guard scrolledInsertionInFlight else { return }
		finishUpdates(expectedOrder: expectedOrder)
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
			scrolledInsertionInFlight = false
		}
		return false
	}

	private func restoreTopInsertion() -> Bool {
		if topInsertionSettlingPassRequested,
			let scroll = outline?.enclosingScrollView
		{
			let clip = scroll.contentView
			var bounds = clip.bounds
			bounds.origin.y = 0
			clip.scroll(to: clip.constrainBoundsRect(bounds).origin)
			scroll.reflectScrolledClipView(clip)
			topInsertionSettlingPassRequested = false
			return false
		}
		guard !pendingTopInsertions.isEmpty,
			let outline,
			let scroll = outline.enclosingScrollView
		else { return false }
		let insertedIDs = pendingTopInsertions.keys.filter(order.contains)
		guard !insertedIDs.isEmpty else { return false }
		let clip = scroll.contentView
		outline.layoutSubtreeIfNeeded()
		let measuredInsertions = insertedIDs.compactMap { id -> (String, CGFloat)? in
			guard let index = order.firstIndex(of: id), index < outline.numberOfRows else { return nil }
			let height = outline.rect(ofRow: index).height
			return height > 1 ? (id, height) : nil
		}
		// SwiftUI can publish the new ID one layout pass before AppKit knows its
		// final row height. Keep it pending and ask the representable for another pass.
		guard !measuredInsertions.isEmpty else { return true }
		let insertedHeight = measuredInsertions.reduce(CGFloat.zero) { $0 + $1.1 }
		let duration = measuredInsertions.compactMap {
			pendingTopInsertions.removeValue(forKey: $0.0)
		}.max() ?? 0
		if duration > 0 {
			topInsertionAnimationInFlight = true
			topInsertionAnimationGeneration += 1
			let generation = topInsertionAnimationGeneration
			outline.wantsLayer = true
			guard let layer = outline.layer else { return false }
			let currentOffset =
				(layer.presentation()?.value(forKeyPath: "transform.translation.y") as? CGFloat)
				?? (layer.value(forKeyPath: "transform.translation.y") as? CGFloat)
				?? 0
			let startOffset = currentOffset - insertedHeight
			layer.removeAnimation(forKey: "workspaceTopInsertion")
			CATransaction.begin()
			CATransaction.setDisableActions(true)
			layer.setValue(0, forKeyPath: "transform.translation.y")
			CATransaction.commit()
			let animation = CABasicAnimation(keyPath: "transform.translation.y")
			animation.fromValue = startOffset
			animation.toValue = 0
			animation.duration = duration
			animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
			CATransaction.begin()
			CATransaction.setCompletionBlock { [weak self] in
				Task { @MainActor [weak self] in
					guard let self, self.topInsertionAnimationGeneration == generation else { return }
					self.topInsertionAnimationInFlight = false
				}
			}
			layer.add(animation, forKey: "workspaceTopInsertion")
			CATransaction.commit()
			return false
		}
		var targetBounds = clip.bounds
		targetBounds.origin.y = 0
		let targetOrigin = clip.constrainBoundsRect(targetBounds).origin
		clip.scroll(to: targetOrigin)
		scroll.reflectScrolledClipView(clip)
		topInsertionAnimationInFlight = false
		topInsertionSettlingPassRequested = true
		return true
	}
}
