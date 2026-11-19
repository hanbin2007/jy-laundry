import SceneKit
import SwiftUI
import UIKit
import simd

/// What the 3D scene shows for one machine.
struct WasherLook: Equatable {
    /// The machine's id, so the carousel can tell when the list of machines itself changes.
    var id: Int
    /// "57"
    var label: String
    var state: DrumState
    var spinning: Bool
    /// "00:11" while running with a known end, otherwise empty.
    var clock: String
}

/// The machines as a swipeable 3D carousel on a clear background, so the page's gradient shows through.
/// The machine in view stands in front with its door turned toward the text on the left; the next ones
/// wait in a line behind it, up and to the right. Swipe to switch: the machine in view swings out to the
/// left and walks round to the back of the line while the next one comes forward.
struct WasherCarousel: UIViewRepresentable {
    var machines: [WasherLook]
    @Binding var selection: Int
    /// Where the floor under the machine in view appears, in this view's points.
    var anchor: CGPoint
    /// 1 is the size in the design, where a machine is about 230 pt tall.
    var scale: CGFloat
    var dark: Bool
    /// Turn the drum and slosh the water (off for Reduce Motion).
    var animates: Bool
    /// Run the frame loop (off when the screen is hidden or the app is in the background).
    var active: Bool

    func makeCoordinator() -> WasherStage { WasherStage() }

    func makeUIView(context: Context) -> SCNView {
        context.coordinator.makeView()
    }

    func updateUIView(_ view: SCNView, context: Context) {
        let stage = context.coordinator
        let binding = $selection
        stage.onIndex = { binding.wrappedValue = $0 }
        stage.update(machines: machines, selection: selection, dark: dark, animates: animates, anchor: anchor, scale: scale)
        stage.setActive(active)
        stage.go(selection)
    }

    static func dismantleUIView(_ view: SCNView, coordinator: WasherStage) {
        coordinator.setActive(false)
    }
}

/// Lays out its scene again whenever its size changes.
final class StageView: SCNView {
    var onLayout: ((CGSize) -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?(bounds.size)
    }
}

// MARK: - Stage

@MainActor
final class WasherStage: NSObject, UIGestureRecognizerDelegate {
    /// Called when a swipe settles on another machine.
    var onIndex: ((Int) -> Void)?

    private let scene = SCNScene()
    private let cameraNode = SCNNode()
    private let sun = SCNLight()
    private let rim = SCNLight()
    private let fill = SCNLight()
    private let materials = WasherMaterials()
    private weak var view: StageView?
    private var washers: [Washer] = []
    /// The machine ids last shown, in order.
    private var ids: [Int]?

    // `index` counts switches without wrapping; the machine in view is `index` mod `count`.
    private var count = 1
    private var index = 0
    private var pos = 0.0
    private var posVel = 0.0
    private var dragging = false
    private var dragBase = 0.0

    private var dark: Bool?
    private var animates = true
    private var anchor = CGPoint.zero
    private var scale: CGFloat = 1
    private var projected: (size: CGSize, anchor: CGPoint, scale: CGFloat)?

    private var link: CADisplayLink?
    private var lastTime: CFTimeInterval = 0
    private var time = 0.0
    /// Set when something outside the frame loop changed, so the next frame lays the scene out again.
    private var needsArrange = true

    // The view in the design: the machine turned so its door faces left, the camera above and in front.
    private let turn = -0.52
    /// Where the next machine in line stands, relative to the one in front of it (metres).
    private let lineX = 0.12, lineZ = -1.0
    /// How far the leaving machine swings out to the left and toward the camera on its way round.
    private let swingX = 1.2, swingZ = 0.3
    /// Points of finger travel for one machine.
    private let slotWidth: CGFloat = 180
    /// Points per metre at one metre from the camera, at scale 1 (a 420 pt view with a 26° field of view).
    private let focal = 909.6
    /// A critically damped spring: it settles smoothly without bouncing.
    private let stiffness = 60.0

    var current: Int { Self.mod(index, count) }

