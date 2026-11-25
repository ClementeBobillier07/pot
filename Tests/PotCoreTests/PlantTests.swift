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
                events.append(event(Double(day) * 86400 + 9 * 3600, 80_000))
                events.append(event(Double(day) * 86400 + 14 * 3600, 50_000))
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
        XCTAssertGreaterThanOrEqual(single.health, 0.3)
    }

    func testLeavesGrowIndividuallyAndCalibrationCapsExtremeUsage() {
        var state = PlantState(seed: 42, provider: .codex, createdAt: start)
        let sample = event(60, 1_000_000_000)
        PlantEngine.advance(state: &state, events: [sample], now: start.addingTimeInterval(12 * 3600))
        let leaves = state.organs.filter { $0.kind == .leaf }
        XCTAssertGreaterThan(leaves[0].size, 1)
        XCTAssertNotEqual(leaves[0].size, leaves[1].size)
        let initialBudget = 0.25 + 0.75 * 12 / 72
        XCTAssertLessThanOrEqual(state.days.first!.credited, initialBudget)
        XCTAssertLessThanOrEqual(state.historicalMaturity + state.reserve, initialBudget + 0.00001)
    }

    func testCalibrationUsesSeventyTwoElapsedHoursAcrossMidnight() {
        let nearMidnight = start.addingTimeInterval(86400 - 60)
        var state = PlantState(seed: 77, provider: .codex, createdAt: nearMidnight)
        let recent = UsageEvent(id: "after-midnight", provider: .codex, timestamp: nearMidnight.addingTimeInterval(120), model: "synthetic", input: 1_000_000_000, output: 0)
        PlantEngine.advance(state: &state, events: [recent], now: nearMidnight.addingTimeInterval(3600))
        XCTAssertLessThan(state.days.first!.credited, 0.27, "Crossing midnight must not skip a calibration day")
        let later = UsageEvent(id: "third-day", provider: .codex, timestamp: nearMidnight.addingTimeInterval(70 * 3600), model: "synthetic", input: 1_000_000_000, output: 0)
        PlantEngine.advance(state: &state, events: [recent, later], now: nearMidnight.addingTimeInterval(71 * 3600))
        XCTAssertLessThan(state.days.last!.credited, 1, "The first 72 elapsed hours remain calibrated even across four UTC dates")
        PlantEngine.advance(state: &state, events: [recent, later], now: nearMidnight.addingTimeInterval(73 * 3600))
        XCTAssertEqual(state.days.last!.credited, 1, accuracy: 0.00001)
    }

    func testWeekendGraceDataGapFreezeRecoveryAndPersistentMaturity() {
        var state = PlantState(seed: 10, provider: .codex, createdAt: start)
        let work = event(3600, 100_000)
        PlantEngine.advance(state: &state, events: [work], now: start.addingTimeInterval(2 * 86400))
        XCTAssertEqual(state.health, 1, accuracy: 0.00001)
        let initialHealth = state.health
        PlantEngine.advance(state: &state, events: [work], now: start.addingTimeInterval(90 * 86400), dataAvailable: false)
        XCTAssertEqual(state.health, initialHealth)
        PlantEngine.advance(state: &state, events: [work], now: start.addingTimeInterval(120 * 86400))
        XCTAssertLessThan(state.health, 0.5)
        let unhealthy = state.health
        let maturity = state.historicalMaturity
        let returnWork = event(120 * 86400 + 3600, 100_000)
        PlantEngine.advance(state: &state, events: [work, returnWork], now: start.addingTimeInterval(122 * 86400))
        XCTAssertGreaterThan(state.health, unhealthy)
        XCTAssertGreaterThanOrEqual(state.historicalMaturity, maturity)
    }

    func testPersistedRestartMatchesUninterruptedState() throws {
        var live = PlantState(seed: 111, provider: .codex, createdAt: start)
        let events = (0..<40).map { event(Double($0) * 86400 + 9 * 3600, 120_000) }
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
        for day in 0..<90 {
            events.append(event(Double(day) * 86400 + 3600, 150_000))
            PlantEngine.advance(state: &state, events: events, now: start.addingTimeInterval(Double(day + 1) * 86400))
        }
        let flowers = state.organs.filter { $0.kind == .flower }
        XCTAssertGreaterThan(flowers.count, 1)
        XCTAssertGreaterThan(Set(flowers.map(\.maturation)).count, 1)
    }
    func testPausedGardenFreezesBiologyAndDoesNotBankPausedUsage() {
        var plant = PlantState(seed: 7, provider: .codex, createdAt: start)
        var events: [UsageEvent] = []
        for day in 0..<10 { events.append(event(Double(day) * 86400 + 9 * 3600, 120_000)) }
        PlantEngine.advance(state: &plant, events: events, now: start.addingTimeInterval(10 * 86400))
        PlantEngine.setPaused(true, state: &plant, now: start.addingTimeInterval(10 * 86400))
        let frozen = plant
        // Two weeks of vacation with heavy usage recorded meanwhile.
        for day in 10..<24 { events.append(event(Double(day) * 86400 + 9 * 3600, 5_000_000)) }
        PlantEngine.advance(state: &plant, events: events, now: start.addingTimeInterval(24 * 86400))
        XCTAssertEqual(plant.organs, frozen.organs)
        XCTAssertEqual(plant.health, frozen.health)
        XCTAssertEqual(plant.reserve, frozen.reserve)
        XCTAssertEqual(plant.historicalMaturity, frozen.historicalMaturity)
        PlantEngine.setPaused(false, state: &plant, now: start.addingTimeInterval(24 * 86400))
        XCTAssertNil(plant.pausedAt)
        // One quiet day after returning: paused usage is not credited and the pause is not dormancy.
        PlantEngine.advance(state: &plant, events: events, now: start.addingTimeInterval(25 * 86400))
        XCTAssertLessThanOrEqual(plant.reserve, frozen.reserve + 0.0001)
        XCTAssertGreaterThan(plant.health, 0.95)
        // Without the pause, two silent weeks would have lowered health.
        var unpaused = frozen; unpaused.pausedAt = nil
        PlantEngine.advance(state: &unpaused, events: Array(events.prefix(10)), now: start.addingTimeInterval(25 * 86400))
        XCTAssertLessThan(unpaused.health, plant.health)
    }

    func testPausedStatePersists() throws {
        var plant = PlantState(seed: 3, provider: .claude, createdAt: start)
        PlantEngine.setPaused(true, state: &plant, now: start.addingTimeInterval(3600))
        let decoded = try JSONDecoder().decode(PlantState.self, from: JSONEncoder().encode(plant))
        XCTAssertEqual(decoded.pausedAt, plant.pausedAt)
    }
}
