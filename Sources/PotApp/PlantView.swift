#if os(macOS)
import AppKit
import SwiftUI
import PotCore

/// Plain RGB so the renderer can blend palette colours deterministically (health, wilting).
private struct RGB {
    var r: Double, g: Double, b: Double
    init(_ hex: UInt32) { r = Double((hex >> 16) & 255) / 255; g = Double((hex >> 8) & 255) / 255; b = Double(hex & 255) / 255 }
    init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }
    func mixed(_ other: RGB, _ t: Double) -> RGB {
        let k = min(1, max(0, t))
        return RGB(r: r + (other.r - r) * k, g: g + (other.g - g) * k, b: b + (other.b - b) * k)
    }
    func lighter(_ t: Double) -> RGB { mixed(RGB(0xFFFFFF), t) }
    func darker(_ t: Double) -> RGB { mixed(RGB(0x000000), t) }
    var color: Color { Color(red: r, green: g, blue: b) }
}

/// Colours of the owner's botanical references (Pot — growth & recovery, variations 01–03, copihue).
private enum Palette {
    static func leaves(_ form: PlantForm) -> [RGB] {
        switch (form.provider, form.species) {
        case (.codex, .surprise): return [RGB(0x4F8E62), RGB(0x67A275), RGB(0x3F7A53), RGB(0x7DB486)]
        case (.codex, _): return [RGB(0x5A9C55), RGB(0x76B25F), RGB(0x4A8A49), RGB(0x8CC26E)]
        case (.claude, .copihue): return [RGB(0x4E9443), RGB(0x6AAE52), RGB(0x3F803A), RGB(0x86C064)]
        case (.claude, _): return [RGB(0x6E9E4A), RGB(0x88B556), RGB(0x5B8A3D), RGB(0x9EC567)]
        }
    }
    static func flowers(_ form: PlantForm) -> [(petal: RGB, center: RGB)] {
        switch (form.provider, form.species) {
        case (.codex, .classic): return [(RGB(0xFBF8EE), RGB(0xF0C534)), (RGB(0xF4B8C8), RGB(0xE7A03A)), (RGB(0xF7D543), RGB(0xE59A2B)), (RGB(0xC6A8E2), RGB(0xF0C534))]
        case (.codex, .blossom): return [(RGB(0xF1A9B8), RGB(0xD9788F)), (RGB(0xFFFFFF), RGB(0xF2C230)), (RGB(0xB996DE), RGB(0xF4D24B)), (RGB(0xF6CE48), RGB(0xE09A2A))]
        case (.codex, .surprise): return [(RGB(0xF6ECD9), RGB(0xE9C36A)), (RGB(0xF4C3B8), RGB(0xE9A06E)), (RGB(0x2E3A78), RGB(0xC9D85A)), (RGB(0x7C2442), RGB(0x4FC2B9)), (RGB(0xF3D44B), RGB(0xE6A52E))]
        case (.claude, .classic): return [(RGB(0xF27A44), RGB(0xF6C14C)), (RGB(0xF7C7A2), RGB(0xF2A65A)), (RGB(0xFBE8C8), RGB(0xF2B54E)), (RGB(0xB9A0DC), RGB(0xF4CC52))]
        case (.claude, .blossom): return [(RGB(0xF17B4E), RGB(0xE8483A)), (RGB(0xA98BDA), RGB(0xF2D04C)), (RGB(0xF8F2E4), RGB(0xE9D9B0))]
        case (.claude, .surprise): return [(RGB(0xF5823E), RGB(0xD6452E)), (RGB(0xEFE24A), RGB(0xD8378C)), (RGB(0x5B1F3B), RGB(0x46C4C0)), (RGB(0xFAF0DA), RGB(0xF1C454))]
        case (.codex, .copihue): return [(RGB(0xF8F2EA), RGB(0xE05A61))]
        case (.claude, .copihue): return [(RGB(0xE53A37), RGB(0xB3262C))]
        }
    }
    static let stem = RGB(0x5E8F45)
    static let yellow = RGB(0xD9C259)
    static let brown = RGB(0xA77B47)
    static let darkBrown = RGB(0x7C5733)
    static let stake = RGB(0xD49A5B)
    static func dryTone(_ base: RGB, _ dry: Double) -> RGB {
        dry < 0.5 ? base.mixed(yellow, dry * 2) : yellow.mixed(brown, (dry - 0.5) * 2)
    }
}

