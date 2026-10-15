import Foundation
import Testing
import ThingsDiaryClient
@testable import thingsdiary_mac

@Test("Diary store reopens the selected diary and its entries without a network")
func diaryStorePersistsDownloadedState() async throws {
    let fileURL = FileManager.default.temporaryDirectory
        .appending(path: "thingsdiary-store-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: fileURL) }

    let diary = ThingsDiaryDiary(
        id: "diary-1",
        title: "Personal",
        description: "Daily notes",
        createdAt: Date(timeIntervalSince1970: 1),
        updatedAt: Date(timeIntervalSince1970: 2),
        version: 3
    )
    let entry = ThingsDiaryEntry(
        id: "entry-1",
        diaryID: diary.id,
        content: "Offline note",
        archived: true,
        bookmarked: true,
        previewHidden: true,
        createdAt: Date(timeIntervalSince1970: 4),
        updatedAt: Date(timeIntervalSince1970: 5),
        version: 6
    )

    let store = try DiaryStore(fileURL: fileURL)
    try await store.replaceSelectedDiary(diary, entries: [entry])

    let reopenedStore = try DiaryStore(fileURL: fileURL)

    #expect(await reopenedStore.selectedDiary() == diary)
    #expect(await reopenedStore.entries(diaryID: diary.id) == [entry])
}

@Test("Saving a local note persists its stable ID and outbox record together")
func diaryStorePersistsEntryAndOutboxAtomically() async throws {
    let fileURL = FileManager.default.temporaryDirectory
        .appending(path: "thingsdiary-outbox-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: fileURL) }

    let diary = ThingsDiaryDiary(
        id: "diary-1",
        title: "Personal",
        description: "",
        createdAt: Date(timeIntervalSince1970: 1),
        updatedAt: Date(timeIntervalSince1970: 2),
        version: 3
    )
    let localEntry = ThingsDiaryEntry(
        id: "client-generated-entry-id",
        diaryID: diary.id,
        content: "Created offline",
        createdAt: Date(timeIntervalSince1970: 4),
        updatedAt: Date(timeIntervalSince1970: 4),
        version: 4_000
    )
    let write = PendingEntryWrite(operation: .create, entry: localEntry)
    let store = try DiaryStore(fileURL: fileURL)
    try await store.replaceSelectedDiary(diary, entries: [])

    try await store.savePendingEntry(write)

    let reopenedStore = try DiaryStore(fileURL: fileURL)
    #expect(await reopenedStore.entries(diaryID: diary.id) == [localEntry])
    #expect(await reopenedStore.pendingEntryWrites() == [write])
}

@Test("Synchronization retries a lost create response with the same entry ID")
func diaryStoreRetriesCreateIdempotently() async throws {
    let fileURL = FileManager.default.temporaryDirectory
        .appending(path: "thingsdiary-retry-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: fileURL) }

    let localEntry = ThingsDiaryEntry(
        id: "stable-entry-id",
        diaryID: "diary-1",
        content: "Retry me",
        createdAt: Date(timeIntervalSince1970: 1),
        updatedAt: Date(timeIntervalSince1970: 1),
        version: 1_000
    )
    let serverEntry = ThingsDiaryEntry(
        id: localEntry.id,
        diaryID: localEntry.diaryID,
        content: localEntry.content,
        createdAt: localEntry.createdAt,
        updatedAt: Date(timeIntervalSince1970: 2),
        version: 2_000
    )
    let write = PendingEntryWrite(operation: .create, entry: localEntry)
    let store = try DiaryStore(fileURL: fileURL)
    let remote = LostCreateResponseRemote(serverEntry: serverEntry)
    try await store.savePendingEntry(write)

    do {
        try await store.synchronize(with: remote)
        Issue.record("Expected the first lost response to fail")
    } catch {}

    #expect(await store.pendingEntryWrites() == [write])
    try await store.synchronize(with: remote)

    #expect(await remote.receivedEntryIDs == [localEntry.id, localEntry.id])
    #expect(await store.pendingEntryWrites().isEmpty)
    #expect(await store.entries(diaryID: localEntry.diaryID) == [serverEntry])
}

@Test("Synchronization applies entry changes and deduplicates a repeated final page")
func diaryStorePullsAndCheckpointsChanges() async throws {
    let fileURL = FileManager.default.temporaryDirectory
        .appending(path: "thingsdiary-changes-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: fileURL) }

    let diary = ThingsDiaryDiary(
        id: "diary-1",
        title: "Personal",
        description: "",
        createdAt: Date(timeIntervalSince1970: 1),
        updatedAt: Date(timeIntervalSince1970: 2),
        version: 3
    )
    let oldEntry = ThingsDiaryEntry(
        id: "entry-1",
        diaryID: diary.id,
        content: "Before",
        createdAt: Date(timeIntervalSince1970: 3),
        updatedAt: Date(timeIntervalSince1970: 3),
        version: 3_000
    )
    let removedEntry = ThingsDiaryEntry(
        id: "entry-removed",
        diaryID: diary.id,
        content: "Remove me",
        createdAt: Date(timeIntervalSince1970: 3),
        updatedAt: Date(timeIntervalSince1970: 3),
        version: 3_000
    )
    let serverEntry = ThingsDiaryEntry(
        id: oldEntry.id,
        diaryID: diary.id,
        content: "After",
        createdAt: oldEntry.createdAt,
        updatedAt: Date(timeIntervalSince1970: 5),
        version: 5_000
    )
    let changedAt = Date(timeIntervalSince1970: 6)
    let changes = [
        ThingsDiaryChange(
            id: "change-update",
            createdAt: changedAt,
            operation: .updated,
            entityType: .entry,
            entityID: oldEntry.id
        ),
        ThingsDiaryChange(
            id: "change-remove",
            createdAt: changedAt,
            operation: .removed,
            entityType: .entry,
            entityID: removedEntry.id
        ),
    ]
    let remote = RepeatingChangesRemote(
        page: ThingsDiaryChangesPage(changes: changes, nextPageToken: nil),
        entries: [serverEntry.id: serverEntry]
    )
    let store = try DiaryStore(fileURL: fileURL)
    try await store.replaceSelectedDiary(diary, entries: [oldEntry, removedEntry])

    try await store.synchronize(with: remote)

    #expect(await store.entries(diaryID: diary.id) == [serverEntry])
    let reopenedStore = try DiaryStore(fileURL: fileURL)
    try await reopenedStore.synchronize(with: remote)

    #expect(await remote.requestedEntryIDs == [serverEntry.id])
    #expect(await remote.requestedSince.last == changedAt)
}

@Test("A version conflict preserves both local and server note content")
func diaryStorePreservesEntryConflict() async throws {
    let fileURL = FileManager.default.temporaryDirectory
        .appending(path: "thingsdiary-conflict-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: fileURL) }

    let diary = ThingsDiaryDiary(
        id: "diary-1",
        title: "Personal",
        description: "",
        createdAt: Date(timeIntervalSince1970: 1),
        updatedAt: Date(timeIntervalSince1970: 2),
        version: 3
    )
    let localEntry = ThingsDiaryEntry(
        id: "entry-1",
        diaryID: diary.id,
        content: "Local edit",
        createdAt: Date(timeIntervalSince1970: 3),
        updatedAt: Date(timeIntervalSince1970: 5),
        version: 5_000
    )
    let serverEntry = ThingsDiaryEntry(
        id: localEntry.id,
        diaryID: diary.id,
        content: "Server edit",
        createdAt: localEntry.createdAt,
        updatedAt: Date(timeIntervalSince1970: 6),
        version: 6_000
    )
    let store = try DiaryStore(fileURL: fileURL)
    try await store.replaceSelectedDiary(diary, entries: [])
    try await store.savePendingEntry(PendingEntryWrite(
        operation: .update,
        entry: localEntry
    ))

    try await store.synchronize(with: ConflictRemote(serverEntry: serverEntry))

    #expect(await store.entries(diaryID: diary.id) == [serverEntry])
    #expect(await store.pendingEntryWrites().isEmpty)
    let reopenedStore = try DiaryStore(fileURL: fileURL)
    #expect(await reopenedStore.entryConflicts() == [
        DiaryEntryConflict(local: localEntry, server: serverEntry),
    ])
}

private enum SyncTestFailure: Error {
    case lostResponse
}

private actor LostCreateResponseRemote: DiaryStoreRemote {
    let serverEntry: ThingsDiaryEntry
    private(set) var receivedEntryIDs: [String] = []

    init(serverEntry: ThingsDiaryEntry) {
        self.serverEntry = serverEntry
    }

    func createEntry(
        diaryID: String,
        entryID: String,
        params: ThingsDiaryEntryParams
    ) async throws -> ThingsDiaryEntry {
        receivedEntryIDs.append(entryID)
        if receivedEntryIDs.count == 1 {
            throw SyncTestFailure.lostResponse
        }
        return serverEntry
    }

    func updateEntry(
        _ entry: ThingsDiaryEntry,
        params: ThingsDiaryEntryParams
    ) async throws -> ThingsDiaryEntry {
        throw SyncTestFailure.lostResponse
    }
}

private actor RepeatingChangesRemote: DiaryStoreRemote {
    let page: ThingsDiaryChangesPage
    let storedEntries: [String: ThingsDiaryEntry]
    private(set) var requestedEntryIDs: [String] = []
    private(set) var requestedSince: [Date?] = []

    init(
        page: ThingsDiaryChangesPage,
        entries: [String: ThingsDiaryEntry]
    ) {
        self.page = page
        storedEntries = entries
    }

    func createEntry(
        diaryID: String,
        entryID: String,
        params: ThingsDiaryEntryParams
    ) async throws -> ThingsDiaryEntry {
        throw SyncTestFailure.lostResponse
    }

    func updateEntry(
        _ entry: ThingsDiaryEntry,
        params: ThingsDiaryEntryParams
    ) async throws -> ThingsDiaryEntry {
        throw SyncTestFailure.lostResponse
    }

    func getDiaryChanges(
        diaryID: String,
        since: Date?,
        limit: Int?,
        nextPageToken: String?
    ) async throws -> ThingsDiaryChangesPage {
        requestedSince.append(since)
        return page
    }

    func getEntry(
        diaryID: String,
        entryID: String
    ) async throws -> ThingsDiaryEntry {
        requestedEntryIDs.append(entryID)
        guard let entry = storedEntries[entryID] else {
            throw SyncTestFailure.lostResponse
        }
        return entry
    }
}

private actor ConflictRemote: DiaryStoreRemote {
    let serverEntry: ThingsDiaryEntry

    init(serverEntry: ThingsDiaryEntry) {
        self.serverEntry = serverEntry
    }

    func createEntry(
        diaryID: String,
        entryID: String,
        params: ThingsDiaryEntryParams
    ) async throws -> ThingsDiaryEntry {
        throw SyncTestFailure.lostResponse
    }

    func updateEntry(
        _ entry: ThingsDiaryEntry,
        params: ThingsDiaryEntryParams
    ) async throws -> ThingsDiaryEntry {
        throw ThingsDiaryClientError.httpStatus(409, body: Data())
    }

    func getEntry(
        diaryID: String,
        entryID: String
    ) async throws -> ThingsDiaryEntry {
        serverEntry
    }
}
