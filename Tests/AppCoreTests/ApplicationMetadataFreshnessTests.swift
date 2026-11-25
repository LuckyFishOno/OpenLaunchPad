import Foundation
import XCTest

@testable import AppCore

final class ApplicationMetadataFreshnessTests: XCTestCase {
    func testNameAndStampFollowAnUpdateInPlace() throws {
        let app = try makeApplication(name: "Old", identifier: "test.fresh.app")
        let resolver = AppMetadataResolver()
        let before = try XCTUnwrap(resolver.resolve(bundleURL: app))
        let unchanged = try XCTUnwrap(resolver.resolve(bundleURL: app))

        try writeInfo(["CFBundleName": "New", "CFBundleIdentifier": "test.fresh.app"], to: app)
        let after = try XCTUnwrap(resolver.resolve(bundleURL: app))

        XCTAssertEqual(before, unchanged)
        XCTAssertEqual(before.displayName, "Old")
        XCTAssertEqual(after.displayName, "New")
        XCTAssertEqual(after.id, before.id)
        XCTAssertNotEqual(after, before)
        XCTAssertNotEqual(after.contentStamp, before.contentStamp)
    }

    func testBundleReplacedByAnIdenticalCopyHasANewStamp() throws {
        let app = try makeApplication(name: "Same", identifier: "test.fresh.copy")
        let before = try XCTUnwrap(ApplicationContentStamp(bundleURL: app))
        let copy = app.deletingLastPathComponent().appendingPathComponent("Copy.app")
        try FileManager.default.copyItem(at: app, to: copy)
        _ = try FileManager.default.replaceItemAt(app, withItemAt: copy)

        XCTAssertNotEqual(ApplicationContentStamp(bundleURL: app), before)
    }

    func testApplicationFirstSeenWithoutInfoPlistGetsItsIdentifierLater() throws {
        let app = try makeDirectory().appendingPathComponent("Copying.app")
        try FileManager.default.createDirectory(
            at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let resolver = AppMetadataResolver()
        let incomplete = try XCTUnwrap(resolver.resolve(bundleURL: app))

        try writeInfo(["CFBundleName": "Copied", "CFBundleIdentifier": "test.fresh.copied"], to: app)
        let complete = try XCTUnwrap(resolver.resolve(bundleURL: app))

        XCTAssertNil(incomplete.bundleIdentifier)
        XCTAssertEqual(complete.bundleIdentifier, "test.fresh.copied")
        XCTAssertEqual(complete.displayName, "Copied")
    }

    func testLocalizedNamePrecedesInfoPlist() throws {
        let app = try makeApplication(name: "Plain", identifier: "test.fresh.localized")
        let language = try XCTUnwrap(Bundle.main.preferredLocalizations.first)
        let project = app.appendingPathComponent("Contents/Resources/\(language).lproj")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try "\"CFBundleDisplayName\" = \"Localized\";".write(
            to: project.appendingPathComponent("InfoPlist.strings"), atomically: true, encoding: .utf16)

        let reader = try XCTUnwrap(BundleInfoReader(bundleURL: app))

        XCTAssertEqual(reader.string(forKey: "CFBundleDisplayName"), "Localized")
        XCTAssertEqual(reader.string(forKey: "CFBundleName"), "Plain")
        XCTAssertEqual(reader.bundleIdentifier, "test.fresh.localized")
    }

    func testLocalizedTableAndMacKeysAreRead() throws {
        let app = try makeApplication(name: "Plain", identifier: "test.fresh.table")
        let language = try XCTUnwrap(Bundle.main.preferredLocalizations.first)
        let resources = app.appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let table: [String: Any] = [
            language: ["CFBundleDisplayName": "Phone name", "CFBundleDisplayName-macos": "Mac name"],
            "LocProvenance": ["ignored": true],
        ]
        try PropertyListSerialization.data(fromPropertyList: table, format: .binary, options: 0)
            .write(to: resources.appendingPathComponent("InfoPlist.loctable"))

        let reader = try XCTUnwrap(BundleInfoReader(bundleURL: app))

        XCTAssertEqual(reader.string(forKey: "CFBundleDisplayName"), "Mac name")
    }

    func testDirectoryChangesInsideABundleAreIgnored() {
        for path in [
            "/Applications/", "/Applications/Utilities/", "/Applications/Foo.app/", "/Applications/Foo.app/Contents/",
            "/Applications/Tools/Foo.APP",
        ] {
            XCTAssertTrue(ApplicationDirectoryChange.affectsCatalog(path: path), path)
        }
        for path in [
            "/Applications/Foo.app/Contents/Resources/", "/Applications/Foo.app/Contents/Library/Bar.app/",
            "/Applications/Foo.app/Logs/",
        ] {
            XCTAssertFalse(ApplicationDirectoryChange.affectsCatalog(path: path), path)
        }
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("fresh-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func makeApplication(name: String, identifier: String) throws -> URL {
        let app = try makeDirectory().appendingPathComponent("Test.app")
        try FileManager.default.createDirectory(
            at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try writeInfo(["CFBundleName": name, "CFBundleIdentifier": identifier], to: app)
        return app
    }

    private func writeInfo(_ info: [String: Any], to app: URL) throws {
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"), options: .atomic)
    }
}
