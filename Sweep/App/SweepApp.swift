import SwiftUI

@main
struct SweepApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        Window("Sweep", id: "main") {
            RootView()
                .environment(model)
                .frame(minWidth: 980, minHeight: 640)
        }
        .defaultSize(width: 1180, height: 760)
        .windowToolbarStyle(.unified)
        .commands { SweepCommands(model: model) }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

struct SweepCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            ForEach(Array(SweepModule.allCases.prefix(9).enumerated()), id: \.element) { index, module in
                Button(module.title) { model.selection = module }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
        }
        CommandGroup(replacing: .help) {
            Button("Einführung erneut anzeigen") { model.showOnboarding = true }
        }
    }
}
