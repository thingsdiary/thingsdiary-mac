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
		}

		window.title = title
		window.titleVisibility = .hidden
		window.titlebarAppearsTransparent = true
		window.styleMask.insert(.fullSizeContentView)
		window.toolbar?.isVisible = false
		window.isMovableByWindowBackground = false
		window.titlebarSeparatorStyle = .none
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
		configuredWindow = nil
	}
}
