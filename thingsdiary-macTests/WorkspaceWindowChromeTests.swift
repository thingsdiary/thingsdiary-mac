import CoreGraphics
import Foundation
import Testing

@testable import thingsdiary

@Test("Window controls use the workspace titlebar center in either coordinate system")
func windowControlsUseWorkspaceTitlebarCenter() {
	let bounds = CGRect(x: 0, y: 10, width: 900, height: 600)

	#expect(
		workspaceTitlebarCenterY(in: bounds, isFlipped: true)
			== bounds.minY + workspaceTitlebarHeight / 2
	)
	#expect(
		workspaceTitlebarCenterY(in: bounds, isFlipped: false)
			== bounds.maxY - workspaceTitlebarHeight / 2
	)
}

@Test("Window controls keep a small inset from the leading edge")
func windowControlsKeepLeadingInset() {
	#expect(workspaceTrafficLightsHorizontalOffset(closeButtonMinX: 16) == 4)
}
