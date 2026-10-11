import Foundation

/// Thin wrapper around `launchctl` to stop user launch agents before their plist is moved to the Trash.
/// Without this an agent would keep running until the next login.
enum Launchctl {
    /// Unloads a launch agent of the current user. Failure is not an error: the agent may simply not be loaded.
    @discardableResult
    static func bootoutUserAgent(plist url: URL) -> Bool {
        let domain = "gui/\(getuid())"
        return run(["bootout", domain, url.path]) == 0
    }

    private static func run(_ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }
}
