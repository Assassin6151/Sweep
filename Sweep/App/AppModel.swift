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

    static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    private static let onboardingKey = "didCompleteOnboarding"

    init() {
        showOnboarding = !AppModel.isRunningTests && !UserDefaults.standard.bool(forKey: AppModel.onboardingKey)
    }

    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: AppModel.onboardingKey)
        showOnboarding = false
        permissions.refresh()
    }
}
