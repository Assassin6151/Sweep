import XCTest
@testable import Sweep

final class DuplicateFinderTests: XCTestCase {
    private var fake: FakeHome!

    override func setUpWithError() throws {
        fake = try FakeHome()
    }

    private func finder(minimumSize: Int64 = 1, partial: Int = 1_024) -> DuplicateFinder {
        DuplicateFinder(minimumSize: minimumSize, partialHashLength: partial,
                        walker: FileWalker(privacy: PrivacyProtectedLocations(paths: fake.paths, hasFullDiskAccess: true)))
    }

    private func data(_ size: Int, seed: UInt8, tail: UInt8? = nil) -> Data {
        var bytes = (0..<size).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ Int(seed)) }
        if let tail { bytes[size - 1] = tail }
        return Data(bytes)
    }

    func testFindsIdenticalFilesAcrossFolders() async throws {
        let content = data(5_000, seed: 1)
        try fake.file("Documents/report.pdf", contents: content)
        try fake.file("Downloads/report (1).pdf", contents: content)
        try fake.file("Desktop/report copy.pdf", contents: content)
        try fake.file("Documents/other.pdf", contents: data(5_000, seed: 2))

        let groups = try await finder().scan([fake.home]) { _ in }
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].files.count, 3)
        XCTAssertEqual(groups[0].wastedBytes, 10_000)
    }

    func testSameSizeAndSameBeginningButDifferentEndIsNoDuplicate() async throws {
        // Identical first 1 KB (partial hash) but a different last byte: only the full hash tells them apart.
        try fake.file("a.bin", contents: data(4_096, seed: 7, tail: 1))
        try fake.file("b.bin", contents: data(4_096, seed: 7, tail: 2))
        let groups = try await finder(partial: 1_024).scan([fake.home]) { _ in }
        XCTAssertTrue(groups.isEmpty)
    }

    func testHardLinksAreNotDuplicates() async throws {
        let original = try fake.file("photo.jpg", contents: data(3_000, seed: 3))
        try FileManager.default.linkItem(at: original, to: fake.home.appending(path: "photo-link.jpg"))
        let groups = try await finder().scan([fake.home]) { _ in }
        XCTAssertTrue(groups.isEmpty)
    }

    func testRespectsMinimumSizeAndSkipsHiddenFiles() async throws {
        try fake.file("small1.txt", contents: data(100, seed: 4))
        try fake.file("small2.txt", contents: data(100, seed: 4))
        try fake.file(".hidden/a.bin", contents: data(5_000, seed: 5))
        try fake.file(".hidden/b.bin", contents: data(5_000, seed: 5))
        let groups = try await finder(minimumSize: 1_000).scan([fake.home]) { _ in }
        XCTAssertTrue(groups.isEmpty)
    }

    func testHashIsStableAndRespectsLimit() throws {
        let url = try fake.file("x.bin", contents: data(10_000, seed: 9))
        XCTAssertEqual(DuplicateFinder.hash(url, limit: nil), DuplicateFinder.hash(url, limit: nil))
        XCTAssertNotEqual(DuplicateFinder.hash(url, limit: 100), DuplicateFinder.hash(url, limit: nil))
    }
}

final class DuplicateSelectionTests: XCTestCase {
    private func group(_ id: String, _ files: [(String, TimeInterval)]) -> DuplicateGroup {
        DuplicateGroup(id: id, size: 100, files: files.map {
            DuplicateFile(url: URL(fileURLWithPath: $0.0), size: 100, modified: Date(timeIntervalSince1970: $0.1))
        })
    }

    private lazy var groups = [
        group("g1", [("/a/long/path/file.txt", 100), ("/b/file.txt", 300), ("/c/file.txt", 200)]),
        group("g2", [("/x/one.mov", 50), ("/y/one.mov", 10)]),
    ]

    func testKeepNewest() {
        let selection = DuplicateSelection.autoSelect(groups, rule: .newest)
        XCTAssertEqual(selection, ["/a/long/path/file.txt", "/c/file.txt", "/y/one.mov"])
    }

