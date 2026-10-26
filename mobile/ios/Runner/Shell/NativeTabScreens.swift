import UIKit

/// Native screens that replace the Flutter page of some tabs (see NativeTab.nativeScreen).
/// They are child controllers of the shell, layered above the Flutter view and below the tab bar,
/// so they inherit the bottom inset the tab bar reserves. Only one is visible at a time.
@MainActor
final class NativeTabScreens {
  private struct Screen {
    let id: String
    /// Created on first display, so the first layout happens at the final size and insets
    /// (a scroll view laid out while hidden starts scrolled, with its large title collapsed).
    /// Then kept alive while hidden to preserve scroll position and search.
    var controller: UIViewController?
  }

  private unowned let shell: UIViewController
  /// Keyed by tab index.
  private var screens: [Int: Screen] = [:]
  private var visibleIndex: Int?
  private var appearance: (style: UIUserInterfaceStyle, tint: UIColor)?

  init(shell: UIViewController) {
    self.shell = shell
  }

  /// Keeps, declares or removes screens to match the tabs Dart declared.
  func update(tabs: [NativeTab]) {
    for (index, tab) in tabs.enumerated() where screens[index]?.id != tab.nativeScreen {
      remove(at: index)
      if let id = tab.nativeScreen { screens[index] = Screen(id: id) }
    }
    for index in screens.keys where index >= tabs.count {
      remove(at: index)
    }
  }

  func apply(style: UIUserInterfaceStyle, tint: UIColor) {
    appearance = (style, tint)
    for controller in screens.values.compactMap(\.controller) {
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
    let previous = visibleIndex.flatMap { screens[$0]?.controller?.view }
    let next = target.flatMap(controller(at:))?.view
    visibleIndex = target

    next?.alpha = animated ? 0 : 1
    next?.isHidden = false
    let changes = {
      previous?.alpha = 0
      next?.alpha = 1
    }
    let completion = { (_: Bool) in
      // A later call may have shown it again.
      if let previous, previous !== self.visibleIndex.flatMap({ self.screens[$0]?.controller?.view }) {
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

  private func controller(at index: Int) -> UIViewController? {
    guard let screen = screens[index] else { return nil }
    if let controller = screen.controller { return controller }
    guard let controller = Self.makeScreen(screen.id) else { return nil }
    attach(controller)
    screens[index]?.controller = controller
    return controller
  }

  private static func makeScreen(_ id: String) -> UIViewController? {
    guard #available(iOS 26, *) else { return nil }
    return switch id {
    case "albums": AlbumsScreen.make()
    default: nil
    }
  }

  private func attach(_ controller: UIViewController) {
    shell.addChild(controller)
    let screenView = controller.view!
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
    shell.view.layoutIfNeeded()
  }

  private func remove(at index: Int) {
    guard let screen = screens.removeValue(forKey: index) else { return }
    if visibleIndex == index { visibleIndex = nil }
    guard let controller = screen.controller else { return }
    controller.willMove(toParent: nil)
    controller.view.removeFromSuperview()
    controller.removeFromParent()
  }
}
