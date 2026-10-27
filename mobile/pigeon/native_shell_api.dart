import 'package:pigeon/pigeon.dart';

// iOS only: native chrome (Liquid Glass) around the Flutter view, iOS 26+.
@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/platform/native_shell_api.g.dart',
    swiftOut: 'ios/Runner/Shell/NativeShell.g.swift',
    swiftOptions: SwiftOptions(includeErrorClass: false),
    dartOptions: DartOptions(),
    dartPackageName: 'immich_mobile',
  ),
)
class NativeTab {
  final String label;

  /// SF Symbol name
  final String symbol;
  final bool enabled;

  /// Id of a native screen shown in place of the Flutter page for this tab (e.g. "albums"), if any.
  final String? nativeScreen;

  const NativeTab({required this.label, required this.symbol, required this.enabled, this.nativeScreen});
}

/// Everything the native chrome needs to render, sent as one snapshot so updates are atomic.
class NativeShellState {
  final int selectedIndex;

  /// False when the TabShell is not the visible screen (pushed route, popup, landscape, logged out).
  final bool isShellVisible;

  /// Hides the tab bar while the shell itself stays visible (multi-select).
  final bool isTabBarSuppressed;

  /// A Flutter route is hosted by native navigation: native screens stay visible under it.
  final bool isHostingRoute;

  /// The hosted route is the top Flutter route (no route or popup above it), so the native bar,
  /// back button and back-swipe apply to it.
  final bool isHostedRouteOnTop;

  const NativeShellState({
    required this.selectedIndex,
    required this.isShellVisible,
    required this.isTabBarSuppressed,
    required this.isHostingRoute,
    required this.isHostedRouteOnTop,
  });
}

/// A Flutter route a native screen asks to open, by its name in Dart's registry of hostable routes.
class NativeRoute {
  final String name;
  final Map<String, String> arguments;

  const NativeRoute({required this.name, required this.arguments});
}

enum NativeThemeMode { system, light, dark }

/// The app's own theme settings, applied to every native view.
class NativeAppearance {
  final NativeThemeMode themeMode;

  /// ARGB primary colors of the light and dark themes.
  final int lightTint;
  final int darkTint;

  const NativeAppearance({required this.themeMode, required this.lightTint, required this.darkTint});
}

@HostApi()
abstract class NativeShellHostApi {
  bool isAvailable();

  void setTabs(List<NativeTab> tabs);

  void setState(NativeShellState state);

  void setAppearance(NativeAppearance appearance);

  /// Drift wrote to these tables (debounced). Native screens reading the database refresh on it.
  void databaseDidChange(List<String> tables);

  /// The hosted route was popped on the Dart side (e.g. its own back button): pop it natively.
  void closeHostedRoute();
}

@FlutterApi()
abstract class NativeShellFlutterApi {
  void onTabSelected(int index);

  /// Pushes [route], ready to be shown by native navigation once this returns true.
  @async
  bool openRoute(NativeRoute route);

  /// Native navigation popped the hosted route: drop it (and anything opened from it).
  void hostedRouteClosed();

  /// A route is (or is no longer) hosted by native navigation, under a native bar of [barHeight]
  /// (0 while that bar is hidden).
  void onHostedRouteChanged(bool isHosted, double barHeight);
}
