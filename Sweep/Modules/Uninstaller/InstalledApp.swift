import Foundation

struct InstalledApp: Identifiable, Hashable, Sendable {
    var id: String { url.path }
    let url: URL
    let name: String
    let bundleID: String
    let version: String?
    let executableName: String?
    let isFromAppStore: Bool
    /// Last time the app was opened, according to Spotlight.
    let lastUsed: Date?
    /// When the app was added to the Mac, used when it has never been opened.
    let dateAdded: Date?
    var size: Int64?

    /// The date used to judge whether an app is unused.
    var lastActivity: Date? { lastUsed ?? dateAdded }

    func isUnused(days: Int, now: Date = .now) -> Bool {
        guard let lastActivity else { return false }
        return now.timeIntervalSince(lastActivity) > Double(days) * 86_400
    }

    var lastUsedDescription: String {
        if let lastUsed { return "Zuletzt geöffnet \(lastUsed.relativeDescription)" }
        if let dateAdded { return "Nie geöffnet · installiert \(dateAdded.relativeDescription)" }
        return "Nutzung unbekannt"
    }
}

enum LeftoverKind: String, CaseIterable, Sendable {
    case appSupport, caches, preferences, containers, groupContainers, savedState, logs, crashReports
    case webData, launchAgents, launchDaemons, helpers, scripts, plugins

    var title: String {
        switch self {
        case .appSupport: "Programmdaten"
        case .caches: "Caches"
        case .preferences: "Einstellungen"
        case .containers: "App-Container"
        case .groupContainers: "Gruppen-Container"
        case .savedState: "Fensterzustand"
        case .logs: "Protokolle"
        case .crashReports: "Absturzberichte"
        case .webData: "Web-Daten & Cookies"
        case .launchAgents: "Launch Agents"
        case .launchDaemons: "Launch Daemons"
        case .helpers: "Hilfsprogramme"
        case .scripts: "App-Skripte"
        case .plugins: "Plug-ins"
        }
    }

    var symbol: String {
        switch self {
        case .appSupport: "folder"
        case .caches: "internaldrive"
        case .preferences: "slider.horizontal.3"
        case .containers, .groupContainers: "shippingbox"
        case .savedState: "macwindow"
        case .logs: "doc.text"
        case .crashReports: "exclamationmark.triangle"
        case .webData: "globe"
        case .launchAgents, .launchDaemons: "bolt.horizontal"
        case .helpers: "wrench.and.screwdriver"
        case .scripts: "applescript"
        case .plugins: "puzzlepiece.extension"
        }
    }
}

enum MatchConfidence: Sendable {
    /// Matched by bundle identifier – very reliable.
    case high
    /// Matched by app name only – shown, but not preselected.
    case medium
}

struct Leftover: Identifiable, Hashable, Sendable {
    var id: String { url.path }
    let url: URL
    let kind: LeftoverKind
    let confidence: MatchConfidence
    let size: Int64
    let isSystemWide: Bool
}
