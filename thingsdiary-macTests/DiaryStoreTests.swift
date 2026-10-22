import Foundation
import Testing
import ThingsDiaryClient

@testable import thingsdiary

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

@Test("Diary store reopens plaintext topics and templates without a network")
func diaryStorePersistsTopicsAndTemplates() async throws {
	let fileURL = FileManager.default.temporaryDirectory
		.appending(path: "thingsdiary-store-entities-\(UUID().uuidString).json")
	defer { try? FileManager.default.removeItem(at: fileURL) }
	let diary = ThingsDiaryDiary(
		id: "diary-1",
		title: "Personal",
		description: "",
		createdAt: Date(timeIntervalSince1970: 1),
		updatedAt: Date(timeIntervalSince1970: 2),
		version: 3
	)
	let topic = ThingsDiaryTopic(
		id: "topic-1",
		diaryID: diary.id,
		title: "Work",
		description: "Work notes",
		color: "blue",
		entryPreviewable: false,
		defaultTemplateID: "template-1",
		createdAt: Date(timeIntervalSince1970: 3),
		updatedAt: Date(timeIntervalSince1970: 4),
		version: 4_000
	)
	let template = ThingsDiaryTemplate(
		id: "template-1",
		diaryID: diary.id,
		content: "# Work note",
		createdAt: Date(timeIntervalSince1970: 3),
		updatedAt: Date(timeIntervalSince1970: 4),
		version: 4_000
	)
	let store = try DiaryStore(fileURL: fileURL)

	try await store.replaceSelectedDiary(
		diary,
		entries: [],
		topics: [topic],
		templates: [template]
	)

	let reopened = try DiaryStore(fileURL: fileURL)
	#expect(await reopened.topics(diaryID: diary.id) == [topic])
	#expect(await reopened.templates(diaryID: diary.id) == [template])
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

@Test(
	"A version conflict preserves both local and server note content",
	arguments: [
		ThingsDiaryClientError.httpStatus(409, body: Data()),
		ThingsDiaryClientError.rpc(code: 1006, message: "version conflict"),
	]
)
func diaryStorePreservesEntryConflict(_ conflictError: ThingsDiaryClientError) async throws {
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
	try await store.savePendingEntry(
		PendingEntryWrite(
			operation: .update,
			entry: localEntry
		))

	try await store.synchronize(
		with: ConflictRemote(serverEntry: serverEntry, conflictError: conflictError)
	)

	#expect(await store.entries(diaryID: diary.id) == [serverEntry])
	#expect(await store.pendingEntryWrites().isEmpty)
	let reopenedStore = try DiaryStore(fileURL: fileURL)
	#expect(
		await reopenedStore.entryConflicts() == [
			DiaryEntryConflict(local: localEntry, server: serverEntry)
		])
}

@Test("Synchronization sends a pending soft delete and stores the server result")
func diaryStoreSynchronizesSoftDelete() async throws {
	let fileURL = FileManager.default.temporaryDirectory
		.appending(path: "thingsdiary-delete-\(UUID().uuidString).json")
	defer { try? FileManager.default.removeItem(at: fileURL) }
	let diary = ThingsDiaryDiary(
		id: "diary-1",
		title: "Personal",
		description: "",
		createdAt: Date(timeIntervalSince1970: 1),
		updatedAt: Date(timeIntervalSince1970: 2),
		version: 3
	)
	let deletedAt = Date(timeIntervalSince1970: 5)
	let localDeleted = ThingsDiaryEntry(
		id: "entry-1",
		diaryID: diary.id,
		content: "In trash",
		createdAt: Date(timeIntervalSince1970: 3),
		updatedAt: deletedAt,
		deletedAt: deletedAt,
		version: 5_000
	)
	let serverDeleted = ThingsDiaryEntry(
		id: localDeleted.id,
		diaryID: diary.id,
		content: localDeleted.content,
		createdAt: localDeleted.createdAt,
		updatedAt: Date(timeIntervalSince1970: 6),
		deletedAt: Date(timeIntervalSince1970: 6),
		version: 6_000
	)
	let store = try DiaryStore(fileURL: fileURL)
	try await store.replaceSelectedDiary(diary, entries: [])
	try await store.savePendingEntry(
		PendingEntryWrite(
			operation: .delete,
			entry: localDeleted
		))
	let remote = DeleteRemote(serverEntry: serverDeleted)

	try await store.synchronize(with: remote)

	#expect(await remote.deletedEntryIDs == [localDeleted.id])
	#expect(await store.pendingEntryWrites().isEmpty)
	#expect(await store.entries(diaryID: diary.id) == [serverDeleted])
}

