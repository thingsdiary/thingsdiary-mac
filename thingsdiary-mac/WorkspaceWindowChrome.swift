import AppKit
import SwiftUI

nonisolated let workspaceTrafficLightsLeadingInset: CGFloat = 20

nonisolated func workspaceTitlebarCenterY(in bounds: CGRect, isFlipped: Bool) -> CGFloat {
	isFlipped
		? bounds.minY + workspaceTitlebarHeight / 2
		: bounds.maxY - workspaceTitlebarHeight / 2
}

nonisolated func workspaceTrafficLightsHorizontalOffset(closeButtonMinX: CGFloat) -> CGFloat {
	workspaceTrafficLightsLeadingInset - closeButtonMinX
}

private func positionWindowTrafficLights(in window: NSWindow) {
	guard
		let contentView = window.contentView,
		let closeButton = window.standardWindowButton(.closeButton),
		let closeButtonContainer = closeButton.superview
	else { return }

	let closeButtonFrame = contentView.convert(closeButton.frame, from: closeButtonContainer)
	let horizontalOffset = workspaceTrafficLightsHorizontalOffset(
		closeButtonMinX: closeButtonFrame.minX
	)
	let titlebarCenterY = workspaceTitlebarCenterY(
		in: contentView.bounds,
		isFlipped: contentView.isFlipped
	)

	for (buttonType, identifier) in [
		(NSWindow.ButtonType.closeButton, "window.close"),
		(.miniaturizeButton, "window.minimize"),
		(.zoomButton, "window.zoom"),
	] {
		guard
			let button = window.standardWindowButton(buttonType),
			let buttonContainer = button.superview
		else { continue }

		button.isHidden = false
		button.setAccessibilityIdentifier(identifier)
		let frameInContent = contentView.convert(button.frame, from: buttonContainer)
		let targetCenter = NSPoint(
			x: frameInContent.midX + horizontalOffset,
			y: titlebarCenterY
		)
		let centerInContainer = buttonContainer.convert(targetCenter, from: contentView)
		let targetOrigin = NSPoint(
			x: centerInContainer.x - button.frame.width / 2,
			y: centerInContainer.y - button.frame.height / 2
		)
		guard
			abs(button.frame.origin.x - targetOrigin.x) > 0.5
				|| abs(button.frame.origin.y - targetOrigin.y) > 0.5
		else { continue }
		button.setFrameOrigin(targetOrigin)
	}
}

struct AuthenticationWindowChrome: NSViewRepresentable {
	func makeNSView(context: Context) -> AuthenticationWindowChromeView {
		AuthenticationWindowChromeView()
	}

	func updateNSView(_ view: AuthenticationWindowChromeView, context: Context) {
		view.positionTrafficLights()
	}
}

final class AuthenticationWindowChromeView: NSView {
	override func viewDidMoveToWindow() {
		super.viewDidMoveToWindow()
		positionTrafficLights()
		DispatchQueue.main.async { [weak self] in
			self?.positionTrafficLights()
		}
	}

	override func layout() {
		super.layout()
		positionTrafficLights()
	}

	func positionTrafficLights() {
		guard let window else { return }
		positionWindowTrafficLights(in: window)
	}

	override func hitTest(_ point: NSPoint) -> NSView? {
		nil
	}
}

struct TitlebarMaterialBackground: NSViewRepresentable {
	func makeNSView(context: Context) -> NSVisualEffectView {
		let view = TitlebarMaterialView()
		view.blendingMode = .behindWindow
		view.material = .titlebar
		view.state = .followsWindowActiveState
		return view
	}

	func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

final class TitlebarMaterialView: NSVisualEffectView {
	override func hitTest(_ point: NSPoint) -> NSView? {
		nil
	}
}

struct WorkspaceWindowDragArea: NSViewRepresentable {
	func makeNSView(context: Context) -> WorkspaceWindowDragAreaView {
		WorkspaceWindowDragAreaView()
	}

	func updateNSView(_ view: WorkspaceWindowDragAreaView, context: Context) {}
}

final class WorkspaceWindowDragAreaView: NSView {
	override var mouseDownCanMoveWindow: Bool { true }

	override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
		true
	}

	override func mouseDown(with event: NSEvent) {
		window?.performDrag(with: event)
	}
}

struct WorkspaceContextMenuArea: NSViewRepresentable {
	let title: String
	let systemImage: String
	let isEnabled: Bool
	let primaryAction: () -> Void
	let menuAction: () -> Void

	func makeNSView(context: Context) -> WorkspaceContextMenuAreaView {
		WorkspaceContextMenuAreaView()
	}

