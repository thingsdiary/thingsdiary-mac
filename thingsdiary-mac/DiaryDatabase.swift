import Foundation
import GRDB

nonisolated enum DiaryDatabaseError: Error {
	case unsupportedSchema
}

nonisolated enum DiaryDatabase {
	static func open(at url: URL) throws -> DatabaseQueue {
		try FileManager.default.createDirectory(
			at: url.deletingLastPathComponent(),
			withIntermediateDirectories: true
		)
		let database = try DatabaseQueue(path: url.path)
		try prepare(database)
		return database
	}

	static func inMemory() throws -> DatabaseQueue {
		let database = try DatabaseQueue()
		try prepare(database)
		return database
	}

	private static func prepare(_ database: DatabaseQueue) throws {
		let migrator = migrator
		let isUnsupported = try database.read { database in
			try migrator.hasBeenSuperseded(database)
		}
		guard !isUnsupported else {
			throw DiaryDatabaseError.unsupportedSchema
		}
		try migrator.migrate(database)
	}

	private static var migrator: DatabaseMigrator {
		var migrator = DatabaseMigrator()
		migrator.registerMigration("v1") { database in
			try database.create(table: "diaries") { table in
				table.column("id", .text).primaryKey()
				table.column("selected", .boolean).notNull().defaults(to: false)
				table.column("last_sync_at", .datetime)
				table.column("payload", .blob).notNull()
			}
			try database.create(table: "entries") { table in
				table.column("diary_id", .text).notNull()
				table.column("id", .text).notNull()
				table.column("payload", .blob).notNull()
				table.primaryKey(["diary_id", "id"])
			}
			try database.create(table: "topics") { table in
				table.column("diary_id", .text).notNull()
				table.column("id", .text).notNull()
				table.column("payload", .blob).notNull()
				table.primaryKey(["diary_id", "id"])
			}
			try database.create(table: "templates") { table in
				table.column("diary_id", .text).notNull()
				table.column("id", .text).notNull()
				table.column("payload", .blob).notNull()
				table.primaryKey(["diary_id", "id"])
			}
			try database.create(table: "sync") { table in
				table.column("kind", .text).notNull()
				table.column("diary_id", .text).notNull()
				table.column("entity_id", .text).notNull()
				table.column("operation", .text)
				table.column("payload", .blob).notNull()
				table.primaryKey(["kind", "diary_id", "entity_id"])
			}
		}
		return migrator
	}
}
