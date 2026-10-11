import Foundation
import Observation

/// Runs junk, large file and duplicate scans in one go by driving the modules' own view models,
/// so every result is immediately available in the module screens as well.
@Observable
@MainActor
final class SmartScanViewModel {
    enum Part: String, CaseIterable, Identifiable {
        case junk, largeFiles, duplicates
        var id: String { rawValue }

        var module: SweepModule {
            switch self {
            case .junk: .junk
            case .largeFiles: .largeFiles
            case .duplicates: .duplicates
            }
        }
    }

    enum PartState: Equatable { case waiting, running, done }
    enum Phase: Equatable { case idle, scanning, done }

    private(set) var phase: Phase = .idle
    private(set) var states: [Part: PartState] = [:]
    private(set) var startedAt: Date?
    private(set) var finishedAt: Date?

    let junk: JunkCleanerViewModel
    let largeFiles: LargeFilesViewModel
    let duplicates: DuplicatesViewModel
    private var runTask: Task<Void, Never>?

    init(junk: JunkCleanerViewModel, largeFiles: LargeFilesViewModel, duplicates: DuplicatesViewModel) {
        self.junk = junk
        self.largeFiles = largeFiles
        self.duplicates = duplicates
    }

    func state(of part: Part) -> PartState { states[part] ?? .waiting }

    var summary: SmartScanSummary {
        SmartScanSummary.make(junk: junk.results, junkSelection: junk.selection,
                              duplicates: duplicates.groups, duplicateSelection: duplicates.selection,
                              largeFiles: largeFiles.visibleFiles)
    }

    /// Overall progress across the three parts (large files have no known total and count when done).
    var overallProgress: Double {
        let junkPart = state(of: .junk) == .done ? 1 : (junk.progress.fraction ?? 0)
        let duplicatePart = state(of: .duplicates) == .done ? 1 : (duplicates.progress.fraction ?? 0)
        let largePart: Double = state(of: .largeFiles) == .done ? 1 : 0.3
        return (junkPart + duplicatePart + largePart) / 3
    }

    func detail(for part: Part) -> String {
        switch part {
        case .junk: junk.progress.message
        case .largeFiles: largeFiles.progress.message
        case .duplicates: duplicates.progress.message
        }
    }

    func start() {
        guard phase != .scanning else { return }
        phase = .scanning
        startedAt = .now
        states = Dictionary(uniqueKeysWithValues: Part.allCases.map { ($0, .running) })
        runTask = Task {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { @MainActor in
                    await self.junk.scanAndWait()
                    self.states[.junk] = .done
                }
                group.addTask { @MainActor in
                    await self.largeFiles.scanAndWait()
                    self.states[.largeFiles] = .done
                }
                group.addTask { @MainActor in
                    await self.duplicates.scanAndWait()
                    self.states[.duplicates] = .done
                }
            }
            guard phase == .scanning else { return }
            finishedAt = .now
            phase = .done
        }
    }

    func cancel() {
        runTask?.cancel()
        junk.cancel()
        largeFiles.cancel()
        duplicates.cancel()
        states = [:]
        phase = .idle
    }
}
