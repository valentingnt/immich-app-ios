import Flutter
import UIKit

class NativeShellApiImpl: NativeShellHostApi {
  private let flutterApi: NativeShellFlutterApi

  init(messenger: FlutterBinaryMessenger) {
    flutterApi = NativeShellFlutterApi(binaryMessenger: messenger)
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
}
