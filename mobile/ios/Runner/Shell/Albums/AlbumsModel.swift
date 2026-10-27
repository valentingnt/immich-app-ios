import Foundation
import SQLiteData

/// State of the native Albums screen: albums read from the database, filtered and sorted the way
/// RemoteAlbumService.searchAlbums / sortAlbums do in Dart. Actions go through AlbumsBridge.
@available(iOS 26, *)
@MainActor
@Observable
final class AlbumsModel {
  enum Filter: Hashable {
    case all, sharedWithMe, mine
  }

  @ObservationIgnored @FetchAll private var albums: [AlbumSummary]
  let bridge: AlbumsBridge
  var searchText = ""
  var filter = Filter.all
  /// Native navigation to the Flutter album page.
  var routes = FlutterRoutePath()
  private(set) var serverEndpoint: String?
  @ObservationIgnored private let database: DatabasePool
  @ObservationIgnored private var observation: Task<Void, Never>?

  init(database: DatabasePool, bridge: AlbumsBridge) {
    self.database = database
    self.bridge = bridge
    _albums = FetchAll(AlbumSummary.query, database: database)
    serverEndpoint = Self.readServerEndpoint(database)
    observation = Task { [weak self] in
      for await _ in ShellDatabase.changes(affecting: AlbumSummary.observedTables.union(["store_entity"])) {
        guard let self else { return }
        serverEndpoint = Self.readServerEndpoint(database)
        try? await $albums.load()
      }
    }
  }

  deinit {
    observation?.cancel()
  }

  // MARK: Navigation

  func openAlbum(_ id: String) {
    routes.open("album", arguments: ["id": id])
  }

  var strings: NativeAlbumsStrings? { bridge.configuration?.strings }
  var sortOptions: [NativeAlbumSortOption] { bridge.configuration?.sortOptions ?? [] }

  var preferences: NativeAlbumsPreferences {
    bridge.configuration?.preferences
      ?? NativeAlbumsPreferences(sortMode: .mostRecent, isReverse: true, isGrid: false)
  }

  var isEmpty: Bool { albums.isEmpty }

  var visibleAlbums: [AlbumSummary] {
    sorted(filtered(albums))
  }

  func isOwned(_ album: AlbumSummary) -> Bool {
    album.ownerId == bridge.configuration?.currentUserId
  }

  /// "Owned" or "Shared by {user}".
  func ownership(of album: AlbumSummary) -> String {
    guard let strings else { return "" }
    return isOwned(album) ? strings.owned : strings.sharedByTemplate.replacingOccurrences(of: "{user}", with: album.ownerName)
  }

  // MARK: Preferences

  /// Selecting the current mode again flips the order, like the Flutter sort button.
  func selectSort(_ mode: NativeAlbumSortMode) {
    var preferences = preferences
    if preferences.sortMode == mode {
      preferences.isReverse.toggle()
    } else {
      preferences.sortMode = mode
      preferences.isReverse = false
    }
    save(preferences)
  }

  func setGrid(_ isGrid: Bool) {
    var preferences = preferences
    preferences.isGrid = isGrid
    save(preferences)
  }

  func isAscending(_ mode: NativeAlbumSortMode) -> Bool {
    let ascendingByDefault = sortOptions.first { $0.mode == mode }?.isAscendingByDefault ?? false
    return ascendingByDefault != (preferences.sortMode == mode && preferences.isReverse)
  }

  private func save(_ preferences: NativeAlbumsPreferences) {
    bridge.savePreferences(preferences)
  }

  // MARK: Filtering and sorting

  private func filtered(_ albums: [AlbumSummary]) -> [AlbumSummary] {
    let query = searchText.trimmingCharacters(in: .whitespaces)
    let userId = bridge.configuration?.currentUserId
    return albums.filter { album in
      let matchesQuery = query.isEmpty
        || album.name.localizedCaseInsensitiveContains(query)
        || album.description.localizedCaseInsensitiveContains(query)
      let matchesFilter = switch filter {
      case .all: true
      case .sharedWithMe: userId == nil || album.ownerId != userId
      case .mine: userId == nil || album.ownerId == userId
      }
      return matchesQuery && matchesFilter
    }
  }

  private func sorted(_ albums: [AlbumSummary]) -> [AlbumSummary] {
    let mode = preferences.sortMode
    let ascending = isAscending(mode)
    func order<T: Comparable>(_ lhs: T, _ rhs: T) -> Bool { ascending ? lhs < rhs : lhs > rhs }

    switch mode {
    case .title:
      return albums.sorted {
        let result = $0.name.localizedStandardCompare($1.name)
        return ascending ? result == .orderedAscending : result == .orderedDescending
      }
    case .assetCount: return albums.sorted { order($0.assetCount, $1.assetCount) }
    case .lastModified: return albums.sorted { order($0.updatedAt, $1.updatedAt) }
    case .created: return albums.sorted { order($0.createdAt, $1.createdAt) }
    case .mostRecent: return sortedByAssetDate(albums, \.endDate, order)
    case .mostOldest: return sortedByAssetDate(albums, \.startDate, order)
    }
  }

  /// Empty albums have no asset date and always come last, as in Dart.
  private func sortedByAssetDate(
    _ albums: [AlbumSummary], _ date: KeyPath<AlbumSummary, Date?>, _ order: (Date, Date) -> Bool
  ) -> [AlbumSummary] {
    let dated = albums.filter { $0[keyPath: date] != nil }.sorted { order($0[keyPath: date]!, $1[keyPath: date]!) }
    return dated + albums.filter { $0[keyPath: date] == nil }
  }

  private static func readServerEndpoint(_ database: DatabasePool) -> String? {
    try? database.read(ShellDatabase.serverEndpoint)
  }
}
