import Foundation

/// Rules for choosing which copy to keep. The selection always contains the files to *remove*.
enum KeepRule: String, CaseIterable, Identifiable, Sendable {
    case newest, oldest, shortestPath

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newest: "Neueste behalten"
        case .oldest: "Älteste behalten"
        case .shortestPath: "Kürzesten Pfad behalten"
        }
    }

    func keeper(in group: DuplicateGroup) -> DuplicateFile? {
        switch self {
        case .newest:
            group.files.max { ($0.modified ?? .distantPast) < ($1.modified ?? .distantPast) }
        case .oldest:
            group.files.min { ($0.modified ?? .distantFuture) < ($1.modified ?? .distantFuture) }
        case .shortestPath:
            group.files.min { ($0.url.path.count, $0.url.path) < ($1.url.path.count, $1.url.path) }
        }
    }
}

enum DuplicateSelection {
    /// Selects every file except the keeper of each group.
    static func autoSelect(_ groups: [DuplicateGroup], rule: KeepRule) -> Set<String> {
        var selection = Set<String>()
        for group in groups {
            let keeper = rule.keeper(in: group)
            for file in group.files where file.id != keeper?.id { selection.insert(file.id) }
        }
        return selection
    }

    /// Guarantees that at least one file per group stays: if a whole group is selected, its keeper
    /// (by `rule`) is deselected again.
    static func validated(_ selection: Set<String>, groups: [DuplicateGroup], rule: KeepRule = .newest) -> Set<String> {
        var result = selection
        for group in groups where group.files.allSatisfy({ result.contains($0.id) }) {
            if let keeper = rule.keeper(in: group) { result.remove(keeper.id) }
        }
        return result
    }
}
