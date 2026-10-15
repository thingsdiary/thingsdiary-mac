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
	func createDiary(_ params: ThingsDiaryCreateParams) async throws -> ThingsDiaryDiary
	func entries(diaryID: String) async throws -> [ThingsDiaryEntry]
	func topics(diaryID: String) async throws -> [ThingsDiaryTopic]
	func templates(diaryID: String) async throws -> [ThingsDiaryTemplate]
	func createEntry(
		diaryID: String,
		params: ThingsDiaryEntryParams
	) async throws -> ThingsDiaryEntry
	func updateEntry(
		_ entry: ThingsDiaryEntry,
		params: ThingsDiaryEntryParams
	) async throws -> ThingsDiaryEntry
	func createTopic(
		diaryID: String,
		params: ThingsDiaryTopicParams
	) async throws -> ThingsDiaryTopic
	func updateTopic(
		_ topic: ThingsDiaryTopic,
		params: ThingsDiaryTopicParams
	) async throws -> ThingsDiaryTopic
	func createTemplate(
		diaryID: String,
		params: ThingsDiaryTemplateParams
	) async throws -> ThingsDiaryTemplate
	func updateTemplate(
		_ template: ThingsDiaryTemplate,
		params: ThingsDiaryTemplateParams
	) async throws -> ThingsDiaryTemplate
}

extension ThingsDiaryAppClient {
	func createDiary(_ params: ThingsDiaryCreateParams) async throws -> ThingsDiaryDiary {
		throw DiaryStoreError.unsupportedRemoteEntry
	}

	func topics(diaryID: String) async throws -> [ThingsDiaryTopic] { [] }

	func templates(diaryID: String) async throws -> [ThingsDiaryTemplate] { [] }

	func createEntry(
		diaryID: String,
		entryID: String,
		params: ThingsDiaryEntryParams
	) async throws -> ThingsDiaryEntry {
		try await createEntry(diaryID: diaryID, params: params)
	}

	func createTopic(
		diaryID: String,
		params: ThingsDiaryTopicParams
	) async throws -> ThingsDiaryTopic {
		throw DiaryStoreError.unsupportedRemoteEntry
	}

	func updateTopic(
		_ topic: ThingsDiaryTopic,
		params: ThingsDiaryTopicParams
	) async throws -> ThingsDiaryTopic {
		throw DiaryStoreError.unsupportedRemoteEntry
	}

	func createTemplate(
		diaryID: String,
		params: ThingsDiaryTemplateParams
	) async throws -> ThingsDiaryTemplate {
		throw DiaryStoreError.unsupportedRemoteEntry
	}

