import Foundation

struct JunkItem: Identifiable, Hashable, Sendable {
    var id: String { url.path }
    let url: URL
    let name: String
    let size: Int64
    let modified: Date?
    let selectedByDefault: Bool
}

struct JunkCategoryResult: Identifiable, Sendable {
    var id: JunkCategoryID { category.id }
    let category: JunkCategory
    var items: [JunkItem]
    /// Number of locations that could not be read (usually missing Full Disk Access).
    var unreadableLocations: Int

    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
}

/// Finds junk for the given categories. Categories are scanned concurrently; each item is
/// measured recursively and checked against the blocklist before it is offered to the user.
struct JunkScanService: Sendable {
    let categories: [JunkCategory]
    let protection: ProtectedPaths
    let privacy: PrivacyProtectedLocations
    var now: @Sendable () -> Date = { Date() }

    init(categories: [JunkCategory], protection: ProtectedPaths, hasFullDiskAccess: Bool = true) {
        self.categories = categories
        self.protection = protection
        self.privacy = PrivacyProtectedLocations(paths: protection.paths, hasFullDiskAccess: hasFullDiskAccess)
    }

    func scan(progress: @escaping @Sendable (ScanProgress) -> Void) async throws -> [JunkCategoryResult] {
        let throttle = ProgressThrottle<ScanProgress>(handler: progress)
        let total = Double(max(categories.count, 1))
        let counter = Counter()

        let results = try await withThrowingTaskGroup(of: (Int, JunkCategoryResult).self) { group in
            for (index, category) in categories.enumerated() {
                group.addTask {
                    let result = try scan(category) { path in
                        throttle.send(ScanProgress(fraction: counter.value / total, message: "Suche nach \(category.title) …", currentPath: path))
                    }
                    let done = counter.increment()
                    throttle.send(ScanProgress(fraction: done / total, message: "\(category.title) geprüft", currentPath: ""), force: done == total)
                    return (index, result)
                }
            }
            var collected: [(Int, JunkCategoryResult)] = []
            for try await result in group { collected.append(result) }
            return collected.sorted { $0.0 < $1.0 }.map(\.1)
        }
        return results
    }

    /// Scans a single category synchronously. Exposed for tests.
    func scan(_ category: JunkCategory, onPath: (String) -> Void = { _ in }) throws -> JunkCategoryResult {
        var items: [JunkItem] = []
        var seen = Set<String>()
        var unreadable = 0
        var skippedForPrivacy = false

        for source in category.sources {
            try Task.checkCancellation()
            if privacy.shouldSkip(source.root) {
                unreadable += 1
                continue
            }
            guard FileSizer.exists(source.root) else { continue }
            guard let candidates = candidates(for: source) else {
                unreadable += 1
                continue
            }
            for url in candidates {
                try Task.checkCancellation()
                let name = url.lastPathComponent
                guard !source.excludedNames.contains(name), !seen.contains(url.path) else { continue }
                guard protection.isAllowed(url) else { continue }
                if privacy.shouldSkip(url) {
                    skippedForPrivacy = true
                    continue
                }
                let values = try? url.resourceValues(forKeys: Set(FileSizer.resourceKeys))
                if let minimumAge = source.minimumAge {
                    let modified = values?.contentModificationDate ?? .distantPast
                    guard now().timeIntervalSince(modified) >= minimumAge else { continue }
                }
                onPath(url.path)
                let measurement = try FileSizer.measure(url) { onPath($0.path) }
                guard measurement.bytes > 0 else { continue }
                seen.insert(url.path)
                items.append(JunkItem(
                    url: url,
                    name: displayName(for: url, source: source),
                    size: measurement.bytes,
                    modified: values?.contentModificationDate,
                    selectedByDefault: source.selectedByDefault && category.selectedByDefault
                ))
            }
        }
        items.sort { $0.size > $1.size }
        if skippedForPrivacy { unreadable += 1 }
        return JunkCategoryResult(category: category, items: items, unreadableLocations: unreadable)
    }

    private func candidates(for source: JunkSource) -> [URL]? {
        switch source.strategy {
        case .itself:
            return [source.root]
        case .children:
            return FileSizer.children(of: source.root)
        case .nested(let subpath):
            guard let containers = FileSizer.children(of: source.root) else { return nil }
            return containers
                .map { $0.appending(path: subpath, directoryHint: .isDirectory) }
                .filter { FileSizer.exists($0) }
        }
    }

    private func displayName(for url: URL, source: JunkSource) -> String {
        switch source.strategy {
        case .itself:
            return source.label ?? url.lastPathComponent
        case .nested:
            // ~/Library/Containers/<bundle id>/Data/Library/Caches → show the bundle id.
            let components = url.pathComponents
            if let index = components.lastIndex(of: "Data"), index > 0 { return components[index - 1] }
            return url.lastPathComponent
        case .children:
            if let label = source.label { return "\(label): \(url.lastPathComponent)" }
            return url.lastPathComponent
        }
    }
}
