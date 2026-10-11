import Foundation

enum JunkCategoryID: String, CaseIterable, Sendable, Hashable {
    case userCaches, containerCaches, systemCaches, userLogs, systemLogs, crashReports
    case temporaryFiles, xcode, homebrew, developerCaches, trash
}

enum JunkRisk: Sendable {
    /// Rebuilt automatically, safe to remove.
    case safe
    /// Usually fine, but worth a look before removing. Not selected by default.
    case review
}

/// Where a category looks for junk.
struct JunkSource: Sendable {
    enum Strategy: Sendable {
        /// Every direct child of `root` is one item.
        case children
        /// `root` itself is one item.
        case itself
        /// For every child of `root`, `<child>/<subpath>` is one item (e.g. container caches).
        case nested(subpath: String)
    }

    var root: URL
    var strategy: Strategy = .children
    var excludedNames: Set<String> = []
    /// Only items not modified for at least this long count as junk.
    var minimumAge: TimeInterval?
    var selectedByDefault = true
    var label: String?
}

struct JunkCategory: Identifiable, Sendable {
    let id: JunkCategoryID
    var title: String
    var explanation: String
    var symbol: String
    var risk: JunkRisk = .safe
    var deletionMode: DeletionMode = .moveToTrash
    var sources: [JunkSource]

    var selectedByDefault: Bool { risk == .safe && deletionMode == .moveToTrash }
}

