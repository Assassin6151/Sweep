import Foundation

/// Runs command line tools (read-only helpers such as `pluginkit` or `osascript`).
enum Shell {
    struct Result: Sendable {
        let status: Int32
        let output: String
        let error: String
    }

    /// Runs `executable` and waits at most `timeout` seconds. Returns nil if it could not be started or timed out.
    static func execute(_ executable: String, _ arguments: [String], timeout: TimeInterval = 15) -> Result? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do { try process.run() } catch { return nil }

        // Drain the pipes concurrently so a chatty process cannot block on a full buffer.
        let collector = OutputCollector()
        let readers = DispatchGroup()
        DispatchQueue.global().async(group: readers) { collector.setOut(outPipe.fileHandleForReading.readDataToEndOfFile()) }
        DispatchQueue.global().async(group: readers) { collector.setErr(errPipe.fileHandleForReading.readDataToEndOfFile()) }

        guard finished.wait(timeout: .now() + timeout) == .success else {
            process.terminate()
            return nil
        }
        _ = readers.wait(timeout: .now() + 2)
        return Result(status: process.terminationStatus, output: collector.out, error: collector.err)
    }

    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 15) -> String? {
        guard let result = execute(executable, arguments, timeout: timeout), result.status == 0 else { return nil }
        return result.output
    }

    private final class OutputCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var outData = Data()
        private var errData = Data()

        func setOut(_ data: Data) { lock.lock(); outData = data; lock.unlock() }
        func setErr(_ data: Data) { lock.lock(); errData = data; lock.unlock() }
        var out: String { lock.lock(); defer { lock.unlock() }; return String(decoding: outData, as: UTF8.self) }
        var err: String { lock.lock(); defer { lock.unlock() }; return String(decoding: errData, as: UTF8.self) }
    }
}
