import Foundation

nonisolated enum WorkspaceBulkAction: Equatable, Sendable {
	case saveContents
	case bookmark(Bool)
	case previewHidden(Bool)
	case duplicate
	case saveAsTemplate
	case moveToTopic(String?)
	case archive(Bool)
	case moveToTrash
	case restore
	case deletePermanently
	case deleteTemplates
}

nonisolated struct WorkspaceBulkResult: Equatable, Sendable {
	/// Includes changes accepted into the local offline queue.
	var succeededIDs: Set<String> = []
	var failedIDs: Set<String> = []
	var queuedIDs: Set<String> = []
	var errorsByID: [String: String] = [:]
}
