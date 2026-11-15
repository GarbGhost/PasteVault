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
        XCTAssertTrue(UpdateService.isVersion("1.1.0", newerThan: "1.0.1"))
        XCTAssertFalse(UpdateService.isVersion("1.0.1", newerThan: "1.1.0"))
        XCTAssertFalse(UpdateService.isVersion("1.1.0", newerThan: "v1.1.0"))

        // Newer major version
        XCTAssertTrue(UpdateService.isVersion("v2.0.0", newerThan: "1.9.9"))

        // Older remote version
        XCTAssertFalse(UpdateService.isVersion("v1.0.0", newerThan: "1.0.1"))

        // Pre-release / build suffix stripping
        XCTAssertFalse(UpdateService.isVersion("v1.0.0-beta.1", newerThan: "1.0.0"))
        XCTAssertTrue(UpdateService.isVersion("V1.0.2-rc.1", newerThan: "1.0.1"))
    }

    @MainActor
    func testPrivateOrOfflineStateDistinctFromUpToDate() {
        let releasesURL = UpdateService.releasesPageURL
        let offline = UpdateService.UpdateState.privateOrOffline(currentVersion: "1.1.0", releasesURL: releasesURL)
        let upToDate = UpdateService.UpdateState.upToDate(currentVersion: "1.1.0")
        XCTAssertNotEqual(offline, upToDate, "404/offline state must stay distinct from verified upToDate state")
        XCTAssertEqual(UpdateService.shared.currentVersion, "1.1.0")
    }
}
