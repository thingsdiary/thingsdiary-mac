import AppKit
import SwiftUI

struct EntrySaveActionKey: FocusedValueKey {
	typealias Value = () -> Void
}

extension FocusedValues {
	var entrySaveAction: EntrySaveActionKey.Value? {
		get { self[EntrySaveActionKey.self] }
		set { self[EntrySaveActionKey.self] = newValue }
	}
}

private struct EntryCommands: Commands {
	@FocusedValue(\.entrySaveAction) private var save

	var body: some Commands {
		CommandGroup(replacing: .saveItem) {
			Button("Save") {
				save?()
			}
			.disabled(save == nil)
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
