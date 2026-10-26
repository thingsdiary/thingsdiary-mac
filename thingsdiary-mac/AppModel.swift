import Foundation
import OSLog
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
	func connect() async throws
	func disconnect() async
	func events() async -> AsyncThrowingStream<ThingsDiaryRealtimeEvent, Error>
	func register(
		login: String,
		password: String,
		secretKey: String,
		kdfSalt: String
	) async throws -> ThingsDiaryPublicKeys
	func login(login: String, password: String, secretKey: String) async throws
	func diaries() async throws -> [ThingsDiaryDiary]
	func createDiary(_ params: ThingsDiaryCreateParams) async throws -> ThingsDiaryDiary
	func updateDiary(
		_ diary: ThingsDiaryDiary,
		params: ThingsDiaryDiaryParams
	) async throws -> ThingsDiaryDiary
	func entries(diaryID: String) async throws -> [ThingsDiaryEntry]
	func topics(diaryID: String) async throws -> [ThingsDiaryTopic]
	func templates(diaryID: String) async throws -> [ThingsDiaryTemplate]
	func createEntry(
		diaryID: String,
		params: ThingsDiaryEntryParams
	) async throws -> ThingsDiaryEntry
	func createEntry(
		diaryID: String,
		entryID: String,
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
	func deleteTopic(
		diaryID: String,
		topicID: String,
		deleteEntries: Bool?,
		soft: Bool?
	) async throws
	func createTemplate(
		diaryID: String,
		params: ThingsDiaryTemplateParams
	) async throws -> ThingsDiaryTemplate
	func updateTemplate(
		_ template: ThingsDiaryTemplate,
		params: ThingsDiaryTemplateParams
	) async throws -> ThingsDiaryTemplate
	func deleteTemplate(diaryID: String, templateID: String, soft: Bool?) async throws
}

extension ThingsDiaryAppClient {
	func connect() async throws {}

	func disconnect() async {}

	func events() async -> AsyncThrowingStream<ThingsDiaryRealtimeEvent, Error> {
		AsyncThrowingStream { $0.finish() }
	}

	func createDiary(_ params: ThingsDiaryCreateParams) async throws -> ThingsDiaryDiary {
		throw DiaryStoreError.unsupportedRemoteEntry
	}

	func updateDiary(
		_ diary: ThingsDiaryDiary,
		params: ThingsDiaryDiaryParams
	) async throws -> ThingsDiaryDiary {
		throw DiaryStoreError.unsupportedRemoteEntry
	}

	func topics(diaryID: String) async throws -> [ThingsDiaryTopic] { [] }

	func templates(diaryID: String) async throws -> [ThingsDiaryTemplate] { [] }

