import AppKit
import Observation

@Observable
@MainActor
final class UninstallerViewModel {
    enum SortOrder: String, CaseIterable, Identifiable {
        case name, size, lastUsed
        var id: String { rawValue }
        var title: String {
            switch self {
            case .name: "Name"
            case .size: "Größe"
            case .lastUsed: "Zuletzt benutzt"
            }
        }
    }

    private(set) var apps: [InstalledApp] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    var searchText = ""
    var sortOrder: SortOrder = .name
    var onlyUnused = false
    var unusedDays: Int {
        didSet { UserDefaults.standard.set(unusedDays, forKey: "unusedAppDays") }
    }

    var selectedAppID: String? {
        didSet { if oldValue != selectedAppID { loadLeftovers() } }
    }
    private(set) var leftovers: [Leftover] = []
    private(set) var skippedLocations = 0
    private(set) var isSearchingLeftovers = false
    var selectedLeftovers: Set<String> = []

    var pendingPlan: DeletionPlan?
    var lastOutcome: DeletionOutcome?
    var runningAppToQuit: InstalledApp?
    private var pendingAfterQuit: DeletionPlan?

    private let deletion: DeletionService
    private let permissions: PermissionService
    private let paths: SystemPaths
    private var leftoverTask: Task<Void, Never>?
    private var sizeTask: Task<Void, Never>?

    init(deletion: DeletionService, permissions: PermissionService, paths: SystemPaths = .current) {
        self.deletion = deletion
        self.permissions = permissions
        self.paths = paths
        let stored = UserDefaults.standard.integer(forKey: "unusedAppDays")
        unusedDays = stored > 0 ? stored : 90
    }

    var protection: ProtectedPaths { deletion.protection }

    var selectedApp: InstalledApp? { apps.first { $0.id == selectedAppID } }

    var unusedCount: Int { apps.filter { $0.isUnused(days: unusedDays) }.count }

    var visibleApps: [InstalledApp] {
        var list = apps
        if onlyUnused { list = list.filter { $0.isUnused(days: unusedDays) } }
        if !searchText.isEmpty {
            list = list.filter { $0.name.localizedCaseInsensitiveContains(searchText) || $0.bundleID.localizedCaseInsensitiveContains(searchText) }
        }
        switch sortOrder {
        case .name: break
        case .size: list.sort { ($0.size ?? 0) > ($1.size ?? 0) }
        case .lastUsed: list.sort { ($0.lastActivity ?? .distantPast) < ($1.lastActivity ?? .distantPast) }
        }
        return list
    }

    var leftoverSize: Int64 { leftovers.reduce(0) { $0 + $1.size } }
    var selectedLeftoverSize: Int64 { leftovers.filter { selectedLeftovers.contains($0.id) }.reduce(0) { $0 + $1.size } }

    var groupedLeftovers: [(kind: LeftoverKind, items: [Leftover])] {
        let groups = Dictionary(grouping: leftovers, by: \.kind)
        return LeftoverKind.allCases.compactMap { kind in groups[kind].map { (kind, $0) } }
    }

    // MARK: Loading

    func loadIfNeeded() {
        guard !hasLoaded, !isLoading else { return }
        reload()
    }

    func reload() {
        isLoading = true
        let service = AppDiscoveryService(paths: paths)
        Task {
            let found = (try? await Task.detached(priority: .userInitiated) { try service.discover() }.value) ?? []
            apps = found
            isLoading = false
            hasLoaded = true
            if selectedAppID == nil || !found.contains(where: { $0.id == selectedAppID }) {
                selectedAppID = visibleApps.first?.id
            }
            measureSizes()
        }
    }

    /// Measures app bundle sizes in the background, a few at a time, updating the list as results arrive.
    private func measureSizes() {
        sizeTask?.cancel()
        let urls = apps.filter { $0.size == nil }.map(\.url)
        sizeTask = Task { [weak self] in
            await withTaskGroup(of: (String, Int64).self) { group in
                var iterator = urls.makeIterator()
                func addNext() {
                    guard let url = iterator.next() else { return }
                    group.addTask { (url.path, (try? FileSizer.measure(url).bytes) ?? 0) }
                }
                for _ in 0..<4 { addNext() }
                for await (path, size) in group {
                    guard !Task.isCancelled else { return }
                    self?.setSize(size, for: path)
                    addNext()
                }
            }
        }
    }

