import Flutter
import UIKit

/// Root controller (see Main.storyboard). Hosts native chrome above the single Flutter view.
/// On iOS < 26 it behaves exactly like FlutterViewController.
class ImmichShellViewController: FlutterViewController {
  var onTabSelected: ((Int) -> Void)?

  private let tabBarHost = TabBarHostController()
  private var tabBar: UITabBar { tabBarHost.tabBar }
  private var isTabBarHidden = true
  private var tabBarInset: CGFloat = 0

  static var isSupported: Bool {
    if #available(iOS 26, *) { return true }
    return false
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    guard Self.isSupported else { return }

    addChild(tabBarHost)
    let hostView = tabBarHost.view!
    hostView.translatesAutoresizingMaskIntoConstraints = false
    hostView.isHidden = true
    view.addSubview(hostView)
    NSLayoutConstraint.activate([
      hostView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      hostView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      hostView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])
    tabBarHost.didMove(toParent: self)
    tabBar.delegate = self
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    guard Self.isSupported else { return }
    updateSafeAreaInsets()
  }

  // MARK: - Tab bar API

  func setTabs(_ tabs: [(label: String, symbol: String, enabled: Bool)]) {
    guard Self.isSupported else { return }
    let selectedTag = tabBar.selectedItem?.tag ?? 0
    let items = tabs.enumerated().map { index, tab in
      let item = UITabBarItem(title: tab.label, image: UIImage(systemName: tab.symbol), tag: index)
      item.isEnabled = tab.enabled
      return item
    }
    tabBar.setItems(items, animated: false)
    tabBar.selectedItem = items.first { $0.tag == selectedTag } ?? items.first
  }

  func setSelectedIndex(_ index: Int) {
    guard let items = tabBar.items, items.indices.contains(index) else { return }
    tabBar.selectedItem = items[index]
  }

  func setTabBarHidden(_ hidden: Bool, animated: Bool) {
    guard Self.isSupported, hidden != isTabBarHidden else { return }
    isTabBarHidden = hidden
    let hostView = tabBarHost.view!

    let offset = hostView.bounds.height
    if !hidden {
      hostView.isHidden = false
      if animated { hostView.transform = CGAffineTransform(translationX: 0, y: offset) }
    }

    let changes = {
      hostView.transform = hidden ? CGAffineTransform(translationX: 0, y: offset) : .identity
      self.updateSafeAreaInsets()
    }
    let completion = { (_: Bool) in
      if self.isTabBarHidden {
        hostView.isHidden = true
        hostView.transform = .identity
      }
    }

    if animated {
      UIView.animate(withDuration: 0.25, delay: 0, options: [.beginFromCurrentState, .curveEaseInOut],
                     animations: changes, completion: completion)
    } else {
      changes()
      completion(true)
    }
  }

  /// Reserves the space covered by the tab bar so Flutter sees it as MediaQuery.padding.bottom.
  private func updateSafeAreaInsets() {
    let deviceBottom = view.window?.safeAreaInsets.bottom ?? 0
    let barHeight = tabBarHost.view.bounds.height
    let inset = isTabBarHidden ? 0 : max(0, barHeight - deviceBottom)
    guard inset != tabBarInset else { return }
    tabBarInset = inset
    additionalSafeAreaInsets.bottom = inset
    // The host must not inherit the inset it creates, or the bar would grow with it.
    tabBarHost.additionalSafeAreaInsets.bottom = -inset
  }
}

extension ImmichShellViewController: UITabBarDelegate {
  func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
    // Called on re-selection too; Dart handles scroll-to-top / search focus.
    onTabSelected?(item.tag)
  }
}

private final class TabBarHostController: UIViewController {
  let tabBar = UITabBar()

  override func loadView() {
    let view = PassthroughView()
    view.backgroundColor = .clear
    tabBar.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(tabBar)
    NSLayoutConstraint.activate([
      tabBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      tabBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      tabBar.topAnchor.constraint(equalTo: view.topAnchor),
      tabBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])
    self.view = view
  }
}

/// Lets touches outside the tab bar's visible glass reach Flutter.
private final class PassthroughView: UIView {
  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    let hit = super.hitTest(point, with: event)
    return hit === self ? nil : hit
  }
}
