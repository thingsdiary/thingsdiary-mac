import Foundation
import Testing
import ThingsDiaryClient

@testable import thingsdiary

@Test("Diary settings default to the first row and follow the hovered row")
func diarySettingsVisibilityFollowsHover() {
	#expect(diarySettingsVisible(for: "first", firstDiaryID: "first", hoveredDiaryID: nil))
	#expect(!diarySettingsVisible(for: "second", firstDiaryID: "first", hoveredDiaryID: nil))
	#expect(!diarySettingsVisible(for: "first", firstDiaryID: "first", hoveredDiaryID: "second"))
	#expect(diarySettingsVisible(for: "second", firstDiaryID: "first", hoveredDiaryID: "second"))
}

@Test("Entry list filters sections, searches content, and sorts by update time")
func filtersEntryList() {
	let active = listEntry(
		id: "active",
		content: "Morning Walk",
		bookmarked: true,
		updatedAt: 4
	)
	let other = listEntry(id: "other", content: "Evening", updatedAt: 3)
	let archived = listEntry(id: "archived", content: "Old walk", archived: true, updatedAt: 2)
	let deleted = listEntry(id: "deleted", content: "Deleted walk", deletedAt: 5, updatedAt: 1)
	let entries = [deleted, archived, other, active]

	#expect(visibleEntries(entries, section: .entries, query: "walk", sort: .newest) == [active])
	#expect(visibleEntries(entries, section: .bookmarks, query: "", sort: .newest) == [active])
	#expect(visibleEntries(entries, section: .archive, query: "", sort: .newest) == [archived])
	#expect(visibleEntries(entries, section: .trash, query: "", sort: .newest) == [deleted])
	#expect(visibleEntries(entries, section: .entries, query: "", sort: .oldest) == [other, active])
}

@Test("Diary navigation filters active notes by topic")
func filtersDiaryNavigationByTopic() {
	let matching = listEntry(
		id: "matching",
		content: "Project note",
		topicID: "topic-1",
		updatedAt: 3
	)
	let anotherTopic = listEntry(
		id: "another",
		content: "Another project",
		topicID: "topic-2",
		updatedAt: 2
	)
	let archived = listEntry(
		id: "archived",
		content: "Archived project",
		archived: true,
		topicID: "topic-1",
		updatedAt: 1
	)

	#expect(
		visibleEntries(
			[archived, anotherTopic, matching],
			selection: .topic("topic-1"),
			query: "project",
			sort: .newest
		) == [matching])
}

@Test("Entry actions match the note lifecycle state")
func entryActionsMatchLifecycleState() {
	let active = listEntry(id: "active", content: "Active", updatedAt: 2)
	let deleted = listEntry(
		id: "deleted",
		content: "Deleted",
		deletedAt: 3,
		updatedAt: 3
	)

	#expect(
		availableEntryActions(for: active) == [
			.toggleBookmark,
			.toggleArchive,
			.duplicate,
			.saveAsTemplate,
			.moveToTopic,
			.moveToTrash,
		])
	#expect(
		availableEntryActions(for: deleted) == [
			.restore,
			.deletePermanently,
		])
}

@Test("Entry drop destinations resolve only valid moves")
func resolvesEntryDropDestinations() {
	let active = listEntry(id: "active", content: "Active", topicID: "topic-1", updatedAt: 2)
	let payload = EntryDragPayload(diaryID: "diary-1", entryID: "active")
	#expect(resolveEntryDrop(payload, to: .bookmarks, diaryID: "diary-1", entries: [active]) == .bookmark)
	#expect(
		resolveEntryDrop(payload, to: .topic("topic-2"), diaryID: "diary-1", entries: [active])
			== .moveToTopic("topic-2"))
	#expect(resolveEntryDrop(payload, to: .archive, diaryID: "diary-1", entries: [active]) == .archive)
	#expect(resolveEntryDrop(payload, to: .trash, diaryID: "diary-1", entries: [active]) == .moveToTrash)
	#expect(resolveEntryDrop(payload, to: .topic("topic-1"), diaryID: "diary-1", entries: [active]) == nil)
	#expect(resolveEntryDrop(payload, to: .archive, diaryID: "other", entries: [active]) == nil)
	#expect(resolveEntryDrop(payload, to: .trash, diaryID: "diary-1", entries: []) == nil)
	let deleted = listEntry(id: "active", content: "Active", deletedAt: 3, updatedAt: 3)
	#expect(resolveEntryDrop(payload, to: .archive, diaryID: "diary-1", entries: [deleted]) == nil)
	let archived = listEntry(id: "active", content: "Active", archived: true, updatedAt: 2)
	#expect(resolveEntryDrop(payload, to: .archive, diaryID: "diary-1", entries: [archived]) == nil)
	let bookmarked = listEntry(id: "active", content: "Active", bookmarked: true, updatedAt: 2)
	#expect(resolveEntryDrop(payload, to: .bookmarks, diaryID: "diary-1", entries: [bookmarked]) == nil)
}

