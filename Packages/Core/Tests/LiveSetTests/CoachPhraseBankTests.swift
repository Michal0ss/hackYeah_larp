import XCTest
@testable import LiveSet

final class CoachPhraseBankTests: XCTestCase {
    private let bank = CoachPhraseBank(variantsByPhrase: [
        "głębiej": [
            .init(text: "głębiej", file: "a"),
            .init(text: "jeszcze głębiej", file: "b"),
            .init(text: "dojedź do końca", file: "c"),
        ],
        "jeden": [.init(text: "jeden", file: "solo")],
    ])

    func test_unknownPhrase_returnsNil() {
        XCTAssertNil(bank.pickVariant(for: "coś innego", exists: { _ in true }))
    }

    func test_knownPhraseWithNoExistingClip_returnsNil() {
        XCTAssertNil(bank.pickVariant(for: "głębiej", exists: { _ in false }))
    }

    func test_onlyExistingVariantsAreConsidered() {
        for _ in 0..<20 {
            let variant = bank.pickVariant(for: "głębiej", exists: { $0 == "b" })
            XCTAssertEqual(variant?.file, "b")
        }
    }

    func test_avoidsRepeatingTheLastClipWhenAnotherExists() {
        for _ in 0..<20 {
            let variant = bank.pickVariant(for: "głębiej", excluding: "a", exists: { _ in true })
            XCTAssertNotEqual(variant?.file, "a")
        }
    }

    func test_singleVariant_isReusedEvenWhenExcluded() {
        // "Avoid repeating" must never mean "go silent" when there is nothing else to say.
        XCTAssertEqual(bank.pickVariant(for: "jeden", excluding: "solo", exists: { _ in true })?.file, "solo")
    }

    func test_parsesManifestJSON() throws {
        let json = """
            {"voiceId": "v1", "modelId": "m1", "phrases": {"głębiej": [{"text": "głębiej", "file": "x"}]}}
            """
        let bank = CoachPhraseBank.parse(Data(json.utf8))
        XCTAssertEqual(bank?.variants(for: "głębiej"), [.init(text: "głębiej", file: "x")])
    }

    func test_malformedManifest_parsesToNil() {
        XCTAssertNil(CoachPhraseBank.parse(Data("not json".utf8)))
    }

    func test_loadBundled_fromBundleWithoutManifest_isEmpty() {
        let bank = CoachPhraseBank.loadBundled(from: Bundle(for: EmptyBundleMarker.self))
        XCTAssertTrue(bank.variants(for: "głębiej").isEmpty)
    }
}

private final class EmptyBundleMarker {}
