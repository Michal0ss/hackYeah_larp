import XCTest
@testable import Insights

// Placeholder so the test target exists. The owner replaces it with real tests.
final class InsightsTests: XCTestCase {
    func testModuleExists() {
        XCTAssertFalse(InsightsModule.owner.isEmpty)
    }
}
