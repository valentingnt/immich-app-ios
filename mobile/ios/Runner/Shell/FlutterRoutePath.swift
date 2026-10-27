import SwiftUI

/// Native navigation path of a SwiftUI screen that opens Flutter routes (see FlutterRouteHost).
/// Bind it to the screen's NavigationStack and add `flutterRouteDestination()` inside it.
/// One route is shown at a time: the app has a single Flutter engine.
@available(iOS 26, *)
@MainActor
@Observable
final class FlutterRoutePath {
  var path: [NativeRoute] = []
  @ObservationIgnored private var isOpening = false

  /// Opens the route `name` of Dart's `nativeRoutes`, pushed natively once Flutter rendered it.
  func open(_ name: String, arguments: [String: String] = [:]) {
    guard path.isEmpty, !isOpening else { return }
    isOpening = true
    let route = NativeRoute(name: name, arguments: arguments)
    Task {
      defer { isOpening = false }
      guard await FlutterRouteHost.shared.open(route, dismiss: { [weak self] in self?.path.removeAll() }) else { return }
      path = [route]
    }
  }
}

@available(iOS 26, *)
extension View {
  /// Shows the Flutter route pushed by a FlutterRoutePath.
  func flutterRouteDestination() -> some View {
    navigationDestination(for: NativeRoute.self) { _ in
      if let container = FlutterRouteHost.shared.container {
        FlutterRouteView(container: container)
      }
    }
  }
}
