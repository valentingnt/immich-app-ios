import Flutter
import UIKit

/// Root controller (see Main.storyboard). Hosts native chrome above the single Flutter view.
/// On iOS < 26 it behaves exactly like FlutterViewController.
class ImmichShellViewController: FlutterViewController {
  var onTabSelected: ((Int) -> Void)?

  private let tabBar = UITabBar()
  private let tabBarContainer = PassthroughView()
  private var isTabBarHidden = true
  private var tabBarInset: CGFloat = 0

  static var isSupported: Bool {
    if #available(iOS 26, *) { return true }
    return false
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    guard Self.isSupported else { return }

    tabBarContainer.isHidden = true
    tabBarContainer.translatesAutoresizingMaskIntoConstraints = false
    tabBar.translatesAutoresizingMaskIntoConstraints = false
    tabBar.delegate = self
    tabBarContainer.addSubview(tabBar)
    NSLayoutConstraint.activate([
      tabBar.leadingAnchor.constraint(equalTo: tabBarContainer.leadingAnchor),
      tabBar.trailingAnchor.constraint(equalTo: tabBarContainer.trailingAnchor),
      tabBar.topAnchor.constraint(equalTo: tabBarContainer.topAnchor),
      tabBar.bottomAnchor.constraint(equalTo: tabBarContainer.bottomAnchor),
    ])
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    guard Self.isSupported else { return }
    attachTabBarIfNeeded()
    updateSafeAreaInsets()
  }

  /// The bar lives in the window, right above the Flutter view (and below UIKit modals presented later):
  /// inside the Flutter view it would inherit the inset it reserves, and lay its items out above itself.
  private func attachTabBarIfNeeded() {
    guard tabBarContainer.superview == nil, let window = view.window else { return }
    window.insertSubview(tabBarContainer, aboveSubview: view)
    NSLayoutConstraint.activate([
      tabBarContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      tabBarContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      tabBarContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])
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
    let container = tabBarContainer

    let offset = container.bounds.height
    if !hidden {
      container.isHidden = false
      if animated { container.transform = CGAffineTransform(translationX: 0, y: offset) }
    }

    let changes = {
      container.transform = hidden ? CGAffineTransform(translationX: 0, y: offset) : .identity
      self.updateSafeAreaInsets()
    }
    let completion = { (_: Bool) in
      if self.isTabBarHidden {
        container.isHidden = true
        container.transform = .identity
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
    let barHeight = tabBarContainer.bounds.height
    let inset = isTabBarHidden ? 0 : max(0, barHeight - deviceBottom)
    guard inset != tabBarInset else { return }
    tabBarInset = inset
    additionalSafeAreaInsets.bottom = inset
  }
}

extension ImmichShellViewController: UITabBarDelegate {
  func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
    // Called on re-selection too; Dart handles scroll-to-top / search focus.
    onTabSelected?(item.tag)
  }
}

/// Lets touches outside the tab bar's visible glass reach Flutter.
private final class PassthroughView: UIView {
  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    let hit = super.hitTest(point, with: event)
    return hit === self ? nil : hit
  }
}
