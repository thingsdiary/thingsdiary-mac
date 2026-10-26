import Foundation
import ThingsDiaryClient

nonisolated struct EntryPreviewMenuState {
	let entryHidesPreview: Bool
	let topicHidesPreview: Bool

	var isHidden: Bool { entryHidesPreview || topicHidesPreview }

	var title: String {
		if topicHidesPreview {
			return entryHidesPreview
				? "Preview Hidden by Entry and Topic" : "Preview Hidden by Topic"
		}
		return entryHidesPreview ? "Show Preview" : "Hide Preview"
	}
}

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
	case templates
	case archive
	case trash
}

nonisolated let minimumEntryListWidth: CGFloat = 260
nonisolated let minimumEntryEditorWidth: CGFloat = 420
nonisolated let entryListDividerWidth: CGFloat = 1
nonisolated let entryListResizeHitWidth: CGFloat = 9
nonisolated let minimumBrowserTabWidth: CGFloat = 92
nonisolated let maximumBrowserTabWidth: CGFloat = 170
nonisolated let workspaceTitlebarHorizontalInset: CGFloat = 12
nonisolated let browserTabSpacing = workspaceTitlebarHorizontalInset
nonisolated let browserTabLeadingPadding = workspaceTitlebarHorizontalInset
nonisolated let browserTabCreateButtonWidth: CGFloat = 30
nonisolated let browserTabCreateButtonSpacing: CGFloat = 8
nonisolated let workspaceTitlebarHeight: CGFloat = 46
nonisolated let editorWorkspaceFocusHysteresis: CGFloat = 60
nonisolated let minimumSplitWorkspaceWidth =
	minimumEntryListWidth + entryListDividerWidth + minimumEntryEditorWidth
nonisolated let minimumDiaryOverviewWidth: CGFloat = 620

nonisolated func diaryEditControlVisible(
	for diaryID: String,
	firstDiaryID: String?,
	hoveredDiaryID: String?
) -> Bool {
	diaryID == (hoveredDiaryID ?? firstDiaryID)
}

nonisolated enum WorkspaceTabID: Hashable {
	case entry(String)
	case template(String)

	var documentID: String {
		switch self {
		case .entry(let id), .template(let id): id
		}
	}

	var tabAccessibilityID: String {
		switch self {
		case .entry(let id): "entry-tab.\(id)"
		case .template(let id): "template-tab.\(id)"
		}
	}

	var closeAccessibilityID: String {
		switch self {
		case .entry(let id): "entry-tab.close.\(id)"
		case .template(let id): "template-tab.close.\(id)"
		}
	}

	var editorAccessibilityID: String {
		switch self {
		case .entry: "entry.editor"
		case .template: "template.editor"
		}
	}
}

