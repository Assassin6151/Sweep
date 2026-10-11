import AppKit
import Observation

/// Checks Full Disk Access and leads the user to the right pane in System Settings.
@Observable
@MainActor
final class PermissionService {
    private(set) var hasFullDiskAccess = false
    private(set) var lastChecked: Date?

    init() {
        refresh()
    }

    func refresh() {
        hasFullDiskAccess = FullDiskAccessProbe.isGranted()
        lastChecked = .now
    }

    func openFullDiskAccessSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles",
        ]
        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) { return }
        }
    }

    func revealAppInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    /// Starts a fresh instance of Sweep and quits this one, so a newly granted permission takes effect.
    func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }
}

/// Full Disk Access cannot be queried directly; we probe files that are only readable with it.
enum FullDiskAccessProbe {
    static func isGranted(paths: SystemPaths = .current) -> Bool {
        let probes = [
            paths.system("Library/Application Support/com.apple.TCC/TCC.db").path(percentEncoded: false),
            paths.user("Library/Safari/CloudTabs.db").path(percentEncoded: false),
            paths.user("Library/Safari/Bookmarks.plist").path(percentEncoded: false),
        ]
        for probe in probes where FileManager.default.fileExists(atPath: probe) {
            if let handle = FileHandle(forReadingAtPath: probe) {
                try? handle.close()
                return true
            }
            return false
        }
        // Fallback: the Safari container listing is protected as well.
        return (try? FileManager.default.contentsOfDirectory(atPath: paths.user("Library/Safari").path(percentEncoded: false))) != nil
    }
}
