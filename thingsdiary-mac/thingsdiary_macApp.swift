import AppKit
import SwiftUI
import ThingsDiaryClient

struct EntrySaveActionKey: FocusedValueKey {
	typealias Value = () -> Void
}

struct EntrySaveAllActionKey: FocusedValueKey {
	typealias Value = () -> Void
}

struct EntryCloseActionKey: FocusedValueKey {
	typealias Value = () -> Void
}

struct EntryCreationActions {
	let newEntry: () -> Void
	let newBookmark: () -> Void
	let newTemplate: () -> Void
}

struct EntryCreateActionKey: FocusedValueKey {
	typealias Value = EntryCreationActions
}

struct SelectNextTabActionKey: FocusedValueKey {
	typealias Value = () -> Void
}

struct SelectPreviousTabActionKey: FocusedValueKey {
	typealias Value = () -> Void
}

struct LogoutActionKey: FocusedValueKey {
	typealias Value = () -> Void
}

struct DiaryMenuActions {
	let currentDiaryID: String
	let availableDiaries: [ThingsDiaryDiary]
	let createDiary: () -> Void
	let selectDiary: (ThingsDiaryDiary) -> Void
}

struct DiaryMenuActionKey: FocusedValueKey {
	typealias Value = DiaryMenuActions
}

extension FocusedValues {
	var entrySaveAction: EntrySaveActionKey.Value? {
		get { self[EntrySaveActionKey.self] }
		set { self[EntrySaveActionKey.self] = newValue }
	}

	var entrySaveAllAction: EntrySaveAllActionKey.Value? {
		get { self[EntrySaveAllActionKey.self] }
		set { self[EntrySaveAllActionKey.self] = newValue }
	}

	var entryCloseAction: EntryCloseActionKey.Value? {
		get { self[EntryCloseActionKey.self] }
		set { self[EntryCloseActionKey.self] = newValue }
	}

	var entryCreateAction: EntryCreateActionKey.Value? {
		get { self[EntryCreateActionKey.self] }
		set { self[EntryCreateActionKey.self] = newValue }
	}

	var selectNextTabAction: SelectNextTabActionKey.Value? {
		get { self[SelectNextTabActionKey.self] }
		set { self[SelectNextTabActionKey.self] = newValue }
	}

	var selectPreviousTabAction: SelectPreviousTabActionKey.Value? {
		get { self[SelectPreviousTabActionKey.self] }
		set { self[SelectPreviousTabActionKey.self] = newValue }
	}

	var logoutAction: LogoutActionKey.Value? {
		get { self[LogoutActionKey.self] }
		set { self[LogoutActionKey.self] = newValue }
	}

	var diaryMenuActions: DiaryMenuActionKey.Value? {
		get { self[DiaryMenuActionKey.self] }
		set { self[DiaryMenuActionKey.self] = newValue }
	}
}

private struct UITestingWindowActivator: NSViewRepresentable {
	let isEnabled: Bool

	final class ActivatorView: NSView {
		var isEnabled = false
		private var configuredWindow: NSWindow?

		override func viewDidMoveToWindow() {
			super.viewDidMoveToWindow()
			guard isEnabled, let window, configuredWindow !== window else { return }
			configuredWindow = window
			DispatchQueue.main.async {
				guard let visibleFrame = NSScreen.main?.visibleFrame else { return }
				let origin = CGPoint(
					x: visibleFrame.midX - window.frame.width / 2,
					y: visibleFrame.midY - window.frame.height / 2
				)
				window.setFrameOrigin(origin)
				window.makeKeyAndOrderFront(nil)
				NSApplication.shared.activate(ignoringOtherApps: true)
			}
		}
	}

	func makeNSView(context: Context) -> ActivatorView {
		let view = ActivatorView(frame: .zero)
		view.isEnabled = isEnabled
		return view
	}

	func updateNSView(_ view: ActivatorView, context: Context) {
		view.isEnabled = isEnabled
	}
}

private struct EntryCommands: Commands {
	@Environment(\.openWindow) private var openWindow
	@FocusedValue(\.entrySaveAction) private var save
	@FocusedValue(\.entrySaveAllAction) private var saveAll
	@FocusedValue(\.entryCloseAction) private var close
	@FocusedValue(\.entryCreateAction) private var creationActions
	@FocusedValue(\.diaryMenuActions) private var diaryMenuActions
	@FocusedValue(\.selectNextTabAction) private var selectNextTab
	@FocusedValue(\.selectPreviousTabAction) private var selectPreviousTab

