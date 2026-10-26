import 'dart:async';
import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/events.model.dart';
import 'package:immich_mobile/domain/utils/event_stream.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/platform/native_shell_api.g.dart';
import 'package:immich_mobile/routing/router.dart';

/// Whether the native iOS tab bar (iOS 26+, Liquid Glass) replaces the Flutter one.
final nativeTabBarAvailableProvider = FutureProvider<bool>((ref) async {
  if (!Platform.isIOS) {
    return false;
  }
  try {
    return await NativeShellHostApi().isAvailable();
  } catch (_) {
    return false;
  }
});

/// Synchronous read for widgets. While unresolved on iOS, assume native to avoid a flash of the Flutter bar.
bool watchNativeTabBarEnabled(WidgetRef ref) => ref.watch(nativeTabBarAvailableProvider).valueOrNull ?? Platform.isIOS;

/// SF Symbols, in the same order as the TabShell destinations.
const _tabSymbols = ['photo.on.rectangle', 'magnifyingglass', 'rectangle.stack', 'square.grid.2x2'];

/// Mirrors the TabShell state onto the native tab bar. Renders [child] unchanged.
class NativeTabBar extends ConsumerStatefulWidget {
  const NativeTabBar({
    super.key,
    required this.tabsRouter,
    required this.destinations,
    required this.onSelected,
    required this.child,
  });

  final TabsRouter tabsRouter;
  final List<NavigationDestination> destinations;
  final void Function(int index) onSelected;
  final Widget child;

  @override
  ConsumerState<NativeTabBar> createState() => _NativeTabBarState();
}

class _NativeTabBarState extends ConsumerState<NativeTabBar> implements NativeShellFlutterApi {
  final _api = NativeShellHostApi();
  StackRouter? _rootRouter;
  StreamSubscription? _multiSelectSubscription;
  bool _attached = false;
  bool _isMultiSelectEnabled = false;
  bool? _lastHidden;
  int? _lastSelectedIndex;
  List<(String, bool)>? _lastTabs;

  bool get _enabled => ref.read(nativeTabBarAvailableProvider).valueOrNull ?? false;

  @override
  void initState() {
    super.initState();
    _multiSelectSubscription = EventStream.shared.listen<MultiSelectToggleEvent>((event) {
      _isMultiSelectEnabled = event.isEnabled;
      _sync();
    });
    NativeShellRouteObserver.popupCount.addListener(_sync);
  }

  void _attach() {
    if (_attached || !_enabled) {
      return;
    }
    _attached = true;
    NativeShellFlutterApi.setUp(this);
    final rootRouter = ref.read(appRouterProvider);
    rootRouter.addListener(_sync);
    _rootRouter = rootRouter;
    widget.tabsRouter.addListener(_sync);
  }

  @override
  void didUpdateWidget(covariant NativeTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_attached && oldWidget.tabsRouter != widget.tabsRouter) {
      oldWidget.tabsRouter.removeListener(_sync);
      widget.tabsRouter.addListener(_sync);
    }
  }

  @override
  void dispose() {
    unawaited(_multiSelectSubscription?.cancel());
    NativeShellRouteObserver.popupCount.removeListener(_sync);
    if (_attached) {
      NativeShellFlutterApi.setUp(null);
      _rootRouter?.removeListener(_sync);
      widget.tabsRouter.removeListener(_sync);
      unawaited(_api.setTabBarHidden(true, false));
    }
    super.dispose();
  }

  @override
  void onTabSelected(int index) => widget.onSelected(index);

  void _sync() {
    if (!mounted || !_attached) {
      return;
    }

    final tabs = [for (final d in widget.destinations) (d.label, d.enabled)];
    if (_lastTabs == null || !_sameTabs(tabs, _lastTabs!)) {
      _lastTabs = tabs;
      unawaited(
        _api.setTabs([
          for (final (i, (label, enabled)) in tabs.indexed)
            NativeTab(label: label, symbol: _tabSymbols[i], enabled: enabled),
        ]),
      );
    }

    final selectedIndex = widget.tabsRouter.activeIndex;
    if (selectedIndex != _lastSelectedIndex) {
      _lastSelectedIndex = selectedIndex;
      unawaited(_api.setSelectedIndex(selectedIndex));
    }

    final isTabShellOnTop = _rootRouter?.stackData.lastOrNull?.name == TabShellRoute.name;
    final hidden =
        _isMultiSelectEnabled ||
        context.orientation == Orientation.landscape ||
        !isTabShellOnTop ||
        NativeShellRouteObserver.popupCount.value > 0;
    if (hidden != _lastHidden) {
      // Appear without animation the first time so the grid does not jump.
      final animated = _lastHidden != null;
      _lastHidden = hidden;
      unawaited(_api.setTabBarHidden(hidden, animated));
    }
  }

  static bool _sameTabs(List<(String, bool)> a, List<(String, bool)> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    // Rebuilds on availability, locale (labels), readonly mode (destinations) and orientation.
    if (watchNativeTabBarEnabled(ref) && _enabled) {
      _attach();
      context.orientation;
      WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
    }
    return widget.child;
  }
}

/// Counts popup routes (dialogs, bottom sheets) above the TabShell, which would otherwise render under the native bar.
class NativeShellRouteObserver extends NavigatorObserver {
  /// Shared across instances: auto_route may create one observer per navigator.
  static final popupCount = ValueNotifier<int>(0);

  @override
  void didPush(Route route, Route? previousRoute) {
    if (route is PopupRoute) {
      popupCount.value++;
    }
  }

  @override
  void didPop(Route route, Route? previousRoute) => _onRemoved(route);

  @override
  void didRemove(Route route, Route? previousRoute) => _onRemoved(route);

  @override
  void didReplace({Route? newRoute, Route? oldRoute}) {
    if (oldRoute != null) {
      _onRemoved(oldRoute);
    }
    if (newRoute != null) {
      didPush(newRoute, null);
    }
  }

  void _onRemoved(Route route) {
    if (route is PopupRoute && popupCount.value > 0) {
      popupCount.value--;
    }
  }
}
