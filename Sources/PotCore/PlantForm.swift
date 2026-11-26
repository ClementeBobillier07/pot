import Foundation

/// Botanical variant of a plant, fixed at birth by its seed (owner spec, 2026-11-26):
/// variation 01 40 %, variation 02 35 %, variation 03 24 %, copihue 1 %.
public enum PlantSpecies: String, CaseIterable, Codable, Sendable {
    case classic, blossom, surprise, copihue

    public static func of(seed: UInt64) -> PlantSpecies {
        // SplitMix finalizer so consecutive seeds still spread evenly.
        var z = seed &+ 0x9e3779b97f4a7c15
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        z ^= z >> 31
        switch z % 100 {
        case 0..<40: return .classic
        case 40..<75: return .blossom
        case 75..<99: return .surprise
        default: return .copihue
        }
    }

    public func title(for provider: Provider) -> String {
        switch self {
        case .classic: return "Variation 01"
        case .blossom: return "Variation 02"
        case .surprise: return "Variation 03"
        case .copihue: return provider == .codex ? "White copihue" : "Red copihue"
        }
    }
}

// MARK: - Drawable form

/// Everything the renderer needs, in a 320×400 canvas (pot base near y 384, soil at y ≈ 332).
/// Built deterministically from the plant's seed, growth and health, so the same plant always
/// looks the same and grows continuously instead of jumping between stored organ graphs.
public struct PlantForm: Sendable {
    public struct Point: Sendable, Equatable { public var x, y: Double }
    public enum StemKind: Sendable { case stem, branch, vine, stake }
    public struct Stem: Sendable { public var kind: StemKind; public var points: [Point]; public var width: Double }
    public enum LeafShape: Sendable { case oval, round, broad, lance, longLance, slender, heart, cotyledon }
    public struct Leaf: Sendable {
        public var base: Point
        /// Radians from vertical, clockwise (0 points up).
        public var angle: Double
        public var length: Double
        public var width: Double
        public var shape: LeafShape
        public var tone: Int
        /// 0 green … 1 brown and curled.
        public var dry: Double
        /// Stable identity, so a leaf keeps its jitter and its fate (which leaves fall first) as the plant grows.
        public var key: UInt64 = 0
        public var tip: Point { Point(x: base.x + sin(angle) * length, y: base.y - cos(angle) * length) }
    }
    public enum FlowerKind: Sendable { case round5, star5, rose, daisy, camellia, smallStar, bell, bud, driedPod }
    public struct Flower: Sendable {
        public var center: Point
        public var size: Double
        public var angle: Double
        public var kind: FlowerKind
        public var color: Int
        /// 0 closed bud … 1 fully open.
        public var openness: Double
        /// Petal colour faded toward dry.
        public var fade: Double
        public var hanging: Bool
    }

    public var species: PlantSpecies
    public var provider: Provider
    /// Growth progress 0 (seed) … 1 (full, ≈ 90 reference days).
    public var growth: Double
    /// 0 healthy … 1 fully wilted.
    public var wilt: Double
    public var recovering: Bool
    public var stems: [Stem] = []
    public var leaves: [Leaf] = []
    public var flowers: [Flower] = []
    public var fallenLeaves: Int = 0

    /// Visible extent of plant and pot in canvas units.
    public var bounds: (minX: Double, minY: Double, maxX: Double, maxY: Double) {
        var minX = 104.0, maxX = 216.0, minY = 326.0, maxY = 388.0
        func add(_ p: Point, _ r: Double) { minX = min(minX, p.x - r); maxX = max(maxX, p.x + r); minY = min(minY, p.y - r); maxY = max(maxY, p.y + r) }
        for s in stems { for p in s.points { add(p, s.width) } }
        for l in leaves { add(l.base, 2); add(l.tip, l.width * 0.5) }
        for f in flowers { add(f.center, f.size) }
        return (minX, minY, maxX, maxY)
    }
}

/// Deterministic generator independent of the engine's organ RNG.
private struct FormRandom {
    var state: UInt64
    mutating func next() -> Double {
        state &+= 0x9e3779b97f4a7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        z ^= z >> 31
        return Double(z >> 11) / 9_007_199_254_740_992
    }
    mutating func range(_ a: Double, _ b: Double) -> Double { a + (b - a) * next() }
}