	func updateNSView(_ nsView: WorkspaceContextMenuAreaView, context: Context) {
		nsView.title = title
		nsView.systemImage = systemImage
		nsView.isMenuItemEnabled = isEnabled
		nsView.primaryAction = primaryAction
		nsView.menuAction = menuAction
	}
}

final class WorkspaceContextMenuAreaView: NSView {
	var title = ""
	var systemImage = ""
	var isMenuItemEnabled = false
	var primaryAction: (() -> Void)?
	var menuAction: (() -> Void)?

	override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
		true
	}

	override func mouseDown(with event: NSEvent) {
	}

	override func mouseUp(with event: NSEvent) {
		primaryAction?()
	}

	override func rightMouseDown(with event: NSEvent) {
		let menu = NSMenu()
		menu.autoenablesItems = false
		let item = NSMenuItem(
			title: title,
			action: #selector(performMenuAction),
			keyEquivalent: ""
		)
		item.target = self
		item.isEnabled = isMenuItemEnabled
		item.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: title)
		menu.addItem(item)
		NSMenu.popUpContextMenu(menu, with: event, for: self)
	}

	@objc private func performMenuAction() {
		menuAction?()
	}
}

struct WorkspaceTopicColorMenuOption: Equatable {
	let id: String
	let title: String
	let hex: String
	let isSelected: Bool
}

struct WorkspaceTopicContextMenuArea: NSViewRepresentable {
	let colors: [WorkspaceTopicColorMenuOption]
	let isColorMenuEnabled: Bool
	let selectColor: (String) -> Void
	let edit: () -> Void
	let delete: () -> Void

	func makeNSView(context: Context) -> WorkspaceTopicContextMenuAreaView {
		WorkspaceTopicContextMenuAreaView()
	}

	func updateNSView(_ view: WorkspaceTopicContextMenuAreaView, context: Context) {
		view.colors = colors
		view.isColorMenuEnabled = isColorMenuEnabled
		view.selectColor = selectColor
		view.edit = edit
		view.delete = delete
	}
}

final class WorkspaceTopicContextMenuAreaView: NSView {
	var colors: [WorkspaceTopicColorMenuOption] = []
	var isColorMenuEnabled = true
	var selectColor: ((String) -> Void)?
	var edit: (() -> Void)?
	var delete: (() -> Void)?

	override func hitTest(_ point: NSPoint) -> NSView? {
		guard let event = NSApplication.shared.currentEvent else { return nil }
		switch event.type {
		case .rightMouseDown, .rightMouseUp:
			return bounds.contains(point) ? self : nil
		default:
			return nil
		}
	}

	override func rightMouseDown(with event: NSEvent) {
		let menu = NSMenu()
		menu.autoenablesItems = false

		let colorItem = NSMenuItem(
			title: "Color",
			action: nil,
			keyEquivalent: ""
		)
		colorItem.isEnabled = isColorMenuEnabled

		let colorMenu = NSMenu(title: "Color")
		colorMenu.autoenablesItems = false
		for color in colors {
			let item = NSMenuItem(
				title: color.title,
				action: #selector(performColorAction(_:)),
				keyEquivalent: ""
			)
			item.target = self
			item.representedObject = color.hex
			item.image = Self.colorCircleImage(hex: color.hex)
			item.state = color.isSelected ? .on : .off
			item.isEnabled = isColorMenuEnabled && !color.isSelected
			colorMenu.addItem(item)
		}
		colorItem.submenu = colorMenu
		menu.addItem(colorItem)
		menu.addItem(.separator())

		let editItem = NSMenuItem(
			title: "Edit",
			action: #selector(performEditAction),
			keyEquivalent: ""
		)
		editItem.target = self
		menu.addItem(editItem)

		let deleteItem = NSMenuItem(
			title: "Delete",
			action: #selector(performDeleteAction),
			keyEquivalent: ""
		)
		deleteItem.target = self
		menu.addItem(deleteItem)

		NSMenu.popUpContextMenu(menu, with: event, for: self)
	}

	@objc private func performColorAction(_ sender: NSMenuItem) {
		guard let hex = sender.representedObject as? String else { return }
		selectColor?(hex)
	}

	@objc private func performEditAction() {
		edit?()
	}

	@objc private func performDeleteAction() {
		delete?()
	}

	private static func colorCircleImage(hex: String) -> NSImage? {
		let value = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
		guard value.count == 6, let number = UInt64(value, radix: 16) else { return nil }
		let color = NSColor(
			srgbRed: CGFloat((number >> 16) & 0xff) / 255,
			green: CGFloat((number >> 8) & 0xff) / 255,
			blue: CGFloat(number & 0xff) / 255,
			alpha: 1
		)
		let image = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
			color.setFill()
			NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
			return true
		}
		image.isTemplate = false
		return image
	}
}

