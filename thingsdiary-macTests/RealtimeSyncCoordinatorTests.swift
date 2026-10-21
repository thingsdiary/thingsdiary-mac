import Foundation
import Testing
import ThingsDiaryClient

@testable import thingsdiary

@Test("A realtime event arriving after the initial pull triggers another synchronization")
func delayedRealtimeEventTriggersSynchronization() async throws {
	let fixture = try await RealtimeCoordinatorFixture()
	defer { try? FileManager.default.removeItem(at: fixture.fileURL) }
	let coordinator = RealtimeSyncCoordinator(
		client: fixture.client,
		store: fixture.store,
		onSnapshot: { _ in }
	)

	try await coordinator.start()
	await fixture.client.waitForPullCount(1)
	#expect(await fixture.client.sendEvent())
	await fixture.client.waitForPullCount(2)

	await coordinator.stop()
}

@Test("Events received during a pull are coalesced into one follow-up synchronization")
func realtimeEventBurstIsCoalesced() async throws {
	let fixture = try await RealtimeCoordinatorFixture(delayFirstPull: true)
	defer { try? FileManager.default.removeItem(at: fixture.fileURL) }
	let coordinator = RealtimeSyncCoordinator(
		client: fixture.client,
		store: fixture.store,
		onSnapshot: { _ in }
	)

	try await coordinator.start()
	await fixture.client.waitForPullCount(1)
	#expect(await fixture.client.sendEvent())
	#expect(await fixture.client.sendEvent())
	#expect(await fixture.client.sendEvent())
	try await Task.sleep(for: .milliseconds(10))
	await fixture.client.releaseFirstPull()
	await fixture.client.waitForPullCount(2)
	await Task.yield()

	#expect(await fixture.client.pullCount == 2)
	await coordinator.stop()
}

@Test("Stopping realtime cancels its event subscription")
func stoppingRealtimeCancelsEventSubscription() async throws {
	let fixture = try await RealtimeCoordinatorFixture()
	defer { try? FileManager.default.removeItem(at: fixture.fileURL) }
	let coordinator = RealtimeSyncCoordinator(
		client: fixture.client,
		store: fixture.store,
		onSnapshot: { _ in }
	)

	try await coordinator.start()
	await fixture.client.waitForPullCount(1)
	await coordinator.stop()

	#expect(await fixture.client.sendEvent() == false)
	#expect(await fixture.client.pullCount == 1)
}

private struct RealtimeCoordinatorFixture {
	let fileURL: URL
	let store: DiaryStore
	let client: RealtimeTestClient

	init(delayFirstPull: Bool = false) async throws {
		fileURL = FileManager.default.temporaryDirectory
			.appending(path: "thingsdiary-realtime-\(UUID().uuidString).json")
		store = try DiaryStore(fileURL: fileURL)
		client = RealtimeTestClient(delayFirstPull: delayFirstPull)
		try await store.replaceSelectedDiary(
			ThingsDiaryDiary(
				id: "diary-1",
				title: "Personal",
				description: "",
				createdAt: Date(timeIntervalSince1970: 1),
				updatedAt: Date(timeIntervalSince1970: 2),
				version: 3
			),
			entries: []
		)
	}
}

private actor RealtimeTestClient: ThingsDiaryAppClient {
	private let eventStream: AsyncThrowingStream<Io_Thingsdiary_V1_Event, Error>
	private let eventContinuation: AsyncThrowingStream<Io_Thingsdiary_V1_Event, Error>.Continuation
	private let delayFirstPull: Bool
	private var firstPullContinuation: CheckedContinuation<Void, Never>?
	private var pullWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
	private var isConnected = false
	private(set) var pullCount = 0

	init(delayFirstPull: Bool) {
		let pair = AsyncThrowingStream<Io_Thingsdiary_V1_Event, Error>.makeStream()
		eventStream = pair.stream
		eventContinuation = pair.continuation
		self.delayFirstPull = delayFirstPull
	}

	func connect() async throws {
		isConnected = true
	}

	func disconnect() async {
		guard isConnected else { return }
		isConnected = false
		eventContinuation.finish()
	}

	func events() async -> AsyncThrowingStream<Io_Thingsdiary_V1_Event, Error> {
		eventStream
	}

	func sendEvent() -> Bool {
		switch eventContinuation.yield(Io_Thingsdiary_V1_Event()) {
		case .enqueued, .dropped:
			return true
		case .terminated:
			return false
		@unknown default:
			return false
		}
	}

	func waitForPullCount(_ expectedCount: Int) async {
		guard pullCount < expectedCount else { return }
		await withCheckedContinuation { continuation in
			pullWaiters.append((expectedCount, continuation))
		}
	}

	func releaseFirstPull() {
		firstPullContinuation?.resume()
		firstPullContinuation = nil
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

	func getDiaryChanges(
		diaryID: String,
		since: Date?,
		limit: Int?,
		nextPageToken: String?
	) async throws -> ThingsDiaryChangesPage {
		pullCount += 1
		let readyWaiters = pullWaiters.filter { $0.count <= pullCount }
		pullWaiters.removeAll { $0.count <= pullCount }
		readyWaiters.forEach { $0.continuation.resume() }
		if delayFirstPull, pullCount == 1 {
			await withCheckedContinuation { continuation in
				firstPullContinuation = continuation
			}
		}
		return ThingsDiaryChangesPage(changes: [], nextPageToken: nil)
	}
}

private enum RealtimeTestFailure: Error {
	case unexpectedCall
}