    override init() {
        super.init()
        scene.background.contents = UIColor.clear
        scene.lightingEnvironment.contents = Textures.environment()

        let camera = SCNCamera()
        camera.zNear = 0.05
        camera.zFar = 40
        camera.projectionDirection = .vertical
        camera.fieldOfView = 26
        cameraNode.camera = camera
        cameraNode.simdPosition = [0, 2.3, 3.9]
        cameraNode.simdLook(at: [0, 0.42, 0])
        scene.rootNode.addChildNode(cameraNode)

        // No room: only the shadows the machines cast, so the page's gradient shows through.
        let ground = SCNPlane(width: 12, height: 12)
        let groundMaterial = SCNMaterial()
        groundMaterial.lightingModel = .shadowOnly
        ground.materials = [groundMaterial]
        let groundNode = SCNNode(geometry: ground)
        groundNode.eulerAngles.x = -.pi / 2
        groundNode.castsShadow = false
        scene.rootNode.addChildNode(groundNode)

        // Light from above and a little in front, so the shadow falls close behind the machine
        // and never sweeps across the text on the left.
        sun.type = .directional
        sun.castsShadow = true
        sun.shadowMode = .deferred
        sun.shadowMapSize = CGSize(width: 2048, height: 2048)
        sun.shadowSampleCount = 16
        sun.shadowRadius = 8
        sun.shadowBias = 0.02
        let sunNode = SCNNode()
        sunNode.light = sun
        sunNode.simdPosition = [-0.9, 4.2, 1.7]
        sunNode.simdLook(at: .zero)
        scene.rootNode.addChildNode(sunNode)

        rim.type = .directional
        rim.color = UIColor(red: 0.81, green: 0.88, blue: 1, alpha: 1)
        let rimNode = SCNNode()
        rimNode.light = rim
        rimNode.simdPosition = [3, 1.5, -1.5]
        rimNode.simdLook(at: .zero)
        scene.rootNode.addChildNode(rimNode)

        fill.type = .ambient
        fill.color = UIColor(red: 0.92, green: 0.93, blue: 0.96, alpha: 1)
        let fillNode = SCNNode()
        fillNode.light = fill
        scene.rootNode.addChildNode(fillNode)
    }

