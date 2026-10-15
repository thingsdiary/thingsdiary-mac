import Foundation
import Observation
import ThingsDiaryClient

struct ThingsDiaryPublicKeys: Sendable, Equatable {
    let signing: String
    let encryption: String
}

struct ThingsDiaryRegistrationResult: Sendable, Equatable {
    let secretKey: String
    let publicKeys: ThingsDiaryPublicKeys
}

nonisolated protocol ThingsDiaryAppClient: DiaryStoreRemote {
    func register(
        login: String,
        password: String,
        secretKey: String,
        kdfSalt: String
    ) async throws -> ThingsDiaryPublicKeys
    func login(login: String, password: String, secretKey: String) async throws
    func diaries() async throws -> [ThingsDiaryDiary]
    func entries(diaryID: String) async throws -> [ThingsDiaryEntry]
    func createEntry(
        diaryID: String,
        params: ThingsDiaryEntryParams
    ) async throws -> ThingsDiaryEntry
    func updateEntry(
        _ entry: ThingsDiaryEntry,
        params: ThingsDiaryEntryParams
    ) async throws -> ThingsDiaryEntry
}

extension ThingsDiaryAppClient {
    func createEntry(
        diaryID: String,
        entryID: String,
        params: ThingsDiaryEntryParams
    ) async throws -> ThingsDiaryEntry {
        try await createEntry(diaryID: diaryID, params: params)
    }
}

nonisolated struct LiveThingsDiaryAppClient: ThingsDiaryAppClient {
    private let client: ThingsDiaryClient

    init(client: ThingsDiaryClient = ThingsDiaryClient()) {
        self.client = client
    }

    func register(
        login: String,
        password: String,
        secretKey: String,
        kdfSalt: String
    ) async throws -> ThingsDiaryPublicKeys {
        let state = try await client.register(
            login: login,
            password: password,
            secretKey: secretKey,
            kdfSalt: kdfSalt
        )
        return ThingsDiaryPublicKeys(
            signing: state.credentials.signingPublicKey.base64EncodedString(),
            encryption: state.credentials.encryptionPublicKey.base64EncodedString()
        )
    }

    func login(login: String, password: String, secretKey: String) async throws {
        _ = try await client.login(
            login: login,
            password: password,
            secretKey: secretKey
        )
    }

    func diaries() async throws -> [ThingsDiaryDiary] {
        try await client.allDiaries()
    }

    func entries(diaryID: String) async throws -> [ThingsDiaryEntry] {
        try await client.allEntries(diaryID: diaryID)
    }

    func createEntry(
        diaryID: String,
        params: ThingsDiaryEntryParams
    ) async throws -> ThingsDiaryEntry {
        try await client.createEntry(diaryID: diaryID, params: params)
    }

    func createEntry(
        diaryID: String,
        entryID: String,
        params: ThingsDiaryEntryParams
    ) async throws -> ThingsDiaryEntry {
        try await client.createEntry(
            diaryID: diaryID,
            entryID: entryID,
            params: params
        )
    }

    func updateEntry(
        _ entry: ThingsDiaryEntry,
        params: ThingsDiaryEntryParams
    ) async throws -> ThingsDiaryEntry {
        try await client.updateEntry(entry, params: params)
    }

    func getDiaryChanges(
        diaryID: String,
        since: Date?,
        limit: Int?,
        nextPageToken: String?
    ) async throws -> ThingsDiaryChangesPage {
        try await client.getDiaryChanges(
            diaryID: diaryID,
            since: since,
            limit: limit,
            nextPageToken: nextPageToken
        )
    }

    func getEntry(
        diaryID: String,
        entryID: String
    ) async throws -> ThingsDiaryEntry {
        try await client.getEntry(diaryID: diaryID, entryID: entryID)
    }
}

enum ThingsDiaryAppScreen: Equatable {
    case login
    case registration
    case loading
    case registrationComplete(ThingsDiaryRegistrationResult)
    case diaries([ThingsDiaryDiary])
    case entries(diary: ThingsDiaryDiary, entries: [ThingsDiaryEntry])
    case error(String)
}

@MainActor
@Observable
final class ThingsDiaryAppModel {
    var login = ""
    var password = ""
    var secretKey = ""
    private(set) var screen: ThingsDiaryAppScreen = .login

    private let client: any ThingsDiaryAppClient
    private let store: DiaryStore?
    private var diarySelectionID: UUID?
    private var loadedDiaries: [ThingsDiaryDiary] = []

    var canSubmit: Bool {
        !login.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (try? ThingsDiarySecretKey.parse(secretKey)) != nil
    }

