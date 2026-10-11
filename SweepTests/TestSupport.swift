import Foundation
import XCTest
@testable import Sweep

/// A throwaway folder tree acting as a fake home directory.
final class FakeHome {
    let root: URL
    let home: URL
    let paths: SystemPaths

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "SweepTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        home = root.appending(path: "home", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let tmp = root.appending(path: "tmp", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        paths = SystemPaths(home: home, temporaryDirectory: tmp, systemRoot: root.appending(path: "sysroot", directoryHint: .isDirectory))
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    /// Creates a file with `size` bytes of the given repeating byte at `relative` (to home unless absolute base given).
    @discardableResult
    func file(_ relative: String, size: Int = 4096, byte: UInt8 = 0x41, base: URL? = nil, modified: Date? = nil) throws -> URL {
        let url = (base ?? home).appending(path: relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: byte, count: size).write(to: url)
        if let modified {
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        }
        return url
    }

    @discardableResult
    func file(_ relative: String, contents: Data, base: URL? = nil) throws -> URL {
        let url = (base ?? home).appending(path: relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url)
        return url
    }

    @discardableResult
    func folder(_ relative: String, base: URL? = nil) throws -> URL {
        let url = (base ?? home).appending(path: relative, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
}

/// Moves "trashed" files into a private folder instead of the real Trash.
final class RecordingTrasher: FileTrasher, @unchecked Sendable {
    let trashFolder: URL
    var failingPaths: Set<String> = []
    private(set) var trashed: [URL] = []
    private(set) var removed: [URL] = []

    init(trashFolder: URL) {
        self.trashFolder = trashFolder
        try? FileManager.default.createDirectory(at: trashFolder, withIntermediateDirectories: true)
    }

    func moveToTrash(_ url: URL) throws -> URL? {
        if failingPaths.contains(url.path) {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
        }
        let destination = trashFolder.appending(path: UUID().uuidString + "-" + url.lastPathComponent)
        try FileManager.default.moveItem(at: url, to: destination)
        trashed.append(url)
        return destination
    }

    func removePermanently(_ url: URL) throws {
        try FileManager.default.removeItem(at: url)
        removed.append(url)
    }
}