    func makeView() -> SCNView {
        let v = StageView(frame: .zero, options: nil)
        v.scene = scene
        v.pointOfView = cameraNode
        v.backgroundColor = .clear
        v.isOpaque = false
        v.antialiasingMode = .multisampling4X
        v.preferredFramesPerSecond = 60
        v.rendersContinuously = false
        v.onLayout = { [weak self] _ in self?.updateProjection() }
        let pan = UIPanGestureRecognizer(target: self, action: #selector(pan(_:)))
        pan.delegate = self
        v.addGestureRecognizer(pan)
        view = v
        return v
    }

    func update(machines: [WasherLook], selection: Int, dark: Bool, animates: Bool, anchor: CGPoint, scale: CGFloat) {
        let n = max(1, machines.count)
        while washers.count < n {
            let w = Washer(materials: materials)
            scene.rootNode.addChildNode(w.holder)
            washers.append(w)
        }
        count = n
        for (i, w) in washers.enumerated() {
            if i < machines.count { w.look = machines[i] } else { w.holder.isHidden = true }
        }
        // On first show, or when machines are added, removed or reordered, place the selected machine
        // in front at once instead of animating from wherever the old list left off.
        let newIDs = machines.map(\.id)
        if newIDs != ids {
            ids = newIDs
            index = Self.mod(selection, n)
            pos = Double(index)
            posVel = 0
            dragBase = pos
        }
        if self.dark != dark {
            self.dark = dark
            applyTheme(dark)
        }
        self.animates = animates
        self.anchor = anchor
        self.scale = scale
        updateProjection()
        wake()
        // When the frame loop is not running, still show a correct, still picture.
        if link == nil {
            arrange()
            for w in washers where !w.holder.isHidden { w.tick(time: time, dt: 0) }
        }
    }

    /// Show machine `k`, taking the shorter way round. Does nothing if it is already in view.
    func go(_ k: Int) {
        guard count > 1 else { return }
        var d = Self.mod(k - current, count)
        if Double(d) > Double(count) / 2 { d -= count }
        guard d != 0 else { return }
        index += d
        wake()
    }

    /// Run the frame loop again after it paused on a still scene.
    private func wake() {
        needsArrange = true
        link?.isPaused = false
    }

    func setActive(_ on: Bool) {
        if on, link == nil {
            let l = CADisplayLink(target: self, selector: #selector(step(_:)))
            l.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
            l.add(to: .main, forMode: .common)
            link = l
            lastTime = 0
            needsArrange = true
        } else if !on, let l = link {
            l.invalidate()
            link = nil
            view?.rendersContinuously = false
            // Finish where it was heading, so the picture is right when it comes back.
            dragging = false
            pos = Double(index)
            posVel = 0
            arrange()
        }
    }

    // MARK: Frame loop

    @objc private func step(_ link: CADisplayLink) {
        let now = link.timestamp
        let dt = lastTime == 0 ? 1.0 / 60 : min(0.05, max(0, now - lastTime))
        lastTime = now
        if !dragging { settle(dt) }
        let turning = animates && washers.prefix(count).contains { !$0.holder.isHidden && $0.look.state == .busy }
        let moving = dragging || posVel != 0 || pos != Double(index) || turning
        // Work and redraw every frame only while something moves; a still scene is left alone.
        if moving || needsArrange {
            needsArrange = false
            arrange()
            let motion = animates ? dt : 0
            time += motion
            for w in washers where !w.holder.isHidden { w.tick(time: time, dt: motion) }
        }
        if view?.rendersContinuously != moving { view?.rendersContinuously = moving }
        // Nothing moves and nothing changed: stop until a swipe, a switch or new data wakes the loop.
        if !moving { link.isPaused = true }
    }

    private func settle(_ dt: Double) {
        let target = Double(index)
        let damping = 2 * stiffness.squareRoot()
        for _ in 0..<4 {
            let h = dt / 4
            posVel += (stiffness * (target - pos) - damping * posVel) * h
            pos += posVel * h
        }
        if abs(target - pos) < 0.0005, abs(posVel) < 0.001 {
            pos = target
            posVel = 0
        }
    }

    /// Put each machine in its slot: 0 is in view, 1 is next in line behind it, and so on.
    /// Between -1 and 0 a machine is leaving: it swings out to the left and walks round to the back.
    private func arrange() {
        let n = Double(count)
        for i in 0..<min(count, washers.count) {
            let w = washers[i]
            var p = count > 1 ? Self.mod(Double(i) - pos, n) : Double(i) - pos
            if count > 1, p > n - 1 { p -= n }
            // Only the machine in view and the next two in line are drawn.
            w.holder.isHidden = p >= 2.05
            guard p < 2.05 else { continue }

            var x: Double, z: Double, r = turn, opacity = 1.0
            if p >= 0 {
                x = p * lineX
                z = p * lineZ
            } else {
                let t = -p, back = n - 1, e = t * t * (3 - 2 * t), s = sin(.pi * t)
                x = e * back * lineX - s * swingX
                z = e * back * lineZ + s * swingZ
                r += s * 0.45
                // It fades out quickly as it swings away, passing softly behind the chart,
                // and fades back in as it reaches the back of the line.
                func smooth(_ a: Double, _ b: Double, _ x: Double) -> Double {
                    let u = min(1, max(0, (x - a) / (b - a)))
                    return u * u * (3 - 2 * u)
                }
                opacity = t <= 0.5 ? 1 - smooth(0, 0.4, t) : smooth(0.6, 1, t)
            }
            w.holder.simdPosition = [Float(x), 0, Float(z)]
            w.holder.eulerAngles.y = Float(r)
            w.holder.opacity = CGFloat(opacity)
            // A machine on its way out drops its shadow, so nothing dark sweeps across the chart.
            w.setShadows(p > -0.12)
        }
    }

    // MARK: Swipe

    @objc private func pan(_ g: UIPanGestureRecognizer) {
        guard let view else { return }
        let dx = g.translation(in: view).x
        let slot = slotWidth * scale
        switch g.state {
        case .began:
            dragging = true
            dragBase = pos
            posVel = 0
            wake()
        case .changed:
            pos = dragBase - Double(dx / slot)
            // With one machine there is nowhere to go: follow the finger only a little.
            if count < 2 { pos = dragBase + (pos - dragBase) * 0.25 }
        case .ended, .cancelled, .failed:
            dragging = false
            let vel = g.velocity(in: view).x
            var next = index
            if count > 1, g.state == .ended {
                if dx < -30 || vel < -400 { next = index + 1 }
                else if dx > 30 || vel > 400 { next = index - 1 }
            }
            // Hand the finger's speed to the spring, so the motion carries on without a jolt.
            posVel = max(-6, min(6, -Double(vel / slot)))
            if next != index {
                index = next
                onIndex?(current)
            }
        default:
            break
        }
    }

    func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        guard let pan = g as? UIPanGestureRecognizer, let view else { return true }
        let v = pan.velocity(in: view)
        return abs(v.x) > abs(v.y)
    }

    // MARK: Look

    private func applyTheme(_ dark: Bool) {
        scene.lightingEnvironment.intensity = dark ? 0.35 : 0.8
        sun.intensity = dark ? 480 : 820
        rim.intensity = dark ? 420 : 240
        fill.intensity = dark ? 50 : 90
        sun.shadowColor = UIColor(white: 0, alpha: dark ? 0.42 : 0.16)
    }

    /// Keep the machine the same size whatever the view's height, and shift the picture (not the angle)
    /// so the floor under the machine in view lands on the anchor.
    private func updateProjection() {
        guard let view, let camera = cameraNode.camera else { return }
        let size = view.bounds.size
        guard size.width > 1, size.height > 1 else { return }
        if let p = projected, p.size == size, p.anchor == anchor, p.scale == scale { return }
        projected = (size, anchor, scale)

        let f = 2 * focal * Double(scale) / Double(size.height)   // 1 / tan(fov / 2)
        let probe = SCNCamera()
        probe.zNear = camera.zNear
        probe.zFar = camera.zFar
        probe.projectionDirection = .vertical
        probe.fieldOfView = CGFloat(2 * atan(1 / f) * 180 / .pi)
        var m = simd_float4x4(probe.projectionTransform(withViewportSize: size))

        let eye = cameraNode.simdWorldTransform.inverse * SIMD4<Float>(0, 0, 0, 1)
        let clip = m * eye
        let x0 = clip.x / clip.w, y0 = clip.y / clip.w
        let tx = Float(anchor.x / size.width) * 2 - 1
        let ty = 1 - Float(anchor.y / size.height) * 2
        let sx = tx - x0, sy = ty - y0
        // Add the shift to clip x and y in proportion to w, which moves the picture in normalised space.
        for c in 0..<4 {
            m[c][0] += sx * m[c][3]
            m[c][1] += sy * m[c][3]
        }
        camera.projectionTransform = SCNMatrix4(m)
    }

    private static func mod(_ a: Int, _ n: Int) -> Int { ((a % n) + n) % n }
    private static func mod(_ a: Double, _ n: Double) -> Double {
        let r = a.truncatingRemainder(dividingBy: n)
        return r < 0 ? r + n : r
    }
}

// MARK: - Washer

@MainActor
final class WasherMaterials {
    let enamel = WasherMaterials.pbr(0xF7F7F5, rough: 0.3)
    let panel = WasherMaterials.pbr(0xE9EBEE, rough: 0.45)
    let chrome = WasherMaterials.pbr(0xDFE3E8, metal: 1, rough: 0.16)
    let rubber = WasherMaterials.pbr(0x2A2D32, rough: 0.85)
    let drum: SCNMaterial
    let drumBack: SCNMaterial
    let water = WasherMaterials.pbr(0x4F86FF, rough: 0.08)
    let contact = SCNMaterial()
    let cloth: [SCNMaterial] = [0xFF8F86, 0xFFD773, 0xB9A5FF, 0xF4F4F6].map { WasherMaterials.pbr($0, rough: 0.95) }

