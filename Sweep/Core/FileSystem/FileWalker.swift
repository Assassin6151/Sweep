import Foundation

/// Walks folders and reports every regular file. Used by the duplicate and large file finders.
struct FileWalker: Sendable {
    var skipHidden = true
    /// Folders that are never entered (absolute, normalized paths).
    var excludedFolders: [String] = []
    let privacy: PrivacyProtectedLocations

    /// Calls `visit` for each regular file below `roots`. Package contents (apps, libraries) are skipped.
    func walk(_ roots: [URL], visit: (URL, URLResourceValues) throws -> Void) throws {
        let keys = FileSizer.resourceKeys
        let keySet = Set(keys)
        let excluded = excludedFolders.flatMap(ProtectedPaths.pathAndResolved)
        var options: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
        if skipHidden { options.insert(.skipsHiddenFiles) }

        for root in roots {
            guard !privacy.shouldSkip(root),
                  let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: options,
                                                                   errorHandler: { _, _ in true }) else { continue }
            var counter = 0
            for case let url as URL in enumerator {
                counter += 1
                if counter % 512 == 0 { try Task.checkCancellation() }
                guard let values = try? url.resourceValues(forKeys: keySet) else { continue }
                if values.isDirectory == true {
                    let path = url.path
                    if excluded.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) || privacy.shouldSkip(url) {
                        enumerator.skipDescendants()
                    }
                    continue
                }
                guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
                try visit(url, values)
            }
        }
    }
}
