import XCTest
@testable import Sweep

@MainActor
final class ActivityLogTests: XCTestCase {
    private var fileURL: URL!

    override func setUp() {
        fileURL = FileManager.default.temporaryDirectory.appending(path: "log-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func entry(size: Int64 = 100) -> ActivityEntry {
        ActivityEntry(module: .junk, action: .cleaned, title: "Junk entfernen",
                      items: [ActivityItem(path: "/tmp/a", size: size, trashedPath: "/Users/x/.Trash/a")])
    }

    func testEntriesPersistAcrossInstances() {
        let log = ActivityLog(fileURL: fileURL)
        log.record(entry(size: 100))
        log.record(entry(size: 200))

        let reloaded = ActivityLog(fileURL: fileURL)
        XCTAssertEqual(reloaded.entries.count, 2)
        XCTAssertEqual(reloaded.entries.first?.freedBytes, 200, "newest entry first")
        XCTAssertEqual(reloaded.totalFreedBytes, 300)
        XCTAssertEqual(reloaded.entries.first?.items.first?.trashedPath, "/Users/x/.Trash/a")
    }

    func testEmptyEntriesAreIgnored() {
        let log = ActivityLog(fileURL: fileURL)
        log.record(ActivityEntry(module: .junk, action: .cleaned, title: "leer", items: []))
        XCTAssertTrue(log.entries.isEmpty)
    }

    func testMarkRestoredAndClear() {
        let log = ActivityLog(fileURL: fileURL)
        let recorded = entry()
        log.record(recorded)
        log.markRestored(itemID: recorded.items[0].id, in: recorded.id)
        XCTAssertEqual(ActivityLog(fileURL: fileURL).entries.first?.items.first?.status, .restored)

        log.clear()
        XCTAssertTrue(ActivityLog(fileURL: fileURL).entries.isEmpty)
    }

    func testRestoreMovesFileBack() throws {
        let fake = try FakeHome()
        let original = try fake.file("Library/Caches/com.example/blob", size: 10)
        let log = ActivityLog(fileURL: fileURL)
        let trasher = RecordingTrasher(trashFolder: fake.root.appending(path: "trash"))
        let service = DeletionService(log: log, paths: fake.paths, trasher: trasher)
        let plan = DeletionPlan(title: "t", message: "", module: .junk, action: .cleaned,
                                candidates: [DeletionCandidate(url: original, size: 10)])
        let outcome = SafeDeleter(protection: ProtectedPaths(paths: fake.paths), trasher: trasher).execute(plan)
        log.record(outcome.entry)
        XCTAssertFalse(fake.exists(original))

        try service.restore(item: outcome.entry.items[0], in: outcome.entry)
        XCTAssertTrue(fake.exists(original))
        XCTAssertEqual(log.entries.first?.items.first?.status, .restored)
    }
}
