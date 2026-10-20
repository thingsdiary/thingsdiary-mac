import Foundation
import GRDB
import Testing

@testable import thingsdiary

@Test("Diary database migrations are repeatable and healthy")
func diaryDatabaseMigrationContract() throws {
	let fileURL = FileManager.default.temporaryDirectory
		.appending(path: "thingsdiary-migrations-\(UUID().uuidString).sqlite")
	defer { try? FileManager.default.removeItem(at: fileURL) }

	try DiaryDatabase.open(at: fileURL).close()
	let database = try DiaryDatabase.open(at: fileURL)
	let contract = try database.read { database in
		let migrations = try String.fetchAll(
			database,
			sql: "SELECT identifier FROM grdb_migrations ORDER BY identifier"
		)
		let tables = try String.fetchAll(
			database,
			sql: "SELECT name FROM sqlite_schema WHERE type = 'table' ORDER BY name"
		)
		let integrity = try String.fetchOne(database, sql: "PRAGMA integrity_check")
		let foreignKeyFailures = try Row.fetchAll(database, sql: "PRAGMA foreign_key_check")
		return (migrations, tables, integrity, foreignKeyFailures.count)
	}
	try database.close()

	#expect(contract.0 == ["v1"])
	#expect(
		contract.1
			== ["diaries", "entries", "grdb_migrations", "sync", "templates", "topics"]
	)
	#expect(contract.2 == "ok")
	#expect(contract.3 == 0)
}

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
