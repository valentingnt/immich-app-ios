import Flutter

/// Receives the Library configuration from Dart and exposes Dart's library actions to SwiftUI.
@available(iOS 26, *)
@MainActor
@Observable
final class LibraryBridge {
  static let shared = LibraryBridge()

  private(set) var configuration: NativeLibraryConfiguration?
  @ObservationIgnored fileprivate var flutterApi: NativeLibraryFlutterApi?

  /// The previews depend on the user and their preferences: reload them when those change.
  @ObservationIgnored var onConfigurationChange: (() -> Void)?

  func openProfile() {
    flutterApi?.openProfile { _ in }
  }

  func openLockedFolder() {
    flutterApi?.openLockedFolder { _ in }
  }

  fileprivate func configure(_ configuration: NativeLibraryConfiguration, api: NativeLibraryFlutterApi) {
    flutterApi = api
    guard self.configuration != configuration else { return }
    let previous = self.configuration
    self.configuration = configuration
    if previous?.currentUserId != configuration.currentUserId
      || previous?.minimumFaces != configuration.minimumFaces
      || previous?.isMemoriesEnabled != configuration.isMemoriesEnabled {
      onConfigurationChange?()
    }
  }
}

class NativeLibraryApiImpl: NativeLibraryHostApi {
  private let flutterApi: NativeLibraryFlutterApi

  init(messenger: FlutterBinaryMessenger) {
    flutterApi = NativeLibraryFlutterApi(binaryMessenger: messenger)
  }

  func configure(configuration: NativeLibraryConfiguration) throws {
    guard #available(iOS 26, *) else { return }
    // Pigeon calls host APIs on the main thread.
    MainActor.assumeIsolated {
      LibraryBridge.shared.configure(configuration, api: flutterApi)
    }
  }
}
