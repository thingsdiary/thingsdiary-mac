import Foundation
import Testing
import ThingsDiaryClient

@testable import thingsdiary

@MainActor
@Test("Bulk bookmarks set a common value, keep successful writes, and preserve metadata after a partial failure")
func bulkBookmarksKeepPartialSuccess() async {
	let client = BulkTestClient(
		entries: [bulkEntry("a", bookmarked: true), bulkEntry("b"), bulkEntry("c")], rejected: ["b"])
	let model = ThingsDiaryAppModel(client: client)
	await model.selectDiary(bulkDiary)
	let result = await model.performBulkAction(
		.bookmark(true), ids: ["a", "b", "c", "c"], contentsByID: ["c": "Unsaved edit"])
	#expect(result.succeededIDs == ["a", "c"])
	#expect(result.failedIDs == ["b"])
	#expect(result.errorsByID["b"] != nil)
	guard case .entries(_, let entries) = model.screen else {
		Issue.record("Workspace disappeared")
		return
	}
	#expect(entries.filter(\.bookmarked).map(\.id) == ["a", "c"])
	#expect(entries.first(where: { $0.id == "c" })?.content == "Content c")
	#expect(entries.first(where: { $0.id == "c" })?.createdAt == bulkDate)
	#expect(await client.updateIDs == ["b", "c"])
}

@MainActor
@Test("Bulk duplication copies each selected entry once and uses its current draft content")
func bulkDuplicatesUseDraftContent() async {
	let client = BulkTestClient(entries: [bulkEntry("a", bookmarked: true), bulkEntry("b")])
	let model = ThingsDiaryAppModel(client: client)
	await model.selectDiary(bulkDiary)
	let result = await model.performBulkAction(.duplicate, ids: ["a", "b", "a"], contentsByID: ["a": "Edited a"])
	#expect(result.succeededIDs == ["a", "b"])
	#expect(await client.createdEntryParams.map(\.content) == ["Edited a", "Content b"])
	#expect(await client.createdEntryParams.map(\.bookmarked) == [true, false])
	guard case .entries(_, let entries) = model.screen else {
		Issue.record("Workspace disappeared")
		return
	}
	#expect(entries.count == 4)
	#expect(entries.first?.content == "Content a")
}

@MainActor
@Test("Bulk Save as Template creates one template per selected entry and keeps successful templates after a failure")
func bulkSaveAsTemplateCreatesOnePerEntry() async {
	let client = BulkTestClient(
		entries: [bulkEntry("a"), bulkEntry("b"), bulkEntry("c")], rejectedTemplateContents: ["Content b"])
	let model = ThingsDiaryAppModel(client: client)
	await model.selectDiary(bulkDiary)
	let result = await model.performBulkAction(.saveAsTemplate, ids: ["a", "b", "c"], contentsByID: ["a": "Edited a"])
	#expect(result.succeededIDs == ["a", "c"])
	#expect(result.failedIDs == ["b"])
	#expect(model.templates.map(\.content) == ["Edited a", "Content c"])
	guard case .entries(_, let entries) = model.screen else {
		Issue.record("Workspace disappeared")
		return
	}
	#expect(entries.count == 3)
}

@MainActor
@Test("Bulk preview changes reject topic restrictions without failing eligible entries")
func bulkPreviewRespectsTopicPolicy() async {
	let topic = bulkTopic(id: "private", previewable: false)
	let client = BulkTestClient(entries: [bulkEntry("a", topicID: "private"), bulkEntry("b")], topics: [topic])
	let model = ThingsDiaryAppModel(client: client)
	await model.selectDiary(bulkDiary)
	let result = await model.performBulkAction(.previewHidden(true), ids: ["a", "b"])
	#expect(result.failedIDs == ["a"])
	#expect(result.succeededIDs == ["b"])
	guard case .entries(_, let entries) = model.screen else {
		Issue.record("Workspace disappeared")
		return
	}
	#expect(entries.first(where: { $0.id == "a" })?.previewHidden == false)
	#expect(entries.first(where: { $0.id == "b" })?.previewHidden == true)
}

