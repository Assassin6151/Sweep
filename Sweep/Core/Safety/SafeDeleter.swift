import Foundation

enum DeletionMode: String, Codable, Sendable {
    /// Move to the Trash – the default for everything.
    case moveToTrash
    /// Remove for good. Only allowed for items that already are in the Trash ("Papierkorb leeren").
    case permanent
}

/// One file or folder the user is about to remove.
struct DeletionCandidate: Identifiable, Hashable, Sendable {
    var id: String { url.path }
    let url: URL
    let size: Int64
    var mode: DeletionMode = .moveToTrash
    /// Optional context shown in the preview, e.g. the junk category.
    var context: String?
}

/// Everything the preview sheet needs to ask for confirmation.
struct DeletionPlan: Identifiable, Sendable {
    let id = UUID()
    var title: String
    var message: String
    var module: SweepModule
    var action: ActivityAction
    var candidates: [DeletionCandidate]
    var confirmTitle: String = "In den Papierkorb legen"

    var totalSize: Int64 { candidates.reduce(0) { $0 + $1.size } }
    var containsPermanent: Bool { candidates.contains { $0.mode == .permanent } }
}

/// Abstraction over the actual file operations so the deletion logic can be tested without touching the real Trash.
protocol FileTrasher: Sendable {
    /// Moves the item to the Trash and returns where it ended up.
    func moveToTrash(_ url: URL) throws -> URL?
    func removePermanently(_ url: URL) throws
}

struct SystemTrasher: FileTrasher {
    func moveToTrash(_ url: URL) throws -> URL? {
        var resulting: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
        return resulting as URL?
    }

    func removePermanently(_ url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }
}

struct DeletionOutcome: Sendable {
    var entry: ActivityEntry

    var removedItems: [ActivityItem] { entry.items.filter { $0.status == .done } }
    var problemItems: [ActivityItem] { entry.items.filter { $0.status != .done } }
    var freedBytes: Int64 { removedItems.reduce(0) { $0 + $1.size } }
    var removedPaths: Set<String> { Set(removedItems.map(\.path)) }
}

/// Executes a confirmed plan. Pure apart from the injected trasher, so it is fully unit tested.
struct SafeDeleter: Sendable {
    let protection: ProtectedPaths
    let trasher: FileTrasher

    func execute(_ plan: DeletionPlan) -> DeletionOutcome {
        var items: [ActivityItem] = []
        for candidate in plan.candidates {
            items.append(process(candidate))
        }
        let entry = ActivityEntry(module: plan.module, action: plan.action, title: plan.title, items: items)
        return DeletionOutcome(entry: entry)
    }

    private func process(_ candidate: DeletionCandidate) -> ActivityItem {
        let url = candidate.url
        var item = ActivityItem(path: url.path, size: candidate.size, mode: candidate.mode)

        if let reason = protection.verdict(for: url).reason {
            item.status = .blocked
            item.message = reason
            return item
        }
        if candidate.mode == .permanent && !protection.isInsideTrash(url) {
            item.status = .blocked
            item.message = "Endgültiges Löschen ist nur für Dateien im Papierkorb erlaubt."
            return item
        }
        // `attributesOfItem` does not follow symlinks, so dangling links still count as present.
        guard (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil else {
            item.status = .failed
            item.message = "Nicht mehr vorhanden."
            return item
        }
        do {
            switch candidate.mode {
            case .moveToTrash:
                item.trashedPath = try trasher.moveToTrash(url)?.path
            case .permanent:
                try trasher.removePermanently(url)
            }
            item.status = .done
        } catch {
            item.status = .failed
            item.message = Self.describe(error)
        }
        return item
    }

    static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain,
           [NSFileWriteNoPermissionError, NSFileReadNoPermissionError].contains(nsError.code) {
            return "Keine Berechtigung. Für diesen Eintrag sind Administratorrechte oder Festplattenvollzugriff nötig."
        }
        return nsError.localizedDescription
    }
}
