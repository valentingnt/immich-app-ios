import Flutter

/// Receives the Albums configuration from Dart and exposes Dart's album actions to SwiftUI.
@available(iOS 26, *)
@MainActor
@Observable
final class AlbumsBridge {
  static let shared = AlbumsBridge()

  private(set) var configuration: NativeAlbumsConfiguration?
  @ObservationIgnored fileprivate var flutterApi: NativeAlbumsFlutterApi?
  private var itemCounts: [Int: String] = [:]
  @ObservationIgnored private var requestedItemCounts: Set<Int> = []
  @ObservationIgnored private var isRequestingItemCounts = false

  func createAlbum() {
    flutterApi?.createAlbum { _ in }
  }

  func openProfile() {
    flutterApi?.openProfile { _ in }
  }

  func refresh() async {
    await call { api, done in api.refresh(completion: done) }
  }

  func deleteAlbum(_ id: String) async {
    await call { api, done in api.deleteAlbum(albumId: id, completion: done) }
  }

  /// Applied right away; Dart persists them and sends its configuration back.
  func savePreferences(_ preferences: NativeAlbumsPreferences) {
    configuration?.preferences = preferences
    flutterApi?.savePreferences(preferences: preferences) { _ in }
  }

  /// "505 items", in the user's language. Resolved by Dart (plural rules) and cached per language.
  func itemCount(_ count: Int) -> String? {
    if let label = itemCounts[count] { return label }
    requestedItemCounts.insert(count)
    scheduleItemCountsRequest()
    return nil
  }

  private func scheduleItemCountsRequest() {
    guard !isRequestingItemCounts, let flutterApi else { return }
    isRequestingItemCounts = true
    // Next run loop: batch every count requested by the rows being rendered.
    Task { @MainActor in
      let counts = Array(requestedItemCounts)
      requestedItemCounts.removeAll()
      let strings = configuration?.strings
      flutterApi.formatItemCounts(counts: counts.map(Int64.init)) { result in
        Task { @MainActor in
          self.isRequestingItemCounts = false
          // Discard results from before a language change.
          guard self.configuration?.strings == strings, case .success(let labels) = result else { return }
          for (count, label) in zip(counts, labels) { self.itemCounts[count] = label }
          if !self.requestedItemCounts.isEmpty { self.scheduleItemCountsRequest() }
        }
      }
    }
  }

  fileprivate func configure(_ configuration: NativeAlbumsConfiguration, api: NativeAlbumsFlutterApi) {
    flutterApi = api
    if self.configuration != configuration {
      if self.configuration?.strings != configuration.strings { itemCounts.removeAll() }
      self.configuration = configuration
    }
    // Counts asked for before Dart was reachable.
    if !requestedItemCounts.isEmpty { scheduleItemCountsRequest() }
  }

  /// Awaits a Dart call; failures are reported by Dart itself (toasts, logs).
  private func call(_ body: (NativeAlbumsFlutterApi, @escaping (Result<Void, PigeonError>) -> Void) -> Void) async {
    guard let flutterApi else { return }
    await withCheckedContinuation { continuation in
      body(flutterApi) { _ in continuation.resume() }
    }
  }
}

class NativeAlbumsApiImpl: NativeAlbumsHostApi {
  private let flutterApi: NativeAlbumsFlutterApi

  init(messenger: FlutterBinaryMessenger) {
    flutterApi = NativeAlbumsFlutterApi(binaryMessenger: messenger)
  }

  func configure(configuration: NativeAlbumsConfiguration) throws {
    guard #available(iOS 26, *) else { return }
    // Pigeon calls host APIs on the main thread.
    MainActor.assumeIsolated {
      AlbumsBridge.shared.configure(configuration, api: flutterApi)
    }
  }
}