    init() {
        enamel.clearCoat.contents = 0.8
        enamel.clearCoatRoughness.contents = 0.18

        let holes = Textures.perforation()
        drum = Self.pbr(0xFFFFFF, metal: 0.85, rough: 0.38)
        drumBack = Self.pbr(0xFFFFFF, metal: 0.8, rough: 0.45)
        for (m, repeatX, repeatY) in [(drum, 6, 3), (drumBack, 3, 3)] {
            m.diffuse.contents = holes
            m.diffuse.wrapS = .repeat
            m.diffuse.wrapT = .repeat
            m.diffuse.contentsTransform = SCNMatrix4MakeScale(Float(repeatX), Float(repeatY), 1)
        }

        water.transparency = 0.45
        water.blendMode = .alpha
        water.isDoubleSided = true
        water.writesToDepthBuffer = false

        contact.lightingModel = .constant
        contact.diffuse.contents = Textures.contactShadow()
        contact.blendMode = .alpha
        contact.writesToDepthBuffer = false
    }

    static func pbr(_ hex: Int, metal: CGFloat = 0, rough: CGFloat) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = UIColor(hex: hex)
        m.metalness.contents = metal
        m.roughness.contents = rough
        return m
    }
}

/// One washing machine: an enamel body with a round door, a control panel with a small display,
/// and a drum that turns while it runs.
@MainActor
final class Washer {
    let holder = SCNNode()
    var look = WasherLook(id: 0, label: "", state: .idle, spinning: false, clock: "")