/// The definitions of all junk categories. Built from `SystemPaths` so tests can point them at a fake home.
enum JunkCatalog {
    static func categories(paths: SystemPaths, ownBundleID: String = Bundle.main.bundleIdentifier ?? "com.assassin6151.sweep") -> [JunkCategory] {
        let lib = paths.userLibrary
        let sysLib = paths.systemLibrary
        let dev = lib.appending(path: "Developer")

        let handledElsewhere: Set<String> = [
            "Homebrew", "Yarn", "pip", "CocoaPods", "org.swift.swiftpm", "com.apple.dt.Xcode",
        ]
        let keepUserCaches: Set<String> = [
            ownBundleID, "CloudKit", "com.apple.bird", "com.apple.akd", "FamilyCircle", "com.apple.HomeKit",
            "com.apple.containermanagerd", "com.apple.ap.adprivacyd", "com.apple.iCloudHelper",
        ]

        return [
            JunkCategory(
                id: .userCaches, title: "App-Caches",
                explanation: "Zwischenspeicher deiner Apps. Sie werden bei Bedarf automatisch neu angelegt; Apps starten danach evtl. einmal etwas langsamer.",
                symbol: "internaldrive",
                sources: [
                    JunkSource(root: lib.appending(path: "Caches"), excludedNames: keepUserCaches.union(handledElsewhere)),
                    JunkSource(root: lib.appending(path: "Caches/com.apple.dt.Xcode"), strategy: .itself, label: "Xcode-Cache"),
                ]
            ),
            JunkCategory(
                id: .containerCaches, title: "Caches in App-Containern",
                explanation: "Caches von Apps aus dem App Store und von Apples Apps, die in eigenen Containern laufen. Benötigt Festplattenvollzugriff.",
                symbol: "shippingbox",
                sources: [
                    JunkSource(root: lib.appending(path: "Containers"), strategy: .nested(subpath: "Data/Library/Caches")),
                ]
            ),
            JunkCategory(
                id: .systemCaches, title: "System-Caches",
                explanation: "Systemweite Caches unter /Library/Caches. Einige gehören dem System und lassen sich nur mit Administratorrechten entfernen.",
                symbol: "gearshape.2", risk: .review,
                sources: [JunkSource(root: sysLib.appending(path: "Caches"))]
            ),
            JunkCategory(
                id: .userLogs, title: "Protokolle",
                explanation: "Protokolldateien deiner Apps. Sie helfen bei der Fehlersuche, werden für den Alltag aber nicht gebraucht.",
                symbol: "doc.text",
                sources: [JunkSource(root: lib.appending(path: "Logs"), excludedNames: ["DiagnosticReports", "Homebrew"])]
            ),
            JunkCategory(
                id: .systemLogs, title: "System-Protokolle",
                explanation: "Systemweite Protokolle unter /Library/Logs. Zum Teil nur mit Administratorrechten entfernbar.",
                symbol: "doc.text.magnifyingglass", risk: .review,
                sources: [JunkSource(root: sysLib.appending(path: "Logs"), excludedNames: ["DiagnosticReports"])]
            ),
            JunkCategory(
                id: .crashReports, title: "Absturzberichte",
                explanation: "Berichte über abgestürzte Apps. Nur nötig, wenn du einen Fehler melden möchtest.",
                symbol: "exclamationmark.triangle",
                sources: [
                    JunkSource(root: lib.appending(path: "Logs/DiagnosticReports")),
                    JunkSource(root: sysLib.appending(path: "Logs/DiagnosticReports"), selectedByDefault: false),
                ]
            ),
            JunkCategory(
                id: .temporaryFiles, title: "Temporäre Dateien",
                explanation: "Temporäre Dateien, die seit mindestens drei Tagen nicht verändert wurden. Neuere bleiben unangetastet, weil laufende Apps sie noch brauchen könnten.",
                symbol: "clock.badge.xmark",
                sources: [JunkSource(root: paths.temporaryDirectory, excludedNames: [ownBundleID], minimumAge: 3 * 86_400)]
            ),
            JunkCategory(
                id: .xcode, title: "Xcode",
                explanation: "DerivedData, Gerätesupport und Simulator-Caches werden von Xcode neu erzeugt. Archive enthalten Symbole für Absturzanalysen und sind daher abgewählt.",
                symbol: "hammer",
                sources: [
                    JunkSource(root: dev.appending(path: "Xcode/DerivedData"), label: "DerivedData"),
                    JunkSource(root: dev.appending(path: "Xcode/iOS DeviceSupport"), label: "iOS-Gerätesupport"),
                    JunkSource(root: dev.appending(path: "Xcode/watchOS DeviceSupport"), label: "watchOS-Gerätesupport"),
                    JunkSource(root: dev.appending(path: "Xcode/macOS DeviceSupport"), label: "macOS-Gerätesupport"),
                    JunkSource(root: dev.appending(path: "CoreSimulator/Caches"), strategy: .itself, label: "Simulator-Caches"),
                    JunkSource(root: dev.appending(path: "Xcode/UserData/Previews"), strategy: .itself, label: "SwiftUI-Vorschauen"),
                    JunkSource(root: dev.appending(path: "Xcode/Archives"), selectedByDefault: false, label: "Archive"),
                ]
            ),
            JunkCategory(
                id: .homebrew, title: "Homebrew-Reste",
                explanation: "Heruntergeladene Pakete und Protokolle von Homebrew. Installierte Programme bleiben unberührt.",
                symbol: "mug",
                sources: [
                    JunkSource(root: lib.appending(path: "Caches/Homebrew")),
                    JunkSource(root: lib.appending(path: "Logs/Homebrew")),
                ]
            ),
            JunkCategory(
                id: .developerCaches, title: "Entwickler-Caches",
                explanation: "Paket-Caches von npm, Yarn, pip, CocoaPods, Gradle und Swift Package Manager. Werden beim nächsten Build neu geladen.",
                symbol: "chevron.left.forwardslash.chevron.right",
                sources: [
                    JunkSource(root: paths.home.appending(path: ".npm/_cacache"), strategy: .itself, label: "npm"),
                    JunkSource(root: lib.appending(path: "Caches/Yarn"), strategy: .itself, label: "Yarn"),
                    JunkSource(root: lib.appending(path: "Caches/pip"), strategy: .itself, label: "pip"),
                    JunkSource(root: lib.appending(path: "Caches/CocoaPods"), strategy: .itself, label: "CocoaPods"),
                    JunkSource(root: lib.appending(path: "Caches/org.swift.swiftpm"), strategy: .itself, label: "Swift Package Manager"),
                    JunkSource(root: paths.home.appending(path: ".gradle/caches"), strategy: .itself, label: "Gradle"),
                ]
            ),
            JunkCategory(
                id: .trash, title: "Papierkorb",
                explanation: "Dateien in deinem Papierkorb. Achtung: Leeren ist endgültig und kann nicht rückgängig gemacht werden.",
                symbol: "trash", risk: .review, deletionMode: .permanent,
                sources: [JunkSource(root: paths.trash, excludedNames: [".DS_Store"])]
            ),
        ]
    }
}
