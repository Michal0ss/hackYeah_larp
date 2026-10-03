import XCTest
@testable import CoachVoice

final class SpeechTextTests: XCTestCase {
    func test_plainTextIsUnchanged() {
        XCTAssertEqual(cleanForSpeech("Zrób trzy serie po dziesięć."), "Zrób trzy serie po dziesięć.")
    }

    func test_boldMarkersAreStripped() {
        XCTAssertEqual(cleanForSpeech("Zrób **trzy serie**."), "Zrób trzy serie.")
    }

    func test_headingHashesAreStripped() {
        XCTAssertEqual(cleanForSpeech("## Plan na dziś"), "Plan na dziś")
    }

    func test_bulletDashesAreDroppedButTextKept() {
        XCTAssertEqual(cleanForSpeech("Zrób:\n- przysiady\n- pompki"), "Zrób:. przysiady. pompki")
    }

    func test_markdownLinkKeepsOnlyLabel() {
        XCTAssertEqual(cleanForSpeech("Zobacz [plan](https://example.com) na dziś"), "Zobacz plan na dziś")
    }

    func test_emptyLinesAreDropped() {
        XCTAssertEqual(cleanForSpeech("Pierwsze\n\n\nDrugie"), "Pierwsze. Drugie")
    }
}
