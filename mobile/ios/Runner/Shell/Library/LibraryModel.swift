import Foundation
import SQLiteData

/// State of the native Library screen: collection previews read from the database, reloaded when
/// Drift writes to their tables or when the Dart configuration they depend on changes.
@available(iOS 26, *)
@MainActor
@Observable
final class LibraryModel {
  let bridge: LibraryBridge
  /// Native navigation to the Flutter destinations.
  var routes = FlutterRoutePath()

  private(set) var people: [LibrarySummary.Person] = []
  private(set) var memories: [LibrarySummary.Memory] = []
  private(set) var localAlbums: [LibrarySummary.LocalAlbum] = []
  private(set) var partners: [LibrarySummary.Partner] = []
  private(set) var lastPlace: LibrarySummary.Place?
  private(set) var serverEndpoint: String?

  @ObservationIgnored private let database: DatabasePool
  @ObservationIgnored private var observation: Task<Void, Never>?

  init(database: DatabasePool, bridge: LibraryBridge) {
    self.database = database
    self.bridge = bridge
    observation = Task { [weak self] in
      self?.reload()
      for await _ in ShellDatabase.changes(affecting: LibrarySummary.observedTables.union(["store_entity"])) {
        self?.reload()
      }
    }
    bridge.onConfigurationChange = { [weak self] in self?.reload() }
  }

  deinit {
    observation?.cancel()
  }

  var strings: NativeLibraryStrings? { bridge.configuration?.strings }
  var isTrashEnabled: Bool { bridge.configuration?.isTrashEnabled ?? false }

  // MARK: Navigation

  func open(_ route: String, arguments: [String: String] = [:]) {
    routes.open(route, arguments: arguments)
  }

  func openPartner(_ partner: LibrarySummary.Partner) {
    open("partner", arguments: ["id": partner.id])
  }

  /// "Photos of {user}".
  func photosTitle(of partner: LibrarySummary.Partner) -> String {
    strings?.partnerPhotosTemplate.replacingOccurrences(of: "{user}", with: partner.name) ?? partner.name
  }

  // MARK: Loading

  private func reload() {
    let configuration = bridge.configuration
    do {
      let result = try database.read { db in
        let userId = configuration?.currentUserId
        return (
          people: try LibrarySummary.people(minimumFaces: Int(configuration?.minimumFaces ?? 3)).fetchAll(db),
          memories: configuration?.isMemoriesEnabled == false || userId == nil
            ? [] : try LibrarySummary.memories(ownerId: userId!).fetchAll(db),
          localAlbums: try LibrarySummary.localAlbums.fetchAll(db),
          partners: try userId.map { try LibrarySummary.partners(userId: $0).fetchAll(db) } ?? [],
          lastPlace: try LibrarySummary.lastPlace.fetchOne(db),
          serverEndpoint: try ShellDatabase.serverEndpoint(db)
        )
      }
      people = result.people
      memories = result.memories
      localAlbums = result.localAlbums
      partners = result.partners
      if lastPlace != result.lastPlace { lastPlace = result.lastPlace }
      serverEndpoint = result.serverEndpoint
    } catch {
      // Keep the previous previews: the next change notification retries.
    }
  }
}
