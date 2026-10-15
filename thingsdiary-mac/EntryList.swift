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

nonisolated enum DiaryNavigationSelection: Hashable {
    case notes
    case bookmarks
    case topic(String)
    case archive
    case trash
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

nonisolated func visibleEntries(
    _ entries: [ThingsDiaryEntry],
    selection: DiaryNavigationSelection,
    query: String,
    sort: EntrySort
) -> [ThingsDiaryEntry] {
    let section = switch selection {
    case .notes, .topic:
        EntrySection.notes
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
