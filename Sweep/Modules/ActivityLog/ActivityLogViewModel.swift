import Foundation
import Observation

@Observable
@MainActor
final class ActivityLogViewModel {
    var filter: SweepModule?
    var searchText = ""
    var expanded: Set<UUID> = []
    var errorMessage: String?
    var confirmClear = false

    private let deletion: DeletionService
    var log: ActivityLog { deletion.log }

    init(deletion: DeletionService) {
        self.deletion = deletion
    }

    var modulesInLog: [SweepModule] {
        let used = Set(log.entries.map(\.module))
        return SweepModule.allCases.filter { used.contains($0) }
    }

    var filteredEntries: [ActivityEntry] {
        log.entries.filter { entry in
            (filter == nil || entry.module == filter)
                && (searchText.isEmpty
                    || entry.title.localizedCaseInsensitiveContains(searchText)
                    || entry.items.contains { $0.path.localizedCaseInsensitiveContains(searchText) })
        }
    }

    /// Entries grouped by calendar day, newest first.
    var groupedEntries: [(day: Date, entries: [ActivityEntry])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: filteredEntries) { calendar.startOfDay(for: $0.date) }
        return groups.keys.sorted(by: >).map { ($0, groups[$0]!.sorted { $0.date > $1.date }) }
    }

    func canRestore(_ item: ActivityItem) -> Bool {
        guard item.status == .done, let trashed = item.trashedPath else { return false }
        return FileManager.default.fileExists(atPath: trashed)
    }

    func restore(_ item: ActivityItem, in entry: ActivityEntry) {
        do {
            try deletion.restore(item: item, in: entry)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggle(_ entry: ActivityEntry) {
        if expanded.contains(entry.id) { expanded.remove(entry.id) } else { expanded.insert(entry.id) }
    }

    func clear() {
        log.clear()
    }
}
