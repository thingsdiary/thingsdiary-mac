struct WorkspaceListPresentation<Item: Identifiable> where Item.ID: Hashable {
	private(set) var items: [Item]
	private(set) var hasSnapshot: Bool

	init(items: [Item] = []) {
		self.items = items
		hasSnapshot = !items.isEmpty
	}

	@discardableResult
	mutating func reconcile(with source: [Item]) -> Bool {
		let membershipChanged = items.map(\.id) != source.map(\.id)
		items = source
		hasSnapshot = true
		return membershipChanged
	}
}
