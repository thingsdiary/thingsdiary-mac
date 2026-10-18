import Foundation
import ThingsDiaryClient

nonisolated enum EntrySection: String, CaseIterable, Identifiable {
	case entries = "Entries"
	case bookmarks = "Bookmarks"
	case archive = "Archive"
	case trash = "Trash"

	var id: Self { self }
}

nonisolated enum EntrySort: String, CaseIterable, Identifiable {
	case newest = "Newest"
	case oldest = "Oldest"

	var id: Self { self }
}

nonisolated enum DiaryNavigationSelection: Hashable {
	case entries
	case bookmarks
	case topic(String)
	case archive
	case trash
}

nonisolated let minimumEntryListWidth: CGFloat = 260
nonisolated let minimumEntryEditorWidth: CGFloat = 420
nonisolated let entryListDividerWidth: CGFloat = 9
nonisolated let minimumEntryTabWidth: CGFloat = 92
nonisolated let maximumEntryTabWidth: CGFloat = 170
nonisolated let entryTabSpacing: CGFloat = 3
nonisolated let entryTabLeadingPadding: CGFloat = 6
nonisolated let entryTabCreateButtonWidth: CGFloat = 30
nonisolated let entryTabCreateButtonSpacing = entryTabSpacing
nonisolated let workspaceTitlebarHeight: CGFloat = 46
nonisolated let editorWorkspaceFocusHysteresis: CGFloat = 60
nonisolated let minimumSplitWorkspaceWidth =
	minimumEntryListWidth + entryListDividerWidth + minimumEntryEditorWidth
nonisolated let minimumDiaryOverviewWidth: CGFloat = 620

nonisolated func diarySettingsVisible(
	for diaryID: String,
	firstDiaryID: String?,
	hoveredDiaryID: String?
) -> Bool {
	diaryID == (hoveredDiaryID ?? firstDiaryID)
}

nonisolated struct EntryTabsState: Equatable {
	var openEntryIDs: [String] = []
	var activeEntryID: String?
	var pinnedEntryIDs: Set<String> = []
	var previewEntryID: String?

	mutating func open(_ entryID: String) {
		if !openEntryIDs.contains(entryID) {
			openEntryIDs.append(entryID)
		}
		promote(entryID)
		activeEntryID = entryID
	}

	mutating func preview(_ entryID: String) {
		if openEntryIDs.contains(entryID) {
			activeEntryID = entryID
			if previewEntryID == entryID {
				promote(entryID)
			}
			return
		}

		if let previewEntryID,
			let previewIndex = openEntryIDs.firstIndex(of: previewEntryID)
		{
			openEntryIDs[previewIndex] = entryID
		} else {
			openEntryIDs.append(entryID)
		}
		previewEntryID = entryID
		activeEntryID = entryID
	}

	mutating func promote(_ entryID: String) {
		guard previewEntryID == entryID else { return }
		previewEntryID = nil
	}

	func isPreview(_ entryID: String) -> Bool {
		previewEntryID == entryID
	}

	mutating func close(_ entryID: String) {
		guard let index = openEntryIDs.firstIndex(of: entryID) else { return }
		openEntryIDs.remove(at: index)
		pinnedEntryIDs.remove(entryID)
		if previewEntryID == entryID {
			previewEntryID = nil
		}
		guard activeEntryID == entryID else { return }
		activeEntryID = openEntryIDs.indices.contains(index) ? openEntryIDs[index] : openEntryIDs.last
	}

	mutating func togglePin(_ entryID: String) {
		guard openEntryIDs.contains(entryID) else { return }
		promote(entryID)
		if pinnedEntryIDs.remove(entryID) == nil {
			pinnedEntryIDs.insert(entryID)
		}
		normalizePinnedOrder()
	}

	func isPinned(_ entryID: String) -> Bool {
		pinnedEntryIDs.contains(entryID)
	}

	func closeableOtherEntryIDs(keeping entryID: String) -> [String] {
		openEntryIDs.filter { $0 != entryID && !isPinned($0) }
	}

	mutating func move(_ entryID: String, to destinationIndex: Int) {
		guard let sourceIndex = openEntryIDs.firstIndex(of: entryID) else { return }
		let range = reorderRange(for: entryID)
		let entryID = openEntryIDs.remove(at: sourceIndex)
		let index = min(max(destinationIndex, range.lowerBound), range.upperBound)
		openEntryIDs.insert(entryID, at: index)
	}

	func reorderRange(for entryID: String) -> ClosedRange<Int> {
		let pinnedCount = pinnedEntryIDs.count
		if isPinned(entryID) {
			return 0...max(pinnedCount - 1, 0)
		}
		return min(pinnedCount, openEntryIDs.count - 1)...max(openEntryIDs.count - 1, pinnedCount)
	}

	mutating func reconcile(validEntryIDs: Set<String>) {
		openEntryIDs.removeAll { !validEntryIDs.contains($0) }
		pinnedEntryIDs.formIntersection(validEntryIDs)
		if let previewEntryID, !validEntryIDs.contains(previewEntryID) {
			self.previewEntryID = nil
		}
		if let activeEntryID, !validEntryIDs.contains(activeEntryID) {
			self.activeEntryID = openEntryIDs.last
		}
	}

	private mutating func normalizePinnedOrder() {
		openEntryIDs =
			openEntryIDs.filter(pinnedEntryIDs.contains)
			+ openEntryIDs.filter { !pinnedEntryIDs.contains($0) }
	}
}

