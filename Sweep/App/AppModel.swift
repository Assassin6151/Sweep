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
        default:
            nil
        }
    }
}
