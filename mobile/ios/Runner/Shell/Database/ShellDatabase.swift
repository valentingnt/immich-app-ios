import Foundation
import SQLiteData

/// Read-only access to the app's Drift database (Documents/immich.sqlite).
/// Dart owns the schema, migrations and every write; native screens only read.
enum ShellDatabase {
  enum Error: Swift.Error {
    case missingDatabase(URL)
  }

  /// Opened lazily: the file only exists once Flutter has initialized the database.
  static func shared() throws -> DatabasePool {
    try lock.withLock {
      if let pool { return pool }
      let url = try FileManager.default
        .url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        .appendingPathComponent("immich.sqlite")
      guard FileManager.default.fileExists(atPath: url.path) else { throw Error.missingDatabase(url) }

      var configuration = Configuration()
      configuration.readonly = true
      configuration.label = "ShellDatabase"
      // Drift writes from another connection; wait for its transactions instead of failing.
      configuration.busyMode = .timeout(5)
      let opened = try DatabasePool(path: url.path, configuration: configuration)
      pool = opened
      return opened
    }
  }

  private static let lock = NSLock()
  nonisolated(unsafe) private static var pool: DatabasePool?
}

extension ShellDatabase {
  private static let didChange = Notification.Name("ShellDatabase.didChange")
  private static let tablesKey = "tables"

  /// Called when Drift wrote to `tables` (from Dart, which owns every write).
  static func notifyChange(tables: Set<String>) {
    NotificationCenter.default.post(name: didChange, object: nil, userInfo: [tablesKey: tables])
  }

  /// Emits whenever one of `tables` changed. SQLite observation can't see writes made by Drift's own connection.
  static func changes(affecting tables: Set<String>) -> AsyncStream<Void> {
    AsyncStream { continuation in
      let observer = NotificationCenter.default.addObserver(forName: didChange, object: nil, queue: nil) { notification in
        guard let changed = notification.userInfo?[tablesKey] as? Set<String>, !changed.isDisjoint(with: tables) else { return }
        continuation.yield()
      }
      continuation.onTermination = { _ in NotificationCenter.default.removeObserver(observer) }
    }
  }
}

extension ShellDatabase {
  /// e.g. `https://demo.immich.app/api`. Explicit column names: the @Table models in Schemas/ map
  /// camelCase property names as is, which don't match Drift's snake_case columns.
  static func serverEndpoint(_ db: Database) throws -> String? {
    try #sql(
      "SELECT string_value FROM store_entity WHERE id = \(StoreKey._serverEndpoint.rawValue)",
      as: String?.self
    ).fetchOne(db) ?? nil
  }
}
