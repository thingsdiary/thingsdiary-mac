import Foundation
import Testing
import ThingsDiaryClient
@testable import thingsdiary_mac

@MainActor
@Test("Registration generates a secret key and exposes public keys")
func successfulRegistrationShowsKeys() async throws {
    let publicKeys = ThingsDiaryPublicKeys(
        signing: "signing-public-key",
        encryption: "encryption-public-key"
    )
    let client = StubAppClient(
        result: .success([]),
        registrationResult: .success(publicKeys)
    )
    let model = ThingsDiaryAppModel(client: client)
    model.login = "new-person@example.test"
    model.password = "password"

    await model.register()

    guard case let .registrationComplete(result) = model.screen else {
        Issue.record("Expected completed registration")
        return
    }
    let registeredSecretKey = await client.receivedRegistrationSecretKey
    #expect(try ThingsDiarySecretKey.parse(result.secretKey).rawValue == result.secretKey)
    #expect(result.publicKeys == publicKeys)
    #expect(result.secretKey == registeredSecretKey)
    #expect(model.password.isEmpty)
}

@MainActor
@Test("Continuing after registration hides the secret key and loads diaries")
func registrationContinuesToDiaries() async {
    let diary = ThingsDiaryDiary(
        id: "diary-1",
        title: "Personal",
        description: "Daily notes",
        createdAt: Date(timeIntervalSince1970: 1),
        updatedAt: Date(timeIntervalSince1970: 2),
        version: 3
    )
    let client = StubAppClient(result: .success([diary]))
    let model = ThingsDiaryAppModel(client: client)
    model.login = "new-person@example.test"
    model.password = "password"
    await model.register()

    await model.continueAfterRegistration()

    #expect(model.screen == .diaries([diary]))
}

@MainActor
@Test("User can switch between sign in and registration")
func switchesAuthenticationForm() {
    let model = ThingsDiaryAppModel(client: StubAppClient(result: .success([])))

    model.showRegistration()
    #expect(model.screen == .registration)

    model.showLogin()
    #expect(model.screen == .login)
}

@MainActor
@Test("Successful login loads decrypted diaries and clears secrets")
func successfulLoginLoadsDiaries() async throws {
    let diary = ThingsDiaryDiary(
        id: "diary-1",
        title: "Personal",
        description: "Daily notes",
        createdAt: Date(timeIntervalSince1970: 1),
        updatedAt: Date(timeIntervalSince1970: 2),
        version: 3
    )
    let client = StubAppClient(result: .success([diary]))
    let model = ThingsDiaryAppModel(client: client)
    model.login = "person@example.test"
    model.password = "password"
    model.secretKey = "TDKV1-000G-40R4-0M30-E209-185G-R38E-1W6"

    await model.submit()

    #expect(model.screen == .diaries([diary]))
    #expect(model.password.isEmpty)
    #expect(model.secretKey.isEmpty)
    #expect(await client.receivedLogin == "person@example.test")
    #expect(await client.receivedPassword == "password")
    #expect(await client.receivedSecretKey == "TDKV1-000G-40R4-0M30-E209-185G-R38E-1W6")
}

@MainActor
@Test("Selecting a diary loads its plaintext entries")
func selectingDiaryLoadsEntries() async {
    let diary = ThingsDiaryDiary(
        id: "diary-1",
        title: "Personal",
        description: "Daily notes",
        createdAt: Date(timeIntervalSince1970: 1),
        updatedAt: Date(timeIntervalSince1970: 2),
        version: 3
    )
    let entry = ThingsDiaryEntry(
        id: "entry-1",
        diaryID: diary.id,
        content: "First note",
        createdAt: Date(timeIntervalSince1970: 3),
        updatedAt: Date(timeIntervalSince1970: 4),
        version: 5
    )
    let client = StubAppClient(
        result: .success([diary]),
        entriesResult: .success([entry])
    )
    let model = ThingsDiaryAppModel(client: client)
    model.login = "person@example.test"
    model.password = "password"
    model.secretKey = "TDKV1-000G-40R4-0M30-E209-185G-R38E-1W6"
    await model.submit()

    await model.selectDiary(diary)

    let receivedDiaryID = await client.receivedEntriesDiaryID
    #expect(model.screen == .entries(diary: diary, entries: [entry]))
    #expect(receivedDiaryID == diary.id)
}