@MainActor
@Test("Bulk topic assignment sets one destination and skips entries already in that topic")
func bulkTopicAssignmentUsesOneDestination() async {
	let client = BulkTestClient(
		entries: [bulkEntry("a", topicID: "target"), bulkEntry("b")], topics: [bulkTopic(id: "target")])
	let model = ThingsDiaryAppModel(client: client)
	await model.selectDiary(bulkDiary)
	let result = await model.performBulkAction(.moveToTopic("target"), ids: ["a", "b", "missing"])
	#expect(result.succeededIDs == ["a", "b"])
	#expect(result.failedIDs == ["missing"])
	#expect(await client.updateIDs == ["b"])
	guard case .entries(_, let entries) = model.screen else {
		Issue.record("Workspace disappeared")
		return
	}
	#expect(entries.allSatisfy { $0.topicID == "target" && $0.createdAt == bulkDate })
}

@MainActor
@Test("Bulk trash and restore preserve the archive flag and permanent deletion only accepts trashed entries")
func bulkTrashAndRestorePreserveArchive() async {
	let client = BulkTestClient(entries: [bulkEntry("a", archived: true), bulkEntry("b")])
	let model = ThingsDiaryAppModel(client: client)
	await model.selectDiary(bulkDiary)
	#expect(await model.performBulkAction(.moveToTrash, ids: ["a", "b"]).succeededIDs == ["a", "b"])
	#expect(await model.performBulkAction(.restore, ids: ["a"]).succeededIDs == ["a"])
	let removed = await model.performBulkAction(.deletePermanently, ids: ["a", "b"])
	#expect(removed.failedIDs == ["a"])
	#expect(removed.succeededIDs == ["b"])
	guard case .entries(_, let entries) = model.screen else {
		Issue.record("Workspace disappeared")
		return
	}
	#expect(entries.map(\.id) == ["a"])
	#expect(entries.first?.archived == true)
	#expect(entries.first?.deletedAt == nil)
}

@MainActor
@Test("Bulk offline writes stay visible, retain dates, and report queued source IDs")
func bulkOfflineChangesAreQueued() async throws {
	let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent(
		"store.json")
	defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
	let store = try DiaryStore(fileURL: url)
	let client = BulkTestClient(entries: [bulkEntry("a"), bulkEntry("b")], rejected: ["a", "b"])
	let model = ThingsDiaryAppModel(client: client, store: store)
	await model.selectDiary(bulkDiary)
	let result = await model.performBulkAction(.archive(true), ids: ["a", "b"])
	#expect(result.succeededIDs == ["a", "b"])
	#expect(result.failedIDs.isEmpty)
	#expect(result.queuedIDs == ["a", "b"])
	#expect(await store.pendingEntryWrites().count == 2)
	guard case .entries(_, let entries) = model.screen else {
		Issue.record("Workspace disappeared")
		return
	}
	#expect(entries.allSatisfy { $0.archived && $0.createdAt == bulkDate })
}

@MainActor
@Test("Bulk template deletion clears topic defaults and only removes successful templates")
func bulkTemplateDeletionClearsDefaults() async {
	let first = bulkTemplate(id: "one", content: "One")
	let second = bulkTemplate(id: "two", content: "Two")
	let client = BulkTestClient(
		entries: [], topics: [bulkTopic(id: "topic", defaultTemplateID: "one")], templates: [first, second],
		rejected: ["two"])
	let model = ThingsDiaryAppModel(client: client)
	await model.selectDiary(bulkDiary)
	let result = await model.performBulkAction(.deleteTemplates, ids: ["one", "two"], templates: true)
	#expect(result.succeededIDs == ["one"])
	#expect(result.failedIDs == ["two"])
	#expect(model.templates.map(\.id) == ["two"])
	#expect(model.topics.first?.defaultTemplateID == nil)
	guard case .entries = model.screen else {
		Issue.record("Workspace disappeared")
		return
	}
}

@MainActor
@Test("Bulk template duplication uses draft content and creates separate templates")
func bulkTemplateDuplicationUsesDrafts() async {
	let client = BulkTestClient(
		entries: [], templates: [bulkTemplate(id: "one", content: "One"), bulkTemplate(id: "two", content: "Two")])
	let model = ThingsDiaryAppModel(client: client)
	await model.selectDiary(bulkDiary)
	let result = await model.performBulkAction(
		.duplicate, ids: ["one", "two"], templates: true, contentsByID: ["one": "Edited one"])
	#expect(result.succeededIDs == ["one", "two"])
	#expect(model.templates.map(\.content) == ["One", "Two", "Edited one", "Two"])
}

