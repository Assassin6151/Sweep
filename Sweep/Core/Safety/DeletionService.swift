import Foundation
import Observation

/// The single entry point modules use to delete anything. Runs the deletion off the main
/// thread, applies the blocklist (including the user's own exclusions) and writes the log.
@MainActor
final class DeletionService {
    let log: ActivityLog
    private let paths: SystemPaths
    private let trasher: FileTrasher

    init(log: ActivityLog, paths: SystemPaths = .current, trasher: FileTrasher = SystemTrasher()) {
        self.log = log
        self.paths = paths
        self.trasher = trasher
    }

    var protection: ProtectedPaths {
        ProtectedPaths(paths: paths, userExclusions: UserExclusions.load())
    }

    func perform(_ plan: DeletionPlan) async -> DeletionOutcome {
        let deleter = SafeDeleter(protection: protection, trasher: trasher)
        let outcome = await Task.detached(priority: .userInitiated) {
            deleter.execute(plan)
        }.value
        log.record(outcome.entry)
        return outcome
    }

    /// Moves a previously trashed item back to where it came from.
    func restore(item: ActivityItem, in entry: ActivityEntry) throws {
        guard let trashed = item.trashedPath else { throw RestoreError.notInTrash }
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: trashed) else { throw RestoreError.notInTrash }
        guard !fileManager.fileExists(atPath: item.path) else { throw RestoreError.destinationExists }
        let destination = URL(fileURLWithPath: item.path)
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.moveItem(at: URL(fileURLWithPath: trashed), to: destination)
        log.markRestored(itemID: item.id, in: entry.id)
    }

    enum RestoreError: LocalizedError {
        case notInTrash, destinationExists

        var errorDescription: String? {
            switch self {
            case .notInTrash: "Die Datei liegt nicht mehr im Papierkorb."
            case .destinationExists: "Am ursprünglichen Ort existiert bereits eine Datei mit diesem Namen."
            }
        }
    }
}

/// Folders the user excluded in Settings. They are added to the blocklist and skipped by scans.
enum UserExclusions {
    static let key = "userExclusions"

    static func load(_ defaults: UserDefaults = .standard) -> [String] {
        defaults.stringArray(forKey: key) ?? []
    }

    static func save(_ paths: [String], _ defaults: UserDefaults = .standard) {
        defaults.set(paths, forKey: key)
    }
}
