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
@Test("Successful login persists the reusable authentication state")
func loginPersistsAuthentication() async {
	let sessionStore = TestAuthSessionStore()
	let model = ThingsDiaryAppModel(
		client: StubAppClient(result: .success([])),
		sessionStore: sessionStore
	)
	model.login = "person@example.test"
	model.password = "password"
	model.secretKey = "TDKV1-000G-40R4-0M30-E209-185G-R38E-1W6"

	await model.submit()

	#expect(sessionStore.session?.login == "person@example.test")
	#expect(sessionStore.session?.authentication.token == "session-token")
	#expect(sessionStore.session?.authentication.credentials.encryptionPrivateKey == Data([1]))
	#expect(sessionStore.session?.authentication.credentials.signingPrivateKey == Data([3]))
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
@Test("Diary edit request selects the diary and can be consumed once")
func diaryEditRequestSelectsDiary() async {
	let selectedDiary = diary(id: "diary-1", title: "Personal")
	let requestedDiary = diary(id: "diary-2", title: "Work")
	let model = ThingsDiaryAppModel(
		client: StubAppClient(result: .success([selectedDiary, requestedDiary]))
	)
	await model.selectDiary(selectedDiary)

	await model.requestDiaryEdit(for: requestedDiary)

	guard case .entries(let openDiary, _) = model.screen else {
		Issue.record("Expected the requested diary workspace")
		return
	}
	#expect(openDiary == requestedDiary)
	#expect(model.diaryEditRequestID == requestedDiary.id)
	#expect(model.consumeDiaryEditRequest(for: requestedDiary.id))
	#expect(!model.consumeDiaryEditRequest(for: requestedDiary.id))
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
@Test("Updating a diary replaces it in the workspace and diary list")
func updatesDiary() async {
	let selectedDiary = diary(id: "diary-1", title: "Personal")
	let entry = entry(id: "entry-1", diaryID: selectedDiary.id, content: "Note")
	let updatedDiary = ThingsDiaryDiary(
		id: selectedDiary.id,
		title: "Renamed",
		description: "Daily notes",
		createdAt: selectedDiary.createdAt,
		updatedAt: Date(timeIntervalSince1970: 4),
		version: 5
	)
	let client = StubAppClient(
		result: .success([selectedDiary]),
		updateDiaryResult: .success(updatedDiary),
		entriesResult: .success([entry])
	)
	let model = ThingsDiaryAppModel(client: client)
	model.login = "person@example.test"
	model.password = "password"
	model.secretKey = "TDKV1-000G-40R4-0M30-E209-185G-R38E-1W6"
	await model.submit()

	let saved = await model.updateDiary(
		selectedDiary,
		title: "  Renamed  ",
		description: "  Daily notes  "
	)

	#expect(saved)
	#expect(model.screen == .entries(diary: updatedDiary, entries: [entry]))
	#expect(model.availableDiaries == [updatedDiary])
	#expect(
		await client.receivedUpdateDiaryParams
			== ThingsDiaryDiaryParams(
				title: "Renamed",
				description: "Daily notes"
			))
}

@MainActor
@Test("Updating a topic can remove its default template")
func removesTopicDefaultTemplate() async {
	let selectedDiary = diary(id: "diary-1", title: "Personal")
	let now = Date(timeIntervalSince1970: 1_700_000_000)
	let original = ThingsDiaryTopic(
		id: "topic-1",
		diaryID: selectedDiary.id,
		title: "Work",
		description: "",
		color: "blue",
		defaultTemplateID: "template-1",
		createdAt: now,
		updatedAt: now,
		version: 1
	)
	let updated = ThingsDiaryTopic(
		id: original.id,
		diaryID: original.diaryID,
		title: original.title,
		description: original.description,
		color: original.color,
		defaultTemplateID: nil,
		createdAt: original.createdAt,
		updatedAt: original.updatedAt,
		version: 2
	)
	let client = StubAppClient(
		result: .success([selectedDiary]),
		topicsResult: .success([original]),
		updateTopicResult: .success(updated)
	)
	let model = ThingsDiaryAppModel(client: client)
	await model.selectDiary(selectedDiary)

	await model.updateTopic(
		original,
		title: original.title,
		description: original.description,
		color: original.color,
		defaultTemplateID: .some(nil)
	)

	#expect(model.topics == [updated])
	#expect(await client.receivedUpdateTopicParams?.defaultTemplateID == nil)
}

@MainActor
@Test("Deleting a topic can delete its notes")
func deletingTopicDeletesItsEntries() async {
	let selectedDiary = diary(id: "diary-1", title: "Personal")
	let work = topic(id: "topic-1", diaryID: selectedDiary.id, title: "Work")
	let linkedEntry = entry(
		id: "entry-1",
		diaryID: selectedDiary.id,
		content: "Linked note",
		topicID: work.id
	)
	let unrelatedEntry = entry(id: "entry-2", diaryID: selectedDiary.id, content: "Other note")
	let client = StubAppClient(
		result: .success([selectedDiary]),
		entriesResult: .success([linkedEntry, unrelatedEntry]),
		topicsResult: .success([work])
	)
	let model = ThingsDiaryAppModel(client: client)
	await model.selectDiary(selectedDiary)

	let deleted = await model.deleteTopic(work, deleteEntries: true)

	#expect(deleted)
	#expect(model.topics.isEmpty)
	guard case .entries(_, let entries) = model.screen else {
		Issue.record("Expected the diary workspace")
		return
	}
	#expect(entries.first(where: { $0.id == linkedEntry.id })?.deletedAt != nil)
	#expect(entries.first(where: { $0.id == unrelatedEntry.id }) == unrelatedEntry)
	#expect(await client.receivedDeletedTopicID == work.id)
	#expect(await client.receivedDeleteTopicEntries == true)
	#expect(await client.receivedDeleteTopicSoft == true)
}

@MainActor
@Test("Deleting a topic can keep its notes without a topic")
func deletingTopicKeepsEntriesWithoutTopic() async {
	let selectedDiary = diary(id: "diary-1", title: "Personal")
	let work = topic(id: "topic-1", diaryID: selectedDiary.id, title: "Work")
	let linkedEntry = entry(
		id: "entry-1",
		diaryID: selectedDiary.id,
		content: "Linked note",
		topicID: work.id
	)
	let client = StubAppClient(
		result: .success([selectedDiary]),
		entriesResult: .success([linkedEntry]),
		topicsResult: .success([work])
	)
	let model = ThingsDiaryAppModel(client: client)
	await model.selectDiary(selectedDiary)

	let deleted = await model.deleteTopic(work, deleteEntries: false)

	#expect(deleted)
	#expect(model.topics.isEmpty)
	guard case .entries(_, let entries) = model.screen else {
		Issue.record("Expected the diary workspace")
		return
	}
	let keptEntry = entries.first(where: { $0.id == linkedEntry.id })
	#expect(keptEntry?.topicID == nil)
	#expect(keptEntry?.deletedAt == nil)
	#expect(await client.receivedDeletedTopicID == work.id)
	#expect(await client.receivedDeleteTopicEntries == false)
	#expect(await client.receivedDeleteTopicSoft == true)
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
@Test("A list draft is visible immediately and can be discarded")
func createsVisibleEntryDraft() async {
	let diary = diary(id: "diary-1", title: "Personal")
	let model = ThingsDiaryAppModel(
		client: StubAppClient(result: .success([diary]))
	)
	await model.selectDiary(diary)

	let draft = model.beginEntryDraft(appearsInList: true)

	#expect(draft != nil)
	#expect(model.entryDraftIDs == Set([draft?.id].compactMap { $0 }))
	#expect(model.entryDraftIDsHiddenFromList.isEmpty)
	#expect(model.screen == .entries(diary: diary, entries: [draft].compactMap { $0 }))

	model.discardEntryDraft(draft?.id ?? "")

	#expect(model.entryDraftIDs.isEmpty)
	#expect(model.screen == .entries(diary: diary, entries: []))
}

@MainActor
@Test("A draft created in a topic keeps its topic assignment")
func createsEntryDraftInTopic() async {
	let diary = diary(id: "diary-1", title: "Personal")
	let model = ThingsDiaryAppModel(
		client: StubAppClient(result: .success([diary]))
	)
	await model.selectDiary(diary)

	let draft = model.beginEntryDraft(appearsInList: true, topicID: "topic-1")

	#expect(draft?.topicID == "topic-1")
	#expect(model.screen == .entries(diary: diary, entries: [draft].compactMap { $0 }))
}

@MainActor
@Test("A topic draft starts with its default template")
func createsEntryDraftFromTopicDefaultTemplate() async {
	let diary = diary(id: "diary-1", title: "Personal")
	let now = Date(timeIntervalSince1970: 1_700_000_000)
	let topic = ThingsDiaryTopic(
		id: "topic-1",
		diaryID: diary.id,
		title: "Work",
		description: "",
		color: "#93C5FD",
		defaultTemplateID: "template-1",
		createdAt: now,
		updatedAt: now,
		version: 1
	)
	let defaultTemplate = template(
		id: "template-1",
		diaryID: diary.id,
		content: "Weekly review\nWins:\nNext:"
	)
	let model = ThingsDiaryAppModel(
		client: StubAppClient(
			result: .success([diary]),
			topicsResult: .success([topic]),
			templatesResult: .success([defaultTemplate])
		)
	)
	await model.selectDiary(diary)

	let draft = model.beginEntryDraft(appearsInList: true, topicID: topic.id)

	#expect(draft?.content == defaultTemplate.content)
	#expect(draft?.topicID == topic.id)
}

@MainActor
@Test("Editing a tab draft promotes it into the diary")
func promotesHiddenTabDraftOnFirstEdit() async {
	let diary = diary(id: "diary-1", title: "Personal")
	let client = StubAppClient(
		result: .success([diary]),
		createEntryResult: .failure(TestFailure.rejected)
	)
	let model = ThingsDiaryAppModel(client: client)
	await model.selectDiary(diary)
	let draft = model.beginEntryDraft(appearsInList: false)
	let draftID = try! #require(draft?.id)

	#expect(model.entryDraftIDsHiddenFromList == Set([draftID]))

	model.promoteEntryDraft(draftID, content: "Started writing")

	#expect(model.entryDraftIDs.isEmpty)
	#expect(model.entryDraftIDsHiddenFromList.isEmpty)
	#expect(model.entryPendingCreationIDs == [draftID])
	guard case .entries(_, let entries) = model.screen else {
		Issue.record("Expected the selected diary")
		return
	}
	#expect(entries.first?.id == draftID)
	#expect(entries.first?.content == "Started writing")
}

@MainActor
@Test("Bookmarking a draft promotes and persists it")
func bookmarkingDraftPromotesAndPersistsIt() async throws {
	let fileURL = FileManager.default.temporaryDirectory
		.appending(path: "thingsdiary-app-bookmark-draft-\(UUID().uuidString).json")
	defer { try? FileManager.default.removeItem(at: fileURL) }
	let selectedDiary = diary(id: "diary-1", title: "Personal")
	let store = try DiaryStore(fileURL: fileURL)
	let client = StubAppClient(
		result: .success([selectedDiary]),
		stableCreateEntryResult: .failure(TestFailure.rejected)
	)
	let model = ThingsDiaryAppModel(client: client, store: store)
	await model.selectDiary(selectedDiary)
	let draft = try #require(model.beginEntryDraft(appearsInList: false))

	await model.toggleBookmark(draft)

	#expect(model.entryDraftIDs.isEmpty)
	#expect(model.entryDraftIDsHiddenFromList.isEmpty)
	#expect(model.entryPendingCreationIDs == [draft.id])
	guard case .entries(_, let entries) = model.screen else {
		Issue.record("Expected the selected diary")
		return
	}
	#expect(entries.first(where: { $0.id == draft.id })?.bookmarked == true)

	for _ in 0..<100 {
		if await store.pendingEntryWrites().contains(where: { $0.id == draft.id }) {
			break
		}
		try await Task.sleep(for: .milliseconds(1))
	}
	let storedEntry = await store.entries(diaryID: selectedDiary.id).first {
		$0.id == draft.id
	}
	#expect(storedEntry?.bookmarked == true)
	#expect(
		await store.pendingEntryWrites().contains {
			$0.id == draft.id && $0.operation == .create
		}
	)
}

@MainActor
@Test("Moving a draft to a topic promotes and persists it")
func movingDraftToTopicPromotesAndPersistsIt() async throws {
	let fileURL = FileManager.default.temporaryDirectory
		.appending(path: "thingsdiary-app-move-draft-\(UUID().uuidString).json")
	defer { try? FileManager.default.removeItem(at: fileURL) }
	let selectedDiary = diary(id: "diary-1", title: "Personal")
	let store = try DiaryStore(fileURL: fileURL)
	let client = StubAppClient(
		result: .success([selectedDiary]),
		stableCreateEntryResult: .failure(TestFailure.rejected)
	)
	let model = ThingsDiaryAppModel(client: client, store: store)
	await model.selectDiary(selectedDiary)
	let draft = try #require(model.beginEntryDraft(appearsInList: false))

	await model.moveEntry(draft, toTopicID: "topic-1")

	#expect(model.entryDraftIDs.isEmpty)
	#expect(model.entryDraftIDsHiddenFromList.isEmpty)
	#expect(model.entryPendingCreationIDs == [draft.id])
	guard case .entries(_, let entries) = model.screen else {
		Issue.record("Expected the selected diary")
		return
	}
	#expect(entries.first(where: { $0.id == draft.id })?.topicID == "topic-1")

	for _ in 0..<100 {
		if await store.pendingEntryWrites().contains(where: { $0.id == draft.id }) {
			break
		}
		try await Task.sleep(for: .milliseconds(1))
	}
	let storedEntry = await store.entries(diaryID: selectedDiary.id).first {
		$0.id == draft.id
	}
	#expect(storedEntry?.topicID == "topic-1")
	#expect(
		await store.pendingEntryWrites().contains {
			$0.id == draft.id && $0.operation == .create
		}
	)
}

