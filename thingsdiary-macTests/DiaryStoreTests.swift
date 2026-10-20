import Foundation
import Testing
import ThingsDiaryClient

@testable import thingsdiary

@Test("In-memory diary store uses the production persistence engine")
func diaryStoreSupportsInMemoryPersistence() async throws {
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
		createdAt: Date(timeIntervalSince1970: 4),
		updatedAt: Date(timeIntervalSince1970: 5),
		version: 6
	)
	let store = try DiaryStore.inMemory()

	try await store.replaceSelectedDiary(diary, entries: [entry])

	#expect(await store.selectedDiary() == diary)
	#expect(await store.entries(diaryID: diary.id) == [entry])
}

@Test("Diary store imports the legacy JSON once and keeps a backup")
func diaryStoreImportsLegacyJSON() async throws {
	let directory = FileManager.default.temporaryDirectory
		.appending(path: "thingsdiary-legacy-\(UUID().uuidString)", directoryHint: .isDirectory)
	defer { try? FileManager.default.removeItem(at: directory) }
	try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
	let databaseURL = directory.appending(path: "store.sqlite")
	let legacyURL = directory.appending(path: "state.json")
	let legacyData = try legacyStoreData()
	try legacyData.write(to: legacyURL)

	let store = try DiaryStore(fileURL: databaseURL, legacyJSONURL: legacyURL)

	#expect(await store.selectedDiary()?.id == "diary-1")
	#expect(await store.entries(diaryID: "diary-1").map(\.id) == ["entry-1"])
	#expect(await store.pendingEntryWrites().map(\.id) == ["entry-1"])
	#expect(try Data(contentsOf: legacyURL) == legacyData)
	#expect(try Data(contentsOf: legacyURL.appendingPathExtension("backup")) == legacyData)

	let reopened = try DiaryStore(fileURL: databaseURL, legacyJSONURL: legacyURL)
	#expect(await reopened.entries(diaryID: "diary-1").map(\.id) == ["entry-1"])
	#expect(await reopened.pendingEntryWrites().map(\.id) == ["entry-1"])

	let otherAccount = try DiaryStore(
		fileURL: directory.appending(path: "other-account.sqlite"),
		legacyJSONURL: legacyURL
	)
	#expect(await otherAccount.selectedDiary() == nil)
	#expect(await otherAccount.entries(diaryID: "diary-1").isEmpty)
}

@Test("Malformed legacy JSON leaves the source and database empty")
func diaryStoreRejectsMalformedLegacyJSONAtomically() async throws {
	let directory = FileManager.default.temporaryDirectory
		.appending(path: "thingsdiary-broken-legacy-\(UUID().uuidString)")
	defer { try? FileManager.default.removeItem(at: directory) }
	try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
	let databaseURL = directory.appending(path: "store.sqlite")
	let legacyURL = directory.appending(path: "state.json")
	let malformed = Data("{".utf8)
	try malformed.write(to: legacyURL)

	#expect(throws: (any Error).self) {
		_ = try DiaryStore(fileURL: databaseURL, legacyJSONURL: legacyURL)
	}
	#expect(try Data(contentsOf: legacyURL) == malformed)
	#expect(!FileManager.default.fileExists(atPath: legacyURL.appendingPathExtension("backup").path))

	try legacyStoreData().write(to: legacyURL)
	let recovered = try DiaryStore(fileURL: databaseURL, legacyJSONURL: legacyURL)
	#expect(await recovered.selectedDiary()?.id == "diary-1")
}

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
	let synchronizer = DiarySynchronizer(store: store, remote: remote)
	try await store.savePendingEntry(write)

	do {
		try await synchronizer.synchronize()
		Issue.record("Expected the first lost response to fail")
	} catch {}

	#expect(await store.pendingEntryWrites() == [write])
	try await synchronizer.synchronize()

	#expect(await remote.receivedEntryIDs == [localEntry.id, localEntry.id])
	#expect(await store.pendingEntryWrites().isEmpty)
	#expect(await store.entries(diaryID: localEntry.diaryID) == [serverEntry])
}

@Test("Synchronization replays an overlapping entry checkpoint idempotently")
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
	let firstCheckpoint = changedAt

	try await DiarySynchronizer(
		store: store,
		remote: remote,
		now: { firstCheckpoint }
	).synchronize()

	#expect(await store.entries(diaryID: diary.id) == [serverEntry])
	let reopenedStore = try DiaryStore(fileURL: fileURL)
	try await DiarySynchronizer(
		store: reopenedStore,
		remote: remote,
		now: { Date(timeIntervalSince1970: 20) }
	).synchronize()

	#expect(await remote.requestedEntryIDs == [serverEntry.id, serverEntry.id])
	#expect(await remote.requestedSince == [nil, firstCheckpoint])
	#expect(await reopenedStore.entries(diaryID: diary.id) == [serverEntry])
}

