import Flutter

/// Pigeon APIs of the native shell. Bound to the UI engine only, never to background engines,
/// so that callbacks always reach the Dart isolate that owns the UI.
enum NativeShellApis {
  static func register(messenger: FlutterBinaryMessenger) {
    NativeShellHostApiSetup.setUp(binaryMessenger: messenger, api: NativeShellApiImpl(messenger: messenger))
    NativeAlbumsHostApiSetup.setUp(binaryMessenger: messenger, api: NativeAlbumsApiImpl(messenger: messenger))
  }
}
