import CoreServices
import Foundation

/// Finds installed third party apps and reads their metadata.
struct AppDiscoveryService: Sendable {
    var roots: [URL]
    var ownBundleID: String
    /// Returns (last used, date added) for an app. Injectable for tests.
    var usageProvider: @Sendable (URL) -> (lastUsed: Date?, added: Date?) = AppDiscoveryService.spotlightUsage

    init(paths: SystemPaths = .current, ownBundleID: String = Bundle.main.bundleIdentifier ?? "") {
        roots = [paths.system("Applications"), paths.user("Applications")]
        self.ownBundleID = ownBundleID
    }

    init(roots: [URL], ownBundleID: String, usageProvider: @escaping @Sendable (URL) -> (lastUsed: Date?, added: Date?)) {
        self.roots = roots
        self.ownBundleID = ownBundleID
        self.usageProvider = usageProvider
    }

    func discover() throws -> [InstalledApp] {
        var apps: [InstalledApp] = []
        var seen = Set<String>()
        for root in roots {
            for url in appBundles(in: root) {
                try Task.checkCancellation()
                guard let app = readApp(at: url), !seen.contains(app.bundleID) else { continue }
                seen.insert(app.bundleID)
                apps.append(app)
            }
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// `.app` bundles directly in `root` and one level below (vendor folders like "/Applications/Adobe Photoshop 2026").
    func appBundles(in root: URL) -> [URL] {
        guard let children = FileSizer.children(of: root, includeHidden: false) else { return [] }
        var result: [URL] = []
        for child in children {
            if child.pathExtension == "app" {
                result.append(child)
            } else if (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                      let nested = FileSizer.children(of: child, includeHidden: false) {
                result += nested.filter { $0.pathExtension == "app" }
            }
        }
        return result
    }

    func readApp(at url: URL) -> InstalledApp? {
        guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier else { return nil }
        // Apple's apps are part of macOS; Sweep never offers to remove itself either.
        guard !bundleID.hasPrefix("com.apple."), bundleID != ownBundleID else { return nil }
        let info = bundle.infoDictionary ?? [:]
        let name = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        let usage = usageProvider(url)
        let receipt = url.appending(path: "Contents/_MASReceipt/receipt")
        return InstalledApp(
            url: url,
            name: name.isEmpty ? url.deletingPathExtension().lastPathComponent : name,
            bundleID: bundleID,
            version: info["CFBundleShortVersionString"] as? String,
            executableName: info["CFBundleExecutable"] as? String,
            isFromAppStore: FileManager.default.fileExists(atPath: receipt.path),
            lastUsed: usage.lastUsed,
            dateAdded: usage.added
        )
    }

    @Sendable
    static func spotlightUsage(_ url: URL) -> (lastUsed: Date?, added: Date?) {
        guard let item = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL) else { return (nil, nil) }
        let lastUsed = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
        let added = MDItemCopyAttribute(item, kMDItemDateAdded) as? Date
        return (lastUsed, added)
    }
}
