import Foundation
import ThingsDiaryClient

actor DiarySynchronizer {
	private struct ActiveSynchronization {
		let id: UUID
		let task: Task<Void, Error>
	}

	private let store: DiaryStore
	private let remote: any DiaryStoreRemote
	private var activeSynchronization: ActiveSynchronization?

	init(store: DiaryStore, remote: any DiaryStoreRemote) {
		self.store = store
		self.remote = remote
	}

	func synchronize() async throws {
		while true {
			let synchronization: ActiveSynchronization
			if let activeSynchronization {
				synchronization = activeSynchronization
			} else {
				let nextSynchronization = ActiveSynchronization(
					id: UUID(),
					task: Task { try await self.performSynchronization() }
				)
				activeSynchronization = nextSynchronization
				synchronization = nextSynchronization
			}
			do {
				try await synchronization.task.value
			} catch {
				if activeSynchronization?.id == synchronization.id {
					activeSynchronization = nil
				}
				throw error
			}
			if activeSynchronization?.id == synchronization.id {
				activeSynchronization = nil
			}
			if await store.pendingEntryWrites().isEmpty {
				return
			}
		}
	}

	private func performSynchronization() async throws {
		while let write = await store.nextPendingEntryWrite() {
			let params = ThingsDiaryEntryParams(
				content: write.entry.content,
				topicID: write.entry.topicID,
				archived: write.entry.archived,
				bookmarked: write.entry.bookmarked,
				previewHidden: write.entry.previewHidden
			)
			let serverEntry: ThingsDiaryEntry
			do {
				switch write.operation {
				case .create:
					serverEntry = try await remote.createEntry(
						diaryID: write.entry.diaryID,
						entryID: write.entry.id,
						params: params
					)
				case .update:
					serverEntry = try await remote.updateEntry(write.entry, params: params)
				case .delete:
					try await remote.deleteEntry(
						diaryID: write.entry.diaryID,
						entryID: write.entry.id,
						soft: true
					)
					serverEntry = try await remote.getEntry(
						diaryID: write.entry.diaryID,
						entryID: write.entry.id
					)
				case .restore:
					serverEntry = try await remote.restoreEntry(
						diaryID: write.entry.diaryID,
						entryID: write.entry.id
					)
				case .remove:
					try await remote.deleteEntry(
						diaryID: write.entry.diaryID,
						entryID: write.entry.id,
						soft: false
					)
					try await store.completeRemoval(write: write)
					continue
				}
			} catch ThingsDiaryClientError.httpStatus(409, _) {
				let currentServerEntry = try await remote.getEntry(
					diaryID: write.entry.diaryID,
					entryID: write.entry.id
				)
				try await store.recordConflict(write: write, server: currentServerEntry)
				continue
			}
			try await store.complete(write: write, serverEntry: serverEntry)
		}

		guard let diaryID = await store.selectedDiaryID() else { return }
		try await pullChanges(diaryID: diaryID)
	}

	private func pullChanges(diaryID: String) async throws {
		var nextPageToken: String?
		repeat {
			let page = try await remote.getDiaryChanges(
				diaryID: diaryID,
				since: await store.lastChangeAt(diaryID: diaryID),
				limit: nil,
				nextPageToken: nextPageToken
			)
			for change in page.changes {
				guard !(await store.hasApplied(change, diaryID: diaryID)) else { continue }
				try await apply(change, diaryID: diaryID)
			}
			nextPageToken = page.nextPageToken
		} while nextPageToken != nil
	}

	private func apply(_ change: ThingsDiaryChange, diaryID: String) async throws {
		switch change.entityType {
		case .entry:
			if await store.hasPendingEntry(id: change.entityID) {
				try await store.record(change, diaryID: diaryID)
				return
			}
			switch change.operation {
			case .created, .updated, .softDeleted:
				let entry = try await remote.getEntry(
					diaryID: diaryID,
					entryID: change.entityID
				)
				try await store.applyRemoteEntry(entry, change: change, diaryID: diaryID)
			case .removed:
				try await store.removeRemoteEntry(change: change, diaryID: diaryID)
			}
		case .topic:
			switch change.operation {
			case .created, .updated, .softDeleted:
				let topic = try await remote.getTopic(
					diaryID: diaryID,
					topicID: change.entityID
				)
				try await store.applyRemoteTopic(topic, change: change, diaryID: diaryID)
			case .removed:
				try await store.removeRemoteTopic(change: change, diaryID: diaryID)
			}
		case .template:
			switch change.operation {
			case .created, .updated, .softDeleted:
				let template = try await remote.getTemplate(
					diaryID: diaryID,
					templateID: change.entityID
				)
				try await store.applyRemoteTemplate(template, change: change, diaryID: diaryID)
			case .removed:
				try await store.removeRemoteTemplate(change: change, diaryID: diaryID)
			}
		case .diary:
			try await store.record(change, diaryID: diaryID)
		}
	}
}
