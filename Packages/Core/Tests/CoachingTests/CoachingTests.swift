import XCTest
@testable import Coaching

// Placeholder so the test target exists. The owner replaces it with real tests.
final class CoachingTests: XCTestCase {
    func testModuleExists() {
        XCTAssertFalse(CoachingModule.owner.isEmpty)
    }
}