    func testKeepOldest() {
        let selection = DuplicateSelection.autoSelect(groups, rule: .oldest)
        XCTAssertEqual(selection, ["/b/file.txt", "/c/file.txt", "/x/one.mov"])
    }

    func testKeepShortestPath() {
        let selection = DuplicateSelection.autoSelect(groups, rule: .shortestPath)
        XCTAssertFalse(selection.contains("/b/file.txt"))
        XCTAssertTrue(selection.contains("/a/long/path/file.txt"))
    }

    func testValidationAlwaysKeepsOneCopy() {
        let everything = Set(groups.flatMap { $0.files.map(\.id) })
        let validated = DuplicateSelection.validated(everything, groups: groups, rule: .newest)
        for group in groups {
            XCTAssertEqual(group.files.filter { !validated.contains($0.id) }.count, 1, group.id)
        }
        XCTAssertFalse(validated.contains("/b/file.txt"))
    }

    func testValidationLeavesPartialSelectionsAlone() {
        let selection: Set<String> = ["/a/long/path/file.txt"]
        XCTAssertEqual(DuplicateSelection.validated(selection, groups: groups), selection)
    }
}

final class LargeFileFinderTests: XCTestCase {
    func testFindsLargeFilesAndSkipsExcludedFolders() throws {
        let fake = try FakeHome()
        try fake.file("Movies/holiday.mov", size: 300_000)
        try fake.file("Downloads/installer.dmg", size: 200_000)
        try fake.file("Documents/small.txt", size: 1_000)
        try fake.file("Library/Caches/huge.bin", size: 500_000)
        try fake.file(".models/llm.bin", size: 400_000)

        let walker = FileWalker(skipHidden: false, excludedFolders: [fake.paths.userLibrary.path],
                                privacy: PrivacyProtectedLocations(paths: fake.paths, hasFullDiskAccess: true))
        let files = try LargeFileFinder(minimumSize: 100_000, walker: walker).scan([fake.home]) { _ in }
        XCTAssertEqual(files.map(\.name), ["llm.bin", "holiday.mov", "installer.dmg"])
        XCTAssertEqual(files.first { $0.name == "holiday.mov" }?.kind, .video)
        XCTAssertEqual(files.first { $0.name == "installer.dmg" }?.kind, .diskImage)
    }

    func testAgeFilterUsesLatestOfAccessAndModification() {
        let now = Date()
        let file = LargeFile(url: URL(fileURLWithPath: "/a"), size: 1, modified: now.addingTimeInterval(-400 * 86_400),
                             accessed: now.addingTimeInterval(-10 * 86_400), kind: .other)
        XCTAssertFalse(file.isOlder(thanDays: 30, now: now), "accessed recently")
        XCTAssertTrue(file.isOlder(thanDays: 0, now: now), "0 means no age filter")
        let old = LargeFile(url: URL(fileURLWithPath: "/b"), size: 1, modified: now.addingTimeInterval(-400 * 86_400),
                            accessed: now.addingTimeInterval(-380 * 86_400), kind: .other)
        XCTAssertTrue(old.isOlder(thanDays: 365, now: now))
    }

    func testFileKindClassification() {
        XCTAssertEqual(FileKind(url: URL(fileURLWithPath: "/a.mp4")), .video)
        XCTAssertEqual(FileKind(url: URL(fileURLWithPath: "/a.zip")), .archive)
        XCTAssertEqual(FileKind(url: URL(fileURLWithPath: "/a.pkg")), .installer)
        XCTAssertEqual(FileKind(url: URL(fileURLWithPath: "/a.heic")), .image)
        XCTAssertEqual(FileKind(url: URL(fileURLWithPath: "/a.pdf")), .document)
        XCTAssertEqual(FileKind(url: URL(fileURLWithPath: "/a.xyz123")), .other)
    }
}