nonisolated enum EntryTabCloseDisposition: Equatable {
	case close
	case confirmDiscard
}

nonisolated func entryTabCloseDisposition(
	persistedContent: String,
	draftContent: String
) -> EntryTabCloseDisposition {
	draftContent == persistedContent ? .close : .confirmDiscard
}

nonisolated struct EntryTabReorderSession: Equatable {
	let entryID: String
	let startIndex: Int
	private(set) var placeholderIndex: Int
	private(set) var translation: CGFloat = 0

	init(entryID: String, startIndex: Int) {
		self.entryID = entryID
		self.startIndex = startIndex
		placeholderIndex = startIndex
	}

	mutating func update(
		translation: CGFloat,
		tabWidth: CGFloat,
		tabCount: Int,
		allowedRange: ClosedRange<Int>? = nil
	) {
		self.translation = translation
		let destination = entryTabReorderDestination(
			startIndex: startIndex,
			translation: translation,
			tabWidth: tabWidth,
			tabCount: tabCount
		)
		if let allowedRange {
			placeholderIndex = min(
				max(destination, allowedRange.lowerBound),
				allowedRange.upperBound
			)
		} else {
			placeholderIndex = destination
		}
	}

	func previewOrder(in entryIDs: [String]) -> [String] {
		var preview = entryIDs.filter { $0 != entryID }
		preview.insert(entryID, at: min(max(placeholderIndex, 0), preview.count))
		return preview
	}

	func offset(forTabAt index: Int, tabWidth: CGFloat) -> CGFloat {
		let step = tabWidth + entryTabSpacing
		if index == startIndex {
			return translation
		}
		if placeholderIndex < startIndex, placeholderIndex..<startIndex ~= index {
			return step
		}
		if placeholderIndex > startIndex, (startIndex + 1)...placeholderIndex ~= index {
			return -step
		}
		return 0
	}

	func commit(to tabs: inout EntryTabsState) {
		tabs.move(entryID, to: placeholderIndex)
	}
}

nonisolated func effectiveEntryListWidth(
	preferredWidth: CGFloat,
	availableWidth: CGFloat
) -> CGFloat {
	let maximumWidth = min(440, availableWidth - entryListDividerWidth - minimumEntryEditorWidth)
	return min(max(preferredWidth, minimumEntryListWidth), max(maximumWidth, minimumEntryListWidth))
}

nonisolated func adaptiveEntryTabWidth(
	availableWidth: CGFloat,
	tabCount: Int
) -> CGFloat {
	guard tabCount > 0 else { return maximumEntryTabWidth }
	let separatorsWidth = CGFloat(max(tabCount - 1, 0)) * entryTabSpacing
	let fittedWidth = floor((max(availableWidth, 0) - separatorsWidth) / CGFloat(tabCount))
	return min(maximumEntryTabWidth, max(minimumEntryTabWidth, fittedWidth))
}