@Test("Confirmation is required for destructive entry actions")
func confirmsDestructiveEntryActions() {
	#expect(entryActionRequiresConfirmation(.moveToTrash, content: "Some content"))
	#expect(!entryActionRequiresConfirmation(.moveToTrash, content: "  \n"))
	#expect(entryActionRequiresConfirmation(.deletePermanently, content: ""))
	#expect(!entryActionRequiresConfirmation(.archive, content: "Some content"))
	#expect(!entryActionRequiresConfirmation(.bookmark, content: "Some content"))
}

@Test("Entry list presentation separates title and preview")
func entryListPresentationSeparatesTitleAndPreview() {
	#expect(
		entryListPresentation(content: "Project plan\nFirst task\nSecond task")
			== EntryListPresentation(
				title: "Project plan",
				preview: "First task Second task"
			))
	#expect(
		entryListPresentation(content: "  \n\n")
			== EntryListPresentation(
				title: "Untitled",
				preview: nil
			))
}

@Test("Template list presentation names an empty template")
func templateListPresentationNamesEmptyTemplate() {
	#expect(
		templateListPresentation(content: "")
			== EntryListPresentation(title: "Untitled Template", preview: nil)
	)
}

@Test("Topic titles are trimmed and limited to the web client contract")
func normalizesTopicTitles() {
	#expect(normalizedTopicTitle("  Personal  ") == "Personal")
	#expect(normalizedTopicTitle("abcdefghijklmnop") == "abcdefghijkl")
}

@Test("Editor workspace uses hysteresis around its minimum width")
func adaptsEditorWorkspaceWidthWithoutLayoutChurn() {
	#expect(
		updatedEditorWorkspaceCompactState(
			isCompact: false,
			hasSelectedEntry: true,
			availableWidth: minimumSplitWorkspaceWidth - 1,
			isDragging: false
		))
	#expect(
		updatedEditorWorkspaceCompactState(
			isCompact: true,
			hasSelectedEntry: true,
			availableWidth: minimumSplitWorkspaceWidth + editorWorkspaceFocusHysteresis - 1,
			isDragging: false
		))
	#expect(
		!updatedEditorWorkspaceCompactState(
			isCompact: true,
			hasSelectedEntry: true,
			availableWidth: minimumSplitWorkspaceWidth + editorWorkspaceFocusHysteresis,
			isDragging: false
		))
	#expect(
		!updatedEditorWorkspaceCompactState(
			isCompact: true,
			hasSelectedEntry: false,
			availableWidth: 320,
			isDragging: false
		))
	#expect(
		!updatedEditorWorkspaceCompactState(
			isCompact: false,
			hasSelectedEntry: true,
			availableWidth: 320,
			isDragging: true
		))
}

@Test("Workspace gives a selected editor priority in compact widths")
func choosesEntryWorkspaceLayout() {
	#expect(
		entryWorkspaceLayout(
			selectionIsEmpty: false,
			hasSelectedEntry: true,
			availableWidth: minimumSplitWorkspaceWidth,
			isEditorFocusMode: false,
			isCompact: false,
			compactPane: .editor
		) == .split)
	#expect(
		entryWorkspaceLayout(
			selectionIsEmpty: false,
			hasSelectedEntry: true,
			availableWidth: minimumSplitWorkspaceWidth - 1,
			isEditorFocusMode: false,
			isCompact: true,
			compactPane: .editor
		) == .editorOnly)
	#expect(
		entryWorkspaceLayout(
			selectionIsEmpty: false,
			hasSelectedEntry: true,
			availableWidth: minimumSplitWorkspaceWidth - 1,
			isEditorFocusMode: false,
			isCompact: true,
			compactPane: .list
		) == .listOnly)
	#expect(
		entryWorkspaceLayout(
			selectionIsEmpty: false,
			hasSelectedEntry: true,
			availableWidth: 1_200,
			isEditorFocusMode: true,
			isCompact: false,
			compactPane: .editor
		) == .editorOnly)
	#expect(
		entryWorkspaceLayout(
			selectionIsEmpty: true,
			hasSelectedEntry: false,
			availableWidth: 1_200,
			isEditorFocusMode: false,
			isCompact: false,
			compactPane: .editor
		) == .listOnly)
	#expect(
		entryWorkspaceLayout(
			selectionIsEmpty: true,
			hasSelectedEntry: true,
			availableWidth: 1_200,
			isEditorFocusMode: false,
			isCompact: false,
			compactPane: .editor
		) == .split)
	#expect(
		entryWorkspaceLayout(
			selectionIsEmpty: false,
			hasSelectedEntry: false,
			availableWidth: minimumDiaryOverviewWidth,
			isEditorFocusMode: false,
			isCompact: false,
			compactPane: .editor
		) == .split)
	#expect(
		entryWorkspaceLayout(
			selectionIsEmpty: false,
			hasSelectedEntry: false,
			availableWidth: minimumDiaryOverviewWidth - 1,
			isEditorFocusMode: false,
			isCompact: false,
			compactPane: .editor
		) == .listOnly
	)
}

