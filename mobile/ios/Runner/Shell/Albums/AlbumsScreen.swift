import SwiftUI

@available(iOS 26, *)
@MainActor
enum AlbumsScreen {
  static func make() -> UIViewController? {
    guard let database = try? ShellDatabase.shared() else { return nil }
    return UIHostingController(rootView: AlbumsView(model: AlbumsModel(database: database, bridge: .shared)))
  }
}
