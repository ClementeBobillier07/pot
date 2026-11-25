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
    public var tokens: Int64
    public var reference: Double
    public var credited: Double
}

public struct PlantState: Codable, Equatable, Sendable {
    public var engineVersion = 1
    public var seed: UInt64
    public var provider: Provider
    public var createdAt: Date
    public var lastUpdated: Date
    public var historicalMaturity: Double = 0
    public var health: Double = 1
    public var reserve: Double = 0
    public var reference: Double = 100_000
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
    /// Set while the person has paused the garden (vacation). Biology and deterioration are frozen.
    public var pausedAt: Date?

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

public enum PlantEngine {
    public static let maximumLeaves = 32
    public static let maximumFlowers = 6
    public static let maximumBranches = 12
    public static let maximumReserve = 3.0
    public static let maximumDailyEnergy = 1.0
    private static let hour = 3600.0

    public static func day(_ date: Date) -> Int { Int(floor(date.timeIntervalSince1970 / 86400)) }

    /// Supply a canonical usage snapshot for this profile, not raw line-by-line deltas.
    /// Energy is independent of prices and never credits history predating the plant.
    /// "Pause the garden": freezes growth, ageing and deterioration until resumed. Usage that
    /// happens while paused still appears in statistics but is never banked as energy, and the
    /// paused time does not count as dormancy afterwards.
    public static func setPaused(_ paused: Bool, state: inout PlantState, now: Date) {
        if paused {
            guard state.pausedAt == nil else { return }
            state.pausedAt = max(now, state.lastUpdated)
            state.lastUpdated = max(now, state.lastUpdated)
        } else if let since = state.pausedAt {
            let resumeAt = max(now, state.lastUpdated)
            let duration = max(0, resumeAt.timeIntervalSince(since))
            state.pausedAt = nil
            state.lastUpdated = resumeAt
            // Shift biological clocks so the pause is invisible to dormancy and scheduling.
            state.lastActivity = state.lastActivity.map { $0.addingTimeInterval(duration) }
            state.lastReliableObservation = state.lastReliableObservation.addingTimeInterval(duration)
            state.nextBirth = state.nextBirth.addingTimeInterval(duration)
            state.nextBranch = state.nextBranch.addingTimeInterval(duration)
            state.nextFlower = state.nextFlower.addingTimeInterval(duration)
            // Paused days were never observed by the hourly simulation; do not credit them later.
            state.creditedBeforeDay = max(state.creditedBeforeDay, day(resumeAt) - 1)
            state.reserve = min(state.reserve, maximumReserve)
        }
    }

    public static func advance(state: inout PlantState, events: [UsageEvent], now: Date, dataAvailable: Bool = true) {
        guard now > state.lastUpdated else { return }
        if state.pausedAt != nil { state.lastUpdated = now; return }
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
            let values = grouped[eventDay]!
            let total = values.reduce(Int64(0)) { partial, event in
                let positive = max(0, event.totalTokens)
                return partial > Int64.max - positive ? Int64.max : partial + positive
            }
            if var prior = ledger[eventDay] {
                prior.tokens = max(prior.tokens, total)
                ledger[eventDay] = prior
            } else {
                let previous = ledger.values.filter { $0.day < eventDay && $0.day >= eventDay - 30 && $0.tokens > 0 }.map { Double($0.tokens) }.sorted()
                let median = previous.isEmpty ? 100_000 : previous[previous.count / 2]
                let confidence = min(1, Double(previous.count) / 7)
                let target = 100_000 * (1 - confidence) + median * confidence
                let previousReference = ledger.values.filter { $0.day < eventDay }.sorted { $0.day < $1.day }.last?.reference ?? state.reference
                // While fewer than seven active days are known (calibration), follow the observed rhythm
                // directly: real heavy users run ~10^8 tokens/day, which a ±15 %/day limit from the
                // 100k prior would need weeks to reach, crediting maximum energy every day meanwhile.
                // After calibration the limit keeps one large or quiet day from swinging the target.
                let reference = confidence < 1 ? max(10_000, target) : min(previousReference * 1.15, max(previousReference * 0.85, max(10_000, target)))
                ledger[eventDay] = PlantDay(day: eventDay, tokens: total, reference: reference, credited: 0)
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
            let positive = max(0, event.totalTokens)
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
                observedTokens[eventDay] = old > Int64.max - max(0, event.totalTokens) ? Int64.max : old + max(0, event.totalTokens)
                if event.totalTokens > 0 { state.lastActivity = max(state.lastActivity ?? state.createdAt, event.timestamp) }
                activityIndex += 1
            }
            // Grants are released only after their day has been observed. This
            // avoids filling reserve with an entire year of logs at once.
            if var record = ledger[currentDay] {
                // Calibration follows 72 elapsed hours, not UTC midnight crossings.
                // UTC still anchors the daily energy cap and deduplication journal.
                let elapsedSinceBirth = max(0, next.timeIntervalSince(state.createdAt))
                let calibration = min(1, 0.25 + 0.75 * elapsedSinceBirth / (72 * hour))
                let entitlement = min(maximumDailyEnergy, log1p(Double(observedTokens[currentDay, default: 0]) / record.reference) / log(2)) * calibration
                let grant = max(0, entitlement - record.credited)
                state.reserve = min(maximumReserve, state.reserve + grant)
                record.credited += grant
                ledger[currentDay] = record
                state.reference = record.reference
            }
            let elapsedHours = next.timeIntervalSince(cursor) / hour
            tick(state: &state, hours: elapsedHours, now: next, dataAvailable: dataAvailable)
            cursor = next
        }
        state.days = ledger.values.filter { $0.day >= oldest }.sorted { $0.day < $1.day }
        state.lastUpdated = now
        if dataAvailable { state.lastReliableObservation = now }
    }