@MainActor
@Test("Bulk draft saving reports failures without hiding the workspace or losing other edits")
func bulkSaveContentsKeepsPartialSuccess() async {
	let client = BulkTestClient(entries: [bulkEntry("a"), bulkEntry("b")], rejected: ["b"])
	let model = ThingsDiaryAppModel(client: client)
	await model.selectDiary(bulkDiary)
	let result = await model.performBulkAction(
		.saveContents, ids: ["a", "b"], contentsByID: ["a": "Edited a", "b": "Edited b"])
	#expect(result.succeededIDs == ["a"])
	#expect(result.failedIDs == ["b"])
	guard case .entries(_, let entries) = model.screen else {
		Issue.record("Workspace disappeared")
		return
	}
	#expect(entries.first(where: { $0.id == "a" })?.content == "Edited a")
	#expect(entries.first(where: { $0.id == "b" })?.content == "Content b")
}

@MainActor
@Test("Bulk saving an ephemeral entry keeps its ID and promotes it only after success")
func bulkSaveContentsPromotesEphemeralEntry() async throws {
	let client = BulkTestClient(entries: [])
	let model = ThingsDiaryAppModel(client: client)
	await model.selectDiary(bulkDiary)
	let draft = try #require(model.beginEntryDraft(appearsInList: true))
	let result = await model.performBulkAction(.saveContents, ids: [draft.id], contentsByID: [draft.id: "Saved draft"])
	#expect(result.succeededIDs == [draft.id])
	#expect(!model.entryDraftIDs.contains(draft.id))
	guard case .entries(_, let entries) = model.screen else {
		Issue.record("Workspace disappeared")
		return
	}
	#expect(entries.first?.id == draft.id)
	#expect(entries.first?.content == "Saved draft")
}

@MainActor
@Test("Bulk saving template drafts updates their contents before a destructive action")
func bulkSaveTemplateContents() async {
	let client = BulkTestClient(entries: [], templates: [bulkTemplate(id: "one", content: "One")])
	let model = ThingsDiaryAppModel(client: client)
	await model.selectDiary(bulkDiary)
	let result = await model.performBulkAction(
		.saveContents, ids: ["one"], templates: true, contentsByID: ["one": "Edited one"])
	#expect(result.succeededIDs == ["one"])
	#expect(model.templates.first?.content == "Edited one")
}

@MainActor
@Test(
	"Bulk metadata preserves an unsynced create and destructive operations reject it without replacing its queue entry")
func bulkUnsyncedCreationSurvivesMetadataAndTrash() async throws {
	let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent(
		"store.json")
	defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
	let store = try DiaryStore(fileURL: url)
	let client = BulkTestClient(entries: [bulkEntry("a")], rejectCreates: true)
	let model = ThingsDiaryAppModel(client: client, store: store)
	await model.selectDiary(bulkDiary)
	let duplicated = await model.performBulkAction(.duplicate, ids: ["a"])
	#expect(duplicated.queuedIDs == ["a"])
	let copyID = try #require(await store.pendingEntryWrites().first?.id)
	let bookmarked = await model.performBulkAction(.bookmark(true), ids: [copyID])
	#expect(bookmarked.queuedIDs == [copyID])
	#expect(await store.pendingEntryWrites().first?.operation == .create)
	#expect(await store.pendingEntryWrites().first?.entry.bookmarked == true)
	for action in [WorkspaceBulkAction.moveToTrash, .restore, .deletePermanently] {
		let result = await model.performBulkAction(action, ids: [copyID])
		#expect(result.failedIDs == [copyID])
		#expect(result.errorsByID[copyID]?.contains("syncing") == true)
		#expect(await store.pendingEntryWrites().first?.operation == .create)
	}
	guard case .entries(_, let entries) = model.screen else {
		Issue.record("Workspace disappeared")
		return
	}
	#expect(entries.first(where: { $0.id == copyID })?.deletedAt == nil)
}

@MainActor
@Test("Bulk deletion removes ephemeral templates without requiring a save")
func bulkDeleteEphemeralTemplates() async throws {
	let client = BulkTestClient(entries: [])
	let model = ThingsDiaryAppModel(client: client)
	await model.selectDiary(bulkDiary)
	let draft = try #require(await model.beginTemplateDraft())
	#expect(model.templateDraftIDs.contains(draft.id))
	let result = await model.performBulkAction(.deleteTemplates, ids: [draft.id], templates: true)
	#expect(result.succeededIDs == [draft.id])
	#expect(model.templates.isEmpty)
	#expect(!model.templateDraftIDs.contains(draft.id))
}

