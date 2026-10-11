import XCTest
@testable import Sweep

final class SafeDeleterTests: XCTestCase {
    private var fake: FakeHome!
    private var trasher: RecordingTrasher!
    private var deleter: SafeDeleter!

    override func setUpWithError() throws {
        fake = try FakeHome()
        trasher = RecordingTrasher(trashFolder: fake.root.appending(path: "recorded-trash"))
        deleter = SafeDeleter(protection: ProtectedPaths(paths: fake.paths), trasher: trasher)
    }

    private func plan(_ candidates: [DeletionCandidate]) -> DeletionPlan {
        DeletionPlan(title: "Test", message: "", module: .junk, action: .cleaned, candidates: candidates)
    }

    func testMovesAllowedItemsToTrashAndRecordsWhere() throws {
        let cache = try fake.file("Library/Caches/com.example/data.bin", size: 1000)
        let outcome = deleter.execute(plan([DeletionCandidate(url: cache.deletingLastPathComponent(), size: 1000)]))

        XCTAssertEqual(outcome.removedItems.count, 1)
        XCTAssertEqual(outcome.freedBytes, 1000)
        XCTAssertFalse(fake.exists(cache))
        let trashedPath = try XCTUnwrap(outcome.removedItems.first?.trashedPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: trashedPath))
        XCTAssertTrue(trasher.removed.isEmpty, "nothing may be deleted permanently")
    }

    func testProtectedItemsAreNeverTouched() throws {
        let documents = try fake.folder("Documents")
        try fake.file("Documents/thesis.pdf")
        let outcome = deleter.execute(plan([DeletionCandidate(url: documents, size: 4096)]))

        XCTAssertEqual(outcome.entry.items.first?.status, .blocked)
        XCTAssertTrue(fake.exists(documents))
        XCTAssertTrue(trasher.trashed.isEmpty)
    }

    func testPermanentDeletionOnlyInsideTrash() throws {
        let outside = try fake.file("Downloads/movie.mov")
        let inside = try fake.file(".Trash/old.zip")
        let outcome = deleter.execute(plan([
            DeletionCandidate(url: outside, size: 4096, mode: .permanent),
            DeletionCandidate(url: inside, size: 4096, mode: .permanent),
        ]))

        XCTAssertEqual(outcome.entry.items[0].status, .blocked)
        XCTAssertTrue(fake.exists(outside))
        XCTAssertEqual(outcome.entry.items[1].status, .done)
        XCTAssertFalse(fake.exists(inside))
        XCTAssertEqual(trasher.removed, [inside])
    }

    func testMissingAndFailingItemsAreReported() throws {
        let failing = try fake.file("Library/Caches/locked/file")
        trasher.failingPaths = [failing.path]
        let missing = fake.home.appending(path: "Library/Caches/gone")
        let outcome = deleter.execute(plan([
            DeletionCandidate(url: missing, size: 10),
            DeletionCandidate(url: failing, size: 10),
        ]))

        XCTAssertEqual(outcome.entry.items.map(\.status), [.failed, .failed])
        XCTAssertNotNil(outcome.entry.items[1].message)
        XCTAssertTrue(fake.exists(failing))
        XCTAssertEqual(outcome.freedBytes, 0)
    }

    func testOutcomeIsLoggedWithModuleAndAction() throws {
        let file = try fake.file("Library/Logs/app.log")
        let outcome = deleter.execute(plan([DeletionCandidate(url: file, size: 4096)]))
        XCTAssertEqual(outcome.entry.module, .junk)
        XCTAssertEqual(outcome.entry.action, .cleaned)
        XCTAssertEqual(outcome.entry.items.first?.path, file.path)
    }
}
