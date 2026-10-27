import Flutter
import UIKit

class NativeShellApiImpl: NativeShellHostApi {
  private let flutterApi: NativeShellFlutterApi

  init(messenger: FlutterBinaryMessenger) {
    flutterApi = NativeShellFlutterApi(binaryMessenger: messenger)
    guard #available(iOS 26, *) else { return }
    MainActor.assumeIsolated {
      FlutterRouteHost.shared.onHostedRouteChange = { [flutterApi] isHosted, barHeight in
        flutterApi.onHostedRouteChanged(isHosted: isHosted, barHeight: barHeight) { _ in }
      }
    }
  }

  // Plugins are registered before the window scene connects, so resolve the root controller lazily.
  private var shell: ImmichShellViewController? {
    guard let shell = ImmichShellViewController.current else { return nil }
    if shell.onTabSelected == nil {
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
    shell?.setTabs(tabs)
  }

  func setState(state: NativeShellState) throws {
    shell?.apply(state)
  }

  func setAppearance(appearance: NativeAppearance) throws {
    shell?.apply(appearance)
  }

  func databaseDidChange(tables: [String]) throws {
    ShellDatabase.notifyChange(tables: Set(tables))
  }
}
