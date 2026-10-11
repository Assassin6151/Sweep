import XCTest
@testable import Sweep

final class UninstallerTests: XCTestCase {
    private var fake: FakeHome!

    override func setUpWithError() throws {
        fake = try FakeHome()
    }

    @discardableResult
    private func makeApp(_ name: String, bundleID: String, executable: String? = nil, in folder: String = "Applications", appStore: Bool = false) throws -> URL {
        let app = fake.home.appending(path: "\(folder)/\(name).app")
        let info: [String: Any] = [
            "CFBundleIdentifier": bundleID,
            "CFBundleName": name,
            "CFBundleShortVersionString": "2.1",
            "CFBundleExecutable": executable ?? name,
            "CFBundlePackageType": "APPL",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try fake.file("\(folder)/\(name).app/Contents/Info.plist", contents: data)
        try fake.file("\(folder)/\(name).app/Contents/MacOS/\(executable ?? name)", size: 50_000)
        if appStore { try fake.file("\(folder)/\(name).app/Contents/_MASReceipt/receipt", size: 100) }
        return app
    }

    private func discovery(usage: (lastUsed: Date?, added: Date?) = (nil, nil)) -> AppDiscoveryService {
        AppDiscoveryService(roots: [fake.home.appending(path: "Applications")], ownBundleID: "com.test.sweep", usageProvider: { _ in usage })
    }

    // MARK: Discovery

    func testDiscoversAppsIncludingVendorFoldersAndSkipsAppleAndSelf() throws {
        try makeApp("Writer", bundleID: "com.example.writer", appStore: true)
        try makeApp("Studio Tool", bundleID: "com.vendor.tool", in: "Applications/Vendor Suite")
        try makeApp("Notes Clone", bundleID: "com.apple.fakeNotes")
        try makeApp("Sweep", bundleID: "com.test.sweep")

        let apps = try discovery().discover()
        XCTAssertEqual(apps.map(\.bundleID), ["com.vendor.tool", "com.example.writer"])
        XCTAssertEqual(apps.first { $0.bundleID == "com.example.writer" }?.isFromAppStore, true)
        XCTAssertEqual(apps.first?.version, "2.1")
    }

    func testUnusedDetection() throws {
        try makeApp("Old", bundleID: "com.example.old")
        let longAgo = Date().addingTimeInterval(-200 * 86_400)
        let app = try XCTUnwrap(discovery(usage: (longAgo, nil)).discover().first)
        XCTAssertTrue(app.isUnused(days: 90))
        XCTAssertFalse(app.isUnused(days: 365))

        let neverOpened = try XCTUnwrap(discovery(usage: (nil, longAgo)).discover().first)
        XCTAssertTrue(neverOpened.isUnused(days: 90), "never opened since install counts as unused")

        let unknown = try XCTUnwrap(discovery().discover().first)
        XCTAssertFalse(unknown.isUnused(days: 1), "no data means no claim")
    }

    // MARK: Leftovers

    private func finder(fullDiskAccess: Bool = true) -> LeftoverFinder {
        LeftoverFinder(paths: fake.paths, protection: ProtectedPaths(paths: fake.paths), hasFullDiskAccess: fullDiskAccess)
    }

    private func installedWriter() throws -> InstalledApp {
        try makeApp("Writer Pro", bundleID: "com.example.writer", executable: "WriterPro")
        return try XCTUnwrap(discovery().discover().first)
    }

    func testFindsLeftoversByBundleID() throws {
        let app = try installedWriter()
        try fake.file("Library/Preferences/com.example.writer.plist", size: 1_000)
        try fake.file("Library/Preferences/com.example.writer.helper.plist", size: 1_000)
        try fake.file("Library/Caches/com.example.writer/cache.db", size: 9_000)
        try fake.file("Library/Containers/com.example.writer/Data/x", size: 2_000)
        try fake.file("Library/Group Containers/ABCDE12345.com.example.writer/shared.db", size: 2_000)
        try fake.file("Library/Saved Application State/com.example.writer.savedState/window.data", size: 500)
        try fake.file("Library/HTTPStorages/com.example.writer/x", size: 500)
        try fake.file("Library/LaunchAgents/com.example.writer.updater.plist", size: 500)
        try fake.file("Library/Logs/DiagnosticReports/WriterPro-2026-01-01-101010.ips", size: 500)
        try fake.file("sysroot/Library/LaunchDaemons/com.example.writer.daemon.plist", size: 500, base: fake.root)

        let (leftovers, skipped) = try finder().findLeftovers(for: app)
        let names = Set(leftovers.map(\.url.lastPathComponent))
        XCTAssertEqual(names, [
            "com.example.writer.plist", "com.example.writer.helper.plist", "com.example.writer",
            "ABCDE12345.com.example.writer", "com.example.writer.savedState", "com.example.writer.updater.plist",
            "WriterPro-2026-01-01-101010.ips", "com.example.writer.daemon.plist",
        ])
        XCTAssertEqual(skipped, 0)
        XCTAssertTrue(leftovers.allSatisfy { $0.confidence == .high })
        XCTAssertEqual(leftovers.first { $0.kind == .launchDaemons }?.isSystemWide, true)
    }

    func testDoesNotMatchSimilarBundleIDs() throws {
        let app = try installedWriter()
        try fake.file("Library/Preferences/com.example.writerlite.plist")
        try fake.file("Library/Preferences/com.example.plist")
        try fake.file("Library/Caches/com.example.writer2/x")
        let (leftovers, _) = try finder().findLeftovers(for: app)
        XCTAssertTrue(leftovers.isEmpty, "found \(leftovers.map(\.url.lastPathComponent))")
    }

    func testNameMatchesAreMediumConfidenceAndOnlyInSomePlaces() throws {
        let app = try installedWriter()
        try fake.file("Library/Application Support/Writer Pro/library.db", size: 3_000)
        try fake.file("Library/Preferences/Writer Pro.plist", size: 100)
        let (leftovers, _) = try finder().findLeftovers(for: app)
        XCTAssertEqual(leftovers.map(\.url.lastPathComponent), ["Writer Pro"])
        XCTAssertEqual(leftovers.first?.confidence, .medium)
    }

    func testShortAppNamesNeverMatchByName() throws {
        try makeApp("Go", bundleID: "com.example.go")
        let app = try XCTUnwrap(discovery().discover().first)
        try fake.file("Library/Application Support/Go/x")
        let (leftovers, _) = try finder().findLeftovers(for: app)
        XCTAssertTrue(leftovers.isEmpty)
    }

    func testContainersAreSkippedWithoutFullDiskAccess() throws {
        let app = try installedWriter()
        try fake.file("Library/Containers/com.example.writer/Data/x", size: 2_000)
        try fake.file("Library/Preferences/com.example.writer.plist")
        let (leftovers, skipped) = try finder(fullDiskAccess: false).findLeftovers(for: app)
        XCTAssertEqual(leftovers.map(\.url.lastPathComponent), ["com.example.writer.plist"])
        XCTAssertEqual(skipped, 3, "Containers, Group Containers and Cookies")
    }

    func testStripExtensions() {
        XCTAssertEqual(LeftoverFinder.stripExtensions("com.a.b.plist"), "com.a.b")
        XCTAssertEqual(LeftoverFinder.stripExtensions("com.a.b.savedState"), "com.a.b")
        XCTAssertEqual(LeftoverFinder.stripExtensions("com.a.b"), "com.a.b")
    }
}
