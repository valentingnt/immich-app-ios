import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/platform/native_shell_api.g.dart';
import 'package:immich_mobile/providers/infrastructure/album.provider.dart';
import 'package:immich_mobile/providers/infrastructure/user.provider.dart';
import 'package:immich_mobile/providers/user.provider.dart';
import 'package:immich_mobile/routing/native_hostable_route.dart';
import 'package:immich_mobile/routing/router.dart';

typedef NativeRouteResolver = Future<PageRouteInfo?> Function(WidgetRef ref, Map<String, String> arguments);

/// Routes native screens can open by name (see NativeRoute), built from their arguments; null when
/// the target no longer exists. Each one must use `NativeHostableRoute.builder` in the router.
final Map<String, NativeRouteResolver> nativeRoutes = {
  'album': (ref, arguments) async {
    final album = await ref.read(remoteAlbumServiceProvider).get(arguments['id']!);
    return album == null ? null : RemoteAlbumRoute(album: album);
  },
  'favorites': _fixed(const FavoriteRoute()),
  'archive': _fixed(const ArchiveRoute()),
  'trash': _fixed(const TrashRoute()),
  'sharedLinks': _fixed(const SharedLinkRoute()),
  'folders': _fixed(FolderRoute()),
  'people': _fixed(const PeopleCollectionRoute()),
  'places': _fixed(PlaceRoute(currentLocation: null)),
  'localAlbums': _fixed(const LocalAlbumsRoute()),
  'memories': _fixed(const MemoryListRoute()),
  'partners': _fixed(const PartnerRoute()),
  'partner': (ref, arguments) async {
    final userId = ref.read(currentUserProvider)?.id;
    if (userId == null) {
      return null;
    }
    final partners = await ref.read(partnerServiceProvider).search(userId, .sharedWith).first;
    final partner = partners.where((partner) => partner.id == arguments['id']).firstOrNull;
    return partner == null ? null : PartnerDetailRoute(partner: partner);
  },
};

NativeRouteResolver _fixed(PageRouteInfo route) =>
    (_, _) async => route;

/// Dart side of FlutterRouteHost (iOS): pushes the routes native navigation asks for and keeps the
/// router in step with the native stack showing them. One route is hosted at a time.
class NativeRouteHost {
  NativeRouteHost(this._ref, this._api, {required this.onChanged});

  final WidgetRef _ref;
  final NativeShellHostApi _api;

  /// [isHosting] or [isHostedRouteOnTop] changed outside of a router notification.
  final VoidCallback onChanged;

  /// From right before the push until the route is popped, from either side.
  bool get isHosting => _isHosting;
  bool _isHosting = false;
  AutoRoutePage? _hostedPage;

  StackRouter get _router => _ref.read(appRouterProvider);

  /// Whether the hosted route is the top route, so that the native bar and back-swipe apply to it.
  bool get isHostedRouteOnTop => _hostedPage != null && identical(_router.stack.lastOrNull, _hostedPage);

  void dispose() => _router.removeListener(_closeIfCovered);

  Future<bool> push(NativeRoute request) async {
    if (_isHosting) {
      return false;
    }
    final route = await nativeRoutes[request.name]?.call(_ref, request.arguments);
    if (route == null) {
      return false;
    }
    // Set first: the native screen must stay visible above the route while it is pushed.
    _isHosting = true;
    NativeHostableRoute.pushForNativeHost = true;
    final popped = _router.push(route);
    // Rendered, so that the engine shows the route as soon as it moves to the native stack.
    await WidgetsBinding.instance.endOfFrame;
    final hostedPage = NativeHostableRoute.hostedPage;
    if (NativeHostableRoute.pushForNativeHost || hostedPage == null) {
      // Not declared with NativeHostableRoute.builder: left as a regular Flutter page.
      assert(false, '${route.routeName} is in nativeRoutes but not built by NativeHostableRoute.builder');
      NativeHostableRoute.pushForNativeHost = false;
      _isHosting = false;
      onChanged();
      return false;
    }
    _hostedPage = hostedPage;
    _router.addListener(_closeIfCovered);
    unawaited(popped.whenComplete(_ended));
    onChanged();
    return true;
  }

  /// Native navigation popped the route, which is already off screen: drop it and whatever was opened from it.
  void closedByNative() {
    if (_isHosting) {
      _router.popUntilRouteWithName(TabShellRoute.name);
    }
  }

  void _ended() {
    if (!_isHosting) {
      return;
    }
    _isHosting = false;
    _hostedPage = null;
    _router.removeListener(_closeIfCovered);
    onChanged();
    // No-op when native navigation popped first.
    unawaited(_api.closeHostedRoute());
  }

  /// Some flows go "back" to a tab by pushing it, e.g. AlbumsRoute after deleting the album, which
  /// stacks a second TabShell above the hosted route. With native navigation that means closing the
  /// route: keep the original TabShell, drop everything above it.
  void _closeIfCovered() {
    final stack = _router.stack;
    final hostedIndex = stack.indexWhere((page) => identical(page, _hostedPage));
    if (hostedIndex < 0 || !stack.skip(hostedIndex + 1).any((page) => page.name == TabShellRoute.name)) {
      return;
    }
    final shellIndex = stack.lastIndexWhere((page) => page.name == TabShellRoute.name, hostedIndex);
    final above = stack.sublist(shellIndex + 1).map((page) => page.routeData).toSet();
    _router.removeWhere(above.contains);
    _ended();
  }
}
