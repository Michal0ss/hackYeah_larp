import XCTest
import Contracts
@testable import Insights

// MARK: Shared corpus (also checked by backend/scripts/check_texts.py)

private struct Corpus: Decodable {
    struct Bad: Decodable { var text: String; var category: String }
    struct Contradiction: Decodable { var decision: String; var text: String }
    struct Number: Decodable { var source: String; var text: String; var invented: Bool }
    var bad: [Bad]
    var good: [String]
    var contradictions: [Contradiction]
    var numbers: [Number]

    static func load() throws -> Corpus {
        // Packages/Core/Tests/InsightsTests/<file> -> repo root is five levels up from the file.
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        url.appendPathComponent("backend/scripts/text_safety_corpus.json")
        return try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: url))
    }
}

final class TextGuardTests: XCTestCase {
    func testEveryBadPhraseIsCaughtInItsCategory() throws {
        for item in try Corpus.load().bad {
            let problems = TextGuard.problems(in: [item.text])
            XCTAssertTrue(problems.contains("unsafe_phrase:\(item.category)"), "\(item.text) -> \(problems)")
        }
    }

    func testGoodPhrasesPass() throws {
        for text in try Corpus.load().good {
            XCTAssertEqual(TextGuard.problems(in: [text]), [], text)
        }
    }

    func testContradictionsWithTheDecisionAreCaught() throws {
        for item in try Corpus.load().contradictions {
            let decision = try XCTUnwrap(Decision(rawValue: item.decision))
            XCTAssertTrue(TextGuard.problems(in: [item.text], decision: decision).contains("contradicts_decision"), item.text)
        }
    }

    func testInventedNumbers() throws {
        for item in try Corpus.load().numbers {
            let flagged = TextGuard.problems(in: [item.text], source: item.source).contains("invented_number")
            XCTAssertEqual(flagged, item.invented, "\(item.text) vs \(item.source)")
        }
    }

    func testEmptyAndTooLong() {
        XCTAssertTrue(TextGuard.problems(in: ["Dziś lżejszy trening", "  "]).contains("empty"))
        XCTAssertTrue(TextGuard.problems(in: [String(repeating: "słowo ", count: 150)]).contains("too_long"))
    }

    func testCareHintIsRequiredWhenTheEngineRaisedAFlag() {
        let rec = Fixtures.care
        XCTAssertTrue(TextGuard.problems(headline: "Trening z uwagą", explanation: "Zrób dziś lżejszą wersję.", for: rec)
            .contains("missing_care_hint"))
        XCTAssertEqual(TextGuard.problems(headline: "Trening z uwagą",
                                          explanation: "Zrób dziś lżejszą wersję. Warto rozważyć konsultację z fizjoterapeutą.",
                                          for: rec), [])
    }
}

// MARK: Fixtures

enum Fixtures {
    static let day = Date(timeIntervalSince1970: 1_791_000_000)

    static func rec(_ decision: Decision, _ headline: String, _ factors: [(FactorSource, String, Bool)], _ action: String,
                    care: String? = nil, simulated: Bool = false) -> DailyRecommendation {
        DailyRecommendation(date: day, decision: decision, headline: headline,
                            factors: factors.map { RecommendationFactor(source: $0.0, text: $0.1, isNegative: $0.2) },
                            suggestedAction: action, careFlag: care.map { CareFlag(reason: $0) }, isSimulated: simulated)
    }

    static let prototype = rec(.adapt, "Dziś lżejszy trening",
                               [(.sleep, "Sen 5 h 40 min", true), (.hrv, "HRV 38 ms, 17% poniżej twojej średniej", true),
                                (.checkIn, "Stres 4/5", true)],
                               "Zrób o jedną serię mniej w każdym ćwiczeniu i obniż intensywność (RPE 6–7).")
    static let good = rec(.train, "Trenuj według planu", [(.sleep, "Sen 7 h 30 min", false)],
                          "Zrób dzisiejszą sesję tak, jak jest w planie.")
    static let heavy = rec(.rest, "Dziś regeneracja",
                           [(.sleep, "Sen 5 h 10 min", true), (.hrv, "HRV 31 ms, 30% poniżej twojej średniej", true)],
                           "Odpuść mocny trening. Wybierz odpoczynek albo lekką aktywność.")
    static let care = rec(.adapt, "Dziś trening z uwagą na technikę",
                          [(.technique, "Przysiad: pochylenie tułowia w 3 z 5 powtórzeń", true)],
                          "Zrób o jedną serię mniej w każdym ćwiczeniu.",
                          care: "Ten sam sygnał pojawił się w 3 analizach z ostatnich 14 dni.")
    static var simulated: DailyRecommendation { var r = prototype; r.isSimulated = true; return r }