@MainActor
@Test("Destructive actions ignore ephemeral drafts")
func destructiveActionsIgnoreEphemeralDrafts() async throws {
	let fileURL = FileManager.default.temporaryDirectory
		.appending(path: "thingsdiary-app-ephemeral-actions-\(UUID().uuidString).json")
	defer { try? FileManager.default.removeItem(at: fileURL) }
	let selectedDiary = diary(id: "diary-1", title: "Personal")
	let store = try DiaryStore(fileURL: fileURL)
	let model = ThingsDiaryAppModel(
		client: StubAppClient(result: .success([selectedDiary])),
		store: store
	)
	await model.selectDiary(selectedDiary)
	let draft = try #require(model.beginEntryDraft(appearsInList: true))

	await model.toggleArchive(draft)
	await model.moveToTrash(draft)

	#expect(model.entryDraftIDs == [draft.id])
	#expect(model.screen == .entries(diary: selectedDiary, entries: [draft]))
	#expect(await store.pendingEntryWrites().isEmpty)
}

@MainActor
@Test("Editing a note while its create is in flight preserves the latest content")
func editingEntryDuringCreatePreservesLatestContent() async throws {
	let fileURL = FileManager.default.temporaryDirectory
		.appending(path: "thingsdiary-app-create-race-\(UUID().uuidString).json")
	defer { try? FileManager.default.removeItem(at: fileURL) }
	let selectedDiary = diary(id: "diary-1", title: "Personal")
	let store = try DiaryStore(fileURL: fileURL)
	let firstServerEntry = entry(
		id: "draft-id",
		diaryID: selectedDiary.id,
		content: "First"
	)
	let latestServerEntry = entry(
		id: "draft-id",
		diaryID: selectedDiary.id,
		content: "Latest"
	)
	let client = StubAppClient(
		result: .success([selectedDiary]),
		stableCreateEntryResult: .success(firstServerEntry),
		stableCreateEntryDelay: .milliseconds(100),
		updateEntryResult: .success(latestServerEntry)
	)
	let model = ThingsDiaryAppModel(client: client, store: store)
	await model.selectDiary(selectedDiary)
	let draft = try #require(model.beginEntryDraft(appearsInList: false))

	model.promoteEntryDraft(draft.id, content: "First")
	for _ in 0..<100 {
		if await client.receivedStableCreateParams != nil { break }
		try await Task.sleep(for: .milliseconds(1))
	}
	#expect(await client.receivedStableCreateParams?.content == "First")
	guard case .entries(_, let entries) = model.screen,
		let promotedEntry = entries.first(where: { $0.id == draft.id })
	else {
		Issue.record("Expected the promoted entry")
		return
	}

	await model.updateEntry(promotedEntry, content: "Latest")

	#expect(await client.receivedUpdateParams?.content == "Latest")
	#expect(await store.pendingEntryWrites().isEmpty)
	#expect(await store.entries(diaryID: selectedDiary.id).first?.content == "Latest")
	#expect(model.entryPendingCreationIDs.isEmpty)
	guard case .entries(_, let updatedEntries) = model.screen else {
		Issue.record("Expected the selected diary")
		return
	}
	#expect(updatedEntries.first(where: { $0.id == draft.id })?.content == "Latest")
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

	let didSave = await model.updateEntry(original, content: "After")

	#expect(didSave)
	#expect(model.screen == .entries(diary: diary, entries: [updated]))
}

