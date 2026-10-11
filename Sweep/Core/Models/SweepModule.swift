import SwiftUI

enum SidebarSection: String, CaseIterable, Identifiable {
    case overview, cleanup, applications, files, protection, history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Übersicht"
        case .cleanup: "Bereinigen"
        case .applications: "Programme"
        case .files: "Dateien"
        case .protection: "Schutz"
        case .history: "Verlauf"
        }
    }

    var modules: [SweepModule] { SweepModule.allCases.filter { $0.section == self } }
}

/// Every top level screen of the app.
enum SweepModule: String, CaseIterable, Identifiable, Hashable {
    case smartScan, junk, uninstaller, spaceMap, duplicates, largeFiles, malware, activity, permissions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smartScan: "Smart Scan"
        case .junk: "Junk-Cleaner"
        case .uninstaller: "Deinstallieren"
        case .spaceMap: "Speicherkarte"
        case .duplicates: "Duplikate"
        case .largeFiles: "Große & alte Dateien"
        case .malware: "Adware-Check"
        case .activity: "Aktivitätsprotokoll"
        case .permissions: "Berechtigungen"
        }
    }

    var subtitle: String {
        switch self {
        case .smartScan: "Junk, große Dateien und Duplikate in einem Durchlauf finden."
        case .junk: "Caches, Logs, temporäre Dateien und Entwickler-Reste aufräumen."
        case .uninstaller: "Apps restlos entfernen oder auf Werkseinstellungen zurücksetzen."
        case .spaceMap: "Sehen, welche Ordner und Dateien den meisten Platz belegen."
        case .duplicates: "Identische Dateien aufspüren und nur eine Kopie behalten."
        case .largeFiles: "Platzfresser und lange nicht geöffnete Dateien finden."
        case .malware: "Launch Agents, Anmeldeobjekte und Browser-Erweiterungen prüfen."
        case .activity: "Nachvollziehen, was Sweep wann entfernt hat."
        case .permissions: "Festplattenvollzugriff und Datenschutz verstehen."
        }
    }

    var symbol: String {
        switch self {
        case .smartScan: "sparkles"
        case .junk: "trash.slash"
        case .uninstaller: "shippingbox"
        case .spaceMap: "square.grid.3x3.square"
        case .duplicates: "doc.on.doc"
        case .largeFiles: "archivebox"
        case .malware: "shield.lefthalf.filled"
        case .activity: "clock.arrow.circlepath"
        case .permissions: "lock.shield"
        }
    }

    var tint: Color {
        switch self {
        case .smartScan: Color(red: 0.20, green: 0.55, blue: 0.95)
        case .junk: Color(red: 0.16, green: 0.70, blue: 0.55)
        case .uninstaller: Color(red: 0.42, green: 0.40, blue: 0.92)
        case .spaceMap: Color(red: 0.97, green: 0.58, blue: 0.20)
        case .duplicates: Color(red: 0.66, green: 0.36, blue: 0.90)
        case .largeFiles: Color(red: 0.92, green: 0.34, blue: 0.52)
        case .malware: Color(red: 0.90, green: 0.30, blue: 0.27)
        case .activity: Color(red: 0.40, green: 0.52, blue: 0.64)
        case .permissions: Color(red: 0.93, green: 0.70, blue: 0.16)
        }
    }

    var section: SidebarSection {
        switch self {
        case .smartScan: .overview
        case .junk, .duplicates, .largeFiles: .cleanup
        case .uninstaller: .applications
        case .spaceMap: .files
        case .malware, .permissions: .protection
        case .activity: .history
        }
    }

    var gradient: LinearGradient {
        LinearGradient(colors: [tint.opacity(0.95), tint.shaded(by: 0.25)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension Color {
    /// Darkens a color by blending it with black (works on macOS 14, unlike `mix(with:by:)`).
    func shaded(by fraction: CGFloat) -> Color {
        let base = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(self)
        return Color(nsColor: base.blended(withFraction: fraction, of: .black) ?? base)
    }
}