    static let aiExplanation = "Krótki sen, niższe HRV i podwyższony stres to sygnał, że warto dziś zwolnić. Zrób o jedną serię mniej (RPE 6–7)."
}

// MARK: Engine text

final class EngineTextTests: XCTestCase {
    func testReasonThenActionKeepingTheEngineHeadline() {
        let t = EngineText.make(for: Fixtures.prototype)
        XCTAssertEqual(t.headline, "Dziś lżejszy trening")
        XCTAssertEqual(t.explanation, "Powód: sen 5 h 40 min; HRV 38 ms, 17% poniżej twojej średniej; stres 4/5. "
            + "Zrób o jedną serię mniej w każdym ćwiczeniu i obniż intensywność (RPE 6–7).")
        XCTAssertEqual(t.source, .engine)
        XCTAssertTrue(t.isTemplate)
    }

    func testGoodDayHasNoReasonLine() {
        XCTAssertEqual(EngineText.make(for: Fixtures.good).explanation, "Zrób dzisiejszą sesję tak, jak jest w planie.")
    }

    func testCareFlagAddsTheConsultationHint() {
        XCTAssertTrue(EngineText.make(for: Fixtures.care).explanation.hasSuffix("warto rozważyć konsultację z fizjoterapeutą lub lekarzem."))
    }

    func testAtMostThreeReasons() {
        let many = Fixtures.rec(.rest, "Dziś regeneracja",
                                [(.sleep, "Sen 5 h", true), (.hrv, "HRV 30 ms", true), (.restingHeartRate, "Tętno 70", true),
                                 (.checkIn, "Stres 5/5", true)], "Odpuść.")
        XCTAssertEqual(EngineText.make(for: many).explanation.components(separatedBy: ";").count, 3)
    }

    func testOurOwnTextsPassOurOwnRules() {
        for rec in [Fixtures.prototype, Fixtures.good, Fixtures.heavy, Fixtures.care] {
            let t = EngineText.make(for: rec)
            XCTAssertEqual(TextGuard.problems(headline: t.headline, explanation: t.explanation, for: rec), [], t.explanation)
        }
    }
}

// MARK: Texter

private actor FakeFetcher: RecommendationTextFetching {
    enum Behaviour { case answer(RemoteRecommendationText), slowAnswer(RemoteRecommendationText, seconds: Double), fail, hang(seconds: Double) }
    var behaviour: Behaviour
    private(set) var calls = 0

    init(_ behaviour: Behaviour) { self.behaviour = behaviour }

    func set(_ new: Behaviour) { behaviour = new }

    func fetch(_ recommendation: DailyRecommendation) async throws -> RemoteRecommendationText {
        calls += 1
        switch behaviour {
        case .answer(let remote): return remote
        case .slowAnswer(let remote, let seconds):
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return remote
        case .fail: throw URLError(.notConnectedToInternet)
        case .hang(let seconds):
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return RemoteRecommendationText(headline: "x", explanation: "y", fromModel: true)
        }
    }
}

private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date(timeIntervalSince1970: 1_791_000_000)
    var now: Date { lock.lock(); defer { lock.unlock() }; return value }
    func advance(_ seconds: TimeInterval) { lock.lock(); value = value.addingTimeInterval(seconds); lock.unlock() }
}

