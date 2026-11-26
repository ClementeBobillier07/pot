import Foundation

public enum OrganKind: String, Codable, Sendable { case stem, branch, leaf, flower }
public enum FlowerStage: String, Codable, CaseIterable, Sendable {
    case sprout, bud, partial, bloom, mature, wilted, fallen
}

/// Coordinates use a normalized canvas: (0,0) is top left, soil is (.5,.80).
public struct PlantOrgan: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var parentID: String?
    public var kind: OrganKind
    public var bornAt: Date
    public var ageHours: Double
    public var size: Double
    public var maximumSize: Double
    public var orientation: Double
    public var x: Double
    public var y: Double
    public var endX: Double
    public var endY: Double
    public var shape: Int
    public var colorIndex: Int
    public var health: Double
    public var growthRate: Double
    public var maturation: Double
    public var flowerStage: FlowerStage

    public var endpoint: (x: Double, y: Double) {
        let progress = min(1, max(0.12, maturation))
        return (x + (endX - x) * progress, y + (endY - y) * progress)
    }
}

public struct PlantDay: Codable, Equatable, Sendable {
    public var day: Int
    /// Work units observed that UTC day (see `PlantEngine.workUnits`).
    public var tokens: Int64
    /// Reference day used for this day's energy (the global constant since engine 2).
    public var reference: Double
    public var credited: Double
}

public struct PlantState: Codable, Equatable, Sendable {
    /// Engine 2 (2026-11-26): one global rhythm for everyone, wilting from day 2 without use.
    public var engineVersion = PlantEngine.version
    public var seed: UInt64
    public var provider: Provider
    public var createdAt: Date
    public var lastUpdated: Date
    public var historicalMaturity: Double = 0
    public var health: Double = 1
    public var reserve: Double = 0
    public var reference: Double = PlantEngine.referenceDailyWork
    public var lastActivity: Date?
    public var organs: [PlantOrgan] = []
    public var days: [PlantDay] = []
    public var serial: UInt64 = 0
    public var retiredOrgans: Int64 = 0
    public var nextBirth: Date
    public var nextBranch: Date
    public var nextFlower: Date
    public var creditedBeforeDay: Int
    public var lastReliableObservation: Date
    /// Energy turned into visible growth (engine 3). `nil` in plants stored by older engines.
    public var growth: Double?

    public init(seed: UInt64, provider: Provider, createdAt: Date) {
        self.seed = seed
        self.provider = provider
        self.createdAt = createdAt
        self.lastUpdated = createdAt
        self.nextBirth = createdAt.addingTimeInterval(12 * 3600)
        self.nextBranch = createdAt.addingTimeInterval(3 * 86400)
        self.nextFlower = createdAt.addingTimeInterval(7 * 86400)
        self.creditedBeforeDay = PlantEngine.day(createdAt) - 1
        self.lastReliableObservation = createdAt
        var stem = makeOrgan(kind: .stem, parent: nil, date: createdAt, x: 0.5, y: 0.80, endX: 0.5, endY: 0.64, angle: 0)
        stem.size = 10
        stem.maturation = 1
        organs.append(stem)
        organs.append(makeOrgan(kind: .leaf, parent: stem.id, date: createdAt, x: 0.5, y: 0.665, endX: 0.5, endY: 0.665, angle: -0.65))
        organs.append(makeOrgan(kind: .leaf, parent: stem.id, date: createdAt, x: 0.5, y: 0.645, endX: 0.5, endY: 0.645, angle: 0.72))
    }

    mutating func random() -> Double {
        serial &+= 1
        var value = seed &+ serial &* 0x9e3779b97f4a7c15
        value = (value ^ (value >> 30)) &* 0xbf58476d1ce4e5b9
        value = (value ^ (value >> 27)) &* 0x94d049bb133111eb
        value ^= value >> 31
        return Double(value >> 11) / 9_007_199_254_740_992
    }

    mutating func makeOrgan(kind: OrganKind, parent: String?, date: Date, x: Double, y: Double, endX: Double, endY: Double, angle: Double) -> PlantOrgan {
        let maximum = kind == .leaf ? 5 + random() * 5 : 10
        let shape = Int(random() * 3)
        let color = Int(random() * 4)
        let rate = 0.55 + random() * 0.9
        let id = "\(seed)-\(serial)-\(kind.rawValue)"
        return PlantOrgan(id: id, parentID: parent, kind: kind, bornAt: date, ageHours: 0,
                          size: 1, maximumSize: maximum, orientation: angle,
                          x: x, y: y, endX: endX, endY: endY, shape: shape, colorIndex: color,
                          health: health, growthRate: rate, maturation: 0,
                          flowerStage: .sprout)
    }
}

