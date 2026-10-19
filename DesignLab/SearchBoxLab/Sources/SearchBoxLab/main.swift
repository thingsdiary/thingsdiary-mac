import AppKit
import SwiftUI

private final class LabAppDelegate: NSObject, NSApplicationDelegate {
	func applicationDidFinishLaunching(_ notification: Notification) {
		NSApp.setActivationPolicy(.regular)
		NSApp.activate(ignoringOtherApps: true)
	}
}

@main
struct SearchBoxLabApp: App {
	@NSApplicationDelegateAdaptor(LabAppDelegate.self) private var appDelegate

	var body: some Scene {
		WindowGroup("Search box lab") {
			SearchBoxLab()
		}
		.defaultSize(width: 1_280, height: 900)
	}
}

private enum SearchBoxVariant: String, CaseIterable, Identifiable {
	case softFill
	case compactPill
	case minimalBorder
	case elevated
	case accentFocus
	case toolbar
	case underline
	case sidebarInset
	case editorial

	var id: Self { self }

	var title: String {
		switch self {
		case .softFill: "Soft fill"
		case .compactPill: "Compact pill"
		case .minimalBorder: "Minimal border"
		case .elevated: "Elevated card"
		case .accentFocus: "Accent focus"
		case .toolbar: "Toolbar control"
		case .underline: "Underline"
		case .sidebarInset: "Sidebar inset"
		case .editorial: "Editorial"
		}
	}

	var note: String {
		switch self {
		case .softFill: "Quiet default for lists"
		case .compactPill: "Smallest vertical footprint"
		case .minimalBorder: "Neutral and precise"
		case .elevated: "Strong separation from content"
		case .accentFocus: "Focus is impossible to miss"
		case .toolbar: "Feels native in a command row"
		case .underline: "Lightest visual treatment"
		case .sidebarInset: "Matches navigation surfaces"
		case .editorial: "More character, less utility-like"
		}
	}

	var height: CGFloat {
		switch self {
		case .compactPill, .toolbar: 30
		case .underline: 34
		default: 36
		}
	}

	var cornerRadius: CGFloat {
		switch self {
		case .compactPill, .toolbar: height / 2
		case .editorial: 4
		default: 9
		}
	}

	var horizontalPadding: CGFloat {
		switch self {
		case .compactPill, .toolbar: 10
		default: 11
		}
	}

	var showsShortcut: Bool { self == .toolbar }
	var usesUnderline: Bool { self == .underline }
	var usesShadow: Bool { self == .elevated }
}

private struct SearchBoxLab: View {
	var body: some View {
		TabView {
			SearchVariantsGallery()
				.tabItem {
					Label("Variants", systemImage: "square.grid.3x3")
				}

			EntriesIntegrationLab()
				.tabItem {
					Label("Entries", systemImage: "rectangle.split.3x1")
				}
		}
	}
}

private struct SearchVariantsGallery: View {
	private let columns = [
		GridItem(.adaptive(minimum: 340, maximum: 430), spacing: 16)
	]

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 22) {
				header

				LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
					ForEach(SearchBoxVariant.allCases) { variant in
						VariantCard(variant: variant)
					}
				}
			}
			.padding(24)
		}
		.background(Color(nsColor: .windowBackgroundColor))
	}

	private var header: some View {
		VStack(alignment: .leading, spacing: 7) {
			Text("Search box lab")
				.font(.largeTitle.bold())
			Text("Nine custom directions for the shared search component")
				.font(.title3)
				.foregroundStyle(.secondary)
			Text(
				"Click to focus, type to filter, use the clear button, or press Escape. A second Escape releases focus."
			)
			.font(.callout)
			.foregroundStyle(.secondary)
		}
	}
}

private struct EntriesIntegrationLab: View {
	@State private var variant = SearchBoxVariant.softFill

	var body: some View {
		VStack(spacing: 0) {
			HStack(spacing: 12) {
				VStack(alignment: .leading, spacing: 2) {
					Text("Entries preview")
						.font(.headline)
					Text("Change the search style without leaving the real layout")
						.font(.caption)
						.foregroundStyle(.secondary)
				}

				Spacer()

				Picker("Search style", selection: $variant) {
					ForEach(SearchBoxVariant.allCases) { item in
						Text(item.title).tag(item)
					}
				}
				.pickerStyle(.menu)
				.frame(width: 210)
			}
			.padding(.horizontal, 18)
			.padding(.vertical, 12)
			.background(Color(nsColor: .windowBackgroundColor))

			Divider()

			EntriesPreview(searchVariant: variant)
		}
		.background(Color(nsColor: .windowBackgroundColor))
	}
}