final class RecommendationTexterTests: XCTestCase {
    private let valid = RemoteRecommendationText(headline: "Dziś lżejszy trening", explanation: Fixtures.aiExplanation, fromModel: true)
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("forma-texter-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private func texter(_ fetcher: FakeFetcher, consent: Bool = true, clock: Clock = Clock(), file: Bool = false,
                        options: RecommendationTexter.Options = .init(timeout: 1)) -> RecommendationTexter {
        let url = file ? dir.appendingPathComponent("texts.json") : nil
        return RecommendationTexter(fetcher: fetcher, hasConsent: { consent }, options: options, cacheURL: url,
                                    now: { clock.now })
    }

    func testModelTextIsUsedWhenAllowedAndValid() async {
        let fetcher = FakeFetcher(.answer(valid))
        let t = await texter(fetcher).text(for: Fixtures.prototype)
        XCTAssertEqual(t.source, .ai)
        XCTAssertEqual(t.explanation, Fixtures.aiExplanation)
        XCTAssertEqual(t.warnings, [])
    }

    func testWithoutConsentNothingIsSentAndTheLocalTextIsUsed() async {
        let fetcher = FakeFetcher(.answer(valid))
        let t = await texter(fetcher, consent: false).text(for: Fixtures.prototype)
        let calls = await fetcher.calls
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(t, EngineText.make(for: Fixtures.prototype))
    }

    func testSimulatedDataNeedsNoConsent() async {
        let fetcher = FakeFetcher(.answer(valid))
        let t = await texter(fetcher, consent: false).text(for: Fixtures.simulated)
        let calls = await fetcher.calls
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(t.source, .ai)
    }

    func testSecondCallComesFromTheCache() async {
        let fetcher = FakeFetcher(.answer(valid))
        let texter = texter(fetcher)
        _ = await texter.text(for: Fixtures.prototype)
        let again = await texter.text(for: Fixtures.prototype)
        let calls = await fetcher.calls
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(again.source, .ai)
    }

    func testDifferentRecommendationIsFetchedAgain() async {
        let fetcher = FakeFetcher(.answer(valid))
        let texter = texter(fetcher)
        _ = await texter.text(for: Fixtures.prototype)
        _ = await texter.text(for: Fixtures.heavy)
        let calls = await fetcher.calls
        XCTAssertEqual(calls, 2)
    }

    func testCacheSurvivesARestart() async {
        let fetcher = FakeFetcher(.answer(valid))
        _ = await texter(fetcher, file: true).text(for: Fixtures.prototype)
        let second = FakeFetcher(.fail)
        let t = await texter(second, file: true).text(for: Fixtures.prototype)
        let calls = await second.calls
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(t.source, .ai)
    }

    func testOldCacheEntriesAreDropped() async {
        let clock = Clock()
        let fetcher = FakeFetcher(.answer(valid))
        _ = await texter(fetcher, clock: clock, file: true).text(for: Fixtures.prototype)
        clock.advance(4 * 86_400)
        _ = await texter(fetcher, clock: clock, file: true).text(for: Fixtures.prototype)
        let calls = await fetcher.calls
        XCTAssertEqual(calls, 2)
    }

    func testClearCacheForgetsEverything() async {
        let fetcher = FakeFetcher(.answer(valid))
        let texter = texter(fetcher, file: true)
        let file = dir.appendingPathComponent("texts.json")
        _ = await texter.text(for: Fixtures.prototype)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        await texter.clearCache()
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        _ = await texter.text(for: Fixtures.prototype)
        let calls = await fetcher.calls
        XCTAssertEqual(calls, 2)
    }

    func testOfflineFallsBackToLocalTextWithAWarning() async {
        let t = await texter(FakeFetcher(.fail)).text(for: Fixtures.prototype)
        XCTAssertEqual(t.source, .engine)
        XCTAssertEqual(t.warnings, ["offline"])
        XCTAssertEqual(t.explanation, EngineText.make(for: Fixtures.prototype).explanation)
    }

    func testTimeoutFallsBackToLocalText() async {
        let t = await texter(FakeFetcher(.hang(seconds: 5)), options: .init(timeout: 0.05)).text(for: Fixtures.prototype)
        XCTAssertEqual(t.source, .engine)
        XCTAssertEqual(t.warnings, ["timeout"])
    }