nonisolated struct BrowserTabsState<TabID: Hashable>: Equatable {
	var openTabIDs: [TabID] = []
	var activeTabID: TabID?
	var pinnedTabIDs: Set<TabID> = []
	var previewTabID: TabID?

	mutating func open(_ tabID: TabID) {
		if !openTabIDs.contains(tabID) {
			openTabIDs.append(tabID)
		}
		promote(tabID)
		activeTabID = tabID
	}

	mutating func preview(_ tabID: TabID) {
		if openTabIDs.contains(tabID) {
			activeTabID = tabID
			if previewTabID == tabID {
				promote(tabID)
			}
			return
		}

		if let previewTabID,
			let previewIndex = openTabIDs.firstIndex(of: previewTabID)
		{
			openTabIDs[previewIndex] = tabID
		} else {
			openTabIDs.append(tabID)
		}
		previewTabID = tabID
		activeTabID = tabID
	}

	mutating func promote(_ tabID: TabID) {
		guard previewTabID == tabID else { return }
		previewTabID = nil
	}

	func isPreview(_ tabID: TabID) -> Bool {
		previewTabID == tabID
	}

	mutating func close(_ tabID: TabID) {
		guard let index = openTabIDs.firstIndex(of: tabID) else { return }
		openTabIDs.remove(at: index)
		pinnedTabIDs.remove(tabID)
		if previewTabID == tabID {
			previewTabID = nil
		}
		guard activeTabID == tabID else { return }
		activeTabID = openTabIDs.indices.contains(index) ? openTabIDs[index] : openTabIDs.last
	}

	mutating func selectTab(offset: Int) {
		guard
			openTabIDs.count > 1,
			let activeTabID,
			let activeIndex = openTabIDs.firstIndex(of: activeTabID)
		else { return }
		let count = openTabIDs.count
		let destinationIndex = (activeIndex + offset + count) % count
		self.activeTabID = openTabIDs[destinationIndex]
	}

	mutating func togglePin(_ tabID: TabID) {
		guard openTabIDs.contains(tabID) else { return }
		promote(tabID)
		if pinnedTabIDs.remove(tabID) == nil {
			pinnedTabIDs.insert(tabID)
		}
		normalizePinnedOrder()
	}

	func isPinned(_ tabID: TabID) -> Bool {
		pinnedTabIDs.contains(tabID)
	}

	func closeableOtherTabIDs(keeping tabID: TabID) -> [TabID] {
		openTabIDs.filter { $0 != tabID && !isPinned($0) }
	}

	mutating func move(_ tabID: TabID, to destinationIndex: Int) {
		guard let sourceIndex = openTabIDs.firstIndex(of: tabID) else { return }
		let range = reorderRange(for: tabID)
		let tabID = openTabIDs.remove(at: sourceIndex)
		let index = min(max(destinationIndex, range.lowerBound), range.upperBound)
		openTabIDs.insert(tabID, at: index)
	}

	func reorderRange(for tabID: TabID) -> ClosedRange<Int> {
		let pinnedCount = pinnedTabIDs.count
		if isPinned(tabID) {
			return 0...max(pinnedCount - 1, 0)
		}
		return min(pinnedCount, openTabIDs.count - 1)...max(openTabIDs.count - 1, pinnedCount)
	}

	mutating func reconcile(validTabIDs: Set<TabID>) {
		openTabIDs.removeAll { !validTabIDs.contains($0) }
		pinnedTabIDs.formIntersection(validTabIDs)
		if let previewTabID, !validTabIDs.contains(previewTabID) {
			self.previewTabID = nil
		}
		if let activeTabID, !validTabIDs.contains(activeTabID) {
			self.activeTabID = openTabIDs.last
		}
	}

	private mutating func normalizePinnedOrder() {
		openTabIDs =
			openTabIDs.filter(pinnedTabIDs.contains)
			+ openTabIDs.filter { !pinnedTabIDs.contains($0) }
	}
}

nonisolated enum BrowserTabCloseDisposition: Equatable {
	case close
	case confirmDiscard
}

nonisolated func browserTabCloseDisposition(
	persistedContent: String,
	draftContent: String
) -> BrowserTabCloseDisposition {
	draftContent == persistedContent ? .close : .confirmDiscard
}

