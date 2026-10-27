import 'dart:async';
import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/events.model.dart';
import 'package:immich_mobile/domain/utils/event_stream.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/pages/common/native_albums.dart';
import 'package:immich_mobile/pages/common/native_route_host.dart';
import 'package:immich_mobile/platform/native_shell_api.g.dart';
import 'package:immich_mobile/providers/infrastructure/db.provider.dart';
import 'package:immich_mobile/providers/infrastructure/settings.provider.dart';
import 'package:immich_mobile/providers/theme.provider.dart';
import 'package:immich_mobile/routing/native_hostable_route.dart';
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
  StreamSubscription? _databaseSubscription;
  NativeAlbumsBridge? _albums;
  NativeRouteHost? _routes;
  bool _attached = false;
  bool _isMultiSelectEnabled = false;
  List<NativeTab>? _sentTabs;
  NativeShellState? _sentState;
  NativeAppearance? _sentAppearance;

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
    _routes = NativeRouteHost(ref, _api, onChanged: _sync);
    _albums = NativeAlbumsBridge(ref, () => context);
    _databaseSubscription = _watchDatabase();
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
      _albums?.dispose();
      _routes?.dispose();
      unawaited(_databaseSubscription?.cancel());
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
              isHostingRoute: false,
              isHostedRouteOnTop: false,
            ),
          ),
        );
      }
    }
    super.dispose();
  }

  @override
  void onTabSelected(int index) => widget.onSelected(index);

  @override
  Future<bool> openRoute(NativeRoute route) => _routes?.push(route) ?? Future.value(false);

  @override
  void hostedRouteClosed() => _routes?.closedByNative();

  @override
  void onHostedRouteChanged(bool isHosted, double barHeight) {
    ref.read(nativeHostBarHeightProvider.notifier).state = isHosted ? barHeight : null;
  }

  /// Forwards Drift table changes, batched, so native screens reading the database can refresh.
  StreamSubscription _watchDatabase() {
    final pending = <String>{};
    Timer? debounce;
    return ref.read(driftProvider).tableUpdates().listen((updates) {
      pending.addAll(updates.map((update) => update.table));
      debounce?.cancel();
      debounce = Timer(const Duration(milliseconds: 250), () {
        final tables = pending.toList();
        pending.clear();
        unawaited(_api.databaseDidChange(tables));
      });
    });
  }

  NativeAppearance _computeAppearance() {
    final theme = ref.read(immichThemeProvider);
    return NativeAppearance(
      themeMode: switch (ref.read(appConfigProvider).theme.mode) {
        ThemeMode.light => NativeThemeMode.light,
        ThemeMode.dark => NativeThemeMode.dark,
        ThemeMode.system => NativeThemeMode.system,
      },
      lightTint: theme.light.primary.toARGB32(),
      darkTint: theme.dark.primary.toARGB32(),
    );
  }

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
      isHostingRoute: _routes?.isHosting ?? false,
      // Popups (dialogs, sheets) are not in the router stack but cover the hosted page too.
      isHostedRouteOnTop: (_routes?.isHostedRouteOnTop ?? false) && NativeShellRouteObserver.popupCount.value == 0,
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

    final appearance = _computeAppearance();
    if (appearance != _sentAppearance) {
      _sentAppearance = appearance;
      unawaited(_api.setAppearance(appearance));
    }

    _albums?.sync(context);

    final state = _computeState();
    if (state != _sentState) {
      _sentState = state;
      unawaited(_api.setState(state));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Rebuilds on availability, locale (labels), readonly mode (destinations), orientation,
    // theme and settings.
    if (watchNativeShellEnabled(ref) && _available) {
      _attach();
      context.orientation;
      ref.watch(immichThemeProvider);
      ref.watch(appConfigProvider);
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
