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

final class ProfileAndPlanContractTests: XCTestCase {
    func testProfileSavedBeforeNewFieldsStillDecodes() throws {
        let json = #"{"goal":"strength","level":"beginner","daysPerWeek":3,"sessionMinutes":45,"equipment":"none","avoid":"x"}"#
        let profile = try JSONDecoder().decode(UserProfile.self, from: Data(json.utf8))
        XCTAssertEqual(profile.gear, [])
        XCTAssertEqual(profile.avoidTags, [])
        XCTAssertFalse(profile.easyStart)
        XCTAssertEqual(profile.avoid, "x")
    }

    func testProfileRoundTrip() throws {
        let profile = UserProfile(goal: .fitness, level: .intermediate, daysPerWeek: 4, sessionMinutes: 60, equipment: .gym,
                                  avoid: "skoki", gear: [.gym, .kettlebell], avoidTags: [.jumps, .deepLunges], easyStart: true)
        let decoded = try JSONDecoder().decode(UserProfile.self, from: JSONEncoder().encode(profile))
        XCTAssertEqual(decoded, profile)
    }

    func testEquipmentResolvesToBestTier() {
        XCTAssertEqual(Equipment.resolve(from: []), .none)
        XCTAssertEqual(Equipment.resolve(from: [.none]), .none)
        XCTAssertEqual(Equipment.resolve(from: [.kettlebell]), .dumbbells)
        XCTAssertEqual(Equipment.resolve(from: [.dumbbells, .kettlebell]), .dumbbells)
        XCTAssertEqual(Equipment.resolve(from: [.dumbbells, .gym]), .gym)
    }

    func testSamplePlanHasOneSessionPerRequestedDay() async throws {
        for days in 2...5 {
            let profile = UserProfile(goal: .strength, level: .intermediate, daysPerWeek: days, sessionMinutes: 45, equipment: .dumbbells)
            let plan = try await SampleServices().generatePlan(for: profile)
            XCTAssertEqual(plan.sessions.count, days)
            XCTAssertEqual(Set(plan.sessions.map(\.weekday)).count, days, "weekdays must be unique")
        }
    }

    func testSamplePlanLeavesOutAvoidedMovements() async throws {
        let profile = UserProfile(goal: .strength, level: .intermediate, daysPerWeek: 3, sessionMinutes: 45, equipment: .dumbbells,
                                  avoidTags: [.deepLunges, .overheadPress])
        let plan = try await SampleServices().generatePlan(for: profile)
        let ids = plan.sessions.flatMap { $0.exercises.map(\.exerciseId) }
        XCTAssertFalse(ids.contains("lunge"))
        XCTAssertFalse(ids.contains("overhead_press"))
        XCTAssertTrue(plan.sessions.allSatisfy { !$0.exercises.isEmpty })
    }

    func testEasyStartReducesSetsButKeepsAtLeastTwo() async throws {
        let normal = UserProfile(goal: .strength, level: .intermediate, daysPerWeek: 3, sessionMinutes: 45, equipment: .dumbbells)
        var easy = normal
        easy.easyStart = true
        let a = try await SampleServices().generatePlan(for: normal)
        let b = try await SampleServices().generatePlan(for: easy)
        XCTAssertLessThan(b.sessions[0].exercises[0].sets, a.sessions[0].exercises[0].sets)
        XCTAssertTrue(b.sessions.flatMap(\.exercises).allSatisfy { $0.sets >= 2 })
    }

    func testPlanOnlyUsesCatalogExercises() async throws {
        let profile = UserProfile(goal: .physique, level: .beginner, daysPerWeek: 5, sessionMinutes: 60, equipment: .gym)
        let plan = try await SampleServices().generatePlan(for: profile)
        let ids = Set(SampleData.catalog.map(\.id))
        XCTAssertTrue(plan.sessions.flatMap { $0.exercises.map(\.exerciseId) }.allSatisfy(ids.contains))
    }

    func testSampleHealthAuthorizationGrants() async {
        let granted = await SampleServices().requestAccess()
        XCTAssertTrue(granted)
    }
}
