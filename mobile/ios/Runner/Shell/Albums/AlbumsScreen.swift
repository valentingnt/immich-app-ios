import SQLiteData
import SwiftUI

@available(iOS 26, *)
@MainActor
enum AlbumsScreen {
  static func make() -> UIViewController? {
    guard let database = try? ShellDatabase.shared() else { return nil }
    return UIHostingController(rootView: AlbumsView(model: AlbumsModel(database: database)))
  }
}

@available(iOS 26, *)
@MainActor
@Observable
final class AlbumsModel {
  @ObservationIgnored @FetchAll var albums: [AlbumSummary]

  init(database: any DatabaseReader) {
    _albums = FetchAll(AlbumSummary.query, database: database)
  }
}

@available(iOS 26, *)
struct AlbumsView: View {
  let model: AlbumsModel

  var body: some View {
    NavigationStack {
      List(model.albums) { album in
        VStack(alignment: .leading) {
          Text(album.name)
          Text("\(album.assetCount)")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      }
      .navigationTitle("Albums")
    }
  }
}
