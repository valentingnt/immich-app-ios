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

@HostApi()
abstract class NativeShellHostApi {
  bool isAvailable();

  void setTabs(List<NativeTab> tabs);

  void setSelectedIndex(int index);

  void setTabBarHidden(bool hidden, bool animated);
}

@FlutterApi()
abstract class NativeShellFlutterApi {
  void onTabSelected(int index);
}
