import Foundation

actor RealtimeSyncCoordinator {
	typealias SnapshotHandler = @MainActor @Sendable (DiaryStoreSnapshot) -> Void

	private let client: any ThingsDiaryAppClient
	private let store: DiaryStore?
	private let onSnapshot: SnapshotHandler

	private var generation = UUID()
	private var eventTask: Task<Void, Never>?
	private var syncTask: Task<Void, Never>?
	private var syncRequested = false
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
				for try await _ in eventStream {
					guard !Task.isCancelled else { return }
					await self?.requestSynchronization(for: sessionGeneration)
				}
			} catch is CancellationError {
				return
			} catch {
				// A later start establishes a fresh session. Keep the last local snapshot
				// intact when this session's stream terminates with an error.
				return
			}
		}

		// Events can be missed between authentication and stream subscription.
		// Pulling once after the stream is installed closes that window.
		requestSynchronization(for: sessionGeneration)
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
		syncTask?.cancel()
		syncTask = nil
		syncRequested = false
	}

	private func requestSynchronization(for sessionGeneration: UUID) {
		guard sessionGeneration == generation, store != nil else { return }
		syncRequested = true
		guard syncTask == nil else { return }

		syncTask = Task { [weak self] in
			await self?.drainSynchronizationRequests(for: sessionGeneration)
		}
	}

	private func drainSynchronizationRequests(for sessionGeneration: UUID) async {
		defer { syncTask = nil }
		guard let store else { return }

		while syncRequested,
			sessionGeneration == generation,
			!Task.isCancelled
		{
			syncRequested = false
			do {
				try await store.synchronize(with: client)
				guard
					sessionGeneration == generation,
					!Task.isCancelled,
					let snapshot = await store.snapshot()
				else { return }
				await onSnapshot(snapshot)
			} catch is CancellationError {
				return
			} catch {
				// Synchronization is retried by the next event (or a new session's
				// mandatory catch-up pull) without terminating the event consumer.
			}
		}
	}
}