private struct PreviewEntry: Identifiable, Hashable {
	let id: Int
	let title: String
	let excerpt: String
	let date: String
	let topic: String?
	let isBookmarked: Bool

	var fullText: String {
		"\(title) \(excerpt) \(topic ?? "")"
	}
}

private struct EntriesPreview: View {
	let searchVariant: SearchBoxVariant
	@State private var query = ""
	@State private var selectedEntryID = 1
	@FocusState private var searchIsFocused: Bool

	private let entries = [
		PreviewEntry(
			id: 1,
			title: "Decisions from the product review",
			excerpt: "Keep the entry list calm. Search should be easy to find without taking over the column.",
			date: "Today, 10:42",
			topic: "Product",
			isBookmarked: true
		),
		PreviewEntry(
			id: 2,
			title: "Morning pages",
			excerpt: "The rain finally stopped before breakfast. Walked through Vera and wrote down three ideas.",
			date: "Today, 08:15",
			topic: "Journal",
			isBookmarked: false
		),
		PreviewEntry(
			id: 3,
			title: "Books to revisit",
			excerpt: "The Design of Everyday Things, Ways of Seeing, and the old typography reference.",
			date: "Yesterday",
			topic: "Reading",
			isBookmarked: true
		),
		PreviewEntry(
			id: 4,
			title: "Trip to Kazbegi",
			excerpt: "Leave early, check the weather near the pass, and stop for khinkali on the way back.",
			date: "Oct 16",
			topic: "Travel",
			isBookmarked: false
		),
		PreviewEntry(
			id: 5,
			title: "Search behavior",
			excerpt: "Typing filters immediately. The clear button restores the list and Escape clears the same state.",
			date: "Oct 14",
			topic: "Product",
			isBookmarked: false
		),
	]

	private var filteredEntries: [PreviewEntry] {
		let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !normalizedQuery.isEmpty else { return entries }
		return entries.filter { $0.fullText.localizedCaseInsensitiveContains(normalizedQuery) }
	}

	private var selectedEntry: PreviewEntry? {
		entries.first { $0.id == selectedEntryID }
	}

	var body: some View {
		HStack(spacing: 0) {
			navigationSidebar
			Divider()
			entryList
			Divider()
			entryDetail
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.background(.background)
	}

	private var navigationSidebar: some View {
		VStack(alignment: .leading, spacing: 4) {
			HStack(spacing: 9) {
				RoundedRectangle(cornerRadius: 5)
					.fill(Color.accentColor.gradient)
					.frame(width: 28, height: 28)
					.overlay {
						Image(systemName: "book.closed.fill")
							.foregroundStyle(.white)
					}
				Text("Daily Notes")
					.font(.headline)
				Spacer()
			}
			.padding(.horizontal, 12)
			.padding(.bottom, 12)

			sidebarRow("Entries", icon: "note.text", count: 5, selected: true)
			sidebarRow("Bookmarks", icon: "bookmark", count: 2)

			Text("TOPICS")
				.font(.caption2.weight(.semibold))
				.foregroundStyle(.tertiary)
				.padding(.horizontal, 12)
				.padding(.top, 14)
				.padding(.bottom, 4)

			sidebarRow("Product", icon: "circle.fill", iconColor: .blue)
			sidebarRow("Journal", icon: "circle.fill", iconColor: .orange)
			sidebarRow("Reading", icon: "circle.fill", iconColor: .purple)
			sidebarRow("Travel", icon: "circle.fill", iconColor: .green)

			Spacer()

			Divider()
			sidebarRow("Archive", icon: "archivebox")
			sidebarRow("Trash", icon: "trash")
		}
		.padding(.vertical, 12)
		.frame(width: 210)
		.background(Color(nsColor: .underPageBackgroundColor).opacity(0.72))
	}

	private func sidebarRow(
		_ title: String,
		icon: String,
		count: Int? = nil,
		selected: Bool = false,
		iconColor: Color = .accentColor
	) -> some View {
		HStack(spacing: 8) {
			Image(systemName: icon)
				.font(.system(size: icon == "circle.fill" ? 7 : 13))
				.foregroundStyle(iconColor)
				.frame(width: 16)
			Text(title)
				.lineLimit(1)
			Spacer()
			if let count {
				Text("\(count)")
					.font(.caption.monospacedDigit())
					.foregroundStyle(.secondary)
			}
		}
		.font(.callout)
		.padding(.horizontal, 10)
		.frame(height: 30)
		.background(selected ? Color.accentColor.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 6))
		.padding(.horizontal, 6)
	}

