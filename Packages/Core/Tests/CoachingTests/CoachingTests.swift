@testable import API
import Contracts
import XCTest
@testable import Coaching

// MARK: shared fakes

/// Scripted backend: each call of `chatStream` plays the next entry and records the request.
final class FakeBackend: CoachBackend, @unchecked Sendable {
    enum Step {
        case events([ChatEvent])
        /// Events, then the stream fails (like a dropped connection).
        case eventsThenFailure([ChatEvent], Error)
        /// The request is refused before any event (HTTP error).
        case failure(Error)
    }

    private let lock = NSLock()
    private var script: [Step]
    private(set) var requests: [ChatRequest] = []

    init(_ script: [Step]) { self.script = script }

    func chatStream(_ request: ChatRequest) -> AsyncThrowingStream<ChatEvent, Error> {
        lock.lock()
        requests.append(request)
        let step = script.isEmpty ? Step.events([.done(stopReason: "end_turn", usage: ChatUsage(inputTokens: 0, outputTokens: 0))]) : script.removeFirst()
        lock.unlock()
        return AsyncThrowingStream { continuation in
            switch step {
            case .events(let events):
                events.forEach { continuation.yield($0) }
                continuation.finish()
            case .eventsThenFailure(let events, let error):
                events.forEach { continuation.yield($0) }
                continuation.finish(throwing: error)
            case .failure(let error):
                continuation.finish(throwing: error)
            }
        }
    }
}

let usage = ChatUsage(inputTokens: 10, outputTokens: 5)

func answer(_ pieces: String...) -> FakeBackend.Step {
    .events(pieces.map { .delta($0) } + [.done(stopReason: "end_turn", usage: usage)])
}

func toolCall(_ id: String, _ name: String, _ input: [String: JSONValue] = [:], saying: String? = nil) -> FakeBackend.Step {
    var events: [ChatEvent] = []
    if let saying { events.append(.delta(saying)) }
    events.append(.toolUse(API.ToolCall(id: id, name: name, input: .object(input))))
    events.append(.done(stopReason: "tool_use", usage: usage))
    return .events(events)
}

/// Records what a tool runner was asked and answers with a fixed output.
final class FakeTools: CoachToolRunning, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var calls: [String] = []
    var outputs: [String: CoachToolOutput] = [:]

    func run(name: String, input: JSONValue) async -> CoachToolOutput {
        lock.lock(); calls.append(name); lock.unlock()
        return outputs[name] ?? CoachToolOutput(content: "{}", sourceLabel: name)
    }
}

struct FixedProfile {
    static let value = SampleData.profile
}

func collect(_ stream: AsyncThrowingStream<CoachEvent, Error>) async throws -> (deltas: String, checks: [String], reply: CoachReply?) {
    var deltas = "", checks: [String] = [], reply: CoachReply?
    for try await event in stream {
        switch event {
        case .delta(let piece): deltas += piece
        case .checking(let label): checks.append(label)
        case .finished(let finished): reply = finished
        }
    }
    return (deltas, checks, reply)
}

func makeChat(_ backend: FakeBackend, tools: CoachToolRunning = FakeTools(), consent: Bool = false,
              maxToolRounds: Int = 4) -> CoachChat {
    CoachChat(backend: backend, tools: tools, profile: { FixedProfile.value }, recommendation: SampleServices(),
              hasHealthConsent: { consent }, maxToolRounds: maxToolRounds)
}

func tempFile(_ name: String) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("forma-tests-\(UUID().uuidString)").appendingPathComponent(name)
}

// MARK: consent

final class ConsentStoreTests: XCTestCase {
    func testStartsUndecided() {
        let store = ConsentStore(fileURL: tempFile("consent.json"))
        XCTAssertFalse(store.isDecided)
        XCTAssertFalse(store.isGranted)
    }

