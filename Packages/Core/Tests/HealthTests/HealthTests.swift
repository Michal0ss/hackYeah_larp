import XCTest
@testable import Health

// Placeholder so the test target exists. The owner replaces it with real tests.
final class HealthTests: XCTestCase {
    func testModuleExists() {
        XCTAssertFalse(HealthModule.owner.isEmpty)
    }
}
