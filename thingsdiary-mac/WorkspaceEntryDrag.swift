import SwiftUI

private let entryDragPasteboardType = NSPasteboard.PasteboardType("io.thingsdiary.entry")

/// Unmodified clicks select a native outline row. Modifier clicks stay with List.
/// Tracking a possible drag here avoids a SwiftUI gesture capturing Shift/Command input.
struct WorkspaceEntryDragSource<Preview: View>: ViewModifier {
	let enabled: Bool
	let payloads: [EntryDragPayload]
	let isSelected: Bool
	let select: () -> Void
	let open: () -> Void
	@ViewBuilder let preview: () -> Preview

	func body(content: Content) -> some View {
		content.overlay(
			WorkspaceEntryDragArea(
				enabled: enabled, payloads: payloads, isSelected: isSelected, select: select, open: open
			) {
				let host = NSHostingView(
					rootView: preview().overlay(alignment: .topTrailing) {
						if payloads.count > 1 {
							Text("\(payloads.count)").font(.caption.bold()).padding(6)
								.background(.tint, in: Circle()).foregroundStyle(.white)
						}
					})
				host.frame.size = NSSize(width: 280, height: max(host.fittingSize.height, 60))
				host.layoutSubtreeIfNeeded()
				guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
				host.cacheDisplay(in: host.bounds, to: bitmap)
				let image = NSImage(size: host.bounds.size)
				image.addRepresentation(bitmap)
				return image
			}.accessibilityHidden(true))
	}
}

private struct WorkspaceEntryDragArea: NSViewRepresentable {
	let enabled: Bool
	let payloads: [EntryDragPayload]
	let isSelected: Bool
	let select: () -> Void
	let open: () -> Void
	let previewImage: () -> NSImage?

	func makeNSView(context: Context) -> EntryDragAreaView { EntryDragAreaView() }

	func updateNSView(_ view: EntryDragAreaView, context: Context) {
		view.enabled = enabled
		view.payloads = payloads
		view.isSelected = isSelected
		view.select = select
		view.open = open
		view.previewImage = previewImage
	}
}

private final class EntryDragAreaView: NSView, NSDraggingSource {
	var enabled = false
	var isSelected = false
	var payloads: [EntryDragPayload] = []
	var select: (() -> Void)?
	var open: (() -> Void)?
	var previewImage: (() -> NSImage?)?

	override func hitTest(_ point: NSPoint) -> NSView? {
		guard enabled, bounds.contains(convert(point, from: superview)), let event = NSApp.currentEvent,
			event.type == .leftMouseDown,
			event.modifierFlags.intersection([.shift, .command, .control, .option]).isEmpty
		else { return nil }
		return self
	}

	override func mouseDown(with event: NSEvent) {
		guard let window else { return }
		var parent = superview
		while let view = parent, !(view is NSOutlineView) { parent = view.superview }
		let outline = parent as? NSOutlineView
		if let outline {
			window.makeFirstResponder(outline)
			let row = outline.row(at: outline.convert(event.locationInWindow, from: nil))
			if row >= 0 && !isSelected { outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
		}
		if !isSelected { select?() }
		while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
			if next.type == .leftMouseUp {
				select?()
				if event.clickCount == 2 { open?() } else if let outline { window.makeFirstResponder(outline) }
				return
			}
			guard
				hypot(
					next.locationInWindow.x - event.locationInWindow.x,
					next.locationInWindow.y - event.locationInWindow.y) >= 4,
				!payloads.isEmpty
			else { continue }
			let image = previewImage?()
			let items = payloads.compactMap { payload -> NSDraggingItem? in
				guard let data = try? JSONEncoder().encode(payload) else { return nil }
				let item = NSPasteboardItem()
				item.setData(data, forType: entryDragPasteboardType)
				let draggingItem = NSDraggingItem(pasteboardWriter: item)
				draggingItem.setDraggingFrame(bounds, contents: image)
				return draggingItem
			}
			let session = beginDraggingSession(with: items, event: next, source: self)
			session.draggingFormation = .pile
			return
		}
	}

	func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext)
		-> NSDragOperation
	{
		context == .withinApplication ? .move : []
	}
}

struct WorkspaceEntryDropTarget: ViewModifier {
	let destination: EntryDropDestination?
	@Binding var targetedDestination: EntryDropDestination?
	let perform: ([EntryDragPayload], EntryDropDestination) -> Void

	func body(content: Content) -> some View {
		if let destination {
			content.overlay(
				WorkspaceEntryDropArea(
					destination: destination,
					targetedDestination: $targetedDestination, perform: perform
				).accessibilityHidden(true))
		} else {
			content
		}
	}
}

private struct WorkspaceEntryDropArea: NSViewRepresentable {
	let destination: EntryDropDestination
	@Binding var targetedDestination: EntryDropDestination?
	let perform: ([EntryDragPayload], EntryDropDestination) -> Void

	func makeNSView(context: Context) -> EntryDropAreaView {
		let view = EntryDropAreaView()
		view.registerForDraggedTypes([entryDragPasteboardType])
		return view
	}

	func updateNSView(_ view: EntryDropAreaView, context: Context) {
		view.targeted = { target in
			if target {
				targetedDestination = destination
			} else if targetedDestination == destination {
				targetedDestination = nil
			}
		}
		view.perform = { payload in perform(payload, destination) }
	}
}

private final class EntryDropAreaView: NSView {
	var targeted: ((Bool) -> Void)?
	var perform: (([EntryDragPayload]) -> Void)?

	override func hitTest(_ point: NSPoint) -> NSView? {
		if let event = NSApp.currentEvent,
			[.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp].contains(event.type)
		{
			return nil
		}
		return super.hitTest(point)
	}

	override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
		guard sender.draggingPasteboard.availableType(from: [entryDragPasteboardType]) != nil else { return [] }
		targeted?(true)
		return .move
	}

	override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .move }
	override func draggingExited(_ sender: NSDraggingInfo?) { targeted?(false) }
	override func draggingEnded(_ sender: NSDraggingInfo) { targeted?(false) }

	override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
		targeted?(false)
		let payloads = (sender.draggingPasteboard.pasteboardItems ?? []).compactMap { item -> EntryDragPayload? in
			guard let data = item.data(forType: entryDragPasteboardType) else { return nil }
			return try? JSONDecoder().decode(EntryDragPayload.self, from: data)
		}
		guard !payloads.isEmpty else { return false }
		perform?(payloads)
		return true
	}
}
