import XCTest
@testable import Content

// Placeholder so the test target exists. The owner replaces it with real tests.
final class ContentTests: XCTestCase {
    func testModuleExists() {
        XCTAssertFalse(ContentModule.owner.isEmpty)
    }
}
