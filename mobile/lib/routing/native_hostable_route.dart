import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Height of the native navigation bar above the route hosted by native navigation, or null when
/// no route is hosted. The hosted page drops its back button (the native bar has one) and removes
/// this height from its top padding so that its toolbar lines up with the native bar.
final nativeHostBarHeightProvider = StateProvider<double?>((ref) => null);

/// Routes that native navigation can host (iOS native shell, see FlutterRouteHost).
///
/// When pushed for native navigation, the page appears without a Flutter transition and without
/// Flutter's back-swipe: the native stack animates it and owns the back gesture. Otherwise it is
/// the same MaterialPageRoute auto_route builds by default.
abstract final class NativeHostableRoute {
  /// Set right before pushing a route on behalf of native navigation.
  static bool pushForNativeHost = false;

  /// The route currently shown by native navigation, if any.
  static Route? _hostedRoute;

  /// Whether [context] belongs to the route shown by native navigation (not another route of the same page).
  static bool isHosted(BuildContext context) {
    final route = ModalRoute.of(context);
    return route != null && identical(route, _hostedRoute);
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
