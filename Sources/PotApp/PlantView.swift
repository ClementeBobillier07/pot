#if os(macOS)
import SwiftUI
import PotCore

/// Plain RGB so the renderer can blend palette colors deterministically (age, health, wilting).
private struct RGB {
    var r: Double, g: Double, b: Double
    init(_ hex: UInt32) { r = Double((hex >> 16) & 255) / 255; g = Double((hex >> 8) & 255) / 255; b = Double(hex & 255) / 255 }
    init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }
    func mixed(_ other: RGB, _ t: Double) -> RGB {
        let k = min(1, max(0, t))
        return RGB(r: r + (other.r - r) * k, g: g + (other.g - g) * k, b: b + (other.b - b) * k)
    }
    var color: Color { Color(red: r, green: g, blue: b) }
}

/// Visual language shared with the landing illustrations (landing/components/Plant.tsx):
/// Codex grows rounded eucalyptus leaves in a sage pot; Claude Code grows slender pointed
/// leaves in a terracotta pot. Flowers are flat ellipse petals around a golden center.
private struct PlantPalette {
    let leaves: [RGB]
    let flowers: [RGB]
    let stem: RGB
    let petals: Int
    static let codex = PlantPalette(leaves: [RGB(0x477C60), RGB(0x63976F), RGB(0x9DB68D), RGB(0x568A68)],
                                    flowers: [RGB(0xE4C761), RGB(0xF2E9BA), RGB(0xDFB5CD), RGB(0xB7A1CE)],
                                    stem: RGB(0x55815B), petals: 5)
    static let claude = PlantPalette(leaves: [RGB(0x537850), RGB(0x6E915C), RGB(0x9CAB76), RGB(0x647F4E)],
                                     flowers: [RGB(0xE79C77), RGB(0xDB8069), RGB(0xF1D69B), RGB(0xAE94C0)],
                                     stem: RGB(0x73864C), petals: 6)
    static let center = RGB(0xC49C49)
    static let tired = RGB(0xB8A85E)      // low turgor, under-watered foliage
    static let autumn = RGB(0xC2B26C)     // a leaf near the end of its natural life
    static let dried = RGB(0xA88D72)      // wilting petals
}

/// Mature plants can reach past the 320×400 canvas. The frame zooms out gently around the pot,
/// never below 72 %, so detail stays visible (master doc §8 "Renovación sin saturación").
/// FloatingPlant hit testing can apply the same scale around (160, 392).
enum PlantLayout {
    static let anchor = CGPoint(x: 160, y: 392)
    static func fitScale(_ plant: PlantState) -> Double {
        var minX = 40.0, maxX = 280.0, minY = 30.0
        for organ in plant.organs {
            let end = organ.endpoint
            let reach: Double
            switch organ.kind {
            case .stem, .branch: reach = 4
            case .leaf: reach = 9 + organ.size * 5.5
            case .flower: reach = 18 + organ.size * 1.9
            }
            for p in [(organ.x, organ.y), (end.x, end.y)] {
                minX = min(minX, p.0 * 320 - reach); maxX = max(maxX, p.0 * 320 + reach); minY = min(minY, p.1 * 400 - reach)
            }
        }
        let horizontal = min((anchor.x - 4) / max(1, anchor.x - minX), (316 - anchor.x) / max(1, maxX - anchor.x))
        let vertical = (anchor.y - 4) / max(1, anchor.y - minY)
        return max(0.72, min(1, horizontal, vertical))
    }

    /// Visible extent of pot and organs in the 320×400 canvas, after the fit zoom.
    /// The floating panel uses it to place its close button and its hover zone.
    static func visibleBounds(_ plant: PlantState) -> CGRect {
        var minX = 88.0, maxX = 232.0, minY = 318.0, maxY = 396.0 // pot
        for organ in plant.organs {
            let end = organ.endpoint
            let reach: Double
            switch organ.kind {
            case .stem, .branch: reach = 4
            case .leaf: reach = 9 + organ.size * 5.5
            case .flower: reach = 18 + organ.size * 1.9
            }
            for p in [(organ.x, organ.y), (end.x, end.y)] {
                minX = min(minX, p.0 * 320 - reach); maxX = max(maxX, p.0 * 320 + reach); minY = min(minY, p.1 * 400 - reach)
            }
        }
        let fit = fitScale(plant)
        func t(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: anchor.x + (x - anchor.x) * fit, y: anchor.y + (y - anchor.y) * fit) }
        let a = t(minX, minY), b = t(maxX, maxY)
        return CGRect(x: max(0, a.x), y: max(0, a.y), width: min(320, b.x) - max(0, a.x), height: min(400, b.y) - max(0, a.y))
    }
}

