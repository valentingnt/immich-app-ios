import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/data/store/user_metadata.dart';
import 'package:immich_mobile/generated/translations.g.dart';
import 'package:immich_mobile/platform/native_library_api.g.dart';
import 'package:immich_mobile/providers/server_info.provider.dart';
import 'package:immich_mobile/providers/user.provider.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/widgets/common/app_bar_dialog/app_bar_dialog.dart';

/// Backs the native Library tab: sends it configuration and runs its actions with the existing Dart logic.
class NativeLibraryBridge implements NativeLibraryFlutterApi {
  NativeLibraryBridge(this._ref, this._context) {
    NativeLibraryFlutterApi.setUp(this);
  }

  final WidgetRef _ref;

  /// Context of the TabShell, used to show Flutter dialogs.
  final BuildContext Function() _context;
  final _api = NativeLibraryHostApi();
  NativeLibraryConfiguration? _sent;

  void dispose() => NativeLibraryFlutterApi.setUp(null);

  /// Providers the configuration is built from, for the shell to rebuild on.
  static void watchSources(WidgetRef ref) {
    ref.watch(currentUserProvider);
    ref.watch(UserMetadataStore.instance.preferences());
    ref.watch(serverInfoProvider.select((info) => info.serverFeatures.trash));
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

  NativeLibraryConfiguration _configuration(Translations t) {
    final user = _ref.read(currentUserProvider);
    return NativeLibraryConfiguration(
      currentUserId: user?.id,
      minimumFaces: _ref.read(UserMetadataStore.instance.preferences()).valueOrNull?.minimumFaces ?? 3,
      isMemoriesEnabled: user?.memoryEnabled ?? true,
      isTrashEnabled: _ref.read(serverInfoProvider).serverFeatures.trash,
      strings: NativeLibraryStrings(
        title: t.library$,
        favorites: t.favorites,
        archived: t.archived,
        sharedLinks: t.shared_links,
        trash: t.trash,
        people: t.people,
        places: t.places,
        onThisDevice: t.on_this_device,
        memories: t.memories,
        folders: t.folders,
        lockedFolder: t.locked_folder,
        partners: t.partners,
        partnerPhotosTemplate: t.partner_list_user_photos(user: '{user}'),
      ),
    );
  }

  @override
  void openProfile() =>
      unawaited(showDialog(context: _context(), useRootNavigator: false, builder: (_) => const ImmichAppBarDialog()));

  @override
  void openLockedFolder() => unawaited(_ref.read(appRouterProvider).push(const LockedFolderRoute()));
}