private func clamp(_ v: Double, _ a: Double = 0, _ b: Double = 1) -> Double { min(b, max(a, v)) }

/// Stable pseudo-random value in [0, 1) for (seed, a, b, c). Per-element streams keep every leaf and
/// flower in place from one day to the next, however many other elements appear meanwhile.
private func unit(_ seed: UInt64, _ a: Int, _ b: Int = 0, _ c: Int = 0) -> Double {
    var r = FormRandom(state: seed ^ (UInt64(truncatingIfNeeded: a) &* 0x100000001B3) ^ (UInt64(truncatingIfNeeded: b) &* 0xC2B2AE3D27D4EB4F) ^ (UInt64(truncatingIfNeeded: c) &* 0x165667B19E3779F9))
    return r.next()
}
private func key(_ a: Int, _ b: Int, _ c: Int) -> UInt64 { UInt64(truncatingIfNeeded: a &* 1_000_003 &+ b &* 1_009 &+ c) }

public enum PlantFormBuilder {
    static let soilY = 332.0
    static let stemX = 160.0

    private struct Style {
        var leaf: PlantForm.LeafShape
        var leafLength: Double
        var leafWidth: Double
        var leafAngle: Double          // from the stem's heading
        var pairs: Bool                // opposite leaves (bushy) vs alternate
        var branchAngle: Double        // from vertical
        var branchCount: Int
        var branchLength: Double
        var maxHeight: Double
        var flowers: [(kind: PlantForm.FlowerKind, size: Double, colors: [Int])]
        var flowerCount: Int
    }

    private static func style(_ species: PlantSpecies, _ provider: Provider) -> Style {
        switch (provider, species) {
        case (.codex, .classic):
            return Style(leaf: .oval, leafLength: 29.0, leafWidth: 0.82, leafAngle: 1.0, pairs: true, branchAngle: 0.95, branchCount: 10, branchLength: 92, maxHeight: 262,
                         flowers: [(.round5, 16.0, [0, 1, 2, 3])], flowerCount: 13)
        case (.codex, .blossom):
            return Style(leaf: .round, leafLength: 31.0, leafWidth: 0.9, leafAngle: 1.05, pairs: true, branchAngle: 1.0, branchCount: 10, branchLength: 98, maxHeight: 258,
                         flowers: [(.rose, 20.2, [0]), (.daisy, 18.6, [1]), (.star5, 18.6, [2]), (.round5, 11.0, [3])], flowerCount: 13)
        case (.codex, .surprise):
            return Style(leaf: .broad, leafLength: 38.0, leafWidth: 0.92, leafAngle: 1.1, pairs: false, branchAngle: 0.9, branchCount: 8, branchLength: 100, maxHeight: 268,
                         flowers: [(.camellia, 22.8, [0, 1]), (.round5, 18.6, [2, 3]), (.smallStar, 9.2, [4])], flowerCount: 12)
        case (.claude, .classic):
            return Style(leaf: .lance, leafLength: 43.5, leafWidth: 0.3, leafAngle: 0.62, pairs: false, branchAngle: 0.5, branchCount: 9, branchLength: 92, maxHeight: 292,
                         flowers: [(.star5, 18.6, [0, 1, 2, 3])], flowerCount: 11)
        case (.claude, .blossom):
            return Style(leaf: .longLance, leafLength: 49.3, leafWidth: 0.26, leafAngle: 0.7, pairs: false, branchAngle: 0.55, branchCount: 9, branchLength: 98, maxHeight: 290,
                         flowers: [(.daisy, 20.2, [0]), (.star5, 18.6, [1]), (.bell, 11.9, [2])], flowerCount: 11)
        case (.claude, .surprise):
            return Style(leaf: .slender, leafLength: 42.0, leafWidth: 0.32, leafAngle: 0.68, pairs: false, branchAngle: 0.6, branchCount: 9, branchLength: 94, maxHeight: 286,
                         flowers: [(.daisy, 20.2, [0, 1, 2]), (.round5, 11.9, [3])], flowerCount: 11)
        case (_, .copihue):
            return Style(leaf: .heart, leafLength: 39.1, leafWidth: 0.5, leafAngle: 0.95, pairs: false, branchAngle: 0, branchCount: 0, branchLength: 0, maxHeight: 290,
                         flowers: [(.bell, 25.2, [0])], flowerCount: 4)
        }
    }

