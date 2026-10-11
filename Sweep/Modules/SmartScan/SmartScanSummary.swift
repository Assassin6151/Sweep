import Foundation

/// Combines the results of the three Smart Scan parts without counting anything twice.
struct SmartScanSummary: Equatable, Sendable {
    var junkBytes: Int64 = 0
    var duplicateBytes: Int64 = 0
    var duplicateCount = 0
    /// Large files that are not already counted as removable duplicates.
    var largeFileBytes: Int64 = 0
    var largeFileCount = 0

    /// What can be freed right away with the default selections (junk + surplus duplicates).
    var reclaimableBytes: Int64 { junkBytes + duplicateBytes }

    static func make(junk: [JunkCategoryResult], junkSelection: Set<String>,
                     duplicates: [DuplicateGroup], duplicateSelection: Set<String>,
                     largeFiles: [LargeFile]) -> SmartScanSummary {
        var summary = SmartScanSummary()
        summary.junkBytes = junk.flatMap(\.items).filter { junkSelection.contains($0.id) }.reduce(0) { $0 + $1.size }

        let selectedDuplicates = duplicates.flatMap(\.files).filter { duplicateSelection.contains($0.id) }
        summary.duplicateBytes = selectedDuplicates.reduce(0) { $0 + $1.size }
        summary.duplicateCount = selectedDuplicates.count

        let duplicatePaths = Set(selectedDuplicates.map(\.id))
        let remainingLarge = largeFiles.filter { !duplicatePaths.contains($0.id) }
        summary.largeFileBytes = remainingLarge.reduce(0) { $0 + $1.size }
        summary.largeFileCount = remainingLarge.count
        return summary
    }
}
