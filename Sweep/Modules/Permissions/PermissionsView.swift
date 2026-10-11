import SwiftUI

struct PermissionsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ModuleHeader(module: .permissions)
                FullDiskAccessGuide()
                    .card(padding: 22)
                SafetyPromises()
                    .card(padding: 22)
            }
            .padding(Theme.pagePadding)
            .frame(maxWidth: 860, alignment: .leading)
        }
    }
}

/// The safety rules Sweep follows, shown in onboarding and on the permissions page.
struct SafetyPromises: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Unsere Sicherheitsregeln")
                .font(.headline)
            promise("trash", "Alles geht zuerst in den Papierkorb. Nur „Papierkorb leeren“ ist endgültig und wird extra bestätigt.")
            promise("lock", "Systemordner, deine Benutzer-Hauptordner, Schlüsselbund und iCloud Drive stehen auf einer Sperrliste und können nie gelöscht werden.")
            promise("eye", "Vor jeder Löschung siehst du eine Vorschau mit Pfad und Größe und bestätigst selbst.")
            promise("list.bullet.clipboard", "Jede Aktion landet im Aktivitätsprotokoll – inklusive Wiederherstellen aus dem Papierkorb.")
        }
    }

    private func promise(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(SweepModule.junk.tint)
                .frame(width: 22)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}
