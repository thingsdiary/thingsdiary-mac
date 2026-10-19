import AppKit
import SwiftUI

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
		for buttonType in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
			window.standardWindowButton(buttonType)?.isHidden = false
		}

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