	func createEntry(
		diaryID: String,
		entryID: String,
		params: ThingsDiaryEntryParams
	) async throws -> ThingsDiaryEntry {
		throw DiaryStoreError.unsupportedRemoteEntry
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

	func deleteTopic(
		diaryID: String,
		topicID: String,
		deleteEntries: Bool?,
		soft: Bool?
	) async throws {
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

	func deleteTemplate(diaryID: String, templateID: String, soft: Bool?) async throws {
		throw DiaryStoreError.unsupportedRemoteEntry
	}
}

nonisolated struct ThingsDiaryServerConfiguration: Equatable, Sendable {
	static let baseURLEnvironmentKey = "THINGSDIARY_BASE_URL"

	let baseURL: URL

	init(environment: [String: String] = ProcessInfo.processInfo.environment) {
		let configuredURL = environment[Self.baseURLEnvironmentKey].flatMap(URL.init(string:))
		baseURL = configuredURL ?? ThingsDiaryClient.productionURL
	}
}

nonisolated struct LiveThingsDiaryAppClient: ThingsDiaryAppClient {
	private static let logger = Logger(
		subsystem: "io.thingsdiary.thingsdiary-mac",
		category: "network"
	)

	private let client: ThingsDiaryClient
	private let baseURL: URL

	init(configuration: ThingsDiaryServerConfiguration = ThingsDiaryServerConfiguration()) {
		baseURL = configuration.baseURL
		client = ThingsDiaryClient(baseURL: configuration.baseURL)
	}

	func connect() async throws {
		Self.logger.notice("Connecting realtime for \(baseURL.absoluteString, privacy: .public)")
		try await client.connect()
		Self.logger.notice("Realtime connected")
	}

	func disconnect() async {
		await client.disconnect()
	}

	func events() async -> AsyncThrowingStream<ThingsDiaryRealtimeEvent, Error> {
		let source = await client.events()
		return AsyncThrowingStream { continuation in
			let task = Task {
				do {
					for try await event in source {
						do {
							if let event = try await resolve(event) {
								continuation.yield(event)
							}
						} catch is CancellationError {
							throw CancellationError()
						} catch {
							// One failed point read must not terminate the realtime subscription.
							continue
						}
					}
					continuation.finish()
				} catch {
					continuation.finish(throwing: error)
				}
			}
			continuation.onTermination = { _ in task.cancel() }
		}
	}

	private func resolve(
		_ event: Io_Thingsdiary_V1_Event
	) async throws -> ThingsDiaryRealtimeEvent? {
		guard let payload = event.payload else { return nil }
		switch payload {
		case .diaryCreated(let value):
			return ThingsDiaryRealtimeEvent(
				eventID: value.eventID,
				operationID: event.operationID,
				update: .upsertDiary(try await client.getDiary(id: value.diary.id))
			)
		case .diaryChanged(let value):
			return ThingsDiaryRealtimeEvent(
				eventID: value.eventID,
				operationID: event.operationID,
				update: .upsertDiary(try await client.getDiary(id: value.diary.id))
			)
		case .diaryDeleted(let value):
			return ThingsDiaryRealtimeEvent(
				eventID: value.eventID,
				operationID: event.operationID,
				update: .removeDiary(id: value.diaryID, version: value.version)
			)
		case .entryChanged(let value):
			return try await entryEvent(event, value: value.entry, eventID: value.eventID)
		case .entryRestored(let value):
			return try await entryEvent(event, value: value.entry, eventID: value.eventID)
		case .entryDeleted(let value):
			if value.entry.hasRemovedAt {
				return ThingsDiaryRealtimeEvent(
					eventID: value.eventID,
					operationID: event.operationID,
					update: .removeEntry(
						diaryID: value.entry.diaryID,
						id: value.entry.id,
						version: value.entry.version
					)
				)
			}
			return try await entryEvent(event, value: value.entry, eventID: value.eventID)
		case .topicChanged(let value):
			return try await topicEvent(event, value: value.topic, eventID: value.eventID)
		case .topicRestored(let value):
			return try await topicEvent(event, value: value.topic, eventID: value.eventID)
		case .topicDeleted(let value):
			if value.topic.hasRemovedAt {
				return ThingsDiaryRealtimeEvent(
					eventID: value.eventID,
					operationID: event.operationID,
					update: .removeTopic(
						diaryID: value.topic.diaryID,
						id: value.topic.id,
						version: value.topic.version
					)
				)
			}
			return try await topicEvent(event, value: value.topic, eventID: value.eventID)
		case .templateChanged(let value):
			return try await templateEvent(event, value: value.template, eventID: value.eventID)
		case .templateRestored(let value):
			return try await templateEvent(event, value: value.template, eventID: value.eventID)
		case .templateDeleted(let value):
			if value.template.hasRemovedAt {
				return ThingsDiaryRealtimeEvent(
					eventID: value.eventID,
					operationID: event.operationID,
					update: .removeTemplate(
						diaryID: value.template.diaryID,
						id: value.template.id,
						version: value.template.version
					)
				)
			}
			return try await templateEvent(event, value: value.template, eventID: value.eventID)
		}
	}

	private func entryEvent(
		_ event: Io_Thingsdiary_V1_Event,
		value: Io_Thingsdiary_V1_Entry,
		eventID: String
	) async throws -> ThingsDiaryRealtimeEvent {
		ThingsDiaryRealtimeEvent(
			eventID: eventID,
			operationID: event.operationID,
			update: .upsertEntry(
				try await client.getEntry(diaryID: value.diaryID, entryID: value.id)
			)
		)
	}

	private func topicEvent(
		_ event: Io_Thingsdiary_V1_Event,
		value: Io_Thingsdiary_V1_Topic,
		eventID: String
	) async throws -> ThingsDiaryRealtimeEvent {
		ThingsDiaryRealtimeEvent(
			eventID: eventID,
			operationID: event.operationID,
			update: .upsertTopic(
				try await client.getTopic(diaryID: value.diaryID, topicID: value.id)
			)
		)
	}

	private func templateEvent(
		_ event: Io_Thingsdiary_V1_Event,
		value: Io_Thingsdiary_V1_Template,
		eventID: String
	) async throws -> ThingsDiaryRealtimeEvent {
		ThingsDiaryRealtimeEvent(
			eventID: eventID,
			operationID: event.operationID,
			update: .upsertTemplate(
				try await client.getTemplate(diaryID: value.diaryID, templateID: value.id)
			)
		)
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
		Self.logger.notice("Signing in through \(baseURL.absoluteString, privacy: .public)")
		_ = try await client.login(
			login: login,
			password: password,
			secretKey: secretKey
		)
		Self.logger.notice("Sign-in completed")
	}

	func diaries() async throws -> [ThingsDiaryDiary] {
		Self.logger.notice("Loading diaries")
		let diaries = try await client.allDiaries()
		Self.logger.notice("Loaded \(diaries.count) diaries")
		return diaries
	}

	func createDiary(_ params: ThingsDiaryCreateParams) async throws -> ThingsDiaryDiary {
		try await client.createDiary(params)
	}

	func updateDiary(
		_ diary: ThingsDiaryDiary,
		params: ThingsDiaryDiaryParams
	) async throws -> ThingsDiaryDiary {
		try await client.updateDiary(diary, params: params)
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

	func deleteTopic(
		diaryID: String,
		topicID: String,
		deleteEntries: Bool?,
		soft: Bool?
	) async throws {
		try await client.deleteTopic(
			diaryID: diaryID,
			topicID: topicID,
			deleteEntries: deleteEntries,
			soft: soft
		)
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

	func deleteTemplate(diaryID: String, templateID: String, soft: Bool?) async throws {
		try await client.deleteTemplate(diaryID: diaryID, templateID: templateID, soft: soft)
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

#if DEBUG
	nonisolated private enum UITestingAuthScenario: String {
		case workspace
		case loginSuccess = "login-success"
		case loginBadRequest = "login-bad-request"
		case registrationSuccess = "registration-success"
		case registrationMismatch = "registration-mismatch"
		case registrationDuplicate = "registration-duplicate"
		case registrationBadRequest = "registration-bad-request"
	}

	private actor UITestingAppClient: ThingsDiaryAppClient {
		let scenario: UITestingAuthScenario
		private var storedEntries: [String: ThingsDiaryEntry]

		init(scenario: UITestingAuthScenario = .workspace, entries: [ThingsDiaryEntry] = []) {
			self.scenario = scenario
			storedEntries = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
		}

		func register(
			login: String,
			password: String,
			secretKey: String,
			kdfSalt: String
		) async throws -> ThingsDiaryPublicKeys {
			switch scenario {
			case .registrationSuccess:
				return ThingsDiaryPublicKeys(signing: "signing-public-key", encryption: "encryption-public-key")
			case .registrationDuplicate:
				throw ThingsDiaryClientError.httpStatus(409, body: Data())
			case .registrationBadRequest:
				throw ThingsDiaryClientError.httpStatus(
					400,
					body: Data(
						#"{"error_code":"BAD_REQUEST","error_reason":"password rejected by server"}"#.utf8
					)
				)
			default:
				throw DiaryStoreError.unsupportedRemoteEntry
			}
		}

		func login(login: String, password: String, secretKey: String) async throws {
			guard scenario == .loginBadRequest else { return }
			throw ThingsDiaryClientError.httpStatus(
				400,
				body: Data(
					#"{"error_code":"BAD_REQUEST","error_reason":"login rejected by server"}"#.utf8
				)
			)
		}

		func diaries() async throws -> [ThingsDiaryDiary] { [] }

		func updateDiary(
			_ diary: ThingsDiaryDiary,
			params: ThingsDiaryDiaryParams
		) async throws -> ThingsDiaryDiary {
			let now = Date()
			return ThingsDiaryDiary(
				id: diary.id,
				title: params.title,
				description: params.description,
				createdAt: diary.createdAt,
				updatedAt: now,
				version: max(diary.version + 1, UInt64(now.timeIntervalSince1970 * 1_000))
			)
		}

		func entries(diaryID: String) async throws -> [ThingsDiaryEntry] {
			storedEntries.values.filter { $0.diaryID == diaryID }
		}

		func createEntry(
			diaryID: String,
			params: ThingsDiaryEntryParams
		) async throws -> ThingsDiaryEntry {
			try await createEntry(
				diaryID: diaryID,
				entryID: UUID().uuidString.lowercased(),
				params: params
			)
		}

		func createEntry(
			diaryID: String,
			entryID: String,
			params: ThingsDiaryEntryParams
		) async throws -> ThingsDiaryEntry {
			let now = Date()
			let created = ThingsDiaryEntry(
				id: entryID,
				diaryID: diaryID,
				content: params.content,
				topicID: params.topicID,
				archived: params.archived,
				bookmarked: params.bookmarked,
				previewHidden: params.previewHidden,
				createdAt: now,
				updatedAt: now,
				version: UInt64(now.timeIntervalSince1970 * 1_000)
			)
			storedEntries[created.id] = created
			return created
		}

		func updateEntry(
			_ entry: ThingsDiaryEntry,
			params: ThingsDiaryEntryParams
		) async throws -> ThingsDiaryEntry {
			let now = Date()
			let updated = ThingsDiaryEntry(
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
				version: max(entry.version + 1, UInt64(now.timeIntervalSince1970 * 1_000))
			)
			storedEntries[updated.id] = updated
			return updated
		}

		func getEntry(diaryID: String, entryID: String) async throws -> ThingsDiaryEntry {
			guard let entry = storedEntries[entryID], entry.diaryID == diaryID else {
				throw DiaryStoreError.unsupportedRemoteEntry
			}
			return entry
		}

		func deleteEntry(diaryID: String, entryID: String, soft: Bool?) async throws {
			let entry = try await getEntry(diaryID: diaryID, entryID: entryID)
			if soft == true {
				storedEntries[entryID] = entryChangingDeletion(entry, deletedAt: .now)
			} else {
				storedEntries.removeValue(forKey: entryID)
			}
		}

		func restoreEntry(diaryID: String, entryID: String) async throws -> ThingsDiaryEntry {
			let entry = try await getEntry(diaryID: diaryID, entryID: entryID)
			let restored = entryChangingDeletion(entry, deletedAt: nil)
			storedEntries[entryID] = restored
			return restored
		}

		private func entryChangingDeletion(_ entry: ThingsDiaryEntry, deletedAt: Date?) -> ThingsDiaryEntry {
			let now = Date()
			return ThingsDiaryEntry(
				id: entry.id, diaryID: entry.diaryID, content: entry.content, topicID: entry.topicID,
				archived: entry.archived, bookmarked: entry.bookmarked, previewHidden: entry.previewHidden,
				createdAt: entry.createdAt, updatedAt: now, deletedAt: deletedAt,
				version: max(entry.version + 1, UInt64(now.timeIntervalSince1970 * 1_000))
			)
		}

		func createTopic(
			diaryID: String,
			params: ThingsDiaryTopicParams
		) async throws -> ThingsDiaryTopic {
			let now = Date()
			return ThingsDiaryTopic(
				id: UUID().uuidString.lowercased(),
				diaryID: diaryID,
				title: params.title,
				description: params.description,
				color: params.color,
				entryPreviewable: params.entryPreviewable,
				defaultTemplateID: params.defaultTemplateID,
				createdAt: now,
				updatedAt: now,
				version: UInt64(now.timeIntervalSince1970 * 1_000)
			)
		}

		func updateTopic(
			_ topic: ThingsDiaryTopic,
			params: ThingsDiaryTopicParams
		) async throws -> ThingsDiaryTopic {
			let now = Date()
			return ThingsDiaryTopic(
				id: topic.id,
				diaryID: topic.diaryID,
				title: params.title,
				description: params.description,
				color: params.color,
				entryPreviewable: params.entryPreviewable,
				defaultTemplateID: params.defaultTemplateID,
				createdAt: topic.createdAt,
				updatedAt: now,
				deletedAt: topic.deletedAt,
				version: max(topic.version + 1, UInt64(now.timeIntervalSince1970 * 1_000))
			)
		}

		func deleteTopic(
			diaryID: String,
			topicID: String,
			deleteEntries: Bool?,
			soft: Bool?
		) async throws {}

		func createTemplate(
			diaryID: String,
			params: ThingsDiaryTemplateParams
		) async throws -> ThingsDiaryTemplate {
			let now = Date()
			return ThingsDiaryTemplate(
				id: UUID().uuidString.lowercased(),
				diaryID: diaryID,
				content: params.content,
				createdAt: now,
				updatedAt: now,
				version: UInt64(now.timeIntervalSince1970 * 1_000)
			)
		}

		func updateTemplate(
			_ template: ThingsDiaryTemplate,
			params: ThingsDiaryTemplateParams
		) async throws -> ThingsDiaryTemplate {
			let now = Date()
			return ThingsDiaryTemplate(
				id: template.id,
				diaryID: template.diaryID,
				content: params.content,
				createdAt: template.createdAt,
				updatedAt: now,
				deletedAt: template.deletedAt,
				version: max(template.version + 1, UInt64(now.timeIntervalSince1970 * 1_000))
			)
		}

		func deleteTemplate(diaryID: String, templateID: String, soft: Bool?) async throws {}
	}

#endif

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
	var passwordConfirmation = ""
	var secretKey = ""
	private(set) var screen: ThingsDiaryAppScreen = .login {
		didSet {
			guard screen != .loading else { return }
			drainDeferredRealtimeUpdates()
		}
	}
	private(set) var topics: [ThingsDiaryTopic] = []
	private(set) var templates: [ThingsDiaryTemplate] = []
	private(set) var presentation: ThingsDiaryAppPresentation = .none
	private(set) var diaryEditRequestID: String?
	private var creationReturnPresentation: ThingsDiaryAppPresentation?
	private(set) var diaryCreationError: String?
	private(set) var entryDraftIDs: Set<String> = []
	private(set) var entryDraftIDsHiddenFromList: Set<String> = []
	private(set) var entryPendingCreationIDs: Set<String> = []
	private(set) var templateDraftIDs: Set<String> = []
	private(set) var isAuthenticated = false
	var isLogoutConfirmationPresented = false

	var isCreatingDiary: Bool { presentation == .diaryCreation }
	var availableDiaries: [ThingsDiaryDiary] { loadedDiaries }

	private let client: any ThingsDiaryAppClient
	private let store: DiaryStore?
	private var realtimeCoordinator: RealtimeSyncCoordinator?
	private var diarySelectionID: UUID?
	private var loadedDiaries: [ThingsDiaryDiary] = []
	private var deferredRealtimeUpdates: [(ThingsDiaryRealtimeEvent, DiaryStoreSnapshot?)] = []
	private var isDrainingRealtimeUpdates = false

	var canSubmit: Bool {
		!login.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
			&& !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
			&& (try? ThingsDiarySecretKey.parse(secretKey)) != nil
	}

	var canRegister: Bool {
		isValidEmail(login)
			&& password.trimmingCharacters(in: .whitespacesAndNewlines).count >= 8
			&& password == passwordConfirmation
	}

	init(
		client: any ThingsDiaryAppClient = LiveThingsDiaryAppClient(),
		store: DiaryStore? = nil
	) {
		self.client = client
		self.store = store
	}

	#if DEBUG
		static func uiTestingAuthentication(scenario rawValue: String) -> ThingsDiaryAppModel {
			let scenario = UITestingAuthScenario(rawValue: rawValue) ?? .loginSuccess
			let model = ThingsDiaryAppModel(client: UITestingAppClient(scenario: scenario))

			switch scenario {
			case .workspace:
				break
			case .loginSuccess, .loginBadRequest:
				break
			case .registrationSuccess, .registrationMismatch, .registrationDuplicate,
				.registrationBadRequest:
				model.screen = .registration
			}

			return model
		}

		static func uiTestingWorkspace(
			includesDeletedEntry: Bool = true,
			includesTemplate: Bool = false,
			includesMultipleTemplates: Bool = false,
			includesMultipleDiaries: Bool = false,
			includesHiddenPreviews: Bool = false
		) -> ThingsDiaryAppModel {
			let now = Date(timeIntervalSince1970: 1_700_000_000)
			let diary = ThingsDiaryDiary(
				id: "fixture-diary",
				title: "Test Diary",
				description: "UI testing workspace",
				createdAt: now,
				updatedAt: now,
				version: 1
			)
			let entries = (1...19).map { index in
				let timestamp = now.addingTimeInterval(TimeInterval(-(index - 1) * 60))
				let content: String
				if includesHiddenPreviews && (3...4).contains(index) {
					content = ""
				} else if includesHiddenPreviews && index == 5 {
					content =
						"Мысли о сегодняшнем дне\nНесколько наблюдений, которые хочется сохранить. Прогулка, новые идеи и планы на следующую неделю. Ещё одна строка для проверки длинного превью. 🙂"
				} else {
					content =
						index == 1
						? "Fixture Entry\nA useful preview for UI testing."
						: index == 2
							? "Fixture Entry 2"
							: "Fixture Entry \(index)\nSample note \(index) for UI testing."
				}
				return ThingsDiaryEntry(
					id: index == 1 ? "fixture-entry" : "fixture-entry-\(index)",
					diaryID: diary.id,
					content: content,
					topicID: index == 19 || (includesHiddenPreviews && (6...8).contains(index))
						? "fixture-topic-2" : nil,
					previewHidden: includesHiddenPreviews && (2...5).contains(index),
					createdAt: timestamp,
					updatedAt: timestamp,
					version: 1
				)
			}
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
			let secondTopic = ThingsDiaryTopic(
				id: "fixture-topic-2",
				diaryID: diary.id,
				title: "Personal Topic",
				description: "",
				color: "#FCA5A5",
				entryPreviewable: !includesHiddenPreviews,
				createdAt: now,
				updatedAt: now,
				version: 1
			)
			let initialEntries = entries + [archivedEntry] + (includesDeletedEntry ? [deletedEntry] : [])
			let model = ThingsDiaryAppModel(client: UITestingAppClient(entries: initialEntries))
			model.isAuthenticated = true
			let secondDiary = ThingsDiaryDiary(
				id: "fixture-diary-2",
				title: "Second Diary",
				description: "Second UI testing diary",
				createdAt: now,
				updatedAt: now,
				version: 1
			)
			model.loadedDiaries = includesMultipleDiaries ? [diary, secondDiary] : [diary]
			model.topics = [topic, secondTopic]
			if includesTemplate || includesMultipleTemplates {
				model.templates = [
					ThingsDiaryTemplate(
						id: "fixture-template",
						diaryID: diary.id,
						content: "Context menu template",
						createdAt: now,
						updatedAt: now,
						version: 1
					)
				]
			}
			if includesMultipleTemplates {
				model.templates += (2...4).map { index in
					ThingsDiaryTemplate(
						id: "fixture-template-\(index)", diaryID: diary.id,
						content: "Fixture Template \(index)",
						createdAt: now.addingTimeInterval(TimeInterval(-index * 60)),
						updatedAt: now, version: 1
					)
				}
			}

			model.screen = .entries(
				diary: diary,
				entries: initialEntries
			)
			return model
		}
	#endif

	func showRegistration() {
		password = ""
		passwordConfirmation = ""
		secretKey = ""
		screen = .registration
	}

	func showLogin() {
		password = ""
		passwordConfirmation = ""
		secretKey = ""
		screen = .login
	}

	func requestLogoutConfirmation() {
		guard isAuthenticated else { return }
		isLogoutConfirmationPresented = true
	}

	func logout() async {
		guard isAuthenticated else { return }
		isAuthenticated = false
		isLogoutConfirmationPresented = false
		diarySelectionID = nil

		await realtimeCoordinator?.stop()
		realtimeCoordinator = nil
		try? await store?.clear()

		login = ""
		password = ""
		passwordConfirmation = ""
		secretKey = ""
		topics = []
		templates = []
		presentation = .none
		creationReturnPresentation = nil
		diaryCreationError = nil
		diaryEditRequestID = nil
		entryDraftIDs = []
		entryDraftIDsHiddenFromList = []
		entryPendingCreationIDs = []
		templateDraftIDs = []
		loadedDiaries = []
		deferredRealtimeUpdates = []
		isDrainingRealtimeUpdates = false
		screen = .login
	}

	func continueAfterRegistration() async {
		guard case .registrationComplete = screen else {
			return
		}
		screen = .loading
		do {
			try await startRealtimeSession()
			let diaries = try await client.diaries()
			isAuthenticated = true
			await routeToDiaries(diaries)
		} catch {
			screen = .error("Account created, but diaries could not be loaded. Sign in to try again.")
		}
	}

	func showDiaries() {
		diarySelectionID = nil
		entryDraftIDs = []
		entryDraftIDsHiddenFromList = []
		entryPendingCreationIDs = []
		templateDraftIDs = []
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

	func requestDiaryEdit(for diary: ThingsDiaryDiary) async {
		if case .entries(let selectedDiary, _) = screen,
			selectedDiary.id != diary.id
		{
			await selectDiary(diary)
		}
		guard case .entries(let selectedDiary, _) = screen,
			selectedDiary.id == diary.id
		else {
			return
		}
		diaryEditRequestID = diary.id
	}

	func consumeDiaryEditRequest(for diaryID: String) -> Bool {
		guard diaryEditRequestID == diaryID else { return false }
		diaryEditRequestID = nil
		return true
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

	@discardableResult
	func updateDiary(
		_ diary: ThingsDiaryDiary,
		title: String,
		description: String
	) async -> Bool {
		let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !title.isEmpty else { return false }
		do {
			let updated = try await client.updateDiary(
				diary,
				params: ThingsDiaryDiaryParams(
					title: title,
					description: description.trimmingCharacters(in: .whitespacesAndNewlines)
				)
			)
			loadedDiaries = loadedDiaries.map { $0.id == updated.id ? updated : $0 }
			if case .entries(let currentDiary, let entries) = screen,
				currentDiary.id == updated.id
			{
				try await store?.replaceSelectedDiary(
					updated,
					entries: entries,
					topics: topics,
					templates: templates
				)
				screen = .entries(diary: updated, entries: entries)
			}
			return true
		} catch {
			return false
		}
	}

	func selectDiary(_ diary: ThingsDiaryDiary) async {
		let selectionID = UUID()
		diarySelectionID = selectionID
		entryDraftIDs = []
		entryDraftIDsHiddenFromList = []
		entryPendingCreationIDs = []
		templateDraftIDs = []
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
			let activeTopics = topics.filter { $0.deletedAt == nil }
			self.topics = activeTopics
			self.templates = templates
			if let store {
				try await store.replaceSelectedDiary(
					diary,
					entries: entries,
					topics: activeTopics,
					templates: templates
				)
				try await store.synchronize(with: client)
				self.topics = await store.topics(diaryID: diary.id)
				self.templates = await store.templates(diaryID: diary.id)
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

	@discardableResult
	func beginEntryDraft(
		appearsInList: Bool,
		topicID: String? = nil,
		bookmarked: Bool = false
	) -> ThingsDiaryEntry? {
		guard case .entries(let diary, let entries) = screen else { return nil }
		let now = Date()
		let defaultTemplateContent =
			topics
			.first(where: { $0.id == topicID })
			.flatMap(\.defaultTemplateID)
			.flatMap { templateID in templates.first(where: { $0.id == templateID })?.content }
		let draft = ThingsDiaryEntry(
			id: UUID().uuidString.lowercased(),
			diaryID: diary.id,
			content: defaultTemplateContent ?? "",
			topicID: topicID,
			bookmarked: bookmarked,
			createdAt: now,
			updatedAt: now,
			version: UInt64(now.timeIntervalSince1970 * 1_000)
		)
		entryDraftIDs.insert(draft.id)
		if !appearsInList {
			entryDraftIDsHiddenFromList.insert(draft.id)
		}
		screen = .entries(diary: diary, entries: entries + [draft])
		return draft
	}

	func discardEntryDraft(_ entryID: String) {
		guard entryDraftIDs.remove(entryID) != nil,
			case .entries(let diary, let entries) = screen
		else { return }
		entryDraftIDsHiddenFromList.remove(entryID)
		screen = .entries(
			diary: diary,
			entries: entries.filter { $0.id != entryID }
		)
	}

	func promoteEntryDraft(_ entryID: String, content: String) {
		guard case .entries(_, let entries) = screen,
			let draft = entries.first(where: { $0.id == entryID })
		else { return }
		promoteEntryDraft(
			draft,
			params: ThingsDiaryEntryParams(
				content: content,
				topicID: draft.topicID,
				archived: draft.archived,
				bookmarked: draft.bookmarked,
				previewHidden: draft.previewHidden
			)
		)
	}

	private func promoteEntryDraft(
		_ draft: ThingsDiaryEntry,
		params: ThingsDiaryEntryParams,
		allowsUnchanged: Bool = false
	) {
		guard entryDraftIDs.contains(draft.id),
			case .entries(let diary, let entries) = screen,
			entries.contains(where: { $0.id == draft.id })
		else { return }
		guard
			allowsUnchanged
				|| params.content != draft.content
				|| params.topicID != draft.topicID
				|| params.archived != draft.archived
				|| params.bookmarked != draft.bookmarked
				|| params.previewHidden != draft.previewHidden
		else { return }
		entryDraftIDs.remove(draft.id)
		entryDraftIDsHiddenFromList.remove(draft.id)
		entryPendingCreationIDs.insert(draft.id)
		let now = Date()
		let entry = ThingsDiaryEntry(
			id: draft.id,
			diaryID: draft.diaryID,
			content: params.content,
			topicID: params.topicID,
			archived: params.archived,
			bookmarked: params.bookmarked,
			previewHidden: params.previewHidden,
			createdAt: draft.createdAt,
			updatedAt: now,
			version: max(
				UInt64(now.timeIntervalSince1970 * 1_000),
				draft.version + 1
			)
		)
		screen = .entries(
			diary: diary,
			entries: entries.map { $0.id == entry.id ? entry : $0 }
		)
		Task { await persistPromotedEntry(entry) }
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
				await refreshEntriesFromStore(store, diaryID: diary.id)
			} catch {
				await refreshEntriesFromStore(store, diaryID: diary.id)
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

	private func persistPromotedEntry(_ entry: ThingsDiaryEntry) async {
		guard case .entries(let diary, _) = screen, diary.id == entry.diaryID else { return }
		let params = ThingsDiaryEntryParams(
			content: entry.content,
			topicID: entry.topicID,
			archived: entry.archived,
			bookmarked: entry.bookmarked,
			previewHidden: entry.previewHidden
		)
		if let store {
			do {
				try await store.savePendingEntry(
					PendingEntryWrite(operation: .create, entry: entry)
				)
				try await store.synchronize(with: client)
				let isStillPending = await store.pendingEntryWrites().contains {
					$0.id == entry.id
				}
				if !isStillPending {
					entryPendingCreationIDs.remove(entry.id)
				}
				let storedEntry = await store.entries(diaryID: diary.id).first {
					$0.id == entry.id
				}
				if let storedEntry,
					case .entries(let currentDiary, let entries) = screen,
					currentDiary.id == diary.id
				{
					screen = .entries(
						diary: currentDiary,
						entries: entries.map { $0.id == entry.id ? storedEntry : $0 }
					)
				}
			} catch {}
			return
		}
		do {
			let created = try await client.createEntry(
				diaryID: diary.id,
				entryID: entry.id,
				params: params
			)
			guard created.id == entry.id else { return }
			entryPendingCreationIDs.remove(entry.id)
			guard case .entries(let currentDiary, let entries) = screen,
				currentDiary.id == diary.id
			else { return }
			screen = .entries(
				diary: currentDiary,
				entries: entries.map { $0.id == entry.id ? created : $0 }
			)
		} catch {
			// The in-memory entry stays available for this session.
		}
	}

	@discardableResult
	func updateEntry(_ entry: ThingsDiaryEntry, content: String) async -> Bool {
		let params = ThingsDiaryEntryParams(
			content: content,
			topicID: entry.topicID,
			archived: entry.archived,
			bookmarked: entry.bookmarked,
			previewHidden: entry.previewHidden
		)
		if entryDraftIDs.contains(entry.id) {
			promoteEntryDraft(entry, params: params, allowsUnchanged: true)
			return !entryDraftIDs.contains(entry.id)
		}
		return await saveEntry(entry, params: params)
	}

	func moveEntry(_ entry: ThingsDiaryEntry, toTopicID topicID: String?) async {
		if entryDraftIDs.contains(entry.id) {
			promoteEntryDraft(
				entry,
				params: ThingsDiaryEntryParams(
					content: entry.content,
					topicID: topicID,
					archived: entry.archived,
					bookmarked: entry.bookmarked,
					previewHidden: entry.previewHidden
				)
			)
			return
		}
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
		defaultTemplateID: String?? = nil
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

	@discardableResult
	func deleteTopic(_ topic: ThingsDiaryTopic, deleteEntries: Bool) async -> Bool {
		guard case .entries(let diary, let entries) = screen else { return false }
		do {
			try await client.deleteTopic(
				diaryID: topic.diaryID,
				topicID: topic.id,
				deleteEntries: deleteEntries,
				soft: true
			)

			let now = Date()
			let nextEntries = entries.map { entry in
				guard entry.topicID == topic.id else { return entry }
				return entryAfterDeletingTopic(
					entry,
					deleteEntry: deleteEntries,
					at: now
				)
			}
			try await store?.removeTopic(
				diaryID: topic.diaryID,
				topicID: topic.id,
				entries: nextEntries
			)
			topics.removeAll { $0.id == topic.id }
			if deleteEntries {
				let deletedEntryIDs = Set(
					entries.lazy.filter { $0.topicID == topic.id }.map(\.id)
				)
				entryDraftIDs.subtract(deletedEntryIDs)
				entryDraftIDsHiddenFromList.subtract(deletedEntryIDs)
				entryPendingCreationIDs.subtract(deletedEntryIDs)
			}
			screen = .entries(diary: diary, entries: nextEntries)
			return true
		} catch {
			screen = .error("Could not delete the topic.")
			return false
		}
	}

	private func entryAfterDeletingTopic(
		_ entry: ThingsDiaryEntry,
		deleteEntry: Bool,
		at date: Date
	) -> ThingsDiaryEntry {
		ThingsDiaryEntry(
			id: entry.id,
			diaryID: entry.diaryID,
			content: entry.content,
			topicID: deleteEntry ? entry.topicID : nil,
			archived: entry.archived,
			bookmarked: entry.bookmarked,
			previewHidden: entry.previewHidden,
			createdAt: entry.createdAt,
			updatedAt: date,
			deletedAt: deleteEntry ? date : entry.deletedAt,
			version: max(entry.version + 1, UInt64(date.timeIntervalSince1970 * 1_000))
		)
	}

	@discardableResult
	func createTemplate(content: String) async -> ThingsDiaryTemplate? {
		guard case .entries(let diary, _) = screen else { return nil }
		do {
			let template = try await client.createTemplate(
				diaryID: diary.id,
				params: ThingsDiaryTemplateParams(content: content)
			)
			try await store?.upsertTemplate(template)
			templates.append(template)
			return template
		} catch {
			screen = .error("Could not create the template.")
			return nil
		}
	}

	@discardableResult
	func beginTemplateDraft() async -> ThingsDiaryTemplate? {
		guard let template = await createTemplate(content: "") else { return nil }
		templateDraftIDs.insert(template.id)
		return template
	}

	@discardableResult
	func updateTemplate(_ template: ThingsDiaryTemplate, content: String) async -> Bool {
		do {
			let updated = try await client.updateTemplate(
				template,
				params: ThingsDiaryTemplateParams(content: content)
			)
			try await store?.upsertTemplate(updated)
			templates = templates.map { $0.id == updated.id ? updated : $0 }
			templateDraftIDs.remove(template.id)
			return true
		} catch {
			screen = .error("Could not update the template.")
			return false
		}
	}

	@discardableResult
	func deleteTemplate(_ template: ThingsDiaryTemplate) async -> Bool {
		do {
			for topic in topics where topic.defaultTemplateID == template.id {
				let updated = try await client.updateTopic(
					topic,
					params: ThingsDiaryTopicParams(
						title: topic.title,
						description: topic.description,
						color: topic.color,
						entryPreviewable: topic.entryPreviewable,
						defaultTemplateID: nil
					)
				)
				try await store?.upsertTopic(updated)
				topics = topics.map { $0.id == updated.id ? updated : $0 }
			}
			try await client.deleteTemplate(
				diaryID: template.diaryID,
				templateID: template.id,
				soft: true
			)
			try await store?.removeTemplate(diaryID: template.diaryID, templateID: template.id)
			templates.removeAll { $0.id == template.id }
			templateDraftIDs.remove(template.id)
			return true
		} catch {
			screen = .error("Could not delete the template.")
			return false
		}
	}

	func toggleEntryPreview(_ entry: ThingsDiaryEntry) async {
		guard case .entries(_, let entries) = screen,
			let current = entries.first(where: { $0.id == entry.id }),
			current.deletedAt == nil,
			!entryDraftIDs.contains(current.id),
			topics.first(where: { $0.id == current.topicID })?.entryPreviewable != false
		else { return }
		await saveEntry(
			current,
			params: ThingsDiaryEntryParams(
				content: current.content,
				topicID: current.topicID,
				archived: current.archived,
				bookmarked: current.bookmarked,
				previewHidden: !current.previewHidden
			)
		)
	}

	func toggleBookmark(_ entry: ThingsDiaryEntry) async {
		if entryDraftIDs.contains(entry.id) {
			promoteEntryDraft(
				entry,
				params: ThingsDiaryEntryParams(
					content: entry.content,
					topicID: entry.topicID,
					archived: entry.archived,
					bookmarked: !entry.bookmarked,
					previewHidden: entry.previewHidden
				)
			)
			return
		}
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
		guard !entryDraftIDs.contains(entry.id) else { return }
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
		guard !entryDraftIDs.contains(entry.id),
			case .entries(let diary, let entries) = screen
		else {
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
			await refreshEntriesFromStore(store, diaryID: diary.id)
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
			await refreshEntriesFromStore(store, diaryID: diary.id)
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
			await refreshEntriesFromStore(store, diaryID: diary.id)
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

	/// Runs against a fixed diary and refreshes each source before acting on it.
	/// An accepted local write succeeds even when synchronization must wait for a connection.
	func performBulkAction(
		_ action: WorkspaceBulkAction,
		ids: [String],
		templates templateSelection: Bool = false,
		contentsByID: [String: String] = [:]
	) async -> WorkspaceBulkResult {
		var result = WorkspaceBulkResult()
		guard case .entries(let diary, _) = screen else {
			result.failedIDs = Set(ids)
			return result
		}
		let selectionID = diarySelectionID
		var seen: Set<String> = []
		var queuedSources: [String: String] = [:]
		for id in ids where seen.insert(id).inserted {
			do {
				guard bulkDiaryIsCurrent(diary.id, selectionID: selectionID) else {
					throw BulkOperationError.unavailable
				}
				if templateSelection {
					try await performBulkTemplateAction(
						action, id: id, diaryID: diary.id, selectionID: selectionID,
						content: contentsByID[id]
					)
				} else {
					let queuedID = try await performBulkEntryAction(
						action, id: id, diaryID: diary.id, selectionID: selectionID,
						content: contentsByID[id]
					)
					if let queuedID { queuedSources[id] = queuedID }
				}
				result.succeededIDs.insert(id)
			} catch {
				result.failedIDs.insert(id)
				result.errorsByID[id] = error.localizedDescription
			}
		}
		if let store, !queuedSources.isEmpty {
			try? await store.synchronize(with: client)
			let pending = Set(await store.pendingEntryWrites().map(\.id))
			if bulkDiaryIsCurrent(diary.id, selectionID: selectionID) {
				entryPendingCreationIDs.subtract(Set(queuedSources.values).subtracting(pending))
			}
			for (sourceID, writeID) in queuedSources where pending.contains(writeID) {
				result.queuedIDs.insert(sourceID)
			}
			if bulkDiaryIsCurrent(diary.id, selectionID: selectionID) {
				await refreshEntriesFromStore(store, diaryID: diary.id)
			}
		}
		return result
	}

	nonisolated private enum BulkOperationError: LocalizedError {
		case unavailable
		case pendingCreation
		var errorDescription: String? {
			switch self {
			case .unavailable: "This action is no longer available for the selected item."
			case .pendingCreation:
				"This entry must finish syncing before it can be moved to Trash, restored, or permanently deleted."
			}
		}
	}

	private func bulkDiaryIsCurrent(_ diaryID: String, selectionID: UUID?) -> Bool {
		guard case .entries(let diary, _) = screen else { return false }
		return diary.id == diaryID && diarySelectionID == selectionID
	}

	private func mergeBulkEntry(
		_ updated: ThingsDiaryEntry, removing: Bool = false, selectionID: UUID?
	) {
		guard bulkDiaryIsCurrent(updated.diaryID, selectionID: selectionID),
			case .entries(let diary, var entries) = screen
		else { return }
		if removing {
			entries.removeAll { $0.id == updated.id }
		} else if let index = entries.firstIndex(where: { $0.id == updated.id }) {
			entries[index] = updated
		} else {
			entries.append(updated)
		}
		screen = .entries(diary: diary, entries: entries)
	}

	private func performBulkEntryAction(
		_ action: WorkspaceBulkAction, id: String, diaryID: String,
		selectionID: UUID?, content: String?
	) async throws -> String? {
		let hasPendingCreate: Bool
		if let store {
			hasPendingCreate = await store.pendingEntryWrites().contains {
				$0.id == id && $0.operation == .create
			}
		} else {
			hasPendingCreate = false
		}
		guard bulkDiaryIsCurrent(diaryID, selectionID: selectionID),
			case .entries(_, let entries) = screen,
			let entry = entries.first(where: { $0.id == id && $0.diaryID == diaryID }),
			!entryDraftIDs.contains(id) || action == .saveContents || action == .duplicate || action == .saveAsTemplate
		else { throw BulkOperationError.unavailable }
		if hasPendingCreate || entryPendingCreationIDs.contains(id),
			action == .moveToTrash || action == .restore || action == .deletePermanently
		{
			throw BulkOperationError.pendingCreation
		}
		let isDeleted = entry.deletedAt != nil
		if isDeleted {
			guard action == .restore || action == .deletePermanently else {
				throw BulkOperationError.unavailable
			}
		} else if action == .restore || action == .deletePermanently || action == .deleteTemplates {
			throw BulkOperationError.unavailable
		}
		if action == .saveAsTemplate {
			let created = try await client.createTemplate(
				diaryID: diaryID, params: ThingsDiaryTemplateParams(content: content ?? entry.content)
			)
			try await store?.upsertTemplate(created)
			if bulkDiaryIsCurrent(diaryID, selectionID: selectionID) { templates.append(created) }
			return nil
		}
		var params = ThingsDiaryEntryParams(
			content: entry.content, topicID: entry.topicID, archived: entry.archived,
			bookmarked: entry.bookmarked, previewHidden: entry.previewHidden
		)
		var operation: PendingEntryOperation =
			hasPendingCreate || entryPendingCreationIDs.contains(id) || entryDraftIDs.contains(id) ? .create : .update
		var deletedAt = entry.deletedAt
		var destinationID = entry.id
		let now = Date()
		switch action {
		case .saveContents:
			guard let content else { throw BulkOperationError.unavailable }
			params = ThingsDiaryEntryParams(
				content: content, topicID: entry.topicID,
				archived: entry.archived, bookmarked: entry.bookmarked, previewHidden: entry.previewHidden)
		case .bookmark(let value):
			if entry.bookmarked == value { return nil }
			params = ThingsDiaryEntryParams(
				content: entry.content, topicID: entry.topicID,
				archived: entry.archived, bookmarked: value, previewHidden: entry.previewHidden)
		case .previewHidden(let value):
			guard topics.first(where: { $0.id == entry.topicID })?.entryPreviewable != false else {
				throw BulkOperationError.unavailable
			}
			if entry.previewHidden == value { return nil }
			params = ThingsDiaryEntryParams(
				content: entry.content, topicID: entry.topicID,
				archived: entry.archived, bookmarked: entry.bookmarked, previewHidden: value)
		case .archive(let value):
			if entry.archived == value { return nil }
			params = ThingsDiaryEntryParams(
				content: entry.content, topicID: entry.topicID,
				archived: value, bookmarked: entry.bookmarked, previewHidden: entry.previewHidden)
		case .moveToTopic(let topicID):
			guard topicID == nil || topics.contains(where: { $0.id == topicID && $0.diaryID == diaryID }) else {
				throw BulkOperationError.unavailable
			}
			if entry.topicID == topicID { return nil }
			params = ThingsDiaryEntryParams(
				content: entry.content, topicID: topicID,
				archived: entry.archived, bookmarked: entry.bookmarked, previewHidden: entry.previewHidden)
		case .duplicate:
			destinationID = UUID().uuidString.lowercased()
			operation = .create
			params = ThingsDiaryEntryParams(
				content: content ?? entry.content, topicID: entry.topicID,
				archived: entry.archived, bookmarked: entry.bookmarked, previewHidden: entry.previewHidden)
		case .moveToTrash:
			operation = .delete
			deletedAt = now
		case .restore:
			operation = .restore
			deletedAt = nil
		case .deletePermanently: operation = .remove
		case .saveAsTemplate, .deleteTemplates: throw BulkOperationError.unavailable
		}
		let localEntry = ThingsDiaryEntry(
			id: destinationID, diaryID: diaryID, content: params.content, topicID: params.topicID,
			archived: params.archived, bookmarked: params.bookmarked, previewHidden: params.previewHidden,
			createdAt: action == .duplicate ? now : entry.createdAt, updatedAt: now, deletedAt: deletedAt,
			version: max(UInt64(now.timeIntervalSince1970 * 1_000), entry.version + 1)
		)
		if let store {
			try await store.savePendingEntry(PendingEntryWrite(operation: operation, entry: localEntry))
			mergeBulkEntry(localEntry, removing: operation == .remove, selectionID: selectionID)
			if action == .saveContents && bulkDiaryIsCurrent(diaryID, selectionID: selectionID) {
				entryDraftIDs.remove(id)
				entryDraftIDsHiddenFromList.remove(id)
				if operation == .create { entryPendingCreationIDs.insert(id) }
			}
			return destinationID
		}
		let updated: ThingsDiaryEntry
		switch action {
		case .saveContents where operation == .create:
			updated = try await client.createEntry(diaryID: diaryID, entryID: id, params: params)
		case .duplicate:
			updated = try await client.createEntry(diaryID: diaryID, params: params)
		case .moveToTrash:
			try await client.deleteEntry(diaryID: diaryID, entryID: id, soft: true)
			updated = localEntry
		case .restore:
			updated = try await client.restoreEntry(diaryID: diaryID, entryID: id)
		case .deletePermanently:
			try await client.deleteEntry(diaryID: diaryID, entryID: id, soft: false)
			updated = localEntry
		default:
			updated = try await client.updateEntry(entry, params: params)
		}
		mergeBulkEntry(updated, removing: action == .deletePermanently, selectionID: selectionID)
		if action == .saveContents && bulkDiaryIsCurrent(diaryID, selectionID: selectionID) {
			entryDraftIDs.remove(id)
			entryDraftIDsHiddenFromList.remove(id)
			entryPendingCreationIDs.remove(id)
		}
		return nil
	}

	private func performBulkTemplateAction(
		_ action: WorkspaceBulkAction, id: String, diaryID: String,
		selectionID: UUID?, content: String?
	) async throws {
		guard let template = templates.first(where: { $0.id == id && $0.diaryID == diaryID }),
			!templateDraftIDs.contains(id) || action == .saveContents || action == .duplicate
				|| action == .deleteTemplates
		else { throw BulkOperationError.unavailable }
		switch action {
		case .saveContents:
			guard let content else { throw BulkOperationError.unavailable }
			let updated = try await client.updateTemplate(template, params: ThingsDiaryTemplateParams(content: content))
			try await store?.upsertTemplate(updated)
			if bulkDiaryIsCurrent(diaryID, selectionID: selectionID) {
				templates = templates.map { $0.id == updated.id ? updated : $0 }
				templateDraftIDs.remove(id)
			}
		case .duplicate:
			let created = try await client.createTemplate(
				diaryID: diaryID, params: ThingsDiaryTemplateParams(content: content ?? template.content)
			)
			try await store?.upsertTemplate(created)
			if bulkDiaryIsCurrent(diaryID, selectionID: selectionID) { templates.append(created) }
		case .deleteTemplates:
			for topic in topics.filter({ $0.defaultTemplateID == id }) {
				guard bulkDiaryIsCurrent(diaryID, selectionID: selectionID) else {
					throw BulkOperationError.unavailable
				}
				let updated = try await client.updateTopic(
					topic,
					params: ThingsDiaryTopicParams(
						title: topic.title, description: topic.description, color: topic.color,
						entryPreviewable: topic.entryPreviewable, defaultTemplateID: nil))
				try await store?.upsertTopic(updated)
				if bulkDiaryIsCurrent(diaryID, selectionID: selectionID) {
					topics = topics.map { $0.id == updated.id ? updated : $0 }
				}
			}
			guard bulkDiaryIsCurrent(diaryID, selectionID: selectionID) else {
				throw BulkOperationError.unavailable
			}
			try await client.deleteTemplate(diaryID: diaryID, templateID: id, soft: true)
			try await store?.removeTemplate(diaryID: diaryID, templateID: id)
			if bulkDiaryIsCurrent(diaryID, selectionID: selectionID) {
				templates.removeAll { $0.id == id }
				templateDraftIDs.remove(id)
			}
		default: throw BulkOperationError.unavailable
		}
	}

	@discardableResult
	private func saveEntry(
		_ entry: ThingsDiaryEntry,
		params: ThingsDiaryEntryParams
	) async -> Bool {
		guard case .entries(let diary, let entries) = screen else {
			return false
		}
		if let store {
			let operation: PendingEntryOperation =
				entryPendingCreationIDs.contains(entry.id) ? .create : .update
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
						operation: operation,
						entry: localEntry
					))
				screen = .entries(
					diary: diary,
					entries: entries.map { $0.id == localEntry.id ? localEntry : $0 }
				)
			} catch {
				await refreshEntriesFromStore(store, diaryID: diary.id)
				return false
			}
			do {
				try await store.synchronize(with: client)
				if operation == .create {
					let isStillPending = await store.pendingEntryWrites().contains {
						$0.id == entry.id
					}
					if !isStillPending {
						entryPendingCreationIDs.remove(entry.id)
					}
				}
			} catch {}
			await refreshEntriesFromStore(store, diaryID: diary.id)
			return true
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
			return true
		} catch {
			screen = .entries(diary: diary, entries: entries)
			return false
		}
	}

	private func refreshEntriesFromStore(_ store: DiaryStore, diaryID: String) async {
		let storedEntries = await store.entries(diaryID: diaryID)
		guard case .entries(let diary, let currentEntries) = screen,
			diary.id == diaryID
		else { return }
		screen = .entries(
			diary: diary,
			entries: entriesPreservingTransientEntries(storedEntries, from: currentEntries)
		)
	}

	private func entriesPreservingTransientEntries(
		_ storedEntries: [ThingsDiaryEntry],
		from currentEntries: [ThingsDiaryEntry]
	) -> [ThingsDiaryEntry] {
		let storedEntryIDs = Set(storedEntries.map(\.id))
		let transientEntryIDs = entryDraftIDs.union(entryPendingCreationIDs)
		let transientEntries = currentEntries.filter {
			transientEntryIDs.contains($0.id) && !storedEntryIDs.contains($0.id)
		}
		return storedEntries + transientEntries
	}

	func register() async {
		guard canRegister else {
			password = ""
			passwordConfirmation = ""
			screen = .error(
				"Enter a valid email and matching passwords with at least 8 characters."
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
			self.passwordConfirmation = ""
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
		} catch let ThingsDiaryClientError.httpStatus(status, body) where status == 400 {
			let reason = Self.serverErrorReason(from: body)
			screen = .error(
				reason.map { "Registration failed: \($0)" }
					?? "Registration failed. Check the email and password and try again.")
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
			try await startRealtimeSession()
			let diaries = try await client.diaries()
			isAuthenticated = true
			await routeToDiaries(diaries)
		} catch let ThingsDiaryClientError.httpStatus(status, body) where status == 400 {
			let reason = Self.serverErrorReason(from: body)
			screen = .error(
				reason.map { "Sign in failed: \($0)" }
					?? "Sign in failed. Check your credentials and try again.")
		} catch {
			screen = .error("Could not sign in or load diaries. Check your credentials and try again.")
		}
	}

	func retry() {
		screen = .login
	}

	private func startRealtimeSession() async throws {
		if realtimeCoordinator == nil {
			realtimeCoordinator = RealtimeSyncCoordinator(
				client: client,
				store: store,
				onSnapshot: { [weak self] event, snapshot in
					self?.applyRealtimeEvent(event, snapshot: snapshot)
				}
			)
		}
		try await realtimeCoordinator?.start()
	}

	private func applyRealtimeEvent(
		_ event: ThingsDiaryRealtimeEvent,
		snapshot: DiaryStoreSnapshot?
	) {
		if screen == .loading {
			deferredRealtimeUpdates.append((event, snapshot))
			if deferredRealtimeUpdates.count > 256 {
				deferredRealtimeUpdates.removeFirst()
			}
			return
		}

		switch event.update {
		case .upsertDiary(let updated):
			if let index = loadedDiaries.firstIndex(where: { $0.id == updated.id }) {
				guard updated.version >= loadedDiaries[index].version else { return }
				loadedDiaries[index] = updated
			} else {
				loadedDiaries.append(updated)
			}
		case .removeDiary(let id, let version):
			if let diary = loadedDiaries.first(where: { $0.id == id }),
				version < diary.version
			{
				return
			}
			loadedDiaries.removeAll { $0.id == id }
			if case .entries(let diary, _) = screen, diary.id == id {
				topics = []
				templates = []
				entryDraftIDs = []
				entryDraftIDsHiddenFromList = []
				entryPendingCreationIDs = []
				templateDraftIDs = []
				screen = .diaries(loadedDiaries)
			}
			return
		case .upsertEntry(let entry):
			applyRealtimeEntry(entry)
		case .removeEntry(let diaryID, let id, let version):
			removeRealtimeEntry(diaryID: diaryID, id: id, version: version)
		case .upsertTopic(let topic):
			guard currentDiaryID == topic.diaryID else { break }
			if topic.deletedAt != nil {
				topics.removeAll { $0.id == topic.id }
			} else {
				upsertVersioned(
					topic,
					in: &topics,
					id: \ThingsDiaryTopic.id,
					version: \ThingsDiaryTopic.version
				)
			}
		case .removeTopic(let diaryID, let id, let version):
			guard currentDiaryID == diaryID else { break }
			if let topic = topics.first(where: { $0.id == id }), topic.version > version { break }
			topics.removeAll { $0.id == id }
		case .upsertTemplate(let template):
			guard currentDiaryID == template.diaryID else { break }
			upsertVersioned(
				template,
				in: &templates,
				id: \ThingsDiaryTemplate.id,
				version: \ThingsDiaryTemplate.version
			)
		case .removeTemplate(let diaryID, let id, let version):
			guard currentDiaryID == diaryID else { break }
			if let template = templates.first(where: { $0.id == id }),
				template.version > version
			{
				break
			}
			templates.removeAll { $0.id == id }
		}

		if let snapshot {
			applyRealtimeSnapshot(snapshot)
		}
	}

	private func drainDeferredRealtimeUpdates() {
		guard !isDrainingRealtimeUpdates, !deferredRealtimeUpdates.isEmpty else { return }
		isDrainingRealtimeUpdates = true
		defer { isDrainingRealtimeUpdates = false }

		let updates = deferredRealtimeUpdates
		deferredRealtimeUpdates.removeAll(keepingCapacity: true)
		for update in updates {
			switch update.0.update {
			case .upsertDiary, .removeDiary:
				applyRealtimeEvent(update.0, snapshot: update.1)
			default:
				if currentDiaryID == update.0.update.diaryID {
					applyRealtimeEvent(update.0, snapshot: update.1)
				} else {
					deferredRealtimeUpdates.append(update)
				}
			}
		}
	}

	private var currentDiaryID: String? {
		guard case .entries(let diary, _) = screen else { return nil }
		return diary.id
	}

	private func applyRealtimeEntry(_ entry: ThingsDiaryEntry) {
		guard case .entries(let diary, let entries) = screen,
			diary.id == entry.diaryID,
			!entryDraftIDs.contains(entry.id)
		else { return }
		if let current = entries.first(where: { $0.id == entry.id }),
			current.version > entry.version
		{
			return
		}
		screen = .entries(
			diary: diary,
			entries: entries.filter { $0.id != entry.id } + [entry]
		)
	}

	private func removeRealtimeEntry(diaryID: String, id: String, version: UInt64) {
		guard case .entries(let diary, let entries) = screen,
			diary.id == diaryID,
			!entryDraftIDs.contains(id)
		else { return }
		if let current = entries.first(where: { $0.id == id }), current.version > version {
			return
		}
		screen = .entries(diary: diary, entries: entries.filter { $0.id != id })
	}

	private func upsertVersioned<Value>(
		_ value: Value,
		in values: inout [Value],
		id: KeyPath<Value, String>,
		version: KeyPath<Value, UInt64>
	) {
		let valueID = value[keyPath: id]
		if let current = values.first(where: { $0[keyPath: id] == valueID }),
			current[keyPath: version] > value[keyPath: version]
		{
			return
		}
		values.removeAll { $0[keyPath: id] == valueID }
		values.append(value)
	}

	private func applyRealtimeSnapshot(_ snapshot: DiaryStoreSnapshot) {
		guard
			case .entries(let diary, let currentEntries) = screen,
			diary.id == snapshot.diary.id
		else { return }
		loadedDiaries = loadedDiaries.map {
			$0.id == snapshot.diary.id ? snapshot.diary : $0
		}
		topics = snapshot.topics.filter { $0.deletedAt == nil }
		templates = snapshot.templates
		screen = .entries(
			diary: snapshot.diary,
			entries: entriesPreservingTransientEntries(
				snapshot.entries,
				from: currentEntries
			)
		)
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
