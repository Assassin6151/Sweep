import Foundation

/// The blocklist. Every deletion in Sweep is checked against it, no matter which module asks.
///
/// Three kinds of rules:
/// - *exact*: the folder itself must never be removed, but its contents may (e.g. `~/Library/Caches`)
/// - *subtree*: neither the folder nor anything inside may be removed (e.g. `/System`)
/// - *structural*: depth checks, files inside app bundles or photo libraries, Apple's own apps
struct ProtectedPaths: Sendable {
    enum Verdict: Equatable, Sendable {
        case allowed
        case blocked(String)

        var isAllowed: Bool { self == .allowed }

        var reason: String? {
            if case .blocked(let reason) = self { return reason }
            return nil
        }
    }

    let paths: SystemPaths
    var userExclusions: [String]
    var additionalProtected: [String]

    init(paths: SystemPaths = .current,
         userExclusions: [String] = [],
         additionalProtected: [String] = ProtectedPaths.sweepOwnPaths()) {
        self.paths = paths
        self.userExclusions = userExclusions.map(Self.normalize)
        self.additionalProtected = additionalProtected.map(Self.normalize)
    }

    static func sweepOwnPaths() -> [String] {
        var own = [Bundle.main.bundleURL.path]
        own.append(ActivityLog.defaultDirectory.path)
        return own
    }

    // MARK: Rules

    private var exactPaths: Set<String> {
        let home = Self.normalize(paths.home.path)
        let root = Self.normalize(paths.systemRoot.path)
        var set: Set<String> = [
            "/", "/Applications", "/Library", "/System", "/Users", "/Volumes", "/private", "/private/var",
            "/private/tmp", "/var", "/tmp", "/etc", "/opt", "/opt/homebrew", "/usr/local", "/cores", "/Network",
            "/Library/Caches", "/Library/Logs", "/Library/Application Support", "/Library/LaunchAgents",
            "/Library/LaunchDaemons", "/Library/Preferences", "/Library/PrivilegedHelperTools", "/Library/Logs/DiagnosticReports",
            "/Users/Shared",
            home,
        ]
        let homeChildren = [
            "Library", "Documents", "Desktop", "Downloads", "Pictures", "Movies", "Music", "Public", "Applications",
            ".Trash", "Library/Caches", "Library/Logs", "Library/Logs/DiagnosticReports", "Library/Application Support",
            "Library/Preferences", "Library/Containers", "Library/Group Containers", "Library/LaunchAgents",
            "Library/Developer", "Library/Developer/Xcode", "Library/Developer/Xcode/DerivedData",
            "Library/Developer/Xcode/Archives", "Library/Developer/CoreSimulator", "Library/Saved Application State",
            "Library/HTTPStorages", "Library/WebKit", "Library/Cookies", "Library/Application Scripts",
        ]
        for child in homeChildren { set.insert(Self.normalize(home + "/" + child)) }
        if root != "/" {
            // Tests use a fake system root: mirror the system level folders under it.
            for path in Array(set) where path.hasPrefix("/") && !path.hasPrefix(home) {
                set.insert(Self.normalize(root + path))
            }
        }
        set.insert(Self.normalize(paths.temporaryDirectory.path))
        return set
    }

    private var subtreePaths: [String] {
        let home = Self.normalize(paths.home.path)
        let root = Self.normalize(paths.systemRoot.path)
        let systemLevel = [
            "/System", "/bin", "/sbin", "/usr/bin", "/usr/sbin", "/usr/lib", "/usr/libexec", "/usr/share",
            "/private/etc", "/etc", "/private/var/db", "/private/var/root", "/private/var/vm", "/Library/Apple",
            "/Library/Keychains", "/Library/Extensions", "/Library/Security", "/Library/Frameworks",
        ]
        var result = systemLevel
        if root != "/" { result += systemLevel.map { Self.normalize(root + $0) } }
        let homeLevel = [
            "Library/Keychains", "Library/Mobile Documents", "Library/CloudStorage", "Library/Mail",
            "Library/Messages", "Library/Accounts", "Library/Cookies/Cookies.binarycookies",
            ".ssh", ".gnupg",
        ]
        result += homeLevel.map { Self.normalize(home + "/" + $0) }
        result += additionalProtected
        result += userExclusions
        return result
    }

    // MARK: Checking

    func verdict(for url: URL) -> Verdict {
        guard url.isFileURL else { return .blocked("Kein lokaler Dateipfad.") }
        for form in Self.normalizedForms(of: url) {
            if let reason = reason(toBlock: form) { return .blocked(reason) }
        }
        if url.pathExtension.lowercased() == "app", let id = Bundle(url: url)?.bundleIdentifier, id.hasPrefix("com.apple.") {
            return .blocked("Apps von Apple sind Teil von macOS und werden nicht entfernt.")
        }
        return .allowed
    }

    func isAllowed(_ url: URL) -> Bool { verdict(for: url).isAllowed }

    /// Whether `url` lives inside a trash folder, the only place where permanent deletion is permitted.
    func isInsideTrash(_ url: URL) -> Bool {
        let trash = Self.normalize(paths.trash.path)
        return Self.normalizedForms(of: url).contains { path in
            path.hasPrefix(trash + "/") || (path.hasPrefix("/Volumes/") && path.contains("/.Trashes/"))
        }
    }

    private func reason(toBlock path: String) -> String? {
        let components = path.split(separator: "/")
        if components.count < 2 {
            return "Pfade direkt unter dem Startvolume sind geschützt."
        }
        if exactPaths.contains(path) {
            return "Dieser Ordner ist für macOS oder dein Benutzerkonto wichtig. Nur sein Inhalt darf aufgeräumt werden."
        }
        for prefix in subtreePaths where path == prefix || path.hasPrefix(prefix + "/") {
            if userExclusions.contains(prefix) { return "Von dir in den Einstellungen ausgeschlossen." }
            return "Geschützter Bereich (\(prefix))."
        }
        let parents = components.dropLast()
        if parents.contains(where: { $0.lowercased().hasSuffix(".app") }) {
            return "Dateien innerhalb eines App-Pakets würden die App beschädigen."
        }
        if parents.contains(where: { $0.lowercased().hasSuffix(".photoslibrary") }) {
            return "Inhalte einer Fotos-Mediathek werden nie einzeln gelöscht."
        }
        return nil
    }

    // MARK: Normalization

    static func normalize(_ path: String) -> String {
        var standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        while standardized.count > 1 && standardized.hasSuffix("/") { standardized.removeLast() }
        return standardized
    }

    /// The literal path plus the path with its parent resolved, so a symlinked parent cannot sneak
    /// a protected location past the checks. The last component is not resolved: trashing a
    /// symlink only moves the link itself.
    static func normalizedForms(of url: URL) -> [String] {
        let literal = normalize(url.path)
        var forms = [literal]
        let parent = (literal as NSString).deletingLastPathComponent
        if let resolved = realpath(parent, nil) {
            let resolvedParent = String(cString: resolved)
            free(resolved)
            let form = normalize(resolvedParent + "/" + (literal as NSString).lastPathComponent)
            if !forms.contains(form) { forms.append(form) }
        }
        // `/var`, `/tmp` and `/etc` are aliases for their `/private` counterparts.
        for form in forms {
            for alias in ["/var", "/tmp", "/etc"] where form == alias || form.hasPrefix(alias + "/") {
                let privateForm = "/private" + form
                if !forms.contains(privateForm) { forms.append(privateForm) }
            }
        }
        return forms
    }
}
