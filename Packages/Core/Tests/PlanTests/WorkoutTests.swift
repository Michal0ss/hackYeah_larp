import Contracts
import XCTest
@testable import Plan

final class TrainingLogTests: XCTestCase {
    private func file() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("forma-log-\(UUID().uuidString)").appendingPathComponent("training-log.json")
    }

    private let session = UUID()

    private func set(_ exercise: String = "goblet_squat", index: Int = 1, reps: Int? = 8, weight: Double? = nil,
                     date: Date = Date()) -> LoggedSet {
        LoggedSet(sessionId: session, exerciseId: exercise, setIndex: index, date: date, reps: reps, weightKg: weight)
    }

    func testSetsSurviveARestart() {
        let url = file()
        let log = TrainingLogStore(fileURL: url)
        let saved = set(weight: 12.5)
        log.record(saved)
        XCTAssertEqual(TrainingLogStore(fileURL: url).sets, [saved])
    }

    func testTheSameSetOfTheSameSessionIsReplaced() {
        let log = TrainingLogStore(fileURL: nil)
        log.record(set(reps: 6))
        log.record(set(reps: 8))
        XCTAssertEqual(log.sets.count, 1)
        XCTAssertEqual(log.sets.first?.reps, 8)
        log.record(set(index: 2))  // another set
        XCTAssertEqual(log.sets.count, 2)
    }

    func testNumbersAreLimitedAndWeightIsRoundedOrDropped() {
        XCTAssertEqual(LoggedSet(sessionId: session, exerciseId: "x", setIndex: 1, reps: 999).reps, 200)
        XCTAssertEqual(LoggedSet(sessionId: session, exerciseId: "x", setIndex: 1, reps: -3).reps, 0)
        XCTAssertEqual(LoggedSet(sessionId: session, exerciseId: "x", setIndex: 1, weightKg: 12.3).weightKg, 12.25)
        XCTAssertNil(LoggedSet(sessionId: session, exerciseId: "x", setIndex: 1, weightKg: 0).weightKg)
        XCTAssertNil(LoggedSet(sessionId: session, exerciseId: "x", setIndex: 1, weightKg: -5).weightKg)
        XCTAssertEqual(LoggedSet(sessionId: session, exerciseId: "x", setIndex: 1, weightKg: 9_000).weightKg, 500)
    }

    func testEditingMarksTheSetAsEditedOnlyWhenSomethingChanged() throws {
        let log = TrainingLogStore(fileURL: nil)
        let original = set(reps: 6)
        log.record(original)
        XCTAssertEqual(log.edit(original.id, reps: 6)?.isEdited, false, "same number: not an edit")
        let edited = try XCTUnwrap(log.edit(original.id, reps: 7, weightKg: 20))
        XCTAssertEqual(edited.reps, 7)
        XCTAssertEqual(edited.weightKg, 20)
        XCTAssertTrue(edited.isEdited)
        XCTAssertEqual(log.edit(original.id, weightKg: .some(nil))?.weightKg, nil, "the weight can be taken away")
        XCTAssertNil(log.edit(UUID(), reps: 1))
    }

    func testLastWeightComesFromTheNewestSetWithAWeight() {
        let log = TrainingLogStore(fileURL: nil)
        log.record(set(index: 1, weight: 10))
        log.record(set(index: 2, weight: nil))
        XCTAssertEqual(log.lastWeight(exerciseId: "goblet_squat"), 10, "a set without a weight does not hide the earlier one")
        XCTAssertNil(log.lastWeight(exerciseId: "plank"))
    }

    func testSetsOfOneSessionComeInOrderAndOthersAreLeftOut() {
        let log = TrainingLogStore(fileURL: nil)
        let t0 = Date()
        log.record(set(index: 2, date: t0.addingTimeInterval(60)))
        log.record(set(index: 1, date: t0))
        log.record(LoggedSet(sessionId: UUID(), exerciseId: "x", setIndex: 1))
        XCTAssertEqual(log.sets(forSession: session).map(\.setIndex), [1, 2])
    }

    func testTheLogIsCapped() {
        let log = TrainingLogStore(fileURL: nil)
        for index in 0..<(TrainingLogStore.maxSets + 10) { log.record(set(index: index + 1)) }
        XCTAssertEqual(log.sets.count, TrainingLogStore.maxSets)
    }

    func testRemoveAndClear() {
        let url = file()
        let log = TrainingLogStore(fileURL: url)
        let one = set()
        log.record(one)
        log.remove(one.id)
        XCTAssertTrue(log.sets.isEmpty)
        log.record(set(index: 2))
        log.clear()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(TrainingLogStore(fileURL: url).sets.isEmpty)
    }

    func testABrokenFileIsKeptAsideAndTheLogStartsEmpty() throws {
        let url = file()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("nope".utf8).write(to: url)
        XCTAssertTrue(TrainingLogStore(fileURL: url).sets.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.deletingPathExtension().appendingPathExtension("corrupt.json").path))
    }

    func testParallelWrites() {
        let log = TrainingLogStore(fileURL: file())
        DispatchQueue.concurrentPerform(iterations: 40) { index in
            if index % 2 == 0 { log.record(set(index: index + 1)) } else { _ = log.sets }
        }
        XCTAssertEqual(log.sets.count, 20)
    }
}

