import XCTest
@testable import Plan

// Placeholder so the test target exists. The owner replaces it with real tests.
final class PlanTests: XCTestCase {
    func testModuleExists() {
        XCTAssertFalse(PlanModule.owner.isEmpty)
    }
}
