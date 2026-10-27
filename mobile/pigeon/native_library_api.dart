import 'package:pigeon/pigeon.dart';

// iOS only: the native (SwiftUI) Library tab, iOS 26+. Data is read from the database natively;
// destinations are Flutter pages opened through native navigation (see NativeRoute).
@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/platform/native_library_api.g.dart',
    swiftOut: 'ios/Runner/Shell/Library/NativeLibrary.g.swift',
    swiftOptions: SwiftOptions(includeErrorClass: false),
    dartOptions: DartOptions(),
    dartPackageName: 'immich_mobile',
  ),
)
/// Translated strings. Templates keep their placeholder (`{user}`) for native substitution.
class NativeLibraryStrings {
  final String title;
  final String favorites;
  final String archived;
  final String sharedLinks;
  final String trash;
  final String people;
  final String places;
  final String onThisDevice;
  final String memories;
  final String folders;
  final String lockedFolder;
  final String partners;
  final String partnerPhotosTemplate;

  const NativeLibraryStrings({
    required this.title,
    required this.favorites,
    required this.archived,
    required this.sharedLinks,
    required this.trash,
    required this.people,
    required this.places,
    required this.onThisDevice,
    required this.memories,
    required this.folders,
    required this.lockedFolder,
    required this.partners,
    required this.partnerPhotosTemplate,
  });
}

/// Everything the screen needs from Dart, resent whenever any part changes.
class NativeLibraryConfiguration {
  final String? currentUserId;

  /// The user's "minimum faces" preference: people with fewer faces (and no name) are left out.
  final int minimumFaces;
  final bool isMemoriesEnabled;

  /// The server has the trash enabled.
  final bool isTrashEnabled;
  final NativeLibraryStrings strings;

  const NativeLibraryConfiguration({
    required this.currentUserId,
    required this.minimumFaces,
    required this.isMemoriesEnabled,
    required this.isTrashEnabled,
    required this.strings,
  });
}

@HostApi()
abstract class NativeLibraryHostApi {
  void configure(NativeLibraryConfiguration configuration);
}

@FlutterApi()
abstract class NativeLibraryFlutterApi {
  void openProfile();

  /// Pushed as a regular Flutter page: its guard may ask for authentication first.
  void openLockedFolder();
}
