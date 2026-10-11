import SwiftUI

/// Explains in plain words why Sweep asks for Full Disk Access and walks through granting it.
/// Used by the onboarding and by the permissions module.
struct FullDiskAccessGuide: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let permissions = model.permissions
        VStack(alignment: .leading, spacing: 18) {
            StatusBanner(granted: permissions.hasFullDiskAccess)

            VStack(alignment: .leading, spacing: 10) {
                Text("Warum braucht Sweep das?")
                    .font(.headline)
                ReasonRow(symbol: "folder.badge.questionmark",
                          text: "macOS schützt viele Ordner, z. B. Mail, Safari, Nachrichten und die Daten anderer Apps. Ohne Freigabe sieht Sweep dort nichts und findet weniger Caches und App-Reste.")
                ReasonRow(symbol: "rectangle.stack.badge.person.crop",
                          text: "Ohne Vollzugriff fragt macOS bei jedem geschützten Ordner einzeln nach. Mit Vollzugriff entfallen diese Unterbrechungen.")
                ReasonRow(symbol: "hand.raised",
                          text: "Sweep liest nur Dateinamen, Größen und Datumsangaben. Nichts verlässt deinen Mac, es gibt keine Analyse- oder Telemetriedaten.")
                ReasonRow(symbol: "checkmark.seal",
                          text: "Gelöscht wird nur, was du in der Vorschau bestätigst – und auch dann landet es zuerst im Papierkorb.")
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("So erteilst du die Freigabe")
                    .font(.headline)
                StepRow(number: 1, text: "Öffne „Systemeinstellungen → Datenschutz & Sicherheit → Festplattenvollzugriff“.")
                StepRow(number: 2, text: "Schalte „Sweep“ ein. Fehlt Sweep in der Liste, klicke auf „+“ oder ziehe die App aus dem Finder hinein.")
                StepRow(number: 3, text: "Starte Sweep danach neu, damit macOS die Freigabe übernimmt.")
            }

            if !permissions.hasFullDiskAccess {
                StaleEntryHint(appPath: Bundle.main.bundleURL.path(percentEncoded: false))
            }

            HStack(spacing: 10) {
                Button {
                    permissions.openFullDiskAccessSettings()
                } label: {
                    Label("Systemeinstellungen öffnen", systemImage: "gearshape")
                }
                .buttonStyle(.prominent(SweepModule.permissions.tint))

                Button("Sweep im Finder zeigen") { permissions.revealAppInFinder() }
                Button("Erneut prüfen") {
                    withAnimation(Theme.spring) { permissions.refresh() }
                }
                Button("Neu starten") { permissions.relaunch() }
            }
            .controlSize(.large)

            Text("Du kannst Sweep auch ohne Vollzugriff nutzen. Geschützte Bereiche werden dann übersprungen und als „nicht lesbar“ markiert.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

private struct StatusBanner: View {
    let granted: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: granted ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                .font(.system(size: 28))
                .foregroundStyle(granted ? .green : .orange)
                .symbolEffect(.bounce, value: granted)
            VStack(alignment: .leading, spacing: 2) {
                Text(granted ? "Festplattenvollzugriff ist aktiv" : "Festplattenvollzugriff fehlt noch")
                    .font(.headline)
                Text(granted ? "Sweep kann alle relevanten Bereiche prüfen." : "Einige Bereiche können nicht geprüft werden.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background((granted ? Color.green : Color.orange).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .animation(Theme.spring, value: granted)
    }
}

/// macOS ties the permission to the exact signature of a build. A rebuilt or second copy of Sweep
/// shows up under the same name in System Settings but is not covered by the old entry.
private struct StaleEntryHint: View {
    let appPath: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Sweep ist eingeschaltet und trotzdem fehlt der Zugriff?", systemImage: "questionmark.circle")
                .font(.headline)
            Text("Dann gehört der Eintrag in der Liste zu einer anderen oder älteren Kopie von Sweep. Markiere „Sweep“ in der Liste, entferne den Eintrag mit „–“, füge über „+“ genau diese App hinzu, schalte sie ein und starte Sweep neu.")
                .fixedSize(horizontal: false, vertical: true)
            Text(appPath)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }
}

private struct ReasonRow: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(SweepModule.permissions.tint)
                .frame(width: 22)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct StepRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.callout.weight(.bold).monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(SweepModule.permissions.tint))
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
