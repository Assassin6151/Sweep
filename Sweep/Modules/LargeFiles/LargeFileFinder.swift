import Foundation

struct LargeFile: Identifiable, Hashable, Sendable {
    var id: String { url.path }
    let url: URL
    let size: Int64
    let modified: Date?
    let accessed: Date?
    let kind: FileKind

    var name: String { url.lastPathComponent }
    var folder: String { url.deletingLastPathComponent().path }

    /// The most recent sign of use: the later of last access and last modification.
    var lastUsed: Date? {
        switch (accessed, modified) {
        case let (a?, m?): max(a, m)
        case let (a?, nil): a
        case let (nil, m?): m
        default: nil
        }
    }

    func isOlder(thanDays days: Int, now: Date = .now) -> Bool {
        guard days > 0 else { return true }
        guard let lastUsed else { return true }
        return now.timeIntervalSince(lastUsed) > Double(days) * 86_400
    }
}

/// Finds every file above a size threshold. Filtering by age and kind happens in the view model,
/// so the user can change filters without scanning again.
struct LargeFileFinder: Sendable {
    var minimumSize: Int64 = 50 * 1_048_576
    let walker: FileWalker

    func scan(_ roots: [URL], progress: @escaping @Sendable (ScanProgress) -> Void) throws -> [LargeFile] {
        let throttle = ProgressThrottle<ScanProgress>(handler: progress)
        var found: [LargeFile] = []
        var checked = 0
        try walker.walk(roots) { url, values in
            checked += 1
            throttle.send(ScanProgress(fraction: nil, message: "\(checked.formatted()) Dateien geprüft · \(found.count) große gefunden", currentPath: url.path))
            let size = FileSizer.entrySize(values)
            guard size >= minimumSize else { return }
            found.append(LargeFile(url: url, size: size, modified: values.contentModificationDate,
                                   accessed: values.contentAccessDate, kind: FileKind(url: url)))
        }
        return found.sorted { $0.size > $1.size }
    }
}
