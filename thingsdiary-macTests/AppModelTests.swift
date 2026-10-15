import Foundation
import Testing
import ThingsDiaryClient

@testable import thingsdiary

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

	guard case .registrationComplete(let result) = model.screen else {
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
@Test("Registration validates email and password before calling the server")
func registrationValidatesCredentials() async {
	let client = StubAppClient(result: .success([]))
	let model = ThingsDiaryAppModel(client: client)
	model.login = "not-an-email"
	model.password = "short"

	await model.register()

	#expect(
		model.screen
			== .error(
				"Enter a valid email and a password with at least 8 characters."
			))
	#expect(await client.receivedRegistrationSecretKey == nil)
}

@MainActor
@Test("Registration explains that the account already exists")
func registrationExplainsDuplicateAccount() async {
	let client = StubAppClient(
		result: .success([]),
		registrationResult: .failure(
			ThingsDiaryClientError.httpStatus(
				409,
				body: Data(#"{"error_code":"account_already_exists"}"#.utf8)
			))
	)
	let model = ThingsDiaryAppModel(client: client)
	model.login = "person@example.test"
	model.password = "password"

	await model.register()

	#expect(model.screen == .error("An account with this email already exists."))
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

	#expect(model.screen == .entries(diary: diary, entries: []))
	#expect(model.presentation == .none)
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

	#expect(model.screen == .entries(diary: diary, entries: []))
	#expect(model.password.isEmpty)
	#expect(model.secretKey.isEmpty)
	#expect(await client.receivedLogin == "person@example.test")
	#expect(await client.receivedPassword == "password")
	#expect(await client.receivedSecretKey == "TDKV1-000G-40R4-0M30-E209-185G-R38E-1W6")
}

@MainActor
@Test("An empty diary list opens diary creation")
func emptyDiaryListOpensCreation() async {
	let model = ThingsDiaryAppModel(client: StubAppClient(result: .success([])))
	model.login = "person@example.test"
	model.password = "password"
	model.secretKey = "TDKV1-000G-40R4-0M30-E209-185G-R38E-1W6"

	await model.submit()

	#expect(model.screen == .diaries([]))
	#expect(model.isCreatingDiary)
	#expect(model.presentation == .diaryCreation)
}

@MainActor
@Test("Login routes one diary directly into its workspace")
func loginSelectsSingleDiary() async {
	let selectedDiary = diary(id: "diary-1", title: "Personal")
	let client = StubAppClient(result: .success([selectedDiary]))
	let model = ThingsDiaryAppModel(client: client)
	model.login = "person@example.test"
	model.password = "password"
	model.secretKey = "TDKV1-000G-40R4-0M30-E209-185G-R38E-1W6"

	await model.submit()

	#expect(model.screen == .entries(diary: selectedDiary, entries: []))
	#expect(model.presentation == .none)
}

@MainActor
@Test("Login routes multiple diaries to the picker")
func loginShowsDiaryPickerForMultipleDiaries() async {
	let diaries = [diary(id: "diary-1", title: "Personal"), diary(id: "diary-2", title: "Work")]
	let model = ThingsDiaryAppModel(client: StubAppClient(result: .success(diaries)))
	model.login = "person@example.test"
	model.password = "password"
	model.secretKey = "TDKV1-000G-40R4-0M30-E209-185G-R38E-1W6"

	await model.submit()

	#expect(model.screen == .diaries(diaries))
	#expect(model.presentation == .diaryPicker)
}

@MainActor
@Test("Cancelling the diary picker preserves the open workspace and its data")
func cancelDiaryPickerPreservesWorkspace() async {
	let selectedDiary = diary(id: "diary-1", title: "Personal")
	let topic = topic(id: "topic-1", diaryID: selectedDiary.id, title: "Work")
	let template = template(id: "template-1", diaryID: selectedDiary.id, content: "# Template")
	let entry = entry(id: "entry-1", diaryID: selectedDiary.id, content: "Note")
	let model = ThingsDiaryAppModel(
		client: StubAppClient(
			result: .success([selectedDiary]),
			entriesResult: .success([entry]),
			topicsResult: .success([topic]),
			templatesResult: .success([template])
		))
	await model.selectDiary(selectedDiary)

	model.showDiaryPicker()
	#expect(model.presentation == .diaryPicker)
	model.cancelDiaryPicker()

	#expect(model.presentation == .none)
	#expect(model.screen == .entries(diary: selectedDiary, entries: [entry]))
	#expect(model.topics == [topic])
	#expect(model.templates == [template])
}

@MainActor
@Test("Diary settings request selects the diary and can be consumed once")
func diarySettingsRequestSelectsDiary() async {
	let selectedDiary = diary(id: "diary-1", title: "Personal")
	let requestedDiary = diary(id: "diary-2", title: "Work")
	let model = ThingsDiaryAppModel(
		client: StubAppClient(result: .success([selectedDiary, requestedDiary]))
	)
	await model.selectDiary(selectedDiary)

	await model.requestDiarySettings(for: requestedDiary)

	guard case .entries(let openDiary, _) = model.screen else {
		Issue.record("Expected the requested diary workspace")
		return
	}
	#expect(openDiary == requestedDiary)
	#expect(model.diarySettingsRequestID == requestedDiary.id)
	#expect(model.consumeDiarySettingsRequest(for: requestedDiary.id))
	#expect(!model.consumeDiarySettingsRequest(for: requestedDiary.id))
}

@MainActor
@Test("Cancelling diary creation opened from the picker returns to the picker")
func cancelDiaryCreationReturnsToPicker() {
	let model = ThingsDiaryAppModel(client: StubAppClient(result: .success([])))

	model.showDiaryPicker()
	model.showDiaryCreation()
	model.cancelDiaryCreation()

	#expect(model.presentation == .diaryPicker)
}

@MainActor
@Test("Creating the first diary closes creation and shows the diary")
func createsFirstDiary() async {
	let created = diary(id: "diary-new", title: "Personal")
	let client = StubAppClient(
		result: .success([]),
		createDiaryResult: .success(created)
	)
	let model = ThingsDiaryAppModel(client: client)
	model.login = "person@example.test"
	model.password = "password"
	model.secretKey = "TDKV1-000G-40R4-0M30-E209-185G-R38E-1W6"
	await model.submit()

	await model.createDiary(title: "Personal", description: "Daily notes")

	#expect(model.screen == .entries(diary: created, entries: []))
	#expect(!model.isCreatingDiary)
	#expect(model.presentation == .none)
	#expect(
		await client.receivedCreateDiaryParams
			== ThingsDiaryCreateParams(
				title: "Personal",
				description: "Daily notes"
			))
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
@Test("Selecting a diary loads its topics and templates")
func selectingDiaryLoadsTopicsAndTemplates() async {
	let selectedDiary = diary(id: "diary-1", title: "Personal")
	let topic = ThingsDiaryTopic(
		id: "topic-1",
		diaryID: selectedDiary.id,
		title: "Work",
		description: "Work notes",
		color: "blue",
		createdAt: Date(timeIntervalSince1970: 1),
		updatedAt: Date(timeIntervalSince1970: 2),
		version: 3
	)
	let template = ThingsDiaryTemplate(
		id: "template-1",
		diaryID: selectedDiary.id,
		content: "# Heading",
		createdAt: Date(timeIntervalSince1970: 1),
		updatedAt: Date(timeIntervalSince1970: 2),
		version: 3
	)
	let client = StubAppClient(
		result: .success([selectedDiary]),
		topicsResult: .success([topic]),
		templatesResult: .success([template])
	)
	let model = ThingsDiaryAppModel(client: client)

	await model.selectDiary(selectedDiary)

	#expect(model.topics == [topic])
	#expect(model.templates == [template])
	#expect(await client.receivedTopicsDiaryID == selectedDiary.id)
	#expect(await client.receivedTemplatesDiaryID == selectedDiary.id)
}

@MainActor
@Test("Creating and updating a topic sends its parameters to the client")
func createsAndUpdatesTopic() async {
	let selectedDiary = diary(id: "diary-1", title: "Personal")
	let created = topic(id: "topic-1", diaryID: selectedDiary.id, title: "Work")
	let updated = topic(id: "topic-1", diaryID: selectedDiary.id, title: "Projects")
	let client = StubAppClient(
		result: .success([selectedDiary]),
		createTopicResult: .success(created),
		updateTopicResult: .success(updated)
	)
	let model = ThingsDiaryAppModel(client: client)
	await model.selectDiary(selectedDiary)

	await model.createTopic(
		title: "Work",
		description: "Work notes",
		color: "blue",
		entryPreviewable: false,
		defaultTemplateID: "template-1"
	)
	await model.updateTopic(
		created,
		title: "Projects",
		description: "Project notes",
		color: "green",
		entryPreviewable: false,
		defaultTemplateID: "template-2"
	)

	#expect(model.topics == [updated])
	#expect(
		await client.receivedCreateTopicParams
			== ThingsDiaryTopicParams(
				title: "Work",
				description: "Work notes",
				color: "blue",
				entryPreviewable: false,
				defaultTemplateID: "template-1"
			))
	#expect(
		await client.receivedUpdateTopicParams
			== ThingsDiaryTopicParams(
				title: "Projects",
				description: "Project notes",
				color: "green",
				entryPreviewable: false,
				defaultTemplateID: "template-2"
			))
}