    var canRegister: Bool {
        !login.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(
        client: any ThingsDiaryAppClient = LiveThingsDiaryAppClient(),
        store: DiaryStore? = nil
    ) {
        self.client = client
        self.store = store
    }

    func showRegistration() {
        password = ""
        secretKey = ""
        screen = .registration
    }

    func showLogin() {
        password = ""
        secretKey = ""
        screen = .login
    }

    func continueAfterRegistration() async {
        guard case .registrationComplete = screen else {
            return
        }
        screen = .loading
        do {
            let diaries = try await client.diaries()
            loadedDiaries = diaries
            screen = .diaries(diaries)
        } catch {
            screen = .error("Account created, but diaries could not be loaded. Sign in to try again.")
        }
    }

    func showDiaries() {
        diarySelectionID = nil
        screen = .diaries(loadedDiaries)
    }

    func selectDiary(_ diary: ThingsDiaryDiary) async {
        let selectionID = UUID()
        diarySelectionID = selectionID
        screen = .loading
        do {
            let entries = try await client.entries(diaryID: diary.id)
            guard diarySelectionID == selectionID else {
                return
            }
            if let store {
                try await store.replaceSelectedDiary(diary, entries: entries)
                try await store.synchronize(with: client)
            }
            let displayedEntries: [ThingsDiaryEntry]
            if let store {
                displayedEntries = await store.entries(diaryID: diary.id)
            } else {
                displayedEntries = entries
            }
            screen = .entries(
                diary: diary,
                entries: displayedEntries
            )
        } catch {
            guard diarySelectionID == selectionID else {
                return
            }
            if let store,
               await store.selectedDiary()?.id == diary.id {
                screen = .entries(
                    diary: diary,
                    entries: await store.entries(diaryID: diary.id)
                )
                return
            }
            screen = .error("Could not load entries for \(diary.title).")
        }
    }

    func createEntry(content: String) async {
        guard case let .entries(diary, entries) = screen else {
            return
        }
        let content = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else {
            return
        }
        if let store {
            let now = Date()
            let localEntry = ThingsDiaryEntry(
                id: UUID().uuidString.lowercased(),
                diaryID: diary.id,
                content: content,
                createdAt: now,
                updatedAt: now,
                version: UInt64(now.timeIntervalSince1970 * 1_000)
            )
            do {
                try await store.savePendingEntry(PendingEntryWrite(
                    operation: .create,
                    entry: localEntry
                ))
                screen = .entries(diary: diary, entries: entries + [localEntry])
                try await store.synchronize(with: client)
                screen = .entries(
                    diary: diary,
                    entries: await store.entries(diaryID: diary.id)
                )
            } catch {
                screen = .entries(
                    diary: diary,
                    entries: await store.entries(diaryID: diary.id)
                )
            }
            return
        }
        screen = .loading
        do {
            let created = try await client.createEntry(
                diaryID: diary.id,
                params: ThingsDiaryEntryParams(content: content)
            )
            screen = .entries(diary: diary, entries: entries + [created])
        } catch {
            screen = .error("Could not create the note.")
        }
    }

    func updateEntry(_ entry: ThingsDiaryEntry, content: String) async {
        guard case let .entries(diary, entries) = screen else {
            return
        }
        let content = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else {
            return
        }
        if let store {
            let now = Date()
            let localEntry = ThingsDiaryEntry(
                id: entry.id,
                diaryID: entry.diaryID,
                content: content,
                topicID: entry.topicID,
                archived: entry.archived,
                bookmarked: entry.bookmarked,
                previewHidden: entry.previewHidden,
                createdAt: entry.createdAt,
                updatedAt: now,
                deletedAt: entry.deletedAt,
                version: max(
                    UInt64(now.timeIntervalSince1970 * 1_000),
                    entry.version + 1
                )
            )
            do {
                try await store.savePendingEntry(PendingEntryWrite(
                    operation: .update,
                    entry: localEntry
                ))
                screen = .entries(
                    diary: diary,
                    entries: entries.map { $0.id == localEntry.id ? localEntry : $0 }
                )
                try await store.synchronize(with: client)
                screen = .entries(
                    diary: diary,
                    entries: await store.entries(diaryID: diary.id)
                )
            } catch {
                screen = .entries(
                    diary: diary,
                    entries: await store.entries(diaryID: diary.id)
                )
            }
            return
        }
        screen = .loading
        do {
            let updated = try await client.updateEntry(
                entry,
                params: ThingsDiaryEntryParams(
                    content: content,
                    topicID: entry.topicID,
                    archived: entry.archived,
                    bookmarked: entry.bookmarked,
                    previewHidden: entry.previewHidden
                )
            )
            let updatedEntries = entries.map { current in
                current.id == updated.id ? updated : current
            }
            screen = .entries(diary: diary, entries: updatedEntries)
        } catch {
            screen = .error("Could not update the note.")
        }
    }

    func register() async {
        guard !login.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            password = ""
            screen = .error("Enter login and password to register.")
            return
        }

        let login = login
        let password = password
        let secretKey = ThingsDiarySecretKey.generate().rawValue
        let kdfSalt = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        screen = .loading

        defer {
            self.password = ""
        }

        do {
            let publicKeys = try await client.register(
                login: login,
                password: password,
                secretKey: secretKey,
                kdfSalt: kdfSalt
            )
            screen = .registrationComplete(ThingsDiaryRegistrationResult(
                secretKey: secretKey,
                publicKeys: publicKeys
            ))
        } catch {
            screen = .error("Could not register. Check the account details and try again.")
        }
    }

    func submit() async {
        guard canSubmit else {
            password = ""
            secretKey = ""
            screen = .error("Enter login, password, and a valid TDKV1 secret key.")
            return
        }

        let login = login
        let password = password
        let secretKey = secretKey
        screen = .loading

        defer {
            self.password = ""
            self.secretKey = ""
        }

        do {
            try await client.login(
                login: login,
                password: password,
                secretKey: secretKey
            )
            let diaries = try await client.diaries()
            loadedDiaries = diaries
            screen = .diaries(diaries)
        } catch {
            screen = .error("Could not sign in or load diaries. Check your credentials and try again.")
        }
    }

    func retry() {
        screen = .login
    }
}
