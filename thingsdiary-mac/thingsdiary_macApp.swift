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
			EntryCommands()
		}
	}
}
