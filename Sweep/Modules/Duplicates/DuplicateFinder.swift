import CryptoKit
import Foundation

struct DuplicateFile: Identifiable, Hashable, Sendable {
    var id: String { url.path }
    let url: URL
    let size: Int64
    let modified: Date?
}

struct DuplicateGroup: Identifiable, Hashable, Sendable {
    let id: String
    let size: Int64
    var files: [DuplicateFile]

    /// Space that would be freed by keeping just one copy.
    var wastedBytes: Int64 { size * Int64(max(0, files.count - 1)) }
    var name: String { files.first?.url.lastPathComponent ?? "" }
}

/// Finds identical files in three increasingly expensive stages:
/// 1. group by exact size, 2. compare a hash of the first 64 KB, 3. compare a full SHA-256.
/// Hard links (the same file reached twice) are not reported as duplicates.
struct DuplicateFinder: Sendable {
    var minimumSize: Int64 = 1_048_576
    var partialHashLength = 65_536
    let walker: FileWalker

    func scan(_ roots: [URL], progress: @escaping @Sendable (ScanProgress) -> Void) async throws -> [DuplicateGroup] {
        let throttle = ProgressThrottle<ScanProgress>(handler: progress)

        // Stage 1: collect files by size.
        var bySize: [Int64: [DuplicateFile]] = [:]
        var seenIdentities = Set<NSObject>()
        var count = 0
        try walker.walk(roots) { url, values in
            let size = Int64(values.fileSize ?? 0)
            guard size >= minimumSize else { return }
            if let identity = values.fileResourceIdentifier as? NSObject {
                guard seenIdentities.insert(identity).inserted else { return }
            }
            bySize[size, default: []].append(DuplicateFile(url: url, size: size, modified: values.contentModificationDate))
            count += 1
            throttle.send(ScanProgress(fraction: nil, message: "\(count.formatted()) Dateien gefunden …", currentPath: url.path))
        }
        let sameSize = bySize.values.filter { $0.count > 1 }
        let totalBytes = Double(sameSize.reduce(0) { $0 + $1.reduce(0) { $0 + $1.size } })
        let hashed = Counter()

        // Stages 2 and 3, in parallel per size group.
        let groups = try await withThrowingTaskGroup(of: [DuplicateGroup].self) { group in
            var iterator = sameSize.makeIterator()
            func addNext() -> Bool {
                guard let files = iterator.next() else { return false }
                group.addTask {
                    let result = try duplicates(among: files)
                    let bytes = files.reduce(0) { $0 + $1.size }
                    let done = hashed.increment(by: Double(bytes))
                    throttle.send(ScanProgress(fraction: totalBytes > 0 ? done / totalBytes : 1,
                                               message: "Inhalte werden verglichen …", currentPath: files[0].url.path))
                    return result
                }
                return true
            }
            for _ in 0..<4 { _ = addNext() }
            var all: [DuplicateGroup] = []
            while let next = try await group.next() {
                all += next
                _ = addNext()
            }
            return all
        }
        throttle.send(ScanProgress(fraction: 1, message: "Fertig", currentPath: ""), force: true)
        return groups.sorted { $0.wastedBytes > $1.wastedBytes }
    }

    /// Splits files of identical size into groups of identical content.
    func duplicates(among files: [DuplicateFile]) throws -> [DuplicateGroup] {
        guard files.count > 1, let size = files.first?.size else { return [] }
        var byPartial: [String: [DuplicateFile]] = [:]
        for file in files {
            try Task.checkCancellation()
            guard let hash = Self.hash(file.url, limit: partialHashLength) else { continue }
            byPartial[hash, default: []].append(file)
        }
        var result: [DuplicateGroup] = []
        for (partial, candidates) in byPartial where candidates.count > 1 {
            if size <= Int64(partialHashLength) {
                result.append(DuplicateGroup(id: partial, size: size, files: candidates))
                continue
            }
            var byFull: [String: [DuplicateFile]] = [:]
            for file in candidates {
                try Task.checkCancellation()
                guard let hash = Self.hash(file.url, limit: nil) else { continue }
                byFull[hash, default: []].append(file)
            }
            for (full, same) in byFull where same.count > 1 {
                result.append(DuplicateGroup(id: full, size: size, files: same.sorted { $0.url.path < $1.url.path }))
            }
        }
        return result
    }

    /// SHA-256 of the first `limit` bytes, or the whole file when `limit` is nil. Streams in 1 MB chunks.
    static func hash(_ url: URL, limit: Int?) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        var remaining = limit ?? Int.max
        while remaining > 0 {
            if Task.isCancelled { return nil }
            let chunk = min(1_048_576, remaining)
            guard let data = try? handle.read(upToCount: chunk), !data.isEmpty else { break }
            hasher.update(data: data)
            remaining -= data.count
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
