import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TabView {
            Form {
                Section("Allgemein") {
                    Button("Einführung erneut anzeigen") { model.showOnboarding = true }
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Allgemein", systemImage: "gearshape") }
        }
        .frame(width: 520, height: 420)
    }
}