/// The form is designed to fit the 320×400 canvas, so no zoom is needed. FloatingPlant uses the
/// same form for its close button, hover zone and click-through hit testing.
enum PlantLayout {
    static let anchor = CGPoint(x: 160, y: 386)
    static func fitScale(_ plant: PlantState) -> Double { 1 }
    /// Canvas height (from the bottom) that holds this plant plus a little sky, so small plants
    /// don't sit under a tall empty frame. Use with `PlantView(crop: true)`.
    static func cropHeight(_ plant: PlantState, minimum: Double = 150) -> Double {
        max(minimum, min(400, 400 - (PlantFormBuilder.build(plant).bounds.minY - 26)))
    }
    static func visibleBounds(_ plant: PlantState) -> CGRect {
        let b = PlantFormBuilder.build(plant).bounds
        let minX = max(0, b.minX), minY = max(0, b.minY)
        return CGRect(x: minX, y: minY, width: min(320, b.maxX) - minX, height: min(400, b.maxY) - minY)
    }
    /// Whether a canvas point touches the pot or the plant (for click-through hit testing).
    static func contains(_ p: CGPoint, plant: PlantState) -> Bool {
        if CGRect(x: 100, y: 322, width: 120, height: 68).contains(p) { return true }
        let form = PlantFormBuilder.build(plant)
        func near(_ a: PlantForm.Point, _ b: PlantForm.Point, _ r: Double) -> Bool {
            let dx = b.x - a.x, dy = b.y - a.y, len = max(1, dx * dx + dy * dy)
            let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len))
            return hypot(p.x - a.x - t * dx, p.y - a.y - t * dy) < r
        }
        for s in form.stems { for (a, b) in zip(s.points, s.points.dropFirst()) where near(a, b, 7) { return true } }
        for l in form.leaves where near(l.base, l.tip, max(6, l.width * 0.55)) { return true }
        for f in form.flowers where hypot(p.x - f.center.x, p.y - f.center.y) < f.size + 4 { return true }
        return false
    }
}

@MainActor
final class SwipeGate {
    static let floating = SwipeGate()
    private var accumulation = 0.0
    private var switched = false
    private var lastSwitch = Date.distantPast
    private var lastEvent = Date.distantPast
    /// Returns −1 / +1 when this event completes a switch, otherwise nil.
    func direction(for event: NSEvent, threshold: Double = 45) -> Int? {
        let now = Date()
        defer { lastEvent = now }
        if event.phase.contains(.began) || event.phase.contains(.mayBegin) { accumulation = 0; switched = false }
        // A gesture that never reported its end (window changed under the fingers) expires.
        if switched && now.timeIntervalSince(lastEvent) > 0.35 { switched = false; accumulation = 0 }
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) { accumulation = 0; return nil }
        guard event.momentumPhase.isEmpty, !switched else { return nil }
        let dx = event.scrollingDeltaX, dy = event.scrollingDeltaY
        guard abs(dx) > abs(dy) * 1.2 else { return nil }
        let phased = !event.phase.isEmpty
        accumulation += event.hasPreciseScrollingDeltas ? dx : dx * 12
        // Mouse wheels have no phases: fall back to a cooldown.
        guard abs(accumulation) > threshold, phased || now.timeIntervalSince(lastSwitch) > 0.7 else { return nil }
        let result = accumulation > 0 ? -1 : 1
        switched = phased
        accumulation = 0
        lastSwitch = now
        return result
    }
}

