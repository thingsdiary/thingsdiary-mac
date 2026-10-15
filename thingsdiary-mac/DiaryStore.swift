import Foundation
import ThingsDiaryClient

nonisolated enum PendingEntryOperation: String, Codable, Sendable, Equatable {
    case create
    case update
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
}

nonisolated enum DiaryStoreError: Error {
    case unsupportedRemoteEntry
}

extension ThingsDiaryClient: DiaryStoreRemote {}

actor DiaryStore {
    private let fileURL: URL
    private var state: StoredState

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
        entries: [ThingsDiaryEntry]
    ) throws {
        var entriesByID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        for pendingWrite in state.pendingEntryWrites where pendingWrite.entry.diaryID == diary.id {
            entriesByID[pendingWrite.entry.id] = pendingWrite.entry.value
        }
        let nextState = StoredState(
            selectedDiary: StoredDiary(diary),
            entries: entriesByID.values.map(StoredEntry.init),
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

    func savePendingEntry(_ write: PendingEntryWrite) throws {
        var nextState = state
        nextState.entries.removeAll { $0.id == write.entry.id }
        nextState.entries.append(StoredEntry(write.entry))
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
        for storedWrite in state.pendingEntryWrites {
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
                }
            } catch ThingsDiaryClientError.httpStatus(409, _) {
                let currentServerEntry = try await remote.getEntry(
                    diaryID: write.entry.diaryID,
                    entryID: write.entry.id
                )
                try recordConflict(local: write.entry, server: currentServerEntry)
                continue
            }
            try complete(writeID: write.id, serverEntry: serverEntry)
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
            var nextState = state
            var nextCheckpoint = checkpoint
            for change in page.changes where !nextCheckpoint.contains(change) {
                if change.entityType == .entry {
                    switch change.operation {
                    case .created, .updated, .softDeleted:
                        let serverEntry = try await remote.getEntry(
                            diaryID: diaryID,
                            entryID: change.entityID
                        )
                        nextState.entries.removeAll { $0.id == serverEntry.id }
                        nextState.entries.append(StoredEntry(serverEntry))
                    case .removed:
                        nextState.entries.removeAll { $0.id == change.entityID }
                    }
                }
                nextCheckpoint.record(change)
            }
            nextState.checkpoints[diaryID] = nextCheckpoint
            try persist(nextState)
            state = nextState
            nextPageToken = page.nextPageToken
        } while nextPageToken != nil
    }

    private func complete(
        writeID: String,
        serverEntry: ThingsDiaryEntry
    ) throws {
        var nextState = state
        nextState.entries.removeAll { $0.id == serverEntry.id }
        nextState.entries.append(StoredEntry(serverEntry))
        nextState.pendingEntryWrites.removeAll { $0.entry.id == writeID }
        try persist(nextState)
        state = nextState
    }

    private func recordConflict(
        local: ThingsDiaryEntry,
        server: ThingsDiaryEntry
    ) throws {
        var nextState = state
        nextState.entries.removeAll { $0.id == server.id }
        nextState.entries.append(StoredEntry(server))
        nextState.pendingEntryWrites.removeAll { $0.entry.id == local.id }
        nextState.entryConflicts.removeAll { $0.local.id == local.id }
        nextState.entryConflicts.append(StoredEntryConflict(
            DiaryEntryConflict(local: local, server: server)
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
    var pendingEntryWrites: [StoredPendingEntryWrite]
    var checkpoints: [String: StoredCheckpoint]
    var entryConflicts: [StoredEntryConflict]

    init(
        selectedDiary: StoredDiary? = nil,
        entries: [StoredEntry] = [],
        pendingEntryWrites: [StoredPendingEntryWrite] = [],
        checkpoints: [String: StoredCheckpoint] = [:],
        entryConflicts: [StoredEntryConflict] = []
    ) {
        self.selectedDiary = selectedDiary
        self.entries = entries
        self.pendingEntryWrites = pendingEntryWrites
        self.checkpoints = checkpoints
        self.entryConflicts = entryConflicts
    }

    private enum CodingKeys: String, CodingKey {
        case selectedDiary, entries, pendingEntryWrites, checkpoints, entryConflicts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        selectedDiary = try container.decodeIfPresent(StoredDiary.self, forKey: .selectedDiary)
        entries = try container.decodeIfPresent([StoredEntry].self, forKey: .entries) ?? []
        pendingEntryWrites = try container.decodeIfPresent(
            [StoredPendingEntryWrite].self,
            forKey: .pendingEntryWrites
        ) ?? []
        checkpoints = try container.decodeIfPresent(
            [String: StoredCheckpoint].self,
            forKey: .checkpoints
        ) ?? [:]
        entryConflicts = try container.decodeIfPresent(
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
                  !changeIDsAtLastDate.contains(change.id) {
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
