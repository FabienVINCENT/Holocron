import XCTest

/// Fixture lines captured from a real Claude Code transcript (fields trimmed
/// to what Holocron reads; shape preserved).
enum Fixtures {
    static let userPrompt = """
    {"type":"user","cwd":"/Users/fabien/dev/holocron","gitBranch":"main","sessionId":"7774231e-3037-5a0c-9ddf-b5ae0f40a435","timestamp":"2026-07-17T06:51:22.123Z","uuid":"u1","parentUuid":null,"isSidechain":false,"version":"2.1.0","message":{"role":"user","content":"Fix the login bug"}}
    """

    static let assistantText = """
    {"type":"assistant","cwd":"/Users/fabien/dev/holocron","sessionId":"7774231e-3037-5a0c-9ddf-b5ae0f40a435","timestamp":"2026-07-17T06:51:30Z","uuid":"a1","parentUuid":"u1","isSidechain":false,"message":{"role":"assistant","model":"claude-fable-5","stop_reason":"end_turn","content":[{"type":"text","text":"Done. The bug was in auth.ts."}],"usage":{"input_tokens":12,"output_tokens":345,"cache_read_input_tokens":52253,"cache_creation_input_tokens":1622}}}
    """

    static let assistantToolUse = """
    {"type":"assistant","sessionId":"7774231e-3037-5a0c-9ddf-b5ae0f40a435","timestamp":"2026-07-17T06:51:40.500Z","uuid":"a2","isSidechain":false,"message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_01","name":"Bash","input":{"command":"npm test","description":"Run tests"}}],"usage":{"input_tokens":2,"output_tokens":56}}}
    """

    static let toolResult = """
    {"type":"user","sessionId":"7774231e-3037-5a0c-9ddf-b5ae0f40a435","timestamp":"2026-07-17T06:52:01Z","uuid":"u2","isSidechain":false,"message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_01","content":"ok"}]},"toolUseResult":{"stdout":"ok"}}
    """

    static let queueOperation = """
    {"type":"queue-operation","operation":"enqueue","timestamp":"2026-07-17T06:50:00Z","sessionId":"7774231e-3037-5a0c-9ddf-b5ae0f40a435","content":"Please add tests"}
    """

    static func joined(_ lines: [String]) -> Data {
        Data((lines.joined(separator: "\n") + "\n").utf8)
    }
}

final class TranscriptParserTests: XCTestCase {
    func testParsesCompleteLines() {
        let parser = TranscriptParser()
        let lines = parser.feed(Fixtures.joined([Fixtures.userPrompt, Fixtures.assistantText]))
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0].type, "user")
        XCTAssertEqual(lines[0].cwd, "/Users/fabien/dev/holocron")
        XCTAssertEqual(lines[0].sessionId, "7774231e-3037-5a0c-9ddf-b5ae0f40a435")
        XCTAssertEqual(lines[1].message?.stopReason, "end_turn")
        XCTAssertEqual(lines[1].message?.usage?.outputTokens, 345)
    }

    func testHandlesChunkSplitMidLine() {
        let parser = TranscriptParser()
        let data = Fixtures.joined([Fixtures.assistantToolUse])
        let cut = data.count / 2
        XCTAssertEqual(parser.feed(data.prefix(cut)).count, 0)
        let lines = parser.feed(data.suffix(data.count - cut))
        XCTAssertEqual(lines.count, 1)
        guard case .toolUse(let id, let name, let input)? = lines[0].message?.content?.blocks.first else {
            return XCTFail("expected tool_use block")
        }
        XCTAssertEqual(id, "toolu_01")
        XCTAssertEqual(name, "Bash")
        XCTAssertEqual(input["command"]?.stringValue, "npm test")
    }

    func testTimestampWithAndWithoutFractionalSeconds() {
        let parser = TranscriptParser()
        let lines = parser.feed(Fixtures.joined([Fixtures.userPrompt, Fixtures.toolResult]))
        XCTAssertEqual(lines.count, 2)
        XCTAssertNotNil(lines[0].timestamp)
        XCTAssertNotNil(lines[1].timestamp)
    }

    func testGarbageLinesAreSkippedNotFatal() {
        let parser = TranscriptParser()
        let lines = parser.feed(Fixtures.joined(["not json at all", Fixtures.userPrompt, "{\"type\":42}"]))
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(parser.droppedLineCount, 2)
    }

    func testUnknownLineTypesSurviveDecoding() {
        let parser = TranscriptParser()
        let lines = parser.feed(Fixtures.joined([Fixtures.queueOperation]))
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].type, "queue-operation")
        XCTAssertEqual(lines[0].content, "Please add tests")
    }
}
