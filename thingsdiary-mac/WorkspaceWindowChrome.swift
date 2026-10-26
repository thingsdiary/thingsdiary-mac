import AppKit
import SwiftUI
import ThingsDiaryClient

nonisolated let workspaceTrafficLightsLeadingInset: CGFloat = 20

private func markMenuItemDestructive(_ item: NSMenuItem) {
	item.attributedTitle = NSAttributedString(
		string: item.title,
		attributes: [.foregroundColor: NSColor.systemRed]
	)
}

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

struct WorkspaceTabMenuItem {
	let title: String
	var isEnabled = true
	var isDestructive = false
	var isSelected = false
	var children: [WorkspaceTabMenuItem]? = nil
	var action: (() -> Void)? = nil

	static var separator: Self { Self(title: "") }
}

struct WorkspaceTabContextMenuArea: NSViewRepresentable {
	let items: [WorkspaceTabMenuItem]

	func makeNSView(context: Context) -> WorkspaceTabContextMenuAreaView {
		WorkspaceTabContextMenuAreaView()
	}

	func updateNSView(_ view: WorkspaceTabContextMenuAreaView, context: Context) {
		view.items = items
	}
}

final class WorkspaceTabContextMenuAreaView: NSView {
	var items: [WorkspaceTabMenuItem] = []

	override func hitTest(_ point: NSPoint) -> NSView? {
		guard bounds.contains(convert(point, from: superview)),
			let event = NSApplication.shared.currentEvent
		else { return nil }
		switch event.type {
		case .rightMouseDown, .rightMouseUp:
			return self
		case .leftMouseDown where event.modifierFlags.contains(.control):
			return self
		default:
			return nil
		}
	}

	override func mouseDown(with event: NSEvent) {
		if event.modifierFlags.contains(.control) {
			NSMenu.popUpContextMenu(makeMenu(), with: event, for: self)
		} else {
			super.mouseDown(with: event)
		}
	}

	override func rightMouseDown(with event: NSEvent) {
		NSMenu.popUpContextMenu(makeMenu(), with: event, for: self)
	}

	func makeMenu() -> NSMenu { makeMenu(items: items) }

	private func makeMenu(items: [WorkspaceTabMenuItem]) -> NSMenu {
		let menu = NSMenu()
		menu.autoenablesItems = false
		for item in items {
			guard !item.title.isEmpty else {
				menu.addItem(.separator())
				continue
			}
			let nativeItem = NSMenuItem(
				title: item.title,
				action: item.action == nil ? nil : #selector(performAction(_:)),
				keyEquivalent: ""
			)
			nativeItem.target = self
			nativeItem.representedObject = item
			nativeItem.isEnabled = item.isEnabled
			nativeItem.state = item.isSelected ? .on : .off
			if item.isDestructive { markMenuItemDestructive(nativeItem) }
			if let children = item.children { nativeItem.submenu = makeMenu(items: children) }
			menu.addItem(nativeItem)
		}
		return menu
	}

	@objc private func performAction(_ sender: NSMenuItem) {
		guard sender.isEnabled, let item = sender.representedObject as? WorkspaceTabMenuItem else { return }
		item.action?()
	}
}

struct WorkspaceEntryContextMenuArea: NSViewRepresentable {
	let entry: ThingsDiaryEntry
	let topics: [ThingsDiaryTopic]
	let isEphemeral: Bool
	let togglePreview: () -> Void
	let editTopic: (ThingsDiaryTopic) -> Void
	let perform: (EntryAction, String?) -> Void

	func makeNSView(context: Context) -> WorkspaceEntryContextMenuAreaView {
		WorkspaceEntryContextMenuAreaView()
	}

	func updateNSView(_ view: WorkspaceEntryContextMenuAreaView, context: Context) {
		view.entry = entry
		view.topics = topics
		view.isEphemeral = isEphemeral
		view.togglePreview = togglePreview
		view.editTopic = editTopic
		view.perform = perform
	}
}