/// Growth model (engine 2), the same rhythm for everyone:
///
/// * Work of a day, in work units: new input + cache writes + cache reads ÷ 10 + output × 5.
///   The weights follow the usual price ratios between categories, without depending on the
///   model, so long cached contexts do not dominate and expensive models do not grow faster.
/// * Daily energy = log2(1 + work / reference), at most 3. A reference day (10 M units) gives 1;
///   a light day (1 M) gives 0.14; a very heavy day (70 M+) gives the maximum 3.
/// * Energy is banked as the day's work is observed and spent on growth; leaves, branches and
///   flowers cost energy, so light use grows slowly and heavy use grows visibly faster.
/// * Visible growth (engine 3) accumulates the day's energy scaled by vigor; at one reference
///   day per day a plant is full after 90 days (see `PlantFormBuilder`).
/// * Health (engine 3, half the owner's reference timeline): unchanged for a day without
///   use, then ≈ 0.85 at 1.5 days, 0.65 at 3.5 days, 0.40 at 7 days and 0.15 (dry, never dead)
///   at 15 days. Wilted plants don't grow. Days with use restore it in about five to six days.
public enum PlantEngine {
    public static let version = 3
    public static let maximumLeaves = 32
    public static let maximumFlowers = 6
    public static let maximumBranches = 12
    public static let maximumReserve = 4.0
    public static let maximumDailyEnergy = 3.0
    /// A typical day of agent work in work units (hypothesis between a light Codex day of ~1.7 M and
    /// a heavy Claude Code day of ~20 M measured on real logs; tune with the beta).
    public static let referenceDailyWork = 10_000_000.0
    /// Health lost per idle day, by how long the plant has been idle (days).
    public static func wiltRate(idleDays d: Double) -> Double {
        switch d {
        case ..<1: return 0
        case ..<1.5: return 0.3
        case ..<3.5: return 0.10
        case ..<7: return 0.25 / 3.5
        default: return 0.25 / 8
        }
    }
    public static let minimumHealth = 0.15
    /// Owner, 2026-11-26: recovery takes twice as long as wilting's first version (≈ 5–6 days of typical use from dry).
    public static let recoveryPerActiveDay = 0.15
    /// Maturity (energy spent on growth) needed before the first bud: ≈ 12 reference days.
    public static let flowerMaturity = 12.0
    static let flowerCost = 1.2
    private static let hour = 3600.0

    /// Work units of one call (provider- and model-independent).
    public static func workUnits(_ e: UsageEvent) -> Int64 {
        let value = Double(max(0, e.input)) + Double(max(0, e.cacheWrite)) + Double(max(0, e.cacheRead)) / 10 + Double(max(0, e.output)) * 5
        return value >= Double(Int64.max) ? Int64.max : Int64(value)
    }
    public static func dailyEnergy(work: Double) -> Double {
        min(maximumDailyEnergy, log2(1 + max(0, work) / referenceDailyWork))
    }

    public static func day(_ date: Date) -> Int { Int(floor(date.timeIntervalSince1970 / 86400)) }

