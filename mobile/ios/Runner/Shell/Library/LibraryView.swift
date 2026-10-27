import MapKit
import SwiftUI

@available(iOS 26, *)
struct LibraryView: View {
  @Bindable var model: LibraryModel

  var body: some View {
    NavigationStack(path: $model.routes.path) {
      ScrollView {
        if let strings = model.strings {
          VStack(spacing: 24) {
            shortcuts(strings)
            collections(strings)
            quickAccess(strings)
          }
          .padding(.horizontal)
          .padding(.bottom)
        }
      }
      .flutterRouteDestination()
      .navigationTitle(model.strings?.title ?? "")
      .navigationBarTitleDisplayMode(.large)
      .toolbar {
        ToolbarItem {
          Button { model.bridge.openProfile() } label: {
            ProfileAvatar(serverEndpoint: model.serverEndpoint, userId: model.bridge.configuration?.currentUserId)
          }
        }
      }
    }
  }

  // MARK: Sections

  private func shortcuts(_ strings: NativeLibraryStrings) -> some View {
    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
      ShortcutButton(title: strings.favorites, systemImage: "heart") { model.open("favorites") }
      ShortcutButton(title: strings.archived, systemImage: "archivebox") { model.open("archive") }
      ShortcutButton(title: strings.sharedLinks, systemImage: "link") { model.open("sharedLinks") }
      if model.isTrashEnabled {
        ShortcutButton(title: strings.trash, systemImage: "trash") { model.open("trash") }
      }
    }
  }

  private func collections(_ strings: NativeLibraryStrings) -> some View {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 20) {
      CollectionCard(title: strings.people, action: { model.open("people") }) {
        PreviewGrid(items: model.people, spacing: 10) { person in
          RemoteImage(url: faceURL(person), maxPixelSize: 240)
            .clipShape(.circle)
        }
      }
      CollectionCard(title: strings.places, action: { model.open("places") }) {
        PlacesPreview(place: model.lastPlace)
      }
      CollectionCard(title: strings.onThisDevice, action: { model.open("localAlbums") }) {
        PreviewGrid(items: model.localAlbums, spacing: 6) { album in
          LocalAssetImage(localIdentifier: album.thumbnailAssetId, maxPixelSize: 240)
            .clipShape(.rect(cornerRadius: 8))
        }
      }
      CollectionCard(title: strings.memories, action: { model.open("memories") }) {
        PreviewGrid(items: model.memories, spacing: 6) { memory in
          RemoteImage(url: thumbnailURL(memory), placeholder: memory.assetThumbhash, maxPixelSize: 240)
            .clipShape(.rect(cornerRadius: 8))
        }
      }
    }
  }

  private func quickAccess(_ strings: NativeLibraryStrings) -> some View {
    VStack(spacing: 0) {
      QuickAccessRow(title: strings.folders, action: { model.open("folders") }) {
        Image(systemName: "folder")
      }
      Divider().padding(.leading, 56)
      QuickAccessRow(title: strings.lockedFolder, action: { model.bridge.openLockedFolder() }) {
        Image(systemName: "lock")
      }
      Divider().padding(.leading, 56)
      QuickAccessRow(title: strings.partners, action: { model.open("partners") }) {
        Image(systemName: "person.2")
      }
      ForEach(model.partners) { partner in
        Divider().padding(.leading, 56)
        QuickAccessRow(title: model.photosTitle(of: partner), action: { model.openPartner(partner) }) {
          ProfileAvatar(serverEndpoint: model.serverEndpoint, userId: partner.id)
        }
      }
    }
    .background(.fill.quinary, in: .rect(cornerRadius: 20))
  }

  // MARK: URLs

  private func faceURL(_ person: LibrarySummary.Person) -> URL? {
    guard let serverEndpoint = model.serverEndpoint else { return nil }
    // Same URL as getFaceThumbnailUrl in Dart, so that both share the HTTP cache.
    let version = Int64(person.updatedAt.timeIntervalSince1970 * 1000)
    return URL(string: "\(serverEndpoint)/people/\(person.id)/thumbnail?c=\(version)")
  }

  private func thumbnailURL(_ memory: LibrarySummary.Memory) -> URL? {
    guard let serverEndpoint = model.serverEndpoint else { return nil }
    return ShellImageLoader.thumbnailURL(serverEndpoint: serverEndpoint, assetId: memory.assetId, thumbhash: memory.assetThumbhash)
  }
}