nonisolated struct TabReorderSession<TabID: Hashable>: Equatable {
	let tabID: TabID
	let startIndex: Int
	private(set) var placeholderIndex: Int
	private(set) var translation: CGFloat = 0

	init(tabID: TabID, startIndex: Int) {
		self.tabID = tabID
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
		let destination = browserTabReorderDestination(
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

	func previewOrder(in tabIDs: [TabID]) -> [TabID] {
		var preview = tabIDs.filter { $0 != tabID }
		preview.insert(tabID, at: min(max(placeholderIndex, 0), preview.count))
		return preview
	}

	func offset(forTabAt index: Int, tabWidth: CGFloat) -> CGFloat {
		let step = tabWidth + browserTabSpacing
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

	func commit(to tabs: inout BrowserTabsState<TabID>) {
		tabs.move(tabID, to: placeholderIndex)
	}
}

nonisolated func effectiveEntryListWidth(
	preferredWidth: CGFloat,
	availableWidth: CGFloat
) -> CGFloat {
	let maximumWidth = min(440, availableWidth - entryListDividerWidth - minimumEntryEditorWidth)
	return min(max(preferredWidth, minimumEntryListWidth), max(maximumWidth, minimumEntryListWidth))
}

nonisolated func adaptiveBrowserTabWidth(
	availableWidth: CGFloat,
	tabCount: Int
) -> CGFloat {
	guard tabCount > 0 else { return maximumBrowserTabWidth }
	let separatorsWidth = CGFloat(max(tabCount - 1, 0)) * browserTabSpacing
	let fittedWidth = floor((max(availableWidth, 0) - separatorsWidth) / CGFloat(tabCount))
	return min(maximumBrowserTabWidth, max(minimumBrowserTabWidth, fittedWidth))
}

nonisolated func browserTabsContentWidth(tabWidth: CGFloat, tabCount: Int) -> CGFloat {
	guard tabCount > 0 else { return 0 }
	return browserTabLeadingPadding
		+ CGFloat(tabCount) * tabWidth
		+ CGFloat(tabCount - 1) * browserTabSpacing
}

nonisolated func browserTabCreateButtonOffset(
	availableWidth: CGFloat,
	tabsContentWidth: CGFloat
) -> CGFloat {
	let naturalOffset = max(
		tabsContentWidth + browserTabCreateButtonSpacing,
		browserTabLeadingPadding
	)
	let pinnedOffset = max(
		availableWidth - browserTabCreateButtonWidth,
		browserTabLeadingPadding
	)
	return min(naturalOffset, pinnedOffset)
}

nonisolated func browserTabsViewportWidth(createButtonOffset: CGFloat) -> CGFloat {
	max(createButtonOffset - browserTabCreateButtonSpacing, 0)
}

nonisolated func browserTabCreateButtonIsPinned(
	availableWidth: CGFloat,
	tabsContentWidth: CGFloat
) -> Bool {
	let naturalOffset = max(
		tabsContentWidth + browserTabCreateButtonSpacing,
		browserTabLeadingPadding
	)
	let pinnedOffset = max(
		availableWidth - browserTabCreateButtonWidth,
		browserTabLeadingPadding
	)
	return naturalOffset >= pinnedOffset
}

nonisolated func shouldHideBrowserTabCreateButton(
	isReordering: Bool,
	isPinned: Bool
) -> Bool {
	isReordering && !isPinned
}

nonisolated func shouldShowTopicAssignmentMenu(
	topicCount: Int,
	currentTopicID: String?
) -> Bool {
	topicCount > 0 || currentTopicID != nil
}

nonisolated func shouldChangeTopicAssignment(
	currentTopicID: String?,
	selectedTopicID: String?
) -> Bool {
	currentTopicID != selectedTopicID
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

nonisolated func reconciledDraftAfterRemoteUpdate(
	currentDraft: String,
	previousPersistedContent: String,
	updatedPersistedContent: String
) -> String {
	currentDraft == previousPersistedContent ? updatedPersistedContent : currentDraft
}

nonisolated func browserTabReorderDestination(
	startIndex: Int,
	translation: CGFloat,
	tabWidth: CGFloat,
	tabCount: Int
) -> Int {
	guard tabCount > 0 else { return 0 }
	let step = max(tabWidth + browserTabSpacing, 1)
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
	hasSelectedEntry: Bool,
	availableWidth: CGFloat,
	isEntryListCollapsed: Bool,
	isCompact: Bool,
	compactPane: CompactWorkspacePane
) -> EntryWorkspaceLayout {
	if isEntryListCollapsed { return .editorOnly }
	if hasSelectedEntry {
		guard !isCompact else {
			return compactPane == .editor ? .editorOnly : .listOnly
		}
		return .split
	}
	return availableWidth >= minimumDiaryOverviewWidth ? .split : .listOnly
}

nonisolated func workspaceHeaderBrowserWidth(
	availableWidth: CGFloat,
	listWidth: CGFloat,
	layout: EntryWorkspaceLayout,
	navigationChromeWidth: CGFloat
) -> CGFloat {
	switch layout {
	case .listOnly:
		return 0
	case .split:
		return max(availableWidth - listWidth - entryListDividerWidth, 0)
	case .editorOnly:
		return max(availableWidth - navigationChromeWidth, 0)
	}
}

nonisolated func showsDiaryOverview(
	for selection: DiaryNavigationSelection,
	selectionIsEmpty: Bool
) -> Bool {
	guard selectionIsEmpty else { return true }
	switch selection {
	case .topic, .templates, .archive, .trash:
		return false
	case .entries, .bookmarks:
		return true
	}
}

nonisolated enum EntryAction: Equatable {
	case bookmark
	case toggleBookmark
	case toggleArchive
	case archive
	case duplicate
	case saveAsTemplate
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

nonisolated struct EntryDragPayload: Codable {
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

nonisolated func entryShowsMetadataIndicators(_ entry: ThingsDiaryEntry) -> Bool {
	!entry.archived && entry.deletedAt == nil
}

nonisolated func availableEntryActions(for entry: ThingsDiaryEntry) -> [EntryAction] {
	if entry.deletedAt != nil {
		return [.restore, .deletePermanently]
	}
	if entry.archived {
		return [.toggleArchive, .moveToTrash]
	}
	return [
		.toggleBookmark,
		.toggleArchive,
		.duplicate,
		.saveAsTemplate,
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
		case .entries, .topic, .templates:
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
		return selection == .templates ? [] : sectionEntries
	}
	return sectionEntries.filter { $0.topicID == topicID }
}

nonisolated struct EntryListPresentation: Equatable {
	let title: String
	let preview: String?
}

nonisolated func hiddenEntryListPlaceholder(for entryID: String) -> EntryListPresentation {
	let words = [
		"a", "quiet", "moment", "today", "small", "details", "remember", "thoughts",
		"another", "day", "looking", "back", "ideas", "space", "plans", "tomorrow",
	]
	// Stable seed and SplitMix64 keep similar IDs visually distinct without changing on redraw.
	var state = entryID.utf8.reduce(UInt64(0xcbf2_9ce4_8422_2325)) {
		($0 ^ UInt64($1)) &* 0x100_0000_01b3
	}
	func next(_ range: ClosedRange<Int>) -> Int {
		state &+= 0x9e37_79b9_7f4a_7c15
		var value = state
		value = (value ^ (value >> 30)) &* 0xbf58_476d_1ce4_e5b9
		value = (value ^ (value >> 27)) &* 0x94d0_49bb_1331_11eb
		value ^= value >> 31
		return range.lowerBound + Int(value % UInt64(range.count))
	}
	func text(length: ClosedRange<Int>) -> String {
		let count = next(length)
		var result = ""
		while result.count < count {
			if !result.isEmpty { result += " " }
			result += words[next(0...(words.count - 1))]
		}
		return String(result.prefix(count)).trimmingCharacters(in: .whitespaces)
	}
	let title = text(length: 8...28)
	let lineCount = next(1...3)
	let preview = (0..<lineCount).map { _ in text(length: 18...42) }.joined(separator: "\n")
	return EntryListPresentation(title: title, preview: preview)
}

nonisolated func entryListTimestamp(
	_ date: Date,
	now: Date = .now,
	calendar: Calendar = .autoupdatingCurrent,
	locale: Locale = .autoupdatingCurrent
) -> String {
	let today = calendar.startOfDay(for: now)
	let dateDay = calendar.startOfDay(for: date)
	let daysAgo = calendar.dateComponents([.day], from: dateDay, to: today).day ?? .min
	let format = Date.FormatStyle(
		locale: locale,
		calendar: calendar,
		timeZone: calendar.timeZone
	)

	switch daysAgo {
	case 0:
		return date.formatted(format.hour().minute())
	case 1:
		return "Yesterday"
	case 2...6:
		return date.formatted(format.weekday(.wide))
	default:
		if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
			return date.formatted(format.month(.abbreviated).day())
		}
		return date.formatted(format.month(.abbreviated).day().year())
	}
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

nonisolated func templateListPresentation(content: String) -> EntryListPresentation {
	let presentation = entryListPresentation(content: content)
	guard presentation.title != "Untitled" else {
		return EntryListPresentation(title: "Untitled Template", preview: nil)
	}
	return presentation
}

nonisolated let maximumTopicTitleLength = 12

nonisolated func normalizedTopicTitle(_ title: String) -> String {
	String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maximumTopicTitleLength))
}

nonisolated func topicsSortedByCreation(
	_ topics: [ThingsDiaryTopic]
) -> [ThingsDiaryTopic] {
	topics.sorted { left, right in
		left.createdAt == right.createdAt
			? left.id < right.id
			: left.createdAt < right.createdAt
	}
}