    func testGrantingIsRememberedAcrossLaunches() {
        let url = tempFile("consent.json")
        XCTAssertTrue(ConsentStore(fileURL: url).setGranted(true))
        let again = ConsentStore(fileURL: url)
        XCTAssertTrue(again.isGranted)
        XCTAssertTrue(again.isDecided)
        XCTAssertNotNil(again.current.date)
    }

    func testDecliningIsADecisionButNotConsent() {
        let url = tempFile("consent.json")
        ConsentStore(fileURL: url).setGranted(false)
        let again = ConsentStore(fileURL: url)
        XCTAssertTrue(again.isDecided)
        XCTAssertFalse(again.isGranted)
    }

    func testWithdrawingConsent() {
        let store = ConsentStore(fileURL: tempFile("consent.json"))
        store.setGranted(true)
        store.setGranted(false)
        XCTAssertFalse(store.isGranted)
        XCTAssertTrue(store.isDecided)
    }

    func testResetGoesBackToUndecidedAndRemovesTheFile() {
        let url = tempFile("consent.json")
        let store = ConsentStore(fileURL: url)
        store.setGranted(true)
        store.reset()
        XCTAssertFalse(store.isDecided)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertFalse(ConsentStore(fileURL: url).isGranted)
    }

    func testGrantedWithoutADateIsNotConsent() throws {
        let url = tempFile("consent.json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"granted": true}"#.utf8).write(to: url)
        XCTAssertFalse(ConsentStore(fileURL: url).isGranted)
    }

    func testCorruptFileMeansUndecided() throws {
        let url = tempFile("consent.json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)
        XCTAssertFalse(ConsentStore(fileURL: url).isDecided)
    }

    func testInMemoryStoreWorksWithoutAFile() {
        let store = ConsentStore(fileURL: nil)
        XCTAssertTrue(store.setGranted(true))
        XCTAssertTrue(store.isGranted)
    }
}

// MARK: history

final class CoachHistoryStoreTests: XCTestCase {
    func testMessagesSurviveARestart() async {
        let url = tempFile("chat.json")
        let store = CoachHistoryStore(fileURL: url)
        await store.append([ChatMessage(role: .user, text: "Hej"), ChatMessage(role: .coach, text: "Cześć", sources: ["plan treningowy"])])
        let loaded = await CoachHistoryStore(fileURL: url).all()
        XCTAssertEqual(loaded.map(\.text), ["Hej", "Cześć"])
        XCTAssertEqual(loaded.last?.sources, ["plan treningowy"])
    }

    func testOnlyTheNewestMessagesAreKept() async {
        let store = CoachHistoryStore(fileURL: nil)
        await store.append((0..<(CoachHistoryStore.maxMessages + 25)).map { ChatMessage(role: .user, text: "m\($0)") })
        let all = await store.all()
        XCTAssertEqual(all.count, CoachHistoryStore.maxMessages)
        XCTAssertEqual(all.last?.text, "m\(CoachHistoryStore.maxMessages + 24)")
    }

    func testClearRemovesEverythingIncludingTheFile() async {
        let url = tempFile("chat.json")
        let store = CoachHistoryStore(fileURL: url)
        await store.append([ChatMessage(role: .user, text: "Hej")])
        await store.clear()
        let isEmpty = await store.all().isEmpty
        XCTAssertTrue(isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testCorruptFileMeansAnEmptyConversation() async throws {
        let url = tempFile("chat.json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("garbage".utf8).write(to: url)
        let all = await CoachHistoryStore(fileURL: url).all()
        XCTAssertTrue(all.isEmpty)
    }
}

// MARK: tools

/// Counts reads, so a test can prove health data was not touched.
final class Reads: @unchecked Sendable {
    private let lock = NSLock()
    private var names: [String] = []
    func note(_ name: String) { lock.lock(); names.append(name); lock.unlock() }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return names }
}

struct SpyRecovery: RecoveryProviding {
    let reads: Reads
    var snapshots: [RecoverySnapshot] = SampleData.recovery
    func snapshots(days: Int) async -> [RecoverySnapshot] { reads.note("recovery"); return Array(snapshots.prefix(days)) }
}

struct SpyCheckIns: CheckInProviding {
    let reads: Reads
    var entries: [CheckIn]
    func checkIns(days: Int) async -> [CheckIn] { reads.note("checkIns"); return entries }
}

struct SpyRecommendation: RecommendationProviding {
    let reads: Reads
    func todayRecommendation() async -> DailyRecommendation { reads.note("recommendation"); return SampleData.recommendation }
}

struct FixedTechnique: TechniqueHistoryProviding {
    var results: [TechniqueResult] = [SampleData.technique]
    var sets: [SetSummary] = []
    func results(limit: Int) async -> [TechniqueResult] { Array(results.prefix(limit)) }
    func setSummaries(limit: Int) async -> [SetSummary] { Array(sets.prefix(limit)) }
}

final class CoachToolsTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    /// 2026-10-05, a Monday.
    private let monday = Date(timeIntervalSince1970: 1_790_000_000)

    private func tools(consent: Bool, reads: Reads = Reads(), checkIns: [CheckIn]? = nil,
                       technique: FixedTechnique = FixedTechnique()) -> CoachTools {
        CoachTools(plan: SampleServices(), catalog: SampleServices(), recovery: SpyRecovery(reads: reads),
                   checkIns: SpyCheckIns(reads: reads, entries: checkIns ?? [SampleData.checkIn]), technique: technique,
                   recommendation: SpyRecommendation(reads: reads), hasHealthConsent: { consent },
                   calendar: calendar, now: { self.monday })
    }

    private func json(_ output: CoachToolOutput) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(output.content.utf8))
    }

    func testHealthToolsRefuseWithoutConsentAndDoNotReadAnything() async throws {
        let reads = Reads()
        let tools = tools(consent: false, reads: reads)
        for name in CoachToolName.health {
            let output = await tools.run(name: name, input: .object([:]))
            XCTAssertTrue(output.isError, name)
            XCTAssertNil(output.sourceLabel, name)
            XCTAssertNotNil(try json(output)["error"], name)
        }
        XCTAssertEqual(reads.all, [])
    }

    func testNonHealthToolsWorkWithoutConsent() async {
        let tools = tools(consent: false)
        let plan = await tools.run(name: CoachToolName.currentPlan, input: .object([:]))
        let technique = await tools.run(name: CoachToolName.techniqueHistory, input: .object([:]))
        XCTAssertFalse(plan.isError)
        XCTAssertFalse(technique.isError)
    }

    func testUnknownToolIsAnError() async {
        let output = await tools(consent: true).run(name: "delete_everything", input: .object([:]))
        XCTAssertTrue(output.isError)
    }

    func testPlanListsNamesNotOnlyIdsAndMarksToday() async throws {
        let output = await tools(consent: false).run(name: CoachToolName.currentPlan, input: .object([:]))
        let value = try json(output)
        guard case .array(let sessions)? = value["sessions"] else { return XCTFail("no sessions") }
        XCTAssertEqual(sessions.count, SampleData.plan.sessions.count)
        let monday = try XCTUnwrap(sessions.first { $0["weekday"]?.intValue == 1 })
        XCTAssertEqual(monday["today"], .bool(true))
        XCTAssertEqual(monday["dayName"]?.stringValue, "poniedziałek")
        guard case .array(let exercises)? = monday["exercises"] else { return XCTFail("no exercises") }
        XCTAssertEqual(exercises.first?["name"]?.stringValue, "Przysiad")
        XCTAssertEqual(output.sourceLabel, "plan treningowy")
        let wednesday = try XCTUnwrap(sessions.first { $0["weekday"]?.intValue == 3 })
        XCTAssertEqual(wednesday["today"], .bool(false))
    }

    func testTimedExerciseIsDescribedInSeconds() async throws {
        // `plank` is a timed exercise in the bundled catalog, not in the sample one; use a catalog that says so.
        struct TimedCatalog: ExerciseCatalogProviding {
            var exercises: [ExerciseItem] {
                var plank = ExerciseItem(id: "plank", name: "Plank", muscleGroup: "Brzuch", equipment: .none, level: .beginner, summary: "")
                plank.timed = true
                return [plank]
            }
        }
        let tools = CoachTools(plan: SampleServices(), catalog: TimedCatalog(), recovery: SpyRecovery(reads: Reads()),
                               checkIns: SpyCheckIns(reads: Reads(), entries: []), technique: FixedTechnique(),
                               recommendation: SpyRecommendation(reads: Reads()), hasHealthConsent: { false },
                               calendar: calendar, now: { self.monday })
        let output = await tools.run(name: CoachToolName.currentPlan, input: .object([:]))
        XCTAssertTrue(output.content.contains("durationSeconds"))
        XCTAssertTrue(output.content.contains("30–45"))
    }

    func testCheckInNotesNeverLeaveThePhone() async throws {
        let note = CheckIn(date: monday, mood: 2, stress: 5, energy: 1, note: "boli mnie kolano po pracy")
        let output = await tools(consent: true, checkIns: [note]).run(name: CoachToolName.checkIns, input: .object([:]))
        XCTAssertFalse(output.content.contains("kolano"))
        XCTAssertFalse(output.content.contains("note"))
        let value = try json(output)
        XCTAssertEqual(value["average"]?["stress"]?.doubleValue, 5)
        XCTAssertEqual(output.sourceLabel, "check-iny z 7 dni")
    }

    func testRecoverySummaryHasNumbersAgainstTheBaseline() async throws {
        let output = await tools(consent: true).run(name: CoachToolName.recoverySummary, input: .object(["days": .number(5)]))
        let value = try json(output)
        XCTAssertEqual(value["days"]?.intValue, 5)
        XCTAssertEqual(value["lastNight"]?["sleepMinutes"]?.intValue, SampleData.today.sleepMinutes)
        XCTAssertEqual(value["hrv"]?["lastMs"]?.intValue, 38)
        XCTAssertEqual(value["hrv"]?["baselineMs"]?.intValue, 46)
        XCTAssertEqual(value["hrv"]?["percentVsBaseline"]?.intValue, -17)
        XCTAssertEqual(output.sourceLabel, "regeneracja z 5 dni")
        XCTAssertTrue(output.isSimulated)
    }

    func testDaysAreClampedToTheRange() async throws {
        let tools = tools(consent: true)
        let tooMany = await tools.run(name: CoachToolName.recoverySummary, input: .object(["days": .number(500)]))
        XCTAssertEqual(try json(tooMany)["days"]?.intValue, 14)
        let nonsense = await tools.run(name: CoachToolName.recoverySummary, input: .object(["days": .number(-3)]))
        XCTAssertEqual(try json(nonsense)["days"]?.intValue, 1)
        let missing = await tools.run(name: CoachToolName.recoverySummary, input: .null)
        XCTAssertEqual(try json(missing)["days"]?.intValue, 7)
    }

    func testRecoveryWithoutDataSaysSo() async throws {
        let reads = Reads()
        let empty = CoachTools(plan: SampleServices(), catalog: SampleServices(), recovery: SpyRecovery(reads: reads, snapshots: []),
                               checkIns: SpyCheckIns(reads: reads, entries: []), technique: FixedTechnique(),
                               recommendation: SpyRecommendation(reads: reads), hasHealthConsent: { true })
        let output = await empty.run(name: CoachToolName.recoverySummary, input: .object([:]))
        XCTAssertFalse(output.isError)
        XCTAssertNotNil(try json(output)["note"])
    }

    func testRecommendationToolCarriesDecisionAndFactors() async throws {
        let output = await tools(consent: true).run(name: CoachToolName.todayRecommendation, input: .object([:]))
        let value = try json(output)
        XCTAssertEqual(value["decision"]?.stringValue, "adapt")
        XCTAssertEqual(value["decisionLabel"]?.stringValue, "Zmodyfikuj")
        guard case .array(let factors)? = value["factors"] else { return XCTFail("no factors") }
        XCTAssertEqual(factors.count, SampleData.recommendation.factors.count)
        XCTAssertTrue(output.isSimulated)
    }

    func testTechniqueHistoryFiltersByExerciseAndShowsNames() async throws {
        let other = TechniqueResult(exerciseId: "pushup", date: monday, score: 90, componentScores: [:], findings: [], reps: [])
        let tools = tools(consent: false, technique: FixedTechnique(results: [SampleData.technique, other]))
        let all = try json(await tools.run(name: CoachToolName.techniqueHistory, input: .object([:])))
        guard case .array(let analyses)? = all["analyses"] else { return XCTFail("no analyses") }
        XCTAssertEqual(analyses.count, 2)

        let only = await tools.run(name: CoachToolName.techniqueHistory, input: .object(["exerciseId": .string("squat")]))
        guard case .array(let filtered)? = try json(only)["analyses"] else { return XCTFail("no analyses") }
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?["exercise"]?.stringValue, "Przysiad")
        XCTAssertEqual(filtered.first?["suggestedSubstitute"]?.stringValue, "Przysiad kielichowy")
        XCTAssertEqual(filtered.first?["score"]?.intValue, 72)
        XCTAssertEqual(only.sourceLabel, "analizy techniki: Przysiad")
        XCTAssertTrue(only.isSimulated)
    }
}

