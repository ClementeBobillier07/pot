import Foundation
import XCTest
@testable import PotCore

final class PlantTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_735_689_600)
    private func event(_ offset: Double, _ tokens: Int64 = 100_000, id: String? = nil) -> UsageEvent {
        UsageEvent(id: id ?? "event-\(offset)", provider: .codex, timestamp: start.addingTimeInterval(offset), model: "synthetic-test-model", input: tokens, output: 0)
    }

    func testTinyStartAndStableGenetics() throws {
        let first = PlantState(seed: 42, provider: .codex, createdAt: start)
        XCTAssertEqual(first, PlantState(seed: 42, provider: .codex, createdAt: start))
        XCTAssertNotEqual(first.organs, PlantState(seed: 43, provider: .codex, createdAt: start).organs)
        XCTAssertEqual(first.organs.filter { $0.kind == .leaf }.map(\.size), [1, 1])
        XCTAssertEqual(first.historicalMaturity, 0)
        let data = try JSONEncoder().encode(first)
        XCTAssertEqual(try JSONDecoder().decode(PlantState.self, from: data), first)
    }

    func testDeterministicYearHasBoundedConnectedRenewingOrgans() throws {
        var first = PlantState(seed: 19, provider: .codex, createdAt: start)
        var replay = first
        var events: [UsageEvent] = []
        var flowerIDs = Set<String>()
        var stages = Set<FlowerStage>()
        for day in 0..<365 {
            // Two useful sessions, with ordinary weekend gaps.
            if day % 7 < 5 {
                events.append(event(Double(day) * 86400 + 9 * 3600, 12_000_000))
                events.append(event(Double(day) * 86400 + 14 * 3600, 8_000_000))
            }
            let now = start.addingTimeInterval(Double(day + 1) * 86400)
            PlantEngine.advance(state: &first, events: events, now: now)
            PlantEngine.advance(state: &replay, events: events, now: now)
            XCTAssertEqual(first, replay)
            XCTAssertLessThanOrEqual(first.organs.filter { $0.kind == .leaf }.count, PlantEngine.maximumLeaves)
            XCTAssertLessThanOrEqual(first.organs.filter { $0.kind == .flower }.count, PlantEngine.maximumFlowers)
            XCTAssertLessThanOrEqual(first.organs.filter { $0.kind == .stem || $0.kind == .branch }.count, PlantEngine.maximumBranches)
            XCTAssertLessThanOrEqual(first.days.count, 45)
            XCTAssertLessThanOrEqual(first.reserve, PlantEngine.maximumReserve)
            XCTAssertGreaterThanOrEqual(first.reserve, -0.00001)
            let identifiers = Set(first.organs.map(\.id))
            for organ in first.organs {
                XCTAssertGreaterThanOrEqual(organ.size, 1)
                XCTAssertLessThanOrEqual(organ.size, 10)
                if let parent = organ.parentID { XCTAssertTrue(identifiers.contains(parent)) }
                if organ.kind == .flower { flowerIDs.insert(organ.id); stages.insert(organ.flowerStage) }
            }
        }
        XCTAssertGreaterThan(first.retiredOrgans, 10)
        XCTAssertGreaterThan(first.historicalMaturity, 30)
        XCTAssertGreaterThan(flowerIDs.count, 4)
        XCTAssertTrue(stages.contains(.bloom))
        XCTAssertTrue(stages.contains(.wilted))
        XCTAssertLessThan(try JSONEncoder().encode(first).count, 80_000)
    }

    func testNoRewardFromDuplicateImportsHistoricalUsageAndBackwardsClock() {
        var single = PlantState(seed: 5, provider: .codex, createdAt: start)
        var duplicated = single
        let sample = event(1800, 1_000_000)
        let historical = event(-86400, 999_999_999)
        let end = start.addingTimeInterval(86400)
        PlantEngine.advance(state: &single, events: [sample], now: end)
        PlantEngine.advance(state: &duplicated, events: [sample, sample, historical], now: end)
        XCTAssertEqual(single, duplicated)
        let snapshot = single
        PlantEngine.advance(state: &single, events: [sample], now: start.addingTimeInterval(900))
        XCTAssertEqual(single, snapshot)
        PlantEngine.advance(state: &single, events: [sample], now: end)
        XCTAssertEqual(single, snapshot)
        PlantEngine.advance(state: &single, events: [sample], now: end.addingTimeInterval(365 * 86400))
        XCTAssertLessThanOrEqual(single.historicalMaturity, snapshot.historicalMaturity + snapshot.reserve + 0.00001)
        XCTAssertEqual(single.days.count, 0)
        // A year without use leaves the plant wilted, never dead.
        XCTAssertEqual(single.health, PlantEngine.minimumHealth, accuracy: 0.00001)
    }

    func testLeavesGrowIndividuallyAndDailyEnergyIsCapped() {
        var state = PlantState(seed: 42, provider: .codex, createdAt: start)
        let sample = event(60, 1_000_000_000)
        PlantEngine.advance(state: &state, events: [sample], now: start.addingTimeInterval(12 * 3600))
        let leaves = state.organs.filter { $0.kind == .leaf }
        XCTAssertGreaterThan(leaves[0].size, 1)
        XCTAssertNotEqual(leaves[0].size, leaves[1].size)
        XCTAssertLessThanOrEqual(state.days.first!.credited, PlantEngine.maximumDailyEnergy + 0.00001)
        XCTAssertLessThanOrEqual(state.historicalMaturity + state.reserve, PlantEngine.maximumDailyEnergy + 0.00001)
    }

    func testOneGlobalRhythmHeavyUseGrowsVisiblyFasterThanLightUse() {
        XCTAssertEqual(PlantEngine.dailyEnergy(work: PlantEngine.referenceDailyWork), 1, accuracy: 0.00001)
        XCTAssertLessThan(PlantEngine.dailyEnergy(work: 1_000_000), 0.15)
        XCTAssertEqual(PlantEngine.dailyEnergy(work: 1e12), PlantEngine.maximumDailyEnergy)
        // Cache reads weigh a tenth, output five times: long cached contexts don't dominate.
        let call = UsageEvent(id: "w", provider: .claude, timestamp: start, model: "m", input: 100, output: 10, cacheRead: 1_000, cacheWrite: 50)
        XCTAssertEqual(PlantEngine.workUnits(call), 100 + 50 + 100 + 50)
        var heavy = PlantState(seed: 4, provider: .codex, createdAt: start)
        var light = PlantState(seed: 4, provider: .codex, createdAt: start)
        let heavyEvents = (0..<21).map { event(Double($0) * 86400 + 10 * 3600, 40_000_000, id: "h\($0)") }
        let lightEvents = (0..<21).map { event(Double($0) * 86400 + 10 * 3600, 1_000_000, id: "l\($0)") }
        let end = start.addingTimeInterval(21 * 86400)
        PlantEngine.advance(state: &heavy, events: heavyEvents, now: end)
        PlantEngine.advance(state: &light, events: lightEvents, now: end)
        XCTAssertGreaterThan(heavy.historicalMaturity, light.historicalMaturity * 4)
        XCTAssertGreaterThan(heavy.organs.filter { $0.kind == .leaf }.count, light.organs.filter { $0.kind == .leaf }.count + 5)
        XCTAssertGreaterThan(light.health, 0.95, "Light daily use is still care: no wilting")
    }

    func testWiltingShowsFromTheSecondIdleDayFloorsAndRecovers() {
        var state = PlantState(seed: 10, provider: .codex, createdAt: start)
        let work = event(3600, 10_000_000)
        PlantEngine.advance(state: &state, events: [work], now: start.addingTimeInterval(86400 + 3600))
        XCTAssertEqual(state.health, 1, accuracy: 0.00001, "One day without use is unchanged")
        PlantEngine.advance(state: &state, events: [work], now: start.addingTimeInterval(2 * 86400 + 3600))
        XCTAssertLessThan(state.health, 0.85, "Two days without use are visible")
        PlantEngine.advance(state: &state, events: [work], now: start.addingTimeInterval(4 * 86400 + 3600))
        XCTAssertLessThan(state.health, 0.5, "Four days without use look wilted")
        // Missing or unreadable logs freeze health: a reading problem is not a day off.
        let frozen = state.health
        PlantEngine.advance(state: &state, events: [work], now: start.addingTimeInterval(30 * 86400), dataAvailable: false)
        XCTAssertEqual(state.health, frozen)
        PlantEngine.advance(state: &state, events: [work], now: start.addingTimeInterval(60 * 86400))
        XCTAssertEqual(state.health, PlantEngine.minimumHealth, accuracy: 0.00001, "Wilted, never dead")
        let maturity = state.historicalMaturity
        // A few ordinary days of work bring it back.
        let comeback = (60..<63).map { event(Double($0) * 86400 + 9 * 3600, 10_000_000, id: "back\($0)") }
        PlantEngine.advance(state: &state, events: [work] + comeback, now: start.addingTimeInterval(63 * 86400))
        XCTAssertGreaterThan(state.health, 0.8)
        XCTAssertGreaterThanOrEqual(state.historicalMaturity, maturity)
    }

    func testPersistedRestartMatchesUninterruptedState() throws {
        var live = PlantState(seed: 111, provider: .codex, createdAt: start)
        let events = (0..<40).map { event(Double($0) * 86400 + 9 * 3600, 15_000_000) }
        PlantEngine.advance(state: &live, events: events, now: start.addingTimeInterval(20 * 86400))
        var restored = try JSONDecoder().decode(PlantState.self, from: JSONEncoder().encode(live))
        let finish = start.addingTimeInterval(40 * 86400)
        PlantEngine.advance(state: &live, events: events, now: finish)
        PlantEngine.advance(state: &restored, events: events, now: finish)
        XCTAssertEqual(live, restored)
    }

    func testSevenFlowerStagesAreOrderedAndIndependent() {
        let samples: [Double] = [0, 0.15, 0.4, 0.7, 0.85, 0.95, 1]
        XCTAssertEqual(samples.map { PlantEngine.flowerStage(progress: $0, ageHours: 24) }, FlowerStage.allCases)
        var state = PlantState(seed: 80, provider: .codex, createdAt: start)
        var events: [UsageEvent] = []
        // Flowers live about a week and new buds appear every 3–7 days, so check that at some
        // point several coexist at independent stages rather than at one arbitrary day.
        var bestDistinct = 0
        for day in 0..<90 {
            events.append(event(Double(day) * 86400 + 3600, 30_000_000))
            PlantEngine.advance(state: &state, events: events, now: start.addingTimeInterval(Double(day + 1) * 86400))
            let flowers = state.organs.filter { $0.kind == .flower }
            bestDistinct = max(bestDistinct, Set(flowers.map(\.maturation)).count)
        }
        XCTAssertGreaterThan(bestDistinct, 1)
    }
}