    private let materials: WasherMaterials
    private let drum = SCNNode()
    private let clothesGroup = SCNNode()
    private var clothes: [SCNNode] = []
    private let water = SCNNode()
    private let displayMaterial = SCNMaterial()
    private let ledMaterial = SCNMaterial()
    private var contact: SCNNode!
    private var drawn: WasherLook?
    private var shadows = true
    /// Each machine tumbles on its own beat, so two running machines never move in step.
    private let phase = Double.random(in: 0..<20)
    private lazy var spin = phase

    private static let W: CGFloat = 0.6, H: CGFloat = 0.85, D: CGFloat = 0.6, foot: CGFloat = 0.025

    init(materials: WasherMaterials) {
        self.materials = materials
        let W = Self.W, H = Self.H, D = Self.D, foot = Self.foot
        let front = Float(D / 2 + 0.001)

        // The body has a round tunnel where the drum sits, so the drum shows through the door.
        let doorCenter = 0.39 - H / 2
        let body = SCNNode(geometry: Self.slab(width: W, height: H, depth: D, radius: 0.06, bevel: 0.03,
                                               hole: (CGPoint(x: 0, y: doorCenter), 0.186), material: materials.enamel))
        body.position.y = Float(foot + H / 2)
        holder.addChildNode(body)

        // Control panel: a strip with a display, a knob and a status light.
        let panelY = Float(foot + H - 0.085)
        let panel = SCNNode(geometry: Self.slab(width: W - 0.06, height: 0.1, depth: 0.02, radius: 0.025, bevel: 0.008,
                                                material: materials.panel))
        panel.position = SCNVector3(0, panelY, front)
        holder.addChildNode(panel)

        displayMaterial.lightingModel = .constant
        let screen = SCNPlane(width: 0.22, height: 0.055)
        screen.materials = [displayMaterial]
        let display = SCNNode(geometry: screen)
        display.position = SCNVector3(0.03, panelY, front + 0.0115)
        display.castsShadow = false
        holder.addChildNode(display)

        let knob = SCNNode(geometry: Self.cylinder(radius: 0.033, height: 0.024, material: materials.chrome))
        knob.eulerAngles.x = .pi / 2
        knob.position = SCNVector3(-0.19, panelY, front + 0.016)
        holder.addChildNode(knob)

        ledMaterial.lightingModel = .constant
        let ledShape = SCNSphere(radius: 0.0065)
        ledShape.materials = [ledMaterial]
        let led = SCNNode(geometry: ledShape)
        led.position = SCNVector3(0.2, panelY, front + 0.012)
        holder.addChildNode(led)

        // Door.
        let door = SCNNode()
        door.position = SCNVector3(0, Float(foot + 0.39), front)
        holder.addChildNode(door)

        let plateShape = SCNTube(innerRadius: 0.184, outerRadius: 0.245, height: 0.004)
        plateShape.radialSegmentCount = 96
        plateShape.materials = [materials.panel]
        let plate = SCNNode(geometry: plateShape)
        plate.eulerAngles.x = .pi / 2
        plate.position.z = 0.004
        door.addChildNode(plate)

        let ringShape = SCNTorus(ringRadius: 0.212, pipeRadius: 0.03)
        ringShape.ringSegmentCount = 128
        ringShape.pipeSegmentCount = 40
        ringShape.materials = [materials.chrome]
        let ring = SCNNode(geometry: ringShape)
        ring.eulerAngles.x = .pi / 2
        ring.position.z = 0.02
        door.addChildNode(ring)

        let gasketShape = SCNTorus(ringRadius: 0.18, pipeRadius: 0.018)
        gasketShape.ringSegmentCount = 96
        gasketShape.materials = [materials.rubber]
        let gasket = SCNNode(geometry: gasketShape)
        gasket.eulerAngles.x = .pi / 2
        gasket.position.z = 0.008
        door.addChildNode(gasket)

        // The drum behind the glass, with three paddles.
        drum.position.z = -0.17
        door.addChildNode(drum)
        let wallShape = SCNTube(innerRadius: 0.178, outerRadius: 0.182, height: 0.32)
        wallShape.radialSegmentCount = 64
        wallShape.materials = [materials.drum]
        let wall = SCNNode(geometry: wallShape)
        wall.eulerAngles.x = .pi / 2
        drum.addChildNode(wall)
        let back = SCNNode(geometry: Self.cylinder(radius: 0.182, height: 0.004, material: materials.drumBack))
        back.eulerAngles.x = .pi / 2
        back.position.z = -0.16
        drum.addChildNode(back)
        for k in 0..<3 {
            let a = Float(k) * 2 * .pi / 3
            let paddleShape = SCNBox(width: 0.03, height: 0.045, length: 0.28, chamferRadius: 0.005)
            paddleShape.materials = [materials.chrome]
            let paddle = SCNNode(geometry: paddleShape)
            paddle.position = SCNVector3(cos(a) * 0.16, sin(a) * 0.16, 0)
            paddle.eulerAngles.z = a
            drum.addChildNode(paddle)
        }

        // Clothes tumble inside; they are not attached to the drum, so they can fall.
        clothesGroup.position.z = -0.1
        door.addChildNode(clothesGroup)
        for m in materials.cloth {
            let shape = SCNSphere(radius: 0.055)
            shape.segmentCount = 24
            shape.materials = [m]
            let item = SCNNode(geometry: shape)
            item.scale = SCNVector3(1.35, 0.62, 0.95)
            clothesGroup.addChildNode(item)
            clothes.append(item)
        }

        // Water, rebuilt every frame as a wavy slice of a circle.
        water.position.z = -0.012
        water.castsShadow = false
        door.addChildNode(water)

        let handle = SCNNode(geometry: Self.slab(width: 0.032, height: 0.13, depth: 0.03, radius: 0.014, bevel: 0.008,
                                                 material: materials.chrome))
        handle.position = SCNVector3(Float(W / 2 - 0.045), Float(foot + 0.39), front + 0.02)
        holder.addChildNode(handle)

        for fx in [-1.0, 1.0] {
            for fz in [-1.0, 1.0] {
                let f = SCNNode(geometry: Self.cylinder(radius: 0.024, height: foot, material: materials.rubber))
                f.position = SCNVector3(Float(fx * (W / 2 - 0.06)), Float(foot / 2), Float(fz * (D / 2 - 0.06)))
                holder.addChildNode(f)
            }
        }

        // A soft dark patch right under the machine, so it sits on the floor.
        let patch = SCNPlane(width: W * 1.5, height: D * 1.5)
        patch.materials = [materials.contact]
        let contactNode = SCNNode(geometry: patch)
        contactNode.eulerAngles.x = -.pi / 2
        contactNode.position.y = 0.001
        contactNode.castsShadow = false
        holder.addChildNode(contactNode)
        contact = contactNode
    }

