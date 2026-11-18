import SwiftUI

enum Palette {
    static let bg = Color(hex: 0xF4F6F5)
    static let ink = Color(hex: 0x14171A)
    static let secondary = Color(hex: 0x8A9098)
    static let tertiary = Color(hex: 0xAFB4BA)
    static let line = Color(hex: 0xE7EAEC)
    static let jade = Color(hex: 0x0F7A57)
    static let mint = Color(hex: 0x3EC492)
    static let busy = Color(hex: 0xC0453E)
    static let busyBar = Color(hex: 0xD2554D)
    static let dotOff = Color(hex: 0xD6DADF)
    static let alert = Color(hex: 0xC07A3E)
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

struct AuroraBackground: View {
    var body: some View {
        ZStack {
            Palette.bg
            Circle()
                .fill(Color(hex: 0xC6EDD9).opacity(0.95))
                .frame(width: 380, height: 380)
                .blur(radius: 95)
                .offset(x: -150, y: -310)
            Circle()
                .fill(Color(hex: 0xCFE0FF).opacity(0.9))
                .frame(width: 330, height: 330)
                .blur(radius: 105)
                .offset(x: 175, y: -225)
            Circle()
                .fill(Color(hex: 0xF6E5CE).opacity(0.75))
                .frame(width: 320, height: 320)
                .blur(radius: 115)
                .offset(x: 135, y: 440)
        }
        .ignoresSafeArea()
    }
}

private struct GlassSurface: ViewModifier {
    var corner: CGFloat

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(.white.opacity(0.5))
                    .background(
                        .ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: corner, style: .continuous)
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(.white.opacity(0.85), lineWidth: 1)
            }
            .shadow(color: Color(hex: 0x16241F).opacity(0.055), radius: 26, x: 0, y: 14)
    }
}

extension View {
    func glassSurface(corner: CGFloat = 26) -> some View {
        modifier(GlassSurface(corner: corner))
    }
}

struct HistoryBar: View {
    let runs: [[Int]]
    let minutes: Int
    var height: CGFloat = 6
    var showsData: Bool = true
    var segments: Int = 4
    var cornerRadius: CGFloat? = nil

    var body: some View {
        Canvas { context, size in
            let total = CGFloat(max(minutes, 1))

            if segments > 1 {
                for step in 1..<segments {
                    let x = size.width * CGFloat(step) / CGFloat(segments)
                    var tick = Path()
                    tick.move(to: CGPoint(x: x, y: 0))
                    tick.addLine(to: CGPoint(x: x, y: size.height))
                    context.stroke(tick, with: .color(Palette.dotOff.opacity(0.5)), lineWidth: 0.5)
                }
            }
            for run in runs where showsData && run.count == 3 && run[2] != -1 {
                let x = size.width * CGFloat(run[0]) / total
                let width = max(0.8, size.width * CGFloat(run[1]) / total)
                let rect = CGRect(x: x, y: 0, width: width, height: size.height)
                let color = run[2] == 10 ? Palette.mint : Palette.busyBar
                context.fill(Path(rect), with: .color(color))
            }
        }
        .frame(height: height)
        .background(Palette.line.opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius ?? height / 2, style: .continuous))
    }
}

struct ErrorPill: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        Button(action: retry) {
            HStack(spacing: 7) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                Text(message)
                    .font(.system(size: 13, weight: .medium))
                Text("重试")
                    .font(.system(size: 12, weight: .semibold))
                    .opacity(0.7)
            }
            .foregroundStyle(Palette.alert)
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(Palette.alert.opacity(0.09), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
