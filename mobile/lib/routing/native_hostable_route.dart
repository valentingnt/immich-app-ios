import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Height of the native navigation bar above the route hosted by native navigation, or null when
/// no route is hosted.
final nativeHostBarHeightProvider = StateProvider<double?>((ref) => null);

/// Routes native navigation can host (iOS native shell, see FlutterRouteHost and NativeRouteHost).
///
/// When pushed for native navigation, the page appears without a Flutter transition and without
/// Flutter's back-swipe: the native stack animates it and owns the back gesture. Otherwise it is
/// the same MaterialPageRoute auto_route builds by default.
///
/// A hosted page sits under the native bar, which has the back button: its app bar drops its own
/// back button when [watchBarHeight] is not null, and is wrapped in [underNativeBar].
abstract final class NativeHostableRoute {
  /// Set right before pushing a route on behalf of native navigation.
  static bool pushForNativeHost = false;

  /// The route currently shown by native navigation, if any.
  static Route? _hostedRoute;

  static AutoRoutePage? get hostedPage => _hostedRoute?.settings as AutoRoutePage?;

  /// Whether [context] belongs to the route shown by native navigation (not another route of the same page).
  static bool isHosted(BuildContext context) {
    final route = ModalRoute.of(context);
    return route != null && identical(route, _hostedRoute);
  }

  /// Height of the native bar above [context]'s page while native navigation hosts it, else null.
  static double? watchBarHeight(BuildContext context, WidgetRef ref) =>
      isHosted(context) ? ref.watch(nativeHostBarHeightProvider) : null;

  /// Lays [appBar] out under the native bar, so that its toolbar lines up with it.
  static Widget underNativeBar(BuildContext context, double? barHeight, Widget appBar) {
    if (barHeight == null) {
      return appBar;
    }
    final mediaQuery = MediaQuery.of(context);
    return MediaQuery(
      data: mediaQuery.copyWith(padding: mediaQuery.padding.copyWith(top: mediaQuery.padding.top - barHeight)),
      child: appBar,
    );
  }

  static Route<T> builder<T>(BuildContext context, Widget child, AutoRoutePage<T> page) {
    if (!pushForNativeHost) {
      return MaterialPageRoute<T>(settings: page, fullscreenDialog: page.fullscreenDialog, builder: (_) => child);
    }
    pushForNativeHost = false;
    final route = PageRouteBuilder<T>(
      settings: page,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (_, _, _) => child,
    );
    _hostedRoute = route;
    unawaited(
      route.popped.whenComplete(() {
        if (identical(_hostedRoute, route)) {
          _hostedRoute = null;
        }
      }),
    );
    return route;
  }
}
