import XCTest
@testable import Onboarding

final class HealthHistoryCautionTests: XCTestCase {
    func testNothingProvidedCallsForNoCaution() {
        let history = HealthHistory()
        XCTAssertFalse(history.hasRecentLowerBodyInjury)
        XCTAssertFalse(history.hasRecentUpperBodyInjury)
    }

    func testARecentKneeHipOrAnkleInjuryCallsForLowerBodyCaution() {
        for area in [BodyArea.knee, .hip, .ankle] {
            for recency in [InjuryRecency.recent, .mid] {
                let history = HealthHistory(injuries: [area], injuryRecency: recency)
                XCTAssertTrue(history.hasRecentLowerBodyInjury, "\(area) \(recency)")
                XCTAssertFalse(history.hasRecentUpperBodyInjury, "\(area) \(recency)")
            }
        }
    }

    func testARecentShoulderOrElbowInjuryCallsForUpperBodyCaution() {
        for area in [BodyArea.shoulder, .elbow] {
            let history = HealthHistory(injuries: [area], injuryRecency: .recent)
            XCTAssertTrue(history.hasRecentUpperBodyInjury, "\(area)")
            XCTAssertFalse(history.hasRecentLowerBodyInjury, "\(area)")
        }
    }

    func testAnOldInjuryCallsForNoCaution() {
        let history = HealthHistory(injuries: [.knee, .shoulder], injuryRecency: .old)
        XCTAssertFalse(history.hasRecentLowerBodyInjury)
        XCTAssertFalse(history.hasRecentUpperBodyInjury)
    }

    func testABackInjuryIsNotACautionForTheRangeOfAMovement() {
        // A back injury must not make the lean of a squat easier, so it is not mapped to either region.
        let history = HealthHistory(injuries: [.back], injuryRecency: .recent)
        XCTAssertFalse(history.hasRecentLowerBodyInjury)
        XCTAssertFalse(history.hasRecentUpperBodyInjury)
    }

    func testBothRegionsAtOnce() {
        let history = HealthHistory(injuries: [.knee, .elbow], injuryRecency: .mid)
        XCTAssertTrue(history.hasRecentLowerBodyInjury)
        XCTAssertTrue(history.hasRecentUpperBodyInjury)
    }
}
