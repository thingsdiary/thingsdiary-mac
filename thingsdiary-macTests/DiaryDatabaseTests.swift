import Foundation
import GRDB
import Testing

@testable import thingsdiary

@Test("Diary store rejects unsupported future database versions")
func diaryStoreRejectsFutureDatabaseVersion() throws {
	let fileURL = FileManager.default.temporaryDirectory
		.appending(path: "thingsdiary-future-\(UUID().uuidString).sqlite")
	defer { try? FileManager.default.removeItem(at: fileURL) }
	let database = try DatabaseQueue(path: fileURL.path)
	try database.write { database in
		try database.create(table: "grdb_migrations") { table in
			table.column("identifier", .text).notNull().primaryKey()
		}
		try database.execute(
			sql: "INSERT INTO grdb_migrations (identifier) VALUES ('v999')"
		)
	}
	try database.close()

	#expect(throws: DiaryDatabaseError.unsupportedSchema) {
		_ = try DiaryStore(fileURL: fileURL)
	}
}