final class WorkspaceEntryContextMenuAreaView: NSView {
	var entry: ThingsDiaryEntry?
	var topics: [ThingsDiaryTopic] = []
	var isEphemeral = false
	var togglePreview: (() -> Void)?
	var editTopic: ((ThingsDiaryTopic) -> Void)?
	var perform: ((EntryAction, String?) -> Void)?

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
		NSMenu.popUpContextMenu(makeMenu(), with: event, for: self)
	}

	func makeMenu() -> NSMenu {
		let menu = NSMenu()
		menu.autoenablesItems = false
		guard let entry else { return menu }
		let actions = availableEntryActions(for: entry)

		if actions.contains(.restore) {
			menu.addItem(
				menuItem(
					title: "Restore",
					action: #selector(performRestoreAction)
				)
			)
		}

		if actions.contains(.toggleBookmark) {
			menu.addItem(
				menuItem(
					title: entry.bookmarked ? "Remove Bookmark" : "Add Bookmark",
					action: #selector(performToggleBookmarkAction)
				)
			)
		}

		let topic = topics.first { $0.id == entry.topicID }
		let preview = EntryPreviewMenuState(
			entryHidesPreview: entry.previewHidden,
			topicHidesPreview: topic?.entryPreviewable == false
		)
		let previewItem = menuItem(
			title: preview.title,
			action: #selector(performTogglePreviewAction)
		)
		previewItem.isEnabled = !preview.topicHidesPreview && !isEphemeral && entry.deletedAt == nil
		menu.addItem(previewItem)
		if preview.topicHidesPreview {
			menu.addItem(menuItem(title: "Topic Settings…", action: #selector(performEditTopicAction)))
		}

		if actions.contains(.duplicate) {
			let duplicate = menuItem(
				title: "Duplicate",
				action: #selector(performDuplicateAction)
			)
			duplicate.isEnabled = !isEphemeral
			menu.addItem(duplicate)
		}

		if actions.contains(.saveAsTemplate) {
			menu.addItem(
				menuItem(
					title: "Save as Template",
					action: #selector(performSaveAsTemplateAction)
				)
			)
		}

		if actions.contains(.moveToTopic),
			shouldShowTopicAssignmentMenu(
				topicCount: topics.count,
				currentTopicID: entry.topicID
			)
		{
			menu.addItem(topicAssignmentItem(for: entry))
		}

		if actions.contains(.moveToTrash) || actions.contains(.deletePermanently) {
			menu.addItem(.separator())
		}

		if actions.contains(.toggleArchive) {
			let archive = menuItem(
				title: entry.archived ? "Restore from Archive" : "Archive",
				action: #selector(performToggleArchiveAction)
			)
			archive.isEnabled = !isEphemeral
			menu.addItem(archive)
		}

		if actions.contains(.moveToTrash) {
			let trash = menuItem(
				title: "Move to Trash",
				action: #selector(performMoveToTrashAction)
			)
			trash.isEnabled = !isEphemeral
			markMenuItemDestructive(trash)
			menu.addItem(trash)
		}

		if actions.contains(.deletePermanently) {
			let delete = menuItem(
				title: "Delete Permanently",
				action: #selector(performDeletePermanentlyAction)
			)
			markMenuItemDestructive(delete)
			menu.addItem(delete)
		}

		return menu
	}

	private func menuItem(title: String, action: Selector?) -> NSMenuItem {
		let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
		item.target = self
		return item
	}

	private func topicAssignmentItem(for entry: ThingsDiaryEntry) -> NSMenuItem {
		let item = menuItem(title: "Move to Topic", action: nil)
		let submenu = NSMenu(title: "Move to Topic")
		submenu.autoenablesItems = false

		if let currentTopicID = entry.topicID,
			!topics.contains(where: { $0.id == currentTopicID })
		{
			let unavailable = NSMenuItem(
				title: "Unavailable Topic",
				action: nil,
				keyEquivalent: ""
			)
			unavailable.state = .on
			unavailable.isEnabled = false
			submenu.addItem(unavailable)
			submenu.addItem(.separator())
		}

		let noTopic = NSMenuItem(
			title: "No Topic",
			action: #selector(performMoveToTopicAction(_:)),
			keyEquivalent: ""
		)
		noTopic.target = self
		noTopic.representedObject = WorkspaceEntryTopicSelection(topicID: nil)
		noTopic.state = entry.topicID == nil ? .on : .off
		submenu.addItem(noTopic)

		if !topics.isEmpty {
			submenu.addItem(.separator())
		}
		for topic in topics {
			let topicItem = NSMenuItem(
				title: topic.title,
				action: #selector(performMoveToTopicAction(_:)),
				keyEquivalent: ""
			)
			topicItem.target = self
			topicItem.representedObject = WorkspaceEntryTopicSelection(topicID: topic.id)
			topicItem.state = entry.topicID == topic.id ? .on : .off
			submenu.addItem(topicItem)
		}
		item.submenu = submenu
		return item
	}

	@objc private func performRestoreAction() {
		perform?(.restore, nil)
	}

	@objc private func performToggleBookmarkAction() {
		perform?(.toggleBookmark, nil)
	}

	@objc private func performTogglePreviewAction() {
		guard let entry,
			entry.deletedAt == nil, !isEphemeral,
			topics.first(where: { $0.id == entry.topicID })?.entryPreviewable != false
		else { return }
		togglePreview?()
	}

	@objc private func performEditTopicAction() {
		guard let entry, let topic = topics.first(where: { $0.id == entry.topicID }) else { return }
		editTopic?(topic)
	}

	@objc private func performDuplicateAction() {
		perform?(.duplicate, nil)
	}

	@objc private func performSaveAsTemplateAction() {
		perform?(.saveAsTemplate, nil)
	}

	@objc private func performToggleArchiveAction() {
		perform?(.toggleArchive, nil)
	}

	@objc private func performMoveToTrashAction() {
		perform?(.moveToTrash, nil)
	}

	@objc private func performDeletePermanentlyAction() {
		perform?(.deletePermanently, nil)
	}

	@objc private func performMoveToTopicAction(_ sender: NSMenuItem) {
		guard let selection = sender.representedObject as? WorkspaceEntryTopicSelection else {
			return
		}
		perform?(.moveToTopic, selection.topicID)
	}
}

private final class WorkspaceEntryTopicSelection: NSObject {
	let topicID: String?

	init(topicID: String?) {
		self.topicID = topicID
	}
}

struct WorkspaceTemplateContextMenuArea: NSViewRepresentable {
	let delete: () -> Void

	func makeNSView(context: Context) -> WorkspaceTemplateContextMenuAreaView {
		WorkspaceTemplateContextMenuAreaView()
	}

	func updateNSView(_ view: WorkspaceTemplateContextMenuAreaView, context: Context) {
		view.delete = delete
	}
}

final class WorkspaceTemplateContextMenuAreaView: NSView {
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
		NSMenu.popUpContextMenu(makeMenu(), with: event, for: self)
	}

	func makeMenu() -> NSMenu {
		let menu = NSMenu()
		menu.autoenablesItems = false
		let item = NSMenuItem(
			title: "Delete",
			action: #selector(performDeleteAction),
			keyEquivalent: ""
		)
		item.target = self
		markMenuItemDestructive(item)
		menu.addItem(item)
		return menu
	}

	@objc private func performDeleteAction() {
		delete?()
	}
}