/// Switching plants: the old one slides out and fades quickly, the new one slides in from the
/// side the gesture points to, so two pots never sit blended on top of each other.
enum PlantSwitch {
    static func transition(direction: Int) -> AnyTransition {
        let d: CGFloat = direction < 0 ? -1 : 1
        return .asymmetric(
            insertion: .offset(x: 46 * d).combined(with: .opacity).animation(.easeOut(duration: 0.26).delay(0.08)),
            removal: .offset(x: -46 * d).combined(with: .opacity).animation(.easeIn(duration: 0.14)))
    }
}

struct PlantView: View {
    let plant: PlantState
    var active = false
    /// Gentle continuous breathing while a window shows the plant. Off for the always-on
    /// floating panel to keep idle energy near zero; activity pulses still apply there.
    var idle = false
    /// Show only the bottom of the canvas that the frame's aspect allows, at the frame's width
    /// scale: the pot keeps its size and empty sky above small plants is cut away.
    var crop = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dancing = false

    /// Built once per plant update, not per animation frame.
    private var form: PlantForm { PlantFormBuilder.build(plant) }

    var body: some View {
        let form = self.form
        return TimelineView(.animation(minimumInterval: dancing ? 1.0 / 24 : 1.0 / 15, paused: !(dancing || idle) || reduceMotion)) { timeline in
            FormDrawing(form: form, crop: crop, sway: reduceMotion ? 0 : sway(at: timeline.date.timeIntervalSinceReferenceDate))
        }
        .onAppear { if active { pulse() } }
        .onChange(of: active) { _, value in if value { pulse() } else { dancing = false } }
        .onChange(of: plant.lastActivity) { _, _ in if active { pulse() } }
        .onDisappear { dancing = false }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(plant.provider.displayName) plant, \(PlantSpecies.of(seed: plant.seed).title(for: plant.provider))")
        .accessibilityValue(plant.health > 0.8 ? "Growing peacefully" : plant.health > 0.45 ? "A little thirsty" : "Wilted. A few days of work will bring it back.")
    }
    /// Activity dance, or a slow breeze unique to each plant (phase and tempo from its seed).
    private func sway(at t: Double) -> Double {
        if dancing { return sin(t * 3.8) * 0.018 }
        guard idle else { return 0 }
        let phase = Double(plant.seed % 997) / 997 * 2 * .pi
        let tempo = 0.9 + Double(plant.seed % 7) * 0.05
        return sin(t * tempo + phase) * 0.006 + sin(t * tempo * 2.3 + phase) * 0.0025
    }
    private func pulse() {
        guard !reduceMotion else { return }
        dancing = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            dancing = false
        }
    }
}


private struct FormDrawing: View {
    let form: PlantForm
    var crop = false
    var sway: Double

