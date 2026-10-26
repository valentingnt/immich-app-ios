import ImageIO
import UIKit

/// Loads server images for native screens as UIImages, reusing what Flutter's image pipeline uses:
/// the authenticated URLSession and its disk cache, the same URLs (so cache hits are shared),
/// the JPEG XL decoder and thumbhash placeholders from the native core.
final class ShellImageLoader: Sendable {
  static let shared = ShellImageLoader()

  nonisolated(unsafe) private let memoryCache: NSCache<NSString, UIImage> = {
    let cache = NSCache<NSString, UIImage>()
    cache.totalCostLimit = 64 * 1024 * 1024
    return cache
  }()

  /// `GET {serverEndpoint}/assets/{id}/thumbnail`, matching getThumbnailUrlForRemoteId in Dart.
  static func thumbnailURL(serverEndpoint: String, assetId: String, thumbhash: String?) -> URL? {
    var url = "\(serverEndpoint)/assets/\(assetId)/thumbnail?size=thumbnail&edited=true"
    if let thumbhash {
      url += "&c=\(thumbhash.addingPercentEncoding(withAllowedCharacters: uriComponentAllowed) ?? thumbhash)"
    }
    return URL(string: url)
  }

  /// `GET {serverEndpoint}/users/{id}/profile-image`.
  static func profileImageURL(serverEndpoint: String, userId: String) -> URL? {
    URL(string: "\(serverEndpoint)/users/\(userId)/profile-image")
  }

  func cachedImage(for url: URL, maxPixelSize: Int) -> UIImage? {
    memoryCache.object(forKey: Self.key(url, maxPixelSize))
  }

  /// Downloads (or reads from the HTTP cache) and decodes at most `maxPixelSize` on the longest side.
  func image(for url: URL, maxPixelSize: Int) async -> UIImage? {
    let key = Self.key(url, maxPixelSize)
    if let cached = memoryCache.object(forKey: key) { return cached }

    var request = URLRequest(url: url)
    request.cachePolicy = .returnCacheDataElseLoad
    guard let (data, response) = try? await URLSessionManager.shared.session.data(for: request),
          (response as? HTTPURLResponse)?.statusCode ?? 200 < 400,
          !Task.isCancelled
    else { return nil }

    let image = await Task.detached(priority: .userInitiated) {
      response.mimeType == "image/jxl"
        ? Self.decodeJxl(data, maxPixelSize: maxPixelSize)
        : Self.decode(data, maxPixelSize: maxPixelSize)
    }.value
    if let image {
      memoryCache.setObject(image, forKey: key, cost: Self.cost(of: image))
    }
    return image
  }

  /// Blurred placeholder from a base64 thumbhash, as stored by Drift.
  static func placeholder(thumbhash: String) -> UIImage? {
    guard let data = Data(base64Encoded: thumbhash),
          let (width, height, pointer) = NativeCore.thumbhash(data)
    else { return nil }
    return rgbaImage(pointer, width: width, height: height)
  }

  // MARK: - Decoding

  private static func decode(_ data: Data, maxPixelSize: Int) -> UIImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceShouldCacheImmediately: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
    ]
    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
    return UIImage(cgImage: cgImage)
  }

  private static func decodeJxl(_ data: Data, maxPixelSize: Int) -> UIImage? {
    var cancelled = false
    guard let (width, height, pointer) = NativeCore.decodeJxl(
      data, targetWidth: Int64(maxPixelSize), targetHeight: Int64(maxPixelSize),
      maxPixelSize: ImageProcessing.maxPixelSize, cancelled: &cancelled
    ) else { return nil }
    return rgbaImage(pointer, width: width, height: height)
  }

  /// Wraps a malloc'd premultiplied RGBA buffer from the native core; the image frees it.
  private static func rgbaImage(_ pointer: UnsafeMutableRawPointer, width: Int, height: Int) -> UIImage? {
    let bytesPerRow = width * 4
    guard let provider = CGDataProvider(
      dataInfo: nil, data: pointer, size: bytesPerRow * height,
      releaseData: { _, data, _ in free(UnsafeMutableRawPointer(mutating: data)) }
    ) else {
      free(pointer)
      return nil
    }
    guard let cgImage = CGImage(
      width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
      provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
    ) else { return nil }
    return UIImage(cgImage: cgImage)
  }

  private static func key(_ url: URL, _ maxPixelSize: Int) -> NSString {
    "\(maxPixelSize)|\(url.absoluteString)" as NSString
  }

  private static func cost(of image: UIImage) -> Int {
    guard let cgImage = image.cgImage else { return 0 }
    return cgImage.bytesPerRow * cgImage.height
  }

  /// Characters Dart's Uri.encodeComponent leaves as is.
  private static let uriComponentAllowed = CharacterSet(
    charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()"
  )
}