	private var entryList: some View {
		VStack(spacing: 0) {
			HStack {
				Text("Entries")
					.font(.headline)
				Spacer()
				Button {
				} label: {
					Image(systemName: "square.and.pencil")
				}
				.buttonStyle(.plain)
				.help("New entry")
			}
			.padding(.horizontal, 16)
			.padding(.top, 14)
			.padding(.bottom, 9)

			CustomSearchBox(
				text: $query,
				isFocused: $searchIsFocused,
				variant: searchVariant,
				placeholder: "Search entries"
			)
			.padding(.horizontal, 14)
			.padding(.bottom, 10)

			Divider()

			if filteredEntries.isEmpty {
				ContentUnavailableView.search(text: query)
					.frame(maxWidth: .infinity, maxHeight: .infinity)
			} else {
				ScrollView {
					LazyVStack(spacing: 0) {
						ForEach(filteredEntries) { entry in
							entryRow(entry)
							Divider()
								.padding(.leading, 16)
						}
					}
				}
			}
		}
		.frame(width: 360)
		.background(.background)
	}

	private func entryRow(_ entry: PreviewEntry) -> some View {
		VStack(alignment: .leading, spacing: 6) {
			HStack(alignment: .firstTextBaseline, spacing: 8) {
				Text(entry.title)
					.font(.callout.weight(.semibold))
					.lineLimit(1)
				Spacer(minLength: 4)
				if entry.isBookmarked {
					Image(systemName: "bookmark.fill")
						.font(.caption2)
						.foregroundStyle(.tint)
				}
			}

			Text(entry.excerpt)
				.font(.caption)
				.foregroundStyle(.secondary)
				.lineLimit(2)
				.frame(maxWidth: .infinity, alignment: .leading)

			HStack(spacing: 6) {
				Text(entry.date)
				if let topic = entry.topic {
					Text("·")
					Text(topic)
				}
			}
			.font(.caption2)
			.foregroundStyle(.tertiary)
		}
		.padding(.horizontal, 16)
		.padding(.vertical, 12)
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(selectedEntryID == entry.id ? Color.accentColor.opacity(0.11) : .clear)
		.contentShape(Rectangle())
		.onTapGesture { selectedEntryID = entry.id }
	}

	@ViewBuilder private var entryDetail: some View {
		if let selectedEntry {
			VStack(alignment: .leading, spacing: 0) {
				HStack {
					Text(selectedEntry.date)
						.font(.caption)
						.foregroundStyle(.secondary)
					Spacer()
					Button {
					} label: {
						Image(systemName: selectedEntry.isBookmarked ? "bookmark.fill" : "bookmark")
					}
					.buttonStyle(.plain)
					Button {
					} label: {
						Image(systemName: "ellipsis")
					}
					.buttonStyle(.plain)
				}
				.padding(.horizontal, 22)
				.padding(.vertical, 14)

				Divider()

				VStack(alignment: .leading, spacing: 18) {
					Text(selectedEntry.title)
						.font(.title2.weight(.semibold))
					Text(selectedEntry.excerpt)
						.font(.body)
						.lineSpacing(5)
					if let topic = selectedEntry.topic {
						Label(topic, systemImage: "tag")
							.font(.caption)
							.foregroundStyle(.secondary)
					}
					Spacer()
				}
				.padding(28)
				.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
			}
			.background(.background)
		} else {
			ContentUnavailableView("Select an entry", systemImage: "note.text")
				.frame(maxWidth: .infinity, maxHeight: .infinity)
		}
	}
}

private struct VariantCard: View {
	let variant: SearchBoxVariant
	@State private var query = ""
	@FocusState private var isFocused: Bool

	private let notes = [
		"Morning pages",
		"Product decisions",
		"Books to revisit",
		"Trip to Tbilisi",
	]