    /// Supply a canonical usage snapshot for this profile, not raw line-by-line deltas.
    /// Energy is independent of prices and never credits history predating the plant.
    public static func advance(state: inout PlantState, events: [UsageEvent], now: Date, dataAvailable: Bool = true) {
        guard now > state.lastUpdated else { return }
        let start = state.lastUpdated
        let highDay = day(now)
        var seen = Set<String>()
        let eligible = events.filter {
            $0.provider == state.provider && $0.timestamp >= state.createdAt && $0.timestamp <= now &&
            day($0.timestamp) > state.creditedBeforeDay && seen.insert($0.id).inserted
        }
        let grouped = Dictionary(grouping: eligible, by: { day($0.timestamp) })
        // A bounded 45-day journal cannot re-credit old imports after compaction.
        let oldest = max(day(state.createdAt), highDay - 44)
        state.creditedBeforeDay = max(state.creditedBeforeDay, oldest - 1)
        var ledger = Dictionary(uniqueKeysWithValues: state.days.map { ($0.day, $0) })
        for eventDay in grouped.keys.sorted() where eventDay >= oldest {
            let total = grouped[eventDay]!.reduce(Int64(0)) { partial, event in
                let work = workUnits(event)
                return partial > Int64.max - work ? Int64.max : partial + work
            }
            if var prior = ledger[eventDay] {
                prior.tokens = max(prior.tokens, total)
                ledger[eventDay] = prior
            } else {
                ledger[eventDay] = PlantDay(day: eventDay, tokens: total, reference: referenceDailyWork, credited: 0)
            }
        }
        // Simulate no more than 45 days in hourly ticks. Earlier absences age analytically.
        // Energy from distant history is intentionally never banked on reopening.
        var cursor = max(start, now.addingTimeInterval(-45 * 86400))
        if cursor > start {
            age(state: &state, hours: cursor.timeIntervalSince(start) / hour, now: cursor, dataAvailable: dataAvailable)
            state.reserve = 0
        }
        let sortedEvents = eligible.sorted { $0.timestamp < $1.timestamp }
        var activityIndex = 0
        var observedTokens: [Int: Int64] = [:]
        // Seed only past observations; never release a late-day event's energy
        // before that event actually happened during offline catch-up.
        while activityIndex < sortedEvents.count && sortedEvents[activityIndex].timestamp <= cursor {
            let event = sortedEvents[activityIndex]
            let eventDay = day(event.timestamp)
            let previous = observedTokens[eventDay, default: 0]
            let positive = workUnits(event)
            observedTokens[eventDay] = previous > Int64.max - positive ? Int64.max : previous + positive
            if event.totalTokens > 0 { state.lastActivity = max(state.lastActivity ?? state.createdAt, event.timestamp) }
            activityIndex += 1
        }
        while cursor < now {
            let next = min(now, cursor.addingTimeInterval(hour))
            let currentDay = day(cursor)
            while activityIndex < sortedEvents.count && sortedEvents[activityIndex].timestamp <= next {
                let event = sortedEvents[activityIndex]
                let eventDay = day(event.timestamp)
                let old = observedTokens[eventDay, default: 0]
                let work = workUnits(event)
                observedTokens[eventDay] = old > Int64.max - work ? Int64.max : old + work
                if event.totalTokens > 0 { state.lastActivity = max(state.lastActivity ?? state.createdAt, event.timestamp) }
                activityIndex += 1
            }
            // Grants are released only after their day has been observed. This
            // avoids filling reserve with an entire year of logs at once.
            var todayEnergy = 0.0
            if var record = ledger[currentDay] {
                // UTC days anchor the energy cap and the deduplication journal.
                let entitlement = dailyEnergy(work: Double(observedTokens[currentDay, default: 0]))
                let grant = max(0, entitlement - record.credited)
                state.reserve = min(maximumReserve, state.reserve + grant)
                // Visible growth: wilted plants can't turn energy into growth.
                state.growth = (state.growth ?? 0) + grant * min(1, max(0, (state.health - 0.35) / 0.45))
                record.credited += grant
                ledger[currentDay] = record
                todayEnergy = record.credited
                state.reference = referenceDailyWork
            }
            let elapsedHours = next.timeIntervalSince(cursor) / hour
            tick(state: &state, hours: elapsedHours, now: next, dataAvailable: dataAvailable, todayEnergy: todayEnergy)
            cursor = next
        }
        state.days = ledger.values.filter { $0.day >= oldest }.sorted { $0.day < $1.day }
        state.lastUpdated = now
        if dataAvailable { state.lastReliableObservation = now }
    }

    /// Ages organs and lowers health after the first idle day. Without reliable data (missing or
    /// unreadable logs) health is frozen: a reading problem is not a day without use.
    private static func age(state: inout PlantState, hours: Double, now: Date, dataAvailable: Bool) {
        if dataAvailable {
            let lastUse = max(state.lastActivity ?? state.createdAt, state.createdAt)
            let idleDays = now.timeIntervalSince(lastUse) / 86400
            if idleDays > 1 {
                let hoursIdle = min(hours, (idleDays - 1) * 24)
                state.health = max(minimumHealth, state.health - wiltRate(idleDays: idleDays) * hoursIdle / 24)
            }
        }
        for i in state.organs.indices {
            state.organs[i].ageHours += hours
            state.organs[i].health = state.health
        }
    }

