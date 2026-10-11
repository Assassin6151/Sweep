import Foundation
import Observation

@Observable
@MainActor
final class LargeFilesViewModel {
    enum Phase: Equatable { case idle, scanning, results, removing }

    private(set) var phase: Phase = .idle
    private(set) var progress = ScanProgress(fraction: nil, message: "")
    private(set) var files: [LargeFile] = []
    var includeLibrary = false
    var minimumSize: Int64 = 100 * 1_048_576
    var olderThanDays = 0
    var kindFilter: FileKind?
    var sortOrder = [KeyPathComparator(\LargeFile.size, order: .reverse)]
    var selection: Set<String> = []
    var pendingPlan: DeletionPlan?
    var lastOutcome: DeletionOutcome?

    /// Files are collected from this size on; higher thresholds only filter.
    static let scanFloor: Int64 = 50 * 1_048_576

    private let deletion: DeletionService
    private let permissions: PermissionService
    private let paths: SystemPaths
    private var scanTask: Task<Void, Never>?

    init(deletion: DeletionService, permissions: PermissionService, paths: SystemPaths = .current) {
        self.deletion = deletion
        self.permissions = permissions
        self.paths = paths
    }

    var protection: ProtectedPaths { deletion.protection }

    var visibleFiles: [LargeFile] {
        files
            .filter { $0.size >= minimumSize && $0.isOlder(thanDays: olderThanDays) && (kindFilter == nil || $0.kind == kindFilter) }
            .sorted(using: sortOrder)
    }

    var visibleSize: Int64 { visibleFiles.reduce(0) { $0 + $1.size } }

    var selectedFiles: [LargeFile] { files.filter { selection.contains($0.id) } }
    var selectedSize: Int64 { selectedFiles.reduce(0) { $0 + $1.size } }

    /// Total size per kind of the currently size/age filtered files.
    var kindTotals: [(kind: FileKind, size: Int64, count: Int)] {
        let base = files.filter { $0.size >= minimumSize && $0.isOlder(thanDays: olderThanDays) }
        let groups = Dictionary(grouping: base, by: \.kind)
        return groups.map { ($0.key, $0.value.reduce(0) { $0 + $1.size }, $0.value.count) }.sorted { $0.size > $1.size }
    }

    func scan() {
        scanTask?.cancel()
        permissions.refresh()
        phase = .scanning
        lastOutcome = nil
        selection = []
        progress = ScanProgress(fraction: nil, message: "Dateien werden geprüft …")
        var excluded = [paths.trash.path]
        if !includeLibrary { excluded.append(paths.userLibrary.path) }
        let walker = FileWalker(skipHidden: false, excludedFolders: excluded,
                                privacy: PrivacyProtectedLocations(paths: paths, hasFullDiskAccess: permissions.hasFullDiskAccess))
        let finder = LargeFileFinder(minimumSize: Self.scanFloor, walker: walker)
        let root = paths.home
        let onProgress = mainActorProgress { [weak self] (update: ScanProgress) in
            guard self?.phase == .scanning else { return }
            self?.progress = update
        }
        scanTask = Task { [weak self] in
            do {
                let found = try await Task.detached(priority: .userInitiated) {
                    try finder.scan([root], progress: onProgress)
                }.value
                guard !Task.isCancelled, let self else { return }
                self.files = found
                self.phase = .results
            } catch {
                guard let self, self.phase == .scanning else { return }
                self.phase = self.files.isEmpty ? .idle : .results
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
        phase = files.isEmpty ? .idle : .results
    }

    func prepareRemoval() {
        let candidates = selectedFiles.map { DeletionCandidate(url: $0.url, size: $0.size, context: $0.kind.title) }
        guard !candidates.isEmpty else { return }
        pendingPlan = DeletionPlan(
            title: "\(candidates.count) Dateien in den Papierkorb legen?",
            message: "Die Dateien werden in den Papierkorb gelegt und lassen sich von dort wiederherstellen.",
            module: .largeFiles, action: .removedFiles, candidates: candidates
        )
    }

    func execute(_ plan: DeletionPlan) {
        phase = .removing
        Task {
            let outcome = await deletion.perform(plan)
            let removed = outcome.removedPaths
            files.removeAll { removed.contains($0.id) }
            selection.subtract(removed)
            lastOutcome = outcome
            phase = .results
        }
    }
}