@Test("Browser tabs keep entries and templates in one ordered collection")
func opensMixedDocumentTabs() {
	var tabs = BrowserTabsState<WorkspaceTabID>()
	tabs.open(.entry("entry-1"))
	tabs.open(.template("template-1"))

	#expect(tabs.openTabIDs == [.entry("entry-1"), .template("template-1")])
	#expect(tabs.activeTabID == .template("template-1"))

	tabs.preview(.entry("entry-2"))
	#expect(tabs.previewTabID == .entry("entry-2"))
	#expect(tabs.openTabIDs.last == .entry("entry-2"))
}

@Test("Entry tabs activate existing notes without duplicating them")
func opensEntryTabsOnce() {
	var tabs = BrowserTabsState<String>()
	tabs.open("first")
	tabs.open("second")
	tabs.open("first")

	#expect(tabs.openTabIDs == ["first", "second"])
	#expect(tabs.activeTabID == "first")
}

@Test("Entry previews reuse one tab until the note is opened again")
func reusesEntryPreviewTab() {
	var tabs = BrowserTabsState<String>()

	tabs.preview("first")
	#expect(tabs.openTabIDs == ["first"])
	#expect(tabs.activeTabID == "first")
	#expect(tabs.previewTabID == "first")

	tabs.preview("second")
	#expect(tabs.openTabIDs == ["second"])
	#expect(tabs.activeTabID == "second")
	#expect(tabs.previewTabID == "second")

	tabs.preview("second")
	#expect(tabs.openTabIDs == ["second"])
	#expect(tabs.previewTabID == nil)
}

@Test("Entry previews do not replace permanent tabs")
func preservesPermanentTabsWhenPreviewing() {
	var tabs = BrowserTabsState<String>()
	tabs.open("permanent")

	tabs.preview("preview-first")
	tabs.preview("preview-second")
	tabs.preview("permanent")

	#expect(tabs.openTabIDs == ["permanent", "preview-second"])
	#expect(tabs.activeTabID == "permanent")
	#expect(tabs.previewTabID == "preview-second")
}

@Test("Editing and pinning promote an entry preview")
func promotesEntryPreview() {
	var tabs = BrowserTabsState<String>()
	tabs.preview("edited")
	tabs.promote("edited")
	#expect(tabs.previewTabID == nil)

	tabs.preview("pinned")
	tabs.togglePin("pinned")
	#expect(tabs.previewTabID == nil)
	#expect(tabs.isPinned("pinned"))
}

@Test("Closing the active entry tab selects its nearest neighbor")
func closesEntryTabsPredictably() {
	var tabs = BrowserTabsState<String>(
		openTabIDs: ["first", "second", "third"],
		activeTabID: "second"
	)

	tabs.close("second")
	#expect(tabs.openTabIDs == ["first", "third"])
	#expect(tabs.activeTabID == "third")

	tabs.close("third")
	#expect(tabs.openTabIDs == ["first"])
	#expect(tabs.activeTabID == "first")
}

@Test("Closing a tab asks only when its draft differs from persisted content")
func resolvesEntryTabCloseDisposition() {
	#expect(
		browserTabCloseDisposition(
			persistedContent: "Saved",
			draftContent: "Saved"
		) == .close
	)
	#expect(
		browserTabCloseDisposition(
			persistedContent: "Saved",
			draftContent: "Changed"
		) == .confirmDiscard
	)
	#expect(
		browserTabCloseDisposition(
			persistedContent: "",
			draftContent: ""
		) == .close
	)
}

