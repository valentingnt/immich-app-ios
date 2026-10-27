import 'package:pigeon/pigeon.dart';

// iOS only: the native (SwiftUI) Albums tab, iOS 26+. Data is read from the database natively;
// actions and preferences go through the existing Dart logic.
@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/platform/native_albums_api.g.dart',
    swiftOut: 'ios/Runner/Shell/Albums/NativeAlbums.g.swift',
    swiftOptions: SwiftOptions(includeErrorClass: false),
    dartOptions: DartOptions(),
    dartPackageName: 'immich_mobile',
  ),
)
enum NativeAlbumSortMode { title, assetCount, lastModified, created, mostRecent, mostOldest }

class NativeAlbumSortOption {
  final NativeAlbumSortMode mode;
  final String label;
  final bool isAscendingByDefault;

  const NativeAlbumSortOption({required this.mode, required this.label, required this.isAscendingByDefault});
}

class NativeAlbumsPreferences {
  final NativeAlbumSortMode sortMode;
  final bool isReverse;
  final bool isGrid;

  const NativeAlbumsPreferences({required this.sortMode, required this.isReverse, required this.isGrid});
}

/// Translated strings. Templates keep their placeholder (`{user}`, `{album}`) for native substitution.
class NativeAlbumsStrings {
  final String title;
  final String searchPrompt;
  final String filterAll;
  final String filterSharedWithMe;
  final String filterMine;
  final String owned;
  final String sharedByTemplate;
  final String noResults;
  final String createAlbum;
  final String sortBy;
  final String deleteAlbum;
  final String deleteConfirmationTemplate;
  final String delete;
  final String cancel;

  const NativeAlbumsStrings({
    required this.title,
    required this.searchPrompt,
    required this.filterAll,
    required this.filterSharedWithMe,
    required this.filterMine,
    required this.owned,
    required this.sharedByTemplate,
    required this.noResults,
    required this.createAlbum,
    required this.sortBy,
    required this.deleteAlbum,
    required this.deleteConfirmationTemplate,
    required this.delete,
    required this.cancel,
  });
}

/// Everything the screen needs from Dart, resent whenever any part changes.
class NativeAlbumsConfiguration {
  final String? currentUserId;
  final NativeAlbumsPreferences preferences;
  final List<NativeAlbumSortOption> sortOptions;
  final NativeAlbumsStrings strings;

  const NativeAlbumsConfiguration({
    required this.currentUserId,
    required this.preferences,
    required this.sortOptions,
    required this.strings,
  });
}

@HostApi()
abstract class NativeAlbumsHostApi {
  void configure(NativeAlbumsConfiguration configuration);

  /// The natively hosted album route was popped on the Dart side (e.g. its back button).
  void closeAlbum();
}

@FlutterApi()
abstract class NativeAlbumsFlutterApi {
  /// Pushes the album route, ready to be shown by native navigation once this returns true.
  @async
  bool openAlbum(String albumId);

  /// Native navigation popped the hosted album: drop its route (and anything above it).
  void albumClosed();

  void createAlbum();

  void openProfile();

  @async
  void refresh();

  /// Already confirmed natively.
  @async
  void deleteAlbum(String albumId);

  void savePreferences(NativeAlbumsPreferences preferences);

  /// "1 item", "505 items"… with Dart's plural rules, in the same order as [counts].
  List<String> formatItemCounts(List<int> counts);
}
