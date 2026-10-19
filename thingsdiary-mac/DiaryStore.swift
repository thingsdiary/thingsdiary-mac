import Foundation
import ThingsDiaryClient

nonisolated enum PendingEntryOperation: String, Codable, Sendable, Equatable {
	case create
	case update
	case delete
	case restore
	case remove
}

nonisolated struct PendingEntryWrite: Sendable, Equatable, Identifiable {
	let operation: PendingEntryOperation
	let entry: ThingsDiaryEntry

	var id: String { entry.id }

	init(operation: PendingEntryOperation, entry: ThingsDiaryEntry) {
		self.operation = operation
		self.entry = entry
	}
}

nonisolated struct DiaryEntryConflict: Sendable, Equatable, Identifiable {
	let local: ThingsDiaryEntry
	let server: ThingsDiaryEntry

	var id: String { local.id }

	init(local: ThingsDiaryEntry, server: ThingsDiaryEntry) {
		self.local = local
		self.server = server
	}
}

nonisolated protocol DiaryStoreRemote: Sendable {
	func createEntry(
		diaryID: String,
		entryID: String,
		params: ThingsDiaryEntryParams
	) async throws -> ThingsDiaryEntry
	func updateEntry(
		_ entry: ThingsDiaryEntry,
		params: ThingsDiaryEntryParams
	) async throws -> ThingsDiaryEntry
	func getDiaryChanges(
		diaryID: String,
		since: Date?,
		limit: Int?,
		nextPageToken: String?
	) async throws -> ThingsDiaryChangesPage
	func getEntry(
		diaryID: String,
		entryID: String
	) async throws -> ThingsDiaryEntry
	func deleteEntry(
		diaryID: String,
		entryID: String,
		soft: Bool?
	) async throws
	func restoreEntry(
		diaryID: String,
		entryID: String
	) async throws -> ThingsDiaryEntry
	func getTopic(diaryID: String, topicID: String) async throws -> ThingsDiaryTopic
	func getTemplate(diaryID: String, templateID: String) async throws -> ThingsDiaryTemplate
}

extension DiaryStoreRemote {
	func getDiaryChanges(
		diaryID: String,
		since: Date?,
		limit: Int?,
		nextPageToken: String?
	) async throws -> ThingsDiaryChangesPage {
		ThingsDiaryChangesPage(changes: [], nextPageToken: nil)
	}

	func getEntry(
		diaryID: String,
		entryID: String
	) async throws -> ThingsDiaryEntry {
		throw DiaryStoreError.unsupportedRemoteEntry
	}

	func deleteEntry(
		diaryID: String,
		entryID: String,
		soft: Bool?
	) async throws {
		throw DiaryStoreError.unsupportedRemoteEntry
	}

	func restoreEntry(
		diaryID: String,
		entryID: String
	) async throws -> ThingsDiaryEntry {
		throw DiaryStoreError.unsupportedRemoteEntry
	}

	func getTopic(diaryID: String, topicID: String) async throws -> ThingsDiaryTopic {
		throw DiaryStoreError.unsupportedRemoteEntry
	}

	func getTemplate(diaryID: String, templateID: String) async throws -> ThingsDiaryTemplate {
		throw DiaryStoreError.unsupportedRemoteEntry
	}
}

nonisolated enum DiaryStoreError: Error {
	case unsupportedRemoteEntry
}

extension ThingsDiaryClient: DiaryStoreRemote {}

