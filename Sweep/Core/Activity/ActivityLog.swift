import Foundation
import Observation

enum ActivityAction: String, Codable, Sendable {
    case cleaned, uninstalled, reset, emptiedTrash, removedThreat, removedFiles

    var title: String {
        switch self {
        case .cleaned: "Bereinigt"
        case .uninstalled: "Deinstalliert"
        case .reset: "Zurückgesetzt"
        case .emptiedTrash: "Papierkorb geleert"
        case .removedThreat: "Verdächtiges entfernt"
        case .removedFiles: "Dateien entfernt"
        }
    }
}

struct ActivityItem: Codable, Identifiable, Hashable, Sendable {
    enum Status: String, Codable, Sendable {
        case done, failed, blocked, restored
    }

    var id = UUID()
    var path: String
    var size: Int64
    var mode: DeletionMode = .moveToTrash
    var status: Status = .done
    var trashedPath: String?
    var message: String?

    var name: String { (path as NSString).lastPathComponent }
}

struct ActivityEntry: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var date = Date()
    var module: SweepModule
    var action: ActivityAction
    var title: String
    var items: [ActivityItem]

    var freedBytes: Int64 { items.filter { $0.status == .done }.reduce(0) { $0 + $1.size } }
    var succeededCount: Int { items.filter { $0.status == .done || $0.status == .restored }.count }
    var problemCount: Int { items.filter { $0.status == .failed || $0.status == .blocked }.count }
}

extension SweepModule: Codable {}

/// Persistent, append-only history of everything Sweep removed. Stored as JSON in Application Support.
@Observable
@MainActor
final class ActivityLog {
    private(set) var entries: [ActivityEntry] = []
    private let fileURL: URL

    nonisolated static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Sweep", directoryHint: .isDirectory)
    }

    init(fileURL: URL = ActivityLog.defaultDirectory.appending(path: "activity-log.json")) {
        self.fileURL = fileURL
        load()
    }

    var totalFreedBytes: Int64 { entries.reduce(0) { $0 + $1.freedBytes } }

    func record(_ entry: ActivityEntry) {
        guard !entry.items.isEmpty else { return }
        entries.insert(entry, at: 0)
        save()
    }

    func markRestored(itemID: UUID, in entryID: UUID) {
        guard let entryIndex = entries.firstIndex(where: { $0.id == entryID }),
              let itemIndex = entries[entryIndex].items.firstIndex(where: { $0.id == itemID }) else { return }
        entries[entryIndex].items[itemIndex].status = .restored
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        entries = (try? decoder.decode([ActivityEntry].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(entries).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Sweep: Aktivitätsprotokoll konnte nicht gespeichert werden: \(error)")
        }
    }
}