    var body: some View {
        Canvas { context, size in
            if crop {
                let scale = size.width / 320
                context.translateBy(x: 0, y: size.height - 400 * scale)
                context.scaleBy(x: scale, y: scale)
            } else {
                // Whole canvas, centred horizontally and resting on the bottom edge: the pot stays
                // put and the plant grows upward into the space above it.
                let scale = min(size.width / 320, size.height / 400)
                context.translateBy(x: (size.width - 320 * scale) / 2, y: size.height - 400 * scale)
                context.scaleBy(x: scale, y: scale)
            }
            let leafColours = Palette.leaves(form)
            let flowerColours = Palette.flowers(form)
            let w = form.wilt

            // Breeze: higher parts move more; the pot never moves.
            func pt(_ p: PlantForm.Point) -> CGPoint { CGPoint(x: p.x + sway * max(0, 332 - p.y) * 0.9, y: p.y) }

            // Soft ground shadow.
            context.fill(Path(ellipseIn: CGRect(x: 96, y: 382, width: 128, height: 10)),
                         with: .color(Color(red: 0.13, green: 0.23, blue: 0.17).opacity(0.10)))

            // Stake (copihue), then stems and branches.
            for stem in form.stems where stem.kind == .stake {
                guard let a = stem.points.first, let b = stem.points.last else { continue }
                var path = Path(); path.move(to: CGPoint(x: a.x, y: a.y)); path.addLine(to: CGPoint(x: b.x, y: b.y))
                context.stroke(path, with: .color(Palette.stake.color), style: StrokeStyle(lineWidth: stem.width, lineCap: .round))
                var light = Path(); light.move(to: CGPoint(x: a.x - 1, y: a.y)); light.addLine(to: CGPoint(x: b.x - 1, y: b.y + 4))
                context.stroke(light, with: .color(Palette.stake.lighter(0.35).color), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
            }
            let stemTone = (form.recovering ? Palette.stem : Palette.dryTone(Palette.stem, max(0, w - 0.15) * 1.1)).color
            for stem in form.stems where stem.kind != .stake {
                guard stem.points.count > 1 else { continue }
                var path = Path()
                path.move(to: pt(stem.points[0]))
                for i in 1..<stem.points.count {
                    let a = pt(stem.points[i - 1]), b = pt(stem.points[i])
                    path.addQuadCurve(to: CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2), control: a)
                }
                path.addLine(to: pt(stem.points[stem.points.count - 1]))
                context.stroke(path, with: .color(stemTone), style: StrokeStyle(lineWidth: stem.width, lineCap: .round, lineJoin: .round))
            }

            // Leaves: two-tone body with a soft midrib, like the references.
            for leaf in form.leaves {
                var layer = context
                let base = pt(leaf.base)
                layer.translateBy(x: base.x, y: base.y)
                layer.rotate(by: .radians(leaf.angle))
                let tone = Palette.dryTone(leafColours[abs(leaf.tone) % leafColours.count], leaf.dry)
                let (body, half) = leafPaths(leaf)
                layer.fill(body, with: .color(tone.color))
                layer.fill(half, with: .color(tone.lighter(0.16).color))
                if leaf.length > 12 && leaf.shape != .cotyledon {
                    var rib = Path(); rib.move(to: CGPoint(x: 0, y: -leaf.length * 0.08)); rib.addLine(to: CGPoint(x: 0, y: -leaf.length * 0.82))
                    layer.stroke(rib, with: .color(tone.darker(0.18).color.opacity(0.55)), style: StrokeStyle(lineWidth: 0.9, lineCap: .round))
                }
            }

            // Flowers and buds on top.
            for flower in form.flowers {
                let colours = flowerColours[abs(flower.color) % flowerColours.count]
                var layer = context
                let c = pt(flower.center)
                layer.translateBy(x: c.x, y: c.y)
                // Hanging flowers swing further down as they wilt.
                layer.rotate(by: .radians(flower.angle + (flower.hanging ? (flower.angle >= 0 ? 0.6 : -0.6) * flower.fade : 0)))
                let petal = colours.petal.mixed(RGB(0xC9A27E), flower.fade * 0.75)
                drawFlower(flower, in: layer, petal: petal, center: colours.center.mixed(Palette.brown, flower.fade * 0.6))
            }

            drawPot(context)

            // Fallen leaves resting on the ground around the pot.
            for i in 0..<form.fallenLeaves {
                var layer = context
                let x = [92.0, 228, 104, 216, 84, 236, 120, 200, 96][i % 9]
                layer.translateBy(x: x, y: 387 - Double(i % 2) * 1.5)
                layer.rotate(by: .radians(i % 2 == 0 ? 1.35 : -1.4))
                var leaf = Path()
                leaf.move(to: .zero)
                leaf.addQuadCurve(to: CGPoint(x: 0, y: -12), control: CGPoint(x: -5, y: -6))
                leaf.addQuadCurve(to: .zero, control: CGPoint(x: 5, y: -6))
                layer.fill(leaf, with: .color((i % 3 == 0 ? Palette.yellow : Palette.brown).color))
            }
        }
    }