#if DEBUG
	@MainActor
	@Test("Workspace fixture persists trash, restore, and permanent deletion while preserving original attributes")
	func bulkFixtureSupportsEntryLifecycle() async throws {
		let model = ThingsDiaryAppModel.uiTestingWorkspace()
		guard case .entries(let diary, let initial) = model.screen else {
			Issue.record("No fixture workspace")
			return
		}
		let original = try #require(initial.first(where: { $0.id == "fixture-archived-entry" }))
		await model.moveToTrash(original)
		guard case .entries(_, let trashedEntries) = model.screen else {
			Issue.record("Trash replaced workspace with an error")
			return
		}
		let trashed = try #require(trashedEntries.first(where: { $0.id == original.id }))
		#expect(trashed.deletedAt != nil)
		#expect(trashed.archived)
		#expect(trashed.createdAt == original.createdAt)
		await model.restoreEntry(trashed)
		guard case .entries(_, let restoredEntries) = model.screen else {
			Issue.record("Restore replaced workspace with an error")
			return
		}
		let restored = try #require(restoredEntries.first(where: { $0.id == original.id }))
		#expect(restored.deletedAt == nil)
		#expect(restored.archived)
		#expect(restored.content == original.content)
		await model.selectDiary(diary)
		guard case .entries(_, let refreshed) = model.screen else {
			Issue.record("Refresh failed")
			return
		}
		#expect(refreshed.first(where: { $0.id == original.id })?.deletedAt == nil)
		await model.moveToTrash(restored)
		let removed = await model.performBulkAction(.deletePermanently, ids: [original.id])
		#expect(removed.succeededIDs == [original.id])
		await model.selectDiary(diary)
		guard case .entries(_, let remaining) = model.screen else {
			Issue.record("Refresh failed")
			return
		}
		#expect(!remaining.contains(where: { $0.id == original.id }))
	}
#endif

private let bulkDate = Date(timeIntervalSince1970: 100)
private let bulkDiary = ThingsDiaryDiary(
	id: "diary", title: "Diary", description: "", createdAt: bulkDate, updatedAt: bulkDate, version: 1)
private func bulkEntry(_ id: String, topicID: String? = nil, archived: Bool = false, bookmarked: Bool = false)
	-> ThingsDiaryEntry
{
	ThingsDiaryEntry(
		id: id, diaryID: "diary", content: "Content \(id)", topicID: topicID, archived: archived,
		bookmarked: bookmarked, createdAt: bulkDate, updatedAt: bulkDate, version: 1)
}
private func bulkTemplate(id: String, content: String) -> ThingsDiaryTemplate {
	ThingsDiaryTemplate(
		id: id, diaryID: "diary", content: content, createdAt: bulkDate, updatedAt: bulkDate, version: 1)
}
private func bulkTopic(id: String, previewable: Bool = true, defaultTemplateID: String? = nil) -> ThingsDiaryTopic {
	ThingsDiaryTopic(
		id: id, diaryID: "diary", title: id, description: "", color: "blue", entryPreviewable: previewable,
		defaultTemplateID: defaultTemplateID, createdAt: bulkDate, updatedAt: bulkDate, version: 1)
}

