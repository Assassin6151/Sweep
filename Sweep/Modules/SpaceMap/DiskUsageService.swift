import Foundation
import os

/// One entry in the disk usage tree. Small entries are folded into an "other" node to keep the tree compact.
struct DiskNode: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case folder, file, package, other(count: Int), unreadable
    }

    let id: String
    let name: String
    let url: URL
    var size: Int64
    var kind: Kind
    var children: [DiskNode]
    var fileCount: Int

    var canDrillDown: Bool { kind == .folder && !children.isEmpty }
    var isRealItem: Bool {
        switch kind {
        case .other, .unreadable: false
        default: true
        }
    }

    /// Follows a list of child IDs from this node.
    func descendant(at path: [String]) -> DiskNode? {
        var node = self
        for id in path {
            guard let next = node.children.first(where: { $0.id == id }) else { return nil }
            node = next
        }
        return node
    }

    /// Removes the nodes with the given IDs anywhere in the tree and subtracts their sizes from all ancestors.
    func removing(_ ids: Set<String>) -> DiskNode {
        var copy = self
        var removedSize: Int64 = 0
        var removedFiles = 0
        copy.children = children.compactMap { child in
            if ids.contains(child.id) {
                removedSize += child.size
                removedFiles += child.fileCount
                return nil
            }
            let updated = child.removing(ids)
            removedSize += child.size - updated.size
            removedFiles += child.fileCount - updated.fileCount
            return updated
        }
        copy.size -= removedSize
        copy.fileCount -= removedFiles
        return copy
    }
}

struct DiskScanProgress: Sendable, Equatable {
    var bytes: Int64 = 0
    var files: Int = 0
    var currentPath = ""
}

/// Builds a size tree for a folder. Top level folders are scanned in parallel.
struct DiskUsageService: Sendable {
    var maxChildrenPerFolder = 40
    /// Children smaller than this share of their parent are merged into "other".
    var minimumShare = 0.003
    var excludedPaths: Set<String> = ["/System/Volumes", "/Volumes", "/dev", "/private/var/vm", "/net", "/home", "/cores"]
    let privacy: PrivacyProtectedLocations

    func scan(_ root: URL, progress: @escaping @Sendable (DiskScanProgress) -> Void) async throws -> DiskNode {
        let throttle = ProgressThrottle<DiskScanProgress>(interval: 0.1, handler: progress)
        let state = OSAllocatedUnfairLock(initialState: DiskScanProgress())
        let tally: @Sendable (Int64, URL) -> Void = { bytes, url in
            let snapshot = state.withLock { progress -> DiskScanProgress in
                progress.bytes += bytes
                progress.files += 1
                progress.currentPath = url.path
                return progress
            }
            throttle.send(snapshot)
        }

        guard let children = FileSizer.children(of: root) else {
            return DiskNode(id: root.path, name: root.lastPathComponent, url: root, size: 0, kind: .unreadable, children: [], fileCount: 0)
        }
        let nodes = try await withThrowingTaskGroup(of: DiskNode?.self) { group in
            var iterator = children.makeIterator()
            func addNext() -> Bool {
                guard let child = iterator.next() else { return false }
                group.addTask { try node(for: child, tally: tally) }
                return true
            }
            for _ in 0..<6 { _ = addNext() }
            var collected: [DiskNode] = []
            while let next = try await group.next() {
                if let next { collected.append(next) }
                _ = addNext()
            }
            return collected
        }
        throttle.send(state.withLock { $0 }, force: true)
        return folder(root, children: nodes)
    }

    /// Synchronous variant used by tests and by the recursion.
    func node(for url: URL, tally: (Int64, URL) -> Void = { _, _ in }) throws -> DiskNode? {
        try Task.checkCancellation()
        guard let values = try? url.resourceValues(forKeys: Set(FileSizer.resourceKeys)) else { return nil }
        if values.isSymbolicLink == true { return nil }
        let path = url.path
        if excludedPaths.contains(path) || privacy.shouldSkip(url) {
            return DiskNode(id: path, name: url.lastPathComponent, url: url, size: 0, kind: .unreadable, children: [], fileCount: 0)
        }
        if values.isDirectory != true {
            let size = FileSizer.entrySize(values)
            tally(size, url)
            return DiskNode(id: path, name: url.lastPathComponent, url: url, size: size, kind: .file, children: [], fileCount: 1)
        }
        if values.isPackage == true {
            let measurement = try FileSizer.measure(url)
            tally(measurement.bytes, url)
            return DiskNode(id: path, name: url.lastPathComponent, url: url, size: measurement.bytes, kind: .package, children: [], fileCount: measurement.fileCount)
        }
        guard let children = FileSizer.children(of: url) else {
            return DiskNode(id: path, name: url.lastPathComponent, url: url, size: 0, kind: .unreadable, children: [], fileCount: 0)
        }
        var nodes: [DiskNode] = []
        nodes.reserveCapacity(children.count)
        for child in children {
            if let node = try node(for: child, tally: tally) { nodes.append(node) }
        }
        return folder(url, children: nodes)
    }

    /// Creates a folder node, keeping only the biggest children and folding the rest into "other".
    func folder(_ url: URL, children: [DiskNode]) -> DiskNode {
        let sorted = children.filter { $0.size > 0 }.sorted { $0.size > $1.size }
        let total = sorted.reduce(0) { $0 + $1.size }
        let files = children.reduce(0) { $0 + $1.fileCount }
        let threshold = Int64(Double(total) * minimumShare)

        var kept: [DiskNode] = []
        var rest: [DiskNode] = []
        for child in sorted {
            if kept.count < maxChildrenPerFolder && child.size >= threshold { kept.append(child) } else { rest.append(child) }
        }
        if !rest.isEmpty {
            let restSize = rest.reduce(0) { $0 + $1.size }
            kept.append(DiskNode(id: url.path + "/#other", name: "\(rest.count) kleinere Objekte", url: url,
                                 size: restSize, kind: .other(count: rest.count), children: [],
                                 fileCount: rest.reduce(0) { $0 + $1.fileCount }))
        }
        return DiskNode(id: url.path, name: url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent,
                        url: url, size: total, kind: .folder, children: kept, fileCount: files)
    }
}

/// Capacity of the volume a folder lives on.
struct VolumeInfo: Sendable, Equatable {
    let name: String
    let total: Int64
    let available: Int64

    var used: Int64 { max(0, total - available) }
    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }

    init?(for url: URL) {
        let keys: Set<URLResourceKey> = [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey]
        guard let values = try? url.resourceValues(forKeys: keys), let total = values.volumeTotalCapacity else { return nil }
        name = values.volumeName ?? "Volume"
        self.total = Int64(total)
        available = values.volumeAvailableCapacityForImportantUsage ?? Int64(values.volumeAvailableCapacity ?? 0)
    }
}