    private static func tick(state: inout PlantState, hours: Double, now: Date, dataAvailable: Bool, todayEnergy: Double) {
        age(state: &state, hours: hours, now: now, dataAvailable: dataAvailable)
        // Recovery while in use (activity within the last day), faster on fuller days.
        // "In use" = activity within the last day, the moment wilting would begin.
        if dataAvailable, let activity = state.lastActivity, now.timeIntervalSince(activity) < 24 * hour {
            let effort = min(1.4, max(0.35, todayEnergy + 0.3))
            state.health = min(1, state.health + recoveryPerActiveDay * effort * hours / 24)
            for i in state.organs.indices { state.organs[i].health = state.health }
        }
        // A wilted plant keeps its energy but cannot turn it into growth until it recovers.
        let vigor = min(1, max(0, (state.health - 0.35) / 0.45))
        // Once old enough to flower, part of the energy is saved for a bud instead of new leaves.
        let saving = state.historicalMaturity >= flowerMaturity ? flowerCost : 0
        // Energy only flows into organs that are still expanding (or opening buds); otherwise it
        // stays banked for new leaves, branches and flowers, so even light use keeps adding leaves.
        let expanding = state.organs.indices.filter { state.organs[$0].maturation < 1 && state.organs[$0].kind != .flower }
        let opening = state.organs.contains { $0.kind == .flower && $0.maturation < 0.72 }
        let spent = expanding.isEmpty && !opening ? 0 : min(max(0, state.reserve - saving), hours * 0.2 * vigor)
        state.reserve -= spent
        state.historicalMaturity += spent
        if spent > 0, !expanding.isEmpty {
            // Stagger allocation by age; the two initial leaves do not move in lockstep.
            for (offset, i) in expanding.enumerated() {
                let priority = offset % 2 == Int(state.historicalMaturity * 10) % 2 ? 1.5 : 0.55
                state.organs[i].maturation = min(1, state.organs[i].maturation + spent * state.organs[i].growthRate * priority / Double(max(1, expanding.count)) * 1.2)
            }
        }
        for i in state.organs.indices {
            let organ = state.organs[i]
            if organ.kind == .flower {
                // Each flower carries its own biological progress. Opening needs energy and health;
                // open flowers age and fall even without energy.
                if organ.maturation < 0.72, spent > 0 {
                    state.organs[i].maturation = min(0.72, organ.maturation + hours * organ.growthRate / 120 * min(1, spent / max(0.0001, hours * 0.05)))
                } else if organ.maturation >= 0.72 {
                    state.organs[i].maturation = min(1, organ.maturation + hours / 240)
                }
                state.organs[i].flowerStage = flowerStage(progress: state.organs[i].maturation, ageHours: organ.ageHours)
            }
            let progress = min(1, max(0, state.organs[i].maturation))
            let smooth = progress * progress * (3 - 2 * progress)
            state.organs[i].size = 1 + (organ.maximumSize - 1) * smooth
        }
        retire(state: &state)
        // New organs cost energy and need a healthy plant.
        // Leaves and branches never eat into the energy saved for the next bud.
        guard state.health >= 0.6 else { return }
        if now >= state.nextBranch, state.historicalMaturity >= 3, state.reserve - saving >= 0.8 {
            addBranch(state: &state, now: now, cost: 0.8)
            state.nextBranch = now.addingTimeInterval((2 + state.random() * 2) * 86400)
        }
        if now >= state.nextBirth, state.reserve - saving >= 0.35 {
            addLeaf(state: &state, now: now, cost: 0.35)
            state.nextBirth = now.addingTimeInterval((6 + state.random() * 8) * hour)
        }
        if now >= state.nextFlower, state.historicalMaturity >= flowerMaturity, state.health >= 0.75, state.reserve >= flowerCost {
            addFlower(state: &state, now: now, cost: flowerCost)
            state.nextFlower = now.addingTimeInterval((3 + state.random() * 3) * 86400)
        }
    }

    public static func flowerStage(progress: Double, ageHours: Double) -> FlowerStage {
        if progress >= 1 { return .fallen }
        if progress >= 0.92 { return .wilted }
        if progress >= 0.80 { return .mature }
        if progress >= 0.60 { return .bloom }
        if progress >= 0.35 { return .partial }
        if progress >= 0.10 { return .bud }
        return .sprout
    }

    private static func retire(state: inout PlantState) {
        let leaves = state.organs.filter { $0.kind == .leaf }.sorted { $0.bornAt < $1.bornAt }
        // Old leaves fall only while the plant keeps a full crown; ageing alone never strips a plant bare.
        let protected = Set(leaves.suffix(12).map(\.id))
        let oldCount = state.organs.count
        state.organs.removeAll {
            ($0.kind == .leaf && $0.ageHours > 24 * 35 && !protected.contains($0.id)) ||
            ($0.kind == .flower && ($0.flowerStage == .fallen || $0.ageHours > 24 * 45))
        }
        state.retiredOrgans += Int64(oldCount - state.organs.count)
    }

