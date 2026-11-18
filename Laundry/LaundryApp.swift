import SwiftUI

@main
struct LaundryApp: App {
    @State private var store = LaundryStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .preferredColorScheme(.light)
        }
    }
}