actor DiaryStore {
	private struct ActiveSynchronization {
		let id: UUID
		let task: Task<Void, Error>
	}

	private let fileURL: URL
	private var state: StoredState
	private var activeSynchronization: ActiveSynchronization?

	init(fileURL: URL) throws {
		self.fileURL = fileURL
		try FileManager.default.createDirectory(
			at: fileURL.deletingLastPathComponent(),
			withIntermediateDirectories: true
		)
		if FileManager.default.fileExists(atPath: fileURL.path) {
			state = try Self.decoder.decode(
				StoredState.self,
				from: Data(contentsOf: fileURL)
			)
		} else {
			state = StoredState()
		}
	}

	func replaceSelectedDiary(
		_ diary: ThingsDiaryDiary,
		entries: [ThingsDiaryEntry],
		topics: [ThingsDiaryTopic] = [],
		templates: [ThingsDiaryTemplate] = []
	) throws {
		var entriesByID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
		for pendingWrite in state.pendingEntryWrites where pendingWrite.entry.diaryID == diary.id {
			entriesByID[pendingWrite.entry.id] = pendingWrite.entry.value
		}
		let nextState = StoredState(
			selectedDiary: StoredDiary(diary),
			entries: entriesByID.values.map(StoredEntry.init),
			topics: topics.map(StoredTopic.init),
			templates: templates.map(StoredTemplate.init),
			pendingEntryWrites: state.pendingEntryWrites,
			checkpoints: state.checkpoints,
			entryConflicts: state.entryConflicts
		)
		try persist(nextState)
		state = nextState
	}

	func selectedDiary() -> ThingsDiaryDiary? {
		state.selectedDiary?.value
	}

	func entries(diaryID: String) -> [ThingsDiaryEntry] {
		state.entries
			.filter { $0.diaryID == diaryID }
			.map(\.value)
	}

	func topics(diaryID: String) -> [ThingsDiaryTopic] {
		state.topics.filter { $0.diaryID == diaryID }.map(\.value)
	}

	func templates(diaryID: String) -> [ThingsDiaryTemplate] {
		state.templates.filter { $0.diaryID == diaryID }.map(\.value)
	}

	func upsertTopic(_ topic: ThingsDiaryTopic) throws {
		var nextState = state
		nextState.topics.removeAll { $0.id == topic.id }
		nextState.topics.append(StoredTopic(topic))
		try persist(nextState)
		state = nextState
	}

	func removeTopic(
		diaryID: String,
		topicID: String,
		entries: [ThingsDiaryEntry]
	) throws {
		var nextState = state
		nextState.topics.removeAll { $0.diaryID == diaryID && $0.id == topicID }
		nextState.entries.removeAll { $0.diaryID == diaryID }
		nextState.entries.append(contentsOf: entries.map(StoredEntry.init))

		let entriesByID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
		nextState.pendingEntryWrites = nextState.pendingEntryWrites.map { storedWrite in
			guard let entry = entriesByID[storedWrite.entry.id] else { return storedWrite }
			return StoredPendingEntryWrite(
				PendingEntryWrite(operation: storedWrite.operation, entry: entry)
			)
		}

		try persist(nextState)
		state = nextState
	}

	func upsertTemplate(_ template: ThingsDiaryTemplate) throws {
		var nextState = state
		nextState.templates.removeAll { $0.id == template.id }
		nextState.templates.append(StoredTemplate(template))
		try persist(nextState)
		state = nextState
	}

	func removeTemplate(diaryID: String, templateID: String) throws {
		var nextState = state
		nextState.templates.removeAll { $0.diaryID == diaryID && $0.id == templateID }
		try persist(nextState)
		state = nextState
	}

	func savePendingEntry(_ write: PendingEntryWrite) throws {
		var nextState = state
		nextState.entries.removeAll { $0.id == write.entry.id }
		if write.operation != .remove {
			nextState.entries.append(StoredEntry(write.entry))
		}
		nextState.pendingEntryWrites.removeAll { $0.entry.id == write.entry.id }
		nextState.pendingEntryWrites.append(StoredPendingEntryWrite(write))
		try persist(nextState)
		state = nextState
	}

	func pendingEntryWrites() -> [PendingEntryWrite] {
		state.pendingEntryWrites.map(\.value)
	}

	func entryConflicts() -> [DiaryEntryConflict] {
		state.entryConflicts.map(\.value)
	}

	func synchronize(with remote: any DiaryStoreRemote) async throws {
		while true {
			let synchronization: ActiveSynchronization
			if let activeSynchronization {
				synchronization = activeSynchronization
			} else {
				let nextSynchronization = ActiveSynchronization(
					id: UUID(),
					task: Task { try await performSynchronization(with: remote) }
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
			if state.pendingEntryWrites.isEmpty {
				return
			}
		}
	}

	private func performSynchronization(with remote: any DiaryStoreRemote) async throws {
		while let storedWrite = state.pendingEntryWrites.first {
			let write = storedWrite.value
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
					try completeRemoval(write: write)
					continue
				}
			} catch ThingsDiaryClientError.httpStatus(409, _) {
				let currentServerEntry = try await remote.getEntry(
					diaryID: write.entry.diaryID,
					entryID: write.entry.id
				)
				try recordConflict(write: write, server: currentServerEntry)
				continue
			}
			try complete(write: write, serverEntry: serverEntry)
		}

		guard let diaryID = state.selectedDiary?.id else {
			return
		}
		try await pullChanges(diaryID: diaryID, remote: remote)
	}

	private func pullChanges(
		diaryID: String,
		remote: any DiaryStoreRemote
	) async throws {
		var nextPageToken: String?
		repeat {
			let checkpoint = state.checkpoints[diaryID] ?? StoredCheckpoint()
			let page = try await remote.getDiaryChanges(
				diaryID: diaryID,
				since: checkpoint.lastChangeAt,
				limit: nil,
				nextPageToken: nextPageToken
			)
			for change in page.changes {
				let currentCheckpoint = state.checkpoints[diaryID] ?? StoredCheckpoint()
				guard !currentCheckpoint.contains(change) else { continue }
				switch change.entityType {
				case .entry:
					if state.pendingEntryWrites.contains(where: {
						$0.entry.id == change.entityID
					}) {
						try apply(change, diaryID: diaryID) { _ in }
						continue
					}
					switch change.operation {
					case .created, .updated, .softDeleted:
						let serverEntry = try await remote.getEntry(
							diaryID: diaryID,
							entryID: change.entityID
						)
						try apply(change, diaryID: diaryID) { nextState in
							guard
								!nextState.pendingEntryWrites.contains(where: {
									$0.entry.id == change.entityID
								})
							else { return }
							nextState.entries.removeAll { $0.id == serverEntry.id }
							nextState.entries.append(StoredEntry(serverEntry))
						}
					case .removed:
						try apply(change, diaryID: diaryID) { nextState in
							guard
								!nextState.pendingEntryWrites.contains(where: {
									$0.entry.id == change.entityID
								})
							else { return }
							nextState.entries.removeAll { $0.id == change.entityID }
						}
					}
				case .topic:
					switch change.operation {
					case .created, .updated, .softDeleted:
						let topic = try await remote.getTopic(
							diaryID: diaryID,
							topicID: change.entityID
						)
						try apply(change, diaryID: diaryID) { nextState in
							nextState.topics.removeAll { $0.id == topic.id }
							nextState.topics.append(StoredTopic(topic))
						}
					case .removed:
						try apply(change, diaryID: diaryID) { nextState in
							nextState.topics.removeAll { $0.id == change.entityID }
						}
					}
				case .template:
					switch change.operation {
					case .created, .updated, .softDeleted:
						let template = try await remote.getTemplate(
							diaryID: diaryID,
							templateID: change.entityID
						)
						try apply(change, diaryID: diaryID) { nextState in
							nextState.templates.removeAll { $0.id == template.id }
							nextState.templates.append(StoredTemplate(template))
						}
					case .removed:
						try apply(change, diaryID: diaryID) { nextState in
							nextState.templates.removeAll { $0.id == change.entityID }
						}
					}
				case .diary:
					try apply(change, diaryID: diaryID) { _ in }
				}
			}
			nextPageToken = page.nextPageToken
		} while nextPageToken != nil
	}

	private func apply(
		_ change: ThingsDiaryChange,
		diaryID: String,
		mutation: (inout StoredState) -> Void
	) throws {
		var nextState = state
		var checkpoint = nextState.checkpoints[diaryID] ?? StoredCheckpoint()
		guard !checkpoint.contains(change) else { return }
		mutation(&nextState)
		checkpoint.record(change)
		nextState.checkpoints[diaryID] = checkpoint
		try persist(nextState)
		state = nextState
	}

	private func complete(write: PendingEntryWrite, serverEntry: ThingsDiaryEntry) throws {
		var nextState = state
		guard
			let currentWrite = nextState.pendingEntryWrites.first(where: {
				$0.entry.id == write.id
			})?.value
		else { return }
		guard currentWrite == write else {
			if write.operation == .create, currentWrite.operation == .create {
				nextState.pendingEntryWrites.removeAll { $0.entry.id == write.id }
				nextState.pendingEntryWrites.append(
					StoredPendingEntryWrite(
						PendingEntryWrite(operation: .update, entry: currentWrite.entry)
					)
				)
				try persist(nextState)
				state = nextState
			}
			return
		}
		nextState.entries.removeAll { $0.id == serverEntry.id }
		nextState.entries.append(StoredEntry(serverEntry))
		nextState.pendingEntryWrites.removeAll { $0.entry.id == write.id }
		try persist(nextState)
		state = nextState
	}

	private func completeRemoval(write: PendingEntryWrite) throws {
		var nextState = state
		guard nextState.pendingEntryWrites.contains(where: { $0.value == write }) else {
			return
		}
		nextState.entries.removeAll { $0.id == write.id }
		nextState.pendingEntryWrites.removeAll { $0.entry.id == write.id }
		try persist(nextState)
		state = nextState
	}

	private func recordConflict(write: PendingEntryWrite, server: ThingsDiaryEntry) throws {
		var nextState = state
		guard
			let currentWrite = nextState.pendingEntryWrites.first(where: {
				$0.entry.id == write.id
			})?.value
		else { return }
		guard currentWrite == write else {
			if write.operation == .create, currentWrite.operation == .create {
				nextState.pendingEntryWrites.removeAll { $0.entry.id == write.id }
				nextState.pendingEntryWrites.append(
					StoredPendingEntryWrite(
						PendingEntryWrite(operation: .update, entry: currentWrite.entry)
					)
				)
				try persist(nextState)
				state = nextState
			}
			return
		}
		nextState.entries.removeAll { $0.id == server.id }
		nextState.entries.append(StoredEntry(server))
		nextState.pendingEntryWrites.removeAll { $0.entry.id == write.id }
		nextState.entryConflicts.removeAll { $0.local.id == write.id }
		nextState.entryConflicts.append(
			StoredEntryConflict(
				DiaryEntryConflict(local: write.entry, server: server)
			))
		try persist(nextState)
		state = nextState
	}

	private func persist(_ state: StoredState) throws {
		try Self.encoder.encode(state).write(to: fileURL, options: .atomic)
	}

	private static let encoder: JSONEncoder = {
		let encoder = JSONEncoder()
		encoder.dateEncodingStrategy = .millisecondsSince1970
		encoder.outputFormatting = [.sortedKeys]
		return encoder
	}()

	private static let decoder: JSONDecoder = {
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .millisecondsSince1970
		return decoder
	}()
}