struct WorkspaceContextMenuArea: NSViewRepresentable {
	let title: String
	let isEnabled: Bool
	let primaryAction: () -> Void
	let menuAction: () -> Void

	func makeNSView(context: Context) -> WorkspaceContextMenuAreaView {
		WorkspaceContextMenuAreaView()
	}

	func updateNSView(_ nsView: WorkspaceContextMenuAreaView, context: Context) {
		nsView.title = title
		nsView.isMenuItemEnabled = isEnabled
		nsView.primaryAction = primaryAction
		nsView.menuAction = menuAction
	}
}

final class WorkspaceContextMenuAreaView: NSView {
	var title = ""
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
		let menu = makeMenu()
		NSMenu.popUpContextMenu(menu, with: event, for: self)
	}

	func makeMenu() -> NSMenu {
		let menu = NSMenu()
		menu.autoenablesItems = false
		let item = NSMenuItem(
			title: title,
			action: #selector(performMenuAction),
			keyEquivalent: ""
		)
		item.target = self
		item.isEnabled = isMenuItemEnabled
		markMenuItemDestructive(item)
		menu.addItem(item)
		return menu
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

struct WorkspaceTopicTemplateMenuOption: Equatable {
	let id: String
	let title: String
	let isSelected: Bool
}

struct WorkspaceTopicContextMenuArea: NSViewRepresentable {
	let templates: [WorkspaceTopicTemplateMenuOption]
	let hasDefaultTemplate: Bool
	let colors: [WorkspaceTopicColorMenuOption]
	let showsPreviews: Bool
	let isUpdateEnabled: Bool
	let createEntry: () -> Void
	let selectDefaultTemplate: (String?) -> Void
	let togglePreviews: () -> Void
	let selectColor: (String) -> Void
	let edit: () -> Void
	let delete: () -> Void

	func makeNSView(context: Context) -> WorkspaceTopicContextMenuAreaView {
		WorkspaceTopicContextMenuAreaView()
	}

	func updateNSView(_ view: WorkspaceTopicContextMenuAreaView, context: Context) {
		view.templates = templates
		view.hasDefaultTemplate = hasDefaultTemplate
		view.colors = colors
		view.showsPreviews = showsPreviews
		view.isUpdateEnabled = isUpdateEnabled
		view.createEntry = createEntry
		view.selectDefaultTemplate = selectDefaultTemplate
		view.togglePreviews = togglePreviews
		view.selectColor = selectColor
		view.edit = edit
		view.delete = delete
	}
}

final class WorkspaceTopicContextMenuAreaView: NSView {
	var templates: [WorkspaceTopicTemplateMenuOption] = []
	var hasDefaultTemplate = false
	var colors: [WorkspaceTopicColorMenuOption] = []
	var showsPreviews = true
	var isUpdateEnabled = true
	var createEntry: (() -> Void)?
	var selectDefaultTemplate: ((String?) -> Void)?
	var togglePreviews: (() -> Void)?
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
		let menu = makeMenu()
		NSMenu.popUpContextMenu(menu, with: event, for: self)
	}

	func makeMenu() -> NSMenu {
		let menu = NSMenu()
		menu.autoenablesItems = false

		let newEntryItem = NSMenuItem(
			title: "New Entry",
			action: #selector(performCreateEntryAction),
			keyEquivalent: ""
		)
		newEntryItem.target = self
		menu.addItem(newEntryItem)
		menu.addItem(.separator())

		let defaultTemplateItem = NSMenuItem(
			title: "Default Template",
			action: nil,
			keyEquivalent: ""
		)
		defaultTemplateItem.isEnabled = isUpdateEnabled
		let defaultTemplateMenu = NSMenu(title: "Default Template")
		defaultTemplateMenu.autoenablesItems = false
		let noTemplateItem = NSMenuItem(
			title: "None",
			action: #selector(performDefaultTemplateAction(_:)),
			keyEquivalent: ""
		)
		noTemplateItem.target = self
		noTemplateItem.state = hasDefaultTemplate ? .off : .on
		noTemplateItem.isEnabled = isUpdateEnabled && hasDefaultTemplate
		defaultTemplateMenu.addItem(noTemplateItem)
		if !templates.isEmpty {
			defaultTemplateMenu.addItem(.separator())
		}
		for template in templates {
			let item = NSMenuItem(
				title: template.title,
				action: #selector(performDefaultTemplateAction(_:)),
				keyEquivalent: ""
			)
			item.target = self
			item.representedObject = template.id
			item.state = template.isSelected ? .on : .off
			item.isEnabled = isUpdateEnabled && !template.isSelected
			defaultTemplateMenu.addItem(item)
		}
		defaultTemplateItem.submenu = defaultTemplateMenu
		menu.addItem(defaultTemplateItem)

		let previewsItem = NSMenuItem(
			title: showsPreviews ? "Hide Previews" : "Show Previews",
			action: #selector(performTogglePreviewsAction),
			keyEquivalent: ""
		)
		previewsItem.target = self
		previewsItem.isEnabled = isUpdateEnabled
		menu.addItem(previewsItem)

		let colorItem = NSMenuItem(
			title: "Color",
			action: nil,
			keyEquivalent: ""
		)
		colorItem.isEnabled = isUpdateEnabled

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
			item.isEnabled = isUpdateEnabled && !color.isSelected
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
		markMenuItemDestructive(deleteItem)
		menu.addItem(deleteItem)

		return menu
	}

	@objc private func performCreateEntryAction() {
		createEntry?()
	}

	@objc private func performDefaultTemplateAction(_ sender: NSMenuItem) {
		selectDefaultTemplate?(sender.representedObject as? String)
	}

	@objc private func performTogglePreviewsAction() {
		togglePreviews?()
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
