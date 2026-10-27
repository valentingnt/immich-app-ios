import SwiftUI

/// A user's profile picture, sized for a toolbar or a list row.
@available(iOS 26, *)
struct ProfileAvatar: View {
  let serverEndpoint: String?
  let userId: String?
  @State private var image: UIImage?

  private var url: URL? {
    guard let serverEndpoint, let userId else { return nil }
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
