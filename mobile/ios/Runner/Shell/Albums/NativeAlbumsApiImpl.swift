import Flutter

/// Receives the Albums configuration from Dart and exposes Dart's album actions to SwiftUI.
@available(iOS 26, *)
@MainActor
@Observable
final class AlbumsBridge {
  static let shared = AlbumsBridge()

  private(set) var configuration: NativeAlbumsConfiguration?
  @ObservationIgnored fileprivate var flutterApi: NativeAlbumsFlutterApi?

  func openAlbum(_ id: String) {
    flutterApi?.openAlbum(albumId: id) { _ in }
  }

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

  func savePreferences(_ preferences: NativeAlbumsPreferences) {
    flutterApi?.savePreferences(preferences: preferences) { _ in }
  }

  fileprivate func configure(_ configuration: NativeAlbumsConfiguration, api: NativeAlbumsFlutterApi) {
    flutterApi = api
    if self.configuration != configuration { self.configuration = configuration }
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
