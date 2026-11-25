@testable import AppCore
import XCTest

final class AgentIdentityTests: XCTestCase {
    private let current = Data([1, 2, 3])

    func testTheEmbeddedAgentIsCurrent() {
        XCTAssertFalse(AgentIdentity.isOutdated(running: .hash(current), embedded: [current, Data([4])]))
    }

    func testDifferentCodeIsOutdated() {
        XCTAssertTrue(AgentIdentity.isOutdated(running: .hash(Data([9])), embedded: [current, Data([4])]))
    }

    func testAnAgentWhoseFileIsGoneIsOutdated() {
        XCTAssertTrue(AgentIdentity.isOutdated(running: .goneFromDisk, embedded: [current, Data([4])]))
        XCTAssertTrue(AgentIdentity.isOutdated(running: .goneFromDisk, embedded: []))
    }

    func testUnreadableSignaturesNeverReplaceAnAgent() {
        XCTAssertFalse(AgentIdentity.isOutdated(running: .unknown, embedded: [current, Data([4])]))
        XCTAssertFalse(AgentIdentity.isOutdated(running: .hash(current), embedded: []))
    }

    func testAProcessMatchesItsOwnFile() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["30"]
        try process.run()
        defer { process.terminate() }
        let running = AgentIdentity.runningCode(of: process.processIdentifier)
        guard case .hash = running else { return XCTFail("\(running)") }
        XCTAssertFalse(AgentIdentity.isOutdated(
            running: running,
            embedded: AgentIdentity.embeddedHashes(ofAgentAt: URL(fileURLWithPath: "/bin/sleep"))))
        XCTAssertTrue(AgentIdentity.isOutdated(
            running: running,
            embedded: AgentIdentity.embeddedHashes(ofAgentAt: URL(fileURLWithPath: "/bin/ls"))))
    }

    func testAnEndedProcessIsUnknown() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(AgentIdentity.runningCode(of: process.processIdentifier), .unknown)
    }
}
