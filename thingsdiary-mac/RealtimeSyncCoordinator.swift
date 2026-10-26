import Foundation
import ThingsDiaryClient

nonisolated enum ThingsDiaryRealtimeUpdate: Sendable, Equatable {
	case upsertDiary(ThingsDiaryDiary)
	case removeDiary(id: String, version: UInt64)
	case upsertEntry(ThingsDiaryEntry)
	case removeEntry(diaryID: String, id: String, version: UInt64)
	case upsertTopic(ThingsDiaryTopic)
	case removeTopic(diaryID: String, id: String, version: UInt64)
	case upsertTemplate(ThingsDiaryTemplate)
	case removeTemplate(diaryID: String, id: String, version: UInt64)

	var diaryID: String {
		switch self {
		case .upsertDiary(let diary): diary.id
		case .removeDiary(let id, _): id
		case .upsertEntry(let entry): entry.diaryID
		case .removeEntry(let diaryID, _, _): diaryID
		case .upsertTopic(let topic): topic.diaryID
		case .removeTopic(let diaryID, _, _): diaryID
		case .upsertTemplate(let template): template.diaryID
		case .removeTemplate(let diaryID, _, _): diaryID
		}
	}
}

nonisolated struct ThingsDiaryRealtimeEvent: Sendable, Equatable {
	let eventID: String
	let operationID: String
	let update: ThingsDiaryRealtimeUpdate
}

actor RealtimeSyncCoordinator {
	typealias SnapshotHandler =
		@MainActor @Sendable (
			ThingsDiaryRealtimeEvent,
			DiaryStoreSnapshot?
		) -> Void

	private let client: any ThingsDiaryAppClient
	private let store: DiaryStore?
	private let onSnapshot: SnapshotHandler

	private var generation = UUID()
	private var eventTask: Task<Void, Never>?
	private var isConnected = false

	init(
		client: any ThingsDiaryAppClient,
		store: DiaryStore?,
		onSnapshot: @escaping SnapshotHandler
	) {
		self.client = client
		self.store = store
		self.onSnapshot = onSnapshot
	}

	func start() async throws {
		if isConnected {
			await stop()
		} else {
			cancelCurrentGeneration()
		}

		let sessionGeneration = UUID()
		generation = sessionGeneration
		try await client.connect()
		isConnected = true

		let eventStream = await client.events()
		eventTask = Task { [weak self] in
			do {
				for try await event in eventStream {
					guard !Task.isCancelled else { return }
					await self?.apply(event, for: sessionGeneration)
				}
			} catch is CancellationError {
				return
			} catch {
				// A later start establishes a fresh session. Keep the last local snapshot
				// intact when this session's stream terminates with an error.
				return
			}
		}
	}

	func stop() async {
		cancelCurrentGeneration()
		guard isConnected else { return }
		isConnected = false
		await client.disconnect()
	}

	private func cancelCurrentGeneration() {
		generation = UUID()
		eventTask?.cancel()
		eventTask = nil
	}

	private func apply(
		_ event: ThingsDiaryRealtimeEvent,
		for sessionGeneration: UUID
	) async {
		guard sessionGeneration == generation, !Task.isCancelled else { return }
		let snapshot: DiaryStoreSnapshot?
		if let store {
			snapshot = try? await store.applyRealtimeEvent(event)
		} else {
			snapshot = nil
		}
		guard sessionGeneration == generation, !Task.isCancelled else { return }
		await onSnapshot(event, snapshot)
	}
}
