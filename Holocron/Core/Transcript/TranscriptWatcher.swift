import Foundation
import CoreServices

/// Watches Claude Code transcript directories (recursively, via FSEvents) and
/// reports created/modified `.jsonl` files. FSEvents wakes us only on writes,
/// so the app sits at ~0% CPU while agents are quiet.
final class TranscriptWatcher {
    /// Called on `queue` with the URLs of transcript files that changed.
    var onTranscriptsChanged: (([URL]) -> Void)?

    private(set) var rootDirectories: [URL]
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "fr.fabien-vincent.holocron.fsevents", qos: .utility)

    init(rootDirectories: [URL]) {
        self.rootDirectories = rootDirectories
    }

    deinit { stop() }

    static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)
    }

    func start() {
        stop()
        let existingRoots = rootDirectories.filter {
            FileManager.default.fileExists(atPath: $0.path)
        }
        guard !existingRoots.isEmpty else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<TranscriptWatcher>.fromOpaque(info).takeUnretainedValue()
            guard let rawPaths = unsafeBitCast(paths, to: NSArray.self) as? [String] else { return }
            watcher.handleEvents(paths: Array(rawPaths.prefix(count)))
        }

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            existingRoots.map(\.path) as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3, // latency: coalesce bursts of writes
            FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagNoDefer
                | kFSEventStreamCreateFlagUseCFTypes  // paths arrive as CFArray
            )
        ) else { return }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    func updateRoots(_ roots: [URL]) {
        rootDirectories = roots
        start()
    }

    private func handleEvents(paths: [String]) {
        let urls = paths
            .filter { $0.hasSuffix(".jsonl") }
            .map { URL(fileURLWithPath: $0) }
            .filter { Self.isSessionTranscript($0) }
        guard !urls.isEmpty else { return }
        onTranscriptsChanged?(urls)
    }

    /// Subagent sidechain files (`agent-*.jsonl`) are folded into their parent
    /// session by the reducer when inline; standalone ones are skipped rather
    /// than shown as phantom sessions.
    static func isSessionTranscript(_ url: URL) -> Bool {
        !url.lastPathComponent.hasPrefix("agent-")
    }

    /// One-shot enumeration of transcripts already on disk, most recently
    /// modified first, capped to keep startup cheap.
    func scanExistingTranscripts(maxFiles: Int = 80, modifiedWithin: TimeInterval = 48 * 3600) -> [URL] {
        let fileManager = FileManager.default
        let cutoff = Date().addingTimeInterval(-modifiedWithin)
        var found: [(URL, Date)] = []
        for root in rootDirectories {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for case let url as URL in enumerator {
                guard url.pathExtension == "jsonl", Self.isSessionTranscript(url) else { continue }
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                if modified >= cutoff { found.append((url, modified)) }
            }
        }
        return found.sorted { $0.1 > $1.1 }.prefix(maxFiles).map(\.0)
    }
}
