@testable import API
import Contracts
import Plan
import XCTest
@testable import Coaching

final class PainSignalTests: XCTestCase {
    func testPainAndInjuryWordsAreRecognised() {
        for text in ["Boli mnie kolano po przysiadzie", "ból w plecach", "BOL w barku", "Chyba mam kontuzję", "naciągnąłem mięsień",
                     "czuję dyskomfort w biodrze", "mam uraz nadgarstka", "strzyka mnie w łokciu", "drętwieje mi ręka"] {
            XCTAssertTrue(PainSignal.mentions(text), text)
        }
    }

    func testOrdinaryQuestionsAreNot() {
        for text in ["Czy dziś ćwiczyć nogi?", "Czym zastąpić przysiad?", "Jak poprawić technikę?", "Ile powtórzeń w serii?", "",
                     "Chcę zbudować bolce do roweru"] {
            XCTAssertFalse(PainSignal.mentions(text), text)
        }
    }

    func testTheAnswerCarriesTheConsultationFlagWhateverTheModelSays() async throws {
        let backend = FakeBackend([.events([.delta("Spróbuj lżejszego wariantu."),
                                            .done(stopReason: "end_turn", usage: ChatUsage(inputTokens: 1, outputTokens: 1))])])
        let result = try await collect(makeChat(backend).reply(to: "Boli mnie kolano, co robić?", history: []))
        XCTAssertEqual(result.reply?.suggestsConsultation, true)

        let calm = FakeBackend([.events([.delta("Tak."), .done(stopReason: "end_turn", usage: ChatUsage(inputTokens: 1, outputTokens: 1))])])
        let other = try await collect(makeChat(calm).reply(to: "Czy dziś ćwiczyć nogi?", history: []))
        XCTAssertEqual(other.reply?.suggestsConsultation, false)
    }

    func testTheFlagSurvivesSavingTheConversation() throws {
        let message = ChatMessage(role: .coach, text: "Odpowiedź", suggestsConsultation: true)
        let again = try JSONDecoder().decode(ChatMessage.self, from: JSONEncoder().encode(message))
        XCTAssertTrue(again.suggestsConsultation)
        // A conversation saved before the card existed.
        let old = #"{"id":"\#(UUID().uuidString)","role":"coach","text":"x","date":0,"sources":[]}"#
        XCTAssertFalse(try JSONDecoder().decode(ChatMessage.self, from: Data(old.utf8)).suggestsConsultation)
    }
}

final class TrainingLogToolTests: XCTestCase {
    private struct Log: SessionCompletionProviding { var completions: [SessionCompletion] }

    func testTheLogHasFinishedSessionsAndSetsFromTheLastDaysOnly() async throws {
        let now = Date()
        let plan = SampleData.plan
        let recent = SessionCompletion(sessionId: plan.sessions[0].id, date: now.addingTimeInterval(-86_400), completedSets: 3, plannedSets: 4)
        let old = SessionCompletion(sessionId: plan.sessions[1].id, date: now.addingTimeInterval(-40 * 86_400))
        let tools = CoachTools(plan: SampleServices(), catalog: SampleServices(), recovery: SampleServices(), checkIns: SampleServices(),
                               technique: SampleServices(), recommendation: SampleServices(),
                               log: Log(completions: [recent, old]), hasHealthConsent: { false }, now: { now })
        let output = await tools.run(name: CoachToolName.trainingLog, input: .object(["days": .number(14)]))
        XCTAssertFalse(output.isError)
        XCTAssertEqual(output.sourceLabel, "historia treningów")
        XCTAssertTrue(output.content.contains("\"setsDone\":3"))
        XCTAssertEqual(output.content.components(separatedBy: "\"title\"").count - 1, 1, "the 40-day-old session is left out")
    }

    func testItIsNotAHealthTool() {
        XCTAssertFalse(CoachToolName.health.contains(CoachToolName.trainingLog))
    }

    func testWithoutALogItStillAnswers() async {
        let tools = CoachTools(plan: SampleServices(), catalog: SampleServices(), recovery: SampleServices(), checkIns: SampleServices(),
                               technique: SampleServices(), recommendation: SampleServices(), hasHealthConsent: { false })
        let output = await tools.run(name: CoachToolName.trainingLog, input: .object([:]))
        XCTAssertFalse(output.isError)
    }
}
