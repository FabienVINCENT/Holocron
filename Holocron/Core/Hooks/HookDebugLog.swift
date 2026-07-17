import Foundation

/// Append-only debug journal for the hook pipeline, shared by the app and
/// the holocron-hook CLI (separate files). This is what turns "the card
/// didn't show" into "PreToolUse for Bash replied passthrough because rule
/// X matched".
enum HookDebugLog {
    static func directory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Holocron/logs", isDirectory: true)
    }

    private static let queue = DispatchQueue(label: "fr.fabien-vincent.holocron.hooklog")
    private static let maxBytes: UInt64 = 256 * 1024

    /// `file` is a bare name like "hook-app.log" / "hook-client.log".
    static func append(_ line: String, to file: String) {
        queue.async { writeEntry(line, file: file) }
    }

    /// Synchronous variant for short-lived processes (the hook CLI exits
    /// right after use; a queued write would be lost).
    static func appendSync(_ line: String, to file: String) {
        writeEntry(line, file: file)
    }

    private static func writeEntry(_ line: String, file: String) {
        let directory = directory()
        let url = directory.appendingPathComponent(file)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let entry = "\(formatter.string(from: Date())) \(line)\n"
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: url.path) {
                try entry.data(using: .utf8)?.write(to: url)
                return
            }
            // Cheap rotation: restart the file once it grows too big.
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            let size = (attributes?[.size] as? UInt64) ?? 0
            if size > maxBytes {
                try? FileManager.default.removeItem(at: url)
                try entry.data(using: .utf8)?.write(to: url)
                return
            }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            if let data = entry.data(using: .utf8) {
                try handle.write(contentsOf: data)
            }
        } catch {
            // Logging must never take anything down.
        }
    }
}