@Test("Synchronization permanently removes a note queued while offline")
func diaryStoreSynchronizesPermanentDelete() async throws {
	let fileURL = FileManager.default.temporaryDirectory
		.appending(path: "thingsdiary-remove-\(UUID().uuidString).json")
	defer { try? FileManager.default.removeItem(at: fileURL) }
	let entry = ThingsDiaryEntry(
		id: "entry-1",
		diaryID: "diary-1",
		content: "Delete forever",
		createdAt: Date(timeIntervalSince1970: 1),
		updatedAt: Date(timeIntervalSince1970: 2),
		deletedAt: Date(timeIntervalSince1970: 2),
		version: 2_000
	)
	let store = try DiaryStore(fileURL: fileURL)
	try await store.savePendingEntry(PendingEntryWrite(operation: .remove, entry: entry))
	let remote = PermanentDeleteRemote()

	try await store.synchronize(with: remote)

	#expect(await remote.deletedEntryIDs == [entry.id])
	#expect(await remote.receivedSoftValues == [false])
	#expect(await store.entries(diaryID: entry.diaryID).isEmpty)
	#expect(await store.pendingEntryWrites().isEmpty)
}

@Test("A save queued during synchronization is sent before its caller returns")
func diaryStoreDrainsWritesQueuedDuringSynchronization() async throws {
	let fileURL = FileManager.default.temporaryDirectory
		.appending(path: "thingsdiary-pull-race-\(UUID().uuidString).json")
	defer { try? FileManager.default.removeItem(at: fileURL) }
	let diary = ThingsDiaryDiary(
		id: "diary-1",
		title: "Personal",
		description: "",
		createdAt: Date(timeIntervalSince1970: 1),
		updatedAt: Date(timeIntervalSince1970: 1),
		version: 1
	)
	let first = ThingsDiaryEntry(
		id: "entry-1",
		diaryID: diary.id,
		content: "First",
		createdAt: Date(timeIntervalSince1970: 1),
		updatedAt: Date(timeIntervalSince1970: 2),
		version: 2
	)
	let second = ThingsDiaryEntry(
		id: first.id,
		diaryID: diary.id,
		content: "Second",
		createdAt: first.createdAt,
		updatedAt: Date(timeIntervalSince1970: 3),
		version: 3
	)
	let store = try DiaryStore(fileURL: fileURL)
	try await store.replaceSelectedDiary(diary, entries: [])
	try await store.savePendingEntry(PendingEntryWrite(operation: .update, entry: first))
	let remote = DelayedUpdateRemote()
	let firstSynchronization = Task { try await store.synchronize(with: remote) }
	for _ in 0..<100 {
		if await remote.firstUpdateStarted { break }
		try await Task.sleep(for: .milliseconds(1))
	}
	#expect(await remote.firstUpdateStarted)

	try await store.savePendingEntry(PendingEntryWrite(operation: .update, entry: second))
	let secondSynchronization = Task { try await store.synchronize(with: remote) }
	try await firstSynchronization.value
	try await secondSynchronization.value

	#expect(await remote.receivedContents == ["First", "Second"])
	#expect(await store.pendingEntryWrites().isEmpty)
	#expect(await store.entries(diaryID: diary.id) == [second])
}

