import SwiftUI

// Small parts shared by the widgets, the Live Activity and the Dynamic Island.

// MARK: - Links into the app

/// Where a tap on a widget or the Live Activity lands: the overview, on a given machine.
enum DeepLink {
    static let overview = URL(string: "laundry://overview")!

    static func machine(_ id: Int) -> URL {
        URL(string: "laundry://machine/\(id)") ?? overview
    }

    /// The machine a link points at, if it points at one.
    static func machineID(in url: URL) -> Int? {
        guard url.scheme == "laundry", url.host() == "machine" else { return nil }
        return Int(url.lastPathComponent)
    }
}

extension DrumState {
    /// A shape for each state, so the state never rests on colour alone.
    var symbol: String {
        switch self {
        case .idle: return "checkmark.circle.fill"
        case .busy: return "timer"
        case .offline: return "xmark.circle.fill"
        }
    }
}

// MARK: - Time that keeps itself up to date

/// Countdown text the system ticks by itself. It never builds an invalid range, and it takes only the
/// width its digits need (a bare timer text asks for all the width there is).
struct Countdown: View {
    let from: Date
    let to: Date
    var alignment: Alignment = .trailing

    var body: some View {
        Text(to.timeIntervalSince(from) >= 3600 ? "0:00:00" : "00:00")
            .hidden()
            .overlay(alignment: alignment) {
                Text(timerInterval: from...max(to, from), countsDown: true)
                    .multilineTextAlignment(alignment == .leading ? .leading : .trailing)
            }
            .monospacedDigit()
    }
}

/// A wash's progress bar. With both ends known the system keeps it moving, so it stays right between
/// updates; otherwise it shows the last known fraction.
struct CycleProgress: View {
    var start: Date?
    var end: Date?
    var fraction: Double?

    var body: some View {
        if let start, let end, end > start {
            ProgressView(timerInterval: start...end, countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
        } else {
            ProgressView(value: min(1, max(0, fraction ?? 0)))
        }
    }
}

// MARK: - The ring

/// The app's mark, a ring, used as a gauge: whole and green with the number of free washers inside,
/// or filling in blue while the soonest wash runs.
struct StatusRing: View {
    enum Reading: Hashable {
        case free(Int)
        case washing(number: String, start: Date?, end: Date, fraction: Double?)
        /// Washing, with no finish time known.
        case running
        case unavailable
        case outdated
    }

    let reading: Reading
    var size: CGFloat = 22
    /// Large rings name the machine they are timing; small ones have no room for it.
    var namesMachine = false

    @Environment(\.colorScheme) private var scheme

    /// Matched to the system's circular progress ring, which draws the timed case.
    private var line: CGFloat { max(2.5, size * 0.115) }
    private var dark: Bool { scheme == .dark }

    /// The system ring brings its own track.
    private var drawsTrack: Bool {
        if case .washing(_, let start?, let end, _) = reading, end > start { return false }
        return true
    }

    var body: some View {
        ZStack {
            if drawsTrack {
                Circle().strokeBorder(Color.primary.opacity(0.16), lineWidth: line)
            }
            gauge
            inside
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)      // the words next to the ring always say the same thing
    }

    @ViewBuilder private var gauge: some View {
        switch reading {
        case .free:
            Circle().strokeBorder(Palette.fresh, lineWidth: line)
        case .washing(_, let start, let end, let fraction):
            if let start, end > start {
                ProgressView(timerInterval: start...end, countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .progressViewStyle(.circular)
                .tint(Palette.water)
            } else {
                arc(min(1, max(0.03, fraction ?? 0.03)))
            }
        case .running:
            arc(0.25)
        case .unavailable, .outdated:
            EmptyView()
        }
    }

    private func arc(_ fraction: Double) -> some View {
        Circle()
            .inset(by: line / 2)
            .trim(from: 0, to: fraction)
            .stroke(Palette.water, style: StrokeStyle(lineWidth: line, lineCap: .round))
            .rotationEffect(.degrees(-90))
    }

    @ViewBuilder private var inside: some View {
        switch reading {
        case .free(let count):
            Text("\(count)")
                .font(.system(size: size * 0.55, weight: .bold, design: .rounded))
                .foregroundStyle(Palette.ink(.idle, dark: dark))
                .minimumScaleFactor(0.6)
                .padding(line + 1)
        case .washing(let number, _, _, _):
            if namesMachine {
                Text(number)
                    .font(.system(size: size * 0.36, weight: .semibold, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .padding(line + 2)
            }
        case .running:
            EmptyView()
        case .unavailable:
            Image(systemName: "minus")
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(.secondary)
        case .outdated:
            Image(systemName: "exclamationmark")
                .font(.system(size: size * 0.46, weight: .bold))
                .foregroundStyle(.secondary)
        }
    }
}
