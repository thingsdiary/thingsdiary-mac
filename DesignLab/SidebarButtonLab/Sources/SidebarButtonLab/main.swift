import AppKit
import SwiftUI

private final class LabAppDelegate: NSObject, NSApplicationDelegate {
	func applicationDidFinishLaunching(_ notification: Notification) {
		NSApp.setActivationPolicy(.regular)
		NSApp.activate(ignoringOtherApps: true)
	}
}

@main
struct SidebarButtonLabApp: App {
	@NSApplicationDelegateAdaptor(LabAppDelegate.self) private var appDelegate

	var body: some Scene {
		WindowGroup("New Entry button lab") {
			ButtonLabView()
		}
		.defaultSize(width: 1_080, height: 840)
		.windowResizability(.contentSize)
	}
}

private enum DemoAppearance: String, CaseIterable, Identifiable {
	case system = "System"
	case light = "Light"
	case dark = "Dark"

	var id: Self { self }

	var colorScheme: ColorScheme? {
		switch self {
		case .system: nil
		case .light: .light
		case .dark: .dark
		}
	}
}

private enum ButtonVariant: String, CaseIterable, Identifiable {
	case current
	case toolbar
	case plainRow
	case neutralButton
	case sectionAction
	case footer

	var id: Self { self }

	var title: String {
		switch self {
		case .current: "Control"
		case .toolbar: "Toolbar compose"
		case .plainRow: "Command row"
		case .neutralButton: "Neutral push button"
		case .sectionAction: "Section action"
		case .footer: "Sidebar footer"
		}
	}

	var score: String {
		switch self {
		case .toolbar: "24 / 25"
		case .neutralButton: "21 / 25"
		case .plainRow: "18 / 25"
		case .sectionAction: "17 / 25"
		case .footer: "14 / 25"
		case .current: "Baseline"
		}
	}

	var verdict: String {
		switch self {
		case .current: "Action reads as another selected destination."
		case .toolbar: "Clear command hierarchy and familiar macOS placement."
		case .plainRow: "Compact, but still close to navigation rows."
		case .neutralButton: "Clearly a button, though visually heavier."
		case .sectionAction: "Clean, but the small plus is easy to miss."
		case .footer: "Separated from navigation, but too far from the work area."
		}
	}
}

private struct ButtonLabView: View {
	@State private var appearance = DemoAppearance.system
	@State private var activationCount = 0

	private let columns = [
		GridItem(.fixed(320), spacing: 18),
		GridItem(.fixed(320), spacing: 18),
		GridItem(.fixed(320), spacing: 18),
	]

	var body: some View {
		VStack(spacing: 0) {
			HStack(spacing: 16) {
				VStack(alignment: .leading, spacing: 3) {
					Text("New Entry button lab")
						.font(.title2.weight(.semibold))
					Text("Same sidebar, six command patterns. Entries stays selected in every sample.")
						.font(.callout)
						.foregroundStyle(.secondary)
				}

				Spacer()

				Picker("Appearance", selection: $appearance) {
					ForEach(DemoAppearance.allCases) { option in
						Text(option.rawValue).tag(option)
					}
				}
				.pickerStyle(.segmented)
				.frame(width: 220)
			}
			.padding(20)

			Divider()

			ScrollView {
				LazyVGrid(columns: columns, alignment: .center, spacing: 18) {
					ForEach(ButtonVariant.allCases) { variant in
						VariantCard(variant: variant) {
							activationCount += 1
						}
					}
				}
				.padding(20)
			}

			Divider()

			HStack {
				Label("Quorum pick: Toolbar compose", systemImage: "checkmark.seal.fill")
					.foregroundStyle(.green)
				Spacer()
				Text("Demo activations: \(activationCount)")
					.foregroundStyle(.secondary)
			}
			.font(.callout.weight(.medium))
			.padding(.horizontal, 20)
			.frame(height: 44)
		}
		.frame(width: 1_080, height: 840)
		.preferredColorScheme(appearance.colorScheme)
	}
}

private struct VariantCard: View {
	let variant: ButtonVariant
	let createEntry: () -> Void

	var body: some View {
		VStack(alignment: .leading, spacing: 16) {
			HStack(alignment: .firstTextBaseline) {
				Text(variant.title)
					.font(.headline)
				Spacer()
				Text(variant.score)
					.font(.caption.monospacedDigit())
					.foregroundStyle(variant == .toolbar ? .green : .secondary)
			}
			.frame(height: 22, alignment: .top)

			SidebarSample(variant: variant, createEntry: createEntry)
				.frame(height: 270)

			Text(variant.verdict)
				.font(.caption)
				.foregroundStyle(.secondary)
				.lineLimit(2, reservesSpace: true)
		}
		.padding(12)
		.background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
		.overlay {
			RoundedRectangle(cornerRadius: 12, style: .continuous)
				.stroke(
					variant == .toolbar ? Color.green.opacity(0.55) : Color.primary.opacity(0.1),
					lineWidth: variant == .toolbar ? 2 : 1
				)
		}
	}
}

