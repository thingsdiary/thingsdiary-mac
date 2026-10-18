import AppKit
import SwiftUI

extension Notification.Name {
	static let entrySaveRequested = Notification.Name("entrySaveRequested")
}

private struct EntryCommands: Commands {
	var body: some Commands {
		CommandGroup(replacing: .saveItem) {
			Button("Save") {
				NotificationCenter.default.post(name: .entrySaveRequested, object: nil)
			}
			.keyboardShortcut("s", modifiers: .command)
		}
	}
}

@main
struct ThingsDiaryApp: App {
	@State private var model: ThingsDiaryAppModel

	init() {
		NSWindow.allowsAutomaticWindowTabbing = false

		#if DEBUG
			if ProcessInfo.processInfo.arguments.contains("--tab-overlap-lab") {
				_model = State(initialValue: ThingsDiaryAppModel.uiTestingWorkspace())
				return
			}
			if ProcessInfo.processInfo.arguments.contains("--ui-testing-workspace") {
				_model = State(
					initialValue: ThingsDiaryAppModel.uiTestingWorkspace(
						includesDeletedEntry: !ProcessInfo.processInfo.arguments.contains(
							"--ui-testing-empty-trash"
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
		WindowGroup {
			#if DEBUG
				if ProcessInfo.processInfo.arguments.contains("--tab-overlap-lab") {
					TabOverlapLab()
				} else {
					ContentView(model: model)
				}
			#else
				ContentView(model: model)
			#endif
		}
		.windowStyle(.hiddenTitleBar)
		.commands {
			EntryCommands()
		}
	}
}
