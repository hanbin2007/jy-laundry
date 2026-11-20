import SwiftUI
import WidgetKit

@main
struct LaundryWidgetsBundle: WidgetBundle {
    var body: some Widget {
        StatusWidget()
        LaundryLiveActivity()
    }
}
