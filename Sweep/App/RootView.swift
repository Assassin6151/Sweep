import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 236, max: 300)
        } detail: {
            ModuleContainer(module: model.selection)
                .id(model.selection)
                .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.18), value: model.selection)
        .sheet(isPresented: $model.showOnboarding) {
            OnboardingView()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.permissions.refresh()
        }
    }
}

/// Maps a module to its screen.
struct ModuleContainer: View {
    let module: SweepModule

    var body: some View {
        Group {
            switch module {
            case .junk:
                JunkCleanerView()
            case .uninstaller:
                UninstallerView()
            case .spaceMap:
                SpaceMapView()
            case .duplicates:
                DuplicatesView()
            case .largeFiles:
                LargeFilesView()
            case .malware:
                MalwareView()
            case .activity:
                ActivityLogView()
            case .permissions:
                PermissionsView()
            default:
                ModulePlaceholderView(module: module)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .navigationTitle(module.title)
    }
}

struct ModulePlaceholderView: View {
    let module: SweepModule

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ModuleHeader(module: module)
                .padding(Theme.pagePadding)
            HeroState(module: module, title: "Bald verfügbar", message: module.subtitle) { EmptyView() }
        }
    }
}
