import Testing

@testable import thingsdiary

private struct PresentationFixture: Identifiable, Equatable {
	let id: Int
	var title = ""
}

@Test("Only membership changes request a structural animation")
func contentUpdatesDoNotReplayInsertion() {
	var presentation = WorkspaceListPresentation(
		items: [PresentationFixture(id: 1, title: "Draft")]
	)

	#expect(
		presentation.reconcile(
			with: [PresentationFixture(id: 1, title: "Saved")]
		) == false
	)
	#expect(presentation.items.first?.title == "Saved")
	#expect(
		presentation.reconcile(
			with: [PresentationFixture(id: 2), PresentationFixture(id: 1, title: "Saved")]
		) == true
	)
	#expect(presentation.reconcile(with: [PresentationFixture(id: 2)]) == true)
}

@Test("Every burst insertion is represented without waiting for earlier animations")
func burstInsertionsNeverBlockLaterItems() {
	var presentation = WorkspaceListPresentation<PresentationFixture>()
	var source: [PresentationFixture] = []
	var nextID = 0

	for burstSize in [1, 10, 15, 32] {
		for _ in 0..<burstSize {
			source.insert(PresentationFixture(id: nextID), at: 0)
			nextID += 1
			presentation.reconcile(with: source)
		}

		#expect(presentation.items == source)
		#expect(Set(presentation.items.map(\.id)).count == source.count)
	}
}
