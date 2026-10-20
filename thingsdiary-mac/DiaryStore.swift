import CryptoKit
import Foundation
import GRDB
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
	private let database: DatabaseQueue
	private var state: StoredState

	nonisolated static func fileURL(in directory: URL, login: String) -> URL {
		let normalizedLogin = login.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
		let digest = SHA256.hash(data: Data(normalizedLogin.utf8))
		let filename = digest.map { String(format: "%02x", $0) }.joined() + ".sqlite"
		return
			directory
			.appending(path: "accounts", directoryHint: .isDirectory)
			.appending(path: filename)
	}

	init(fileURL: URL, legacyJSONURL: URL? = nil) throws {
		database = try DiaryDatabase.open(at: fileURL)
		if let legacyJSONURL {
			try Self.importLegacyJSON(at: legacyJSONURL, into: database)
		}
		state = try Self.load(from: database)
	}

	private init(database: DatabaseQueue) throws {
		self.database = database
		state = try Self.load(from: database)
	}

	static func inMemory() throws -> DiaryStore {
		try DiaryStore(database: DiaryDatabase.inMemory())
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
		try database.write { database in
			try Self.replaceDomain(with: nextState, in: database)
		}
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
		let stored = StoredTopic(topic)
		nextState.topics.append(stored)
		try database.write { database in
			try Self.upsert(stored, in: database)
		}
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

		try database.write { database in
			try database.execute(
				sql: "DELETE FROM topics WHERE diary_id = ? AND id = ?",
				arguments: [diaryID, topicID]
			)
			try database.execute(sql: "DELETE FROM entries WHERE diary_id = ?", arguments: [diaryID])
			for entry in entries.map(StoredEntry.init) {
				try Self.upsert(entry, in: database)
			}
			for write in nextState.pendingEntryWrites where write.entry.diaryID == diaryID {
				try Self.upsert(write, in: database)
			}
		}
		state = nextState
	}

	func upsertTemplate(_ template: ThingsDiaryTemplate) throws {
		var nextState = state
		nextState.templates.removeAll { $0.id == template.id }
		let stored = StoredTemplate(template)
		nextState.templates.append(stored)
		try database.write { database in
			try Self.upsert(stored, in: database)
		}
		state = nextState
	}

	func removeTemplate(diaryID: String, templateID: String) throws {
		var nextState = state
		nextState.templates.removeAll { $0.diaryID == diaryID && $0.id == templateID }
		try database.write { database in
			try database.execute(
				sql: "DELETE FROM templates WHERE diary_id = ? AND id = ?",
				arguments: [diaryID, templateID]
			)
		}
		state = nextState
	}

	func savePendingEntry(_ write: PendingEntryWrite) throws {
		var nextState = state
		nextState.entries.removeAll { $0.id == write.entry.id }
		let storedEntry = StoredEntry(write.entry)
		if write.operation != .remove {
			nextState.entries.append(storedEntry)
		}
		nextState.pendingEntryWrites.removeAll { $0.entry.id == write.entry.id }
		let storedWrite = StoredPendingEntryWrite(write)
		nextState.pendingEntryWrites.append(storedWrite)
		try database.write { database in
			if write.operation == .remove {
				try Self.deleteEntry(id: write.id, diaryID: write.entry.diaryID, in: database)
			} else {
				try Self.upsert(storedEntry, in: database)
			}
			try Self.upsert(storedWrite, in: database)
		}
		state = nextState
	}

	func pendingEntryWrites() -> [PendingEntryWrite] {
		state.pendingEntryWrites.map(\.value)
	}

	func entryConflicts() -> [DiaryEntryConflict] {
		state.entryConflicts.map(\.value)
	}

	func nextPendingEntryWrite() -> PendingEntryWrite? {
		state.pendingEntryWrites.first?.value
	}

	func selectedDiaryID() -> String? {
		state.selectedDiary?.id
	}

	func lastChangeAt(diaryID: String) -> Date? {
		state.checkpoints[diaryID]?.lastChangeAt
	}

	func hasPendingEntry(id: String) -> Bool {
		state.pendingEntryWrites.contains { $0.entry.id == id }
	}

	func applyRemoteEntry(_ entry: ThingsDiaryEntry) throws {
		guard !state.pendingEntryWrites.contains(where: { $0.entry.id == entry.id })
		else { return }
		guard
			!state.entries.contains(where: {
				$0.id == entry.id && $0.version > entry.version
			})
		else { return }
		var nextState = state
		nextState.entries.removeAll { $0.id == entry.id }
		let stored = StoredEntry(entry)
		nextState.entries.append(stored)
		try database.write { database in
			try Self.upsert(stored, in: database)
		}
		state = nextState
	}

	func removeRemoteEntry(id: String, changedAt: Date) throws {
		guard !state.pendingEntryWrites.contains(where: { $0.entry.id == id }) else { return }
		guard !state.entries.contains(where: { $0.id == id && $0.updatedAt > changedAt })
		else { return }
		var nextState = state
		guard let entry = nextState.entries.first(where: { $0.id == id }) else { return }
		nextState.entries.removeAll { $0.id == id }
		try database.write { database in
			try Self.deleteEntry(id: id, diaryID: entry.diaryID, in: database)
		}
		state = nextState
	}

	func applyRemoteTopic(_ topic: ThingsDiaryTopic) throws {
		guard !state.topics.contains(where: { $0.id == topic.id && $0.version > topic.version })
		else { return }
		var nextState = state
		nextState.topics.removeAll { $0.id == topic.id }
		let stored = StoredTopic(topic)
		nextState.topics.append(stored)
		try database.write { database in
			try Self.upsert(stored, in: database)
		}
		state = nextState
	}

	func removeRemoteTopic(id: String, changedAt: Date) throws {
		guard !state.topics.contains(where: { $0.id == id && $0.updatedAt > changedAt })
		else { return }
		var nextState = state
		guard let topic = nextState.topics.first(where: { $0.id == id }) else { return }
		nextState.topics.removeAll { $0.id == id }
		try database.write { database in
			try database.execute(
				sql: "DELETE FROM topics WHERE diary_id = ? AND id = ?",
				arguments: [topic.diaryID, id]
			)
		}
		state = nextState
	}

	func applyRemoteTemplate(_ template: ThingsDiaryTemplate) throws {
		guard
			!state.templates.contains(where: {
				$0.id == template.id && $0.version > template.version
			})
		else { return }
		var nextState = state
		nextState.templates.removeAll { $0.id == template.id }
		let stored = StoredTemplate(template)
		nextState.templates.append(stored)
		try database.write { database in
			try Self.upsert(stored, in: database)
		}
		state = nextState
	}

	func removeRemoteTemplate(id: String, changedAt: Date) throws {
		guard !state.templates.contains(where: { $0.id == id && $0.updatedAt > changedAt })
		else { return }
		var nextState = state
		guard let template = nextState.templates.first(where: { $0.id == id }) else { return }
		nextState.templates.removeAll { $0.id == id }
		try database.write { database in
			try database.execute(
				sql: "DELETE FROM templates WHERE diary_id = ? AND id = ?",
				arguments: [template.diaryID, id]
			)
		}
		state = nextState
	}

	func finishPull(diaryID: String, at date: Date) throws {
		var nextState = state
		nextState.checkpoints[diaryID] = StoredCheckpoint(lastChangeAt: date)
		try database.write { database in
			try database.execute(
				sql: "UPDATE diaries SET last_sync_at = ? WHERE id = ?",
				arguments: [date, diaryID]
			)
		}
		state = nextState
	}

	func complete(write: PendingEntryWrite, serverEntry: ThingsDiaryEntry) throws {
		var nextState = state
		guard
			let currentWrite = nextState.pendingEntryWrites.first(where: {
				$0.entry.id == write.id
			})?.value
		else { return }
		guard currentWrite == write else {
			if write.operation == .create, currentWrite.operation == .create {
				nextState.pendingEntryWrites.removeAll { $0.entry.id == write.id }
				let storedWrite = StoredPendingEntryWrite(
					PendingEntryWrite(operation: .update, entry: currentWrite.entry)
				)
				nextState.pendingEntryWrites.append(storedWrite)
				try database.write { database in
					try Self.upsert(storedWrite, in: database)
				}
				state = nextState
			}
			return
		}
		let storedEntry = StoredEntry(serverEntry)
		nextState.entries.removeAll { $0.id == serverEntry.id }
		nextState.entries.append(storedEntry)
		nextState.pendingEntryWrites.removeAll { $0.entry.id == write.id }
		try database.write { database in
			try Self.upsert(storedEntry, in: database)
			try Self.deleteSync(kind: "pending", write: write, in: database)
		}
		state = nextState
	}

	func completeRemoval(write: PendingEntryWrite) throws {
		var nextState = state
		guard nextState.pendingEntryWrites.contains(where: { $0.value == write }) else {
			return
		}
		nextState.entries.removeAll { $0.id == write.id }
		nextState.pendingEntryWrites.removeAll { $0.entry.id == write.id }
		try database.write { database in
			try Self.deleteEntry(id: write.id, diaryID: write.entry.diaryID, in: database)
			try Self.deleteSync(kind: "pending", write: write, in: database)
		}
		state = nextState
	}

	func recordConflict(write: PendingEntryWrite, server: ThingsDiaryEntry) throws {
		var nextState = state
		guard
			let currentWrite = nextState.pendingEntryWrites.first(where: {
				$0.entry.id == write.id
			})?.value
		else { return }
		guard currentWrite == write else {
			if write.operation == .create, currentWrite.operation == .create {
				nextState.pendingEntryWrites.removeAll { $0.entry.id == write.id }
				let storedWrite = StoredPendingEntryWrite(
					PendingEntryWrite(operation: .update, entry: currentWrite.entry)
				)
				nextState.pendingEntryWrites.append(storedWrite)
				try database.write { database in
					try Self.upsert(storedWrite, in: database)
				}
				state = nextState
			}
			return
		}
		let storedEntry = StoredEntry(server)
		nextState.entries.removeAll { $0.id == server.id }
		nextState.entries.append(storedEntry)
		nextState.pendingEntryWrites.removeAll { $0.entry.id == write.id }
		nextState.entryConflicts.removeAll { $0.local.id == write.id }
		let storedConflict = StoredEntryConflict(
			DiaryEntryConflict(local: write.entry, server: server)
		)
		nextState.entryConflicts.append(storedConflict)
		try database.write { database in
			try Self.upsert(storedEntry, in: database)
			try Self.deleteSync(kind: "pending", write: write, in: database)
			try Self.upsert(storedConflict, in: database)
		}
		state = nextState
	}

	private static func upsert(_ entry: StoredEntry, in database: Database) throws {
		try database.execute(
			sql: """
				INSERT INTO entries (diary_id, id, payload) VALUES (?, ?, ?)
				ON CONFLICT (diary_id, id) DO UPDATE SET payload = excluded.payload
				""",
			arguments: [entry.diaryID, entry.id, try encoder.encode(entry)]
		)
	}

	private static func upsert(_ topic: StoredTopic, in database: Database) throws {
		try database.execute(
			sql: """
				INSERT INTO topics (diary_id, id, payload) VALUES (?, ?, ?)
				ON CONFLICT (diary_id, id) DO UPDATE SET payload = excluded.payload
				""",
			arguments: [topic.diaryID, topic.id, try encoder.encode(topic)]
		)
	}

	private static func upsert(_ template: StoredTemplate, in database: Database) throws {
		try database.execute(
			sql: """
				INSERT INTO templates (diary_id, id, payload) VALUES (?, ?, ?)
				ON CONFLICT (diary_id, id) DO UPDATE SET payload = excluded.payload
				""",
			arguments: [template.diaryID, template.id, try encoder.encode(template)]
		)
	}

	private static func upsert(_ write: StoredPendingEntryWrite, in database: Database) throws {
		try database.execute(
			sql: """
				INSERT INTO sync (kind, diary_id, entity_id, operation, payload)
				VALUES ('pending', ?, ?, ?, ?)
				ON CONFLICT (kind, diary_id, entity_id) DO UPDATE SET
					operation = excluded.operation,
					payload = excluded.payload
				""",
			arguments: [
				write.entry.diaryID,
				write.entry.id,
				write.operation.rawValue,
				try encoder.encode(write),
			]
		)
	}

	private static func upsert(_ conflict: StoredEntryConflict, in database: Database) throws {
		try database.execute(
			sql: """
				INSERT INTO sync (kind, diary_id, entity_id, operation, payload)
				VALUES ('conflict', ?, ?, NULL, ?)
				ON CONFLICT (kind, diary_id, entity_id) DO UPDATE SET
					operation = NULL,
					payload = excluded.payload
				""",
			arguments: [
				conflict.local.diaryID,
				conflict.local.id,
				try encoder.encode(conflict),
			]
		)
	}

	private static func deleteEntry(id: String, diaryID: String, in database: Database) throws {
		try database.execute(
			sql: "DELETE FROM entries WHERE diary_id = ? AND id = ?",
			arguments: [diaryID, id]
		)
	}

	private static func deleteSync(
		kind: String,
		write: PendingEntryWrite,
		in database: Database
	) throws {
		try database.execute(
			sql: "DELETE FROM sync WHERE kind = ? AND diary_id = ? AND entity_id = ?",
			arguments: [kind, write.entry.diaryID, write.id]
		)
	}

	private static func importLegacyJSON(at url: URL, into database: DatabaseQueue) throws {
		guard FileManager.default.fileExists(atPath: url.path) else { return }
		let backupURL = url.appendingPathExtension("backup")
		guard !FileManager.default.fileExists(atPath: backupURL.path) else { return }
		let imported = try database.write { database in
			guard try isEmpty(database) else { return false }
			let state = try decoder.decode(StoredState.self, from: Data(contentsOf: url))
			try write(state, to: database)
			return true
		}
		guard imported else { return }
		try FileManager.default.copyItem(at: url, to: backupURL)
	}

	private static func isEmpty(_ database: Database) throws -> Bool {
		for table in ["diaries", "entries", "topics", "templates", "sync"] {
			if try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM \(table)") != 0 {
				return false
			}
		}
		return true
	}

	private static func write(_ state: StoredState, to database: Database) throws {
		try database.execute(sql: "DELETE FROM sync")
		try replaceDomain(with: state, in: database)
		for write in state.pendingEntryWrites {
			try upsert(write, in: database)
		}
		for conflict in state.entryConflicts {
			try upsert(conflict, in: database)
		}
	}

	private static func replaceDomain(with state: StoredState, in database: Database) throws {
		try database.execute(sql: "DELETE FROM entries")
		try database.execute(sql: "DELETE FROM topics")
		try database.execute(sql: "DELETE FROM templates")
		try database.execute(sql: "DELETE FROM diaries")

		if let diary = state.selectedDiary {
			try database.execute(
				sql: """
					INSERT INTO diaries (id, selected, last_sync_at, payload)
					VALUES (?, 1, ?, ?)
					""",
				arguments: [
					diary.id,
					state.checkpoints[diary.id]?.lastChangeAt,
					try encoder.encode(diary),
				]
			)
		}

		for entry in state.entries {
			try upsert(entry, in: database)
		}
		for topic in state.topics {
			try upsert(topic, in: database)
		}
		for template in state.templates {
			try upsert(template, in: database)
		}
	}

	private static func load(from database: DatabaseQueue) throws -> StoredState {
		try database.read { database in
			let diaryRow = try Row.fetchOne(
				database,
				sql: "SELECT payload, last_sync_at FROM diaries WHERE selected = 1 LIMIT 1"
			)
			let selectedDiary = try diaryRow.map { row in
				try decoder.decode(StoredDiary.self, from: row["payload"] as Data)
			}
			let entries = try Row.fetchAll(database, sql: "SELECT payload FROM entries").map {
				try decoder.decode(StoredEntry.self, from: $0["payload"] as Data)
			}
			let topics = try Row.fetchAll(database, sql: "SELECT payload FROM topics").map {
				try decoder.decode(StoredTopic.self, from: $0["payload"] as Data)
			}
			let templates = try Row.fetchAll(database, sql: "SELECT payload FROM templates").map {
				try decoder.decode(StoredTemplate.self, from: $0["payload"] as Data)
			}
			let pendingWrites = try Row.fetchAll(
				database,
				sql: "SELECT payload FROM sync WHERE kind = 'pending'"
			).map {
				try decoder.decode(StoredPendingEntryWrite.self, from: $0["payload"] as Data)
			}
			let conflicts = try Row.fetchAll(
				database,
				sql: "SELECT payload FROM sync WHERE kind = 'conflict'"
			).map {
				try decoder.decode(StoredEntryConflict.self, from: $0["payload"] as Data)
			}
			var checkpoints: [String: StoredCheckpoint] = [:]
			if let selectedDiary, let diaryRow,
				let lastSyncAt = diaryRow["last_sync_at"] as Date?
			{
				checkpoints[selectedDiary.id] = StoredCheckpoint(lastChangeAt: lastSyncAt)
			}
			return StoredState(
				selectedDiary: selectedDiary,
				entries: entries,
				topics: topics,
				templates: templates,
				pendingEntryWrites: pendingWrites,
				checkpoints: checkpoints,
				entryConflicts: conflicts
			)
		}
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