	private var filteredNotes: [String] {
		guard !query.isEmpty else { return notes }
		return notes.filter { $0.localizedCaseInsensitiveContains(query) }
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 14) {
			HStack(alignment: .firstTextBaseline) {
				VStack(alignment: .leading, spacing: 3) {
					Text(variant.title)
						.font(.headline)
					Text(variant.note)
						.font(.caption)
						.foregroundStyle(.secondary)
				}

				Spacer()

				Text(isFocused ? "Focused" : "Idle")
					.font(.caption2.weight(.semibold))
					.foregroundStyle(isFocused ? Color.accentColor : .secondary)
					.padding(.horizontal, 7)
					.padding(.vertical, 3)
					.background(
						(isFocused ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08)),
						in: Capsule()
					)
			}

			CustomSearchBox(
				text: $query,
				isFocused: $isFocused,
				variant: variant
			)

			Divider()

			VStack(alignment: .leading, spacing: 7) {
				HStack {
					Text(query.isEmpty ? "All notes" : "Results")
						.font(.caption.weight(.semibold))
						.foregroundStyle(.secondary)
					Spacer()
					Text("\(filteredNotes.count)")
						.font(.caption.monospacedDigit())
						.foregroundStyle(.tertiary)
				}

				if filteredNotes.isEmpty {
					Text("No matches")
						.font(.callout)
						.foregroundStyle(.tertiary)
						.frame(height: 47, alignment: .topLeading)
				} else {
					ForEach(filteredNotes.prefix(3), id: \.self) { note in
						HStack(spacing: 7) {
							Circle()
								.fill(Color.secondary.opacity(0.3))
								.frame(width: 4, height: 4)
							Text(note)
								.font(.callout)
								.lineLimit(1)
						}
					}
				}
			}
			.frame(minHeight: 80, alignment: .top)
		}
		.padding(16)
		.background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
		.overlay {
			RoundedRectangle(cornerRadius: 14)
				.stroke(Color.primary.opacity(0.08), lineWidth: 1)
		}
	}
}

private struct CustomSearchBox: View {
	@Binding var text: String
	@FocusState.Binding var isFocused: Bool
	let variant: SearchBoxVariant
	var placeholder = "Search notes"
	@State private var isHovered = false

	var body: some View {
		HStack(spacing: 8) {
			Image(systemName: searchIcon)
				.font(.system(size: 13, weight: iconWeight))
				.foregroundStyle(iconColor)

			TextField("", text: $text, prompt: Text(placeholder))
				.textFieldStyle(.plain)
				.font(textFont)
				.focused($isFocused)
				.onKeyPress(.escape) {
					if text.isEmpty {
						isFocused = false
					} else {
						text = ""
					}
					return .handled
				}

			if variant.showsShortcut, text.isEmpty, !isFocused {
				Text("⌘F")
					.font(.caption2.monospaced().weight(.medium))
					.foregroundStyle(.tertiary)
					.padding(.horizontal, 5)
					.padding(.vertical, 2)
					.background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
			}

			if !text.isEmpty {
				SearchClearButton {
					text = ""
					isFocused = true
				}
				.accessibilityLabel("Clear search")
			}
		}
		.padding(.horizontal, variant.horizontalPadding)
		.frame(height: variant.height)
		.background { background }
		.overlay { border }
		.shadow(
			color: variant.usesShadow ? Color.black.opacity(isFocused ? 0.14 : 0.09) : .clear,
			radius: variant.usesShadow ? (isFocused ? 8 : 5) : 0,
			y: variant.usesShadow ? 2 : 0
		)
		.contentShape(RoundedRectangle(cornerRadius: variant.cornerRadius))
		.onTapGesture { isFocused = true }
		.onHover { isHovered = $0 }
		.animation(.easeOut(duration: 0.14), value: isFocused)
		.animation(.easeOut(duration: 0.14), value: isHovered)
	}

	@ViewBuilder
	private var background: some View {
		if variant.usesUnderline {
			Color.clear
		} else {
			RoundedRectangle(cornerRadius: variant.cornerRadius, style: .continuous)
				.fill(backgroundColor)
		}
	}

