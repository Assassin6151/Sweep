import XCTest
@testable import Sweep

final class SmartScanSummaryTests: XCTestCase {
    func testCombinesPartsWithoutDoubleCounting() {
        let junkCategory = JunkCatalog.categories(paths: .current).first { $0.id == .userCaches }!
        let junk = [JunkCategoryResult(category: junkCategory, items: [
            JunkItem(url: URL(fileURLWithPath: "/c/a"), name: "a", size: 300, modified: nil, selectedByDefault: true),
            JunkItem(url: URL(fileURLWithPath: "/c/b"), name: "b", size: 700, modified: nil, selectedByDefault: false),
        ], unreadableLocations: 0)]
        let iso = DuplicateFile(url: URL(fileURLWithPath: "/d/big.iso"), size: 5_000, modified: nil)
        let isoCopy = DuplicateFile(url: URL(fileURLWithPath: "/e/big.iso"), size: 5_000, modified: nil)
        let duplicates = [DuplicateGroup(id: "h", size: 5_000, files: [iso, isoCopy])]
        let large = [
            LargeFile(url: iso.url, size: 5_000, modified: nil, accessed: nil, kind: .diskImage),
            LargeFile(url: isoCopy.url, size: 5_000, modified: nil, accessed: nil, kind: .diskImage),
            LargeFile(url: URL(fileURLWithPath: "/m/movie.mov"), size: 9_000, modified: nil, accessed: nil, kind: .video),
        ]

        let summary = SmartScanSummary.make(junk: junk, junkSelection: ["/c/a"],
                                            duplicates: duplicates, duplicateSelection: [isoCopy.id], largeFiles: large)
        XCTAssertEqual(summary.junkBytes, 300)
        XCTAssertEqual(summary.duplicateBytes, 5_000)
        XCTAssertEqual(summary.duplicateCount, 1)
        XCTAssertEqual(summary.reclaimableBytes, 5_300)
        XCTAssertEqual(summary.largeFileCount, 2, "the copy that will be removed is not listed again as a large file")
        XCTAssertEqual(summary.largeFileBytes, 14_000)
    }
}

@MainActor
final class SmartScanFlowTests: XCTestCase {
    func testRunsAllThreePartsAndFillsTheModules() async throws {
        let fake = try FakeHome()
        try fake.file("Library/Caches/com.example.app/cache.bin", size: 20_000)
        let content = Data(repeating: 7, count: 2_000_000)
        try fake.file("Documents/a.bin", contents: content)
        try fake.file("Downloads/a copy.bin", contents: content)
        try fake.file("Movies/huge.mov", size: 60 * 1_048_576)

        let log = ActivityLog(fileURL: fake.root.appending(path: "log.json"))
        let deletion = DeletionService(log: log, paths: fake.paths, trasher: RecordingTrasher(trashFolder: fake.root.appending(path: "trash")))
        let permissions = PermissionService()
        let junk = JunkCleanerViewModel(deletion: deletion, permissions: permissions, paths: fake.paths)
        let large = LargeFilesViewModel(deletion: deletion, permissions: permissions, paths: fake.paths)
        large.minimumSize = LargeFilesViewModel.scanFloor
        let duplicates = DuplicatesViewModel(deletion: deletion, permissions: permissions, paths: fake.paths)
        let smart = SmartScanViewModel(junk: junk, largeFiles: large, duplicates: duplicates)

        smart.start()
        for _ in 0..<200 where smart.phase != .done {
            try await Task.sleep(for: .milliseconds(50))
        }

        XCTAssertEqual(smart.phase, .done)
        XCTAssertTrue(SmartScanViewModel.Part.allCases.allSatisfy { smart.state(of: $0) == .done })
        XCTAssertEqual(junk.phase, .results)
        XCTAssertGreaterThanOrEqual(smart.summary.junkBytes, 20_000)
        XCTAssertEqual(duplicates.groups.count, 1)
        XCTAssertEqual(smart.summary.duplicateCount, 1)
        XCTAssertEqual(large.visibleFiles.map(\.name), ["huge.mov"])
    }
}
