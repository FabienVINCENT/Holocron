import Foundation

/// Incremental JSONL parser. Feed it raw chunks as they are appended to a
/// transcript file; it splits on newlines, keeps the trailing partial line
/// buffered, and decodes each complete line. Undecodable lines are counted
/// and skipped — the transcript format is not a public contract, so parsing
/// must never take the app down.
final class TranscriptParser {
    private var remainder = Data()
    private let decoder = TranscriptJSON.makeDecoder()
    private(set) var droppedLineCount = 0

    func feed(_ chunk: Data) -> [TranscriptLine] {
        remainder.append(chunk)
        var lines: [TranscriptLine] = []
        while let newlineIndex = remainder.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = remainder.subdata(in: remainder.startIndex..<newlineIndex)
            remainder.removeSubrange(remainder.startIndex...newlineIndex)
            guard !lineData.isEmpty else { continue }
            if let line = try? decoder.decode(TranscriptLine.self, from: lineData) {
                lines.append(line)
            } else {
                droppedLineCount += 1
            }
        }
        return lines
    }

    /// Flush a final unterminated line (used when a file is read to EOF and
    /// is not expected to grow, e.g. during tests or full re-reads).
    func flush() -> [TranscriptLine] {
        guard !remainder.isEmpty else { return [] }
        defer { remainder = Data() }
        if let line = try? decoder.decode(TranscriptLine.self, from: remainder) {
            return [line]
        }
        droppedLineCount += 1
        return []
    }
}

/// Tracks a single transcript file on disk and reads only newly appended
/// bytes on each poll — O(new data), not O(file size).
final class TranscriptTail {
    let url: URL
    private var offset: UInt64 = 0
    private let parser = TranscriptParser()

    /// Files larger than this are not replayed from byte 0 on first sight;
    /// only the last `bootstrapWindow` bytes are read. Statuses stay exact
    /// (they depend on the most recent lines); token totals become partial.
    static let fullParseLimit: UInt64 = 32 * 1024 * 1024
    static let bootstrapWindow: UInt64 = 4 * 1024 * 1024

    private(set) var isPartial = false

    init(url: URL) {
        self.url = url
    }

    /// Read appended data and return newly parsed lines.
    func drain() -> [TranscriptLine] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0
        if size < offset {
            // Truncated/rewritten file: start over.
            offset = 0
        }
        if offset == 0 && size > Self.fullParseLimit {
            offset = size - Self.bootstrapWindow
            isPartial = true
            // Skip to the next line boundary so we do not decode a torn line.
            try? handle.seek(toOffset: offset)
            if let probe = try? handle.read(upToCount: 64 * 1024), let data = probe,
               let newline = data.firstIndex(of: UInt8(ascii: "\n")) {
                offset += UInt64(newline) + 1
            }
        }
        guard size > offset else { return [] }

        try? handle.seek(toOffset: offset)
        var lines: [TranscriptLine] = []
        while offset < size {
            let want = Int(min(1024 * 1024, size - offset))
            guard let chunk = try? handle.read(upToCount: want), let data = chunk,
                  !data.isEmpty else { break }
            offset += UInt64(data.count)
            lines.append(contentsOf: parser.feed(data))
        }
        return lines
    }
}