    /// Leaf outline drawn upward from its base (−y), plus its lighter half.
    private func leafPaths(_ leaf: PlantForm.Leaf) -> (Path, Path) {
        let L = leaf.length, W = leaf.width / 2
        func p(_ a: Double, _ c: Double) -> CGPoint { CGPoint(x: c * W, y: -a * L) }
        var body = Path(), half = Path()
        switch leaf.shape {
        case .round, .cotyledon, .broad:
            let k = leaf.shape == .broad ? 1.15 : 1.05
            body.move(to: .zero)
            body.addCurve(to: p(1, 0), control1: p(0.05, -1.25 * k), control2: p(0.95, -0.95 * k))
            body.addCurve(to: .zero, control1: p(0.95, 0.95 * k), control2: p(0.05, 1.25 * k))
            half.move(to: .zero); half.addCurve(to: p(1, 0), control1: p(0.05, -1.25 * k), control2: p(0.95, -0.95 * k)); half.closeSubpath()
        case .oval, .heart:
            body.move(to: .zero)
            body.addCurve(to: p(1, 0), control1: p(0.18, -1.3), control2: p(0.8, -0.75))
            body.addCurve(to: .zero, control1: p(0.8, 0.75), control2: p(0.18, 1.3))
            half.move(to: .zero); half.addCurve(to: p(1, 0), control1: p(0.18, -1.3), control2: p(0.8, -0.75)); half.closeSubpath()
        case .lance, .longLance, .slender:
            body.move(to: .zero)
            body.addCurve(to: p(1, 0), control1: p(0.3, -1.35), control2: p(0.72, -0.9))
            body.addCurve(to: .zero, control1: p(0.72, 0.9), control2: p(0.3, 1.35))
            half.move(to: .zero); half.addCurve(to: p(1, 0), control1: p(0.3, -1.35), control2: p(0.72, -0.9)); half.closeSubpath()
        }
        return (body, half)
    }

