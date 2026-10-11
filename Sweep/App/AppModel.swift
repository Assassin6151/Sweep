import SwiftUI
import Observation

/// Owns app wide state and the long lived view models, so results survive switching modules
/// and the Smart Scan can drive the same scans the individual modules use.
@Observable
@MainActor
final class AppModel {
    var selection: SweepModule = .smartScan
    var showOnboarding: Bool

    let permissions = PermissionService()
    let activityLog: ActivityLog
    let deletion: DeletionService

    let junk: JunkCleanerViewModel
    let activity: ActivityLogViewModel
    let uninstaller: UninstallerViewModel
    let spaceMap: SpaceMapViewModel
    let duplicates: DuplicatesViewModel
    let largeFiles: LargeFilesViewModel
    let malware: MalwareViewModel
    let smartScan: SmartScanViewModel

    static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    private static let onboardingKey = "didCompleteOnboarding"

    init() {
        showOnboarding = !AppModel.isRunningTests && !UserDefaults.standard.bool(forKey: AppModel.onboardingKey)
        activityLog = AppModel.isRunningTests
            ? ActivityLog(fileURL: FileManager.default.temporaryDirectory.appending(path: "sweep-test-log-\(UUID().uuidString).json"))
            : ActivityLog()
        deletion = DeletionService(log: activityLog)
        junk = JunkCleanerViewModel(deletion: deletion, permissions: permissions)
        activity = ActivityLogViewModel(deletion: deletion)
        uninstaller = UninstallerViewModel(deletion: deletion, permissions: permissions)
        spaceMap = SpaceMapViewModel(deletion: deletion, permissions: permissions)
        duplicates = DuplicatesViewModel(deletion: deletion, permissions: permissions)
        largeFiles = LargeFilesViewModel(deletion: deletion, permissions: permissions)
        malware = MalwareViewModel(deletion: deletion, permissions: permissions)
        smartScan = SmartScanViewModel(junk: junk, largeFiles: largeFiles, duplicates: duplicates)
        malware.openInUninstaller = { [weak self] app in
            self?.uninstaller.select(appAt: app)
            self?.selection = .uninstaller
        }
    }

    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: AppModel.onboardingKey)
        showOnboarding = false
        permissions.refresh()
    }

    /// Short text shown next to a module in the sidebar, e.g. the amount of junk found.
    func badge(for module: SweepModule) -> String? {
        switch module {
        case .junk:
            junk.phase == .results && junk.totalFound > 0 ? ByteFormat.string(junk.totalFound) : nil
        case .duplicates:
            duplicates.phase == .results && duplicates.totalWasted > 0 ? ByteFormat.string(duplicates.totalWasted) : nil
        case .largeFiles:
            largeFiles.phase == .results ? "\(largeFiles.visibleFiles.count)" : nil
        case .smartScan:
            smartScan.phase == .done && smartScan.summary.reclaimableBytes > 0 ? ByteFormat.string(smartScan.summary.reclaimableBytes) : nil
        case .malware:
            malware.phase == .results && malware.worstSeverity >= .medium ? "\(malware.count(.high) + malware.count(.medium))" : nil
        case .uninstaller:
            uninstaller.hasLoaded ? "\(uninstaller.apps.count)" : nil
        default:
            nil
        }
    }
}