final class RestTimerTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000)

    func testItCountsDownFromTheMomentItEnds() {
        let timer = RestTimer(seconds: 90, now: t0)
        XCTAssertEqual(timer.remaining(at: t0), 90)
        XCTAssertEqual(timer.remaining(at: t0.addingTimeInterval(30)), 60, "after the screen was locked for 30 s")
        XCTAssertEqual(timer.remaining(at: t0.addingTimeInterval(500)), 0, "never negative")
        XCTAssertFalse(timer.isFinished(at: t0.addingTimeInterval(89)))
        XCTAssertTrue(timer.isFinished(at: t0.addingTimeInterval(90)))
    }

    func testProgressGoesFromZeroToOne() {
        let timer = RestTimer(seconds: 100, now: t0)
        XCTAssertEqual(timer.progress(at: t0), 0)
        XCTAssertEqual(timer.progress(at: t0.addingTimeInterval(25)), 0.25, accuracy: 0.001)
        XCTAssertEqual(timer.progress(at: t0.addingTimeInterval(200)), 1)
        XCTAssertEqual(RestTimer(seconds: 0, now: t0).progress(at: t0), 1, "no rest at all is already over")
    }

    func testPlusAndMinusFifteenSeconds() {
        var timer = RestTimer(seconds: 60, now: t0)
        timer.add(15, now: t0.addingTimeInterval(10))
        XCTAssertEqual(timer.remaining(at: t0.addingTimeInterval(10)), 65)
        timer.add(-15, now: t0.addingTimeInterval(10))
        XCTAssertEqual(timer.remaining(at: t0.addingTimeInterval(10)), 50)
        timer.add(-15, now: t0.addingTimeInterval(50))  // only 0 s were left: cannot go below zero
        XCTAssertEqual(timer.remaining(at: t0.addingTimeInterval(50)), 0)
    }

    func testItCannotBeLongerThanTenMinutes() {
        var timer = RestTimer(seconds: 595, now: t0)
        timer.add(15, now: t0)
        XCTAssertEqual(timer.remaining(at: t0), 600)
        XCTAssertEqual(RestTimer(seconds: 5_000, now: t0).remaining(at: t0), 600)
    }

    func testSkipEndsItNow() {
        var timer = RestTimer(seconds: 60, now: t0)
        timer.skip(now: t0.addingTimeInterval(5))
        XCTAssertTrue(timer.isFinished(at: t0.addingTimeInterval(5)))
    }
}

