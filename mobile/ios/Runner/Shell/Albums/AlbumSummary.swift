import Foundation
import SQLiteData

/// One row of the Albums screen. Mirrors RemoteAlbumRepository.getAll on the Dart side.
/// Columns are decoded in declaration order: keep `query` in sync.
@Selection
struct AlbumSummary: Identifiable, Hashable {
  let id: String
  let name: String
  let description: String
  @Column(as: DriftDate.self) let createdAt: Date
  @Column(as: DriftDate.self) let updatedAt: Date
  let thumbnailAssetId: String?
  /// Base64 thumbhash of the thumbnail asset, for placeholders and the image cache key.
  let thumbnailThumbhash: String?
  let ownerId: String
  let ownerName: String
  /// Non-trashed assets only.
  let assetCount: Int
  /// Oldest and newest asset `local_date_time`, for the "most recent / oldest" sorts.
  @Column(as: DriftDate?.self) let startDate: Date?
  @Column(as: DriftDate?.self) let endDate: Date?
}

extension AlbumSummary {
  /// Tables whose changes affect `query`, as named by Drift.
  static let observedTables: Set<String> = [
    "remote_album_entity", "remote_album_asset_entity", "remote_album_user_entity", "remote_asset_entity", "user_entity",
  ]

  static let query = #sql(
    """
    SELECT
      album.id, album.name, album.description, album.created_at, album.updated_at, album.thumbnail_asset_id,
      thumbnail.thumb_hash,
      owner.id, owner.name,
      COUNT(DISTINCT asset.id),
      MIN(asset.local_date_time),
      MAX(asset.local_date_time)
    FROM remote_album_entity album
    JOIN remote_album_user_entity owner_link
      ON owner_link.album_id = album.id AND owner_link.role = \(AlbumUserRole.owner)
    JOIN user_entity owner ON owner.id = owner_link.user_id
    LEFT JOIN remote_album_asset_entity album_asset ON album_asset.album_id = album.id
    LEFT JOIN remote_asset_entity asset ON asset.id = album_asset.asset_id AND asset.deleted_at IS NULL
    LEFT JOIN remote_asset_entity thumbnail ON thumbnail.id = album.thumbnail_asset_id
    GROUP BY album.id
    """,
    as: AlbumSummary.self
  )
}
