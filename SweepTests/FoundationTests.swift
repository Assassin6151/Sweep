import XCTest
@testable import Sweep

final class FoundationTests: XCTestCase {
    func testByteFormatSplitsValueAndUnit() {
        let parts = ByteFormat.parts(1_500_000_000)
        XCTAssertFalse(parts.value.isEmpty)
        XCTAssertEqual(parts.unit, "GB")
    }

    func testEveryModuleBelongsToASection() {
        let listed = SidebarSection.allCases.flatMap(\.modules)
        XCTAssertEqual(Set(listed), Set(SweepModule.allCases))
    }

    func testSystemPathsAreDerivedFromHome() {
        let home = URL(fileURLWithPath: "/tmp/fakehome", isDirectory: true)
        let paths = SystemPaths(home: home, temporaryDirectory: home, systemRoot: URL(fileURLWithPath: "/"))
        XCTAssertEqual(paths.userLibrary.path, "/tmp/fakehome/Library")
        XCTAssertEqual(paths.trash.path, "/tmp/fakehome/.Trash")
    }
}
