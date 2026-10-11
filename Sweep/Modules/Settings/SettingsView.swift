import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("Allgemein", systemImage: "gearshape") }
            ExclusionSettings()
                .tabItem { Label("Ausschlüsse", systemImage: "lock.shield") }
        }
        .frame(width: 560, height: 440)
    }
}

private struct GeneralSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section("Sicherheit") {
                LabeledContent("Löschen") {
                    Text("Immer in den Papierkorb")
                        .foregroundStyle(.secondary)
                }
                Text("Sweep löscht nie direkt. Nur „Papierkorb leeren“ im Junk-Cleaner entfernt Dateien endgültig – nach einer zusätzlichen Bestätigung.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section("Hilfe") {
                Button("Einführung erneut anzeigen") { model.showOnboarding = true }
                Button("Festplattenvollzugriff öffnen") { model.permissions.openFullDiskAccessSettings() }
            }
        }
        .formStyle(.grouped)
    }
}

/// Lets the user add own folders to the blocklist. They are never scanned for deletion and never removed.
private struct ExclusionSettings: View {
    @State private var exclusions = UserExclusions.load()
    @State private var selection: String?

    var body: some View {
        Form {
            Section {
                List(selection: $selection) {
                    ForEach(exclusions, id: \.self) { path in
                        Label(path, systemImage: "folder")
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .frame(minHeight: 200)
                HStack {
                    Button("Ordner hinzufügen …", action: add)
                    Button("Entfernen") {
                        exclusions.removeAll { $0 == selection }
                        save()
                    }
                    .disabled(selection == nil)
                }
            } header: {
                Text("Geschützte Ordner")
            } footer: {
                Text("Diese Ordner und alles darin werden von Sweep nie gelöscht – zusätzlich zur eingebauten Sperrliste für System- und Benutzerordner.")
            }
        }
        .formStyle(.grouped)
    }

    private func add() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Schützen"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls where !exclusions.contains(url.path) {
            exclusions.append(url.path)
        }
        save()
    }

    private func save() {
        UserExclusions.save(exclusions)
    }
}
