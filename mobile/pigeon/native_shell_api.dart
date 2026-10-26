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

  const NativeTab({required this.label, required this.symbol, required this.enabled});
}

/// Everything the native chrome needs to render, sent as one snapshot so updates are atomic.
class NativeShellState {
  final int selectedIndex;

  /// False when the TabShell is not the visible screen (pushed route, popup, landscape, logged out).
  final bool isShellVisible;

  /// Hides the tab bar while the shell itself stays visible (multi-select).
  final bool isTabBarSuppressed;

  const NativeShellState({required this.selectedIndex, required this.isShellVisible, required this.isTabBarSuppressed});
}

@HostApi()
abstract class NativeShellHostApi {
  bool isAvailable();

  void setTabs(List<NativeTab> tabs);

  void setState(NativeShellState state);
}

@FlutterApi()
abstract class NativeShellFlutterApi {
  void onTabSelected(int index);
}
