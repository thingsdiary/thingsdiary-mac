/// Selection belongs to the visible list, independently of the browser's open tabs.
/// Native List supplies the proposed set after Shift, Command, and keyboard input.
nonisolated struct WorkspaceSelectionState<ID: Hashable>: Equatable {
	private(set) var selectedIDs: Set<ID> = []

	var singleSelectedID: ID? {
		selectedIDs.count == 1 ? selectedIDs.first : nil
	}

	var isMultiple: Bool { selectedIDs.count > 1 }

	enum Transition: Equatable {
		case unchanged
		case empty
		case single(ID)
		case multiple
	}

	/// Rejects IDs outside the current filter or document kind before reporting a change.
	@discardableResult
	mutating func replace(with proposedIDs: Set<ID>, visibleIDs: Set<ID>) -> Transition {
		let nextIDs = proposedIDs.intersection(visibleIDs)
		guard nextIDs != selectedIDs else { return .unchanged }
		selectedIDs = nextIDs
		if let singleSelectedID { return .single(singleSelectedID) }
		return selectedIDs.isEmpty ? .empty : .multiple
	}

	/// Called when search results, section contents, or remotely deleted items change.
	@discardableResult
	mutating func reconcile(visibleIDs: Set<ID>) -> Transition {
		replace(with: selectedIDs, visibleIDs: visibleIDs)
	}
}
