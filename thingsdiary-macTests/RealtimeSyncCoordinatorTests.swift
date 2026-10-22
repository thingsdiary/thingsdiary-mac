import Foundation
import Testing
import ThingsDiaryClient

@testable import thingsdiary

@Test("A realtime event updates the store without pulling changes")
func realtimeEventUpdatesStoreWithoutChanges() async throws {
	let fixture = try await RealtimeCoordinatorFixture()
	defer { try? FileManager.default.removeItem(at: fixture.fileURL) }
	let coordinator = RealtimeSyncCoordinator(
		client: fixture.client,
		store: fixture.store,
		onSnapshot: { _, _ in }
	)

	try await coordinator.start()
	#expect(await fixture.client.sendEvent(fixture.updatedEvent))
	for _ in 0..<100 {
		if await fixture.store.entries(diaryID: fixture.diary.id) == [fixture.updatedEntry] {
			break
		}
		await Task.yield()
	}

	#expect(await fixture.store.entries(diaryID: fixture.diary.id) == [fixture.updatedEntry])
	await coordinator.stop()
}

@Test("An older realtime event does not overwrite a newer entity")
func olderRealtimeEventIsIgnored() async throws {
	let fixture = try await RealtimeCoordinatorFixture()
	defer { try? FileManager.default.removeItem(at: fixture.fileURL) }

	_ = try await fixture.store.applyRealtimeEvent(fixture.updatedEvent)
	_ = try await fixture.store.applyRealtimeEvent(
		ThingsDiaryRealtimeEvent(
			eventID: "older-event",
			operationID: "older-operation",
			update: .upsertEntry(fixture.originalEntry)
		)
	)

	#expect(await fixture.store.entries(diaryID: fixture.diary.id) == [fixture.updatedEntry])
}

@Test("An event received during initial loading is applied after diary selection")
func realtimeEventWaitsForInitialDiaryLoad() async throws {
	let fixture = try await RealtimeCoordinatorFixture()
	defer { try? FileManager.default.removeItem(at: fixture.fileURL) }
	let unloadedStoreURL = fixture.fileURL.deletingLastPathComponent()
		.appending(path: "thingsdiary-realtime-unloaded-\(UUID().uuidString).json")
	defer { try? FileManager.default.removeItem(at: unloadedStoreURL) }
	let unloadedStore = try DiaryStore(fileURL: unloadedStoreURL)

	_ = try await unloadedStore.applyRealtimeEvent(fixture.updatedEvent)
	try await unloadedStore.replaceSelectedDiary(
		fixture.diary,
		entries: [fixture.originalEntry]
	)

	#expect(await unloadedStore.entries(diaryID: fixture.diary.id) == [fixture.updatedEntry])
}

@Test("Stopping realtime cancels its event subscription")
func stoppingRealtimeCancelsEventSubscription() async throws {
	let fixture = try await RealtimeCoordinatorFixture()
	defer { try? FileManager.default.removeItem(at: fixture.fileURL) }
	let coordinator = RealtimeSyncCoordinator(
		client: fixture.client,
		store: fixture.store,
		onSnapshot: { _, _ in }
	)

	try await coordinator.start()
	await coordinator.stop()

	#expect(await fixture.client.sendEvent(fixture.updatedEvent) == false)
}

private struct RealtimeCoordinatorFixture {
	let fileURL: URL
	let store: DiaryStore
	let client: RealtimeTestClient
	let diary: ThingsDiaryDiary
	let originalEntry: ThingsDiaryEntry
	let updatedEntry: ThingsDiaryEntry
	let updatedEvent: ThingsDiaryRealtimeEvent

	init() async throws {
		fileURL = FileManager.default.temporaryDirectory
			.appending(path: "thingsdiary-realtime-\(UUID().uuidString).json")
		store = try DiaryStore(fileURL: fileURL)
		client = RealtimeTestClient()
		diary = ThingsDiaryDiary(
			id: "diary-1",
			title: "Personal",
			description: "",
			createdAt: Date(timeIntervalSince1970: 1),
			updatedAt: Date(timeIntervalSince1970: 2),
			version: 3
		)
		originalEntry = ThingsDiaryEntry(
			id: "entry-1",
			diaryID: diary.id,
			content: "Before",
			createdAt: Date(timeIntervalSince1970: 2),
			updatedAt: Date(timeIntervalSince1970: 3),
			version: 3
		)
		updatedEntry = ThingsDiaryEntry(
			id: originalEntry.id,
			diaryID: diary.id,
			content: "After",
			createdAt: originalEntry.createdAt,
			updatedAt: Date(timeIntervalSince1970: 4),
			version: 4
		)
		updatedEvent = ThingsDiaryRealtimeEvent(
			eventID: "event-1",
			operationID: "operation-1",
			update: .upsertEntry(updatedEntry)
		)
		try await store.replaceSelectedDiary(diary, entries: [originalEntry])
	}
}

private actor RealtimeTestClient: ThingsDiaryAppClient {
	private let eventStream: AsyncThrowingStream<ThingsDiaryRealtimeEvent, Error>
	private let eventContinuation: AsyncThrowingStream<ThingsDiaryRealtimeEvent, Error>.Continuation
	private var isConnected = false

	init() {
		let pair = AsyncThrowingStream<ThingsDiaryRealtimeEvent, Error>.makeStream()
		eventStream = pair.stream
		eventContinuation = pair.continuation
	}

	func connect() async throws {
		isConnected = true
	}

	func disconnect() async {
		guard isConnected else { return }
		isConnected = false
		eventContinuation.finish()
	}

	func events() async -> AsyncThrowingStream<ThingsDiaryRealtimeEvent, Error> {
		eventStream
	}

	func sendEvent(_ event: ThingsDiaryRealtimeEvent) -> Bool {
		switch eventContinuation.yield(event) {
		case .enqueued, .dropped:
			return true
		case .terminated:
			return false
		@unknown default:
			return false
		}
	}

	func register(
		login: String,
		password: String,
		secretKey: String,
		kdfSalt: String
	) async throws -> ThingsDiaryPublicKeys {
		throw RealtimeTestFailure.unexpectedCall
	}

	func login(login: String, password: String, secretKey: String) async throws {
		throw RealtimeTestFailure.unexpectedCall
	}

	func diaries() async throws -> [ThingsDiaryDiary] {
		throw RealtimeTestFailure.unexpectedCall
	}

	func entries(diaryID: String) async throws -> [ThingsDiaryEntry] {
		throw RealtimeTestFailure.unexpectedCall
	}

	func createEntry(
		diaryID: String,
		params: ThingsDiaryEntryParams
	) async throws -> ThingsDiaryEntry {
		throw RealtimeTestFailure.unexpectedCall
	}

	func createEntry(
		diaryID: String,
		entryID: String,
		params: ThingsDiaryEntryParams
	) async throws -> ThingsDiaryEntry {
		throw RealtimeTestFailure.unexpectedCall
	}

	func updateEntry(
		_ entry: ThingsDiaryEntry,
		params: ThingsDiaryEntryParams
	) async throws -> ThingsDiaryEntry {
		throw RealtimeTestFailure.unexpectedCall
	}

}

private enum RealtimeTestFailure: Error {
	case unexpectedCall
}