@MainActor
@Test("Creating and updating a template sends its content to the client")
func createsAndUpdatesTemplate() async {
	let selectedDiary = diary(id: "diary-1", title: "Personal")
	let created = template(id: "template-1", diaryID: selectedDiary.id, content: "# New")
	let updated = template(id: "template-1", diaryID: selectedDiary.id, content: "# Updated")
	let client = StubAppClient(
		result: .success([selectedDiary]),
		createTemplateResult: .success(created),
		updateTemplateResult: .success(updated)
	)
	let model = ThingsDiaryAppModel(client: client)
	await model.selectDiary(selectedDiary)

	await model.createTemplate(content: "# New")
	await model.updateTemplate(created, content: "# Updated")

	#expect(model.templates == [updated])
	#expect(await client.receivedCreateTemplateParams == ThingsDiaryTemplateParams(content: "# New"))
	#expect(await client.receivedUpdateTemplateParams == ThingsDiaryTemplateParams(content: "# Updated"))
}

@MainActor
@Test("Moving a note to a topic updates its topic assignment")
func movesEntryToTopic() async {
	let selectedDiary = diary(id: "diary-1", title: "Personal")
	let original = entry(id: "entry-1", diaryID: selectedDiary.id, content: "Categorize me")
	let updated = ThingsDiaryEntry(
		id: original.id,
		diaryID: original.diaryID,
		content: original.content,
		topicID: "topic-1",
		createdAt: original.createdAt,
		updatedAt: original.updatedAt,
		version: original.version + 1
	)
	let client = StubAppClient(
		result: .success([selectedDiary]),
		entriesResult: .success([original]),
		updateEntryResult: .success(updated)
	)
	let model = ThingsDiaryAppModel(client: client)
	await model.selectDiary(selectedDiary)

	await model.moveEntry(original, toTopicID: "topic-1")

	#expect(model.screen == .entries(diary: selectedDiary, entries: [updated]))
	#expect(
		await client.receivedUpdateParams
			== ThingsDiaryEntryParams(
				content: original.content,
				topicID: "topic-1"
			))
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

	guard case .entries(let diary, let entries) = model.screen else {
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
@Test("Bookmarking a note updates only its bookmark flag")
func bookmarksEntry() async {
	let diary = diary(id: "diary-1", title: "Personal")
	let original = entry(id: "entry-1", diaryID: diary.id, content: "Keep me")
	let updated = ThingsDiaryEntry(
		id: original.id,
		diaryID: original.diaryID,
		content: original.content,
		bookmarked: true,
		createdAt: original.createdAt,
		updatedAt: original.updatedAt,
		version: original.version + 1
	)
	let client = StubAppClient(
		result: .success([diary]),
		entriesResult: .success([original]),
		updateEntryResult: .success(updated)
	)
	let model = ThingsDiaryAppModel(client: client)
	await model.selectDiary(diary)

	await model.toggleBookmark(original)

	#expect(model.screen == .entries(diary: diary, entries: [updated]))
	#expect(
		await client.receivedUpdateParams
			== ThingsDiaryEntryParams(
				content: original.content,
				bookmarked: true
			))
}

