import SwiftUI

@main
struct LaundryApp: App {
    @State private var store = LaundryStore()

    init() {
        Notifier.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-gallery") {
                WidgetGallery()
            } else {
                RootView().environment(store)
            }
            #else
            RootView().environment(store)
            #endif
        }
    }
}
