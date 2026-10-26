import 'dart:async';
import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/events.model.dart';
import 'package:immich_mobile/domain/utils/event_stream.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/platform/native_shell_api.g.dart';
import 'package:immich_mobile/routing/router.dart';

/// Whether the native iOS chrome (iOS 26+, Liquid Glass) replaces the Flutter one.
final nativeShellAvailableProvider = FutureProvider<bool>((ref) async {
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
bool watchNativeShellEnabled(WidgetRef ref) => ref.watch(nativeShellAvailableProvider).valueOrNull ?? Platform.isIOS;

/// Native appearance of each TabShell destination, in the same order.
/// [nativeScreen] names a native screen that replaces the Flutter page while its tab is active.
const _nativeTabs = [
  (symbol: 'photo.on.rectangle', nativeScreen: null),
  (symbol: 'magnifyingglass', nativeScreen: null),
  (symbol: 'rectangle.stack', nativeScreen: 'albums'),
  (symbol: 'square.grid.2x2', nativeScreen: null),
];

/// Mirrors the TabShell state onto the native chrome. Renders [child] unchanged.
class NativeShell extends ConsumerStatefulWidget {
  const NativeShell({
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
  ConsumerState<NativeShell> createState() => _NativeShellState();
}

class _NativeShellState extends ConsumerState<NativeShell> implements NativeShellFlutterApi {
  final _api = NativeShellHostApi();
  StackRouter? _rootRouter;
  StreamSubscription? _multiSelectSubscription;
  bool _attached = false;
  bool _isMultiSelectEnabled = false;
  List<NativeTab>? _sentTabs;
  NativeShellState? _sentState;

  bool get _available => ref.read(nativeShellAvailableProvider).valueOrNull ?? false;

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
    if (_attached || !_available) {
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
  void didUpdateWidget(covariant NativeShell oldWidget) {
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
      final state = _sentState;
      if (state != null) {
        unawaited(
          _api.setState(
            NativeShellState(
              selectedIndex: state.selectedIndex,
              isShellVisible: false,
              isTabBarSuppressed: state.isTabBarSuppressed,
            ),
          ),
        );
      }
    }
    super.dispose();
  }

  @override
  void onTabSelected(int index) => widget.onSelected(index);

  /// The single place deciding what the native chrome shows.
  NativeShellState _computeState() {
    final isTabShellOnTop = _rootRouter?.stackData.lastOrNull?.name == TabShellRoute.name;
    return NativeShellState(
      selectedIndex: widget.tabsRouter.activeIndex,
      isShellVisible:
          isTabShellOnTop &&
          NativeShellRouteObserver.popupCount.value == 0 &&
          context.orientation == Orientation.portrait,
      isTabBarSuppressed: _isMultiSelectEnabled,
    );
  }

  void _sync() {
    if (!mounted || !_attached) {
      return;
    }

    final tabs = [
      for (final (i, d) in widget.destinations.indexed)
        NativeTab(
          label: d.label,
          symbol: _nativeTabs[i].symbol,
          enabled: d.enabled,
          nativeScreen: _nativeTabs[i].nativeScreen,
        ),
    ];
    if (!listEquals(tabs, _sentTabs)) {
      _sentTabs = tabs;
      unawaited(_api.setTabs(tabs));
    }

    final state = _computeState();
    if (state != _sentState) {
      _sentState = state;
      unawaited(_api.setState(state));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Rebuilds on availability, locale (labels), readonly mode (destinations) and orientation.
    if (watchNativeShellEnabled(ref) && _available) {
      _attach();
      context.orientation;
      WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
    }
    return widget.child;
  }
}

/// Counts popup routes (dialogs, bottom sheets) above the TabShell, which would otherwise render under the native chrome.
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