@MainActor
@Test("User can return from entries to the loaded diary list")
func returnsToLoadedDiaries() async {
    let diary = diary(id: "diary-1", title: "Personal")
    let model = ThingsDiaryAppModel(client: StubAppClient(result: .success([diary])))
    model.login = "person@example.test"
    model.password = "password"
    model.secretKey = "TDKV1-000G-40R4-0M30-E209-185G-R38E-1W6"
    await model.submit()
    await model.selectDiary(diary)

    model.showDiaries()

    #expect(model.screen == .diaries([diary]))
}

@MainActor
@Test("Creating a note adds the server result to the selected diary")
func createsEntryInSelectedDiary() async {
    let diary = diary(id: "diary-1", title: "Personal")
    let created = entry(id: "entry-new", diaryID: diary.id, content: "New note")
    let client = StubAppClient(
        result: .success([diary]),
        createEntryResult: .success(created)
    )
    let model = ThingsDiaryAppModel(client: client)
    model.login = "person@example.test"
    model.password = "password"
    model.secretKey = "TDKV1-000G-40R4-0M30-E209-185G-R38E-1W6"
    await model.submit()
    await model.selectDiary(diary)

    await model.createEntry(content: "New note")

    #expect(model.screen == .entries(diary: diary, entries: [created]))
}