private struct SidebarSample: View {
	let variant: ButtonVariant
	let createEntry: () -> Void

	var body: some View {
		VStack(spacing: 0) {
			windowBar
			Divider()
			VStack(alignment: .leading, spacing: 4) {
				if variant == .current || variant == .plainRow || variant == .neutralButton {
					createControl
				}

				if variant == .sectionAction {
					sectionHeaderAction
				}

				navigationRow("Entries", systemImage: "note.text", selected: true)
				navigationRow("Bookmarks", systemImage: "bookmark")

				Divider().padding(.vertical, 4)

				Text("TOPICS")
					.font(.caption2.weight(.semibold))
					.foregroundStyle(.tertiary)
					.padding(.horizontal, 7)
				navigationRow("Work", systemImage: "tag")

				Divider().padding(.vertical, 4)

				navigationRow("Archive", systemImage: "archivebox")
				navigationRow("Trash", systemImage: "trash")

				Spacer(minLength: 4)

				if variant == .footer {
					Divider().padding(.bottom, 5)
					plainCommand(showShortcut: false)
				}
			}
			.padding(10)
		}
		.background(.regularMaterial)
		.clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
		.overlay {
			RoundedRectangle(cornerRadius: 8, style: .continuous)
				.stroke(Color.primary.opacity(0.14), lineWidth: 1)
		}
	}

	private var windowBar: some View {
		HStack(spacing: 7) {
			Circle().fill(.red.opacity(0.8)).frame(width: 9, height: 9)
			Circle().fill(.yellow.opacity(0.8)).frame(width: 9, height: 9)
			Circle().fill(.green.opacity(0.8)).frame(width: 9, height: 9)
			Text("Personal")
				.font(.caption.weight(.medium))
				.foregroundStyle(.secondary)
			Spacer()
			if variant == .toolbar {
				Button(action: createEntry) {
					Label("New Entry", systemImage: "square.and.pencil")
				}
				.buttonStyle(.borderless)
				.controlSize(.small)
				.help("Create a new entry (⌘N)")
			}
		}
		.padding(.horizontal, 10)
		.frame(height: 34)
		.background(.bar)
	}

	@ViewBuilder
	private var createControl: some View {
		switch variant {
		case .current:
			Button(action: createEntry) {
				HStack {
					Label("New Entry", systemImage: "square.and.pencil")
					Spacer()
				}
				.padding(.horizontal, 7)
				.frame(maxWidth: .infinity, minHeight: 32)
				.background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
				.overlay {
					RoundedRectangle(cornerRadius: 7)
						.stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
				}
			}
			.buttonStyle(.plain)
		case .plainRow:
			plainCommand(showShortcut: true)
		case .neutralButton:
			Button(action: createEntry) {
				HStack {
					Label("New Entry", systemImage: "square.and.pencil")
					Spacer()
				}
				.frame(maxWidth: .infinity)
			}
			.buttonStyle(.bordered)
			.controlSize(.regular)
		default:
			EmptyView()
		}
	}

	private func plainCommand(showShortcut: Bool) -> some View {
		Button(action: createEntry) {
			HStack {
				Label("New Entry", systemImage: "square.and.pencil")
				Spacer()
				if showShortcut {
					Text("⌘N")
						.font(.caption)
						.foregroundStyle(.tertiary)
				}
			}
			.padding(.horizontal, 7)
			.frame(maxWidth: .infinity, minHeight: 30)
			.contentShape(.rect)
		}
		.buttonStyle(.plain)
	}

	private var sectionHeaderAction: some View {
		HStack {
			Text("ENTRIES")
				.font(.caption2.weight(.semibold))
				.foregroundStyle(.tertiary)
			Spacer()
			Button(action: createEntry) {
				Image(systemName: "plus")
					.frame(width: 22, height: 20)
					.contentShape(.rect)
			}
			.buttonStyle(.borderless)
			.help("Create a new entry (⌘N)")
		}
		.padding(.leading, 7)
	}

	private func navigationRow(
		_ title: String,
		systemImage: String,
		selected: Bool = false
	) -> some View {
		HStack {
			Image(systemName: systemImage)
				.frame(width: 16)
				.foregroundStyle(.tint)
			Text(title)
			Spacer()
			if title == "Entries" {
				Text("12")
					.font(.caption.monospacedDigit())
					.foregroundStyle(.secondary)
			}
		}
		.padding(.horizontal, 7)
		.frame(maxWidth: .infinity, minHeight: 30)
		.background(
			selected ? Color.accentColor.opacity(0.2) : Color.clear,
			in: RoundedRectangle(cornerRadius: 7)
		)
	}
}
