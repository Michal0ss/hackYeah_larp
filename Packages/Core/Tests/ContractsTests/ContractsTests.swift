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

final class SampleServicesTests: XCTestCase {
    func testSampleServicesServeSampleData() async {
        let services = SampleServices()
        let recovery = await services.snapshots(days: 7)
        XCTAssertEqual(recovery.count, 7)
        XCTAssertEqual(services.exercise(id: "squat")?.name, "Przysiad")
        let session = await services.todaySession()
        XCTAssertNotNil(session)
        let recommendation = await services.todayRecommendation()
        XCTAssertTrue(recommendation.isSimulated)
    }
}