@MainActor
@Test("Creating a note offline keeps it visible and queues synchronization")
func createsEntryOffline() async throws {
    let fileURL = FileManager.default.temporaryDirectory
        .appending(path: "thingsdiary-app-create-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: fileURL) }
    let selectedDiary = diary(id: "diary-1", title: "Personal")
    let store = try DiaryStore(fileURL: fileURL)
    let client = StubAppClient(
        result: .success([selectedDiary]),
        createEntryResult: .failure(TestFailure.rejected)
    )
    let model = ThingsDiaryAppModel(client: client, store: store)
    await model.selectDiary(selectedDiary)

    await model.createEntry(content: "Offline note")

    guard case let .entries(diary, entries) = model.screen else {
        Issue.record("Expected the selected diary with its local note")
        return
    }
    #expect(diary == selectedDiary)
    #expect(entries.count == 1)
    #expect(entries.first?.content == "Offline note")
    let pendingWrites = await store.pendingEntryWrites()
    #expect(pendingWrites.count == 1)
    #expect(pendingWrites.first?.entry.id == entries.first?.id)
}

@MainActor
@Test("Updating a note replaces it with the server result")
func updatesEntryInSelectedDiary() async {
    let diary = diary(id: "diary-1", title: "Personal")
    let original = entry(id: "entry-1", diaryID: diary.id, content: "Before")
    let updated = entry(id: "entry-1", diaryID: diary.id, content: "After")
    let client = StubAppClient(
        result: .success([diary]),
        entriesResult: .success([original]),
        updateEntryResult: .success(updated)
    )
    let model = ThingsDiaryAppModel(client: client)
    model.login = "person@example.test"
    model.password = "password"
    model.secretKey = "TDKV1-000G-40R4-0M30-E209-185G-R38E-1W6"
    await model.submit()
    await model.selectDiary(diary)

    await model.updateEntry(original, content: "After")

    #expect(model.screen == .entries(diary: diary, entries: [updated]))
}

@MainActor
@Test("Updating a note offline keeps the edit visible and queues synchronization")
func updatesEntryOffline() async throws {
    let fileURL = FileManager.default.temporaryDirectory
        .appending(path: "thingsdiary-app-update-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: fileURL) }
    let selectedDiary = diary(id: "diary-1", title: "Personal")
    let original = entry(id: "entry-1", diaryID: selectedDiary.id, content: "Before")
    let store = try DiaryStore(fileURL: fileURL)
    let client = StubAppClient(
        result: .success([selectedDiary]),
        entriesResult: .success([original]),
        updateEntryResult: .failure(TestFailure.rejected)
    )
    let model = ThingsDiaryAppModel(client: client, store: store)
    await model.selectDiary(selectedDiary)

    await model.updateEntry(original, content: "After")

    guard case let .entries(diary, entries) = model.screen else {
        Issue.record("Expected the selected diary with its local edit")
        return
    }
    #expect(diary == selectedDiary)
    #expect(entries.count == 1)
    #expect(entries.first?.id == original.id)
    #expect(entries.first?.content == "After")
    #expect((entries.first?.version ?? 0) > original.version)
    let pendingWrites = await store.pendingEntryWrites()
    #expect(pendingWrites.count == 1)
    #expect(pendingWrites.first?.operation == .update)
    #expect(pendingWrites.first?.entry.content == "After")
}

@MainActor
@Test("A stale entry response cannot replace the newly selected diary")
func latestDiarySelectionWins() async throws {
    let diaryA = diary(id: "diary-a", title: "A")
    let diaryB = diary(id: "diary-b", title: "B")
    let entryA = entry(id: "entry-a", diaryID: diaryA.id, content: "From A")
    let entryB = entry(id: "entry-b", diaryID: diaryB.id, content: "From B")
    let model = ThingsDiaryAppModel(client: DelayedEntriesAppClient(
        diaries: [diaryA, diaryB],
        entries: [diaryA.id: [entryA], diaryB.id: [entryB]],
        delayedDiaryID: diaryA.id
    ))

    let firstSelection = Task { await model.selectDiary(diaryA) }
    try await Task.sleep(for: .milliseconds(20))
    await model.selectDiary(diaryB)
    await firstSelection.value

    #expect(model.screen == .entries(diary: diaryB, entries: [entryB]))
}

@MainActor
@Test("Opening the persisted diary falls back to cached notes when offline")
func selectingDiaryUsesCachedEntriesWhenOffline() async throws {
    let fileURL = FileManager.default.temporaryDirectory
        .appending(path: "thingsdiary-app-cache-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: fileURL) }
    let selectedDiary = diary(id: "diary-1", title: "Personal")
    let cachedEntry = entry(
        id: "entry-1",
        diaryID: selectedDiary.id,
        content: "Available offline"
    )
    let store = try DiaryStore(fileURL: fileURL)
    try await store.replaceSelectedDiary(selectedDiary, entries: [cachedEntry])
    let model = ThingsDiaryAppModel(
        client: StubAppClient(
            result: .success([selectedDiary]),
            entriesResult: .failure(TestFailure.rejected)
        ),
        store: store
    )

    await model.selectDiary(selectedDiary)

    #expect(model.screen == .entries(diary: selectedDiary, entries: [cachedEntry]))
}

@MainActor
@Test("Failed login shows an error, clears secrets, and allows retry")
func failedLoginAllowsRetry() async {
    let client = StubAppClient(result: .failure(TestFailure.rejected))
    let model = ThingsDiaryAppModel(client: client)
    model.login = "person@example.test"
    model.password = "wrong"
    model.secretKey = "TDKV1-000G-40R4-0M30-E209-185G-R38E-1W6"

    await model.submit()

    guard case .error = model.screen else {
        Issue.record("Expected error state")
        return
    }
    #expect(model.password.isEmpty)
    #expect(model.secretKey.isEmpty)

    model.retry()
    #expect(model.screen == .login)
}

@MainActor
@Test("Login requires all credentials before calling the client")
func loginRequiresAllCredentials() async {
    let client = StubAppClient(result: .success([]))
    let model = ThingsDiaryAppModel(client: client)
    model.login = "person@example.test"
    model.password = "   "
    model.secretKey = "TDKV1-000G-40R4-0M30-E209-185G-R38E-1W6"

    await model.submit()

    #expect(model.screen == .error("Enter login, password, and a valid TDKV1 secret key."))
    #expect(await client.receivedLogin == nil)
}

@MainActor
@Test("Login rejects an invalid TDKV1 key before calling the client")
func loginRejectsInvalidSecretKey() async {
    let client = StubAppClient(result: .success([]))
    let model = ThingsDiaryAppModel(client: client)
    model.login = "person@example.test"
    model.password = "password"
    model.secretKey = "TDKV1-000G-40R4-0M30-E209-185G-R38E-1W0"

    await model.submit()

    #expect(model.screen == .error("Enter login, password, and a valid TDKV1 secret key."))
    #expect(await client.receivedLogin == nil)
}

private enum TestFailure: Error {
    case rejected
}

private func diary(id: String, title: String) -> ThingsDiaryDiary {
    ThingsDiaryDiary(
        id: id,
        title: title,
        description: "",
        createdAt: Date(timeIntervalSince1970: 1),
        updatedAt: Date(timeIntervalSince1970: 2),
        version: 3
    )
}

private func entry(id: String, diaryID: String, content: String) -> ThingsDiaryEntry {
    ThingsDiaryEntry(
        id: id,
        diaryID: diaryID,
        content: content,
        createdAt: Date(timeIntervalSince1970: 3),
        updatedAt: Date(timeIntervalSince1970: 4),
        version: 5
    )
}

private actor DelayedEntriesAppClient: ThingsDiaryAppClient {
    let storedDiaries: [ThingsDiaryDiary]
    let storedEntries: [String: [ThingsDiaryEntry]]
    let delayedDiaryID: String

    init(
        diaries: [ThingsDiaryDiary],
        entries: [String: [ThingsDiaryEntry]],
        delayedDiaryID: String
    ) {
        storedDiaries = diaries
        storedEntries = entries
        self.delayedDiaryID = delayedDiaryID
    }

    func register(
        login: String,
        password: String,
        secretKey: String,
        kdfSalt: String
    ) async throws -> ThingsDiaryPublicKeys {
        ThingsDiaryPublicKeys(signing: "signing", encryption: "encryption")
    }

    func login(login: String, password: String, secretKey: String) async throws {}

    func diaries() async throws -> [ThingsDiaryDiary] {
        storedDiaries
    }

    func entries(diaryID: String) async throws -> [ThingsDiaryEntry] {
        if diaryID == delayedDiaryID {
            try await Task.sleep(for: .milliseconds(100))
        }
        return storedEntries[diaryID] ?? []
    }

    func createEntry(
        diaryID: String,
        params: ThingsDiaryEntryParams
    ) async throws -> ThingsDiaryEntry {
        throw TestFailure.rejected
    }

    func updateEntry(
        _ entry: ThingsDiaryEntry,
        params: ThingsDiaryEntryParams
    ) async throws -> ThingsDiaryEntry {
        throw TestFailure.rejected
    }
}

private actor StubAppClient: ThingsDiaryAppClient {
    let result: Result<[ThingsDiaryDiary], Error>
    let registrationResult: Result<ThingsDiaryPublicKeys, Error>
    let entriesResult: Result<[ThingsDiaryEntry], Error>
    let createEntryResult: Result<ThingsDiaryEntry, Error>?
    let updateEntryResult: Result<ThingsDiaryEntry, Error>?
    private(set) var receivedLogin: String?
    private(set) var receivedPassword: String?
    private(set) var receivedSecretKey: String?
    private(set) var receivedRegistrationSecretKey: String?
    private(set) var receivedEntriesDiaryID: String?

    init(
        result: Result<[ThingsDiaryDiary], Error>,
        registrationResult: Result<ThingsDiaryPublicKeys, Error> = .success(
            ThingsDiaryPublicKeys(signing: "signing", encryption: "encryption")
        ),
        entriesResult: Result<[ThingsDiaryEntry], Error> = .success([]),
        createEntryResult: Result<ThingsDiaryEntry, Error>? = nil,
        updateEntryResult: Result<ThingsDiaryEntry, Error>? = nil
    ) {
        self.result = result
        self.registrationResult = registrationResult
        self.entriesResult = entriesResult
        self.createEntryResult = createEntryResult
        self.updateEntryResult = updateEntryResult
    }

    func register(
        login: String,
        password: String,
        secretKey: String,
        kdfSalt: String
    ) async throws -> ThingsDiaryPublicKeys {
        receivedRegistrationSecretKey = secretKey
        return try registrationResult.get()
    }

    func login(login: String, password: String, secretKey: String) async throws {
        receivedLogin = login
        receivedPassword = password
        receivedSecretKey = secretKey
        if case let .failure(error) = result {
            throw error
        }
    }

    func diaries() async throws -> [ThingsDiaryDiary] {
        try result.get()
    }

    func entries(diaryID: String) async throws -> [ThingsDiaryEntry] {
        receivedEntriesDiaryID = diaryID
        return try entriesResult.get()
    }

    func createEntry(
        diaryID: String,
        params: ThingsDiaryEntryParams
    ) async throws -> ThingsDiaryEntry {
        guard let createEntryResult else {
            throw TestFailure.rejected
        }
        return try createEntryResult.get()
    }

    func updateEntry(
        _ entry: ThingsDiaryEntry,
        params: ThingsDiaryEntryParams
    ) async throws -> ThingsDiaryEntry {
        guard let updateEntryResult else {
            throw TestFailure.rejected
        }
        return try updateEntryResult.get()
    }
}

