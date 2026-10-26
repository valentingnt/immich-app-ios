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

  void dispose() => NativeAlbumsFlutterApi.setUp(null);

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

  @override
  Future<void> openAlbum(String albumId) async {
    final album = await _ref.read(remoteAlbumServiceProvider).get(albumId);
    if (album != null) {
      unawaited(_ref.read(appRouterProvider).push(RemoteAlbumRoute(album: album)));
    }
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
  Future<void> savePreferences(NativeAlbumsPreferences preferences) async {
    final settings = _ref.read(settingsProvider);
    await settings.write(.albumSortMode, AlbumSortMode.values.byName(preferences.sortMode.name));
    await settings.write(.albumIsReverse, preferences.isReverse);
    await settings.write(.albumIsGrid, preferences.isGrid);
  }
}