nonisolated func entryTabsContentWidth(tabWidth: CGFloat, tabCount: Int) -> CGFloat {
	guard tabCount > 0 else { return 0 }
	return entryTabLeadingPadding
		+ CGFloat(tabCount) * tabWidth
		+ CGFloat(tabCount - 1) * entryTabSpacing
}

nonisolated func entryTabCreateButtonOffset(
	availableWidth: CGFloat,
	tabsContentWidth: CGFloat
) -> CGFloat {
	let naturalOffset = max(
		tabsContentWidth + entryTabCreateButtonSpacing,
		entryTabLeadingPadding
	)
	let pinnedOffset = max(
		availableWidth - entryTabCreateButtonWidth,
		entryTabLeadingPadding
	)
	return min(naturalOffset, pinnedOffset)
}

nonisolated func entryTabCreateButtonIsPinned(
	availableWidth: CGFloat,
	tabsContentWidth: CGFloat
) -> Bool {
	let naturalOffset = max(
		tabsContentWidth + entryTabCreateButtonSpacing,
		entryTabLeadingPadding
	)
	let pinnedOffset = max(
		availableWidth - entryTabCreateButtonWidth,
		entryTabLeadingPadding
	)
	return naturalOffset >= pinnedOffset
}

nonisolated func shouldHideEntryTabCreateButton(
	isReordering: Bool,
	isPinned: Bool
) -> Bool {
	isReordering && !isPinned
}

nonisolated func reconciledEntryDraftAfterSave(
	currentDraft: String,
	submittedContent: String,
	persistedContent: String
) -> String? {
	guard currentDraft == submittedContent else { return nil }
	let normalizedSubmission = submittedContent.trimmingCharacters(
		in: .whitespacesAndNewlines
	)
	guard persistedContent == normalizedSubmission else { return nil }
	return persistedContent
}

nonisolated func entryTabReorderDestination(
	startIndex: Int,
	translation: CGFloat,
	tabWidth: CGFloat,
	tabCount: Int
) -> Int {
	guard tabCount > 0 else { return 0 }
	let step = max(tabWidth + entryTabSpacing, 1)
	let displacedTabs = Int((translation / step).rounded())
	return min(max(startIndex + displacedTabs, 0), tabCount - 1)
}

nonisolated enum CompactWorkspacePane: Equatable {
	case list
	case editor
}

nonisolated enum EntryWorkspaceLayout: Equatable {
	case listOnly
	case split
	case editorOnly
}

nonisolated func updatedEditorWorkspaceCompactState(
	isCompact: Bool,
	hasSelectedEntry: Bool,
	availableWidth: CGFloat,
	isDragging: Bool
) -> Bool {
	guard hasSelectedEntry else { return false }
	guard !isDragging else { return isCompact }
	if isCompact {
		return availableWidth < minimumSplitWorkspaceWidth + editorWorkspaceFocusHysteresis
	}
	return availableWidth < minimumSplitWorkspaceWidth
}

nonisolated func entryWorkspaceLayout(
	selectionIsEmpty: Bool,
	hasSelectedEntry: Bool,
	availableWidth: CGFloat,
	isEditorFocusMode: Bool,
	isCompact: Bool,
	compactPane: CompactWorkspacePane
) -> EntryWorkspaceLayout {
	guard !selectionIsEmpty else { return .listOnly }
	if hasSelectedEntry {
		if isEditorFocusMode { return .editorOnly }
		guard !isCompact else {
			return compactPane == .editor ? .editorOnly : .listOnly
		}
		return .split
	}
	return availableWidth >= minimumDiaryOverviewWidth ? .split : .listOnly
}

nonisolated enum EntryAction: Equatable {
	case bookmark
	case toggleBookmark
	case toggleArchive
	case archive
	case duplicate
	case moveToTopic
	case moveToTrash
	case restore
	case deletePermanently
}

