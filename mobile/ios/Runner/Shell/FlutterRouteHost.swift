import Flutter
import SwiftUI

/// Shows Flutter routes inside native navigation: while a route is hosted, the app's single
/// engine renders into a FlutterViewController pushed by a native NavigationStack, instead of
/// the shell's view (which is then covered by the native screen doing the push).
///
/// A FlutterEngine renders into one view controller at a time; switching it leaves the Dart
/// isolate untouched, so the Riverpod / Drift / sync state is preserved.
///
/// The native navigation bar stays visible over the hosted route (SwiftUI turns the back-swipe
/// off when it is hidden): it provides the back button, and Flutter is told its height so the
/// hosted page can drop its own back button and keep its toolbar aligned (see NativeHostableRoute).
@available(iOS 26, *)
@MainActor
@Observable
final class FlutterRouteHost {
  static let shared = FlutterRouteHost()

  @ObservationIgnored private(set) var container: FlutterRouteContainer?

  /// Created once and reused: when a FlutterViewController is deallocated, Flutter detaches the
  /// engine's rendering even if another controller owns the engine by then.
  @ObservationIgnored private var hostedFlutter: FlutterViewController?

  /// Reports whether a route is hosted and the height of the native bar above it (0 when hidden).
  @ObservationIgnored var onHostedRouteChange: ((_ isHosted: Bool, _ barHeight: Double) -> Void)?

  @ObservationIgnored var flutterApi: NativeShellFlutterApi?

  /// Pops the hosted route from the native stack that shows it.
  @ObservationIgnored private var dismiss: (() -> Void)?

  /// The hosted route is the top Flutter route: native bar shown. Otherwise Flutter routes pushed
  /// from it (viewer, options…) are on screen and own the whole view, back gesture included.
  var isHostedRouteOnTop = true

  /// Hidden while the hosted page is in a mode with its own leading control (multi-select).
  var showsBackButton = true

  var isHosting: Bool { container != nil }

  /// Asks Dart to push `route`, hidden under the native screen, then moves the engine to a new
  /// view controller already showing it. On `true`, the caller pushes `container` right away;
  /// `dismiss` pops it when Dart closes the route from its side.
  func open(_ route: NativeRoute, dismiss: @escaping () -> Void) async -> Bool {
    guard container == nil, let flutterApi else { return false }
    let isPushed = await withCheckedContinuation { continuation in
      flutterApi.openRoute(route: route) { continuation.resume(returning: (try? $0.get()) ?? false) }
    }
    guard isPushed else { return false }
    guard begin() else {
      flutterApi.hostedRouteClosed { _ in }
      return false
    }
    self.dismiss = dismiss
    return true
  }

  /// Dart popped the hosted route itself.
  func closeRequested() {
    dismiss?()
  }

  private func begin() -> Bool {
    guard container == nil, let shell = ImmichShellViewController.current else { return false }
    let flutter = hostedFlutter ?? FlutterViewController(engine: shell.engine, nibName: nil, bundle: nil)
    hostedFlutter = flutter
    shell.engine.viewController = flutter
    container = FlutterRouteContainer(flutter: flutter) { [weak self] in self?.end() }
    return true
  }

  fileprivate func barHeightDidChange(_ height: Double) {
    onHostedRouteChange?(true, height)
  }

  /// Gives the engine back to the shell, once the hosting controller is off screen.
  private func end() {
    guard container != nil, let shell = ImmichShellViewController.current else { return }
    container = nil
    let dismiss = self.dismiss
    self.dismiss = nil
    shell.engine.viewController = shell
    // The hosted controller tore down the rendering surface and reported the app inactive when it
    // disappeared. The shell, on screen all along, never reappears to restore them: replay its
    // appearance so it recreates its surface and resumes the app.
    shell.beginAppearanceTransition(true, animated: false)
    shell.endAppearanceTransition()
    // Flutter still has the hosted view's size and insets (native bar included): resend the shell's.
    shell.view.setNeedsLayout()
    shell.view.layoutIfNeeded()
    onHostedRouteChange?(false, 0)
    // Native navigation popped: keep the caller's path in step (no-op if it already is), and let Dart
    // drop the route (no-op if Dart popped first).
    dismiss?()
    flutterApi?.hostedRouteClosed { _ in }
  }
}

/// Holds the hosted FlutterViewController and reports when native navigation popped it.
@available(iOS 26, *)
final class FlutterRouteContainer: UIViewController {
  private let flutter: FlutterViewController
  private let onPopped: () -> Void
  private var reportedBarHeight: Double?

  init(flutter: FlutterViewController, onPopped: @escaping () -> Void) {
    self.flutter = flutter
    self.onPopped = onPopped
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  override func viewDidLoad() {
    super.viewDidLoad()
    addChild(flutter)
    flutter.view.frame = view.bounds
    flutter.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    view.addSubview(flutter.view)
    flutter.didMove(toParent: self)
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    // The part of the top safe area added by the native navigation bar.
    let barHeight = max(0, Double(view.safeAreaInsets.top - (view.window?.safeAreaInsets.top ?? 0)))
    guard barHeight != reportedBarHeight else { return }
    reportedBarHeight = barHeight
    MainActor.assumeIsolated { FlutterRouteHost.shared.barHeightDidChange(barHeight) }
  }

  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    // Only once popped: a cancelled back-swipe keeps it on screen without disappearing.
    guard !isInNavigationStack else { return }
    // Free the reused Flutter controller for the next hosted route.
    flutter.willMove(toParent: nil)
    flutter.view.removeFromSuperview()
    flutter.removeFromParent()
    onPopped()
  }

  /// SwiftUI wraps the controller in its own hosting controller: look for any ancestor in the stack.
  private var isInNavigationStack: Bool {
    guard let stack = navigationController?.viewControllers else { return false }
    var ancestor: UIViewController? = self
    while let current = ancestor {
      if stack.contains(current) { return true }
      ancestor = current.parent
    }
    return false
  }
}

/// SwiftUI destination showing the hosted Flutter route full screen, under a transparent native bar.
@available(iOS 26, *)
struct FlutterRouteView: View {
  let container: FlutterRouteContainer
  private let host = FlutterRouteHost.shared

  var body: some View {
    ContainerView(container: container)
      .ignoresSafeArea()
      .toolbarBackground(.hidden, for: .navigationBar)
      // Hiding the bar or its back button also turns off the native back-swipe, which is wanted:
      // routes above the hosted one, and modes like multi-select, handle back themselves.
      .toolbar(host.isHostedRouteOnTop ? .visible : .hidden, for: .navigationBar)
      .navigationBarBackButtonHidden(!host.showsBackButton)
  }

  private struct ContainerView: UIViewControllerRepresentable {
    let container: FlutterRouteContainer

    func makeUIViewController(context: Context) -> FlutterRouteContainer { container }
    func updateUIViewController(_ controller: FlutterRouteContainer, context: Context) {}
  }
}
