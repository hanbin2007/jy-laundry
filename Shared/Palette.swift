import SwiftUI

/// Two ideas carry the whole app: *fresh* (ready, clean, go) and *water* (working, wait).
enum Palette {
    static let fresh = Color(red: 0.13, green: 0.80, blue: 0.64)
    static let freshInk = Color(red: 0.02, green: 0.43, blue: 0.36)
    static let water = Color(red: 0.27, green: 0.47, blue: 1.00)
    static let waterInk = Color(red: 0.16, green: 0.27, blue: 0.80)
    static let deep = Color(red: 0.13, green: 0.16, blue: 0.50)
    static let ember = Color(red: 1.00, green: 0.56, blue: 0.22)

    static func tint(_ state: DrumState) -> Color {
        switch state {
        case .idle: return fresh
        case .busy: return water
        case .offline: return .gray
        }
    }

    /// Readable text colour for a state on a light or dark surface.
    static func ink(_ state: DrumState, dark: Bool) -> Color {
        switch state {
        case .idle: return dark ? fresh : freshInk
        case .busy: return dark ? Color(red: 0.55, green: 0.68, blue: 1.0) : waterInk
        case .offline: return .secondary
        }
    }
}
