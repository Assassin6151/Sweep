import Foundation

/// Locations macOS guards with privacy prompts (TCC / app data protection). Touching them without
/// Full Disk Access either fails or – worse – blocks until the user answers a system dialog.
/// Scanners skip them unless Full Disk Access has been granted.
struct PrivacyProtectedLocations: Sendable {
    let paths: SystemPaths
    let hasFullDiskAccess: Bool

    private var protectedRoots: [String] {
        let library = paths.userLibrary.path
        let relative = [
            "Containers", "Group Containers", "Mail", "Messages", "Safari", "Calendars", "Reminders",
            "HomeKit", "IdentityServices", "Suggestions", "Biome", "Cookies", "Sharing", "Shortcuts",
            "Metadata/CoreSpotlight", "PersonalizationPortrait", "Application Support/AddressBook",
            "Application Support/CallHistoryDB", "Application Support/CallHistoryTransactions",
            "Application Support/com.apple.TCC", "Application Support/Knowledge",
            "Application Support/MobileSync", "Application Support/com.apple.sharedfilelist",
            "Application Support/FileProvider", "Accounts", "Mobile Documents", "CloudStorage", "Keychains",
        ]
        return relative.map { library + "/" + $0 } + [paths.trash.path]
    }

    /// Whether scanning `url` could trigger a privacy prompt and should therefore be skipped.
    func shouldSkip(_ url: URL) -> Bool {
        guard !hasFullDiskAccess else { return false }
        let path = ProtectedPaths.normalize(url.path)
        if protectedRoots.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) { return true }
        // Apple's own caches (Music, Photos, Safari, …) are protected individually.
        let caches = paths.userLibrary.path + "/Caches/"
        if path.hasPrefix(caches), path.dropFirst(caches.count).hasPrefix("com.apple.") { return true }
        // Photo libraries are packages full of protected data.
        if path.lowercased().contains(".photoslibrary") { return true }
        return false
    }
}