struct WorkspaceHorizontalResizeHandle: NSViewRepresentable {
	let accessibilityIdentifier: String
	let onChanged: (CGFloat) -> Void
	let onEnded: () -> Void

	func makeNSView(context: Context) -> WorkspaceHorizontalResizeHandleView {
		let view = WorkspaceHorizontalResizeHandleView()
		view.setAccessibilityElement(true)
		view.setAccessibilityRole(.splitter)
		view.setAccessibilityIdentifier(accessibilityIdentifier)
		view.onChanged = onChanged
		view.onEnded = onEnded
		return view
	}

	func updateNSView(_ view: WorkspaceHorizontalResizeHandleView, context: Context) {
		view.setAccessibilityIdentifier(accessibilityIdentifier)
		view.onChanged = onChanged
		view.onEnded = onEnded
	}
}

struct WorkspaceVerticalResizeDivider: View {
	let accessibilityIdentifier: String
	var height: CGFloat? = nil
	var hitWidth: CGFloat = 9
	var dividerWidth: CGFloat = 1
	let onChanged: (CGFloat) -> Void
	let onEnded: () -> Void

	var body: some View {
		WorkspaceHorizontalResizeHandle(
			accessibilityIdentifier: accessibilityIdentifier,
			onChanged: onChanged,
			onEnded: onEnded
		)
		.frame(width: hitWidth, height: height)
		.overlay {
			Rectangle()
				.fill(Color(nsColor: .separatorColor))
				.frame(width: dividerWidth)
				.allowsHitTesting(false)
		}
		.padding(.horizontal, -(hitWidth - dividerWidth) / 2)
	}
}

final class WorkspaceHorizontalResizeHandleView: NSView {
	var onChanged: ((CGFloat) -> Void)?
	var onEnded: (() -> Void)?

	private var dragStartX: CGFloat?
	private var pointerIsInside = false
	private var resizeTrackingArea: NSTrackingArea?
	private var windowWasMovable: Bool?
	private var resizeCursorIsPushed = false

	override var mouseDownCanMoveWindow: Bool { false }

	override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
		true
	}

	override func resetCursorRects() {
		addCursorRect(bounds, cursor: .resizeLeftRight)
	}

	override func updateTrackingAreas() {
		super.updateTrackingAreas()
		if let resizeTrackingArea {
			removeTrackingArea(resizeTrackingArea)
		}
		let trackingArea = NSTrackingArea(
			rect: bounds,
			options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .cursorUpdate],
			owner: self,
			userInfo: nil
		)
		addTrackingArea(trackingArea)
		resizeTrackingArea = trackingArea
	}

	override func mouseEntered(with event: NSEvent) {
		pointerIsInside = true
		pushResizeCursor()
		blockWindowMovement()
	}

	override func mouseExited(with event: NSEvent) {
		pointerIsInside = false
		if dragStartX == nil {
			popResizeCursor()
			restoreWindowMovement()
		}
	}

	override func cursorUpdate(with event: NSEvent) {
		NSCursor.resizeLeftRight.set()
	}

	override func mouseDown(with event: NSEvent) {
		pushResizeCursor()
		blockWindowMovement()
		dragStartX = event.locationInWindow.x
	}

	override func mouseDragged(with event: NSEvent) {
		guard let dragStartX else { return }
		NSCursor.resizeLeftRight.set()
		onChanged?(event.locationInWindow.x - dragStartX)
	}

	override func mouseUp(with event: NSEvent) {
		dragStartX = nil
		if !pointerIsInside {
			popResizeCursor()
			restoreWindowMovement()
		}
		onEnded?()
	}

	override func viewWillMove(toWindow newWindow: NSWindow?) {
		if newWindow !== window {
			popResizeCursor()
			restoreWindowMovement()
		}
		super.viewWillMove(toWindow: newWindow)
	}

	private func blockWindowMovement() {
		guard windowWasMovable == nil, let window else { return }
		windowWasMovable = window.isMovable
		window.isMovable = false
	}

	private func pushResizeCursor() {
		guard !resizeCursorIsPushed else {
			NSCursor.resizeLeftRight.set()
			return
		}
		NSCursor.resizeLeftRight.push()
		resizeCursorIsPushed = true
	}

	private func popResizeCursor() {
		guard resizeCursorIsPushed else { return }
		NSCursor.pop()
		resizeCursorIsPushed = false
	}

	private func restoreWindowMovement() {
		if let windowWasMovable {
			window?.isMovable = windowWasMovable
		}
		windowWasMovable = nil
	}
}