@MainActor
@Test("Archiving a note updates only its archive flag")
func archivesEntry() async {
	let diary = diary(id: "diary-1", title: "Personal")
	let original = entry(id: "entry-1", diaryID: diary.id, content: "Archive me")
	let updated = ThingsDiaryEntry(
		id: original.id,
		diaryID: original.diaryID,
		content: original.content,
		archived: true,
		createdAt: original.createdAt,
		updatedAt: original.updatedAt,
		version: original.version + 1
	)
	let client = StubAppClient(
		result: .success([diary]),
		entriesResult: .success([original]),
		updateEntryResult: .success(updated)
	)
	let model = ThingsDiaryAppModel(client: client)
	await model.selectDiary(diary)

	await model.toggleArchive(original)

	#expect(model.screen == .entries(diary: diary, entries: [updated]))
	#expect(
		await client.receivedUpdateParams
			== ThingsDiaryEntryParams(
				content: original.content,
				archived: true
			))
}

@MainActor
@Test("Duplicating a note creates a new entry with the same content and metadata")
func duplicatesEntry() async {
	let diary = diary(id: "diary-1", title: "Personal")
	let original = ThingsDiaryEntry(
		id: "entry-1",
		diaryID: diary.id,
		content: "Copy me",
		topicID: "topic-1",
		archived: true,
		bookmarked: true,
		previewHidden: true,
		createdAt: Date(timeIntervalSince1970: 3),
		updatedAt: Date(timeIntervalSince1970: 4),
		version: 5
	)
	let duplicate = ThingsDiaryEntry(
		id: "entry-copy",
		diaryID: diary.id,
		content: original.content,
		topicID: original.topicID,
		archived: original.archived,
		bookmarked: original.bookmarked,
		previewHidden: original.previewHidden,
		createdAt: Date(timeIntervalSince1970: 6),
		updatedAt: Date(timeIntervalSince1970: 6),
		version: 6
	)
	let client = StubAppClient(
		result: .success([diary]),
		entriesResult: .success([original]),
		createEntryResult: .success(duplicate)
	)
	let model = ThingsDiaryAppModel(client: client)
	await model.selectDiary(diary)

	await model.duplicateEntry(original)

	#expect(model.screen == .entries(diary: diary, entries: [original, duplicate]))
	#expect(
		await client.receivedCreateParams
			== ThingsDiaryEntryParams(
				content: original.content,
				topicID: original.topicID,
				archived: true,
				bookmarked: true,
				previewHidden: true
			))
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

	guard case .entries(let diary, let entries) = model.screen else {
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
@Test("Moving a note to trash offline queues a soft delete")
func movesEntryToTrashOffline() async throws {
	let fileURL = FileManager.default.temporaryDirectory
		.appending(path: "thingsdiary-app-delete-\(UUID().uuidString).json")
	defer { try? FileManager.default.removeItem(at: fileURL) }
	let selectedDiary = diary(id: "diary-1", title: "Personal")
	let original = entry(id: "entry-1", diaryID: selectedDiary.id, content: "Trash me")
	let store = try DiaryStore(fileURL: fileURL)
	let client = StubAppClient(
		result: .success([selectedDiary]),
		entriesResult: .success([original])
	)
	let model = ThingsDiaryAppModel(client: client, store: store)
	await model.selectDiary(selectedDiary)

	await model.moveToTrash(original)

	guard case .entries(_, let entries) = model.screen else {
		Issue.record("Expected entries after the local delete")
		return
	}
	#expect(entries.first?.deletedAt != nil)
	let pendingWrites = await store.pendingEntryWrites()
	#expect(pendingWrites.first?.operation == .delete)
	#expect(pendingWrites.first?.entry.id == original.id)
}

@MainActor
@Test("Restoring a note offline replaces its pending delete")
func restoresEntryOffline() async throws {
	let fileURL = FileManager.default.temporaryDirectory
		.appending(path: "thingsdiary-app-restore-\(UUID().uuidString).json")
	defer { try? FileManager.default.removeItem(at: fileURL) }
	let selectedDiary = diary(id: "diary-1", title: "Personal")
	let deleted = ThingsDiaryEntry(
		id: "entry-1",
		diaryID: selectedDiary.id,
		content: "Restore me",
		createdAt: Date(timeIntervalSince1970: 3),
		updatedAt: Date(timeIntervalSince1970: 4),
		deletedAt: Date(timeIntervalSince1970: 4),
		version: 4_000
	)
	let store = try DiaryStore(fileURL: fileURL)
	let client = StubAppClient(
		result: .success([selectedDiary]),
		entriesResult: .success([deleted])
	)
	let model = ThingsDiaryAppModel(client: client, store: store)
	await model.selectDiary(selectedDiary)
	try await store.savePendingEntry(PendingEntryWrite(operation: .delete, entry: deleted))

	await model.restoreEntry(deleted)

	guard case .entries(_, let entries) = model.screen else {
		Issue.record("Expected entries after the local restore")
		return
	}
	#expect(entries.first?.deletedAt == nil)
	let pendingWrites = await store.pendingEntryWrites()
	#expect(pendingWrites.count == 1)
	#expect(pendingWrites.first?.operation == .restore)
}

@MainActor
@Test("A stale entry response cannot replace the newly selected diary")
func latestDiarySelectionWins() async throws {
	let diaryA = diary(id: "diary-a", title: "A")
	let diaryB = diary(id: "diary-b", title: "B")
	let entryA = entry(id: "entry-a", diaryID: diaryA.id, content: "From A")
	let entryB = entry(id: "entry-b", diaryID: diaryB.id, content: "From B")
	let model = ThingsDiaryAppModel(
		client: DelayedEntriesAppClient(
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

private func topic(id: String, diaryID: String, title: String) -> ThingsDiaryTopic {
	ThingsDiaryTopic(
		id: id,
		diaryID: diaryID,
		title: title,
		description: "",
		color: "blue",
		createdAt: Date(timeIntervalSince1970: 1),
		updatedAt: Date(timeIntervalSince1970: 2),
		version: 3
	)
}

private func template(id: String, diaryID: String, content: String) -> ThingsDiaryTemplate {
	ThingsDiaryTemplate(
		id: id,
		diaryID: diaryID,
		content: content,
		createdAt: Date(timeIntervalSince1970: 1),
		updatedAt: Date(timeIntervalSince1970: 2),
		version: 3
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
	let createDiaryResult: Result<ThingsDiaryDiary, Error>?
	let registrationResult: Result<ThingsDiaryPublicKeys, Error>
	let entriesResult: Result<[ThingsDiaryEntry], Error>
	let createEntryResult: Result<ThingsDiaryEntry, Error>?
	let updateEntryResult: Result<ThingsDiaryEntry, Error>?
	let topicsResult: Result<[ThingsDiaryTopic], Error>
	let templatesResult: Result<[ThingsDiaryTemplate], Error>
	let createTopicResult: Result<ThingsDiaryTopic, Error>?
	let updateTopicResult: Result<ThingsDiaryTopic, Error>?
	let createTemplateResult: Result<ThingsDiaryTemplate, Error>?
	let updateTemplateResult: Result<ThingsDiaryTemplate, Error>?
	private(set) var receivedLogin: String?
	private(set) var receivedPassword: String?
	private(set) var receivedSecretKey: String?
	private(set) var receivedRegistrationSecretKey: String?
	private(set) var receivedCreateDiaryParams: ThingsDiaryCreateParams?
	private(set) var receivedEntriesDiaryID: String?
	private(set) var receivedUpdateParams: ThingsDiaryEntryParams?
	private(set) var receivedCreateParams: ThingsDiaryEntryParams?
	private(set) var receivedTopicsDiaryID: String?
	private(set) var receivedTemplatesDiaryID: String?
	private(set) var receivedCreateTopicParams: ThingsDiaryTopicParams?
	private(set) var receivedUpdateTopicParams: ThingsDiaryTopicParams?
	private(set) var receivedCreateTemplateParams: ThingsDiaryTemplateParams?
	private(set) var receivedUpdateTemplateParams: ThingsDiaryTemplateParams?

	init(
		result: Result<[ThingsDiaryDiary], Error>,
		createDiaryResult: Result<ThingsDiaryDiary, Error>? = nil,
		registrationResult: Result<ThingsDiaryPublicKeys, Error> = .success(
			ThingsDiaryPublicKeys(signing: "signing", encryption: "encryption")
		),
		entriesResult: Result<[ThingsDiaryEntry], Error> = .success([]),
		createEntryResult: Result<ThingsDiaryEntry, Error>? = nil,
		updateEntryResult: Result<ThingsDiaryEntry, Error>? = nil,
		topicsResult: Result<[ThingsDiaryTopic], Error> = .success([]),
		templatesResult: Result<[ThingsDiaryTemplate], Error> = .success([]),
		createTopicResult: Result<ThingsDiaryTopic, Error>? = nil,
		updateTopicResult: Result<ThingsDiaryTopic, Error>? = nil,
		createTemplateResult: Result<ThingsDiaryTemplate, Error>? = nil,
		updateTemplateResult: Result<ThingsDiaryTemplate, Error>? = nil
	) {
		self.result = result
		self.createDiaryResult = createDiaryResult
		self.registrationResult = registrationResult
		self.entriesResult = entriesResult
		self.createEntryResult = createEntryResult
		self.updateEntryResult = updateEntryResult
		self.topicsResult = topicsResult
		self.templatesResult = templatesResult
		self.createTopicResult = createTopicResult
		self.updateTopicResult = updateTopicResult
		self.createTemplateResult = createTemplateResult
		self.updateTemplateResult = updateTemplateResult
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
		if case .failure(let error) = result {
			throw error
		}
	}

	func diaries() async throws -> [ThingsDiaryDiary] {
		try result.get()
	}

	func createDiary(_ params: ThingsDiaryCreateParams) async throws -> ThingsDiaryDiary {
		receivedCreateDiaryParams = params
		guard let createDiaryResult else { throw TestFailure.rejected }
		return try createDiaryResult.get()
	}

	func entries(diaryID: String) async throws -> [ThingsDiaryEntry] {
		receivedEntriesDiaryID = diaryID
		return try entriesResult.get()
	}

	func topics(diaryID: String) async throws -> [ThingsDiaryTopic] {
		receivedTopicsDiaryID = diaryID
		return try topicsResult.get()
	}

	func templates(diaryID: String) async throws -> [ThingsDiaryTemplate] {
		receivedTemplatesDiaryID = diaryID
		return try templatesResult.get()
	}

	func createTopic(diaryID: String, params: ThingsDiaryTopicParams) async throws -> ThingsDiaryTopic {
		receivedCreateTopicParams = params
		guard let createTopicResult else { throw TestFailure.rejected }
		return try createTopicResult.get()
	}

	func updateTopic(_ topic: ThingsDiaryTopic, params: ThingsDiaryTopicParams) async throws -> ThingsDiaryTopic {
		receivedUpdateTopicParams = params
		guard let updateTopicResult else { throw TestFailure.rejected }
		return try updateTopicResult.get()
	}

	func createTemplate(diaryID: String, params: ThingsDiaryTemplateParams) async throws -> ThingsDiaryTemplate {
		receivedCreateTemplateParams = params
		guard let createTemplateResult else { throw TestFailure.rejected }
		return try createTemplateResult.get()
	}

	func updateTemplate(_ template: ThingsDiaryTemplate, params: ThingsDiaryTemplateParams) async throws
		-> ThingsDiaryTemplate
	{
		receivedUpdateTemplateParams = params
		guard let updateTemplateResult else { throw TestFailure.rejected }
		return try updateTemplateResult.get()
	}

	func createEntry(
		diaryID: String,
		params: ThingsDiaryEntryParams
	) async throws -> ThingsDiaryEntry {
		receivedCreateParams = params
		guard let createEntryResult else {
			throw TestFailure.rejected
		}
		return try createEntryResult.get()
	}

	func updateEntry(
		_ entry: ThingsDiaryEntry,
		params: ThingsDiaryEntryParams
	) async throws -> ThingsDiaryEntry {
		receivedUpdateParams = params
		guard let updateEntryResult else {
			throw TestFailure.rejected
		}
		return try updateEntryResult.get()
	}
}
