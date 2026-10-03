import XCTest
@testable import Contracts

final class ContractsTests: XCTestCase {
    func testTechniqueResultRoundTrip() throws {
        let data = try JSONEncoder().encode(SampleData.technique)
        let decoded = try JSONDecoder().decode(TechniqueResult.self, from: data)
        XCTAssertEqual(decoded, SampleData.technique)
    }

    func testSampleDataIsMarkedAsSimulated() {
        XCTAssertTrue(SampleData.technique.isSimulated)
        XCTAssertTrue(SampleData.recommendation.isSimulated)
        XCTAssertTrue(SampleData.recovery.allSatisfy { $0.isSimulated })
    }

    func testPlanUsesOnlyCatalogExercises() {
        let ids = Set(SampleData.catalog.map(\.id))
        for session in SampleData.plan.sessions {
            for exercise in session.exercises {
                XCTAssertTrue(ids.contains(exercise.exerciseId), "Unknown exercise \(exercise.exerciseId)")
            }
        }
    }

    func testHrvDeltaRatio() {
        XCTAssertEqual(SampleData.today.hrvDeltaRatio, -8.0 / 46.0, accuracy: 0.0001)
    }
}