    private func setSize(_ size: Int64, for path: String) {
        guard let index = apps.firstIndex(where: { $0.id == path }) else { return }
        apps[index].size = size
    }

    private func loadLeftovers() {
        leftoverTask?.cancel()
        leftovers = []
        selectedLeftovers = []
        skippedLocations = 0
        guard let app = selectedApp else { return }
        isSearchingLeftovers = true
        let finder = LeftoverFinder(paths: paths, protection: protection, hasFullDiskAccess: permissions.hasFullDiskAccess)
        leftoverTask = Task { [weak self] in
            let result = try? await Task.detached(priority: .userInitiated) { try finder.findLeftovers(for: app) }.value
            guard !Task.isCancelled, let self, self.selectedAppID == app.id else { return }
            self.leftovers = result?.leftovers ?? []
            self.skippedLocations = result?.skippedLocations ?? 0
            self.selectedLeftovers = Set(self.leftovers.filter { $0.confidence == .high }.map(\.id))
            self.isSearchingLeftovers = false
        }
    }

    func toggle(_ leftover: Leftover) {
        if selectedLeftovers.contains(leftover.id) { selectedLeftovers.remove(leftover.id) } else { selectedLeftovers.insert(leftover.id) }
    }

    // MARK: Actions

    func prepareUninstall() {
        guard let app = selectedApp else { return }
        var candidates = [DeletionCandidate(url: app.url, size: app.size ?? 0, context: "App")]
        candidates += selectedLeftoverCandidates()
        request(DeletionPlan(
            title: "\(app.name) deinstallieren?",
            message: "Die App und die ausgewählten zugehörigen Dateien werden in den Papierkorb gelegt.",
            module: .uninstaller, action: .uninstalled, candidates: candidates,
            confirmTitle: "Deinstallieren"
        ), for: app)
    }

    func prepareReset() {
        guard let app = selectedApp else { return }
        let candidates = selectedLeftoverCandidates()
        guard !candidates.isEmpty else { return }
        request(DeletionPlan(
            title: "\(app.name) zurücksetzen?",
            message: "Die App bleibt installiert. Ihre Einstellungen, Caches und Daten werden in den Papierkorb gelegt – beim nächsten Start verhält sie sich wie frisch installiert.",
            module: .uninstaller, action: .reset, candidates: candidates,
            confirmTitle: "Zurücksetzen"
        ), for: app)
    }

    private func selectedLeftoverCandidates() -> [DeletionCandidate] {
        leftovers.filter { selectedLeftovers.contains($0.id) }
            .map { DeletionCandidate(url: $0.url, size: $0.size, context: $0.kind.title) }
    }

    private func request(_ plan: DeletionPlan, for app: InstalledApp) {
        if isRunning(app) {
            runningAppToQuit = app
            pendingAfterQuit = plan
        } else {
            pendingPlan = plan
        }
    }

    func isRunning(_ app: InstalledApp) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).isEmpty
    }

    /// Asks the running app to quit and continues with the preview once it is gone.
    func quitRunningAppAndContinue() {
        guard let app = runningAppToQuit else { return }
        runningAppToQuit = nil
        NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).forEach { $0.terminate() }
        Task {
            for _ in 0..<50 where isRunning(app) {
                try? await Task.sleep(for: .milliseconds(100))
            }
            pendingPlan = pendingAfterQuit
            pendingAfterQuit = nil
        }
    }

    func cancelQuit() {
        runningAppToQuit = nil
        pendingAfterQuit = nil
    }

    func execute(_ plan: DeletionPlan) {
        // Stop the app's own launch agents first, otherwise they keep running until the next login.
        let userAgents = paths.userLibrary.appending(path: "LaunchAgents").path
        let agentPlists = plan.candidates.filter { $0.url.deletingLastPathComponent().path == userAgents }
        Task {
            if !agentPlists.isEmpty {
                await Task.detached { agentPlists.forEach { Launchctl.bootoutUserAgent(plist: $0.url) } }.value
            }
            let outcome = await deletion.perform(plan)
            lastOutcome = outcome
            let removed = outcome.removedPaths
            leftovers.removeAll { removed.contains($0.id) }
            selectedLeftovers.subtract(removed)
            if let app = selectedApp, removed.contains(app.id) {
                apps.removeAll { $0.id == app.id }
                selectedAppID = visibleApps.first?.id
            }
        }
    }
}
