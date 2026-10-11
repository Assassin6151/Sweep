import Foundation

/// The well-known locations Sweep works with. Injectable so services can be tested against temp folders.
struct SystemPaths: Sendable, Hashable {
    var home: URL
    var temporaryDirectory: URL
    var systemRoot: URL

    static let current = SystemPaths(
        home: FileManager.default.homeDirectoryForCurrentUser,
        temporaryDirectory: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true),
        systemRoot: URL(fileURLWithPath: "/", isDirectory: true)
    )

    var userLibrary: URL { home.appending(path: "Library", directoryHint: .isDirectory) }
    var systemLibrary: URL { systemRoot.appending(path: "Library", directoryHint: .isDirectory) }
    var trash: URL { home.appending(path: ".Trash", directoryHint: .isDirectory) }

    func user(_ relative: String) -> URL { home.appending(path: relative, directoryHint: .isDirectory) }
    func system(_ relative: String) -> URL { systemRoot.appending(path: relative, directoryHint: .isDirectory) }
}