private actor BulkTestClient: ThingsDiaryAppClient {
	private enum Failure: Error { case rejected }
	private var storedEntries: [ThingsDiaryEntry]
	private let storedTopics: [ThingsDiaryTopic]
	private let storedTemplates: [ThingsDiaryTemplate]
	private let rejected: Set<String>
	private let rejectedTemplateContents: Set<String>
	private let rejectCreates: Bool
	var updateIDs: [String] = []
	var createdEntryParams: [ThingsDiaryEntryParams] = []
	private var serial = 0

	init(
		entries: [ThingsDiaryEntry], topics: [ThingsDiaryTopic] = [], templates: [ThingsDiaryTemplate] = [],
		rejected: Set<String> = [], rejectedTemplateContents: Set<String> = [],
		rejectCreates: Bool = false
	) {
		storedEntries = entries
		storedTopics = topics
		storedTemplates = templates
		self.rejected = rejected
		self.rejectedTemplateContents = rejectedTemplateContents
		self.rejectCreates = rejectCreates
	}
	func register(login: String, password: String, secretKey: String, kdfSalt: String) async throws
		-> ThingsDiaryPublicKeys
	{ throw Failure.rejected }
	func login(login: String, password: String, secretKey: String) async throws {}
	func diaries() async throws -> [ThingsDiaryDiary] { [bulkDiary] }
	func entries(diaryID: String) async throws -> [ThingsDiaryEntry] { storedEntries }
	func topics(diaryID: String) async throws -> [ThingsDiaryTopic] { storedTopics }
	func templates(diaryID: String) async throws -> [ThingsDiaryTemplate] { storedTemplates }
	func updateEntry(_ entry: ThingsDiaryEntry, params: ThingsDiaryEntryParams) async throws -> ThingsDiaryEntry {
		updateIDs.append(entry.id)
		if rejected.contains(entry.id) { throw Failure.rejected }
		let updated = ThingsDiaryEntry(
			id: entry.id, diaryID: entry.diaryID, content: params.content, topicID: params.topicID,
			archived: params.archived, bookmarked: params.bookmarked, previewHidden: params.previewHidden,
			createdAt: entry.createdAt, updatedAt: .now, deletedAt: entry.deletedAt, version: entry.version + 1)
		storedEntries = storedEntries.map { $0.id == entry.id ? updated : $0 }
		return updated
	}
	func createEntry(diaryID: String, params: ThingsDiaryEntryParams) async throws -> ThingsDiaryEntry {
		createdEntryParams.append(params)
		serial += 1
		let created = ThingsDiaryEntry(
			id: "copy-\(serial)", diaryID: diaryID, content: params.content, topicID: params.topicID,
			archived: params.archived, bookmarked: params.bookmarked, previewHidden: params.previewHidden,
			createdAt: .now, updatedAt: .now, version: 1)
		storedEntries.append(created)
		return created
	}
	func createEntry(diaryID: String, entryID: String, params: ThingsDiaryEntryParams) async throws -> ThingsDiaryEntry
	{
		if rejectCreates { throw Failure.rejected }
		let entry = ThingsDiaryEntry(
			id: entryID, diaryID: diaryID, content: params.content, topicID: params.topicID, archived: params.archived,
			bookmarked: params.bookmarked, previewHidden: params.previewHidden, createdAt: .now, updatedAt: .now,
			version: 1)
		storedEntries.append(entry)
		return entry
	}
	func updateTemplate(_ template: ThingsDiaryTemplate, params: ThingsDiaryTemplateParams) async throws
		-> ThingsDiaryTemplate
	{
		if rejected.contains(template.id) { throw Failure.rejected }
		return bulkTemplate(id: template.id, content: params.content)
	}

	func createTemplate(diaryID: String, params: ThingsDiaryTemplateParams) async throws -> ThingsDiaryTemplate {
		if rejectedTemplateContents.contains(params.content) { throw Failure.rejected }
		serial += 1
		return bulkTemplate(id: "template-\(serial)", content: params.content)
	}
	func deleteEntry(diaryID: String, entryID: String, soft: Bool?) async throws {
		if rejected.contains(entryID) { throw Failure.rejected }
		guard let entry = storedEntries.first(where: { $0.id == entryID }) else { throw Failure.rejected }
		storedEntries.removeAll { $0.id == entryID }
		if soft == true {
			storedEntries.append(
				ThingsDiaryEntry(
					id: entry.id, diaryID: diaryID, content: entry.content, topicID: entry.topicID,
					archived: entry.archived, bookmarked: entry.bookmarked, previewHidden: entry.previewHidden,
					createdAt: entry.createdAt, updatedAt: .now, deletedAt: .now, version: entry.version + 1))
		}
	}
	func restoreEntry(diaryID: String, entryID: String) async throws -> ThingsDiaryEntry {
		guard let entry = storedEntries.first(where: { $0.id == entryID }) else { throw Failure.rejected }
		return ThingsDiaryEntry(
			id: entry.id, diaryID: diaryID, content: entry.content, topicID: entry.topicID, archived: entry.archived,
			bookmarked: entry.bookmarked, previewHidden: entry.previewHidden, createdAt: entry.createdAt,
			updatedAt: .now, version: entry.version + 1)
	}
	func deleteTemplate(diaryID: String, templateID: String, soft: Bool?) async throws {
		if rejected.contains(templateID) { throw Failure.rejected }
	}
	func updateTopic(_ topic: ThingsDiaryTopic, params: ThingsDiaryTopicParams) async throws -> ThingsDiaryTopic {
		ThingsDiaryTopic(
			id: topic.id, diaryID: topic.diaryID, title: params.title, description: params.description,
			color: params.color, entryPreviewable: params.entryPreviewable, defaultTemplateID: params.defaultTemplateID,
			createdAt: topic.createdAt, updatedAt: .now, version: topic.version + 1)
	}
}
