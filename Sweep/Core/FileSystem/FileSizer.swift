import Foundation

/// Measures how much disk space files and folders really occupy (allocated size, not logical size).
enum FileSizer {
    static let resourceKeys: [URLResourceKey] = [
        .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .isPackageKey,
        .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey,
        .contentModificationDateKey, .contentAccessDateKey, .fileResourceIdentifierKey,
    ]

    struct Measurement: Sendable {
        var bytes: Int64 = 0
        var fileCount: Int = 0
        var unreadable = false
    }

    /// Size of a single file system entry (no recursion).
    static func entrySize(_ values: URLResourceValues) -> Int64 {
        Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
    }

    /// Recursively measures `url`. Symlinks are not followed. Throws `CancellationError` when the task is cancelled.
    static func measure(_ url: URL, onFile: (URL) -> Void = { _ in }) throws -> Measurement {
        var result = Measurement()
        let keys = Set(resourceKeys)
        guard let values = try? url.resourceValues(forKeys: keys) else {
            result.unreadable = true
            return result
        }
        if values.isSymbolicLink == true { return result }
        guard values.isDirectory == true else {
            result.bytes = entrySize(values)
            result.fileCount = 1
            return result
        }

        var sawError = false
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: resourceKeys, options: [],
            errorHandler: { _, _ in sawError = true; return true }
        ) else {
            result.unreadable = true
            return result
        }

        var counter = 0
        for case let child as URL in enumerator {
            counter += 1
            if counter % 256 == 0 {
                try Task.checkCancellation()
                onFile(child)
            }
            guard let childValues = try? child.resourceValues(forKeys: keys),
                  childValues.isRegularFile == true else { continue }
            result.bytes += entrySize(childValues)
            result.fileCount += 1
        }
        result.unreadable = sawError && result.fileCount == 0
        return result
    }

    /// Lists the direct children of a folder. Returns nil when the folder is not readable.
    static func children(of url: URL, includeHidden: Bool = true) -> [URL]? {
        let options: FileManager.DirectoryEnumerationOptions = includeHidden ? [] : [.skipsHiddenFiles]
        return try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: resourceKeys, options: options)
    }

    static func exists(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
    }
}

/// Forwards progress to the UI at most every `interval` seconds, so scans of millions of files
/// never flood the main thread.
final class ProgressThrottle<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var lastEmit = Date.distantPast
    private let interval: TimeInterval
    private let handler: @Sendable (Value) -> Void

    init(interval: TimeInterval = 0.08, handler: @escaping @Sendable (Value) -> Void) {
        self.interval = interval
        self.handler = handler
    }

    func send(_ value: Value, force: Bool = false) {
        lock.lock()
        let now = Date()
        let shouldEmit = force || now.timeIntervalSince(lastEmit) >= interval
        if shouldEmit { lastEmit = now }
        lock.unlock()
        if shouldEmit { handler(value) }
    }
}

/// Progress snapshot every scan service reports.
struct ScanProgress: Sendable, Equatable {
    var fraction: Double?
    var message: String
    var currentPath: String = ""
}

/// Wraps a main actor progress update into a closure that scan services can call from any thread.
@MainActor
func mainActorProgress<Value: Sendable>(_ apply: @escaping @MainActor (Value) -> Void) -> @Sendable (Value) -> Void {
    { value in Task { @MainActor in apply(value) } }
}
