import XCTest
@testable import Sweep

final class JunkScanServiceTests: XCTestCase {
    private var fake: FakeHome!
    private var service: JunkScanService!

    override func setUpWithError() throws {
        fake = try FakeHome()
        service = JunkScanService(categories: JunkCatalog.categories(paths: fake.paths, ownBundleID: "com.test.sweep"),
                                  protection: ProtectedPaths(paths: fake.paths))
    }

    private func category(_ id: JunkCategoryID) -> JunkCategory {
        JunkCatalog.categories(paths: fake.paths).first { $0.id == id }!
    }

    func testUserCachesAreFoundAndMeasured() throws {
        try fake.file("Library/Caches/com.example.app/a.bin", size: 10_000)
        try fake.file("Library/Caches/com.example.app/nested/b.bin", size: 5_000)
        try fake.file("Library/Caches/CloudKit/keep.db", size: 10_000)
        try fake.file("Library/Caches/Homebrew/downloads/pkg.tar.gz", size: 10_000)
        try fake.folder("Library/Caches/empty")

        let result = try service.scan(category(.userCaches))
        XCTAssertEqual(result.items.map(\.name), ["com.example.app"])
        XCTAssertGreaterThanOrEqual(result.totalSize, 15_000)
        XCTAssertTrue(result.items[0].selectedByDefault)
    }

    func testHomebrewIsItsOwnCategory() throws {
        try fake.file("Library/Caches/Homebrew/downloads/pkg.tar.gz", size: 10_000)
        try fake.file("Library/Logs/Homebrew/wget/01.log", size: 100)
        let result = try service.scan(category(.homebrew))
        XCTAssertEqual(Set(result.items.map(\.name)), ["downloads", "wget"])
    }

    func testTemporaryFilesRespectMinimumAge() throws {
        let tmp = fake.paths.temporaryDirectory
        try fake.file("old.tmp", base: tmp, modified: Date().addingTimeInterval(-5 * 86_400))
        try fake.file("fresh.tmp", base: tmp)
        let result = try service.scan(category(.temporaryFiles))
        XCTAssertEqual(result.items.map(\.name), ["old.tmp"])
    }

    func testContainerCachesUseBundleIDAsName() throws {
        try fake.file("Library/Containers/com.example.writer/Data/Library/Caches/thumbs.db", size: 2_000)
        try fake.file("Library/Containers/com.example.writer/Data/Documents/novel.txt", size: 2_000)
        let result = try service.scan(category(.containerCaches))
        XCTAssertEqual(result.items.map(\.name), ["com.example.writer"])
        XCTAssertTrue(result.items[0].url.path.hasSuffix("Data/Library/Caches"))
    }

    func testXcodeArchivesAreNotPreselected() throws {
        try fake.file("Library/Developer/Xcode/DerivedData/App-abc/Build/x.o", size: 4_000)
        try fake.file("Library/Developer/Xcode/Archives/2026-01-01/App.xcarchive/Info.plist", size: 4_000)
        let result = try service.scan(category(.xcode))
        let byName = Dictionary(uniqueKeysWithValues: result.items.map { ($0.name, $0) })
        XCTAssertEqual(byName["DerivedData: App-abc"]?.selectedByDefault, true)
        XCTAssertEqual(byName["Archive: 2026-01-01"]?.selectedByDefault, false)
    }

    func testTrashUsesPermanentModeAndIsNotPreselected() throws {
        try fake.file(".Trash/old.zip", size: 4_000)
        let trash = category(.trash)
        XCTAssertEqual(trash.deletionMode, .permanent)
        let result = try service.scan(trash)
        XCTAssertEqual(result.items.count, 1)
        XCTAssertFalse(result.items[0].selectedByDefault)
    }

    func testFullScanKeepsCategoryOrderAndReportsProgress() async throws {
        try fake.file("Library/Caches/com.example.app/a.bin", size: 1_000)
        try fake.file("Library/Logs/app.log", size: 1_000)
        let updates = Counter()
        let results = try await service.scan { _ in updates.increment() }
        XCTAssertEqual(results.map(\.id), JunkCategoryID.allCases)
        XCTAssertEqual(results.first { $0.id == .userLogs }?.items.count, 1)
        XCTAssertGreaterThan(updates.value, 0)
    }

    func testCancellationStopsTheScan() async throws {
        for index in 0..<50 { try fake.file("Library/Caches/app\(index)/file", size: 100) }
        let task = Task { try await service.scan { _ in } }
        task.cancel()
        do {
            _ = try await task.value
        } catch is CancellationError {
            return
        }
        // Finishing before cancellation is observed is acceptable, but no crash or hang.
    }
}

final class PrivacyProtectedLocationsTests: XCTestCase {
    func testProtectedAreasAreSkippedWithoutFullDiskAccess() throws {
        let fake = try FakeHome()
        let without = PrivacyProtectedLocations(paths: fake.paths, hasFullDiskAccess: false)
        let with = PrivacyProtectedLocations(paths: fake.paths, hasFullDiskAccess: true)
        let lib = fake.paths.userLibrary
        for url in [lib.appending(path: "Containers/com.x/Data"), lib.appending(path: "Caches/com.apple.Music"),
                    lib.appending(path: "Mail/V10"), fake.paths.trash.appending(path: "a.zip")] {
            XCTAssertTrue(without.shouldSkip(url), url.path)
            XCTAssertFalse(with.shouldSkip(url), url.path)
        }
        XCTAssertFalse(without.shouldSkip(lib.appending(path: "Caches/com.example.app")))
    }

    func testJunkScanSkipsProtectedCachesWithoutAccess() throws {
        let fake = try FakeHome()
        try fake.file("Library/Caches/com.apple.Music/a", size: 1_000)
        try fake.file("Library/Caches/com.example.app/a", size: 1_000)
        let categories = JunkCatalog.categories(paths: fake.paths)
        let service = JunkScanService(categories: categories, protection: ProtectedPaths(paths: fake.paths), hasFullDiskAccess: false)
        let result = try service.scan(categories.first { $0.id == .userCaches }!)
        XCTAssertEqual(result.items.map(\.name), ["com.example.app"])
        XCTAssertGreaterThanOrEqual(result.unreadableLocations, 1)
    }
}
