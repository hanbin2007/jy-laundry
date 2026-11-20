import SwiftUI

/// A washing-machine door, drawn. The same art is used live in the app (animated, tilting with the
/// phone) and frozen in widgets and the Live Activity.
struct Porthole: View {
    var state: DrumState
    var progress: Double? = nil
    var spinning: Bool = false
    var time: Double = 0
    var tilt: Double = 0
    var showsRing: Bool = true

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Canvas { ctx, size in
            PortholeArt(
                state: state,
                progress: progress,
                spinning: spinning,
                time: time,
                tilt: tilt,
                dark: scheme == .dark,
                showsRing: showsRing
            )
            .draw(in: &ctx, size: size)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

struct PortholeArt {
    let state: DrumState
    let progress: Double?
    let spinning: Bool
    let time: Double
    let tilt: Double
    let dark: Bool
    let showsRing: Bool

    private func fract(_ x: Double) -> Double { x - x.rounded(.down) }

    private func circle(_ c: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    }

    func draw(in ctx: inout GraphicsContext, size: CGSize) {
        let side = min(size.width, size.height)
        let R = side * 0.46                        // leave room for the shadow
        let c = CGPoint(x: size.width / 2, y: size.height / 2)

        drawBezel(&ctx, c: c, R: R)
        drawRing(&ctx, c: c, R: R)

        // Rubber gasket between the bezel and the glass.
        let r = R * 0.74
        ctx.fill(circle(c, R * 0.80), with: .radialGradient(
            Gradient(colors: dark
                ? [Color(white: 0.02), Color(white: 0.10)]
                : [Color(white: 0.55), Color(white: 0.80)]),
            center: c, startRadius: r, endRadius: R * 0.80))

        var glass = ctx
        glass.clip(to: circle(c, r))
        drawInterior(&glass, c: c, r: r)
        drawDrum(&glass, c: c, r: r)
        if state == .busy { drawClothes(&glass, c: c, r: r) }
        drawWater(&glass, c: c, r: r, R: R)
        if state == .idle { drawGlints(&glass, c: c, r: r) }
        drawGlass(&glass, c: c, r: r)

        // Glass rim.
        ctx.stroke(circle(c, r), with: .linearGradient(
            Gradient(colors: [.white.opacity(dark ? 0.35 : 0.9), .white.opacity(0.05)]),
            startPoint: CGPoint(x: c.x, y: c.y - r), endPoint: CGPoint(x: c.x, y: c.y + r)),
            lineWidth: max(1, R * 0.014))
    }

    // MARK: Bezel and progress ring

    private func drawBezel(_ ctx: inout GraphicsContext, c: CGPoint, R: CGFloat) {
        var shadowed = ctx
        shadowed.addFilter(.shadow(color: .black.opacity(dark ? 0.55 : 0.16), radius: R * 0.08, x: 0, y: R * 0.05))
        shadowed.fill(circle(c, R), with: .linearGradient(
            Gradient(colors: dark
                ? [Color(white: 0.30), Color(white: 0.12)]
                : [Color(white: 1.0), Color(white: 0.86)]),
            startPoint: CGPoint(x: c.x - R * 0.4, y: c.y - R),
            endPoint: CGPoint(x: c.x + R * 0.4, y: c.y + R)))

        // Brushed-metal sheen on the upper edge.
        ctx.stroke(circle(c, R - 0.5), with: .linearGradient(
            Gradient(colors: [.white.opacity(dark ? 0.35 : 1), .white.opacity(0)]),
            startPoint: CGPoint(x: c.x, y: c.y - R), endPoint: CGPoint(x: c.x, y: c.y)),
            lineWidth: 1)
    }

    private func drawRing(_ ctx: inout GraphicsContext, c: CGPoint, R: CGFloat) {
        let rr = R * 0.90
        let w = R * 0.075
        let track = circle(c, rr)
        ctx.stroke(track, with: .color(dark ? .white.opacity(0.07) : .black.opacity(0.06)), lineWidth: w)
        guard showsRing else { return }

        switch state {
        case .busy:
            guard let p = progress else { return }
            let arc = Path { path in
                path.addArc(center: c, radius: rr,
                            startAngle: .degrees(-90),
                            endAngle: .degrees(-90 + 360 * max(0.015, p)),
                            clockwise: false)
            }
            ctx.drawLayer { glow in
                glow.addFilter(.blur(radius: w * 0.7))
                glow.stroke(arc, with: .color(Palette.water.opacity(0.7)),
                            style: StrokeStyle(lineWidth: w, lineCap: .round))
            }
            ctx.stroke(arc, with: .linearGradient(
                Gradient(colors: [Palette.water, Color(red: 0.45, green: 0.75, blue: 1.0)]),
                startPoint: CGPoint(x: c.x, y: c.y - rr), endPoint: CGPoint(x: c.x, y: c.y + rr)),
                style: StrokeStyle(lineWidth: w, lineCap: .round))
        case .idle:
            ctx.stroke(track, with: .color(Palette.fresh.opacity(dark ? 0.85 : 0.75)), lineWidth: w)
        case .offline:
            break
        }
    }

    // MARK: Inside the glass

    private func drawInterior(_ ctx: inout GraphicsContext, c: CGPoint, r: CGFloat) {
        let colors: [Color]
        switch (state, dark) {
        case (.idle, false): colors = [Color(red: 0.95, green: 0.99, blue: 0.98), Color(red: 0.80, green: 0.93, blue: 0.91)]
        case (.idle, true):  colors = [Color(red: 0.10, green: 0.19, blue: 0.21), Color(red: 0.04, green: 0.09, blue: 0.11)]
        case (.busy, false): colors = [Color(red: 0.22, green: 0.30, blue: 0.66), Color(red: 0.09, green: 0.11, blue: 0.36)]
        case (.busy, true):  colors = [Color(red: 0.13, green: 0.17, blue: 0.44), Color(red: 0.04, green: 0.05, blue: 0.18)]
        case (.offline, false): colors = [Color(white: 0.90), Color(white: 0.78)]
        case (.offline, true):  colors = [Color(white: 0.18), Color(white: 0.08)]
        }
        ctx.fill(circle(c, r), with: .linearGradient(
            Gradient(colors: colors),
            startPoint: CGPoint(x: c.x, y: c.y - r), endPoint: CGPoint(x: c.x, y: c.y + r)))
    }

    /// Perforated drum and three paddles; it turns while washing and races during the spin.
    private func drawDrum(_ ctx: inout GraphicsContext, c: CGPoint, r: CGFloat) {
        let speed = state == .busy ? (spinning ? 5.5 : 1.1) : 0
        let rot = time * speed
        let holeColor: Color = state == .busy
            ? .white.opacity(0.10)
            : (dark ? .white.opacity(0.05) : .black.opacity(0.05))

        for (ring, count) in [(0.30, 8), (0.56, 14), (0.82, 22)] {
            for i in 0..<count {
                let a = rot + Double(i) / Double(count) * .pi * 2 + ring * 1.7
                let p = CGPoint(x: c.x + CGFloat(cos(a)) * r * ring, y: c.y + CGFloat(sin(a)) * r * ring)
                ctx.fill(circle(p, r * 0.024), with: .color(holeColor))
            }
        }

        for i in 0..<3 {
            let a = rot + Double(i) * .pi * 2 / 3
            var paddle = ctx
            paddle.translateBy(x: c.x, y: c.y)
            paddle.rotate(by: .radians(a))
            let rect = CGRect(x: r * 0.80, y: -r * 0.07, width: r * 0.24, height: r * 0.14)
            paddle.fill(Path(roundedRect: rect, cornerRadius: r * 0.07), with: .color(holeColor.opacity(1.6)))
        }
    }

    /// A few soft garments tumbling. In the spin cycle they are pinned to the wall and whirl.
    private func drawClothes(_ ctx: inout GraphicsContext, c: CGPoint, r: CGFloat) {
        let garments: [Color] = [
            Color(red: 1.00, green: 0.56, blue: 0.52),
            Color(red: 1.00, green: 0.84, blue: 0.46),
            Color(red: 0.74, green: 0.62, blue: 1.00),
            Color(white: 0.96),
        ]
        for (i, color) in garments.enumerated() {
            let k = Double(i)
            let a: Double
            let dist: CGFloat
            let drop: CGFloat
            if spinning {
                a = time * 5.5 + k * .pi / 2
                dist = r * 0.70
                drop = 0
            } else {
                a = time * 1.15 + k * 1.57 + sin(time * 0.7 + k) * 0.5
                dist = r * CGFloat(0.40 + 0.12 * sin(time * 0.9 + k * 2))
                drop = r * 0.16
            }
            let p = CGPoint(x: c.x + CGFloat(cos(a)) * dist, y: c.y + CGFloat(sin(a)) * dist * 0.85 + drop)
            var g = ctx
            g.translateBy(x: p.x, y: p.y)
            g.rotate(by: .radians(a * 0.8 + k))
            let w = r * (spinning ? 0.46 : 0.40), h = r * 0.24
            let rect = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
            g.fill(Path(roundedRect: rect, cornerRadius: h * 0.48), with: .radialGradient(
                Gradient(colors: [color.opacity(0.95), color.opacity(0.55)]),
                center: .zero, startRadius: 0, endRadius: w * 0.6))
        }
    }

    private func drawWater(_ ctx: inout GraphicsContext, c: CGPoint, r: CGFloat, R: CGFloat) {
        let level: Double
        switch state {
        case .busy: level = spinning ? 0.12 : 0.50
        case .idle: level = 0.15
        case .offline: return
        }
        let baseY = r * CGFloat(1 - 2 * level)
        let amp = state == .busy ? r * (spinning ? 0.03 : 0.055) : r * 0.012
        let speed = state == .busy ? 2.4 : 0.7

        var w = ctx
        w.translateBy(x: c.x, y: c.y)
        w.rotate(by: .radians(tilt))

        func surfaceY(_ x: CGFloat, phase: Double, scale: Double) -> CGFloat {
            let xr = Double(x / r)
            let wave = sin(xr * 3.1 + time * speed + phase) * 0.7 + sin(xr * 5.3 - time * speed * 1.3 + phase) * 0.3
            return baseY + amp * CGFloat(wave * scale)
        }

        func body(phase: Double, scale: Double) -> (fill: Path, edge: Path) {
            var edge = Path()
            let x0 = -R * 1.3, span = R * 2.6, steps = 56
            for k in 0...steps {
                let x = x0 + span * CGFloat(k) / CGFloat(steps)
                let pt = CGPoint(x: x, y: surfaceY(x, phase: phase, scale: scale))
                k == 0 ? edge.move(to: pt) : edge.addLine(to: pt)
            }
            var fill = edge
            fill.addLine(to: CGPoint(x: x0 + span, y: R * 1.6))
            fill.addLine(to: CGPoint(x: x0, y: R * 1.6))
            fill.closeSubpath()
            return (fill, edge)
        }

        let tone: Color = state == .busy
            ? Color(red: 0.38, green: 0.66, blue: 1.0)
            : Palette.fresh

        let back = body(phase: 1.9, scale: 1.25)
        w.fill(back.fill, with: .color(tone.opacity(state == .busy ? 0.30 : 0.18)))

        let front = body(phase: 0, scale: 1)
        w.fill(front.fill, with: .linearGradient(
            Gradient(colors: [tone.opacity(state == .busy ? 0.55 : 0.32),
                              (state == .busy ? Palette.deep : Palette.freshInk).opacity(state == .busy ? 0.75 : 0.30)]),
            startPoint: CGPoint(x: 0, y: baseY), endPoint: CGPoint(x: 0, y: r)))
        w.stroke(front.edge, with: .color(.white.opacity(state == .busy ? 0.45 : 0.6)), lineWidth: max(0.8, r * 0.012))

        guard state == .busy else { return }
        // Bubbles rising to the surface.
        for i in 0..<10 {
            let seed = Double(i) * 0.618_034
            let rise = fract(time * (spinning ? 0.5 : 0.17) + seed)
            let x = CGFloat(fract(seed * 7.31) - 0.5) * r * 1.5 + CGFloat(sin(time * 2 + Double(i))) * r * 0.03
            let top = surfaceY(x, phase: 0, scale: 1)
            let y = r * 0.98 - CGFloat(rise) * (r * 0.98 - top)
            let size = r * CGFloat(0.016 + 0.022 * fract(seed * 3.7))
            w.stroke(circle(CGPoint(x: x, y: y), size), with: .color(.white.opacity(0.55 * (1 - rise * 0.6))), lineWidth: max(0.6, r * 0.008))
        }
    }

    /// Idle drums sparkle a little: clean and ready.
    private func drawGlints(_ ctx: inout GraphicsContext, c: CGPoint, r: CGFloat) {
        let spots: [(Double, Double, Double)] = [(-0.30, -0.28, 0.13), (0.34, -0.10, 0.09), (0.05, 0.22, 0.07)]
        for (i, s) in spots.enumerated() {
            let pulse = max(0, sin(time * 1.4 + Double(i) * 2.1))
            guard pulse > 0.02 || time == 0 else { continue }
            let k = time == 0 ? 0.8 : pulse
            let center = CGPoint(x: c.x + r * CGFloat(s.0), y: c.y + r * CGFloat(s.1))
            let size = r * CGFloat(s.2 * k)
            ctx.fill(sparkle(center, size), with: .color((dark ? Color.white : Palette.fresh).opacity(0.85 * k)))
        }
    }

    private func sparkle(_ c: CGPoint, _ s: CGFloat) -> Path {
        Path { p in
            p.move(to: CGPoint(x: c.x, y: c.y - s))
            p.addQuadCurve(to: CGPoint(x: c.x + s, y: c.y), control: c)
            p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + s), control: c)
            p.addQuadCurve(to: CGPoint(x: c.x - s, y: c.y), control: c)
            p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - s), control: c)
        }
    }

    /// Curved-glass optics: edge vignette, a crescent reflection and a small specular highlight.
    private func drawGlass(_ ctx: inout GraphicsContext, c: CGPoint, r: CGFloat) {
        ctx.fill(circle(c, r), with: .radialGradient(
            Gradient(colors: [.clear, .black.opacity(dark ? 0.40 : 0.22)]),
            center: c, startRadius: r * 0.55, endRadius: r))

        var crescent = circle(c, r)
        crescent.addPath(circle(CGPoint(x: c.x + r * 0.10, y: c.y + r * 0.13), r * 0.98))
        ctx.fill(crescent, with: .linearGradient(
            Gradient(colors: [.white.opacity(dark ? 0.30 : 0.55), .white.opacity(0)]),
            startPoint: CGPoint(x: c.x - r, y: c.y - r), endPoint: c),
            style: FillStyle(eoFill: true))

        var spec = ctx
        spec.translateBy(x: c.x - r * 0.40, y: c.y - r * 0.48)
        spec.rotate(by: .degrees(-38))
        spec.fill(Path(ellipseIn: CGRect(x: -r * 0.20, y: -r * 0.07, width: r * 0.40, height: r * 0.14)),
                  with: .color(.white.opacity(dark ? 0.22 : 0.45)))
    }
}