// MARK: the conversation loop

final class CoachChatTests: XCTestCase {
    func testPlainAnswerIsStreamedAndFinished() async throws {
        let backend = FakeBackend([answer("Przysiad ", "możesz zastąpić kielichowym.")])
        let result = try await collect(makeChat(backend).reply(to: "Czym zastąpić przysiad?", history: []))
        XCTAssertEqual(result.deltas, "Przysiad możesz zastąpić kielichowym.")
        XCTAssertEqual(result.reply?.text, "Przysiad możesz zastąpić kielichowym.")
        XCTAssertEqual(result.reply?.sources, [])
        XCTAssertEqual(result.reply?.isSimulated, false)
        XCTAssertEqual(backend.requests.count, 1)
        XCTAssertEqual(backend.requests[0].messages, [.user("Czym zastąpić przysiad?")])
    }

    func testToolRoundTripSendsTheResultBackAndAnswers() async throws {
        let tools = FakeTools()
        tools.outputs["get_current_plan"] = CoachToolOutput(content: #"{"today":"Nogi"}"#, sourceLabel: "plan treningowy")
        let backend = FakeBackend([toolCall("c1", "get_current_plan", saying: "Sprawdzę plan."), answer("Dziś masz nogi.")])
        let result = try await collect(makeChat(backend, tools: tools).reply(to: "Co mam dziś?", history: []))

        XCTAssertEqual(tools.calls, ["get_current_plan"])
        XCTAssertEqual(result.checks, ["plan treningowy"])
        XCTAssertEqual(result.deltas, "Sprawdzę plan.\n\nDziś masz nogi.")
        XCTAssertEqual(result.reply?.sources, ["plan treningowy"])

        XCTAssertEqual(backend.requests.count, 2)
        let second = backend.requests[1].messages
        XCTAssertEqual(second.count, 3)
        XCTAssertEqual(second[1], WireMessage(role: .assistant, blocks: [.text("Sprawdzę plan."), .toolUse(id: "c1", name: "get_current_plan", input: .object([:]))]))
        XCTAssertEqual(second[2], WireMessage(role: .user, blocks: [.toolResult(toolUseId: "c1", content: #"{"today":"Nogi"}"#, isError: false)]))
    }

    func testTwoToolsInOneStepAreBothAnswered() async throws {
        let tools = FakeTools()
        let calls: FakeBackend.Step = .events([
            .toolUse(API.ToolCall(id: "a", name: "get_current_plan", input: .object([:]))),
            .toolUse(API.ToolCall(id: "b", name: "get_technique_history", input: .object([:]))),
            .done(stopReason: "tool_use", usage: usage),
        ])
        let backend = FakeBackend([calls, answer("Gotowe.")])
        let result = try await collect(makeChat(backend, tools: tools).reply(to: "Nad czym popracować?", history: []))
        XCTAssertEqual(tools.calls, ["get_current_plan", "get_technique_history"])
        XCTAssertEqual(result.reply?.sources, ["get_current_plan", "get_technique_history"])
        guard case .toolResult(let id, _, _)? = backend.requests[1].messages.last?.blocks.last else { return XCTFail("no result") }
        XCTAssertEqual(id, "b")
        XCTAssertEqual(backend.requests[1].messages.last?.blocks.count, 2)
    }

    func testAnswerBasedOnASimulatedRecommendationInTheContextIsMarkedToo() async throws {
        let withConsent = try await collect(makeChat(FakeBackend([answer("Lżej dziś.")]), consent: true).reply(to: "Hej", history: []))
        XCTAssertEqual(withConsent.reply?.isSimulated, true)  // SampleData.recommendation is simulated
        let withoutConsent = try await collect(makeChat(FakeBackend([answer("Cześć.")]), consent: false).reply(to: "Hej", history: []))
        XCTAssertEqual(withoutConsent.reply?.isSimulated, false)  // nothing simulated was sent
    }

    func testSampleDataMarksTheAnswerAsSimulated() async throws {
        let tools = FakeTools()
        tools.outputs["get_recovery_summary"] = CoachToolOutput(content: "{}", sourceLabel: "regeneracja z 7 dni", isSimulated: true)
        let backend = FakeBackend([toolCall("c1", "get_recovery_summary"), answer("Spałaś krótko.")])
        let result = try await collect(makeChat(backend, tools: tools, consent: true).reply(to: "Jak spałam?", history: []))
        XCTAssertEqual(result.reply?.isSimulated, true)
    }

    // MARK: consent

    func testWithoutConsentNoHealthContextIsSent() async throws {
        let backend = FakeBackend([answer("Cześć.")])
        _ = try await collect(makeChat(backend, consent: false).reply(to: "Hej", history: []))
        XCTAssertFalse(backend.requests[0].consent.health)
        XCTAssertNil(backend.requests[0].context?.todayRecommendation)
        XCTAssertEqual(backend.requests[0].context?.profile, SampleData.profile)
    }

    func testWithConsentTheRecommendationAndTheFlagAreSent() async throws {
        let backend = FakeBackend([answer("Cześć.")])
        _ = try await collect(makeChat(backend, consent: true).reply(to: "Hej", history: []))
        XCTAssertTrue(backend.requests[0].consent.health)
        XCTAssertEqual(backend.requests[0].context?.todayRecommendation, SampleData.recommendation)
    }

    func testConsentWithdrawnBetweenRoundsIsRespected() async throws {
        let flag = ConsentFlag()
        let tools = FakeTools()
        let backend = FakeBackend([toolCall("c1", "get_checkins"), answer("Ok.")])
        let chat = CoachChat(backend: backend, tools: ConsentFlippingTools(inner: tools, flag: flag), profile: { SampleData.profile },
                             recommendation: SampleServices(), hasHealthConsent: { flag.on })
        _ = try await collect(chat.reply(to: "Jak się czuję?", history: []))
        XCTAssertTrue(backend.requests[0].consent.health)
        XCTAssertFalse(backend.requests[1].consent.health)
        XCTAssertNil(backend.requests[1].context?.todayRecommendation)
    }

    // MARK: failures

    func testRequestRefusedBeforeTheStreamBecomesAnApiError() async {
        let error = APIError.server(ServerError(code: "ai_unavailable", message: "Trener jest chwilowo niedostępny."), status: 503, retryAfter: 5)
        let backend = FakeBackend([.failure(error)])
        do {
            _ = try await collect(makeChat(backend).reply(to: "Hej", history: []))
            XCTFail("should fail")
        } catch let failure as CoachChatError {
            XCTAssertEqual(failure, .api(error))
            XCTAssertTrue(failure.isRetryable)
            XCTAssertEqual(failure.userMessage, "Trener jest chwilowo niedostępny.")
        } catch {
            XCTFail("\(error)")
        }
    }

    func testNoNetworkIsRetryableWithAPolishMessage() async {
        let backend = FakeBackend([.failure(APIError.transport("offline"))])
        do {
            _ = try await collect(makeChat(backend).reply(to: "Hej", history: []))
            XCTFail("should fail")
        } catch let failure as CoachChatError {
            XCTAssertTrue(failure.isRetryable)
            XCTAssertTrue(failure.userMessage.contains("połączenia"))
        } catch {
            XCTFail("\(error)")
        }
    }

    func testConsentRequiredFromTheServerIsRecognised() async {
        let error = APIError.server(ServerError(code: "consent_required", message: "Zgoda wyłączona."), status: 422, retryAfter: nil)
        let backend = FakeBackend([.failure(error)])
        do {
            _ = try await collect(makeChat(backend).reply(to: "Hej", history: []))
            XCTFail("should fail")
        } catch let failure as CoachChatError {
            XCTAssertTrue(failure.isConsentProblem)
            XCTAssertFalse(failure.isRetryable)
        } catch {
            XCTFail("\(error)")
        }
    }

    func testErrorEventAfterSomeTextKeepsThePartialAnswer() async {
        let server = ServerError(code: "ai_unavailable", message: "Trener jest chwilowo niedostępny.", requestId: "r1")
        let backend = FakeBackend([.events([.delta("Zaczynam "), .error(server)])])
        var seen = ""
        do {
            for try await event in makeChat(backend).reply(to: "Hej", history: []) {
                if case .delta(let piece) = event { seen += piece }
            }
            XCTFail("should fail")
        } catch let failure as CoachChatError {
            XCTAssertEqual(failure, .interrupted(server, partial: "Zaczynam "))
            XCTAssertEqual(seen, "Zaczynam ")
        } catch {
            XCTFail("\(error)")
        }
    }

    func testEmptyAnswerIsAnError() async {
        let backend = FakeBackend([.events([.done(stopReason: "end_turn", usage: usage)])])
        do {
            _ = try await collect(makeChat(backend).reply(to: "Hej", history: []))
            XCTFail("should fail")
        } catch let failure as CoachChatError {
            XCTAssertEqual(failure, .emptyAnswer)
        } catch {
            XCTFail("\(error)")
        }
    }

    func testEndlessToolRequestsStop() async {
        let step = toolCall("c", "get_current_plan")
        let backend = FakeBackend([step, step, step, step, step, step])
        do {
            _ = try await collect(makeChat(backend, maxToolRounds: 2).reply(to: "Hej", history: []))
            XCTFail("should fail")
        } catch let failure as CoachChatError {
            XCTAssertEqual(failure, .tooManyToolRounds)
            XCTAssertEqual(backend.requests.count, 3)
        } catch {
            XCTFail("\(error)")
        }
    }

    func testCutOffAnswerIsFlagged() async throws {
        let backend = FakeBackend([.events([.delta("Długa odpowiedź bez końca"), .done(stopReason: "max_tokens", usage: usage)])])
        let result = try await collect(makeChat(backend).reply(to: "Hej", history: []))
        XCTAssertEqual(result.reply?.isTruncated, true)
    }

    func testCancellingStopsTheRequestLoop() async throws {
        let backend = FakeBackend([toolCall("c", "get_current_plan"), answer("nie powinno dojść")])
        let stream = makeChat(backend).reply(to: "Hej", history: [])
        let task = Task { try await collect(stream) }
        task.cancel()
        _ = try? await task.value
        XCTAssertLessThanOrEqual(backend.requests.count, 2)
    }

    // MARK: history

    func testHistoryIsSentAsPlainTextWithoutToolBlocks() async throws {
        let history = [
            ChatMessage(role: .user, text: "Hej"),
            ChatMessage(role: .coach, text: "Cześć! Jak mogę pomóc?", sources: ["plan treningowy"]),
        ]
        let backend = FakeBackend([answer("Jasne.")])
        _ = try await collect(makeChat(backend).reply(to: "Co z planem?", history: history))
        XCTAssertEqual(backend.requests[0].messages, [.user("Hej"), .assistant("Cześć! Jak mogę pomóc?"), .user("Co z planem?")])
    }

    func testWireHistoryStartsWithTheUserAndMergesNeighbours() {
        let history = [
            ChatMessage(role: .coach, text: "Zostało po starej rozmowie"),
            ChatMessage(role: .user, text: "Pierwsze"),
            ChatMessage(role: .user, text: "Drugie"),
            ChatMessage(role: .coach, text: "Odpowiedź"),
            ChatMessage(role: .coach, text: "   "),
        ]
        let wire = CoachChat.wireHistory(from: history)
        XCTAssertEqual(wire, [.user("Pierwsze\nDrugie"), .assistant("Odpowiedź")])
    }

    func testAnUnansweredQuestionIsAskedTogetherWithTheNewOne() async throws {
        let backend = FakeBackend([answer("Dobrze.")])
        let history = [ChatMessage(role: .user, text: "Czy ćwiczyć?")]
        _ = try await collect(makeChat(backend).reply(to: "Halo?", history: history))
        XCTAssertEqual(backend.requests[0].messages, [.user("Czy ćwiczyć?\nHalo?")])
    }

    func testLongHistoryIsTrimmedToTheServerLimits() {
        let long = String(repeating: "a", count: 3000)
        let history = (0..<60).map { ChatMessage(role: $0 % 2 == 0 ? .user : .coach, text: long + "\($0)") }
        let wire = CoachChat.wireHistory(from: history)
        XCTAssertLessThanOrEqual(wire.count, CoachChat.maxHistoryMessages)
        let total = wire.reduce(0) { sum, message in
            sum + message.blocks.reduce(0) { if case .text(let t) = $1 { return $0 + t.count } else { return $0 } }
        }
        XCTAssertLessThanOrEqual(total, CoachChat.maxHistoryCharacters)
        XCTAssertEqual(wire.first?.role, .user)
        guard case .text(let newest)? = wire.last?.blocks.first else { return XCTFail("empty history") }
        XCTAssertTrue(newest.hasSuffix("59"), "the newest message must survive trimming")
    }

    func testVeryLongUserTextIsClippedBelowTheBlockLimit() async throws {
        let backend = FakeBackend([answer("Ok.")])
        _ = try await collect(makeChat(backend).reply(to: String(repeating: "x", count: 9000), history: []))
        guard case .text(let text)? = backend.requests[0].messages.first?.blocks.first else { return XCTFail("no text") }
        XCTAssertEqual(text.count, CoachChat.maxTextCharacters)
    }
}

final class ConsentFlag: @unchecked Sendable {
    var on = true
}

/// Withdraws consent as soon as a tool ran, to check that the next request notices.
struct ConsentFlippingTools: CoachToolRunning {
    let inner: FakeTools
    let flag: ConsentFlag

    func run(name: String, input: JSONValue) async -> CoachToolOutput {
        let output = await inner.run(name: name, input: input)
        flag.on = false
        return output
    }
}
