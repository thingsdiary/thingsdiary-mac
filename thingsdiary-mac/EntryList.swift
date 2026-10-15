import Foundation
import CoreTransferable
import UniformTypeIdentifiers
import ThingsDiaryClient

nonisolated enum EntrySection: String, CaseIterable, Identifiable {
    case entries = "Entries"
    case bookmarks = "Bookmarks"
    case archive = "Archive"
    case trash = "Trash"

    var id: Self { self }
}

nonisolated enum EntrySort: String, CaseIterable, Identifiable {
    case newest = "Newest"
    case oldest = "Oldest"

    var id: Self { self }
}

nonisolated enum DiaryNavigationSelection: Hashable {
    case entries
    case bookmarks
    case topic(String)
    case archive
    case trash
}

nonisolated enum EntryAction: Equatable {
    case toggleBookmark
    case toggleArchive
    case archive
    case duplicate
    case moveToTopic
    case moveToTrash
    case restore
    case deletePermanently
}

nonisolated enum EntryDropDestination: Equatable {
    case topic(String)
    case archive
    case trash
}

nonisolated enum EntryActionRequest: Equatable {
    case moveToTopic(String)
    case archive
    case moveToTrash
}

nonisolated struct EntryDragPayload: Codable, Hashable, Transferable {
    let diaryID: String
    let entryID: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .thingsDiaryEntry)
    }
}

nonisolated extension UTType {
    static let thingsDiaryEntry = UTType(exportedAs: "com.thingsdiary.entry")
}

nonisolated func resolveEntryDrop(
    _ payload: EntryDragPayload,
    to destination: EntryDropDestination,
    diaryID: String,
    entries: [ThingsDiaryEntry]
) -> EntryActionRequest? {
    guard payload.diaryID == diaryID,
          let entry = entries.first(where: { $0.id == payload.entryID && $0.diaryID == diaryID }),
          entry.deletedAt == nil else {
        return nil
    }

    switch destination {
    case let .topic(topicID):
        guard entry.topicID != topicID else { return nil }
        return .moveToTopic(topicID)
    case .archive:
        guard !entry.archived else { return nil }
        return .archive
    case .trash:
        return .moveToTrash
    }
}

nonisolated func entryActionRequiresConfirmation(_ action: EntryAction, content: String) -> Bool {
    switch action {
    case .moveToTrash:
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    case .deletePermanently:
        true
    default:
        false
    }
}

nonisolated func availableEntryActions(for entry: ThingsDiaryEntry) -> [EntryAction] {
    if entry.deletedAt != nil {
        return [.restore, .deletePermanently]
    }
    return [
        .toggleBookmark,
        .toggleArchive,
        .duplicate,
        .moveToTopic,
        .moveToTrash,
    ]
}

nonisolated func visibleEntries(
    _ entries: [ThingsDiaryEntry],
    section: EntrySection,
    query: String,
    sort: EntrySort
) -> [ThingsDiaryEntry] {
    let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
    return entries
        .filter { entry in
            let belongsToSection = switch section {
            case .entries:
                entry.deletedAt == nil && !entry.archived
            case .bookmarks:
                entry.deletedAt == nil && !entry.archived && entry.bookmarked
            case .archive:
                entry.deletedAt == nil && entry.archived
            case .trash:
                entry.deletedAt != nil
            }
            return belongsToSection
                && (query.isEmpty || entry.content.localizedCaseInsensitiveContains(query))
        }
        .sorted { left, right in
            switch sort {
            case .newest:
                left.updatedAt == right.updatedAt
                    ? left.id < right.id
                    : left.updatedAt > right.updatedAt
            case .oldest:
                left.updatedAt == right.updatedAt
                    ? left.id < right.id
                    : left.updatedAt < right.updatedAt
            }
        }
}

nonisolated func visibleEntries(
    _ entries: [ThingsDiaryEntry],
    selection: DiaryNavigationSelection,
    query: String,
    sort: EntrySort
) -> [ThingsDiaryEntry] {
    let section = switch selection {
    case .entries, .topic:
        EntrySection.entries
    case .bookmarks:
        EntrySection.bookmarks
    case .archive:
        EntrySection.archive
    case .trash:
        EntrySection.trash
    }

    let sectionEntries = visibleEntries(entries, section: section, query: query, sort: sort)
    guard case let .topic(topicID) = selection else {
        return sectionEntries
    }
    return sectionEntries.filter { $0.topicID == topicID }
}

nonisolated struct EntryListPresentation: Equatable {
    let title: String
    let preview: String?
}

nonisolated func entryListPresentation(content: String) -> EntryListPresentation {
    let lines = content
        .split(whereSeparator: \Character.isNewline)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    guard let title = lines.first else {
        return EntryListPresentation(title: "Untitled", preview: nil)
    }
    let preview = lines.dropFirst().joined(separator: " ")
    return EntryListPresentation(title: title, preview: preview.isEmpty ? nil : preview)
}

nonisolated let maximumTopicTitleLength = 12

nonisolated func normalizedTopicTitle(_ title: String) -> String {
    String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maximumTopicTitleLength))
}
