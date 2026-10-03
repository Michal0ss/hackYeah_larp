import XCTest
@testable import Contracts

final class PlanNoticeTests: XCTestCase {
    private func decode(_ json: String) throws -> TrainingPlan {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(TrainingPlan.self, from: Data(json.utf8))
    }

    func testPlanSavedBeforeNoticesExistedStillDecodes() throws {
        let plan = try decode(#"{"createdAt": "2026-10-03T08:00:00Z", "source": "template", "sessions": []}"#)
        XCTAssertEqual(plan.notices, [])
        XCTAssertEqual(plan.source, .template)
    }

    func testNoticesSurviveARoundTrip() throws {
        let original = TrainingPlan(createdAt: Date(timeIntervalSince1970: 1_790_000_000), source: .template,
                                    sessions: SampleData.plan.sessions, notices: [.offline, .avoidTextNotApplied])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let again = try decode(String(data: try encoder.encode(original), encoding: .utf8)!)
        XCTAssertEqual(again.notices, [.offline, .avoidTextNotApplied])
        XCTAssertEqual(again.sessions, original.sessions)
    }

    func testAnUnknownNoticeFromANewerVersionIsDroppedNotFatal() throws {
        let plan = try decode(#"{"createdAt": "2026-10-03T08:00:00Z", "source": "ai", "sessions": [], "notices": ["offline", "somethingNew"]}"#)
        XCTAssertEqual(plan.notices, [.offline])
    }

    func testEveryNoticeHasAUserMessage() {
        for notice in [PlanNotice.aiUnavailable, .aiInvalidPlan, .offline, .avoidTextNotApplied] {
            XCTAssertFalse(notice.userMessage.isEmpty)
        }
    }

    func testExistingCallersKeepWorking() {
        let plan = TrainingPlan(createdAt: Date(), source: .ai, sessions: [])
        XCTAssertEqual(plan.notices, [])
    }
}
