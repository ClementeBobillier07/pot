import XCTest
@testable import PotCore

final class FloatingPolicyTests: XCTestCase {
    func testModesAndManualDismissalAcrossSession() {
        let now = Date(timeIntervalSince1970: 10_000)
        var policy = FloatingPolicy(mode: .menuBarOnly)
        XCTAssertFalse(policy.visible(lastActivity: now, now: now, hasPlant: true))
        policy.mode = .alwaysWithMe
        XCTAssertTrue(policy.visible(lastActivity: nil, now: now, hasPlant: true))
        XCTAssertFalse(policy.visible(lastActivity: now, now: now, hasPlant: false))
        policy.mode = .whileIWork
        XCTAssertTrue(policy.visible(lastActivity: now, now: now, hasPlant: true))
        policy.hide()
        XCTAssertFalse(policy.visible(lastActivity: now.addingTimeInterval(30), now: now.addingTimeInterval(30), hasPlant: true))
        XCTAssertFalse(policy.visible(lastActivity: now, now: now.addingTimeInterval(181), hasPlant: true))
        XCTAssertTrue(policy.visible(lastActivity: now.addingTimeInterval(182), now: now.addingTimeInterval(182), hasPlant: true))
    }
    func testFutureActivityDoesNotDisplayPlant() {
        let now = Date()
        var policy = FloatingPolicy(mode: .whileIWork)
        XCTAssertFalse(policy.visible(lastActivity: now.addingTimeInterval(10_000), now: now, hasPlant: true))
    }
}
