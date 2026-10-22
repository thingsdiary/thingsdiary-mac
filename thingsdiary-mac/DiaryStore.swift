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

nonisolated struct DiaryStoreSnapshot: Sendable, Equatable {
	let diary: ThingsDiaryDiary
	let entries: [ThingsDiaryEntry]
	let topics: [ThingsDiaryTopic]
	let templates: [ThingsDiaryTemplate]
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
	private var realtimeEventIDs: Set<String> = []
	private var realtimeEventOrder: [String] = []
	private var realtimeRemovalVersions: [String: UInt64] = [:]
	private var deferredRealtimeEvents: [ThingsDiaryRealtimeEvent] = []

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
			entryConflicts: state.entryConflicts
		)
		try persist(nextState)
		state = nextState
		let deferredEvents = deferredRealtimeEvents.filter { $0.update.diaryID == diary.id }
		deferredRealtimeEvents.removeAll { $0.update.diaryID == diary.id }
		for event in deferredEvents {
			_ = try applyRealtimeEvent(event)
		}
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
		state.topics
			.filter { $0.diaryID == diaryID && $0.deletedAt == nil }
			.map(\.value)
	}

	func templates(diaryID: String) -> [ThingsDiaryTemplate] {
		state.templates.filter { $0.diaryID == diaryID }.map(\.value)
	}

	func snapshot() -> DiaryStoreSnapshot? {
		guard let diary = state.selectedDiary?.value else { return nil }
		return DiaryStoreSnapshot(
			diary: diary,
			entries: state.entries.filter { $0.diaryID == diary.id }.map(\.value),
			topics: state.topics
				.filter { $0.diaryID == diary.id && $0.deletedAt == nil }
				.map(\.value),
			templates: state.templates.filter { $0.diaryID == diary.id }.map(\.value)
		)
	}

	func clear() throws {
		activeSynchronization?.task.cancel()
		activeSynchronization = nil
		realtimeEventIDs.removeAll()
		realtimeEventOrder.removeAll()
		realtimeRemovalVersions.removeAll()
		deferredRealtimeEvents.removeAll()
		let emptyState = StoredState()
		try persist(emptyState)
		state = emptyState
	}

	func applyRealtimeEvent(
		_ event: ThingsDiaryRealtimeEvent
	) throws -> DiaryStoreSnapshot? {
		if !event.eventID.isEmpty, realtimeEventIDs.contains(event.eventID) {
			return snapshot()
		}

		var nextState = state
		switch event.update {
		case .upsertDiary(let diary):
			guard realtimeAccepts(
				key: realtimeKey("diary", diary.id),
				version: diary.version,
				currentVersion: nextState.selectedDiary?.id == diary.id
					? nextState.selectedDiary?.version : nil
			) else { return snapshot() }
			if nextState.selectedDiary?.id == diary.id {
				nextState.selectedDiary = StoredDiary(diary)
			}
		case .removeDiary(let id, let version):
			guard realtimeAccepts(
				key: realtimeKey("diary", id),
				version: version,
				currentVersion: nextState.selectedDiary?.id == id
					? nextState.selectedDiary?.version : nil
			) else { return snapshot() }
			realtimeRemovalVersions[realtimeKey("diary", id)] = version
			if nextState.selectedDiary?.id == id {
				nextState.selectedDiary = nil
				nextState.entries.removeAll { $0.diaryID == id }
				nextState.topics.removeAll { $0.diaryID == id }
				nextState.templates.removeAll { $0.diaryID == id }
				nextState.pendingEntryWrites.removeAll { $0.entry.diaryID == id }
			}
		case .upsertEntry(let entry):
			guard nextState.selectedDiary?.id == entry.diaryID else {
				deferRealtimeEvent(event)
				return snapshot()
			}
			guard !nextState.pendingEntryWrites.contains(where: { $0.entry.id == entry.id }) else {
				recordRealtimeEvent(event.eventID)
				return snapshot()
			}
			let currentVersion = nextState.entries.first { $0.id == entry.id }?.version
			guard realtimeAccepts(
				key: realtimeKey("entry", entry.id),
				version: entry.version,
				currentVersion: currentVersion
			) else { return snapshot() }
			nextState.entries.removeAll { $0.id == entry.id }
			nextState.entries.append(StoredEntry(entry))
		case .removeEntry(let diaryID, let id, let version):
			guard nextState.selectedDiary?.id == diaryID else {
				deferRealtimeEvent(event)
				return snapshot()
			}
			guard !nextState.pendingEntryWrites.contains(where: { $0.entry.id == id }) else {
				recordRealtimeEvent(event.eventID)
				return snapshot()
			}
			let key = realtimeKey("entry", id)
			guard realtimeAccepts(
				key: key,
				version: version,
				currentVersion: nextState.entries.first { $0.id == id }?.version
			) else { return snapshot() }
			realtimeRemovalVersions[key] = version
			nextState.entries.removeAll { $0.id == id }
		case .upsertTopic(let topic):
			guard nextState.selectedDiary?.id == topic.diaryID else {
				deferRealtimeEvent(event)
				return snapshot()
			}
			guard realtimeAccepts(
				key: realtimeKey("topic", topic.id),
				version: topic.version,
				currentVersion: nextState.topics.first { $0.id == topic.id }?.version
			) else { return snapshot() }
			nextState.topics.removeAll { $0.id == topic.id }
			nextState.topics.append(StoredTopic(topic))
		case .removeTopic(let diaryID, let id, let version):
			guard nextState.selectedDiary?.id == diaryID else {
				deferRealtimeEvent(event)
				return snapshot()
			}
			let key = realtimeKey("topic", id)
			guard realtimeAccepts(
				key: key,
				version: version,
				currentVersion: nextState.topics.first { $0.id == id }?.version
			) else { return snapshot() }
			realtimeRemovalVersions[key] = version
			nextState.topics.removeAll { $0.id == id }
		case .upsertTemplate(let template):
			guard nextState.selectedDiary?.id == template.diaryID else {
				deferRealtimeEvent(event)
				return snapshot()
			}
			guard realtimeAccepts(
				key: realtimeKey("template", template.id),
				version: template.version,
				currentVersion: nextState.templates.first { $0.id == template.id }?.version
			) else { return snapshot() }
			nextState.templates.removeAll { $0.id == template.id }
			nextState.templates.append(StoredTemplate(template))
		case .removeTemplate(let diaryID, let id, let version):
			guard nextState.selectedDiary?.id == diaryID else {
				deferRealtimeEvent(event)
				return snapshot()
			}
			let key = realtimeKey("template", id)
			guard realtimeAccepts(
				key: key,
				version: version,
				currentVersion: nextState.templates.first { $0.id == id }?.version
			) else { return snapshot() }
			realtimeRemovalVersions[key] = version
			nextState.templates.removeAll { $0.id == id }
		}

		try persist(nextState)
		state = nextState
		recordRealtimeEvent(event.eventID)
		return snapshot()
	}

	private func realtimeKey(_ entity: String, _ id: String) -> String {
		"\(entity):\(id)"
	}

	private func realtimeAccepts(
		key: String,
		version: UInt64,
		currentVersion: UInt64?
	) -> Bool {
		if let removalVersion = realtimeRemovalVersions[key], version <= removalVersion {
			return false
		}
		return currentVersion.map { version >= $0 } ?? true
	}

	private func recordRealtimeEvent(_ eventID: String) {
		guard !eventID.isEmpty, realtimeEventIDs.insert(eventID).inserted else { return }
		realtimeEventOrder.append(eventID)
		if realtimeEventOrder.count > 1_024 {
			let removed = realtimeEventOrder.removeFirst()
			realtimeEventIDs.remove(removed)
		}
	}

	private func deferRealtimeEvent(_ event: ThingsDiaryRealtimeEvent) {
		guard event.eventID.isEmpty
			|| !deferredRealtimeEvents.contains(where: { $0.eventID == event.eventID })
		else {
			return
		}
		deferredRealtimeEvents.append(event)
		if deferredRealtimeEvents.count > 256 {
			deferredRealtimeEvents.removeFirst()
		}
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
			} catch let error where Self.isConflict(error) {
				let currentServerEntry = try await remote.getEntry(
					diaryID: write.entry.diaryID,
					entryID: write.entry.id
				)
				try recordConflict(write: write, server: currentServerEntry)
				continue
			}
			try complete(write: write, serverEntry: serverEntry)
		}
	}

	private static func isConflict(_ error: any Error) -> Bool {
		switch error {
		case ThingsDiaryClientError.httpStatus(409, _),
			ThingsDiaryClientError.rpc(code: 1006, message: _):
			return true
		default:
			return false
		}
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
	var entryConflicts: [StoredEntryConflict]

	init(
		selectedDiary: StoredDiary? = nil,
		entries: [StoredEntry] = [],
		topics: [StoredTopic] = [],
		templates: [StoredTemplate] = [],
		pendingEntryWrites: [StoredPendingEntryWrite] = [],
		entryConflicts: [StoredEntryConflict] = []
	) {
		self.selectedDiary = selectedDiary
		self.entries = entries
		self.topics = topics
		self.templates = templates
		self.pendingEntryWrites = pendingEntryWrites
		self.entryConflicts = entryConflicts
	}

	private enum CodingKeys: String, CodingKey {
		case selectedDiary, entries, topics, templates
		case pendingEntryWrites, entryConflicts
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
		entryConflicts =
			try container.decodeIfPresent(
				[StoredEntryConflict].self,
				forKey: .entryConflicts
			) ?? []
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
