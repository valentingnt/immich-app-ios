import Photos
import SwiftUI

/// A photo from the device library, by its PhotoKit local identifier (Drift's local asset id).
@available(iOS 26, *)
struct LocalAssetImage: View {
  let localIdentifier: String
  let maxPixelSize: Int
  @State private var image: UIImage?

  var body: some View {
    Rectangle()
      .fill(.quaternary)
      .overlay {
        if let image { Image(uiImage: image).resizable().scaledToFill() }
      }
      .clipped()
      .task(id: localIdentifier) {
        image = await Self.load(localIdentifier, maxPixelSize: maxPixelSize)
      }
  }

  private static func load(_ localIdentifier: String, maxPixelSize: Int) async -> UIImage? {
    guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil).firstObject else {
      return nil
    }
    let options = PHImageRequestOptions()
    options.deliveryMode = .highQualityFormat
    options.resizeMode = .fast
    options.isNetworkAccessAllowed = true
    let size = CGSize(width: maxPixelSize, height: maxPixelSize)
    return await withCheckedContinuation { continuation in
      PHImageManager.default().requestImage(
        for: asset, targetSize: size, contentMode: .aspectFill, options: options
      ) { image, _ in
        continuation.resume(returning: image)
      }
    }
  }
}