@Test("Synchronization replays overlapping topic and template checkpoints idempotently")
func diaryStorePullsTopicAndTemplateChanges() async throws {
	let fileURL = FileManager.default.temporaryDirectory
		.appending(path: "thingsdiary-entity-changes-\(UUID().uuidString).json")
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
		title: "Synced topic",
		description: "",
		color: "blue",
		createdAt: Date(timeIntervalSince1970: 3),
		updatedAt: Date(timeIntervalSince1970: 5),
		version: 5_000
	)
	let template = ThingsDiaryTemplate(
		id: "template-1",
		diaryID: diary.id,
		content: "# Synced template",
		createdAt: Date(timeIntervalSince1970: 3),
		updatedAt: Date(timeIntervalSince1970: 5),
		version: 5_000
	)
	let changedAt = Date(timeIntervalSince1970: 6)
	let remote = EntityChangesRemote(
		page: ThingsDiaryChangesPage(
			changes: [
				ThingsDiaryChange(
					id: "topic-change",
					createdAt: changedAt,
					operation: .updated,
					entityType: .topic,
					entityID: topic.id
				),
				ThingsDiaryChange(
					id: "template-change",
					createdAt: changedAt,
					operation: .created,
					entityType: .template,
					entityID: template.id
				),
			], nextPageToken: nil),
		topic: topic,
		template: template
	)
	let store = try DiaryStore(fileURL: fileURL)
	try await store.replaceSelectedDiary(diary, entries: [])
	let firstCheckpoint = changedAt

	try await DiarySynchronizer(
		store: store,
		remote: remote,
		now: { firstCheckpoint }
	).synchronize()

	#expect(await store.topics(diaryID: diary.id) == [topic])
	#expect(await store.templates(diaryID: diary.id) == [template])
	let reopened = try DiaryStore(fileURL: fileURL)
	try await DiarySynchronizer(
		store: reopened,
		remote: remote,
		now: { Date(timeIntervalSince1970: 20) }
	).synchronize()
	#expect(await remote.topicRequests == [topic.id, topic.id])
	#expect(await remote.templateRequests == [template.id, template.id])
	#expect(await reopened.topics(diaryID: diary.id) == [topic])
	#expect(await reopened.templates(diaryID: diary.id) == [template])
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
	try await store.savePendingEntry(
		PendingEntryWrite(
			operation: .update,
			entry: localEntry
		))

	try await DiarySynchronizer(
		store: store,
		remote: ConflictRemote(serverEntry: serverEntry)
	).synchronize()

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

	try await DiarySynchronizer(store: store, remote: remote).synchronize()

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

	try await DiarySynchronizer(store: store, remote: remote).synchronize()

	#expect(await remote.deletedEntryIDs == [entry.id])
	#expect(await remote.receivedSoftValues == [false])
	#expect(await store.entries(diaryID: entry.diaryID).isEmpty)
	#expect(await store.pendingEntryWrites().isEmpty)
}

@Test("A save queued during change pulling is synchronized before its caller returns")
func diaryStoreDrainsWritesQueuedDuringPull() async throws {
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
	let remote = DelayedPullRemote()
	let synchronizer = DiarySynchronizer(store: store, remote: remote)
	let firstSynchronization = Task { try await synchronizer.synchronize() }
	for _ in 0..<100 {
		if await remote.pullStarted { break }
		try await Task.sleep(for: .milliseconds(1))
	}
	#expect(await remote.pullStarted)

	try await store.savePendingEntry(PendingEntryWrite(operation: .update, entry: second))
	let secondSynchronization = Task { try await synchronizer.synchronize() }
	try await firstSynchronization.value
	try await secondSynchronization.value

	#expect(await remote.receivedContents == ["First", "Second"])
	#expect(await store.pendingEntryWrites().isEmpty)
	#expect(await store.entries(diaryID: diary.id) == [second])
}

