import SwiftUI

@available(iOS 26, *)
@MainActor
enum LibraryScreen {
  static func make() -> UIViewController? {
    guard let database = try? ShellDatabase.shared() else { return nil }
    return UIHostingController(rootView: LibraryView(model: LibraryModel(database: database, bridge: .shared)))
  }
}