    private func drawFlower(_ f: PlantForm.Flower, in ctx: GraphicsContext, petal: RGB, center: RGB) {
        let s = f.size
        func circle(_ x: Double, _ y: Double, _ r: Double) -> Path { Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)) }
        switch f.kind {
        case .bud:
            // Green calyx with the petal colour showing at the tip.
            let h = s * (0.9 + 0.5 * f.openness), wd = s * 0.55
            ctx.fill(Path(ellipseIn: CGRect(x: -wd / 2, y: -h, width: wd, height: h)), with: .color(petal.mixed(Palette.stem, 0.65 - f.openness).color))
            var calyx = Path()
            calyx.move(to: CGPoint(x: -wd * 0.6, y: -h * 0.3)); calyx.addQuadCurve(to: CGPoint(x: wd * 0.6, y: -h * 0.3), control: CGPoint(x: 0, y: h * 0.25))
            calyx.addQuadCurve(to: CGPoint(x: -wd * 0.6, y: -h * 0.3), control: CGPoint(x: 0, y: -h * 0.55))
            ctx.fill(calyx, with: .color(Palette.stem.color))
        case .driedPod:
            ctx.fill(Path(ellipseIn: CGRect(x: -s * 0.3, y: 0, width: s * 0.6, height: s * 1.2)), with: .color(Palette.darkBrown.color))
            var tip = Path(); tip.move(to: CGPoint(x: 0, y: s * 1.2)); tip.addLine(to: CGPoint(x: 0, y: s * 1.55))
            ctx.stroke(tip, with: .color(Palette.darkBrown.color), lineWidth: 1)
        case .bell:
            // Copihue-style bell hanging mouth-down from the pedicel, with a scalloped flared rim.
            let open = 0.8 + 0.2 * f.openness, h = s * 1.9, top = s * 0.28, mouth = s * 0.62 * open
            func q(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }
            var bell = Path()
            bell.move(to: q(-top, 0))
            bell.addCurve(to: q(-mouth * 0.92, h * 0.78), control1: q(-top * 2.2, h * 0.15), control2: q(-mouth * 1.05, h * 0.45))
            bell.addQuadCurve(to: q(-mouth * 1.12, h), control: q(-mouth * 0.95, h * 0.93))
            bell.addQuadCurve(to: q(-mouth * 0.36, h * 0.95), control: q(-mouth * 0.76, h * 1.05))
            bell.addQuadCurve(to: q(mouth * 0.36, h * 0.95), control: q(0, h * 1.07))
            bell.addQuadCurve(to: q(mouth * 1.12, h), control: q(mouth * 0.76, h * 1.05))
            bell.addQuadCurve(to: q(mouth * 0.92, h * 0.78), control: q(mouth * 0.95, h * 0.93))
            bell.addCurve(to: q(top, 0), control1: q(mouth * 1.05, h * 0.45), control2: q(top * 2.2, h * 0.15))
            bell.closeSubpath()
            ctx.fill(bell, with: .color(petal.color))
            // Light on one side, colour deepening toward the mouth.
            var light = Path()
            light.move(to: q(top * 0.2, h * 0.05))
            light.addCurve(to: q(mouth * 0.6, h * 0.86), control1: q(top * 1.6, h * 0.2), control2: q(mouth * 0.8, h * 0.5))
            light.addLine(to: q(mouth * 0.1, h * 0.9)); light.closeSubpath()
            ctx.fill(light, with: .color(petal.lighter(0.25).color.opacity(0.7)))
            for x in [-0.55, 0.0, 0.55] {
                var vein = Path(); vein.move(to: q(x * top, h * 0.12)); vein.addQuadCurve(to: q(x * mouth, h * 0.93), control: q(x * mouth * 0.7, h * 0.5))
                ctx.stroke(vein, with: .color(center.color.opacity(0.45)), lineWidth: 0.8)
            }
            var rim = Path()
            rim.move(to: q(-mouth * 1.12, h)); rim.addQuadCurve(to: q(-mouth * 0.36, h * 0.95), control: q(-mouth * 0.76, h * 1.05))
            rim.addQuadCurve(to: q(mouth * 0.36, h * 0.95), control: q(0, h * 1.07)); rim.addQuadCurve(to: q(mouth * 1.12, h), control: q(mouth * 0.76, h * 1.05))
            ctx.stroke(rim, with: .color(center.color), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
            ctx.fill(Path(ellipseIn: CGRect(x: -top * 0.9, y: -top * 0.5, width: top * 1.8, height: top)), with: .color(Palette.stem.color))
        default:
            let open = 0.55 + 0.45 * f.openness
            switch f.kind {
            case .round5, .smallStar, .star5:
                let pointed = f.kind != .round5
                for i in 0..<5 {
                    var leaf = ctx
                    leaf.rotate(by: .radians(Double(i) * 2 * .pi / 5))
                    let L = s * open, Wd = s * (pointed ? 0.42 : 0.62) * open
                    var path = Path()
                    if pointed {
                        path.move(to: .zero)
                        path.addQuadCurve(to: CGPoint(x: 0, y: -L), control: CGPoint(x: -Wd, y: -L * 0.45))
                        path.addQuadCurve(to: .zero, control: CGPoint(x: Wd, y: -L * 0.45))
                    } else {
                        path = Path(ellipseIn: CGRect(x: -Wd / 2, y: -L, width: Wd, height: L * 0.98))
                    }
                    leaf.fill(path, with: .color(petal.color))
                    leaf.fill(Path(ellipseIn: CGRect(x: -Wd * 0.18, y: -L * 0.8, width: Wd * 0.36, height: L * 0.5)), with: .color(petal.lighter(0.18).color.opacity(0.6)))
                }
                ctx.fill(circle(0, 0, s * 0.26), with: .color(center.color))
            case .daisy:
                for i in 0..<12 {
                    var leaf = ctx
                    leaf.rotate(by: .radians(Double(i) * 2 * .pi / 12))
                    leaf.fill(Path(ellipseIn: CGRect(x: -s * 0.12, y: -s * open, width: s * 0.24, height: s * 0.8 * open)), with: .color(petal.color))
                }
                ctx.fill(circle(0, 0, s * 0.3), with: .color(center.color))
                ctx.fill(circle(-s * 0.08, -s * 0.08, s * 0.12), with: .color(center.lighter(0.3).color.opacity(0.7)))
            case .rose:
                // Five outer petals, a cupped middle and a swirled heart.
                for i in 0..<5 {
                    let a = Double(i) * 2 * .pi / 5
                    ctx.fill(circle(sin(a) * s * 0.42 * open, -cos(a) * s * 0.42 * open, s * 0.5 * open), with: .color(petal.color))
                }
                ctx.fill(circle(0, 0, s * 0.55 * open), with: .color(petal.lighter(0.12).color))
                for (r, start) in [(0.42, 190.0), (0.28, 20.0), (0.16, 200.0)] {
                    var arc = Path(); arc.addArc(center: .zero, radius: s * r * open, startAngle: .degrees(start), endAngle: .degrees(start + 200), clockwise: false)
                    ctx.stroke(arc, with: .color(petal.darker(0.16).color), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
                }
            case .camellia:
                for ring in 0..<2 {
                    for i in 0..<6 {
                        var leaf = ctx
                        leaf.rotate(by: .radians(Double(i) * .pi / 3 + Double(ring) * .pi / 6))
                        let r = s * open * (ring == 0 ? 1 : 0.68)
                        leaf.fill(Path(ellipseIn: CGRect(x: -r * 0.36, y: -r, width: r * 0.72, height: r * 0.86)),
                                  with: .color((ring == 0 ? petal : petal.lighter(0.12)).color))
                    }
                }
                ctx.fill(circle(0, 0, s * 0.22), with: .color(center.color))
            default: break
            }
        }
    }

    private func drawPot(_ context: GraphicsContext) {
        if form.provider == .codex {
            // Sage rounded planter.
            let body = Path(roundedRect: CGRect(x: 108, y: 334, width: 104, height: 52), cornerRadius: 13)
            context.fill(body, with: .color(RGB(0x6E9C88).color))
            context.fill(Path(roundedRect: CGRect(x: 104, y: 328, width: 112, height: 14), cornerRadius: 7), with: .color(RGB(0x86B09E).color))
            var shine = Path(); shine.move(to: CGPoint(x: 118, y: 348)); shine.addLine(to: CGPoint(x: 118, y: 372))
            context.stroke(shine, with: .color(RGB(0xA7C8B9).color.opacity(0.8)), style: StrokeStyle(lineWidth: 4, lineCap: .round))
        } else {
            // Terracotta flared pot.
            var pot = Path()
            pot.move(to: CGPoint(x: 110, y: 338)); pot.addLine(to: CGPoint(x: 210, y: 338)); pot.addLine(to: CGPoint(x: 199, y: 382))
            pot.addQuadCurve(to: CGPoint(x: 121, y: 382), control: CGPoint(x: 160, y: 390)); pot.closeSubpath()
            context.fill(pot, with: .color(RGB(0xCB7448).color))
            context.fill(Path(roundedRect: CGRect(x: 104, y: 328, width: 112, height: 15), cornerRadius: 5), with: .color(RGB(0xDC8B5E).color))
            var shine = Path(); shine.move(to: CGPoint(x: 120, y: 348)); shine.addLine(to: CGPoint(x: 126, y: 374))
            context.stroke(shine, with: .color(RGB(0xE5A27C).color), style: StrokeStyle(lineWidth: 4, lineCap: .round))
        }
    }
}
#endif
