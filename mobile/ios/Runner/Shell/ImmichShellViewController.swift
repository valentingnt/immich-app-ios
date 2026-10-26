import Flutter
import UIKit

/// Root controller (see Main.storyboard). Hosts native chrome around the single Flutter view.
/// On iOS < 26 it behaves exactly like FlutterViewController.
class ImmichShellViewController: FlutterViewController {
  /// The root shell of the app's only window scene.
  private(set) static weak var current: ImmichShellViewController?

  static var isSupported: Bool {
    if #available(iOS 26, *) { return true }
    return false
  }

  var onTabSelected: ((Int) -> Void)?

  private let tabBar = NativeTabBar()
  private lazy var screens = NativeTabScreens(shell: self)
  private var state: NativeShellState?

  override func viewDidLoad() {
    super.viewDidLoad()
    Self.current = self
    guard Self.isSupported else { return }
    tabBar.onSelect = { [weak self] index in self?.onTabSelected?(index) }
    tabBar.onCoveredHeightChange = { [weak self] in self?.updateSafeAreaInsets() }
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    guard Self.isSupported else { return }
    tabBar.attach(above: view)
    updateSafeAreaInsets()
  }

  func setTabs(_ tabs: [NativeTab]) {
    guard Self.isSupported else { return }
    tabBar.setTabs(tabs)
    screens.update(tabs: tabs)
  }

  func apply(_ newState: NativeShellState) {
    guard Self.isSupported else { return }
    // The first state lands while the shell appears: don't animate the grid's insets.
    let animated = state != nil
    state = newState
    tabBar.select(Int(newState.selectedIndex))
    tabBar.setVisible(newState.isShellVisible && !newState.isTabBarSuppressed, animated: animated)
    screens.show(selectedIndex: Int(newState.selectedIndex), isShellVisible: newState.isShellVisible, animated: animated)
  }

  /// Reserves the space covered by native chrome so Flutter sees it as MediaQuery.padding.
  private func updateSafeAreaInsets() {
    let bottom = tabBar.coveredHeight
    guard additionalSafeAreaInsets.bottom != bottom else { return }
    additionalSafeAreaInsets.bottom = bottom
  }
}
