import Flutter
import UIKit

class NativeShellApiImpl: NativeShellHostApi {
  private let flutterApi: NativeShellFlutterApi

  init(messenger: FlutterBinaryMessenger) {
    flutterApi = NativeShellFlutterApi(binaryMessenger: messenger)
  }

  // Plugins are registered before the window scene connects, so resolve the root controller lazily.
  private var shell: ImmichShellViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let shell = scenes.flatMap(\.windows).lazy.compactMap { $0.rootViewController as? ImmichShellViewController }.first
    if let shell, shell.onTabSelected == nil {
      shell.onTabSelected = { [flutterApi] index in
        flutterApi.onTabSelected(index: Int64(index)) { _ in }
      }
    }
    return shell
  }

  func isAvailable() throws -> Bool {
    ImmichShellViewController.isSupported
  }

  func setTabs(tabs: [NativeTab]) throws {
    shell?.setTabs(tabs.map { (label: $0.label, symbol: $0.symbol, enabled: $0.enabled) })
  }

  func setSelectedIndex(index: Int64) throws {
    shell?.setSelectedIndex(Int(index))
  }

  func setTabBarHidden(hidden: Bool, animated: Bool) throws {
    shell?.setTabBarHidden(hidden, animated: animated)
  }
}