@Test("A stale conflict cannot remove a newer write for the same note")
func diaryStorePreservesNewerWriteAfterConflict() async throws {
	let fileURL = FileManager.default.temporaryDirectory
		.appending(path: "thingsdiary-conflict-race-\(UUID().uuidString).json")
	defer { try? FileManager.default.removeItem(at: fileURL) }
	let oldWrite = ThingsDiaryEntry(
		id: "entry-1",
		diaryID: "diary-1",
		content: "Old local",
		createdAt: Date(timeIntervalSince1970: 1),
		updatedAt: Date(timeIntervalSince1970: 2),
		version: 2
	)
	let newWrite = ThingsDiaryEntry(
		id: oldWrite.id,
		diaryID: oldWrite.diaryID,
		content: "Newest local",
		createdAt: oldWrite.createdAt,
		updatedAt: Date(timeIntervalSince1970: 3),
		version: 3
	)
	let serverEntry = ThingsDiaryEntry(
		id: oldWrite.id,
		diaryID: oldWrite.diaryID,
		content: "Server",
		createdAt: oldWrite.createdAt,
		updatedAt: Date(timeIntervalSince1970: 4),
		version: 4
	)
	let store = try DiaryStore(fileURL: fileURL)
	try await store.savePendingEntry(PendingEntryWrite(operation: .update, entry: oldWrite))
	let remote = DelayedConflictThenSuccessRemote(serverEntry: serverEntry)
	let synchronization = Task { try await store.synchronize(with: remote) }
	for _ in 0..<100 {
		if await remote.firstUpdateStarted { break }
		try await Task.sleep(for: .milliseconds(1))
	}
	#expect(await remote.firstUpdateStarted)

	try await store.savePendingEntry(PendingEntryWrite(operation: .update, entry: newWrite))
	try await synchronization.value

	#expect(await remote.receivedContents == ["Old local", "Newest local"])
	#expect(await store.pendingEntryWrites().isEmpty)
	#expect(await store.entryConflicts().isEmpty)
	#expect(await store.entries(diaryID: oldWrite.diaryID) == [newWrite])
}

private enum SyncTestFailure: Error {
	case lostResponse
}

private actor DelayedUpdateRemote: DiaryStoreRemote {
	private(set) var firstUpdateStarted = false
	private(set) var receivedContents: [String] = []

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
		receivedContents.append(params.content)
		if !firstUpdateStarted {
			firstUpdateStarted = true
			try await Task.sleep(for: .milliseconds(100))
		}
		return entry
	}
}

private actor DelayedConflictThenSuccessRemote: DiaryStoreRemote {
	let serverEntry: ThingsDiaryEntry
	private(set) var firstUpdateStarted = false
	private(set) var receivedContents: [String] = []

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
		receivedContents.append(params.content)
		if !firstUpdateStarted {
			firstUpdateStarted = true
			try await Task.sleep(for: .milliseconds(100))
			throw ThingsDiaryClientError.httpStatus(409, body: Data())
		}
		return entry
	}

	func getEntry(
		diaryID: String,
		entryID: String
	) async throws -> ThingsDiaryEntry {
		serverEntry
	}
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

private actor ConflictRemote: DiaryStoreRemote {
	let serverEntry: ThingsDiaryEntry
	let conflictError: ThingsDiaryClientError

	init(
		serverEntry: ThingsDiaryEntry,
		conflictError: ThingsDiaryClientError = .httpStatus(409, body: Data())
	) {
		self.serverEntry = serverEntry
		self.conflictError = conflictError
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
		throw conflictError
	}

	func getEntry(
		diaryID: String,
		entryID: String
	) async throws -> ThingsDiaryEntry {
		serverEntry
	}
}

private actor DeleteRemote: DiaryStoreRemote {
	let serverEntry: ThingsDiaryEntry
	private(set) var deletedEntryIDs: [String] = []

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
		throw SyncTestFailure.lostResponse
	}

	func deleteEntry(
		diaryID: String,
		entryID: String,
		soft: Bool?
	) async throws {
		deletedEntryIDs.append(entryID)
	}

	func getEntry(
		diaryID: String,
		entryID: String
	) async throws -> ThingsDiaryEntry {
		serverEntry
	}
}

private actor PermanentDeleteRemote: DiaryStoreRemote {
	private(set) var deletedEntryIDs: [String] = []
	private(set) var receivedSoftValues: [Bool?] = []

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

	func deleteEntry(
		diaryID: String,
		entryID: String,
		soft: Bool?
	) async throws {
		deletedEntryIDs.append(entryID)
		receivedSoftValues.append(soft)
	}
}