struct WorkspaceWindowChrome: NSViewRepresentable {
	let title: String
	@Binding var trafficLightsTrailingInset: CGFloat

	func makeNSView(context: Context) -> WorkspaceWindowChromeView {
		let view = WorkspaceWindowChromeView()
		view.title = title
		let inset = $trafficLightsTrailingInset
		view.trafficLightsInsetDidChange = { inset.wrappedValue = $0 }
		return view
	}

	func updateNSView(_ view: WorkspaceWindowChromeView, context: Context) {
		view.title = title
		let inset = $trafficLightsTrailingInset
		view.trafficLightsInsetDidChange = { inset.wrappedValue = $0 }
		view.applyConfiguration()
	}

	static func dismantleNSView(_ view: WorkspaceWindowChromeView, coordinator: ()) {
		view.restoreConfiguration()
	}
}

final class WorkspaceWindowChromeView: NSView {
	var trafficLightsInsetDidChange: ((CGFloat) -> Void)?
	var title = "thingsdiary" {
		didSet { applyConfiguration() }
	}

	private weak var configuredWindow: NSWindow?
	private var originalTitleVisibility: NSWindow.TitleVisibility?
	private var originalTitlebarAppearsTransparent: Bool?
	private var originalStyleMask: NSWindow.StyleMask?
	private var originalToolbarVisibility: Bool?
	private var originalMovableByBackground: Bool?
	private var originalSeparatorStyle: NSTitlebarSeparatorStyle?
	private var originalTabbingMode: NSWindow.TabbingMode?
	private var lastTrafficLightsInset: CGFloat?

	override func viewDidMoveToWindow() {
		super.viewDidMoveToWindow()
		applyConfiguration()
	}

	override func layout() {
		super.layout()
		if let window {
			window.title = title
			window.titleVisibility = .hidden
			window.titlebarAppearsTransparent = true
		}
		updateTrafficLightsInset()
	}

	override func hitTest(_ point: NSPoint) -> NSView? {
		nil
	}

	func applyConfiguration() {
		guard let window else { return }
		if configuredWindow !== window {
			restoreConfiguration()
			configuredWindow = window
			originalTitleVisibility = window.titleVisibility
			originalTitlebarAppearsTransparent = window.titlebarAppearsTransparent
			originalStyleMask = window.styleMask
			originalToolbarVisibility = window.toolbar?.isVisible
			originalMovableByBackground = window.isMovableByWindowBackground
			originalSeparatorStyle = window.titlebarSeparatorStyle
			originalTabbingMode = window.tabbingMode
		}

		window.title = title
		window.titleVisibility = .hidden
		window.titlebarAppearsTransparent = true
		window.styleMask.insert(.fullSizeContentView)
		window.toolbar?.isVisible = false
		window.isMovableByWindowBackground = false
		window.titlebarSeparatorStyle = .none
		window.tabbingMode = .disallowed
		positionWindowTrafficLights(in: window)

		DispatchQueue.main.async { [weak self] in
			self?.updateTrafficLightsInset()
		}
	}

	private func updateTrafficLightsInset() {
		guard
			let window,
			let contentView = window.contentView,
			let zoomButton = window.standardWindowButton(.zoomButton),
			let buttonContainer = zoomButton.superview
		else { return }

		positionWindowTrafficLights(in: window)

		let buttonFrame = contentView.convert(zoomButton.frame, from: buttonContainer)
		let inset = max(buttonFrame.maxX + 12, 76)
		guard lastTrafficLightsInset.map({ abs($0 - inset) > 0.5 }) ?? true else { return }
		lastTrafficLightsInset = inset
		trafficLightsInsetDidChange?(inset)
	}

	func restoreConfiguration() {
		guard let window = configuredWindow else { return }
		if let originalTitleVisibility {
			window.titleVisibility = originalTitleVisibility
		}
		if let originalTitlebarAppearsTransparent {
			window.titlebarAppearsTransparent = originalTitlebarAppearsTransparent
		}
		if let originalStyleMask {
			window.styleMask = originalStyleMask
		}
		if let originalToolbarVisibility {
			window.toolbar?.isVisible = originalToolbarVisibility
		}
		if let originalMovableByBackground {
			window.isMovableByWindowBackground = originalMovableByBackground
		}
		if let originalSeparatorStyle {
			window.titlebarSeparatorStyle = originalSeparatorStyle
		}
		if let originalTabbingMode {
			window.tabbingMode = originalTabbingMode
		}
		configuredWindow = nil
	}
}