final class WorkoutRunTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000)

    private func exercise(_ id: String, sets: Int, rest: Int = 90) -> PlannedExercise {
        PlannedExercise(exerciseId: id, sets: sets, repsMin: 6, repsMax: 8, restSeconds: rest, tempo: nil)
    }

    // squat 2 sets, bridge 2 sets, plank 1 set
    private lazy var session = PlannedSession(weekday: 1, title: "Całe ciało", exercises: [
        exercise("squat", sets: 2, rest: 120), exercise("bridge", sets: 2, rest: 60), exercise("plank", sets: 1, rest: 45),
    ])

    private func done(_ run: WorkoutRun, reps: Int = 8) -> LoggedSet {
        LoggedSet(sessionId: run.session.id, exerciseId: run.currentExercise!.exerciseId, setIndex: run.setIndex, reps: reps)
    }

    func testTheWholeSessionInOrder() {
        var run = WorkoutRun(session: session)
        XCTAssertEqual(run.phase, .overview)
        run.begin()
        var order: [String] = []
        while run.phase != .finished {
            XCTAssertEqual(run.phase, .performing)
            order.append("\(run.currentExercise!.exerciseId)\(run.setIndex)")
            run.complete(done(run), now: t0)
            XCTAssertEqual(run.phase, .resting)
            run.next()
        }
        XCTAssertEqual(order, ["squat1", "squat2", "bridge1", "bridge2", "plank1"])
        XCTAssertEqual(run.completedSets, 5)
        XCTAssertEqual(run.plannedSets, 5)
    }

    func testTheRestIsTheOneOfTheExerciseJustDone() {
        var run = WorkoutRun(session: session)
        run.begin()
        run.complete(done(run), now: t0)
        XCTAssertEqual(run.rest?.remaining(at: t0), 120)
        run.next()
        run.complete(done(run), now: t0)  // the last squat set, then bridge follows
        XCTAssertEqual(run.rest?.remaining(at: t0), 120)
        XCTAssertEqual(run.upcoming, .exercise(session.exercises[1]))
    }

    func testThereIsNoRestAfterTheVeryLastSet() {
        var run = WorkoutRun(session: session)
        run.begin(atExercise: 2)
        run.complete(done(run), now: t0)
        XCTAssertNil(run.rest)
        XCTAssertEqual(run.upcoming, .finished)
        run.next()
        XCTAssertEqual(run.phase, .finished)
    }

    func testWhatComesNext() {
        var run = WorkoutRun(session: session)
        run.begin()
        run.complete(done(run), now: t0)
        XCTAssertEqual(run.upcoming, .set(number: 2, of: 2))
    }

    func testStartingFromAnExerciseLeavesTheEarlierOnesOut() {
        var run = WorkoutRun(session: session)
        run.begin(atExercise: 1)
        XCTAssertEqual(run.currentExercise?.exerciseId, "bridge")
        XCTAssertEqual(run.plannedSets, 3, "bridge 2 + plank 1")
    }

    func testSkippingAnExerciseKeepsItsSetsAndMovesOn() {
        var run = WorkoutRun(session: session)
        run.begin()
        run.complete(done(run), now: t0)
        run.skipExercise()  // while resting after set 1 of the squat
        XCTAssertEqual(run.phase, .performing)
        XCTAssertEqual(run.currentExercise?.exerciseId, "bridge")
        XCTAssertEqual(run.setIndex, 1)
        XCTAssertEqual(run.completedSets, 1, "the squat set already done stays")
        XCTAssertEqual(run.plannedSets, 4, "bridge 2 + plank 1, and the one squat set already done")
        XCTAssertNil(run.rest)
    }

    func testSkippingTheLastExerciseFinishes() {
        var run = WorkoutRun(session: session)
        run.begin(atExercise: 2)
        run.skipExercise()
        XCTAssertEqual(run.phase, .finished)
    }

    func testFinishingEarlyKeepsWhatWasDone() {
        var run = WorkoutRun(session: session)
        run.begin()
        run.complete(done(run), now: t0)
        run.finish()
        XCTAssertEqual(run.phase, .finished)
        XCTAssertEqual(run.completedSets, 1)
        XCTAssertEqual(run.plannedSets, 5)
    }

    func testCorrectingASetReplacesItNotAddsIt() {
        var run = WorkoutRun(session: session)
        run.begin()
        var first = done(run, reps: 6)
        run.complete(first, now: t0)
        first.reps = 7
        first.weightKg = 20
        run.update(first)
        XCTAssertEqual(run.sets.count, 1)
        XCTAssertEqual(run.lastSet?.reps, 7)
        XCTAssertEqual(run.lastSet?.weightKg, 20)
    }

    func testMovesThatDoNotFitThePhaseAreIgnored() {
        var run = WorkoutRun(session: session)
        run.next()  // nothing to leave yet
        XCTAssertEqual(run.phase, .overview)
        run.complete(LoggedSet(sessionId: session.id, exerciseId: "squat", setIndex: 1), now: t0)
        XCTAssertEqual(run.completedSets, 0, "a set cannot be done before the session started")
        run.begin()
        run.next()  // still performing: there is no rest to leave
        XCTAssertEqual(run.phase, .performing)
    }

    func testTheRestCanBeChangedOnlyWhileResting() {
        var run = WorkoutRun(session: session)
        run.begin()
        run.extendRest(by: 15, now: t0)  // no rest yet
        XCTAssertNil(run.rest)
        run.complete(done(run), now: t0)
        run.extendRest(by: 15, now: t0)
        XCTAssertEqual(run.rest?.remaining(at: t0), 135)
        run.skipRest(now: t0)
        XCTAssertEqual(run.rest?.isFinished(at: t0), true)
    }
}
