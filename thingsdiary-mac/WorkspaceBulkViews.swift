import SwiftUI
import ThingsDiaryClient

struct WorkspaceBulkRequest: Identifiable {
	let id = UUID()
	let action: WorkspaceBulkAction
	let ids: [String]
	let templates: Bool
	let contentsByID: [String: String]
	let saveIDs: [String]
	let hasUnsavedChanges: Bool
	var needsSave: Bool { !saveIDs.isEmpty }
	var confirmationButton: String { action.title }
	var confirmationMessage: String {
		var message = "This applies to \(ids.count) \(templates ? "templates" : "entries")."
		if needsSave { message += " Save their unsaved changes before continuing." }
		if action == .deletePermanently { message += " This cannot be undone." }
		if hasUnsavedChanges && (action == .deletePermanently || action == .deleteTemplates) {
			message += " Unsaved changes in these documents will also be discarded."
		}
		if action == .moveToTrash { message += " You can restore them from Trash." }
		if action == .deleteTemplates {
			message += " Topics using these templates will return to no default template."
		}
		return message
	}
}

extension WorkspaceBulkAction {
	var title: String {
		switch self {
		case .bookmark(let value): value ? "Add Bookmarks" : "Remove Bookmarks"
		case .previewHidden(let value): value ? "Hide Previews" : "Show Previews"
		case .duplicate: "Duplicate"
		case .saveAsTemplate: "Save as Template"
		case .moveToTopic: "Move to Topic…"
		case .archive(let value): value ? "Archive" : "Restore from Archive"
		case .moveToTrash: "Move to Trash"
		case .restore: "Restore"
		case .deletePermanently: "Delete Permanently"
		case .deleteTemplates: "Delete"
		case .saveContents: "Save"
		}
	}

	var symbol: String {
		switch self {
		case .bookmark(let value): value ? "bookmark" : "bookmark.slash"
		case .previewHidden(let value): value ? "eye.slash" : "eye"
		case .duplicate: "plus.square.on.square"
		case .saveAsTemplate: "doc.on.doc"
		case .moveToTopic: "tag"
		case .archive(let value): value ? "archivebox" : "arrow.uturn.backward"
		case .moveToTrash, .deletePermanently, .deleteTemplates: "trash"
		case .restore: "arrow.uturn.backward"
		case .saveContents: "square.and.arrow.down"
		}
	}

	var accessibilityID: String {
		switch self {
		case .bookmark: "bookmark"
		case .previewHidden: "preview"
		case .duplicate: "duplicate"
		case .saveAsTemplate: "save-as-template"
		case .moveToTopic: "topic"
		case .archive: "archive"
		case .moveToTrash: "trash"
		case .restore: "restore"
		case .deletePermanently: "delete"
		case .deleteTemplates: "delete-templates"
		case .saveContents: "save"
		}
	}

	var isDestructive: Bool {
		self == .moveToTrash || self == .deletePermanently || self == .deleteTemplates
	}
}

// The presentation and its selection travel together, so a sheet cannot read stale state.
struct WorkspaceTopicMoveRequest: Identifiable {
	let id = UUID()
	let ids: Set<WorkspaceTabID>
}

struct WorkspaceTopicMoveSheet: View {
	let count: Int
	let topics: [ThingsDiaryTopic]
	let currentTopicIDs: Set<String?>
	let move: (String?) -> Void
	let cancel: () -> Void
	@State private var query = ""
	@State private var searchIsFocused = false
	// Outer optional distinguishes no choice from the explicit No Topic destination.
	@State private var destination: TopicDestination?

	private enum TopicDestination: Hashable {
		case none
		case topic(String)
		var topicID: String? {
			if case .topic(let id) = self { return id }
			return nil
		}
	}

	private var destinationChangesSelection: Bool {
		guard let destination else { return false }
		return currentTopicIDs != Set([destination.topicID])
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 16) {
			Text("Move \(count) Entries to Topic").font(.title2.bold())
				.accessibilityIdentifier("bulk.topic.title")
			if currentTopicIDs.count > 1 {
				Text("Multiple topics").foregroundStyle(.secondary)
			}
			VStack(spacing: 8) {
				SearchBox(
					text: $query,
					isFocused: $searchIsFocused,
					prompt: "Search topics",
					accessibilityLabel: "Search Topics",
					accessibilityIdentifier: "bulk.topic.search"
				)
				List(selection: $destination) {
					topicRow {
						Image(systemName: "tag.slash").foregroundStyle(.secondary)
							.frame(width: 16)
						Text("No Topic")
					}
					.tag(TopicDestination.none)
					.accessibilityIdentifier("bulk.topic.none")
					ForEach(topics.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }) {
						topic in
						topicRow {
							Circle().fill(topicColor(topic.color)).frame(width: 10, height: 10)
								.frame(width: 16)
							Text(topic.title).lineLimit(1).truncationMode(.tail)
						}
						.tag(TopicDestination.topic(topic.id))
						.accessibilityIdentifier("bulk.topic.\(topic.id)")
					}
				}
				.listStyle(.inset)
				.scrollContentBackground(.hidden)
				.contentMargins(0, for: .scrollContent)
				.environment(\.defaultMinListRowHeight, 40)
				// Cancel the native inset list padding so the stack controls spacing.
				.padding(.horizontal, -10)
				.padding(.top, -12)
				.frame(minHeight: 180)
			}
			HStack {
				Spacer()
				Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
				Button("Move") { if let destination { move(destination.topicID) } }
					.keyboardShortcut(.defaultAction)
					.disabled(!destinationChangesSelection)
					.accessibilityIdentifier("bulk.topic.move")
			}
		}.padding(24).frame(width: 420, height: 380)
	}

	private func topicRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
		HStack(spacing: 10, content: content)
			.frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
			.contentShape(.rect)
			.listRowInsets(EdgeInsets(top: 0, leading: 5, bottom: 0, trailing: 5))
			.listRowSeparator(.hidden)
	}

	private func topicColor(_ hex: String) -> Color {
		guard let value = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) else {
			return .accentColor
		}
		return Color(
			red: Double((value >> 16) & 255) / 255,
			green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
	}
}