    func testFailureIsNotRepeatedDuringTheCooldownButIsAfterwards() async {
        let clock = Clock()
        let fetcher = FakeFetcher(.fail)
        let texter = texter(fetcher, clock: clock)
        _ = await texter.text(for: Fixtures.prototype)
        clock.advance(30)
        _ = await texter.text(for: Fixtures.prototype)
        var calls = await fetcher.calls
        XCTAssertEqual(calls, 1)
        clock.advance(40)
        await fetcher.set(.answer(valid))
        let t = await texter.text(for: Fixtures.prototype)
        calls = await fetcher.calls
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(t.source, .ai)
    }

    func testBackendTemplateIsReplacedByTheLocalTextAndKeepsItsWarnings() async {
        let template = RemoteRecommendationText(headline: "Dziś lżejszy trening", explanation: "szablon", fromModel: false,
                                                warnings: ["ai_mock"])
        let t = await texter(FakeFetcher(.answer(template))).text(for: Fixtures.prototype)
        XCTAssertEqual(t.source, .engine)
        XCTAssertEqual(t.warnings, ["ai_mock"])
        XCTAssertNotEqual(t.explanation, "szablon")
    }

    func testUnsafeModelTextIsRejectedOnTheDevice() async {
        let unsafe = RemoteRecommendationText(headline: "Dziś lżejszy trening",
                                              explanation: "Masz zapalenie ścięgna. Weź ibuprofen.", fromModel: true)
        let fetcher = FakeFetcher(.answer(unsafe))
        let texter = texter(fetcher)
        let t = await texter.text(for: Fixtures.prototype)
        XCTAssertEqual(t.source, .engine)
        XCTAssertEqual(t.warnings, ["ai_text_rejected_on_device"])
        XCTAssertFalse(t.explanation.contains("ibuprofen"))
    }

    func testTextThatContradictsTheDecisionIsRejected() async {
        let wrong = RemoteRecommendationText(headline: "Trenuj według planu",
                                             explanation: "Sen 5 h 40 min to nic, trenuj według planu.", fromModel: true)
        let t = await texter(FakeFetcher(.answer(wrong))).text(for: Fixtures.prototype)
        XCTAssertEqual(t.source, .engine)
    }

    func testModelTextWithoutTheCareHintIsRejected() async {
        let noHint = RemoteRecommendationText(headline: "Trening z uwagą na technikę",
                                              explanation: "Pochylenie tułowia wraca w 3 z 5 powtórzeń. Zrób dziś lżejszą wersję.",
                                              fromModel: true)
        let t = await texter(FakeFetcher(.answer(noHint))).text(for: Fixtures.care)
        XCTAssertEqual(t.source, .engine)
        XCTAssertTrue(t.explanation.contains("fizjoterapeut"))
    }

    func testConcurrentCallsShareOneRequest() async {
        let fetcher = FakeFetcher(.slowAnswer(valid, seconds: 0.3))
        let texter = texter(fetcher, options: .init(timeout: 2))
        async let a = texter.text(for: Fixtures.prototype)
        async let b = texter.text(for: Fixtures.prototype)
        async let c = texter.text(for: Fixtures.prototype)
        let results = await [a, b, c]
        let calls = await fetcher.calls
        XCTAssertEqual(calls, 1)
        XCTAssertTrue(results.allSatisfy { $0.source == .ai })
    }

    func testLocalTextIsAvailableWithoutAwaiting() {
        let t = texter(FakeFetcher(.fail)).localText(for: Fixtures.prototype)
        XCTAssertEqual(t, EngineText.make(for: Fixtures.prototype))
    }

    func testKeyChangesWithTheDecisionTheWordingAndTheDay() {
        let base = RecommendationTexter.key(for: Fixtures.prototype)
        var other = Fixtures.prototype; other.decision = .rest
        var otherAction = Fixtures.prototype; otherAction.suggestedAction += "!"
        var otherDay = Fixtures.prototype; otherDay.date = Fixtures.day.addingTimeInterval(86_400)
        XCTAssertNotEqual(base, RecommendationTexter.key(for: other))
        XCTAssertNotEqual(base, RecommendationTexter.key(for: otherAction))
        XCTAssertNotEqual(base, RecommendationTexter.key(for: otherDay))
        XCTAssertEqual(base, RecommendationTexter.key(for: Fixtures.prototype))
    }
}
