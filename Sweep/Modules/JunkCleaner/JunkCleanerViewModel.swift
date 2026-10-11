import Foundation
import Observation

@Observable
@MainActor
final class JunkCleanerViewModel {
    enum Phase: Equatable { case idle, scanning, results, cleaning }

    private(set) var phase: Phase = .idle
    private(set) var progress = ScanProgress(fraction: 0, message: "")
    private(set) var results: [JunkCategoryResult] = []
    private(set) var lastScan: Date?
    var selection: Set<String> = []
    var expanded: Set<JunkCategoryID> = []
    var pendingPlan: DeletionPlan?
    var lastOutcome: DeletionOutcome?

    private let deletion: DeletionService
    private let paths: SystemPaths
    private var scanTask: Task<Void, Never>?

    private let permissions: PermissionService

    init(deletion: DeletionService, permissions: PermissionService, paths: SystemPaths = .current) {
        self.deletion = deletion
        self.permissions = permissions
        self.paths = paths
    }

    var protection: ProtectedPaths { deletion.protection }

    var totalFound: Int64 { results.reduce(0) { $0 + $1.totalSize } }
    var unreadableLocations: Int { results.reduce(0) { $0 + $1.unreadableLocations } }

    var selectedItems: [(JunkItem, JunkCategory)] {
        results.flatMap { result in result.items.filter { selection.contains($0.id) }.map { ($0, result.category) } }
    }

    var selectedSize: Int64 { selectedItems.reduce(0) { $0 + $1.0.size } }

    // MARK: Scanning

    func scan() {
        guard phase != .scanning else { return }
        scanTask?.cancel()
        phase = .scanning
        lastOutcome = nil
        progress = ScanProgress(fraction: 0, message: "Scan wird vorbereitet …")
        permissions.refresh()
        let service = JunkScanService(categories: JunkCatalog.categories(paths: paths), protection: protection,
                                      hasFullDiskAccess: permissions.hasFullDiskAccess)
        let onProgress = mainActorProgress { [weak self] update in
            guard self?.phase == .scanning else { return }
            self?.progress = update
        }
        scanTask = Task { [weak self] in
            do {
                let results = try await service.scan(progress: onProgress)
                guard !Task.isCancelled else { return }
                self?.finish(with: results)
            } catch {
                guard let self, self.phase == .scanning else { return }
                self.phase = self.results.isEmpty ? .idle : .results
            }
        }
    }

    /// Awaitable variant used by the Smart Scan.
    func scanAndWait() async {
        scan()
        await scanTask?.value
    }

    /// Returns to the previous state immediately; the background work stops at its next checkpoint.
    func cancel() {
        scanTask?.cancel()
        scanTask = nil
        phase = results.isEmpty ? .idle : .results
    }

    private func finish(with results: [JunkCategoryResult]) {
        self.results = results.filter { !$0.items.isEmpty || $0.unreadableLocations > 0 }
        selection = Set(results.flatMap { $0.items.filter(\.selectedByDefault).map(\.id) })
        lastScan = .now
        phase = .results
    }

    // MARK: Selection

    func state(of result: JunkCategoryResult) -> SelectionBox.State {
        let selected = result.items.filter { selection.contains($0.id) }.count
        if selected == 0 { return .none }
        return selected == result.items.count ? .all : .some
    }

    func toggle(_ result: JunkCategoryResult) {
        let ids = Set(result.items.map(\.id))
        if state(of: result) == .all {
            selection.subtract(ids)
        } else {
            selection.formUnion(ids)
        }
    }

    func toggle(_ item: JunkItem) {
        if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
    }

    func toggleExpanded(_ id: JunkCategoryID) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }

    // MARK: Cleaning

    func prepareClean() {
        let candidates = selectedItems.map { item, category in
            DeletionCandidate(url: item.url, size: item.size, mode: category.deletionMode, context: category.title)
        }
        guard !candidates.isEmpty else { return }
        let onlyTrash = candidates.allSatisfy { $0.mode == .permanent }
        pendingPlan = DeletionPlan(
            title: onlyTrash ? "Papierkorb leeren?" : "Junk entfernen?",
            message: "Bitte prüfe die Liste. Einträge aus dem Papierkorb werden endgültig gelöscht, alles andere wird in den Papierkorb gelegt.",
            module: .junk,
            action: onlyTrash ? .emptiedTrash : .cleaned,
            candidates: candidates
        )
    }

    func clean(_ plan: DeletionPlan) {
        phase = .cleaning
        Task {
            let outcome = await deletion.perform(plan)
            apply(outcome)
        }
    }

    private func apply(_ outcome: DeletionOutcome) {
        let removed = outcome.removedPaths
        for index in results.indices {
            results[index].items.removeAll { removed.contains($0.id) }
        }
        results.removeAll { $0.items.isEmpty && $0.unreadableLocations == 0 }
        selection.subtract(removed)
        lastOutcome = outcome
        phase = .results
    }
}
