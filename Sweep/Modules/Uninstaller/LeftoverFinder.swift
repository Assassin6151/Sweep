import Foundation

/// Finds the files an app leaves behind in the Library folders.
///
/// Matching rules, from most to least reliable:
/// 1. The entry name equals the bundle ID or starts with `<bundle ID>.` (preferences, containers, caches …)
/// 2. Group containers whose name contains the bundle ID (`TEAMID.com.vendor.app`, `group.com.vendor.app`)
/// 3. Crash reports that start with the executable name
/// 4. Folders named exactly like the app (only in a few places, never preselected)
struct LeftoverFinder: Sendable {
    struct Location: Sendable {
        let url: URL
        let kind: LeftoverKind
        let isSystemWide: Bool
        var matchesByName = false
        var isCrashReports = false
        var isGroupContainers = false
    }

    let paths: SystemPaths
    let protection: ProtectedPaths
    let privacy: PrivacyProtectedLocations

    init(paths: SystemPaths, protection: ProtectedPaths, hasFullDiskAccess: Bool) {
        self.paths = paths
        self.protection = protection
        self.privacy = PrivacyProtectedLocations(paths: paths, hasFullDiskAccess: hasFullDiskAccess)
    }

    var locations: [Location] {
        let user = paths.userLibrary
        let system = paths.systemLibrary
        func u(_ path: String, _ kind: LeftoverKind, byName: Bool = false) -> Location {
            Location(url: user.appending(path: path), kind: kind, isSystemWide: false, matchesByName: byName)
        }
        func s(_ path: String, _ kind: LeftoverKind, byName: Bool = false) -> Location {
            Location(url: system.appending(path: path), kind: kind, isSystemWide: true, matchesByName: byName)
        }
        return [
            u("Application Support", .appSupport, byName: true),
            u("Caches", .caches, byName: true),
            u("Preferences", .preferences),
            u("Preferences/ByHost", .preferences),
            u("Containers", .containers),
            Location(url: user.appending(path: "Group Containers"), kind: .groupContainers, isSystemWide: false, isGroupContainers: true),
            u("Saved Application State", .savedState),
            u("Logs", .logs, byName: true),
            Location(url: user.appending(path: "Logs/DiagnosticReports"), kind: .crashReports, isSystemWide: false, isCrashReports: true),
            u("HTTPStorages", .webData),
            u("WebKit", .webData),
            u("Cookies", .webData),
            u("LaunchAgents", .launchAgents),
            u("Application Scripts", .scripts),
            u("Internet Plug-Ins", .plugins),
            s("Application Support", .appSupport, byName: true),
            s("Caches", .caches),
            s("Preferences", .preferences),
            s("LaunchAgents", .launchAgents),
            s("LaunchDaemons", .launchDaemons),
            s("PrivilegedHelperTools", .helpers),
            s("Logs", .logs, byName: true),
        ]
    }

    func findLeftovers(for app: InstalledApp) throws -> (leftovers: [Leftover], skippedLocations: Int) {
        var results: [Leftover] = []
        var seen = Set<String>()
        var skipped = 0

        for location in locations {
            try Task.checkCancellation()
            if privacy.shouldSkip(location.url) {
                skipped += 1
                continue
            }
            guard let children = FileSizer.children(of: location.url) else { continue }
            for child in children {
                guard let confidence = match(child.lastPathComponent, app: app, location: location),
                      !seen.contains(child.path),
                      !child.path.hasPrefix(app.url.path + "/"),
                      protection.isAllowed(child),
                      !privacy.shouldSkip(child) else { continue }
                seen.insert(child.path)
                let size = (try? FileSizer.measure(child).bytes) ?? 0
                results.append(Leftover(url: child, kind: location.kind, confidence: confidence,
                                        size: size, isSystemWide: location.isSystemWide))
            }
        }
        results.sort { lhs, rhs in
            lhs.kind == rhs.kind ? lhs.size > rhs.size
                : LeftoverKind.allCases.firstIndex(of: lhs.kind)! < LeftoverKind.allCases.firstIndex(of: rhs.kind)!
        }
        return (results, skipped)
    }

    func match(_ entryName: String, app: InstalledApp, location: Location) -> MatchConfidence? {
        let name = Self.stripExtensions(entryName).lowercased()
        let bundleID = app.bundleID.lowercased()
        guard !bundleID.isEmpty else { return nil }

        if name == bundleID || name.hasPrefix(bundleID + ".") || name.hasPrefix(bundleID + "-") {
            return .high
        }
        if location.isGroupContainers {
            if name.hasSuffix("." + bundleID) || name.contains("." + bundleID + ".") || name == "group." + bundleID {
                return .high
            }
        }
        if location.isCrashReports, let executable = app.executableName?.lowercased(), executable.count >= 4 {
            if name.hasPrefix(executable + "-") || name.hasPrefix(executable + "_") { return .high }
        }
        if location.matchesByName {
            let appName = Self.normalizedName(app.name)
            if appName.count >= 4, Self.normalizedName(name) == appName { return .medium }
        }
        return nil
    }

    static func stripExtensions(_ name: String) -> String {
        for suffix in [".plist", ".savedstate", ".binarycookies", ".ips", ".crash", ".diag", ".log"] where name.lowercased().hasSuffix(suffix) {
            return String(name.dropLast(suffix.count))
        }
        return name
    }

    static func normalizedName(_ name: String) -> String {
        name.lowercased().filter { !$0.isWhitespace && $0 != "-" && $0 != "_" }
    }
}