private nonisolated struct StoredState: Codable {
	var selectedDiary: StoredDiary?
	var entries: [StoredEntry]
	var topics: [StoredTopic]
	var templates: [StoredTemplate]
	var pendingEntryWrites: [StoredPendingEntryWrite]
	var checkpoints: [String: StoredCheckpoint]
	var entryConflicts: [StoredEntryConflict]

	init(
		selectedDiary: StoredDiary? = nil,
		entries: [StoredEntry] = [],
		topics: [StoredTopic] = [],
		templates: [StoredTemplate] = [],
		pendingEntryWrites: [StoredPendingEntryWrite] = [],
		checkpoints: [String: StoredCheckpoint] = [:],
		entryConflicts: [StoredEntryConflict] = []
	) {
		self.selectedDiary = selectedDiary
		self.entries = entries
		self.topics = topics
		self.templates = templates
		self.pendingEntryWrites = pendingEntryWrites
		self.checkpoints = checkpoints
		self.entryConflicts = entryConflicts
	}

	private enum CodingKeys: String, CodingKey {
		case selectedDiary, entries, topics, templates
		case pendingEntryWrites, checkpoints, entryConflicts
	}

	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		selectedDiary = try container.decodeIfPresent(StoredDiary.self, forKey: .selectedDiary)
		entries = try container.decodeIfPresent([StoredEntry].self, forKey: .entries) ?? []
		topics = try container.decodeIfPresent([StoredTopic].self, forKey: .topics) ?? []
		templates = try container.decodeIfPresent([StoredTemplate].self, forKey: .templates) ?? []
		pendingEntryWrites =
			try container.decodeIfPresent(
				[StoredPendingEntryWrite].self,
				forKey: .pendingEntryWrites
			) ?? []
		checkpoints =
			try container.decodeIfPresent(
				[String: StoredCheckpoint].self,
				forKey: .checkpoints
			) ?? [:]
		entryConflicts =
			try container.decodeIfPresent(
				[StoredEntryConflict].self,
				forKey: .entryConflicts
			) ?? []
	}
}

