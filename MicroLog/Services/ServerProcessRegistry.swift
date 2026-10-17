import Foundation

/// Tracks the `llama-server` child processes so they can be torn down when the app quits,
/// and cleans up strays left behind by a previous instance that was killed or crashed.
final class ServerProcessRegistry: @unchecked Sendable {
    static let shared = ServerProcessRegistry()

    private let lock = NSLock()
    private var processes: [Process] = []

    private init() {}

    func register(_ process: Process) {
        lock.lock(); defer { lock.unlock() }
        processes.append(process)
    }

    func terminateAll() {
        lock.lock()
        let running = processes
        processes.removeAll()
        lock.unlock()
        for process in running where process.isRunning { process.terminate() }
    }

    /// Kills any `llama-server` we previously launched from our own bin directory. Servers are
    /// children of the app, so they are orphaned (and keep holding their ports and ~GBs of RAM)
    /// if the app is SIGKILLed or crashes.
    func killStaleServers() {
        let kill = Process()
        kill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        kill.arguments = ["-f", ModelManager.shared.llamaServerBinaryURL.path]
        try? kill.run()
        kill.waitUntilExit()
    }
}