struct PlantView: View {
    let plant: PlantState
    var active = false
    /// Gentle continuous breathing while a window shows the plant. Off for the always-on
    /// floating panel to keep idle energy near zero; activity pulses still apply there.
    var idle = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dancing = false
    @State private var oldSizes: [String: Double] = [:]
    @State private var oldMaturation: [String: Double] = [:]
    @State private var blend = 1.0

    var body: some View {
        TimelineView(.animation(minimumInterval: dancing ? 1.0 / 24 : 1.0 / 15, paused: !(dancing || idle) || reduceMotion)) { timeline in
            PlantDrawing(plant: plant, oldSizes: oldSizes, oldMaturation: oldMaturation, blend: blend,
                         sway: reduceMotion ? 0 : sway(at: timeline.date.timeIntervalSinceReferenceDate))
        }
        .onAppear { if active { pulse() } }
        .onChange(of: active) { _, value in if value { pulse() } else { dancing = false } }
        .onChange(of: plant.lastActivity) { _, _ in if active { pulse() } }
        .onDisappear { dancing = false }
        .onChange(of: plant.organs) { before, after in
            let previous = Dictionary(uniqueKeysWithValues: before.map { ($0.id, $0) })
            guard after.contains(where: { organ in
                guard let old = previous[organ.id] else { return true }
                return abs(old.size - organ.size) > 0.00001 || abs(old.maturation - organ.maturation) > 0.00001
            }) else { return }
            oldSizes = Dictionary(uniqueKeysWithValues: before.map { ($0.id, $0.size) })
            oldMaturation = Dictionary(uniqueKeysWithValues: before.map { ($0.id, $0.maturation) })
            blend = reduceMotion ? 1 : 0
            withAnimation(.easeInOut(duration: 1.6)) { blend = 1 }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(plant.provider.displayName) plant")
        .accessibilityValue(plant.health > 0.65 ? "Growing peacefully" : "Resting. Ready to recover when you return.")
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

private struct PlantDrawing: View, Animatable {
    let plant: PlantState
    let oldSizes: [String: Double]
    let oldMaturation: [String: Double]
    var blend: Double
    var sway: Double
    var animatableData: Double {
        get { blend }
        set { blend = newValue }
    }
    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / 320, size.height / 400)
            context.translateBy(x: (size.width - 320 * scale) / 2, y: (size.height - 400 * scale) / 2)
            context.scaleBy(x: scale, y: scale)
            let codex = plant.provider == .codex
            let palette = codex ? PlantPalette.codex : PlantPalette.claude
            let health = min(1, max(0.2, plant.health))
            let fit = PlantLayout.fitScale(plant)

            // Soft ground shadow stays anchored to the pot.
            context.fill(Path(ellipseIn: CGRect(x: 84, y: 384, width: 152, height: 11)),
                         with: .color(Color(red: 0.13, green: 0.23, blue: 0.17).opacity(0.09)))

            var layer = context
            layer.translateBy(x: PlantLayout.anchor.x, y: PlantLayout.anchor.y)
            layer.scaleBy(x: fit, y: fit)
            layer.translateBy(x: -PlantLayout.anchor.x, y: -PlantLayout.anchor.y)

            func point(_ x: Double, _ y: Double) -> CGPoint {
                CGPoint(x: x * 320 + sway * (0.80 - y) * 320, y: y * 400)
            }
            func currentSize(_ organ: PlantOrgan) -> Double {
                let old = oldSizes[organ.id] ?? 1
                return old + (organ.size - old) * blend
            }
            func currentMaturity(_ organ: PlantOrgan) -> Double {
                let old = oldMaturation[organ.id] ?? 0
                return old + (organ.maturation - old) * blend
            }

            // Stems and branches: gently arching strokes, like the landing's quadratic shoots.
            let stemColor = palette.stem.mixed(PlantPalette.tired, (1 - health) * 0.5).color
            for organ in plant.organs where organ.kind == .stem || organ.kind == .branch {
                let start = point(organ.x, organ.y)
                let end = point(organ.endpoint.x, organ.endpoint.y)
                var path = Path()
                path.move(to: start)
                if organ.kind == .stem {
                    let bend = [-0.06, 0.04, 0.08][abs(organ.shape) % 3] * (start.y - end.y)
                    path.addQuadCurve(to: end, control: CGPoint(x: (start.x + end.x) / 2 + bend, y: (start.y + end.y) / 2))
                } else {
                    // Rise first, then lean outward.
                    path.addQuadCurve(to: end, control: CGPoint(x: start.x + (end.x - start.x) * 0.2, y: start.y + (end.y - start.y) * 0.85))
                }
                layer.stroke(path, with: .color(stemColor), style: StrokeStyle(lineWidth: organ.kind == .stem ? 4.4 : 3.3, lineCap: .round))
            }

            func leafPath(length: Double, variation: Double) -> Path {
                // a = along the leaf (drawn upward, -y), c = across.
                func p(_ a: Double, _ c: Double) -> CGPoint { CGPoint(x: c * length * variation, y: -a * length) }
                var leaf = Path()
                leaf.move(to: .zero)
                if codex {
                    leaf.addCurve(to: p(1, 0), control1: p(0.1, -0.62), control2: p(0.92, -0.58))
                    leaf.addCurve(to: .zero, control1: p(0.82, 0.52), control2: p(0.15, 0.55))
                } else {
                    leaf.addQuadCurve(to: p(1, 0), control: p(0.3, -0.5))
                    leaf.addQuadCurve(to: .zero, control: p(0.32, 0.32))
                }
                return leaf
            }

            // Growing tips: a terminal shoot without a flower ends in a small leaflet pair
            // instead of a bare stick. Purely decorative; derived from the graph, not stored.
            let parents = Set(plant.organs.filter { $0.kind != .leaf }.compactMap(\.parentID))
            for organ in plant.organs where (organ.kind == .stem || organ.kind == .branch) && !parents.contains(organ.id) && organ.maturation > 0.2 {
                let start = point(organ.x, organ.y)
                let end = point(organ.endpoint.x, organ.endpoint.y)
                let heading = atan2(end.x - start.x, -(end.y - start.y))
                let length = 8 + 9 * min(1, organ.maturation)
                let tone = palette.leaves[(abs(organ.colorIndex) + 2) % palette.leaves.count].mixed(PlantPalette.tired, (1 - health) * 0.65)
                for spread in [-0.45, 0.4] {
                    var tip = layer
                    tip.translateBy(x: end.x, y: end.y)
                    tip.rotate(by: .radians(heading + spread))
                    tip.fill(leafPath(length: length, variation: 0.9), with: .color(tone.color))
                }
            }

            // Leaves: engine order is birth order, so new growth sits on top of old.
            for organ in plant.organs where organ.kind == .leaf {
                var leafLayer = layer
                let anchor = point(organ.x, organ.y)
                leafLayer.translateBy(x: anchor.x, y: anchor.y)
                // Low health lowers turgor: leaves droop away from vertical.
                let side: Double = organ.orientation >= 0 ? 1 : -1
                leafLayer.rotate(by: .radians(organ.orientation + side * (1 - health) * 0.55))
                let length = 9 + currentSize(organ) * 5.5
                let variation = [1.0, 0.9, 1.1][abs(organ.shape) % 3]
                func p(_ a: Double, _ c: Double) -> CGPoint { CGPoint(x: c * length * variation, y: -a * length) }
                let days = organ.ageHours / 24
                let ageing = max(0, min(1, (days - 24) / 11)) * 0.45
                let tone = palette.leaves[abs(organ.colorIndex) % palette.leaves.count]
                    .mixed(PlantPalette.autumn, ageing)
                    .mixed(PlantPalette.tired, (1 - health) * 0.65)
                leafLayer.fill(leafPath(length: length, variation: variation), with: .color(tone.color))
                if length > 26 {
                    // A faint midrib on grown leaves; invisible on seedlings.
                    var rib = Path()
                    rib.move(to: p(0.12, 0))
                    rib.addQuadCurve(to: p(0.78, codex ? -0.04 : 0.02), control: p(0.45, codex ? -0.06 : 0.04))
                    leafLayer.stroke(rib, with: .color(.white.opacity(0.16)), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
                }
            }

            // Flowers on top: green knot → bud → opening cup → full bloom → wilting.
            for organ in plant.organs where organ.kind == .flower {
                let m = currentMaturity(organ)
                guard m < 1 else { continue }
                var flower = layer
                let anchor = point(organ.x, organ.y)
                flower.translateBy(x: anchor.x, y: anchor.y)
                let wilt = max(0, min(1, (m - 0.92) / 0.08))
                let side: Double = organ.orientation >= 0 ? 1 : -1
                flower.rotate(by: .radians(organ.orientation + side * wilt * 0.9 + side * (1 - health) * 0.25))
                let base = palette.flowers[abs(organ.colorIndex) % palette.flowers.count]
                let petalColor = base.mixed(PlantPalette.dried, wilt * 0.7 + (1 - health) * 0.25)
                let s = currentSize(organ)
                if m < 0.10 {
                    let r = 3.5 + m * 25
                    flower.fill(Path(ellipseIn: CGRect(x: -r * 0.7, y: -r * 1.6, width: r * 1.4, height: r * 1.8)), with: .color(palette.stem.color))
                } else if m < 0.35 {
                    // Closed bud: color shows at the tip as it swells.
                    let t = (m - 0.10) / 0.25
                    let w = 7 + t * 5, h = 11 + t * 9
                    flower.fill(Path(ellipseIn: CGRect(x: -w / 2, y: -h, width: w, height: h)),
                                with: .color(petalColor.mixed(palette.stem, 0.55 - t * 0.5).color))
                    var calyx = Path()
                    calyx.move(to: CGPoint(x: -w * 0.55, y: -h * 0.18))
                    calyx.addQuadCurve(to: CGPoint(x: w * 0.55, y: -h * 0.18), control: CGPoint(x: 0, y: h * 0.25))
                    calyx.addQuadCurve(to: CGPoint(x: -w * 0.55, y: -h * 0.18), control: CGPoint(x: 0, y: -h * 0.55))
                    flower.fill(calyx, with: .color(palette.stem.color))
                } else {
                    let open = min(1, (m - 0.35) / 0.25)
                    let eased = open * open * (3 - 2 * open)
                    let petals = palette.petals + (abs(organ.shape) % 3 == 2 ? 1 : 0)
                    let full = 22 + s * 1.4
                    let length = full * (0.72 + 0.28 * eased) * (1 - wilt * 0.3)
                    let width = length * 0.47
                    // Opening petals fan out from a cup; open flowers face the viewer.
                    let spread = 0.32 + 0.68 * eased
                    for index in 0..<petals {
                        if wilt > 0.45 && index % 2 == 1 { continue } // petals begin to fall
                        var petal = flower
                        let angle = (Double(index) - Double(petals - 1) / 2) * (2 * .pi / Double(petals)) * spread
                        petal.rotate(by: .radians(angle))
                        let rect = CGRect(x: -width / 2, y: -length * 0.86, width: width, height: length)
                        petal.fill(Path(ellipseIn: rect), with: .color(petalColor.color.opacity(1 - wilt * 0.35)))
                    }
                    let r = (6.5 + s * 0.25) * (0.55 + 0.45 * eased)
                    flower.fill(Path(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2)),
                                with: .color(PlantPalette.center.mixed(PlantPalette.dried, wilt * 0.5).color))
                }
            }

            // The provider identity belongs to the pot, even for a newly born seedling.
            if codex {
                var body = Path()
                body.move(to: CGPoint(x: 94, y: 318)); body.addLine(to: CGPoint(x: 226, y: 318)); body.addLine(to: CGPoint(x: 226, y: 371))
                body.addQuadCurve(to: CGPoint(x: 207, y: 387), control: CGPoint(x: 226, y: 387)); body.addLine(to: CGPoint(x: 113, y: 387))
                body.addQuadCurve(to: CGPoint(x: 94, y: 368), control: CGPoint(x: 94, y: 387)); body.closeSubpath()
                context.fill(body, with: .color(RGB(0x74998D).color))
                context.fill(Path(roundedRect: CGRect(x: 92, y: 311, width: 136, height: 17), cornerRadius: 6), with: .color(RGB(0x91AFA3).color))
                var shine = Path(); shine.move(to: CGPoint(x: 106, y: 335)); shine.addLine(to: CGPoint(x: 106, y: 366))
                shine.addQuadCurve(to: CGPoint(x: 116, y: 375), control: CGPoint(x: 106, y: 375))
                context.stroke(shine, with: .color(RGB(0xA8C0B4).color.opacity(0.7)), style: StrokeStyle(lineWidth: 6, lineCap: .round))
            } else {
                var pot = Path()
                pot.move(to: CGPoint(x: 92, y: 322)); pot.addLine(to: CGPoint(x: 228, y: 322)); pot.addLine(to: CGPoint(x: 215, y: 379))
                pot.addQuadCurve(to: CGPoint(x: 105, y: 379), control: CGPoint(x: 160, y: 394)); pot.closeSubpath()
                context.fill(pot, with: .color(RGB(0xBB7B59).color))
                context.fill(Path(roundedRect: CGRect(x: 85, y: 310, width: 150, height: 21), cornerRadius: 6), with: .color(RGB(0xD49D7D).color))
                var shine = Path(); shine.move(to: CGPoint(x: 102, y: 337)); shine.addLine(to: CGPoint(x: 113, y: 372))
                context.stroke(shine, with: .color(RGB(0xD99E7C).color), style: StrokeStyle(lineWidth: 6, lineCap: .round))
            }
        }

    }
}
#endif
