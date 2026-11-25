#if os(macOS)
import SwiftUI
import PotCore

private extension Color {
    init(hex: UInt32) { self.init(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255) }
}

struct PlantView: View {
    let plant: PlantState
    var active = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dancing = false
    @State private var oldSizes: [String: Double] = [:]
    @State private var oldMaturation: [String: Double] = [:]
    @State private var blend = 1.0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !dancing || reduceMotion)) { timeline in
            PlantDrawing(plant: plant, oldSizes: oldSizes, oldMaturation: oldMaturation, blend: blend,
                         sway: dancing && !reduceMotion ? sin(timeline.date.timeIntervalSinceReferenceDate * 3.8) * 0.018 : 0)
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
            let greens: [Color] = codex ? [.init(hex: 0x41765D), .init(hex: 0x5C916F), .init(hex: 0x8EAE82), .init(hex: 0xAFBF8E)] : [.init(hex: 0x567951), .init(hex: 0x6D8C57), .init(hex: 0x8D9F68), .init(hex: 0xADB77E)]
            let flowers: [Color] = codex ? [.init(hex: 0xF2CB66), .init(hex: 0xE8BDD4), .init(hex: 0xF8F1D0), .init(hex: 0xB7A1CE)] : [.init(hex: 0xE78B70), .init(hex: 0xD97562), .init(hex: 0xF4D9A0), .init(hex: 0xB09AC6)]
            func point(_ x: Double, _ y: Double) -> CGPoint {
                CGPoint(x: x * 320 + sway * (0.80 - y) * 320, y: y * 400)
            }
            for organ in plant.organs where organ.kind == .stem || organ.kind == .branch {
                var path = Path()
                let start = point(organ.x, organ.y)
                let end = point(organ.endpoint.x, organ.endpoint.y)
                path.move(to: start)
                path.addLine(to: end)
                context.stroke(path, with: .color(greens[0].opacity(0.85)), style: StrokeStyle(lineWidth: organ.kind == .stem ? 4.5 : 2.8, lineCap: .round))
            }
            for organ in plant.organs where organ.kind == .leaf || organ.kind == .flower {
                var local = context
                let anchor = point(organ.x, organ.y)
                local.translateBy(x: anchor.x, y: anchor.y)
                let health = min(1, max(0.2, organ.health))
                local.rotate(by: .radians(organ.orientation + (organ.orientation >= 0 ? 1 : -1) * (1 - health) * 0.36))
                let old = oldSizes[organ.id] ?? 1
                let current = old + (organ.size - old) * blend
                if organ.kind == .leaf {
                    let length = 9 + current * 5.5
                    let width = length * (codex ? 0.61 : 0.36) * (0.92 + Double(abs(organ.shape) % 3) * 0.08)
                    var leaf = Path()
                    leaf.move(to: .zero)
                    leaf.addCurve(to: CGPoint(x: 0, y: -length), control1: CGPoint(x: -width, y: -length * 0.15), control2: CGPoint(x: -width * (codex ? 1 : 0.55), y: -length * 0.86))
                    leaf.addCurve(to: .zero, control1: CGPoint(x: width * (codex ? 1 : 0.55), y: -length * 0.86), control2: CGPoint(x: width, y: -length * 0.15))
                    local.fill(leaf, with: .color(greens[abs(organ.colorIndex) % greens.count].opacity(0.5 + health * 0.5)))
                } else {
                    let priorMaturation = oldMaturation[organ.id] ?? 0
                    let maturity = priorMaturation + (organ.maturation - priorMaturation) * blend
                    let opening = max(0, min(1, (maturity - 0.12) / 0.48))
                    let fade = max(0, min(1, (maturity - 0.88) / 0.12))
                    let openness = (0.16 + 0.84 * opening * opening * (3 - 2 * opening)) * (1 - fade * 0.65)
                    let radius = (8 + current * 1.4) * openness
                    let petals = 5 + abs(organ.shape) % 3
                    for index in 0..<petals {
                        var petal = local
                        petal.rotate(by: .radians(Double(index) * 2 * .pi / Double(petals)))
                        let rect = CGRect(x: -radius * 0.36, y: -radius * 1.7, width: radius * 0.72, height: radius * 1.6)
                        petal.fill(Path(ellipseIn: rect), with: .color(flowers[abs(organ.colorIndex) % flowers.count].opacity(health)))
                    }
                    local.fill(Path(ellipseIn: CGRect(x: -radius * 0.3, y: -radius * 0.3, width: radius * 0.6, height: radius * 0.6)), with: .color(.init(hex: 0xC29C4E)))
                }
            }
            // The provider identity belongs to the pot, even for a newly born seedling.
            if codex {
                context.fill(Path(roundedRect: CGRect(x: 105, y: 317, width: 110, height: 70), cornerRadius: 17), with: .color(.init(hex: 0x73998F)))
                context.fill(Path(roundedRect: CGRect(x: 103, y: 310, width: 114, height: 15), cornerRadius: 5), with: .color(.init(hex: 0x8AADA1)))
                var shine = Path(); shine.move(to: CGPoint(x: 116, y: 331)); shine.addLine(to: CGPoint(x: 116, y: 367)); shine.addQuadCurve(to: CGPoint(x: 126, y: 377), control: CGPoint(x: 116, y: 377))
                context.stroke(shine, with: .color(.white.opacity(0.13)), style: StrokeStyle(lineWidth: 6, lineCap: .round))
            } else {
                var pot = Path(); pot.move(to: CGPoint(x: 103, y: 321)); pot.addLine(to: CGPoint(x: 118, y: 382)); pot.addQuadCurve(to: CGPoint(x: 202, y: 382), control: CGPoint(x: 160, y: 393)); pot.addLine(to: CGPoint(x: 217, y: 321)); pot.closeSubpath()
                context.fill(pot, with: .color(.init(hex: 0xBC7D5E)))
                context.fill(Path(roundedRect: CGRect(x: 96, y: 310, width: 128, height: 18), cornerRadius: 5), with: .color(.init(hex: 0xD49B7C)))
                var shine = Path(); shine.move(to: CGPoint(x: 112, y: 331)); shine.addLine(to: CGPoint(x: 124, y: 374))
                context.stroke(shine, with: .color(.white.opacity(0.15)), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            }
        }
        .saturation(0.5 + plant.health * 0.5)
    }
}
#endif