@Test("A pulled entry cannot overwrite a local save made while it is loading")
func diaryStorePreservesSaveDuringEntryPull() async throws {
	let fileURL = FileManager.default.temporaryDirectory
		.appending(path: "thingsdiary-entry-pull-race-\(UUID().uuidString).json")
	defer { try? FileManager.default.removeItem(at: fileURL) }
	let diary = ThingsDiaryDiary(
		id: "diary-1",
		title: "Personal",
		description: "",
		createdAt: Date(timeIntervalSince1970: 1),
		updatedAt: Date(timeIntervalSince1970: 1),
		version: 1
	)
	let original = ThingsDiaryEntry(
		id: "entry-1",
		diaryID: diary.id,
		content: "Original",
		createdAt: Date(timeIntervalSince1970: 1),
		updatedAt: Date(timeIntervalSince1970: 1),
		version: 1
	)
	let serverEntry = ThingsDiaryEntry(
		id: original.id,
		diaryID: diary.id,
		content: "Server",
		createdAt: original.createdAt,
		updatedAt: Date(timeIntervalSince1970: 2),
		version: 2
	)
	let localEntry = ThingsDiaryEntry(
		id: original.id,
		diaryID: diary.id,
		content: "Local while pulling",
		createdAt: original.createdAt,
		updatedAt: Date(timeIntervalSince1970: 3),
		version: 3
	)
	let change = ThingsDiaryChange(
		id: "change-1",
		createdAt: Date(timeIntervalSince1970: 2),
		operation: .updated,
		entityType: .entry,
		entityID: original.id
	)
	let store = try DiaryStore(fileURL: fileURL)
	try await store.replaceSelectedDiary(diary, entries: [original])
	let remote = DelayedEntryPullRemote(change: change, serverEntry: serverEntry)
	let synchronizer = DiarySynchronizer(store: store, remote: remote)
	let synchronization = Task { try await synchronizer.synchronize() }
	for _ in 0..<100 {
		if await remote.getEntryStarted { break }
		try await Task.sleep(for: .milliseconds(1))
	}
	#expect(await remote.getEntryStarted)

	try await store.savePendingEntry(PendingEntryWrite(operation: .update, entry: localEntry))
	try await synchronization.value

	#expect(await remote.receivedUpdateContents == [localEntry.content])
	#expect(await store.pendingEntryWrites().isEmpty)
	#expect(await store.entries(diaryID: diary.id) == [localEntry])
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
	let synchronizer = DiarySynchronizer(store: store, remote: remote)
	let synchronization = Task { try await synchronizer.synchronize() }
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

private func legacyStoreData() throws -> Data {
	let diary: [String: Any] = [
		"id": "diary-1",
		"title": "Personal",
		"description": "Imported diary",
		"createdAt": 1_000,
		"updatedAt": 2_000,
		"version": 3,
	]
	let entry: [String: Any] = [
		"id": "entry-1",
		"diaryID": "diary-1",
		"content": "Imported note",
		"archived": false,
		"bookmarked": true,
		"previewHidden": false,
		"createdAt": 4_000,
		"updatedAt": 5_000,
		"version": 6,
	]
	return try JSONSerialization.data(
		withJSONObject: [
			"selectedDiary": diary,
			"entries": [entry],
			"pendingEntryWrites": [
				[
					"operation": "create",
					"entry": entry,
				]
			],
			"checkpoints": [
				"diary-1": [
					"lastChangeAt": 5_000,
					"changeIDsAtLastDate": ["change-1"],
				]
			],
		],
		options: [.sortedKeys]
	)
}

private enum SyncTestFailure: Error {
	case lostResponse
}

private actor DelayedPullRemote: DiaryStoreRemote {
	private(set) var pullStarted = false
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
		return entry
	}

	func getDiaryChanges(
		diaryID: String,
		since: Date?,
		limit: Int?,
		nextPageToken: String?
	) async throws -> ThingsDiaryChangesPage {
		if !pullStarted {
			pullStarted = true
			try await Task.sleep(for: .milliseconds(100))
		}
		return ThingsDiaryChangesPage(changes: [], nextPageToken: nil)
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

private actor DelayedEntryPullRemote: DiaryStoreRemote {
	let change: ThingsDiaryChange
	let serverEntry: ThingsDiaryEntry
	private(set) var getEntryStarted = false
	private(set) var receivedUpdateContents: [String] = []

	init(change: ThingsDiaryChange, serverEntry: ThingsDiaryEntry) {
		self.change = change
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
		receivedUpdateContents.append(params.content)
		return entry
	}

	func getDiaryChanges(
		diaryID: String,
		since: Date?,
		limit: Int?,
		nextPageToken: String?
	) async throws -> ThingsDiaryChangesPage {
		ThingsDiaryChangesPage(changes: [change], nextPageToken: nil)
	}

	func getEntry(
		diaryID: String,
		entryID: String
	) async throws -> ThingsDiaryEntry {
		getEntryStarted = true
		try await Task.sleep(for: .milliseconds(100))
		return serverEntry
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

private actor EntityChangesRemote: DiaryStoreRemote {
	let page: ThingsDiaryChangesPage
	let topic: ThingsDiaryTopic
	let template: ThingsDiaryTemplate
	private(set) var topicRequests: [String] = []
	private(set) var templateRequests: [String] = []

	init(
		page: ThingsDiaryChangesPage,
		topic: ThingsDiaryTopic,
		template: ThingsDiaryTemplate
	) {
		self.page = page
		self.topic = topic
		self.template = template
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
		page
	}

	func getTopic(diaryID: String, topicID: String) async throws -> ThingsDiaryTopic {
		topicRequests.append(topicID)
		return topic
	}

	func getTemplate(
		diaryID: String,
		templateID: String
	) async throws -> ThingsDiaryTemplate {
		templateRequests.append(templateID)
		return template
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
