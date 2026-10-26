import UIKit

/// A UITabBar living in the window, right above the Flutter view and below UIKit modals presented later.
/// Inside the Flutter view it would inherit the safe-area inset it reserves and lay its items out above itself.
/// Only used on iOS 26+ (Liquid Glass), see ImmichShellViewController.isSupported.
final class NativeTabBar: NSObject, UITabBarDelegate {
  var onSelect: ((Int) -> Void)?
  /// Called when the height the bar covers above the device safe area changes.
  var onCoveredHeightChange: (() -> Void)?

  private(set) var isVisible = false
  private let tabBar = UITabBar()
  private let container = PassthroughView()

  override init() {
    super.init()
    container.isHidden = true
    container.translatesAutoresizingMaskIntoConstraints = false
    tabBar.translatesAutoresizingMaskIntoConstraints = false
    tabBar.delegate = self
    container.addSubview(tabBar)
    NSLayoutConstraint.activate([
      tabBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      tabBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      tabBar.topAnchor.constraint(equalTo: container.topAnchor),
      tabBar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
    ])
  }

  /// Height covered above the device safe area, i.e. what content below must reserve.
  var coveredHeight: CGFloat {
    guard isVisible, let window = container.window else { return 0 }
    return max(0, container.bounds.height - window.safeAreaInsets.bottom)
  }

  func attach(above view: UIView) {
    guard container.superview == nil, let window = view.window else { return }
    window.insertSubview(container, aboveSubview: view)
    NSLayoutConstraint.activate([
      container.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      container.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      container.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])
  }

  func setTabs(_ tabs: [NativeTab]) {
    let selectedTag = tabBar.selectedItem?.tag ?? 0
    let items = tabs.enumerated().map { index, tab in
      let item = UITabBarItem(title: tab.label, image: UIImage(systemName: tab.symbol), tag: index)
      item.isEnabled = tab.enabled
      return item
    }
    tabBar.setItems(items, animated: false)
    tabBar.selectedItem = items.first { $0.tag == selectedTag } ?? items.first
  }

  func select(_ index: Int) {
    guard let items = tabBar.items, items.indices.contains(index) else { return }
    tabBar.selectedItem = items[index]
  }

  func setVisible(_ visible: Bool, animated: Bool) {
    guard visible != isVisible else { return }
    isVisible = visible
    container.layoutIfNeeded()
    let offset = CGAffineTransform(translationX: 0, y: container.bounds.height)

    if visible {
      container.isHidden = false
      if animated { container.transform = offset }
    }

    let changes = {
      self.container.transform = visible ? .identity : offset
      self.onCoveredHeightChange?()
    }
    let completion = { (_: Bool) in
      guard !self.isVisible else { return }
      self.container.isHidden = true
      self.container.transform = .identity
    }

    if animated {
      UIView.animate(withDuration: 0.25, delay: 0, options: [.beginFromCurrentState, .curveEaseInOut],
                     animations: changes, completion: completion)
    } else {
      changes()
      completion(true)
    }
  }

  // MARK: UITabBarDelegate

  func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
    // Also called on re-selection; Dart handles scroll-to-top / search focus.
    onSelect?(item.tag)
  }
}

/// Lets touches outside the tab bar's visible glass reach Flutter.
private final class PassthroughView: UIView {
  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    let hit = super.hitTest(point, with: event)
    return hit === self ? nil : hit
  }
}
