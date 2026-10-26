import SwiftUI

@available(iOS 26, *)
struct AlbumsView: View {
  @Bindable var model: AlbumsModel
  @State private var pendingDeletion: AlbumSummary?

  var body: some View {
    NavigationStack {
      content
        .navigationTitle(model.strings?.title ?? "")
        .navigationBarTitleDisplayMode(.large)
        // In the navigation bar: iOS 26 would otherwise put it in the bottom toolbar, under the shell's tab bar.
        .searchable(
          text: $model.searchText,
          placement: .navigationBarDrawer,
          prompt: model.strings?.searchPrompt ?? ""
        )
        .refreshable { await model.bridge.refresh() }
        .toolbar { toolbar }
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

  @ViewBuilder
  private var content: some View {
    let albums = model.visibleAlbums
    if albums.isEmpty && !model.isEmpty {
      ContentUnavailableView(model.strings?.noResults ?? "", systemImage: "magnifyingglass")
    } else if model.preferences.isGrid {
      ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 20) {
          ForEach(albums) { album in
            Button { model.bridge.openAlbum(album.id) } label: { AlbumCell(album: album, model: model) }
              .buttonStyle(.plain)
              .contextMenu { menu(for: album) }
          }
        }
        .padding(.horizontal)
      }
    } else {
      List(albums) { album in
        Button { model.bridge.openAlbum(album.id) } label: { AlbumRow(album: album, model: model) }
          .contextMenu { menu(for: album) }
          .swipeActions {
            if model.isOwned(album) {
              Button(model.strings?.delete ?? "", systemImage: "trash", role: .destructive) { pendingDeletion = album }
            }
          }
      }
      .listStyle(.plain)
    }
  }

  @ViewBuilder
  private func menu(for album: AlbumSummary) -> some View {
    if model.isOwned(album) {
      Button(model.strings?.deleteAlbum ?? "", systemImage: "trash", role: .destructive) { pendingDeletion = album }
    }
  }

  @ToolbarContentBuilder
  private var toolbar: some ToolbarContent {
    ToolbarItem {
      Menu(model.strings?.sortBy ?? "", systemImage: "line.3.horizontal.decrease") {
        if let strings = model.strings {
          Picker(selection: $model.filter) {
            Text(strings.filterAll).tag(AlbumsModel.Filter.all)
            Text(strings.filterSharedWithMe).tag(AlbumsModel.Filter.sharedWithMe)
            Text(strings.filterMine).tag(AlbumsModel.Filter.mine)
          } label: {
            EmptyView()
          }
          .pickerStyle(.inline)
        }

        Section(model.strings?.sortBy ?? "") {
          ForEach(model.sortOptions, id: \.mode) { option in
            Button {
              model.selectSort(option.mode)
            } label: {
              if model.preferences.sortMode == option.mode {
                Label(option.label, systemImage: model.isAscending(option.mode) ? "chevron.up" : "chevron.down")
              } else {
                Text(option.label)
              }
            }
          }
        }

        Picker(selection: Binding(get: { model.preferences.isGrid }, set: { model.setGrid($0) })) {
          Image(systemName: "list.bullet").tag(false)
          Image(systemName: "square.grid.2x2").tag(true)
        } label: {
          EmptyView()
        }
        .pickerStyle(.palette)
      }
    }
    ToolbarItem {
      Button(model.strings?.createAlbum ?? "", systemImage: "plus") { model.bridge.createAlbum() }
    }
    ToolbarItem {
      Button { model.bridge.openProfile() } label: { ProfileAvatar(model: model) }
    }
  }
}

@available(iOS 26, *)
private struct AlbumRow: View {
  let album: AlbumSummary
  let model: AlbumsModel

  var body: some View {
    HStack(spacing: 14) {
      AlbumThumbnail(album: album, serverEndpoint: model.serverEndpoint, maxPixelSize: 216)
        .frame(width: 72, height: 72)
        .clipShape(.rect(cornerRadius: 12))
      VStack(alignment: .leading, spacing: 3) {
        Text(album.name)
          .font(.headline)
          .foregroundStyle(.primary)
          .lineLimit(2)
        AlbumSubtitle(album: album, model: model)
      }
    }
    .padding(.vertical, 2)
  }
}

@available(iOS 26, *)
private struct AlbumCell: View {
  let album: AlbumSummary
  let model: AlbumsModel

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Color.clear
        .aspectRatio(1, contentMode: .fit)
        .overlay { AlbumThumbnail(album: album, serverEndpoint: model.serverEndpoint, maxPixelSize: 600) }
        .clipShape(.rect(cornerRadius: 16))
      Text(album.name)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.primary)
        .lineLimit(1)
      AlbumSubtitle(album: album, model: model)
    }
    .contentShape(.rect)
  }
}

@available(iOS 26, *)
private struct AlbumSubtitle: View {
  let album: AlbumSummary
  let model: AlbumsModel

  var body: some View {
    let count = model.bridge.itemCount(album.assetCount) ?? album.assetCount.formatted()
    Text("\(count) · \(model.ownership(of: album))")
      .font(.subheadline)
      .foregroundStyle(.secondary)
      .lineLimit(1)
  }
}

@available(iOS 26, *)
private struct AlbumThumbnail: View {
  let album: AlbumSummary
  let serverEndpoint: String?
  let maxPixelSize: Int
  @State private var image: UIImage?

  private var url: URL? {
    guard let serverEndpoint, let assetId = album.thumbnailAssetId else { return nil }
    return ShellImageLoader.thumbnailURL(serverEndpoint: serverEndpoint, assetId: assetId, thumbhash: album.thumbnailThumbhash)
  }

  var body: some View {
    Rectangle()
      .fill(.quaternary)
      .overlay {
        if let image {
          Image(uiImage: image).resizable().scaledToFill()
        } else if album.thumbnailAssetId == nil {
          Image(systemName: "photo.on.rectangle").font(.title2).foregroundStyle(.tertiary)
        }
      }
      .clipped()
      .task(id: url) {
        guard let url else { return image = nil }
        let loader = ShellImageLoader.shared
        image = loader.cachedImage(for: url, maxPixelSize: maxPixelSize)
          ?? album.thumbnailThumbhash.flatMap(ShellImageLoader.placeholder(thumbhash:))
        if let loaded = await loader.image(for: url, maxPixelSize: maxPixelSize) {
          image = loaded
        }
      }
  }
}

@available(iOS 26, *)
private struct ProfileAvatar: View {
  let model: AlbumsModel
  @State private var image: UIImage?

  private var url: URL? {
    guard let serverEndpoint = model.serverEndpoint, let userId = model.bridge.configuration?.currentUserId else { return nil }
    return ShellImageLoader.profileImageURL(serverEndpoint: serverEndpoint, userId: userId)
  }

  var body: some View {
    Group {
      if let image {
        Image(uiImage: image).resizable().scaledToFill()
          .frame(width: 30, height: 30)
          .clipShape(.circle)
      } else {
        Image(systemName: "person.crop.circle")
      }
    }
    .task(id: url) {
      guard let url else { return }
      image = await ShellImageLoader.shared.image(for: url, maxPixelSize: 96)
    }
  }
}