    /// Reference days of typical use (energy 1/day) until the plant is full.
    public static let daysToFull = 90.0

    public static func growthProgress(_ plant: PlantState) -> Double {
        clamp((plant.growth ?? 0) / daysToFull)
    }

    public static func build(_ plant: PlantState) -> PlantForm {
        let species = PlantSpecies.of(seed: plant.seed)
        let g = growthProgress(plant)
        let health = clamp(plant.health)
        let wilt = clamp((1 - health) / 0.85)
        // Recovering: in use again (activity within a day) while still below full health.
        let recovering = health < 0.97 && (plant.lastActivity.map { plant.lastUpdated.timeIntervalSince($0) < 86400 } ?? false)
        var form = PlantForm(species: species, provider: plant.provider, growth: g, wilt: wilt, recovering: recovering)
        var rng = FormRandom(state: plant.seed ^ 0x5EED_F0E7)
        let style = style(species, plant.provider)
        if species == .copihue {
            buildCopihue(&form, style: style, g: g, seed: plant.seed)
        } else {
            buildBush(&form, style: style, g: g, rng: &rng, seed: plant.seed, day: Int(plant.lastUpdated.timeIntervalSince1970 / 86400))
        }
        applyWilting(&form, health: health, seed: plant.seed)
        return form
    }

    // MARK: Bushy variants

