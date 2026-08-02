import Foundation

/// Hook-free session→terminal matching: find the running `claude` process
/// whose working directory is the session's cwd and read its controlling
/// tty (`ps` + `lsof`). Slower and blunter than the hook-captured
/// ITERM_SESSION_ID, but works out of the box, including for sessions that
/// started before Holocron ever ran.
enum ProcessLocator {
    struct ClaudeProcess: Sendable {
        let pid: Int32
        let cwd: String
    }

    /// Snapshot of every running claude process with its working directory.
    /// Used for session liveness (a session whose process is gone is dead).
    /// Cost: one `ps` + one `lsof` call for all pids.
    static func runningClaudeProcesses() -> [ClaudeProcess] {
        guard let psOutput = run("/bin/ps", ["-axo", "pid=,command="]) else { return [] }
        var pids: [String] = []
        for line in psOutput.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2, parts[1].lowercased().contains("claude") else { continue }
            // Skip Holocron itself and its helpers.
            guard !parts[1].contains("Holocron") else { continue }
            pids.append(String(parts[0]))
        }
        guard !pids.isEmpty else { return [] }

        guard let lsofOutput = run(
            "/usr/sbin/lsof",
            ["-a", "-p", pids.joined(separator: ","), "-d", "cwd", "-Fpn"]
        ) else { return [] }

        var result: [ClaudeProcess] = []
        var currentPid: Int32?
        for line in lsofOutput.components(separatedBy: "\n") {
            if line.hasPrefix("p") {
                currentPid = Int32(line.dropFirst())
            } else if line.hasPrefix("n"), let pid = currentPid {
                result.append(ClaudeProcess(pid: pid, cwd: String(line.dropFirst())))
            }
        }
        return result
    }

    /// Returns e.g. "/dev/ttys012", or nil when no matching process exists.
    static func ttyOfClaudeProcess(cwd: String) -> String? {
        guard let psOutput = run("/bin/ps", ["-axo", "pid=,tty=,command="]) else { return nil }

        var candidates: [(pid: String, tty: String)] = []
        for line in psOutput.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let parts = trimmed.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count == 3 else { continue }
            let tty = String(parts[1])
            let command = parts[2].lowercased()
            guard tty.hasPrefix("tty"), command.contains("claude") else { continue }
            candidates.append((String(parts[0]), tty))
        }

        for candidate in candidates {
            guard let lsofOutput = run("/usr/sbin/lsof", ["-a", "-p", candidate.pid, "-d", "cwd", "-Fn"])
            else { continue }
            // -Fn output: p<pid> / fcwd / n<path>
            let processCwd = lsofOutput
                .components(separatedBy: "\n")
                .first { $0.hasPrefix("n") }
                .map { String($0.dropFirst()) }
            if processCwd == cwd {
                return "/dev/" + candidate.tty
            }
        }
        return nil
    }

    private static func run(_ path: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}
