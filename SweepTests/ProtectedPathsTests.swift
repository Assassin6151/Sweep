import XCTest
@testable import Sweep

final class ProtectedPathsTests: XCTestCase {
    private var fake: FakeHome!
    private var protection: ProtectedPaths!

    override func setUpWithError() throws {
        fake = try FakeHome()
        protection = ProtectedPaths(paths: SystemPaths(home: fake.home, temporaryDirectory: fake.paths.temporaryDirectory, systemRoot: URL(fileURLWithPath: "/")))
    }

    private func blocked(_ path: String) -> Bool { !protection.isAllowed(URL(fileURLWithPath: path)) }
    private func home(_ relative: String) -> String { fake.home.appending(path: relative).path }

    func testSystemLocationsAreBlocked() {
        for path in ["/", "/System", "/System/Library/CoreServices/Finder.app", "/usr/bin/ls", "/bin/zsh",
                     "/private/etc/hosts", "/etc/hosts", "/Library", "/Applications", "/Users", "/Library/Caches",
                     "/Library/Keychains/System.keychain", "/private/var/db/foo", "/opt/homebrew"] {
            XCTAssertTrue(blocked(path), "\(path) must be protected")
        }
    }

    func testUserFoldersThemselvesAreBlockedButNotTheirContents() {
        for relative in ["", "Documents", "Desktop", "Downloads", "Library", "Library/Caches", "Library/Application Support", ".Trash"] {
            XCTAssertTrue(blocked(home(relative)), "~/\(relative) must be protected")
        }
        XCTAssertFalse(blocked(home("Library/Caches/com.example.app")))
        XCTAssertFalse(blocked(home("Documents/old-video.mov")))
        XCTAssertFalse(blocked(home("Library/Developer/Xcode/DerivedData/MyApp-abc")))
    }

    func testSensitiveUserDataIsBlocked() {
        XCTAssertTrue(blocked(home("Library/Keychains/login.keychain-db")))
        XCTAssertTrue(blocked(home("Library/Mobile Documents/com~apple~CloudDocs/Doc.pages")))
        XCTAssertTrue(blocked(home(".ssh/id_ed25519")))
        XCTAssertTrue(blocked(home("Library/Mail/V10")))
    }

    func testStructuralRules() {
        XCTAssertTrue(blocked("/Applications/Example.app/Contents/MacOS/Example"), "files inside app bundles")
        XCTAssertTrue(blocked(home("Pictures/Photos Library.photoslibrary/database/Photos.sqlite")))
        XCTAssertFalse(blocked("/Applications/Example.app"), "a third party app bundle itself may be removed")
        XCTAssertTrue(blocked("/Something"), "top level folders are protected")
    }

    func testPathTraversalIsNormalized() {
        XCTAssertTrue(blocked(home("Library/Caches/../../Documents")))
        XCTAssertTrue(blocked(home("Library/Caches/./")))
    }

    func testSymlinkedParentCannotBypassBlocklist() throws {
        let link = fake.home.appending(path: "sneaky")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: URL(fileURLWithPath: "/System/Library"))
        XCTAssertTrue(blocked(link.appending(path: "CoreServices").path))
    }

    func testUserExclusions() {
        let excluded = home("Projects/Important")
        let custom = ProtectedPaths(paths: protection.paths, userExclusions: [excluded])
        XCTAssertFalse(custom.isAllowed(URL(fileURLWithPath: excluded + "/build/cache.bin")))
        XCTAssertFalse(custom.isAllowed(URL(fileURLWithPath: excluded)))
        XCTAssertTrue(custom.isAllowed(URL(fileURLWithPath: home("Projects/Other/file"))))
    }

    func testAppleAppsAreBlocked() throws {
        let safari = URL(fileURLWithPath: "/Applications/Safari.app")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: safari.path))
        XCTAssertFalse(protection.isAllowed(safari))
    }

    func testTrashDetection() {
        XCTAssertTrue(protection.isInsideTrash(URL(fileURLWithPath: home(".Trash/old.zip"))))
        XCTAssertFalse(protection.isInsideTrash(URL(fileURLWithPath: home(".Trash"))))
        XCTAssertFalse(protection.isInsideTrash(URL(fileURLWithPath: home("Documents/.Trash-like/file"))))
        XCTAssertTrue(protection.isInsideTrash(URL(fileURLWithPath: "/Volumes/Backup/.Trashes/501/file")))
    }
}