	var body: some Commands {
		CommandGroup(replacing: .newItem) {
			Button("New Window") {
				openWindow(id: "main")
			}
			.keyboardShortcut("n", modifiers: [.command, .shift])

			Button("New Entry") {
				creationActions?.newEntry()
			}
			.disabled(creationActions == nil)
			.keyboardShortcut("n", modifiers: .command)

			Button("New Bookmark") {
				creationActions?.newBookmark()
			}
			.disabled(creationActions == nil)

			Button("New Template") {
				creationActions?.newTemplate()
			}
			.disabled(creationActions == nil)
		}

		CommandGroup(after: .newItem) {
			if let diaryMenuActions {
				Divider()
				Button("New Diary…", action: diaryMenuActions.createDiary)
				Menu("Change Diary") {
					ForEach(diaryMenuActions.availableDiaries) { diary in
						Button {
							diaryMenuActions.selectDiary(diary)
						} label: {
							if diary.id == diaryMenuActions.currentDiaryID {
								Label(diary.title, systemImage: "checkmark")
							} else {
								Text(diary.title)
							}
						}
						.disabled(diary.id == diaryMenuActions.currentDiaryID)
					}
				}
			}
		}

		CommandMenu("Tabs") {
			Button("Next Tab") {
				selectNextTab?()
			}
			.disabled(selectNextTab == nil)
			.keyboardShortcut(.tab, modifiers: .control)

			Button("Previous Tab") {
				selectPreviousTab?()
			}
			.disabled(selectPreviousTab == nil)
			.keyboardShortcut(.tab, modifiers: [.control, .shift])
		}

		CommandGroup(replacing: .saveItem) {
			Button("Save") {
				save?()
			}
			.disabled(save == nil)
			.keyboardShortcut("s", modifiers: .command)

			Button("Save All") {
				saveAll?()
			}
			.disabled(saveAll == nil)
			.keyboardShortcut("s", modifiers: [.command, .option])
		}

		CommandGroup(after: .saveItem) {
			Button("Close Tab") {
				close?()
			}
			.disabled(close == nil)
			.keyboardShortcut("w", modifiers: .command)

			Button("Close Window") {
				NSApp.keyWindow?.performClose(nil)
			}
			.keyboardShortcut("w", modifiers: [.command, .shift])
		}
	}
}

private struct AuthenticationCommands: Commands {
	@FocusedValue(\.logoutAction) private var logout

	var body: some Commands {
		CommandGroup(after: .appSettings) {
			if let logout {
				Button("Logout", action: logout)
			}
		}
	}
}

@main
struct ThingsDiaryApp: App {
	@State private var model: ThingsDiaryAppModel

	init() {
		NSWindow.allowsAutomaticWindowTabbing = false

		#if DEBUG
			let arguments = ProcessInfo.processInfo.arguments
			if let scenarioFlag = arguments.firstIndex(of: "--ui-testing-auth-scenario"),
				arguments.indices.contains(scenarioFlag + 1)
			{
				_model = State(
					initialValue: ThingsDiaryAppModel.uiTestingAuthentication(
						scenario: arguments[scenarioFlag + 1]
					)
				)
				return
			}
			if ProcessInfo.processInfo.arguments.contains("--tab-overlap-lab") {
				_model = State(initialValue: ThingsDiaryAppModel.uiTestingWorkspace())
				return
			}
			if ProcessInfo.processInfo.arguments.contains("--ui-testing-workspace") {
				_model = State(
					initialValue: ThingsDiaryAppModel.uiTestingWorkspace(
						includesDeletedEntry: !ProcessInfo.processInfo.arguments.contains(
							"--ui-testing-empty-trash"
						),
						includesTemplate: ProcessInfo.processInfo.arguments.contains(
							"--ui-testing-template"
						),
						includesMultipleDiaries: ProcessInfo.processInfo.arguments.contains(
							"--ui-testing-multiple-diaries"
						),
						includesHiddenPreviews: ProcessInfo.processInfo.arguments.contains(
							"--ui-testing-hidden-previews"
						)
					)
				)
				return
			}
		#endif

		let applicationSupport = FileManager.default.urls(
			for: .applicationSupportDirectory,
			in: .userDomainMask
		)[0]
		let store = try? DiaryStore(
			fileURL:
				applicationSupport
				.appending(path: "ThingsDiary", directoryHint: .isDirectory)
				.appending(path: "state.json"))
		_model = State(initialValue: ThingsDiaryAppModel(store: store))
	}

	var body: some Scene {
		WindowGroup(id: "main") {
			#if DEBUG
				if ProcessInfo.processInfo.arguments.contains("--tab-overlap-lab") {
					TabOverlapLab()
				} else {
					ContentView(model: model)
						.background(
							UITestingWindowActivator(
								isEnabled: ProcessInfo.processInfo.arguments.contains("--ui-testing-workspace")
									|| ProcessInfo.processInfo.arguments.contains("--ui-testing-auth-scenario")
							)
						)
				}
			#else
				ContentView(model: model)
			#endif
		}
		.windowStyle(.hiddenTitleBar)
		.commands {
			AuthenticationCommands()
			EntryCommands()
		}
	}
}
