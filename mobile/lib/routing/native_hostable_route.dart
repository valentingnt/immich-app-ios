import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Height of the native navigation bar above the route hosted by native navigation, or null when
/// no route is hosted.
final nativeHostBarHeightProvider = StateProvider<double?>((ref) => null);

/// Routes native navigation can host (iOS native shell, see FlutterRouteHost and NativeRouteHost).
/// Declare them in the router with `type: NativeHostableRoute.type`.
///
/// When pushed for native navigation, the page appears without a Flutter transition and without
/// Flutter's back-swipe: the native stack animates it and owns the back gesture. Otherwise it is
/// the same MaterialPageRoute auto_route builds by default.
///
/// A hosted page sits under the transparent native bar, which has the back button. Without any
/// change to the page: its app bar implies no back button, its top padding leaves out the native
/// bar so that its toolbar lines up with it, and its title keeps clear of the native back button.
/// App bars with their own back button hide it when [isHosted].
abstract final class NativeHostableRoute {
  static final type = RouteType.custom(customRouteBuilder: builder);

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

  static Route<T> builder<T>(BuildContext context, Widget child, AutoRoutePage<T> page) {
    if (!pushForNativeHost) {
      return MaterialPageRoute<T>(settings: page, fullscreenDialog: page.fullscreenDialog, builder: (_) => child);
    }
    pushForNativeHost = false;
    final route = _HostedPageRoute<T>(
      settings: page,
      child: _UnderNativeBar(child: child),
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

class _HostedPageRoute<T> extends PageRouteBuilder<T> {
  _HostedPageRoute({required super.settings, required Widget child})
    : super(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, _, _) => child,
      );

  /// Native navigation shows the back button.
  @override
  bool get impliesAppBarDismissal => false;
}

/// Lays the hosted page out as if the native bar were not there, except for keeping app bar
/// titles clear of the native back button.
class _UnderNativeBar extends ConsumerWidget {
  const _UnderNativeBar({required this.child});

  final Widget child;

  /// Leading inset of the native back button, plus the default title spacing.
  static const _titleSpacing = 72.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final barHeight = ref.watch(nativeHostBarHeightProvider) ?? 0;
    final mediaQuery = MediaQuery.of(context);
    final theme = Theme.of(context);
    return MediaQuery(
      data: mediaQuery.copyWith(
        padding: mediaQuery.padding.copyWith(top: mediaQuery.padding.top - barHeight),
        viewPadding: mediaQuery.viewPadding.copyWith(top: mediaQuery.viewPadding.top - barHeight),
      ),
      child: Theme(
        data: theme.copyWith(appBarTheme: theme.appBarTheme.copyWith(titleSpacing: _titleSpacing)),
        child: child,
      ),
    );
  }
}