    private static func age(state: inout PlantState, hours: Double, now: Date, dataAvailable: Bool) {
        let dormantDays = max(0, now.timeIntervalSince(state.lastActivity ?? state.createdAt) / 86400 - 3)
        if dataAvailable {
            let target = max(0.3, 1 - dormantDays * 0.025)
            let alpha = 1 - exp(-hours / 72)
            state.health += (target - state.health) * alpha
        }
        for i in state.organs.indices {
            state.organs[i].ageHours += hours
            state.organs[i].health = state.health
        }
    }

    private static func tick(state: inout PlantState, hours: Double, now: Date, dataAvailable: Bool) {
        age(state: &state, hours: hours, now: now, dataAvailable: dataAvailable)
        let spent = min(state.reserve, hours * 0.035)
        state.reserve -= spent
        state.historicalMaturity += spent
        // Recover gradually after recent activity. Never reset historical maturity.
        if dataAvailable, let activity = state.lastActivity, now.timeIntervalSince(activity) < 72 * hour {
            state.health = min(1, state.health + hours * 0.003)
        }
        let expanding = state.organs.indices.filter { state.organs[$0].maturation < 1 && state.organs[$0].kind != .flower }
        if spent > 0, !expanding.isEmpty {
            // Stagger allocation by age; the two initial leaves do not move in lockstep.
            for (offset, i) in expanding.enumerated() {
                let priority = offset % 2 == Int(state.historicalMaturity * 10) % 2 ? 1.5 : 0.55
                state.organs[i].maturation = min(1, state.organs[i].maturation + spent * state.organs[i].growthRate * priority / Double(max(1, expanding.count)) * 3)
            }
        }
        for i in state.organs.indices {
            let organ = state.organs[i]
            if organ.kind == .flower {
                // Each flower carries its own biological progress. A small reserve
                // sustains opening after work; old flowers wilt even with no energy.
                if organ.maturation < 0.72, spent > 0 {
                    state.organs[i].maturation = min(0.72, organ.maturation + hours * organ.growthRate / 120 * min(1, spent / max(0.0001, hours * 0.02)))
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
        if now >= state.nextBranch, state.historicalMaturity >= 1.2, state.reserve >= 0.15 {
            addBranch(state: &state, now: now)
            state.nextBranch = now.addingTimeInterval((3 + state.random() * 2) * 86400)
        }
        if now >= state.nextBirth, state.reserve >= 0.06 {
            addLeaf(state: &state, now: now)
            state.nextBirth = now.addingTimeInterval((8 + state.random() * 14) * hour)
        }
        if now >= state.nextFlower, state.historicalMaturity >= 3, state.reserve >= 0.25 {
            addFlower(state: &state, now: now)
            state.nextFlower = now.addingTimeInterval((3 + state.random() * 4) * 86400)
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
        let protected = Set(leaves.suffix(2).map(\.id))
        let oldCount = state.organs.count
        state.organs.removeAll {
            ($0.kind == .leaf && $0.ageHours > 24 * 35 && !protected.contains($0.id)) ||
            ($0.kind == .flower && ($0.flowerStage == .fallen || $0.ageHours > 24 * 45))
        }
        state.retiredOrgans += Int64(oldCount - state.organs.count)
    }

    private static func attachment(state: inout PlantState) -> PlantOrgan? {
        let branches = state.organs.filter { ($0.kind == .stem || $0.kind == .branch) && $0.maturation >= 0.9 }
        guard !branches.isEmpty else { return nil }
        return branches[min(branches.count - 1, Int(state.random() * Double(branches.count)))]
    }

    private static func addBranch(state: inout PlantState, now: Date) {
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
        let parent = canExtend ? top : (attachment(state: &state) ?? top)
        let point = parent.endpoint
        let direction = state.random() > 0.5 ? 1.0 : -1.0
        let dx = canExtend ? (state.random() - 0.5) * 0.045 : direction * (0.10 + state.random() * 0.10)
        let dy = canExtend ? 0.12 : 0.05 + state.random() * 0.08
        let kind: OrganKind = canExtend ? .stem : .branch
        let organ = state.makeOrgan(kind: kind, parent: parent.id, date: now, x: point.x, y: point.y,
                                    endX: min(0.82, max(0.18, point.x + dx)), endY: max(0.16, point.y - dy), angle: 0)
        state.organs.append(organ)
        state.reserve -= 0.15
    }

    private static func addLeaf(state: inout PlantState, now: Date) {
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
        state.reserve -= 0.06
    }

    private static func addFlower(state: inout PlantState, now: Date) {
        guard state.organs.filter({ $0.kind == .flower }).count < maximumFlowers,
              let parent = attachment(state: &state) else { return }
        let point = parent.endpoint
        let angle = state.random() * 0.3 - 0.15
        let flower = state.makeOrgan(kind: .flower, parent: parent.id, date: now, x: point.x, y: point.y, endX: point.x, endY: point.y, angle: angle)
        state.organs.append(flower)
        state.reserve -= 0.25
    }
}