    private static func curve(_ a: PlantForm.Point, _ c: PlantForm.Point, _ b: PlantForm.Point, steps: Int = 10) -> [PlantForm.Point] {
        (0...steps).map { i in
            let t = Double(i) / Double(steps), u = 1 - t
            return PlantForm.Point(x: u * u * a.x + 2 * u * t * c.x + t * t * b.x, y: u * u * a.y + 2 * u * t * c.y + t * t * b.y)
        }
    }
    private static func along(_ points: [PlantForm.Point], _ t: Double) -> (PlantForm.Point, Double) {
        guard points.count > 1 else { return (points.first ?? PlantForm.Point(x: stemX, y: soilY), 0) }
        let f = clamp(t) * Double(points.count - 1)
        let i = min(points.count - 2, Int(f)), k = f - Double(i)
        let a = points[i], b = points[i + 1]
        let heading = atan2(b.x - a.x, -(b.y - a.y))
        return (PlantForm.Point(x: a.x + (b.x - a.x) * k, y: a.y + (b.y - a.y) * k), heading)
    }
    private static func length(_ points: [PlantForm.Point]) -> Double {
        zip(points, points.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
    }

    private static func buildBush(_ form: inout PlantForm, style: Style, g: Double, rng: inout FormRandom, seed: UInt64, day: Int) {
        let height = 12 + (style.maxHeight - 12) * pow(g, 0.85)
        let lean = rng.range(-10, 10) * g
        let base = PlantForm.Point(x: stemX, y: soilY)
        let top = PlantForm.Point(x: stemX + lean, y: soilY - height)
        let bow = rng.range(-12, 12) * g
        let stem = curve(base, PlantForm.Point(x: stemX + bow, y: soilY - height * 0.55), top, steps: 14)
        form.stems.append(.init(kind: .stem, points: stem, width: 2.2 + 2.4 * g))
        let leafScale = 0.68 + 0.32 * clamp(g / 0.4)

        // Seedling: just two seed leaves on a short stem.
        if g < 0.05 {
            let size = 5 + 90 * g
            for side in [-1.0, 1.0] {
                form.leaves.append(.init(base: top, angle: side * 0.95, length: size, width: size * 0.8, shape: .cotyledon, tone: side < 0 ? 0 : 3, dry: 0))
            }
            return
        }

        // Branches appear bottom-up as the plant grows; lower ones grow longest.
        var tips: [(PlantForm.Point, Double)] = []
        var branchPoints: [[PlantForm.Point]] = []
        var firstSide: Double = rng.next() < 0.5 ? -1 : 1
        for i in 0..<style.branchCount {
            let birth = 0.08 + Double(i) * 0.62 / Double(style.branchCount)
            let progress = clamp((g - birth) / 0.3)
            let jitter = (rng.range(-0.12, 0.12), rng.range(0.85, 1.1), rng.next())
            guard progress > 0 else { continue }
            let attachT = 0.2 + 0.62 * Double(i) / Double(max(1, style.branchCount - 1))
            let (attach, _) = along(stem, attachT)
            let side = firstSide
            firstSide = -firstSide
            let reach = style.branchLength * jitter.1 * (1 - 0.4 * attachT) * pow(progress, 0.8) * (0.6 + 0.4 * g)
            let angle = side * (style.branchAngle + jitter.0)
            let end = PlantForm.Point(x: attach.x + sin(angle) * reach, y: attach.y - cos(angle) * reach)
            // Rise first, then lean outward, tips turning up again.
            let control = PlantForm.Point(x: attach.x + sin(angle * 0.55) * reach * 0.55, y: attach.y - cos(angle * 0.55) * reach * 0.62)
            let points = curve(attach, control, end, steps: 8)
            form.stems.append(.init(kind: .branch, points: points, width: 1.4 + 1.6 * g))
            branchPoints.append(points)
            tips.append((end, atan2(end.x - control.x, -(end.y - control.y))))
            _ = jitter.2
        }

        // Leaves along the main stem and every branch; young leaves near the tips are smaller.
        func dress(_ points: [PlantForm.Point], index: Int, spacing: Double, sizeBoost: Double) {
            let total = length(points)
            guard total > 6 else { return }
            var d = 8.0, k = 0
            while d < total - 2 {
                let (p, heading) = along(points, d / total)
                let youth = clamp((total - d) / 46, 0, 1)
                let size = style.leafLength * leafScale * sizeBoost * (0.62 + 0.38 * youth) * (0.85 + 0.27 * unit(seed, index, k, 1))
                let sides: [Double] = style.pairs ? [-1, 1] : [k % 2 == 0 ? -1 : 1]
                for (n, side) in sides.enumerated() {
                    let angle = heading + side * (style.leafAngle + (unit(seed, index, k, 2 + n) - 0.5) * 0.36)
                    form.leaves.append(.init(base: p, angle: angle, length: size, width: size * style.leafWidth,
                                             shape: style.leaf, tone: Int(unit(seed, index, k, 4 + n) * 4), dry: 0, key: key(index, k, n)))
                }
                d += spacing * (0.85 + 0.3 * unit(seed, index, k, 6))
                k += 1
            }
            // Terminal leaf pair.
            let (tip, heading) = along(points, 1)
            let tipSize = style.leafLength * leafScale * 0.55 * sizeBoost
            for (n, side) in [-1.0, 1.0].enumerated() {
                form.leaves.append(.init(base: tip, angle: heading + side * 0.45, length: tipSize, width: tipSize * style.leafWidth,
                                         shape: style.leaf, tone: 3, dry: 0, key: key(index, 999, n)))
            }
        }
        dress(stem, index: 0, spacing: style.pairs ? 20 : 15, sizeBoost: 1)
        for (i, points) in branchPoints.enumerated() { dress(points, index: i + 1, spacing: style.pairs ? 18 : 14, sizeBoost: 0.95) }

        // Flowers: buds from ~day 30, first blooms ~day 45, a full crown by day 90.
        // Anchor slots exist from the start (branch tips, crown, mid-branches) and keep their order.
        let slots = style.branchCount + 1 + style.branchCount + 2
        var slotOrder = Array(0..<slots)
        var flowerRng = FormRandom(state: seed ^ 0xF10E_5EED)
        for i in slotOrder.indices.reversed() { slotOrder.swapAt(i, Int(flowerRng.next() * Double(i + 1))) }
        // Map slots onto the anchors that exist today: tips first, then crown, mid-branches, upper stem.
        func anchor(_ slot: Int) -> (PlantForm.Point, Double)? {
            let b = branchPoints.count
            if slot < style.branchCount { return slot < b ? tips[slot] : nil }
            if slot == style.branchCount { return (top, 0) }
            let mid = slot - style.branchCount - 1
            if mid < style.branchCount { return mid < b ? along(branchPoints[mid], 0.6) : nil }
            return along(stem, [0.72, 0.85][min(1, mid - style.branchCount)])
        }
        let order = slotOrder.compactMap { anchor($0) != nil ? $0 : nil }
        for j in 0..<min(style.flowerCount, order.count) {
            let birth = 0.3 + Double(j) * 0.052
            guard g > birth else { continue }
            let pick = style.flowers[j % style.flowers.count]
            let colour = pick.colors[(j / style.flowers.count) % pick.colors.count]
            var openness = clamp((g - birth - 0.05) / 0.1)
            // Renewal once full: each flower closes for a few days in a staggered 14-day cycle.
            if g >= 1, (day + j * 5) % 14 >= 11 { openness = min(openness, 0.25) }
            let (p, heading) = anchor(order[j])!
            let size = pick.size * (0.9 + 0.22 * unit(seed, 500, j)) * (0.8 + 0.2 * g)
            form.flowers.append(.init(center: p, size: size, angle: heading * 0.4 + (unit(seed, 501, j) - 0.5) * 0.6,
                                      kind: openness < 0.3 ? .bud : pick.kind, color: colour,
                                      openness: openness, fade: 0, hanging: pick.kind == .bell))
        }
    }

    // MARK: Copihue — first the vine, then the bells

    private static func buildCopihue(_ form: inout PlantForm, style: Style, g: Double, seed: UInt64) {
        let stakeX = 168.0
        form.stems.append(.init(kind: .stake, points: [PlantForm.Point(x: stakeX, y: soilY + 4), PlantForm.Point(x: stakeX, y: 40)], width: 4.5))
        // Days 1–14: a small sprout at the foot of the stake.
        let sprout = clamp(g / 0.15)
        let vineHeight = (style.maxHeight - 10) * pow(clamp((g - 0.13) / 0.77), 0.9)
        if vineHeight < 14 {
            let h = 4 + 14 * sprout
            let base = PlantForm.Point(x: stakeX - 8, y: soilY)
            let top = PlantForm.Point(x: stakeX - 8, y: soilY - h)
            form.stems.append(.init(kind: .vine, points: [base, top], width: 1.6))
            let size = 4 + 9 * sprout
            for side in [-1.0, 1.0] { form.leaves.append(.init(base: top, angle: side * 0.9, length: size, width: size * 0.7, shape: .cotyledon, tone: 1, dry: 0)) }
            return
        }
        // The vine twines around the stake.
        var vine: [PlantForm.Point] = []
        var y = 0.0
        while y <= vineHeight {
            vine.append(PlantForm.Point(x: stakeX + 11 * sin(y / 40 * .pi + 0.6), y: soilY - y))
            y += 5
        }
        form.stems.append(.init(kind: .vine, points: vine, width: 2.2))
        let total = length(vine)
        var d = 18.0, k = 0
        while d < total - 4 {
            let (p, _) = along(vine, d / total)
            let side: Double = k % 2 == 0 ? -1 : 1
            let youth = clamp((total - d) / 40)
            let size = style.leafLength * (0.55 + 0.45 * youth) * (0.9 + 0.2 * unit(seed, 0, k, 1))
            form.leaves.append(.init(base: p, angle: side * (style.leafAngle + (unit(seed, 0, k, 2) - 0.5) * 0.3), length: size, width: size * style.leafWidth,
                                     shape: .heart, tone: Int(unit(seed, 0, k, 3) * 4), dry: 0, key: key(0, k, 0)))
            d += 23 * (0.9 + 0.2 * unit(seed, 0, k, 4))
            k += 1
        }
        // Up to four bells hanging beside the stake; buds first, slow to open.
        let heights = [0.3, 0.52, 0.7, 0.86]
        for (j, h) in heights.enumerated() {
            let birth = 0.32 + Double(j) * 0.13
            guard g > birth, h * (style.maxHeight - 10) < vineHeight + 10 else { continue }
            let (p, _) = along(vine, h * (style.maxHeight - 10) / max(1, vineHeight))
            let side: Double = j % 2 == 0 ? -1 : 1
            let openness = clamp((g - birth - 0.12) / 0.15)
            // A short arching pedicel from the vine; the bell hangs straight down from its end.
            let center = PlantForm.Point(x: p.x + side * 22, y: p.y + 2)
            form.stems.append(.init(kind: .vine, points: [p, PlantForm.Point(x: p.x + side * 14, y: p.y - 9), center], width: 1.6))
            form.flowers.append(.init(center: center, size: style.flowers[0].size * 0.95 * (openness < 0.3 ? 0.7 : 1),
                                      angle: side * 0.1, kind: openness < 0.3 ? .bud : .bell, color: 0, openness: openness, fade: 0, hanging: true))
        }
    }

    // MARK: Wilting and recovery

    private static func applyWilting(_ form: inout PlantForm, health: Double, seed: UInt64) {
        let w = form.wilt
        guard w > 0.001 else { return }
        if form.recovering {
            // Coming back: fresh green leaves return first, a few dry remnants remain.
            var kept: [PlantForm.Leaf] = []
            for var leaf in form.leaves {
                let h = unit(seed, 900, Int(truncatingIfNeeded: leaf.key))
                if h < health * 1.05 { leaf.angle += (leaf.angle >= 0 ? 1 : -1) * w * 0.25; kept.append(leaf) }
                else if h < health * 1.05 + 0.12 { leaf.dry = 0.85; leaf.length *= 0.7; kept.append(leaf) }
            }
            form.leaves = kept
            form.flowers = form.flowers.compactMap { flower in
                guard health > 0.72 else { return nil }
                var f = flower; f.openness = min(f.openness, (health - 0.72) / 0.28); f.kind = f.openness < 0.3 ? .bud : f.kind; return f
            }
            return
        }
        var kept: [PlantForm.Leaf] = []
        var fallen = 0
        for var leaf in form.leaves {
            let h = unit(seed, 900, Int(truncatingIfNeeded: leaf.key))
            // From ~a week away leaves start to fall; by two weeks most are on the ground.
            if h < (w - 0.55) / 0.45 * 0.8 { fallen += 1; continue }
            leaf.dry = clamp((w - 0.22 + (h - 0.5) * 0.25) / 0.62)
            let side: Double = leaf.angle >= 0 ? 1 : -1
            leaf.angle += side * w * (0.85 + 0.35 * h)
            leaf.length *= 1 - 0.28 * leaf.dry
            leaf.width *= 1 - 0.4 * leaf.dry
            kept.append(leaf)
        }
        form.leaves = kept
        form.fallenLeaves = min(9, fallen / 3 + (fallen > 0 ? 1 : 0))
        // Stems and branches bow; flowers droop, fade, then dry into hanging pods.
        for i in form.stems.indices where form.stems[i].kind == .branch {
            let pts = form.stems[i].points
            guard let start = pts.first else { continue }
            form.stems[i].points = pts.enumerated().map { k, p in
                let t = Double(k) / Double(max(1, pts.count - 1))
                return PlantForm.Point(x: p.x, y: p.y + (p.y < start.y ? (start.y - p.y) : 0) * w * 0.35 * t)
            }
        }
        form.flowers = form.flowers.enumerated().compactMap { j, flower in
            var f = flower
            if w > 0.55 {
                if unit(seed, 901, j) < (w - 0.55) * 1.2 { return nil }
                f.kind = .driedPod; f.hanging = true; f.size *= 0.6; f.fade = 1
            } else if w > 0.18 {
                f.hanging = true
                f.openness *= 1 - (w - 0.18) * 1.6
                f.fade = (w - 0.18) / 0.37
                if f.openness < 0.3, f.kind != .bell { f.kind = .bud }
            }
            return f
        }
    }
}