    func setShadows(_ on: Bool) {
        guard on != shadows else { return }
        shadows = on
        holder.enumerateHierarchy { node, _ in
            if node !== self.contact, node !== self.water, node.geometry != nil { node.castsShadow = on }
        }
        contact.isHidden = !on
    }

    func tick(time: Double, dt: Double) {
        let t = time + phase
        if drawn != look {
            drawn = look
            displayMaterial.diffuse.contents = Textures.display(look)
            ledMaterial.diffuse.contents = Self.stateColor(look.state)
        }
        let busy = look.state == .busy
        clothesGroup.isHidden = !busy
        water.isHidden = !busy
        guard busy else { return }

        let spinning = look.spinning
        spin -= dt * (spinning ? 7 : 1.3)
        drum.eulerAngles.z = Float(spin)
        for (i, item) in clothes.enumerated() {
            let k = Double(i)
            if spinning {
                let a = spin + k * .pi / 2
                item.position = SCNVector3(Float(cos(a) * 0.13), Float(sin(a) * 0.13), Float(Double(i % 2) * 0.05 - 0.02))
            } else {
                // Lifted by the paddles, then falling back: a lopsided orbit in the lower half.
                let a = t * 1.3 + k * 1.6
                item.position = SCNVector3(Float(cos(a) * 0.1), Float(sin(a) * 0.07 - 0.05), Float(Double(i % 2) * 0.06 - 0.03))
            }
            item.eulerAngles = SCNVector3(Float(t * 0.7 + k), Float(t * 0.9 + k * 2), Float(t * 0.5))
        }
        if dt > 0 || water.geometry == nil {
            let g = Self.waterGeometry(level: spinning ? -0.13 : -0.015, t: t, amp: spinning ? 0.006 : 0.012)
            g.materials = [materials.water]
            water.geometry = g
        }
    }

