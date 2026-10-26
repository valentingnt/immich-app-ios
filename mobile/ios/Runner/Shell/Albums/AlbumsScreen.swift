import SQLiteData
import SwiftUI

@available(iOS 26, *)
@MainActor
enum AlbumsScreen {
  static func make() -> UIViewController? {
    guard let database = try? ShellDatabase.shared() else { return nil }
    return UIHostingController(rootView: AlbumsView(model: AlbumsModel(database: database, bridge: .shared)))
  }
}

@available(iOS 26, *)
@MainActor
@Observable
final class AlbumsModel {
  @ObservationIgnored @FetchAll var albums: [AlbumSummary]
  let bridge: AlbumsBridge
  @ObservationIgnored private var reloadTask: Task<Void, Never>?

  init(database: any DatabaseReader, bridge: AlbumsBridge) {
    _albums = FetchAll(AlbumSummary.query, database: database)
    self.bridge = bridge
    reloadTask = Task { [weak self] in
      for await _ in ShellDatabase.changes(affecting: AlbumSummary.observedTables) {
        try? await self?.$albums.load()
      }
    }
  }

  deinit {
    reloadTask?.cancel()
  }

  var strings: NativeAlbumsStrings? { bridge.configuration?.strings }

  func isOwned(_ album: AlbumSummary) -> Bool {
    album.ownerId == bridge.configuration?.currentUserId
  }
}

@available(iOS 26, *)
struct AlbumsView: View {
  let model: AlbumsModel
  @State private var pendingDeletion: AlbumSummary?

  var body: some View {
    NavigationStack {
      List(model.albums) { album in
        Button {
          model.bridge.openAlbum(album.id)
        } label: {
          VStack(alignment: .leading) {
            Text(album.name)
            Text("\(album.assetCount)")
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
        }
        .swipeActions {
          if model.isOwned(album) {
            Button(model.strings?.delete ?? "", systemImage: "trash", role: .destructive) {
              pendingDeletion = album
            }
          }
        }
      }
      .refreshable { await model.bridge.refresh() }
      .navigationTitle(model.strings?.title ?? "")
      .toolbar {
        ToolbarItem {
          Button(model.strings?.createAlbum ?? "", systemImage: "plus") { model.bridge.createAlbum() }
        }
        ToolbarItem {
          Button("", systemImage: "person.crop.circle") { model.bridge.openProfile() }
        }
      }
      .confirmationDialog(
        model.strings?.deleteAlbum ?? "",
        isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
        titleVisibility: .visible,
        presenting: pendingDeletion
      ) { album in
        Button(model.strings?.delete ?? "", role: .destructive) {
          Task { await model.bridge.deleteAlbum(album.id) }
        }
      } message: { album in
        Text(model.strings?.deleteConfirmationTemplate.replacingOccurrences(of: "{album}", with: album.name) ?? "")
      }
    }
  }
}