	@ViewBuilder
	private var border: some View {
		if variant.usesUnderline {
			VStack {
				Spacer()
				Rectangle()
					.fill(isFocused ? Color.accentColor : Color.primary.opacity(isHovered ? 0.28 : 0.16))
					.frame(height: isFocused ? 2 : 1)
			}
		} else {
			RoundedRectangle(cornerRadius: variant.cornerRadius, style: .continuous)
				.strokeBorder(borderColor, lineWidth: borderWidth)
		}
	}

	private var searchIcon: String {
		variant == .editorial ? "text.magnifyingglass" : "magnifyingglass"
	}

	private var iconWeight: Font.Weight {
		switch variant {
		case .compactPill, .minimalBorder: .regular
		default: .medium
		}
	}

	private var textFont: Font {
		switch variant {
		case .compactPill, .toolbar: .caption
		case .editorial: .system(.body, design: .serif)
		default: .callout
		}
	}

	private var iconColor: Color {
		if isFocused, variant == .accentFocus || variant == .editorial {
			return .accentColor
		}
		return .secondary
	}

	private var backgroundColor: Color {
		switch variant {
		case .softFill:
			Color.primary.opacity(isFocused ? 0.075 : isHovered ? 0.06 : 0.045)
		case .compactPill:
			Color.primary.opacity(isFocused ? 0.09 : 0.055)
		case .minimalBorder:
			Color.clear
		case .elevated:
			Color(nsColor: .textBackgroundColor)
		case .accentFocus:
			isFocused ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.035)
		case .toolbar:
			Color(nsColor: .windowBackgroundColor)
		case .underline:
			Color.clear
		case .sidebarInset:
			Color(nsColor: .underPageBackgroundColor).opacity(isHovered ? 0.9 : 0.72)
		case .editorial:
			Color(red: 0.96, green: 0.93, blue: 0.87).opacity(isFocused ? 0.72 : 0.5)
		}
	}

	private var borderColor: Color {
		switch variant {
		case .softFill, .compactPill:
			isFocused ? Color.accentColor.opacity(0.85) : Color.clear
		case .minimalBorder:
			isFocused ? Color.accentColor : Color.primary.opacity(isHovered ? 0.28 : 0.14)
		case .elevated:
			isFocused ? Color.accentColor.opacity(0.8) : Color.primary.opacity(0.08)
		case .accentFocus:
			isFocused ? Color.accentColor : Color.primary.opacity(0.08)
		case .toolbar:
			isFocused ? Color.accentColor.opacity(0.75) : Color.primary.opacity(0.12)
		case .underline:
			Color.clear
		case .sidebarInset:
			isFocused ? Color.accentColor.opacity(0.7) : Color.white.opacity(0.22)
		case .editorial:
			isFocused ? Color.accentColor.opacity(0.75) : Color.brown.opacity(0.22)
		}
	}

	private var borderWidth: CGFloat {
		if isFocused { return 2 }
		return 1
	}
}

private struct SearchClearButton: View {
	let action: () -> Void
	@State private var isHovered = false

	var body: some View {
		Button(action: action) {
			RoundedRectangle(cornerRadius: 5, style: .continuous)
				.fill(Color.primary.opacity(isHovered ? 0.1 : 0))
				.frame(width: 22, height: 22)
				.overlay(alignment: .center) {
					LucideCircleX()
						.stroke(
							Color.secondary,
							style: StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round)
						)
						.frame(width: 13, height: 13)
				}
				.frame(width: 28, height: 28, alignment: .center)
				.contentShape(.rect)
		}
		.buttonStyle(.plain)
		.frame(width: 28, height: 28)
		.onHover { isHovered = $0 }
		.animation(.easeOut(duration: 0.1), value: isHovered)
	}
}

private struct LucideCircleX: Shape {
	func path(in rect: CGRect) -> Path {
		let scale = min(rect.width, rect.height) / 24
		let origin = CGPoint(
			x: rect.midX - 12 * scale,
			y: rect.midY - 12 * scale
		)
		func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
			CGPoint(x: origin.x + x * scale, y: origin.y + y * scale)
		}

		var path = Path()
		path.addEllipse(
			in: CGRect(
				x: origin.x + 2 * scale,
				y: origin.y + 2 * scale,
				width: 20 * scale,
				height: 20 * scale
			)
		)
		path.move(to: point(15, 9))
		path.addLine(to: point(9, 15))
		path.move(to: point(9, 9))
		path.addLine(to: point(15, 15))
		return path
	}
}