    // MARK: Geometry

    /// A rounded slab, optionally with a round hole through it, extruded along z and centred on the origin.
    private static func slab(width w: CGFloat, height h: CGFloat, depth d: CGFloat, radius r: CGFloat, bevel b: CGFloat,
                             hole: (center: CGPoint, radius: CGFloat)? = nil, material: SCNMaterial) -> SCNGeometry {
        let path = UIBezierPath(roundedRect: CGRect(x: -w / 2, y: -h / 2, width: w, height: h), cornerRadius: r)
        if let hole {
            path.append(UIBezierPath(arcCenter: hole.center, radius: hole.radius, startAngle: 0, endAngle: 2 * .pi, clockwise: false))
            path.usesEvenOddFillRule = true
        }
        path.flatness = 0.0008
        let shape = SCNShape(path: path, extrusionDepth: d)
        shape.chamferRadius = b
        let profile = UIBezierPath()
        profile.move(to: CGPoint(x: 0, y: 1))
        profile.addQuadCurve(to: CGPoint(x: 1, y: 0), controlPoint: CGPoint(x: 1, y: 1))
        profile.flatness = 0.02
        shape.chamferProfile = profile
        shape.materials = [material]
        return shape
    }

    private static func cylinder(radius: CGFloat, height: CGFloat, material: SCNMaterial) -> SCNGeometry {
        let c = SCNCylinder(radius: radius, height: height)
        c.radialSegmentCount = 48
        c.materials = [material]
        return c
    }

    /// The water as seen through the door: a slice of the drum's circle below a gently moving surface.
    private static func waterGeometry(level: Double, t: Double, amp: Double) -> SCNGeometry {
        let r = 0.178, n = 36
        let xr = (max(0.0001, r * r - level * level)).squareRoot()
        var points: [SCNVector3] = [SCNVector3(0, Float((level - r) / 2), 0)]
        for k in 0...n {
            let x = -xr + 2 * xr * Double(k) / Double(n)
            let taper = 1 - pow(abs(x / xr), 6)
            let y = level + amp * taper * (sin(x * 22 + t * 2.6) * 0.7 + sin(x * 37 - t * 3.3) * 0.3)
            points.append(SCNVector3(Float(x), Float(y), 0))
        }
        let top = atan2(level, xr)
        for k in 1..<n {
            let th = top - (.pi + 2 * top) * Double(k) / Double(n)
            points.append(SCNVector3(Float(cos(th) * r), Float(sin(th) * r), 0))
        }
        var indices: [Int16] = []
        for i in 1..<points.count {
            let next = i + 1 < points.count ? i + 1 : 1
            indices += [0, Int16(i), Int16(next)]
        }
        let normals = [SCNVector3](repeating: SCNVector3(0, 0, 1), count: points.count)
        return SCNGeometry(sources: [SCNGeometrySource(vertices: points), SCNGeometrySource(normals: normals)],
                           elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
    }

    static func stateColor(_ state: DrumState) -> UIColor {
        switch state {
        case .busy: return UIColor(hex: 0x4D8BFF)
        case .idle: return UIColor(hex: 0x21CCA3)
        case .offline: return UIColor(white: 0.55, alpha: 1)
        }
    }
}

// MARK: - Textures

@MainActor
enum Textures {
    private static func render(_ size: CGSize, opaque: Bool = true, _ draw: (CGContext) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = opaque
        return UIGraphicsImageRenderer(size: size, format: format).image { draw($0.cgContext) }
    }

