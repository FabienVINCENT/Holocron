import Foundation

/// Background half of session tracking: owns the tails and reducers on a
/// private queue and emits immutable snapshots. Deliberately NOT
/// main-actor-isolated — `SessionStore` bridges snapshots onto the UI.
final class TranscriptPipeline: @unchecked Sendable {
    /// Called on the pipeline queue with a full session snapshot.
    var onSnapshot: (@Sendable ([AgentSession]) -> Void)?

    private let queue = DispatchQueue(label: "fr.fabien-vincent.holocron.parse", qos: .utility)
    private var tails: [URL: TranscriptTail] = [:]
    private var reducers: [URL: SessionReducer] = [:]
    private var endedSessionIds: Set<String> = []

    func ingest(urls: [URL]) {
        queue.async { [self] in
            for url in urls {
                guard FileManager.default.fileExists(atPath: url.path) else {
                    tails.removeValue(forKey: url)
                    reducers.removeValue(forKey: url)
                    continue
                }
                let tail = tails[url] ?? TranscriptTail(url: url)
                tails[url] = tail
                let lines = tail.drain()
                guard !lines.isEmpty else { continue }

                let sessionId = lines.first(where: { $0.sessionId != nil })?.sessionId
                    ?? url.deletingPathExtension().lastPathComponent
                var reducer = reducers[url]
                    ?? SessionReducer(sessionId: sessionId, transcriptURL: url)
                reducer.apply(lines)
                reducers[url] = reducer
            }
            publish()
        }
    }

    func markEnded(sessionId: String) {
        queue.async { [self] in
            endedSessionIds.insert(sessionId)
            publish()
        }
    }

    /// Queue-only.
    private func publish() {
        var bySession: [String: AgentSession] = [:]
        for (url, reducer) in reducers {
            var session = reducer.session
            session.endedByHook = endedSessionIds.contains(session.id)
            session.isPartialParse = tails[url]?.isPartial ?? false
            // Two files can share a sessionId after /resume; keep the freshest.
            if let existing = bySession[session.id],
               (existing.lastActivityAt ?? .distantPast) >= (session.lastActivityAt ?? .distantPast) {
                continue
            }
            bySession[session.id] = session
        }
        onSnapshot?(Array(bySession.values))
    }
}