	func updateTemplate(
		_ template: ThingsDiaryTemplate,
		params: ThingsDiaryTemplateParams
	) async throws -> ThingsDiaryTemplate {
		throw DiaryStoreError.unsupportedRemoteEntry
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

	func createDiary(_ params: ThingsDiaryCreateParams) async throws -> ThingsDiaryDiary {
		try await client.createDiary(params)
	}

	func entries(diaryID: String) async throws -> [ThingsDiaryEntry] {
		try await client.allEntries(diaryID: diaryID)
	}

	func topics(diaryID: String) async throws -> [ThingsDiaryTopic] {
		try await client.allTopics(diaryID: diaryID)
	}

	func templates(diaryID: String) async throws -> [ThingsDiaryTemplate] {
		try await client.allTemplates(diaryID: diaryID)
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

	func createTopic(
		diaryID: String,
		params: ThingsDiaryTopicParams
	) async throws -> ThingsDiaryTopic {
		try await client.createTopic(diaryID: diaryID, params: params)
	}

	func updateTopic(
		_ topic: ThingsDiaryTopic,
		params: ThingsDiaryTopicParams
	) async throws -> ThingsDiaryTopic {
		try await client.updateTopic(topic, params: params)
	}

	func createTemplate(
		diaryID: String,
		params: ThingsDiaryTemplateParams
	) async throws -> ThingsDiaryTemplate {
		try await client.createTemplate(diaryID: diaryID, params: params)
	}

	func updateTemplate(
		_ template: ThingsDiaryTemplate,
		params: ThingsDiaryTemplateParams
	) async throws -> ThingsDiaryTemplate {
		try await client.updateTemplate(template, params: params)
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

	func deleteEntry(
		diaryID: String,
		entryID: String,
		soft: Bool?
	) async throws {
		try await client.deleteEntry(
			diaryID: diaryID,
			entryID: entryID,
			soft: soft
		)
	}

	func restoreEntry(
		diaryID: String,
		entryID: String
	) async throws -> ThingsDiaryEntry {
		try await client.restoreEntry(diaryID: diaryID, entryID: entryID)
	}

	func getTopic(diaryID: String, topicID: String) async throws -> ThingsDiaryTopic {
		try await client.getTopic(diaryID: diaryID, topicID: topicID)
	}

	func getTemplate(diaryID: String, templateID: String) async throws -> ThingsDiaryTemplate {
		try await client.getTemplate(diaryID: diaryID, templateID: templateID)
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

enum ThingsDiaryAppPresentation: Equatable {
	case none
	case diaryPicker
	case diaryCreation
}

@MainActor
@Observable
final class ThingsDiaryAppModel {
	var login = ""
	var password = ""
	var secretKey = ""
	private(set) var screen: ThingsDiaryAppScreen = .login
	private(set) var topics: [ThingsDiaryTopic] = []
	private(set) var templates: [ThingsDiaryTemplate] = []
	private(set) var presentation: ThingsDiaryAppPresentation = .none
	private var creationReturnPresentation: ThingsDiaryAppPresentation?
	private(set) var diaryCreationError: String?

	var isCreatingDiary: Bool { presentation == .diaryCreation }
	var availableDiaries: [ThingsDiaryDiary] { loadedDiaries }

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
		isValidEmail(login)
			&& password.trimmingCharacters(in: .whitespacesAndNewlines).count >= 8
	}

	init(
		client: any ThingsDiaryAppClient = LiveThingsDiaryAppClient(),
		store: DiaryStore? = nil
	) {
		self.client = client
		self.store = store
	}

	#if DEBUG
		static func uiTestingWorkspace() -> ThingsDiaryAppModel {
			let now = Date(timeIntervalSince1970: 1_700_000_000)
			let diary = ThingsDiaryDiary(
				id: "fixture-diary",
				title: "Test Diary",
				description: "UI testing workspace",
				createdAt: now,
				updatedAt: now,
				version: 1
			)
			let entry = ThingsDiaryEntry(
				id: "fixture-entry",
				diaryID: diary.id,
				content: "Fixture Entry\nA useful preview for UI testing.",
				createdAt: now,
				updatedAt: now,
				version: 1
			)
			let archivedEntry = ThingsDiaryEntry(
				id: "fixture-archived-entry",
				diaryID: diary.id,
				content: "Archived Entry\nKept safely for later.",
				archived: true,
				createdAt: now.addingTimeInterval(-120),
				updatedAt: now,
				version: 1
			)
			let deletedEntry = ThingsDiaryEntry(
				id: "fixture-deleted-entry",
				diaryID: diary.id,
				content: "Deleted Entry\nWaiting in Trash.",
				createdAt: now.addingTimeInterval(-240),
				updatedAt: now,
				deletedAt: now,
				version: 1
			)
			let topic = ThingsDiaryTopic(
				id: "fixture-topic",
				diaryID: diary.id,
				title: "Work Topic",
				description: "",
				color: "#93C5FD",
				createdAt: now,
				updatedAt: now,
				version: 1
			)
			let model = ThingsDiaryAppModel()
			model.loadedDiaries = [diary]
			model.topics = [topic]
			model.screen = .entries(diary: diary, entries: [entry, archivedEntry, deletedEntry])
			return model
		}
	#endif

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
			await routeToDiaries(diaries)
		} catch {
			screen = .error("Account created, but diaries could not be loaded. Sign in to try again.")
		}
	}

	func showDiaries() {
		diarySelectionID = nil
		topics = []
		templates = []
		presentation = .none
		creationReturnPresentation = nil
		screen = .diaries(loadedDiaries)
	}

	func showDiaryCreation() {
		diaryCreationError = nil
		creationReturnPresentation = presentation == .diaryPicker ? .diaryPicker : nil
		presentation = .diaryCreation
	}

	func showDiaryPicker() {
		presentation = .diaryPicker
	}

	func cancelDiaryPicker() {
		guard presentation == .diaryPicker else { return }
		presentation = .none
	}

	func cancelDiaryCreation() {
		diaryCreationError = nil
		presentation = creationReturnPresentation ?? .none
		creationReturnPresentation = nil
	}

	func createDiary(title: String, description: String) async {
		let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !title.isEmpty else {
			diaryCreationError = "Enter a diary title."
			return
		}
		diaryCreationError = nil
		do {
			let diary = try await client.createDiary(
				ThingsDiaryCreateParams(
					title: title,
					description: description.trimmingCharacters(in: .whitespacesAndNewlines)
				))
			loadedDiaries.append(diary)
			presentation = .none
			creationReturnPresentation = nil
			await selectDiary(diary)
		} catch {
			diaryCreationError = "Could not create the diary. Try again."
		}
	}

	func selectDiary(_ diary: ThingsDiaryDiary) async {
		let selectionID = UUID()
		diarySelectionID = selectionID
		screen = .loading
		do {
			async let entriesRequest = client.entries(diaryID: diary.id)
			async let topicsRequest = client.topics(diaryID: diary.id)
			async let templatesRequest = client.templates(diaryID: diary.id)
			let (entries, topics, templates) = try await (
				entriesRequest,
				topicsRequest,
				templatesRequest
			)
			guard diarySelectionID == selectionID else {
				return
			}
			self.topics = topics
			self.templates = templates
			if let store {
				try await store.replaceSelectedDiary(
					diary,
					entries: entries,
					topics: topics,
					templates: templates
				)
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
				await store.selectedDiary()?.id == diary.id
			{
				topics = await store.topics(diaryID: diary.id)
				templates = await store.templates(diaryID: diary.id)
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
		let content = content.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !content.isEmpty else {
			return
		}
		await createEntry(params: ThingsDiaryEntryParams(content: content))
	}

	func duplicateEntry(_ entry: ThingsDiaryEntry) async {
		await createEntry(
			params: ThingsDiaryEntryParams(
				content: entry.content,
				topicID: entry.topicID,
				archived: entry.archived,
				bookmarked: entry.bookmarked,
				previewHidden: entry.previewHidden
			))
	}

	private func createEntry(params: ThingsDiaryEntryParams) async {
		guard case .entries(let diary, let entries) = screen else {
			return
		}
		if let store {
			let now = Date()
			let localEntry = ThingsDiaryEntry(
				id: UUID().uuidString.lowercased(),
				diaryID: diary.id,
				content: params.content,
				topicID: params.topicID,
				archived: params.archived,
				bookmarked: params.bookmarked,
				previewHidden: params.previewHidden,
				createdAt: now,
				updatedAt: now,
				version: UInt64(now.timeIntervalSince1970 * 1_000)
			)
			do {
				try await store.savePendingEntry(
					PendingEntryWrite(
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
				params: params
			)
			screen = .entries(diary: diary, entries: entries + [created])
		} catch {
			screen = .error("Could not create the entry.")
		}
	}

	func updateEntry(_ entry: ThingsDiaryEntry, content: String) async {
		let content = content.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !content.isEmpty else {
			return
		}
		await saveEntry(
			entry,
			params: ThingsDiaryEntryParams(
				content: content,
				topicID: entry.topicID,
				archived: entry.archived,
				bookmarked: entry.bookmarked,
				previewHidden: entry.previewHidden
			)
		)
	}

	func moveEntry(_ entry: ThingsDiaryEntry, toTopicID topicID: String?) async {
		await saveEntry(
			entry,
			params: ThingsDiaryEntryParams(
				content: entry.content,
				topicID: topicID,
				archived: entry.archived,
				bookmarked: entry.bookmarked,
				previewHidden: entry.previewHidden
			)
		)
	}

	func createTopic(
		title: String,
		description: String,
		color: String,
		entryPreviewable: Bool = true,
		defaultTemplateID: String? = nil
	) async {
		guard case .entries(let diary, _) = screen else { return }
		let title = normalizedTopicTitle(title)
		guard !title.isEmpty else { return }
		do {
			let topic = try await client.createTopic(
				diaryID: diary.id,
				params: ThingsDiaryTopicParams(
					title: title,
					description: description.trimmingCharacters(in: .whitespacesAndNewlines),
					color: color,
					entryPreviewable: entryPreviewable,
					defaultTemplateID: defaultTemplateID
				)
			)
			try await store?.upsertTopic(topic)
			topics.append(topic)
		} catch {
			screen = .error("Could not create the topic.")
		}
	}

	func updateTopic(
		_ topic: ThingsDiaryTopic,
		title: String,
		description: String,
		color: String,
		entryPreviewable: Bool? = nil,
		defaultTemplateID: String? = nil
	) async {
		let title = normalizedTopicTitle(title)
		guard !title.isEmpty else { return }
		do {
			let updated = try await client.updateTopic(
				topic,
				params: ThingsDiaryTopicParams(
					title: title,
					description: description.trimmingCharacters(in: .whitespacesAndNewlines),
					color: color,
					entryPreviewable: entryPreviewable ?? topic.entryPreviewable,
					defaultTemplateID: defaultTemplateID ?? topic.defaultTemplateID
				)
			)
			try await store?.upsertTopic(updated)
			topics = topics.map { $0.id == updated.id ? updated : $0 }
		} catch {
			screen = .error("Could not update the topic.")
		}
	}

	func createTemplate(content: String) async {
		guard case .entries(let diary, _) = screen else { return }
		let content = content.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !content.isEmpty else { return }
		do {
			let template = try await client.createTemplate(
				diaryID: diary.id,
				params: ThingsDiaryTemplateParams(content: content)
			)
			try await store?.upsertTemplate(template)
			templates.append(template)
		} catch {
			screen = .error("Could not create the template.")
		}
	}

	func updateTemplate(_ template: ThingsDiaryTemplate, content: String) async {
		let content = content.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !content.isEmpty else { return }
		do {
			let updated = try await client.updateTemplate(
				template,
				params: ThingsDiaryTemplateParams(content: content)
			)
			try await store?.upsertTemplate(updated)
			templates = templates.map { $0.id == updated.id ? updated : $0 }
		} catch {
			screen = .error("Could not update the template.")
		}
	}

	func toggleBookmark(_ entry: ThingsDiaryEntry) async {
		await saveEntry(
			entry,
			params: ThingsDiaryEntryParams(
				content: entry.content,
				topicID: entry.topicID,
				archived: entry.archived,
				bookmarked: !entry.bookmarked,
				previewHidden: entry.previewHidden
			)
		)
	}

	func toggleArchive(_ entry: ThingsDiaryEntry) async {
		await saveEntry(
			entry,
			params: ThingsDiaryEntryParams(
				content: entry.content,
				topicID: entry.topicID,
				archived: !entry.archived,
				bookmarked: entry.bookmarked,
				previewHidden: entry.previewHidden
			)
		)
	}

	func moveToTrash(_ entry: ThingsDiaryEntry) async {
		guard case .entries(let diary, let entries) = screen else {
			return
		}
		let now = Date()
		let localEntry = ThingsDiaryEntry(
			id: entry.id,
			diaryID: entry.diaryID,
			content: entry.content,
			topicID: entry.topicID,
			archived: entry.archived,
			bookmarked: entry.bookmarked,
			previewHidden: entry.previewHidden,
			createdAt: entry.createdAt,
			updatedAt: now,
			deletedAt: now,
			version: max(
				UInt64(now.timeIntervalSince1970 * 1_000),
				entry.version + 1
			)
		)
		if let store {
			do {
				try await store.savePendingEntry(
					PendingEntryWrite(
						operation: .delete,
						entry: localEntry
					))
				screen = .entries(
					diary: diary,
					entries: entries.map { $0.id == localEntry.id ? localEntry : $0 }
				)
				try await store.synchronize(with: client)
			} catch {}
			screen = .entries(
				diary: diary,
				entries: await store.entries(diaryID: diary.id)
			)
			return
		}
		screen = .loading
		do {
			try await client.deleteEntry(
				diaryID: entry.diaryID,
				entryID: entry.id,
				soft: true
			)
			let deleted = try await client.getEntry(
				diaryID: entry.diaryID,
				entryID: entry.id
			)
			screen = .entries(
				diary: diary,
				entries: entries.map { $0.id == deleted.id ? deleted : $0 }
			)
		} catch {
			screen = .error("Could not move the entry to trash.")
		}
	}

	func restoreEntry(_ entry: ThingsDiaryEntry) async {
		guard case .entries(let diary, let entries) = screen else {
			return
		}
		let now = Date()
		let localEntry = ThingsDiaryEntry(
			id: entry.id,
			diaryID: entry.diaryID,
			content: entry.content,
			topicID: entry.topicID,
			archived: entry.archived,
			bookmarked: entry.bookmarked,
			previewHidden: entry.previewHidden,
			createdAt: entry.createdAt,
			updatedAt: now,
			deletedAt: nil,
			version: max(
				UInt64(now.timeIntervalSince1970 * 1_000),
				entry.version + 1
			)
		)
		if let store {
			do {
				try await store.savePendingEntry(
					PendingEntryWrite(
						operation: .restore,
						entry: localEntry
					))
				screen = .entries(
					diary: diary,
					entries: entries.map { $0.id == localEntry.id ? localEntry : $0 }
				)
				try await store.synchronize(with: client)
			} catch {}
			screen = .entries(
				diary: diary,
				entries: await store.entries(diaryID: diary.id)
			)
			return
		}
		screen = .loading
		do {
			let restored = try await client.restoreEntry(
				diaryID: entry.diaryID,
				entryID: entry.id
			)
			screen = .entries(
				diary: diary,
				entries: entries.map { $0.id == restored.id ? restored : $0 }
			)
		} catch {
			screen = .error("Could not restore the entry.")
		}
	}

	func deleteEntryPermanently(_ entry: ThingsDiaryEntry) async {
		guard case .entries(let diary, let entries) = screen else { return }
		if let store {
			do {
				try await store.savePendingEntry(
					PendingEntryWrite(
						operation: .remove,
						entry: entry
					))
				screen = .entries(
					diary: diary,
					entries: entries.filter { $0.id != entry.id }
				)
				try await store.synchronize(with: client)
			} catch {}
			screen = .entries(
				diary: diary,
				entries: await store.entries(diaryID: diary.id)
			)
			return
		}
		do {
			try await client.deleteEntry(
				diaryID: entry.diaryID,
				entryID: entry.id,
				soft: false
			)
			screen = .entries(
				diary: diary,
				entries: entries.filter { $0.id != entry.id }
			)
		} catch {
			screen = .error("Could not permanently delete the entry.")
		}
	}

	func emptyTrash() async {
		guard case .entries(_, let entries) = screen else { return }
		for entry in entries where entry.deletedAt != nil {
			await deleteEntryPermanently(entry)
		}
	}

	private func saveEntry(
		_ entry: ThingsDiaryEntry,
		params: ThingsDiaryEntryParams
	) async {
		guard case .entries(let diary, let entries) = screen else {
			return
		}
		if let store {
			let now = Date()
			let localEntry = ThingsDiaryEntry(
				id: entry.id,
				diaryID: entry.diaryID,
				content: params.content,
				topicID: params.topicID,
				archived: params.archived,
				bookmarked: params.bookmarked,
				previewHidden: params.previewHidden,
				createdAt: entry.createdAt,
				updatedAt: now,
				deletedAt: entry.deletedAt,
				version: max(
					UInt64(now.timeIntervalSince1970 * 1_000),
					entry.version + 1
				)
			)
			do {
				try await store.savePendingEntry(
					PendingEntryWrite(
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
				params: params
			)
			let updatedEntries = entries.map { current in
				current.id == updated.id ? updated : current
			}
			screen = .entries(diary: diary, entries: updatedEntries)
		} catch {
			screen = .error("Could not update the entry.")
		}
	}

	func register() async {
		guard canRegister else {
			password = ""
			screen = .error(
				"Enter a valid email and a password with at least 8 characters."
			)
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
			screen = .registrationComplete(
				ThingsDiaryRegistrationResult(
					secretKey: secretKey,
					publicKeys: publicKeys
				))
		} catch let ThingsDiaryClientError.httpStatus(status, _) where status == 409 {
			screen = .error("An account with this email already exists.")
		} catch let ThingsDiaryClientError.httpStatus(status, body) {
			let reason = Self.serverErrorReason(from: body)
			screen = .error(
				reason.map { "Registration failed: \($0)" }
					?? "Registration failed with HTTP \(status).")
		} catch {
			screen = .error("Could not reach the registration server. Try again.")
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
		presentation = .none

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
			await routeToDiaries(diaries)
		} catch {
			screen = .error("Could not sign in or load diaries. Check your credentials and try again.")
		}
	}

	func retry() {
		screen = .login
	}

	private func isValidEmail(_ value: String) -> Bool {
		let email = value.trimmingCharacters(in: .whitespacesAndNewlines)
		return email.range(
			of: #"^[^@\s]+@[^@\s]+\.[^@\s]+$"#,
			options: .regularExpression
		) != nil
	}

	private func routeToDiaries(_ diaries: [ThingsDiaryDiary]) async {
		loadedDiaries = diaries
		screen = .diaries(diaries)
		switch diaries.count {
		case 0:
			showDiaryCreation()
		case 1:
			presentation = .none
			await selectDiary(diaries[0])
		default:
			presentation = .diaryPicker
		}
	}

	private static func serverErrorReason(from body: Data) -> String? {
		guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
			let reason = object["error_reason"] as? String,
			!reason.isEmpty
		else {
			return nil
		}
		return reason
	}
}
