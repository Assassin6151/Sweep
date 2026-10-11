import AppKit
import Observation

@Observable
@MainActor
final class DuplicatesViewModel {
    enum Phase: Equatable { case idle, scanning, results, removing }

    private(set) var phase: Phase = .idle
    private(set) var progress = ScanProgress(fraction: nil, message: "")
    private(set) var groups: [DuplicateGroup] = []
    var roots: [URL]
    var minimumSize: Int64 = 1_048_576
    var keepRule: KeepRule = .newest {
        didSet { selection = DuplicateSelection.autoSelect(groups, rule: keepRule) }
    }
    var selection: Set<String> = []
    var expanded: Set<String> = []
    var pendingPlan: DeletionPlan?
    var lastOutcome: DeletionOutcome?
    var hint: String?

    private let deletion: DeletionService
    private let permissions: PermissionService
    private let paths: SystemPaths
    private var scanTask: Task<Void, Never>?

    init(deletion: DeletionService, permissions: PermissionService, paths: SystemPaths = .current) {
        self.deletion = deletion
        self.permissions = permissions
        self.paths = paths
        roots = ["Desktop", "Documents", "Downloads", "Pictures", "Movies", "Music"]
            .map { paths.home.appending(path: $0, directoryHint: .isDirectory) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    var protection: ProtectedPaths { deletion.protection }
    var totalWasted: Int64 { groups.reduce(0) { $0 + $1.wastedBytes } }
    var duplicateFileCount: Int { groups.reduce(0) { $0 + $1.files.count - 1 } }

    var selectedSize: Int64 {
        groups.reduce(0) { total, group in total + group.files.filter { selection.contains($0.id) }.reduce(0) { $0 + $1.size } }
    }

    // MARK: Folders

    func addFolders() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Hinzufügen"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls where !roots.contains(url) { roots.append(url) }
    }

    func remove(_ root: URL) {
        roots.removeAll { $0 == root }
    }

    // MARK: Scanning

    func scan() {
        guard !roots.isEmpty else { return }
        scanTask?.cancel()
        permissions.refresh()
        phase = .scanning
        lastOutcome = nil
        progress = ScanProgress(fraction: nil, message: "Dateien werden gesammelt …")
        let walker = FileWalker(privacy: PrivacyProtectedLocations(paths: paths, hasFullDiskAccess: permissions.hasFullDiskAccess))
        let finder = DuplicateFinder(minimumSize: minimumSize, walker: walker)
        let roots = self.roots
        let onProgress = mainActorProgress { [weak self] (update: ScanProgress) in
            guard self?.phase == .scanning else { return }
            self?.progress = update
        }
        scanTask = Task { [weak self] in
            do {
                let groups = try await Task.detached(priority: .userInitiated) {
                    try await finder.scan(roots, progress: onProgress)
                }.value
                guard !Task.isCancelled, let self else { return }
                self.groups = groups
                self.selection = DuplicateSelection.autoSelect(groups, rule: self.keepRule)
                self.expanded = Set(groups.prefix(3).map(\.id))
                self.phase = .results
            } catch {
                guard let self, self.phase == .scanning else { return }
                self.phase = self.groups.isEmpty ? .idle : .results
            }
        }
    }

    func scanAndWait() async {
        scan()
        await scanTask?.value
    }

    func cancel() {
        scanTask?.cancel()
        scanTask = nil
        phase = groups.isEmpty ? .idle : .results
    }

    func newScan() {
        groups = []
        selection = []
        phase = .idle
    }

    // MARK: Selection

    func toggle(_ file: DuplicateFile, in group: DuplicateGroup) {
        if selection.contains(file.id) {
            selection.remove(file.id)
            return
        }
        let remaining = group.files.filter { !selection.contains($0.id) && $0.id != file.id }
        guard !remaining.isEmpty else {
            hint = "Mindestens eine Kopie bleibt immer erhalten."
            return
        }
        selection.insert(file.id)
    }

    func toggleExpanded(_ group: DuplicateGroup) {
        if expanded.contains(group.id) { expanded.remove(group.id) } else { expanded.insert(group.id) }
    }

    // MARK: Removing

    func prepareRemoval() {
        let safeSelection = DuplicateSelection.validated(selection, groups: groups, rule: keepRule)
        let candidates = groups.flatMap { group in
            group.files.filter { safeSelection.contains($0.id) }.map { DeletionCandidate(url: $0.url, size: $0.size, context: group.name) }
        }
        guard !candidates.isEmpty else { return }
        pendingPlan = DeletionPlan(
            title: "\(candidates.count) Duplikate entfernen?",
            message: "Von jeder Gruppe bleibt mindestens eine Kopie erhalten. Die ausgewählten Kopien werden in den Papierkorb gelegt.",
            module: .duplicates, action: .removedFiles, candidates: candidates
        )
    }

    func execute(_ plan: DeletionPlan) {
        phase = .removing
        Task {
            let outcome = await deletion.perform(plan)
            let removed = outcome.removedPaths
            for index in groups.indices {
                groups[index].files.removeAll { removed.contains($0.id) }
            }
            groups.removeAll { $0.files.count < 2 }
            selection.subtract(removed)
            selection = DuplicateSelection.validated(selection, groups: groups, rule: keepRule)
            lastOutcome = outcome
            phase = .results
        }
    }
}