nonisolated enum EntryDropDestination: Hashable {
	case bookmarks
	case topic(String)
	case archive
	case trash
}

nonisolated enum EntryActionRequest: Equatable {
	case bookmark
	case moveToTopic(String)
	case archive
	case moveToTrash
}

nonisolated struct EntryDragPayload {
	let diaryID: String
	let entryID: String
}

nonisolated func resolveEntryDrop(
	_ payload: EntryDragPayload,
	to destination: EntryDropDestination,
	diaryID: String,
	entries: [ThingsDiaryEntry]
) -> EntryActionRequest? {
	guard payload.diaryID == diaryID,
		let entry = entries.first(where: { $0.id == payload.entryID && $0.diaryID == diaryID }),
		entry.deletedAt == nil
	else {
		return nil
	}

	switch destination {
	case .bookmarks:
		guard !entry.bookmarked else { return nil }
		return .bookmark
	case .topic(let topicID):
		guard entry.topicID != topicID else { return nil }
		return .moveToTopic(topicID)
	case .archive:
		guard !entry.archived else { return nil }
		return .archive
	case .trash:
		return .moveToTrash
	}
}

nonisolated func entryActionRequiresConfirmation(_ action: EntryAction, content: String) -> Bool {
	switch action {
	case .moveToTrash:
		!content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
	case .deletePermanently:
		true
	default:
		false
	}
}

nonisolated func availableEntryActions(for entry: ThingsDiaryEntry) -> [EntryAction] {
	if entry.deletedAt != nil {
		return [.restore, .deletePermanently]
	}
	return [
		.toggleBookmark,
		.toggleArchive,
		.duplicate,
		.moveToTopic,
		.moveToTrash,
	]
}

nonisolated func visibleEntries(
	_ entries: [ThingsDiaryEntry],
	section: EntrySection,
	query: String,
	sort: EntrySort
) -> [ThingsDiaryEntry] {
	let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
	return
		entries
		.filter { entry in
			let belongsToSection =
				switch section {
				case .entries:
					entry.deletedAt == nil && !entry.archived
				case .bookmarks:
					entry.deletedAt == nil && !entry.archived && entry.bookmarked
				case .archive:
					entry.deletedAt == nil && entry.archived
				case .trash:
					entry.deletedAt != nil
				}
			return belongsToSection
				&& (query.isEmpty || entry.content.localizedCaseInsensitiveContains(query))
		}
		.sorted { left, right in
			switch sort {
			case .newest:
				left.updatedAt == right.updatedAt
					? left.id < right.id
					: left.updatedAt > right.updatedAt
			case .oldest:
				left.updatedAt == right.updatedAt
					? left.id < right.id
					: left.updatedAt < right.updatedAt
			}
		}
}

nonisolated func visibleEntries(
	_ entries: [ThingsDiaryEntry],
	selection: DiaryNavigationSelection,
	query: String,
	sort: EntrySort
) -> [ThingsDiaryEntry] {
	let section =
		switch selection {
		case .entries, .topic:
			EntrySection.entries
		case .bookmarks:
			EntrySection.bookmarks
		case .archive:
			EntrySection.archive
		case .trash:
			EntrySection.trash
		}

	let sectionEntries = visibleEntries(entries, section: section, query: query, sort: sort)
	guard case .topic(let topicID) = selection else {
		return sectionEntries
	}
	return sectionEntries.filter { $0.topicID == topicID }
}

nonisolated struct EntryListPresentation: Equatable {
	let title: String
	let preview: String?
}

nonisolated func entryListPresentation(content: String) -> EntryListPresentation {
	let lines =
		content
		.split(whereSeparator: \Character.isNewline)
		.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
		.filter { !$0.isEmpty }
	guard let title = lines.first else {
		return EntryListPresentation(title: "Untitled", preview: nil)
	}
	let preview = lines.dropFirst().joined(separator: " ")
	return EntryListPresentation(title: title, preview: preview.isEmpty ? nil : preview)
}

nonisolated let maximumTopicTitleLength = 12

nonisolated func normalizedTopicTitle(_ title: String) -> String {
	String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maximumTopicTitleLength))
}