// MARK: - Components

@available(iOS 26, *)
private struct ShortcutButton: View {
  let title: String
  let systemImage: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Label(title, systemImage: systemImage)
        .font(.body.weight(.medium))
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .labelStyle(TintedIconLabelStyle())
    .background(.fill.quinary, in: .capsule)
  }
}

@available(iOS 26, *)
private struct TintedIconLabelStyle: LabelStyle {
  func makeBody(configuration: Configuration) -> some View {
    HStack(spacing: 10) {
      configuration.icon.foregroundStyle(.tint).frame(width: 24)
      configuration.title.foregroundStyle(.primary)
    }
  }
}

/// A square preview with its title below, opening the collection.
@available(iOS 26, *)
private struct CollectionCard<Preview: View>: View {
  let title: String
  let action: () -> Void
  @ViewBuilder let preview: Preview

  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 8) {
        Color.clear
          .aspectRatio(1, contentMode: .fit)
          .overlay { preview }
          .background(.tint.quinary)
          .clipShape(.rect(cornerRadius: 20))
        Text(title)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.primary)
          .padding(.leading, 4)
      }
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
  }
}

/// Up to four items in a 2×2 grid.
@available(iOS 26, *)
private struct PreviewGrid<Item: Identifiable, Cell: View>: View {
  let items: [Item]
  let spacing: CGFloat
  @ViewBuilder let cell: (Item) -> Cell

  var body: some View {
    Grid(horizontalSpacing: spacing, verticalSpacing: spacing) {
      ForEach(0..<2, id: \.self) { row in
        GridRow {
          ForEach(0..<2, id: \.self) { column in
            let index = row * 2 + column
            Color.clear
              .aspectRatio(1, contentMode: .fit)
              .overlay {
                if index < items.count { cell(items[index]) }
              }
          }
        }
      }
    }
    .padding(12)
  }
}

@available(iOS 26, *)
private struct PlacesPreview: View {
  let place: LibrarySummary.Place?

  var body: some View {
    if let place {
      let center = CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
      Map(initialPosition: .region(MKCoordinateRegion(center: center, latitudinalMeters: 40_000, longitudinalMeters: 40_000)))
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .allowsHitTesting(false)
        .id(place)
    } else {
      Image(systemName: "map").font(.largeTitle).foregroundStyle(.tint)
    }
  }
}

@available(iOS 26, *)
private struct QuickAccessRow<Icon: View>: View {
  let title: String
  let action: () -> Void
  @ViewBuilder let icon: Icon

  var body: some View {
    Button(action: action) {
      HStack(spacing: 14) {
        icon
          .font(.title3)
          .foregroundStyle(.tint)
          .frame(width: 28, height: 28)
        Text(title)
          .font(.body.weight(.medium))
          .foregroundStyle(.primary)
        Spacer()
        Image(systemName: "chevron.right")
          .font(.footnote.weight(.semibold))
          .foregroundStyle(.tertiary)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 14)
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
  }
}

@available(iOS 26, *)
private struct RemoteImage: View {
  let url: URL?
  var placeholder: String?
  let maxPixelSize: Int
  @State private var image: UIImage?

  var body: some View {
    Rectangle()
      .fill(.quaternary)
      .overlay {
        if let image { Image(uiImage: image).resizable().scaledToFill() }
      }
      .clipped()
      .task(id: url) {
        guard let url else { return image = nil }
        let loader = ShellImageLoader.shared
        image = loader.cachedImage(for: url, maxPixelSize: maxPixelSize)
          ?? placeholder.flatMap(ShellImageLoader.placeholder(thumbhash:))
        if let loaded = await loader.image(for: url, maxPixelSize: maxPixelSize) {
          image = loaded
        }
      }
  }
}
