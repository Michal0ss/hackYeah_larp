import Contracts
import Plan
import XCTest
@testable import Coaching

final class WorkoutContextTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000)

    private func exercise(_ id: String, sets: Int = 3) -> PlannedExercise {
        PlannedExercise(exerciseId: id, sets: sets, repsMin: 6, repsMax: 8, restSeconds: 90, tempo: nil)
    }

    private lazy var session = PlannedSession(weekday: 1, title: "Nogi", exercises: [exercise("squat"), exercise("plank", sets: 2)])

    private func summary(index: Int = 1) -> SetSummary {
        let reps = (1...6).map {
            RepTempo(index: $0, startedAt: Double($0) * 5, eccentric: 1.6, bottomPause: 0.4, concentric: 1.1, topPauseBefore: 0,
                     peakDepth: 0.4, isFullRange: $0 > 2)
        }
        return SetSummary(exerciseId: "squat", setIndex: index, targetTempo: .controlled, reps: reps, tempoScore: 58,
                          tempoFindings: [], techniqueScore: 64,
                          techniqueFindings: [TechniqueFinding(id: "depth", title: "Zbyt płytko", detail: "d", severity: .major,
                                                                repsAffected: 2, repsTotal: 6)],
                          framing: FramingSummary(rating: .good, goodFrameRatio: 0.9))
    }

    private func run(after set: LoggedSet) -> WorkoutRun {
        var run = WorkoutRun(session: session)
        run.begin()
        run.complete(set, now: t0)
        return run
    }

    func testAfterALiveSetTheCameraResultsTravelAsTheSetDigest() {
        let live = summary()
        let set = LoggedSet(sessionId: session.id, exerciseId: "squat", setIndex: 1, reps: 6, source: .live, liveSetId: live.id)
        let context = WorkoutContextFactory.context(for: run(after: set), screen: .rest, liveSummary: live)
        XCTAssertEqual(context.screen, .rest)
        XCTAssertEqual(context.exerciseId, "squat")
        XCTAssertEqual(context.setIndex, 1)
        XCTAssertEqual(context.totalSets, 3)
        XCTAssertEqual(context.lastSet?.reps, 6)
        XCTAssertEqual(context.lastSet?.fullRangeReps, 4)
        XCTAssertNil(context.loggedSet, "nothing was typed or changed")
    }

    func testACorrectedLiveSetAlsoCarriesWhatTheUserTyped() {
        let live = summary()
        var set = LoggedSet(sessionId: session.id, exerciseId: "squat", setIndex: 1, reps: 6, source: .live, liveSetId: live.id)
        set.reps = 7
        set.weightKg = 20
        set.isEdited = true
        let context = WorkoutContextFactory.context(for: run(after: set), screen: .setSummary, liveSummary: live)
        XCTAssertNotNil(context.lastSet)
        XCTAssertEqual(context.loggedSet?.reps, 7)
        XCTAssertEqual(context.loggedSet?.weightKg, 20)
        XCTAssertEqual(context.loggedSet?.plannedMin, 6)
        XCTAssertEqual(context.loggedSet?.plannedMax, 8)
    }

    func testATypedSetHasNoCameraDigest() {
        let set = LoggedSet(sessionId: session.id, exerciseId: "squat", setIndex: 1, reps: 8, source: .manual)
        let context = WorkoutContextFactory.context(for: run(after: set), screen: .rest)
        XCTAssertNil(context.lastSet)
        XCTAssertEqual(context.loggedSet?.reps, 8)
        XCTAssertNil(context.loggedSet?.weightKg, "no weight was typed, none is sent")
    }

    func testATimedSetCarriesSeconds() {
        var run = WorkoutRun(session: session)
        run.begin(atExercise: 1)
        run.complete(LoggedSet(sessionId: session.id, exerciseId: "plank", setIndex: 1, seconds: 45), now: t0)
        let context = WorkoutContextFactory.context(for: run, screen: .rest)
        XCTAssertEqual(context.exerciseId, "plank")
        XCTAssertEqual(context.totalSets, 2)
        XCTAssertEqual(context.loggedSet?.seconds, 45)
        XCTAssertNil(context.loggedSet?.reps)
    }

    func testDuringASetThereIsNoLastSet() {
        var run = WorkoutRun(session: session)
        run.begin()
        let context = WorkoutContextFactory.context(for: run, screen: .liveSet)
        XCTAssertEqual(context.exerciseId, "squat")
        XCTAssertEqual(context.setIndex, 1)
        XCTAssertNil(context.lastSet)
        XCTAssertNil(context.loggedSet)
    }

    func testTheContextSurvivesTheWire() throws {
        let set = LoggedSet(sessionId: session.id, exerciseId: "squat", setIndex: 1, reps: 8, weightKg: 12.5)
        let context = WorkoutContextFactory.context(for: run(after: set), screen: .rest)
        let again = try JSONDecoder().decode(WorkoutContext.self, from: JSONEncoder().encode(context))
        XCTAssertEqual(again, context)
        // A context from before `loggedSet` existed still decodes.
        let old = #"{"screen":"rest","setIndex":1}"#
        XCTAssertNil(try JSONDecoder().decode(WorkoutContext.self, from: Data(old.utf8)).loggedSet)
    }

    func testTheTrainingLogToolListsTypedSetsWithTheirWeightOnlyWhenEntered() async {
        struct Typed: LoggedSetProviding { var sets: [LoggedSet] }
        let now = Date()
        let tools = CoachTools(plan: SampleServices(), catalog: SampleServices(), recovery: SampleServices(), checkIns: SampleServices(),
                               technique: SampleServices(), recommendation: SampleServices(),
                               loggedSets: Typed(sets: [
                                   LoggedSet(sessionId: session.id, exerciseId: "squat", setIndex: 1, date: now, reps: 8, weightKg: 17.5),
                                   LoggedSet(sessionId: session.id, exerciseId: "plank", setIndex: 1, date: now, seconds: 45),
                               ]),
                               hasHealthConsent: { false }, now: { now })
        let output = await tools.run(name: CoachToolName.trainingLog, input: .object([:]))
        XCTAssertTrue(output.content.contains("\"weightKg\":17.5"))
        XCTAssertEqual(output.content.components(separatedBy: "weightKg").count - 1, 1, "the plank has no weight")
        XCTAssertTrue(output.content.contains("\"seconds\":45"))
    }
}