@Test("Entry tabs discard notes that no longer exist")
func reconcilesEntryTabs() {
	var tabs = BrowserTabsState<String>(
		openTabIDs: ["first", "second", "third"],
		activeTabID: "second"
	)

	tabs.reconcile(validTabIDs: ["first", "third"])
	#expect(tabs.openTabIDs == ["first", "third"])
	#expect(tabs.activeTabID == "third")
}

@Test("Entry tabs can move to either side")
func movesEntryTabs() {
	var tabs = BrowserTabsState<String>(
		openTabIDs: ["first", "second", "third"],
		activeTabID: "second"
	)

	tabs.move("third", to: 0)
	#expect(tabs.openTabIDs == ["third", "first", "second"])
	#expect(tabs.activeTabID == "second")

	tabs.move("third", to: 2)
	#expect(tabs.openTabIDs == ["first", "second", "third"])
}

@Test("Pinned entry tabs stay before regular tabs")
func pinsEntryTabsAtTheLeadingEdge() {
	var tabs = BrowserTabsState<String>(
		openTabIDs: ["first", "second", "third"],
		activeTabID: "second"
	)

	tabs.togglePin("third")
	#expect(tabs.openTabIDs == ["third", "first", "second"])
	#expect(tabs.isPinned("third"))

	tabs.move("second", to: 0)
	#expect(tabs.openTabIDs == ["third", "second", "first"])

	tabs.move("third", to: 2)
	#expect(tabs.openTabIDs == ["third", "second", "first"])

	tabs.togglePin("third")
	#expect(tabs.openTabIDs == ["third", "second", "first"])
	#expect(!tabs.isPinned("third"))
}

@Test("Regular entry tabs cannot cross the pinned boundary")
func keepsRegularEntryTabsAfterPinnedTabs() {
	var tabs = BrowserTabsState<String>(
		openTabIDs: ["first", "second", "third", "fourth"],
		activeTabID: "third",
		pinnedTabIDs: ["first", "second"]
	)

	tabs.move("fourth", to: 0)
	#expect(tabs.openTabIDs == ["first", "second", "fourth", "third"])

	var drag = TabReorderSession<String>(tabID: "third", startIndex: 3)
	drag.update(
		translation: -1_000,
		tabWidth: 170,
		tabCount: tabs.openTabIDs.count,
		allowedRange: tabs.reorderRange(for: "third")
	)
	#expect(drag.placeholderIndex == 2)
}

@Test("Closing and reconciling tabs removes stale pins")
func removesStalePinnedEntryTabs() {
	var tabs = BrowserTabsState<String>(
		openTabIDs: ["first", "second", "third"],
		activeTabID: "second",
		pinnedTabIDs: ["first", "second"]
	)

	tabs.close("first")
	#expect(!tabs.isPinned("first"))

	tabs.reconcile(validTabIDs: ["third"])
	#expect(tabs.pinnedTabIDs.isEmpty)
}

@Test("Close other tabs keeps pinned tabs")
func keepsPinnedTabsWhenClosingOtherTabs() {
	let tabs = BrowserTabsState<String>(
		openTabIDs: ["pinned-first", "pinned-second", "regular-first", "regular-second"],
		activeTabID: "regular-first",
		pinnedTabIDs: ["pinned-first", "pinned-second"]
	)

	#expect(
		tabs.closeableOtherTabIDs(keeping: "regular-first") == ["regular-second"]
	)
	#expect(
		tabs.closeableOtherTabIDs(keeping: "pinned-first")
			== ["regular-first", "regular-second"]
	)
}

@Test("Entry list width preserves the preference within safe bounds")
func clampsEntryListWidth() {
	#expect(effectiveEntryListWidth(preferredWidth: 360, availableWidth: 1_200) == 360)
	#expect(effectiveEntryListWidth(preferredWidth: 120, availableWidth: 1_200) == 260)
	#expect(effectiveEntryListWidth(preferredWidth: 900, availableWidth: 1_000) == 440)
	#expect(
		effectiveEntryListWidth(
			preferredWidth: 360,
			availableWidth: minimumSplitWorkspaceWidth
		) == minimumEntryListWidth
	)
}

@Test("Entry tabs shrink evenly before overflowing")
func adaptsEntryTabWidth() {
	#expect(adaptiveBrowserTabWidth(availableWidth: 600, tabCount: 0) == maximumBrowserTabWidth)
	#expect(adaptiveBrowserTabWidth(availableWidth: 600, tabCount: 2) == maximumBrowserTabWidth)
	#expect(adaptiveBrowserTabWidth(availableWidth: 420, tabCount: 3) == 138)
	#expect(adaptiveBrowserTabWidth(availableWidth: 300, tabCount: 8) == minimumBrowserTabWidth)
}

