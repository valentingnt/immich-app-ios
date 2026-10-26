import UIKit

/// Native screens that replace the Flutter page of some tabs (see NativeTab.nativeScreen).
/// They are child controllers of the shell, layered above the Flutter view and below the tab bar,
/// so they inherit the bottom inset the tab bar reserves. Only one is visible at a time.
@MainActor
final class NativeTabScreens {
  private unowned let shell: UIViewController
  /// Screens keyed by tab index. Kept alive while hidden to preserve scroll position and search.
  private var screens: [Int: (id: String, controller: UIViewController)] = [:]
  private var visibleIndex: Int?
  private var appearance: (style: UIUserInterfaceStyle, tint: UIColor)?

  init(shell: UIViewController) {
    self.shell = shell
  }

  /// Creates, keeps or removes screens to match the tabs Dart declared.
  func update(tabs: [NativeTab]) {
    for (index, tab) in tabs.enumerated() {
      if screens[index]?.id == tab.nativeScreen { continue }
      remove(at: index)
      if let id = tab.nativeScreen, let controller = Self.makeScreen(id) {
        add(controller, id: id, at: index)
      }
    }
    for index in screens.keys where index >= tabs.count {
      remove(at: index)
    }
  }

  func apply(style: UIUserInterfaceStyle, tint: UIColor) {
    appearance = (style, tint)
    for (_, controller) in screens.values {
      Self.apply(style: style, tint: tint, to: controller)
    }
  }

  private static func apply(style: UIUserInterfaceStyle, tint: UIColor, to controller: UIViewController) {
    controller.overrideUserInterfaceStyle = style
    controller.view.tintColor = tint
  }

  /// Shows the screen of `selectedIndex` when the shell is visible, hides every other one.
  func show(selectedIndex: Int, isShellVisible: Bool, animated: Bool) {
    let target = isShellVisible && screens[selectedIndex] != nil ? selectedIndex : nil
    guard target != visibleIndex else { return }
    let previous = visibleIndex.flatMap { screens[$0]?.controller.view }
    let next = target.flatMap { screens[$0]?.controller.view }
    visibleIndex = target

    next?.alpha = animated ? 0 : 1
    next?.isHidden = false
    let changes = {
      previous?.alpha = 0
      next?.alpha = 1
    }
    let completion = { (_: Bool) in
      // A later call may have shown it again.
      if let previous, previous !== self.visibleIndex.flatMap({ self.screens[$0]?.controller.view }) {
        previous.isHidden = true
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

  private static func makeScreen(_ id: String) -> UIViewController? {
    guard #available(iOS 26, *) else { return nil }
    return switch id {
    case "albums": AlbumsScreen.make()
    default: nil
    }
  }

  private func add(_ controller: UIViewController, id: String, at index: Int) {
    shell.addChild(controller)
    let screenView = controller.view!
    screenView.isHidden = true
    screenView.translatesAutoresizingMaskIntoConstraints = false
    shell.view.addSubview(screenView)
    NSLayoutConstraint.activate([
      screenView.leadingAnchor.constraint(equalTo: shell.view.leadingAnchor),
      screenView.trailingAnchor.constraint(equalTo: shell.view.trailingAnchor),
      screenView.topAnchor.constraint(equalTo: shell.view.topAnchor),
      screenView.bottomAnchor.constraint(equalTo: shell.view.bottomAnchor),
    ])
    controller.didMove(toParent: shell)
    if let appearance { Self.apply(style: appearance.style, tint: appearance.tint, to: controller) }
    screens[index] = (id, controller)
  }

  private func remove(at index: Int) {
    guard let controller = screens.removeValue(forKey: index)?.controller else { return }
    if visibleIndex == index { visibleIndex = nil }
    controller.willMove(toParent: nil)
    controller.view.removeFromSuperview()
    controller.removeFromParent()
  }
}
