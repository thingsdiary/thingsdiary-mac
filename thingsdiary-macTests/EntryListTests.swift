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

    #expect(visibleEntries(entries, section: .entries, query: "walk", sort: .newest) == [active])
    #expect(visibleEntries(entries, section: .bookmarks, query: "", sort: .newest) == [active])
    #expect(visibleEntries(entries, section: .archive, query: "", sort: .newest) == [archived])
    #expect(visibleEntries(entries, section: .trash, query: "", sort: .newest) == [deleted])
    #expect(visibleEntries(entries, section: .entries, query: "", sort: .oldest) == [other, active])
}

@Test("Diary navigation filters active notes by topic")
func filtersDiaryNavigationByTopic() {
    let matching = listEntry(
        id: "matching",
        content: "Project note",
        topicID: "topic-1",
        updatedAt: 3
    )
    let anotherTopic = listEntry(
        id: "another",
        content: "Another project",
        topicID: "topic-2",
        updatedAt: 2
    )
    let archived = listEntry(
        id: "archived",
        content: "Archived project",
        archived: true,
        topicID: "topic-1",
        updatedAt: 1
    )

    #expect(visibleEntries(
        [archived, anotherTopic, matching],
        selection: .topic("topic-1"),
        query: "project",
        sort: .newest
    ) == [matching])
}

@Test("Entry actions match the note lifecycle state")
func entryActionsMatchLifecycleState() {
    let active = listEntry(id: "active", content: "Active", updatedAt: 2)
    let deleted = listEntry(
        id: "deleted",
        content: "Deleted",
        deletedAt: 3,
        updatedAt: 3
    )

    #expect(availableEntryActions(for: active) == [
        .toggleBookmark,
        .toggleArchive,
        .duplicate,
        .moveToTopic,
        .moveToTrash,
    ])
    #expect(availableEntryActions(for: deleted) == [
        .restore,
        .deletePermanently,
    ])
}

@Test("Entry drop destinations resolve only valid moves")
func resolvesEntryDropDestinations() {
    let active = listEntry(id: "active", content: "Active", topicID: "topic-1", updatedAt: 2)
    let payload = EntryDragPayload(diaryID: "diary-1", entryID: "active")
    #expect(resolveEntryDrop(payload, to: .bookmarks, diaryID: "diary-1", entries: [active]) == .bookmark)
    #expect(resolveEntryDrop(payload, to: .topic("topic-2"), diaryID: "diary-1", entries: [active]) == .moveToTopic("topic-2"))
    #expect(resolveEntryDrop(payload, to: .archive, diaryID: "diary-1", entries: [active]) == .archive)
    #expect(resolveEntryDrop(payload, to: .trash, diaryID: "diary-1", entries: [active]) == .moveToTrash)
    #expect(resolveEntryDrop(payload, to: .topic("topic-1"), diaryID: "diary-1", entries: [active]) == nil)
    #expect(resolveEntryDrop(payload, to: .archive, diaryID: "other", entries: [active]) == nil)
    #expect(resolveEntryDrop(payload, to: .trash, diaryID: "diary-1", entries: []) == nil)
    let deleted = listEntry(id: "active", content: "Active", deletedAt: 3, updatedAt: 3)
    #expect(resolveEntryDrop(payload, to: .archive, diaryID: "diary-1", entries: [deleted]) == nil)
    let archived = listEntry(id: "active", content: "Active", archived: true, updatedAt: 2)
    #expect(resolveEntryDrop(payload, to: .archive, diaryID: "diary-1", entries: [archived]) == nil)
    let bookmarked = listEntry(id: "active", content: "Active", bookmarked: true, updatedAt: 2)
    #expect(resolveEntryDrop(payload, to: .bookmarks, diaryID: "diary-1", entries: [bookmarked]) == nil)
}

@Test("Confirmation is required for destructive entry actions")
func confirmsDestructiveEntryActions() {
    #expect(entryActionRequiresConfirmation(.moveToTrash, content: "Some content"))
    #expect(!entryActionRequiresConfirmation(.moveToTrash, content: "  \n"))
    #expect(entryActionRequiresConfirmation(.deletePermanently, content: ""))
    #expect(!entryActionRequiresConfirmation(.archive, content: "Some content"))
    #expect(!entryActionRequiresConfirmation(.bookmark, content: "Some content"))
}

@Test("Entry list presentation separates title and preview")
func entryListPresentationSeparatesTitleAndPreview() {
    #expect(entryListPresentation(content: "Project plan\nFirst task\nSecond task") == EntryListPresentation(
        title: "Project plan",
        preview: "First task Second task"
    ))
    #expect(entryListPresentation(content: "  \n\n") == EntryListPresentation(
        title: "Untitled",
        preview: nil
    ))
}

@Test("Topic titles are trimmed and limited to the web client contract")
func normalizesTopicTitles() {
    #expect(normalizedTopicTitle("  Personal  ") == "Personal")
    #expect(normalizedTopicTitle("abcdefghijklmnop") == "abcdefghijkl")
}

private func listEntry(
    id: String,
    content: String,
    archived: Bool = false,
    bookmarked: Bool = false,
    topicID: String? = nil,
    deletedAt: TimeInterval? = nil,
    updatedAt: TimeInterval
) -> ThingsDiaryEntry {
    ThingsDiaryEntry(
        id: id,
        diaryID: "diary-1",
        content: content,
        topicID: topicID,
        archived: archived,
        bookmarked: bookmarked,
        createdAt: Date(timeIntervalSince1970: 1),
        updatedAt: Date(timeIntervalSince1970: updatedAt),
        deletedAt: deletedAt.map(Date.init(timeIntervalSince1970:)),
        version: UInt64(updatedAt * 1_000)
    )
}
