import XCTest
@testable import CoachVoice

final class SentenceStreamTests: XCTestCase {
    func test_noTerminator_yieldsNothingYet() {
        var stream = SentenceStream()
        XCTAssertEqual(stream.newSentences(in: "Zrób trzy"), [])
    }

    func test_terminatorWithoutFollowingWhitespace_isNotYetASentenceBoundary() {
        // "3." could still become "3.5" on the next delta.
        var stream = SentenceStream()
        XCTAssertEqual(stream.newSentences(in: "Dodaj 3."), [])
    }

    func test_terminatorFollowedByWhitespace_completesASentence() {
        var stream = SentenceStream()
        XCTAssertEqual(stream.newSentences(in: "Zrób trzy serie. Potem"), ["Zrób trzy serie."])
    }

    func test_decimalNumberIsNotSplitMidStream() {
        var stream = SentenceStream()
        XCTAssertEqual(stream.newSentences(in: "Dodaj 3.5 kg do sztangi. Reszta"), ["Dodaj 3.5 kg do sztangi."])
    }

    func test_secondCall_onlyReturnsNewSentences() {
        var stream = SentenceStream()
        _ = stream.newSentences(in: "Pierwsze. Drugie")
        XCTAssertEqual(stream.newSentences(in: "Pierwsze. Drugie. Trzecie"), ["Drugie."])
    }

    func test_remainder_returnsTrailingTextWithoutTerminator() {
        var stream = SentenceStream()
        _ = stream.newSentences(in: "Pierwsze. Reszta bez kropki")
        XCTAssertEqual(stream.remainder(in: "Pierwsze. Reszta bez kropki"), "Reszta bez kropki")
    }

    func test_remainder_isNilWhenNothingIsLeft() {
        var stream = SentenceStream()
        _ = stream.newSentences(in: "Pierwsze. ")
        XCTAssertNil(stream.remainder(in: "Pierwsze. "))
    }

    func test_questionAndExclamationAlsoTerminate() {
        var stream = SentenceStream()
        XCTAssertEqual(stream.newSentences(in: "Czujesz to? Super! Jedziemy"), ["Czujesz to?", "Super!"])
    }
}
