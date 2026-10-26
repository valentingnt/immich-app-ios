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
