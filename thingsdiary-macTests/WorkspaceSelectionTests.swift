import Testing

@testable import thingsdiary

@Test("Expanding a native selection reports a group without opening its individual documents")
func expandingWorkspaceSelectionDoesNotReportSingleDocuments() {
	var selection = WorkspaceSelectionState<String>()
	let visible: Set<String> = ["first", "second", "third", "fourth"]

	#expect(selection.replace(with: ["second"], visibleIDs: visible) == .single("second"))
	#expect(
		selection.replace(with: ["second", "third", "fourth"], visibleIDs: visible) == .multiple
	)
	#expect(selection.isMultiple)
	#expect(selection.singleSelectedID == nil)
	#expect(selection.selectedIDs == ["second", "third", "fourth"])
}

@Test("Removing selected rows returns the remaining document exactly once")
func reducingWorkspaceSelectionOpensTheRemainingDocumentOnce() {
	var selection = WorkspaceSelectionState<String>()
	let visible: Set<String> = ["first", "second", "third"]
	selection.replace(with: visible, visibleIDs: visible)

	#expect(selection.replace(with: ["first", "third"], visibleIDs: visible) == .multiple)
	#expect(selection.replace(with: ["first"], visibleIDs: visible) == .single("first"))
	#expect(selection.singleSelectedID == "first")
	#expect(!selection.isMultiple)
	#expect(selection.replace(with: ["first"], visibleIDs: visible) == .unchanged)
	#expect(selection.reconcile(visibleIDs: visible) == .unchanged)
	#expect(selection.replace(with: [], visibleIDs: visible) == .empty)
	#expect(selection.singleSelectedID == nil)
}

@Test("Filtering and remote deletion remove invisible targets from the selection")
func workspaceSelectionReconcilesChangingResults() {
	var selection = WorkspaceSelectionState<String>()
	selection.replace(with: ["first", "second", "third"], visibleIDs: ["first", "second", "third"])

	#expect(selection.reconcile(visibleIDs: ["second", "third", "fourth"]) == .multiple)
	#expect(selection.selectedIDs == ["second", "third"])
	#expect(selection.reconcile(visibleIDs: ["third", "fourth"]) == .single("third"))
	#expect(selection.reconcile(visibleIDs: ["fourth"]) == .empty)
	#expect(selection.selectedIDs.isEmpty)
	// Removing a filter must not silently reselect previously hidden documents.
	#expect(selection.reconcile(visibleIDs: ["first", "second", "third", "fourth"]) == .unchanged)
	#expect(selection.selectedIDs.isEmpty)
}

@Test("Entries and templates never share an action selection even if their IDs match")
func workspaceSelectionRejectsOtherDocumentKinds() {
	var selection = WorkspaceSelectionState<WorkspaceTabID>()
	let visible: Set<WorkspaceTabID> = [.entry("same-id"), .entry("another")]

	#expect(
		selection.replace(
			with: [.entry("same-id"), .template("same-id"), .entry("hidden")],
			visibleIDs: visible
		) == .single(.entry("same-id"))
	)
	#expect(selection.selectedIDs == [.entry("same-id")])
	#expect(selection.reconcile(visibleIDs: [.template("same-id")]) == .empty)
}

@Test("Reordering results and adding new rows does not reopen the selected document")
func workspaceSelectionIgnoresUnrelatedResultChanges() {
	var selection = WorkspaceSelectionState<String>()
	selection.replace(with: ["selected"], visibleIDs: ["selected", "other"])

	#expect(selection.reconcile(visibleIDs: Set(["new", "other", "selected"])) == .unchanged)
	#expect(selection.singleSelectedID == "selected")
	#expect(
		selection.replace(with: ["selected", "not-visible"], visibleIDs: ["selected", "other"])
			== .unchanged
	)
}