    /// A soft room for reflections: lighter toward a bright ceiling, with a window and a softer panel.
    static func environment() -> UIImage {
        render(CGSize(width: 512, height: 256)) { c in
            let colors = [UIColor(white: 0.8, alpha: 1).cgColor, UIColor(white: 0.62, alpha: 1).cgColor,
                          UIColor(white: 0.44, alpha: 1).cgColor] as CFArray
            if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.5, 1]) {
                c.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: 256), options: [])
            }
            c.setFillColor(UIColor.white.cgColor)
            c.fill(CGRect(x: 0, y: 0, width: 512, height: 24))
            c.fill(CGRect(x: 96, y: 72, width: 72, height: 60))
            c.setFillColor(UIColor(white: 0.9, alpha: 1).cgColor)
            c.fill(CGRect(x: 330, y: 84, width: 60, height: 48))
        }
    }

    /// The drum's stainless steel with its rows of holes.
    static func perforation() -> UIImage {
        render(CGSize(width: 256, height: 256)) { c in
            c.setFillColor(UIColor(hex: 0xC3C8D0).cgColor)
            c.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
            c.setFillColor(UIColor(hex: 0x5D636D).cgColor)
            var y: CGFloat = 8
            while y < 256 {
                var x: CGFloat = 8 + (Int(y / 16) % 2 == 1 ? 8 : 0)
                while x < 256 {
                    c.fillEllipse(in: CGRect(x: x - 3.2, y: y - 3.2, width: 6.4, height: 6.4))
                    x += 16
                }
                y += 16
            }
        }
    }

    static func contactShadow() -> UIImage {
        render(CGSize(width: 256, height: 256), opaque: false) { c in
            let colors = [UIColor(white: 0, alpha: 0.55).cgColor, UIColor(white: 0, alpha: 0.22).cgColor,
                          UIColor(white: 0, alpha: 0).cgColor] as CFArray
            guard let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.55, 1]) else { return }
            c.drawRadialGradient(g, startCenter: CGPoint(x: 128, y: 128), startRadius: 10,
                                 endCenter: CGPoint(x: 128, y: 128), endRadius: 128, options: [])
        }
    }

    /// The machine's own small display: its number, then the time left or READY.
    static func display(_ look: WasherLook) -> UIImage {
        render(CGSize(width: 512, height: 128)) { c in
            c.setFillColor(UIColor(hex: 0x0C1017).cgColor)
            c.fill(CGRect(x: 0, y: 0, width: 512, height: 128))
            UIGraphicsPushContext(c)
            let label: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 46, weight: .semibold),
                .foregroundColor: UIColor(white: 1, alpha: 0.55)
            ]
            let text = NSAttributedString(string: look.label, attributes: label)
            text.draw(at: CGPoint(x: 26, y: 64 - text.size().height / 2))

            let value: String
            let color: UIColor
            switch look.state {
            case .busy:
                value = look.clock.isEmpty ? "RUN" : look.clock
                color = UIColor(hex: 0x8DB6FF)
            case .idle:
                value = "READY"
                color = UIColor(hex: 0x3EE0B6)
            case .offline:
                value = "OFF"
                color = UIColor(white: 0.55, alpha: 1)
            }
            let big = NSAttributedString(string: value, attributes: [
                .font: UIFont.monospacedSystemFont(ofSize: 62, weight: .semibold),
                .foregroundColor: color
            ])
            let s = big.size()
            big.draw(at: CGPoint(x: 490 - s.width, y: 66 - s.height / 2))
            UIGraphicsPopContext()
        }
    }
}

extension UIColor {
    convenience init(hex: Int) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