@MainActor
@Test("A failed remote note update reports that it was not saved")
func failedEntryUpdateReportsFailure() async {
	let diary = diary(id: "diary-1", title: "Personal")
	let original = entry(id: "entry-1", diaryID: diary.id, content: "Before")
	let client = StubAppClient(
		result: .success([diary]),
		entriesResult: .success([original]),
		updateEntryResult: .failure(TestFailure.rejected)
	)
	let model = ThingsDiaryAppModel(client: client)
	await model.selectDiary(diary)

	let didSave = await model.updateEntry(original, content: "After")

	#expect(!didSave)
	#expect(model.screen == .entries(diary: diary, entries: [original]))
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

	let didSave = await model.updateEntry(original, content: "After")

	#expect(didSave)
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
@Test("Saving one note keeps a draft opened during synchronization")
func savingEntryPreservesDraftOpenedDuringSync() async throws {
	let fileURL = FileManager.default.temporaryDirectory
		.appending(path: "thingsdiary-app-drafts-\(UUID().uuidString).json")
	defer { try? FileManager.default.removeItem(at: fileURL) }
	let selectedDiary = diary(id: "diary-1", title: "Personal")
	let original = entry(id: "entry-1", diaryID: selectedDiary.id, content: "Before")
	let store = try DiaryStore(fileURL: fileURL)
	let client = StubAppClient(
		result: .success([selectedDiary]),
		entriesResult: .success([original]),
		updateEntryResult: .failure(TestFailure.rejected),
		updateEntryDelay: .milliseconds(100)
	)
	let model = ThingsDiaryAppModel(client: client, store: store)
	await model.selectDiary(selectedDiary)

	let saveTask = Task {
		await model.updateEntry(original, content: "After")
	}
	for _ in 0..<100 {
		if await client.receivedUpdateParams != nil { break }
		try await Task.sleep(for: .milliseconds(1))
	}
	#expect(await client.receivedUpdateParams != nil)
	let draft = try #require(model.beginEntryDraft(appearsInList: false))
	await saveTask.value

	guard case .entries(_, let entries) = model.screen else {
		Issue.record("Expected the selected diary")
		return
	}
	#expect(Set(entries.map(\.id)) == [original.id, draft.id])
	#expect(model.entryDraftIDs == [draft.id])
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

private func entry(
	id: String,
	diaryID: String,
	content: String,
	topicID: String? = nil
) -> ThingsDiaryEntry {
	ThingsDiaryEntry(
		id: id,
		diaryID: diaryID,
		content: content,
		topicID: topicID,
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

	func login(
		login: String,
		password: String,
		secretKey: String
	) async throws -> ThingsDiaryAuthState {
		testAuthentication()
	}

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
	let updateDiaryResult: Result<ThingsDiaryDiary, Error>?
	let registrationResult: Result<ThingsDiaryPublicKeys, Error>
	let entriesResult: Result<[ThingsDiaryEntry], Error>
	let createEntryResult: Result<ThingsDiaryEntry, Error>?
	let stableCreateEntryResult: Result<ThingsDiaryEntry, Error>?
	let stableCreateEntryDelay: Duration?
	let updateEntryResult: Result<ThingsDiaryEntry, Error>?
	let updateEntryDelay: Duration?
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
	private(set) var receivedUpdateDiaryParams: ThingsDiaryDiaryParams?
	private(set) var receivedEntriesDiaryID: String?
	private(set) var receivedUpdateParams: ThingsDiaryEntryParams?
	private(set) var receivedCreateParams: ThingsDiaryEntryParams?
	private(set) var receivedStableCreateParams: ThingsDiaryEntryParams?
	private(set) var receivedTopicsDiaryID: String?
	private(set) var receivedTemplatesDiaryID: String?
	private(set) var receivedCreateTopicParams: ThingsDiaryTopicParams?
	private(set) var receivedUpdateTopicParams: ThingsDiaryTopicParams?
	private(set) var receivedDeletedTopicID: String?
	private(set) var receivedDeleteTopicEntries: Bool?
	private(set) var receivedDeleteTopicSoft: Bool?
	private(set) var receivedCreateTemplateParams: ThingsDiaryTemplateParams?
	private(set) var receivedUpdateTemplateParams: ThingsDiaryTemplateParams?

	init(
		result: Result<[ThingsDiaryDiary], Error>,
		createDiaryResult: Result<ThingsDiaryDiary, Error>? = nil,
		updateDiaryResult: Result<ThingsDiaryDiary, Error>? = nil,
		registrationResult: Result<ThingsDiaryPublicKeys, Error> = .success(
			ThingsDiaryPublicKeys(signing: "signing", encryption: "encryption")
		),
		entriesResult: Result<[ThingsDiaryEntry], Error> = .success([]),
		createEntryResult: Result<ThingsDiaryEntry, Error>? = nil,
		stableCreateEntryResult: Result<ThingsDiaryEntry, Error>? = nil,
		stableCreateEntryDelay: Duration? = nil,
		updateEntryResult: Result<ThingsDiaryEntry, Error>? = nil,
		updateEntryDelay: Duration? = nil,
		topicsResult: Result<[ThingsDiaryTopic], Error> = .success([]),
		templatesResult: Result<[ThingsDiaryTemplate], Error> = .success([]),
		createTopicResult: Result<ThingsDiaryTopic, Error>? = nil,
		updateTopicResult: Result<ThingsDiaryTopic, Error>? = nil,
		createTemplateResult: Result<ThingsDiaryTemplate, Error>? = nil,
		updateTemplateResult: Result<ThingsDiaryTemplate, Error>? = nil
	) {
		self.result = result
		self.createDiaryResult = createDiaryResult
		self.updateDiaryResult = updateDiaryResult
		self.registrationResult = registrationResult
		self.entriesResult = entriesResult
		self.createEntryResult = createEntryResult
		self.stableCreateEntryResult = stableCreateEntryResult
		self.stableCreateEntryDelay = stableCreateEntryDelay
		self.updateEntryResult = updateEntryResult
		self.updateEntryDelay = updateEntryDelay
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

	func login(
		login: String,
		password: String,
		secretKey: String
	) async throws -> ThingsDiaryAuthState {
		receivedLogin = login
		receivedPassword = password
		receivedSecretKey = secretKey
		if case .failure(let error) = result {
			throw error
		}
		return testAuthentication()
	}

	func diaries() async throws -> [ThingsDiaryDiary] {
		try result.get()
	}

	func createDiary(_ params: ThingsDiaryCreateParams) async throws -> ThingsDiaryDiary {
		receivedCreateDiaryParams = params
		guard let createDiaryResult else { throw TestFailure.rejected }
		return try createDiaryResult.get()
	}

	func updateDiary(
		_ diary: ThingsDiaryDiary,
		params: ThingsDiaryDiaryParams
	) async throws -> ThingsDiaryDiary {
		receivedUpdateDiaryParams = params
		guard let updateDiaryResult else { throw TestFailure.rejected }
		return try updateDiaryResult.get()
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

	func deleteTopic(
		diaryID: String,
		topicID: String,
		deleteEntries: Bool?,
		soft: Bool?
	) async throws {
		receivedDeletedTopicID = topicID
		receivedDeleteTopicEntries = deleteEntries
		receivedDeleteTopicSoft = soft
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

	func createEntry(
		diaryID: String,
		entryID: String,
		params: ThingsDiaryEntryParams
	) async throws -> ThingsDiaryEntry {
		receivedStableCreateParams = params
		if let stableCreateEntryDelay {
			try await Task.sleep(for: stableCreateEntryDelay)
		}
		guard let stableCreateEntryResult else {
			throw TestFailure.rejected
		}
		let entry = try stableCreateEntryResult.get()
		return ThingsDiaryEntry(
			id: entryID,
			diaryID: diaryID,
			content: entry.content,
			topicID: entry.topicID,
			archived: entry.archived,
			bookmarked: entry.bookmarked,
			previewHidden: entry.previewHidden,
			createdAt: entry.createdAt,
			updatedAt: entry.updatedAt,
			deletedAt: entry.deletedAt,
			version: entry.version
		)
	}

	func updateEntry(
		_ entry: ThingsDiaryEntry,
		params: ThingsDiaryEntryParams
	) async throws -> ThingsDiaryEntry {
		receivedUpdateParams = params
		if let updateEntryDelay {
			try await Task.sleep(for: updateEntryDelay)
		}
		guard let updateEntryResult else {
			throw TestFailure.rejected
		}
		return try updateEntryResult.get()
	}
}

private final class TestAuthSessionStore: AuthSessionStore, @unchecked Sendable {
	private(set) var session: SavedAuthSession?

	func load() throws -> SavedAuthSession? {
		session
	}

	func save(_ session: SavedAuthSession) throws {
		self.session = session
	}

	func clear() throws {
		session = nil
	}
}

private nonisolated func testAuthentication() -> ThingsDiaryAuthState {
	ThingsDiaryAuthState(
		token: "session-token",
		credentials: ThingsDiaryCredentials(
			encryptionPrivateKey: Data([1]),
			encryptionPublicKey: Data([2]),
			signingPrivateKey: Data([3]),
			signingPublicKey: Data([4])
		)
	)
}
