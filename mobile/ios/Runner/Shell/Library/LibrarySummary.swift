import Foundation
import SQLiteData

/// Previews of the Library collections, each mirroring the Dart query behind its card.
/// Columns are decoded in declaration order: keep the queries in sync.
enum LibrarySummary {
  /// Number of items previewed on a collection card.
  static let previewCount = 4

  /// Tables whose changes affect the queries below, as named by Drift.
  static let observedTables: Set<String> = [
    "person_entity", "asset_face_entity", "remote_asset_entity", "memory_entity", "memory_asset_entity",
    "local_album_entity", "local_album_asset_entity", "local_asset_entity", "partner_entity", "user_entity",
    "remote_exif_entity",
  ]

  /// Mirrors PersonDao.watchAll: visible people with enough visible faces on timeline assets, or a name.
  /// Named people first, then by face count.
  @Selection
  struct Person: Identifiable, Hashable {
    let id: String
    @Column(as: DriftDate.self) let updatedAt: Date
  }

  static func people(minimumFaces: Int) -> SQLQueryExpression<Person> {
    #sql(
      """
      SELECT person.id, person.updated_at
      FROM person_entity person
      JOIN asset_face_entity face ON face.person_id = person.id
      JOIN remote_asset_entity asset ON asset.id = face.asset_id
      WHERE person.is_hidden = 0 AND face.is_visible = 1 AND face.deleted_at IS NULL
        AND asset.deleted_at IS NULL AND asset.visibility = \(AssetVisibility.timeline)
      GROUP BY person.id
      HAVING COUNT(face.id) >= \(minimumFaces) OR person.name != ''
      ORDER BY person.name != '' DESC, COUNT(face.id) DESC
      LIMIT \(previewCount)
      """,
      as: Person.self
    )
  }

  /// Mirrors DriftMemoryRepository.getAll (not limited to today): the user's memories with at least
  /// one timeline asset, newest first, each shown by its oldest asset.
  @Selection
  struct Memory: Identifiable, Hashable {
    let id: String
    let assetId: String
    let assetThumbhash: String?
  }

  static func memories(ownerId: String) -> SQLQueryExpression<Memory> {
    #sql(
      """
      SELECT memory.id, asset.id, asset.thumb_hash
      FROM memory_entity memory
      JOIN remote_asset_entity asset ON asset.id = (
        SELECT candidate.id
        FROM memory_asset_entity link
        JOIN remote_asset_entity candidate ON candidate.id = link.asset_id
        WHERE link.memory_id = memory.id
          AND candidate.deleted_at IS NULL AND candidate.visibility = \(AssetVisibility.timeline)
        ORDER BY candidate.created_at
        LIMIT 1
      )
      WHERE memory.owner_id = \(ownerId) AND memory.deleted_at IS NULL
      ORDER BY memory.memory_at DESC
      LIMIT \(previewCount)
      """,
      as: Memory.self
    )
  }

  /// Mirrors localAlbumProvider: device albums with assets, most recently updated first, each shown
  /// by its newest asset (LocalAlbumRepository.getThumbnail). Ids are PhotoKit local identifiers.
  @Selection
  struct LocalAlbum: Identifiable, Hashable {
    let id: String
    let thumbnailAssetId: String
  }

  static let localAlbums = #sql(
    """
    SELECT album.id, asset.id
    FROM local_album_entity album
    JOIN local_asset_entity asset ON asset.id = (
      SELECT candidate.id
      FROM local_album_asset_entity link
      JOIN local_asset_entity candidate ON candidate.id = link.asset_id
      WHERE link.album_id = album.id
      ORDER BY candidate.created_at DESC
      LIMIT 1
    )
    ORDER BY album.updated_at DESC
    LIMIT \(previewCount)
    """,
    as: LocalAlbum.self
  )

  /// Where the newest geotagged timeline photo was taken: centres the Places preview.
  @Selection
  struct Place: Hashable {
    let latitude: Double
    let longitude: Double
  }

  static let lastPlace = #sql(
    """
    SELECT exif.latitude, exif.longitude
    FROM remote_exif_entity exif
    JOIN remote_asset_entity asset ON asset.id = exif.asset_id
    WHERE exif.latitude IS NOT NULL AND exif.longitude IS NOT NULL
      AND asset.deleted_at IS NULL AND asset.visibility = \(AssetVisibility.timeline)
    ORDER BY asset.created_at DESC
    LIMIT 1
    """,
    as: Place.self
  )

  /// Mirrors DriftPartnerRepository.search(.sharedWith): users sharing their photos with the user.
  @Selection
  struct Partner: Identifiable, Hashable {
    let id: String
    let name: String
  }

  static func partners(userId: String) -> SQLQueryExpression<Partner> {
    #sql(
      """
      SELECT user.id, user.name
      FROM partner_entity partner
      JOIN user_entity user ON user.id = partner.shared_by_id
      WHERE partner.shared_with_id = \(userId) AND user.id != \(userId)
      ORDER BY partner.shared_by_id
      """,
      as: Partner.self
    )
  }
}