@Test("New tab button follows the last tab while the row fits")
func newTabButtonFollowsLastTab() {
	let tabsWidth = browserTabsContentWidth(tabWidth: 170, tabCount: 2)

	#expect(tabsWidth == 349)
	#expect(
		browserTabCreateButtonOffset(
			availableWidth: 500,
			tabsContentWidth: tabsWidth
		) == 352
	)
	#expect(
		!browserTabCreateButtonIsPinned(
			availableWidth: 500,
			tabsContentWidth: tabsWidth
		)
	)
}

@Test("New tab button stays pinned when tabs overflow")
func newTabButtonStaysPinned() {
	let tabsWidth = browserTabsContentWidth(tabWidth: 92, tabCount: 6)

	#expect(tabsWidth > 400)
	#expect(
		browserTabCreateButtonOffset(
			availableWidth: 400,
			tabsContentWidth: tabsWidth
		) == 370
	)
	#expect(
		browserTabCreateButtonIsPinned(
			availableWidth: 400,
			tabsContentWidth: tabsWidth
		)
	)
}

@Test("New tab button hides only while an inline tab is being reordered")
func newTabButtonHidesOnlyDuringInlineReorder() {
	#expect(shouldHideBrowserTabCreateButton(isReordering: true, isPinned: false))
	#expect(!shouldHideBrowserTabCreateButton(isReordering: false, isPinned: false))
	#expect(!shouldHideBrowserTabCreateButton(isReordering: true, isPinned: true))
}

@Test("A completed save clears only the submitted draft")
func reconcilesSavedEntryDraft() {
	#expect(
		reconciledEntryDraftAfterSave(
			currentDraft: "Saved text\n",
			submittedContent: "Saved text\n",
			persistedContent: "Saved text"
		) == "Saved text"
	)
	#expect(
		reconciledEntryDraftAfterSave(
			currentDraft: "Typed while saving",
			submittedContent: "Submitted",
			persistedContent: "Submitted"
		) == nil
	)
}

@Test("Entry tab drag crosses neighboring tab centers")
func resolvesEntryTabDragDestination() {
	#expect(browserTabReorderDestination(startIndex: 1, translation: -100, tabWidth: 170, tabCount: 4) == 0)
	#expect(browserTabReorderDestination(startIndex: 1, translation: 80, tabWidth: 170, tabCount: 4) == 1)
	#expect(browserTabReorderDestination(startIndex: 1, translation: 100, tabWidth: 170, tabCount: 4) == 2)
	#expect(browserTabReorderDestination(startIndex: 1, translation: 800, tabWidth: 170, tabCount: 4) == 3)
}

@Test("Entry tab drag keeps source order until drop")
func previewsEntryTabMoveBeforeCommit() {
	var tabs = BrowserTabsState<String>(
		openTabIDs: ["first", "second", "third"],
		activeTabID: "second"
	)
	var drag = TabReorderSession<String>(tabID: "second", startIndex: 1)

	drag.update(translation: -100, tabWidth: 170, tabCount: tabs.openTabIDs.count)

	#expect(tabs.openTabIDs == ["first", "second", "third"])
	#expect(drag.placeholderIndex == 0)
	#expect(drag.previewOrder(in: tabs.openTabIDs) == ["second", "first", "third"])
	#expect(drag.offset(forTabAt: 0, tabWidth: 170) == 173)
	#expect(drag.offset(forTabAt: 1, tabWidth: 170) == -100)
	#expect(drag.offset(forTabAt: 2, tabWidth: 170) == 0)

	drag.commit(to: &tabs)
	#expect(tabs.openTabIDs == ["second", "first", "third"])
}

private func listEntry(
	id: String,
	content: String,
	archived: Bool = false,
	bookmarked: Bool = false,
	topicID: String? = nil,
	deletedAt: TimeInterval? = nil,
	updatedAt: TimeInterval
) -> ThingsDiaryEntry {
	ThingsDiaryEntry(
		id: id,
		diaryID: "diary-1",
		content: content,
		topicID: topicID,
		archived: archived,
		bookmarked: bookmarked,
		createdAt: Date(timeIntervalSince1970: 1),
		updatedAt: Date(timeIntervalSince1970: updatedAt),
		deletedAt: deletedAt.map(Date.init(timeIntervalSince1970:)),
		version: UInt64(updatedAt * 1_000)
	)
}
