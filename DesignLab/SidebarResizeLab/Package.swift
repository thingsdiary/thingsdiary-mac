// swift-tools-version: 6.0

import PackageDescription

let package = Package(
	name: "SidebarResizeLab",
	platforms: [.macOS(.v14)],
	targets: [
		.executableTarget(name: "SidebarResizeLab")
	]
)
