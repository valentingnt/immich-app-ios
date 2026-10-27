import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/constants/enums.dart';
import 'package:immich_mobile/generated/translations.g.dart';
import 'package:immich_mobile/platform/native_albums_api.g.dart';
import 'package:immich_mobile/providers/album/album_sort_by_options.provider.dart';
import 'package:immich_mobile/providers/infrastructure/album.provider.dart';
import 'package:immich_mobile/providers/infrastructure/settings.provider.dart';
import 'package:immich_mobile/providers/user.provider.dart';
import 'package:immich_mobile/routing/native_hostable_route.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/widgets/common/app_bar_dialog/app_bar_dialog.dart';

/// Backs the native Albums tab: sends it configuration and runs its actions with the existing Dart logic.
class NativeAlbumsBridge implements NativeAlbumsFlutterApi {
  NativeAlbumsBridge(this._ref, this._context) {
    NativeAlbumsFlutterApi.setUp(this);
  }

  final WidgetRef _ref;

  /// Context of the TabShell, used to show Flutter dialogs.
  final BuildContext Function() _context;
  final _api = NativeAlbumsHostApi();
  NativeAlbumsConfiguration? _sent;
  Future<void> _pendingSave = Future.value();

  void dispose() {
    NativeAlbumsFlutterApi.setUp(null);
    _ref.read(appRouterProvider).removeListener(_closeIfCovered);
  }

  /// Sends the configuration if any part of it changed.
  void sync(BuildContext context) {
    final configuration = _configuration(context.t);
    if (configuration == _sent) {
      return;
    }
    _sent = configuration;
    unawaited(_api.configure(configuration));
  }

  NativeAlbumsConfiguration _configuration(Translations t) {
    final album = _ref.read(appConfigProvider).album;
    return NativeAlbumsConfiguration(
      currentUserId: _ref.read(currentUserProvider)?.id,
      preferences: NativeAlbumsPreferences(
        sortMode: NativeAlbumSortMode.values.byName(album.sortMode.name),
        isReverse: album.isReverse,
        isGrid: album.isGrid,
      ),
      sortOptions: [
        for (final mode in AlbumSortMode.values)
          NativeAlbumSortOption(
            mode: NativeAlbumSortMode.values.byName(mode.name),
            label: mode.label(t),
            isAscendingByDefault: mode.defaultOrder == SortOrder.asc,
          ),
      ],
      strings: NativeAlbumsStrings(
        title: t.albums,
        searchPrompt: t.search_albums,
        filterAll: t.all,
        filterSharedWithMe: t.shared_with_me,
        filterMine: t.my_albums,
        owned: t.owned,
        sharedByTemplate: t.shared_by_user(user: '{user}'),
        noResults: t.album_search_not_found,
        createAlbum: t.common_create_new_album,
        sortBy: t.sort_albums_by,
        deleteAlbum: t.delete_album,
        deleteConfirmationTemplate: t.album_delete_confirmation(album: '{album}'),
        delete: t.delete,
        cancel: t.cancel,
      ),
    );
  }

  /// The album route pushed for native navigation (see FlutterRouteHost), while it is in the stack.
  bool get isHostingRoute => _isHostingRoute;
  bool _isHostingRoute = false;

  /// Whether the hosted album is the top route, so that the native back-swipe may pop it.
  bool get isHostedRouteOnTop =>
      _isHostingRoute && _ref.read(appRouterProvider).stackData.lastOrNull?.name == RemoteAlbumRoute.name;

  @override
  Future<bool> openAlbum(String albumId) async {
    final album = await _ref.read(remoteAlbumServiceProvider).get(albumId);
    if (album == null) {
      return false;
    }
    final router = _ref.read(appRouterProvider);
    _isHostingRoute = true;
    router.addListener(_closeIfCovered);
    NativeHostableRoute.pushForNativeHost = true;
    // Completes once the route is popped, from either side.
    final popped = router.push(RemoteAlbumRoute(album: album));
    unawaited(popped.whenComplete(_hostedRouteEnded));
    // Rendered, so that the engine shows the album as soon as it moves to the native stack.
    await WidgetsBinding.instance.endOfFrame;
    return true;
  }

  void _hostedRouteEnded() {
    if (!_isHostingRoute) {
      return;
    }
    _isHostingRoute = false;
    _ref.read(appRouterProvider).removeListener(_closeIfCovered);
    // No-op when native navigation popped first.
    unawaited(_api.closeAlbum());
  }

  /// Some flows go "back" to a tab by pushing it, e.g. AlbumsRoute after deleting the album, which
  /// stacks a second TabShell above the hosted album. With native navigation that means closing the
  /// album: keep the original TabShell, drop everything above it.
  void _closeIfCovered() {
    final router = _ref.read(appRouterProvider);
    final stack = router.stackData;
    final shellIndex = stack.indexWhere((route) => route.name == TabShellRoute.name);
    final hostedIndex = stack.indexWhere((route) => route.name == RemoteAlbumRoute.name, shellIndex + 1);
    if (shellIndex < 0 || hostedIndex < 0 || !stack.skip(hostedIndex + 1).any((r) => r.name == TabShellRoute.name)) {
      return;
    }
    final above = stack.sublist(shellIndex + 1).toSet();
    router.removeWhere(above.contains);
    _hostedRouteEnded();
  }

  @override
  void albumClosed() {
    if (!_isHostingRoute) {
      return;
    }
    // The album page is already off screen: drop it and whatever was opened from it.
    _ref.read(appRouterProvider).popUntilRouteWithName(TabShellRoute.name);
  }

  @override
  void createAlbum() => unawaited(_ref.read(appRouterProvider).push(const CreateAlbumRoute()));

  @override
  void openProfile() =>
      unawaited(showDialog(context: _context(), useRootNavigator: false, builder: (_) => const ImmichAppBarDialog()));

  @override
  Future<void> refresh() => _ref.read(remoteAlbumProvider.notifier).refresh();

  @override
  Future<void> deleteAlbum(String albumId) => _ref.read(remoteAlbumProvider.notifier).deleteAlbum(albumId);

  @override
  List<String> formatItemCounts(List<int> counts) {
    final t = _context().t;
    return [for (final count in counts) t.items_count(count: count)];
  }

  /// Serialized: SettingsRepository.write compares against its snapshot before awaiting the write,
  /// so overlapping saves from quick taps would leave the database and the snapshot out of sync.
  @override
  Future<void> savePreferences(NativeAlbumsPreferences preferences) =>
      _pendingSave = _pendingSave.then((_) => _writePreferences(preferences));

  Future<void> _writePreferences(NativeAlbumsPreferences preferences) async {
    final settings = _ref.read(settingsProvider);
    await settings.write(.albumSortMode, AlbumSortMode.values.byName(preferences.sortMode.name));
    await settings.write(.albumIsReverse, preferences.isReverse);
    await settings.write(.albumIsGrid, preferences.isGrid);
  }
}