    private static func attachment(state: inout PlantState, allowing: (PlantOrgan) -> Bool = { _ in true }) -> PlantOrgan? {
        let branches = state.organs.filter { ($0.kind == .stem || $0.kind == .branch) && $0.maturation >= 0.9 && allowing($0) }
        guard !branches.isEmpty else { return nil }
        return branches[min(branches.count - 1, Int(state.random() * Double(branches.count)))]
    }

    private static func addBranch(state: inout PlantState, now: Date, cost: Double) {
        let segments = state.organs.filter { $0.kind == .stem || $0.kind == .branch }
        if segments.count >= maximumBranches {
            // Replace only an unused terminal branch, keeping the graph connected.
            let parents = Set(state.organs.compactMap(\.parentID))
            if let old = segments.first(where: { $0.kind == .branch && !parents.contains($0.id) }) {
                state.organs.removeAll { $0.id == old.id }
                state.retiredOrgans += 1
            } else { return }
        }
        let stems = state.organs.filter { $0.kind == .stem }.sorted { $0.endY > $1.endY }
        guard let top = stems.last else { return }
        let canExtend = top.endY > 0.25 && stems.count < 4 && top.maturation >= 0.9
        // Side branches attach to the main stem or first-order branches only, so chains cannot
        // creep toward one edge, and each grows toward the lighter side to keep the plant balanced.
        let stemIDs = Set(stems.map(\.id))
        let parent = canExtend ? top : (attachment(state: &state, allowing: { $0.kind == .stem || stemIDs.contains($0.parentID ?? "") }) ?? top)
        let point = parent.endpoint
        let weight = state.organs.filter { $0.kind != .stem }.reduce(0.0) { $0 + ($1.endX - 0.5) * ($1.kind == .branch ? 3 : 1) }
        let direction = abs(weight) < 0.05 ? (state.random() > 0.5 ? 1.0 : -1.0) : (weight > 0 ? -1.0 : 1.0)
        let dx = canExtend ? (state.random() - 0.5) * 0.045 : direction * (0.10 + state.random() * 0.10)
        let dy = canExtend ? 0.12 : 0.05 + state.random() * 0.08
        let kind: OrganKind = canExtend ? .stem : .branch
        let organ = state.makeOrgan(kind: kind, parent: parent.id, date: now, x: point.x, y: point.y,
                                    endX: min(0.82, max(0.18, point.x + dx)), endY: max(0.16, point.y - dy), angle: 0)
        state.organs.append(organ)
        state.reserve -= cost
        state.historicalMaturity += cost
    }

    private static func addLeaf(state: inout PlantState, now: Date, cost: Double) {
        guard let parent = attachment(state: &state) else { return }
        let leaves = state.organs.filter { $0.kind == .leaf }
        if leaves.count >= maximumLeaves, let oldest = leaves.min(by: { $0.bornAt < $1.bornAt }) {
            state.organs.removeAll { $0.id == oldest.id }
            state.retiredOrgans += 1
        }
        let fraction = 0.35 + state.random() * 0.65
        let point = (parent.x + (parent.endX - parent.x) * fraction, parent.y + (parent.endY - parent.y) * fraction)
        let direction = leaves.count % 2 == 0 ? -1.0 : 1.0
        let angle = direction * (0.55 + state.random() * 0.45)
        let leaf = state.makeOrgan(kind: .leaf, parent: parent.id, date: now, x: point.0, y: point.1, endX: point.0, endY: point.1, angle: angle)
        state.organs.append(leaf)
        state.reserve -= cost
        state.historicalMaturity += cost
    }

    private static func addFlower(state: inout PlantState, now: Date, cost: Double) {
        guard state.organs.filter({ $0.kind == .flower }).count < maximumFlowers,
              let parent = attachment(state: &state) else { return }
        let point = parent.endpoint
        let angle = state.random() * 0.3 - 0.15
        let flower = state.makeOrgan(kind: .flower, parent: parent.id, date: now, x: point.x, y: point.y, endX: point.x, endY: point.y, angle: angle)
        state.organs.append(flower)
        state.reserve -= cost
        state.historicalMaturity += cost
    }
}
