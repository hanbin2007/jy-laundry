import SwiftUI
import UIKit

private final class SwipeBackDelegate: NSObject, UIGestureRecognizerDelegate {
    static let shared = SwipeBackDelegate()
    weak var navigationController: UINavigationController?

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        (navigationController?.viewControllers.count ?? 0) > 1
    }
}

extension View {
    func enablesSwipeBack() -> some View {
        onAppear {
            DispatchQueue.main.async {
                guard let scene = UIApplication.shared.connectedScenes
                        .compactMap({ $0 as? UIWindowScene })
                        .first(where: { $0.activationState == .foregroundActive }),
                      let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController,
                      let nav = root.firstNavigationController else { return }
                SwipeBackDelegate.shared.navigationController = nav
                nav.interactivePopGestureRecognizer?.delegate = SwipeBackDelegate.shared
                nav.interactivePopGestureRecognizer?.isEnabled = true
            }
        }
    }
}

private extension UIViewController {
    var firstNavigationController: UINavigationController? {
        if let nav = self as? UINavigationController { return nav }
        for child in children {
            if let nav = child.firstNavigationController { return nav }
        }
        return navigationController
    }
}