private nonisolated struct StoredCheckpoint: Codable {
	var lastChangeAt: Date?
	var changeIDsAtLastDate: [String]

	init(lastChangeAt: Date? = nil, changeIDsAtLastDate: [String] = []) {
		self.lastChangeAt = lastChangeAt
		self.changeIDsAtLastDate = changeIDsAtLastDate
	}

	func contains(_ change: ThingsDiaryChange) -> Bool {
		guard let lastChangeAt else {
			return false
		}
		if change.createdAt < lastChangeAt {
			return true
		}
		return change.createdAt == lastChangeAt
			&& changeIDsAtLastDate.contains(change.id)
	}

	mutating func record(_ change: ThingsDiaryChange) {
		guard let lastChangeAt else {
			self.lastChangeAt = change.createdAt
			changeIDsAtLastDate = [change.id]
			return
		}
		if change.createdAt > lastChangeAt {
			self.lastChangeAt = change.createdAt
			changeIDsAtLastDate = [change.id]
		} else if change.createdAt == lastChangeAt,
			!changeIDsAtLastDate.contains(change.id)
		{
			changeIDsAtLastDate.append(change.id)
		}
	}
}

private nonisolated struct StoredDiary: Codable {
	let id: String
	let title: String
	let description: String
	let createdAt: Date
	let updatedAt: Date
	let version: UInt64

	init(_ diary: ThingsDiaryDiary) {
		id = diary.id
		title = diary.title
		description = diary.description
		createdAt = diary.createdAt
		updatedAt = diary.updatedAt
		version = diary.version
	}

	var value: ThingsDiaryDiary {
		ThingsDiaryDiary(
			id: id,
			title: title,
			description: description,
			createdAt: createdAt,
			updatedAt: updatedAt,
			version: version
		)
	}
}

