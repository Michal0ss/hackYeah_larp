import XCTest
@testable import Analysis

// Placeholder so the test target exists. The owner replaces it with real tests.
final class AnalysisTests: XCTestCase {
    func testModuleExists() {
        XCTAssertFalse(AnalysisModule.owner.isEmpty)
    }
}
