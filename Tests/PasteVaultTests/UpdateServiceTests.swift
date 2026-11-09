import XCTest
@testable import PasteVault

final class UpdateServiceTests: XCTestCase {

    func testSemanticVersionComparison() {
        // Equal versions
        XCTAssertFalse(UpdateService.isVersion("v1.0.0", newerThan: "1.0.0"))
        XCTAssertFalse(UpdateService.isVersion("1.1", newerThan: "1.1.0"))

        // Newer patch version
        XCTAssertTrue(UpdateService.isVersion("v1.0.1", newerThan: "1.0.0"))

        // Newer minor version
        XCTAssertTrue(UpdateService.isVersion("v1.1.0", newerThan: "1.0.9"))

        // Newer major version
        XCTAssertTrue(UpdateService.isVersion("v2.0.0", newerThan: "1.9.9"))

        // Older remote version
        XCTAssertFalse(UpdateService.isVersion("v1.0.0", newerThan: "1.0.1"))

        // Pre-release / build suffix stripping
        XCTAssertFalse(UpdateService.isVersion("v1.0.0-beta.1", newerThan: "1.0.0"))
        XCTAssertTrue(UpdateService.isVersion("V1.0.2-rc.1", newerThan: "1.0.1"))
    }
}