private nonisolated struct StoredEntry: Codable {
	let id: String
	let diaryID: String
	let content: String
	let topicID: String?
	let archived: Bool
	let bookmarked: Bool
	let previewHidden: Bool
	let createdAt: Date
	let updatedAt: Date
	let deletedAt: Date?
	let version: UInt64

	init(_ entry: ThingsDiaryEntry) {
		id = entry.id
		diaryID = entry.diaryID
		content = entry.content
		topicID = entry.topicID
		archived = entry.archived
		bookmarked = entry.bookmarked
		previewHidden = entry.previewHidden
		createdAt = entry.createdAt
		updatedAt = entry.updatedAt
		deletedAt = entry.deletedAt
		version = entry.version
	}

	var value: ThingsDiaryEntry {
		ThingsDiaryEntry(
			id: id,
			diaryID: diaryID,
			content: content,
			topicID: topicID,
			archived: archived,
			bookmarked: bookmarked,
			previewHidden: previewHidden,
			createdAt: createdAt,
			updatedAt: updatedAt,
			deletedAt: deletedAt,
			version: version
		)
	}
}

private nonisolated struct StoredTopic: Codable {
	let id: String
	let diaryID: String
	let title: String
	let description: String
	let color: String
	let entryPreviewable: Bool?
	let defaultTemplateID: String?
	let createdAt: Date
	let updatedAt: Date
	let deletedAt: Date?
	let version: UInt64

	init(_ topic: ThingsDiaryTopic) {
		id = topic.id
		diaryID = topic.diaryID
		title = topic.title
		description = topic.description
		color = topic.color
		entryPreviewable = topic.entryPreviewable
		defaultTemplateID = topic.defaultTemplateID
		createdAt = topic.createdAt
		updatedAt = topic.updatedAt
		deletedAt = topic.deletedAt
		version = topic.version
	}

	var value: ThingsDiaryTopic {
		ThingsDiaryTopic(
			id: id,
			diaryID: diaryID,
			title: title,
			description: description,
			color: color,
			entryPreviewable: entryPreviewable ?? true,
			defaultTemplateID: defaultTemplateID,
			createdAt: createdAt,
			updatedAt: updatedAt,
			deletedAt: deletedAt,
			version: version
		)
	}
}

private nonisolated struct StoredTemplate: Codable {
	let id: String
	let diaryID: String
	let content: String
	let createdAt: Date
	let updatedAt: Date
	let deletedAt: Date?
	let version: UInt64

	init(_ template: ThingsDiaryTemplate) {
		id = template.id
		diaryID = template.diaryID
		content = template.content
		createdAt = template.createdAt
		updatedAt = template.updatedAt
		deletedAt = template.deletedAt
		version = template.version
	}

	var value: ThingsDiaryTemplate {
		ThingsDiaryTemplate(
			id: id,
			diaryID: diaryID,
			content: content,
			createdAt: createdAt,
			updatedAt: updatedAt,
			deletedAt: deletedAt,
			version: version
		)
	}
}

private nonisolated struct StoredPendingEntryWrite: Codable {
	let operation: PendingEntryOperation
	let entry: StoredEntry

	init(_ write: PendingEntryWrite) {
		operation = write.operation
		entry = StoredEntry(write.entry)
	}

	var value: PendingEntryWrite {
		PendingEntryWrite(operation: operation, entry: entry.value)
	}
}

private nonisolated struct StoredEntryConflict: Codable {
	let local: StoredEntry
	let server: StoredEntry

	init(_ conflict: DiaryEntryConflict) {
		local = StoredEntry(conflict.local)
		server = StoredEntry(conflict.server)
	}

	var value: DiaryEntryConflict {
		DiaryEntryConflict(local: local.value, server: server.value)
	}
}
