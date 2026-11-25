@testable import AppCore
import XCTest

@MainActor final class AppUpdatesTests: XCTestCase {
    private final class FakeUpdater: AppUpdates.Updater {
        var canCheckForUpdates = true
        var checks = 0
        func checkForUpdates() { checks += 1 }
    }

    func testWithoutAnUpdaterNothingIsAvailable() {
        let updates = AppUpdates()
        updates.check()
        XCTAssertFalse(updates.isAvailable)
        XCTAssertFalse(updates.canCheck)
    }

    func testCheckIsForwardedOnlyWhileTheUpdaterAcceptsOne() {
        let updates = AppUpdates()
        let updater = FakeUpdater()
        updates.connect(updater)
        XCTAssertTrue(updates.isAvailable)
        updates.check()
        XCTAssertEqual(updater.checks, 1)

        updater.canCheckForUpdates = false
        updates.check()
        XCTAssertTrue(updates.isAvailable)
        XCTAssertFalse(updates.canCheck)
        XCTAssertEqual(updater.checks, 1)
    }

    func testSessionEndIsReported() {
        let updates = AppUpdates()
        var finished = 0
        updates.onSessionFinished = { finished += 1 }
        updates.sessionFinished()
        XCTAssertEqual(finished, 1)
    }

    func testEmbeddedAgentResolvesToTheOuterApplication() {
        let agent = URL(fileURLWithPath:
            "/Applications/OpenLaunchPad.app/Contents/Library/LoginItems/OpenLaunchPadAgent.app")
        XCTAssertEqual(UpdateHost.applicationURL(embedding: agent)?.path, "/Applications/OpenLaunchPad.app")
    }

    func testAgentOutsideAnApplicationHasNoHost() {
        XCTAssertNil(UpdateHost.applicationURL(
            embedding: URL(fileURLWithPath: "/tmp/Builds/OpenLaunchPadAgent.app")))
        XCTAssertNil(UpdateHost.applicationURL(
            embedding: URL(fileURLWithPath: "/tmp/Folder/Contents/Library/LoginItems/OpenLaunchPadAgent.app")))
    }

    func testConfigurationNeedsAFeedAndA32ByteKey() {
        let feed = "https://example.com/appcast.xml"
        let key = Data(repeating: 1, count: 32).base64EncodedString()
        XCTAssertTrue(UpdateHost.isConfigured(infoDictionary: ["SUFeedURL": feed, "SUPublicEDKey": key]))
        XCTAssertFalse(UpdateHost.isConfigured(infoDictionary: [:]))
        XCTAssertFalse(UpdateHost.isConfigured(infoDictionary: ["SUFeedURL": feed, "SUPublicEDKey": ""]))
        XCTAssertFalse(UpdateHost.isConfigured(infoDictionary: ["SUFeedURL": "", "SUPublicEDKey": key]))
        XCTAssertFalse(UpdateHost.isConfigured(infoDictionary: ["SUFeedURL": feed, "SUPublicEDKey": "AAAA"]))
    }
}
