import Foundation
import ThingsDiaryClient

nonisolated enum EntrySection: String, CaseIterable, Identifiable {
    case notes = "Notes"
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
            case .notes:
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
