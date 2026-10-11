import AppKit
import Observation

@Observable
@MainActor
final class SpaceMapViewModel {
    enum Phase: Equatable { case idle, scanning, results }

    private(set) var phase: Phase = .idle
    private(set) var progress = DiskScanProgress()
    private(set) var root: DiskNode?
    private(set) var target: URL
    private(set) var volume: VolumeInfo?
    var path: [String] = []
    var hovered: DiskNode?
    var pendingPlan: DeletionPlan?
    var lastOutcome: DeletionOutcome?

    private let deletion: DeletionService
    private let permissions: PermissionService
    private let paths: SystemPaths
    private var scanTask: Task<Void, Never>?

    init(deletion: DeletionService, permissions: PermissionService, paths: SystemPaths = .current) {
        self.deletion = deletion
        self.permissions = permissions
        self.paths = paths
        target = paths.home
        volume = VolumeInfo(for: paths.home)
    }

    var protection: ProtectedPaths { deletion.protection }

    var current: DiskNode? {
        guard let root else { return nil }
        return root.descendant(at: path) ?? root
    }

    /// Breadcrumb entries from the scan root down to the current folder.
    var breadcrumb: [(depth: Int, name: String)] {
        guard let root else { return [] }
        var items = [(0, root.name)]
        var node = root
        for (index, id) in path.enumerated() {
            guard let next = node.children.first(where: { $0.id == id }) else { break }
            items.append((index + 1, next.name))
            node = next
        }
        return items
    }

    var unreadableCount: Int {
        guard let root else { return 0 }
        func count(_ node: DiskNode) -> Int {
            (node.kind == .unreadable ? 1 : 0) + node.children.reduce(0) { $0 + count($1) }
        }
        return count(root)
    }

    // MARK: Scanning

    func scanHome() { scan(paths.home) }
    func scanStartupVolume() { scan(URL(fileURLWithPath: "/")) }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Analysieren"
        panel.directoryURL = target
        guard panel.runModal() == .OK, let url = panel.url else { return }
        scan(url)
    }

    func rescan() { scan(target) }

    func scan(_ url: URL) {
        scanTask?.cancel()
        permissions.refresh()
        target = url
        volume = VolumeInfo(for: url)
        path = []
        hovered = nil
        lastOutcome = nil
        progress = DiskScanProgress()
        phase = .scanning
        let service = DiskUsageService(privacy: PrivacyProtectedLocations(paths: paths, hasFullDiskAccess: permissions.hasFullDiskAccess))
        let onProgress = mainActorProgress { [weak self] (update: DiskScanProgress) in
            guard self?.phase == .scanning else { return }
            self?.progress = update
        }
        scanTask = Task { [weak self] in
            do {
                let tree = try await service.scan(url, progress: onProgress)
                guard !Task.isCancelled, let self else { return }
                self.root = tree
                self.phase = .results
            } catch {
                guard let self, self.phase == .scanning else { return }
                self.phase = self.root == nil ? .idle : .results
            }
        }
    }

    func cancel() {
        scanTask?.cancel()
        scanTask = nil
        phase = root == nil ? .idle : .results
    }

    // MARK: Navigation

    func open(_ node: DiskNode) {
        guard node.canDrillDown else { return }
        hovered = nil
        path.append(node.id)
    }

    func goUp() {
        guard !path.isEmpty else { return }
        hovered = nil
        path.removeLast()
    }

    func go(toDepth depth: Int) {
        hovered = nil
        path = Array(path.prefix(depth))
    }

    // MARK: Removing

    func prepareTrash(_ node: DiskNode) {
        guard node.isRealItem else { return }
        pendingPlan = DeletionPlan(
            title: "„\(node.name)“ in den Papierkorb legen?",
            message: node.kind == .folder ? "Der Ordner und sein gesamter Inhalt werden in den Papierkorb gelegt." : "Die Datei wird in den Papierkorb gelegt.",
            module: .spaceMap, action: .removedFiles,
            candidates: [DeletionCandidate(url: node.url, size: node.size)]
        )
    }

    func execute(_ plan: DeletionPlan) {
        Task {
            let outcome = await deletion.perform(plan)
            lastOutcome = outcome
            guard let root else { return }
            let removed = outcome.removedPaths
            self.root = root.removing(removed)
            if let index = path.firstIndex(where: removed.contains) { path = Array(path.prefix(index)) }
            volume = VolumeInfo(for: target)
        }
    }
}
