import Foundation
import Testing
import ThingsDiaryClient
@testable import thingsdiary_mac

@Test("Entry list filters sections, searches content, and sorts by update time")
func filtersEntryList() {
    let active = listEntry(
        id: "active",
        content: "Morning Walk",
        bookmarked: true,
        updatedAt: 4
    )
    let other = listEntry(id: "other", content: "Evening", updatedAt: 3)
    let archived = listEntry(id: "archived", content: "Old walk", archived: true, updatedAt: 2)
    let deleted = listEntry(id: "deleted", content: "Deleted walk", deletedAt: 5, updatedAt: 1)
    let entries = [deleted, archived, other, active]

    #expect(visibleEntries(entries, section: .notes, query: "walk", sort: .newest) == [active])
    #expect(visibleEntries(entries, section: .bookmarks, query: "", sort: .newest) == [active])
    #expect(visibleEntries(entries, section: .archive, query: "", sort: .newest) == [archived])
    #expect(visibleEntries(entries, section: .trash, query: "", sort: .newest) == [deleted])
    #expect(visibleEntries(entries, section: .notes, query: "", sort: .oldest) == [other, active])
}

private func listEntry(
    id: String,
    content: String,
    archived: Bool = false,
    bookmarked: Bool = false,
    deletedAt: TimeInterval? = nil,
    updatedAt: TimeInterval
) -> ThingsDiaryEntry {
    ThingsDiaryEntry(
        id: id,
        diaryID: "diary-1",
        content: content,
        archived: archived,
        bookmarked: bookmarked,
        createdAt: Date(timeIntervalSince1970: 1),
        updatedAt: Date(timeIntervalSince1970: updatedAt),
        deletedAt: deletedAt.map(Date.init(timeIntervalSince1970:)),
        version: UInt64(updatedAt * 1_000)
    )
}
