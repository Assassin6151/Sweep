import XCTest
@testable import Sweep

final class TreemapLayoutTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 600, height: 400)

    func testAreasAreProportionalAndFillTheBounds() {
        let values: [Double] = [6, 6, 4, 3, 2, 2, 1]
        let rects = TreemapLayout.squarify(values, in: bounds)
        let total = values.reduce(0, +)
        for (value, rect) in zip(values, rects) {
            let expected = value / total * Double(bounds.width * bounds.height)
            XCTAssertEqual(Double(rect.width * rect.height), expected, accuracy: 0.5)
            XCTAssertTrue(bounds.insetBy(dx: -0.01, dy: -0.01).contains(rect), "\(rect) outside bounds")
        }
        let covered = rects.reduce(0) { $0 + $1.width * $1.height }
        XCTAssertEqual(Double(covered), Double(bounds.width * bounds.height), accuracy: 1)
    }

    func testRectanglesDoNotOverlap() {
        let rects = TreemapLayout.squarify([50, 30, 30, 20, 10, 8, 5, 5, 2, 1], in: bounds)
        for i in rects.indices {
            for j in rects.indices where j > i {
                let overlap = rects[i].intersection(rects[j])
                XCTAssertTrue(overlap.isNull || overlap.width * overlap.height < 0.01, "\(i) overlaps \(j)")
            }
        }
    }

    func testResultKeepsInputOrderAndHandlesZero() {
        let rects = TreemapLayout.squarify([1, 0, 9], in: bounds)
        XCTAssertEqual(rects[1], .zero)
        XCTAssertGreaterThan(rects[2].width * rects[2].height, rects[0].width * rects[0].height * 8)
    }

    func testSquarifiedKeepsAspectRatiosReasonable() {
        let rects = TreemapLayout.squarify(Array(repeating: 1, count: 24), in: bounds)
        for rect in rects {
            let ratio = max(rect.width / rect.height, rect.height / rect.width)
            XCTAssertLessThan(ratio, 3, "equal values should give near-square tiles")
        }
    }

    func testEmptyInput() {
        XCTAssertTrue(TreemapLayout.squarify([], in: bounds).isEmpty)
        XCTAssertEqual(TreemapLayout.squarify([5], in: .zero), [.zero])
    }
}

final class DiskUsageServiceTests: XCTestCase {
    private var fake: FakeHome!

    override func setUpWithError() throws {
        fake = try FakeHome()
    }

    private func service(maxChildren: Int = 40, fullDiskAccess: Bool = true) -> DiskUsageService {
        var service = DiskUsageService(privacy: PrivacyProtectedLocations(paths: fake.paths, hasFullDiskAccess: fullDiskAccess))
        service.maxChildrenPerFolder = maxChildren
        return service
    }

    func testBuildsSizeTreeSortedBySize() async throws {
        try fake.file("Movies/big.mov", size: 400_000)
        try fake.file("Documents/a.txt", size: 10_000)
        try fake.file("Documents/sub/b.txt", size: 20_000)
        try fake.file("notes.txt", size: 5_000)

        let root = try await service().scan(fake.home) { _ in }
        XCTAssertEqual(root.children.map(\.name), ["Movies", "Documents", "notes.txt"])
        XCTAssertEqual(root.size, root.children.reduce(0) { $0 + $1.size })
        XCTAssertEqual(root.fileCount, 4)
        let documents = try XCTUnwrap(root.children.first { $0.name == "Documents" })
        XCTAssertEqual(documents.children.map(\.name), ["sub", "a.txt"])
        XCTAssertTrue(documents.canDrillDown)
    }

    func testSmallChildrenAreFoldedIntoOther() async throws {
        for index in 0..<10 { try fake.file("Many/file\(index).bin", size: 8_192 * (index + 1)) }
        let root = try await service(maxChildren: 4).scan(fake.home) { _ in }
        let many = try XCTUnwrap(root.children.first)
        XCTAssertEqual(many.children.count, 5)
        guard case .other(let count) = try XCTUnwrap(many.children.last).kind else { return XCTFail("expected other node") }
        XCTAssertEqual(count, 6)
        XCTAssertEqual(many.size, many.children.reduce(0) { $0 + $1.size })
    }

    func testPackagesAreLeavesAndSymlinksAreIgnored() async throws {
        try fake.file("Applications/Tool.app/Contents/MacOS/Tool", size: 50_000)
        try FileManager.default.createSymbolicLink(at: fake.home.appending(path: "link"), withDestinationURL: URL(fileURLWithPath: "/System"))
        let root = try await service().scan(fake.home) { _ in }
        let apps = try XCTUnwrap(root.children.first { $0.name == "Applications" })
        XCTAssertEqual(apps.children.first?.kind, .package)
        XCTAssertEqual(apps.children.first?.children.isEmpty, true)
        XCTAssertNil(root.children.first { $0.name == "link" })
    }

    func testProtectedFoldersAreSkippedWithoutAccess() async throws {
        try fake.file("Library/Mail/V10/message.emlx", size: 10_000)
        try fake.file("Library/Preferences/a.plist", size: 10_000)
        let root = try await service(fullDiskAccess: false).scan(fake.home) { _ in }
        let library = try XCTUnwrap(root.children.first { $0.name == "Library" })
        XCTAssertEqual(library.children.map(\.name), ["Preferences"], "Mail is skipped and has no size")
    }

    func testRemovingUpdatesAncestorSizes() async throws {
        try fake.file("A/B/big.bin", size: 100_000)
        try fake.file("A/small.bin", size: 10_000)
        let root = try await service().scan(fake.home) { _ in }
        let folderA = try XCTUnwrap(root.children.first)
        let folderB = try XCTUnwrap(folderA.children.first { $0.name == "B" })
        let big = try XCTUnwrap(root.descendant(at: [folderA.id, folderB.id])?.children.first)
        let bigPath = big.id
        let originalSize = root.size
        let bigSize = big.size

        let updated = root.removing([bigPath])
        XCTAssertEqual(updated.size, originalSize - bigSize)
        XCTAssertEqual(updated.fileCount, root.fileCount - 1)
        XCTAssertEqual(updated.children.first?.size, root.children.first.map { $0.size - bigSize })
    }

    func testReportsProgress() async throws {
        try fake.file("x.bin", size: 4_096)
        let counter = Counter()
        _ = try await service().scan(fake.home) { _ in counter.increment() }
        XCTAssertGreaterThan(counter.value, 0)
    }
}
