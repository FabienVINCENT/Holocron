import XCTest

final class SessionReducerTests: XCTestCase {
    private func lines(_ raw: [String]) -> [TranscriptLine] {
        let parser = TranscriptParser()
        return parser.feed(Fixtures.joined(raw))
    }

    private func makeReducer() -> SessionReducer {
        SessionReducer(
            sessionId: "7774231e-3037-5a0c-9ddf-b5ae0f40a435",
            transcriptURL: URL(fileURLWithPath: "/tmp/t.jsonl")
        )
    }

    func testToolRunningThenResolved() {
        var reducer = makeReducer()
        reducer.apply(lines([Fixtures.userPrompt, Fixtures.assistantToolUse]))
        XCTAssertEqual(reducer.session.runningTools.count, 1)
        XCTAssertEqual(reducer.session.runningTools.first?.name, "Bash")
        XCTAssertEqual(
            reducer.session.inferredStatus(now: date("2026-07-17T06:51:45Z"), idleAfter: 1800),
            .running
        )

        reducer.apply(lines([Fixtures.toolResult]))
        XCTAssertEqual(reducer.session.runningTools.count, 0)
    }

    func testWaitingInputAfterCompletedTurn() {
        var reducer = makeReducer()
        reducer.apply(lines([Fixtures.userPrompt, Fixtures.assistantText]))
        XCTAssertEqual(
            reducer.session.inferredStatus(now: date("2026-07-17T06:52:00Z"), idleAfter: 1800),
            .waitingInput
        )
        XCTAssertEqual(reducer.session.lastAssistantText, "Done. The bug was in auth.ts.")
    }

    func testIdleWhenStale() {
        var reducer = makeReducer()
        reducer.apply(lines([Fixtures.userPrompt, Fixtures.assistantText]))
        XCTAssertEqual(
            reducer.session.inferredStatus(now: date("2026-07-17T09:00:00Z"), idleAfter: 1800),
            .idle
        )
    }

    func testUsageAccumulates() {
        var reducer = makeReducer()
        reducer.apply(lines([Fixtures.assistantText, Fixtures.assistantToolUse]))
        XCTAssertEqual(reducer.session.usage.output, 345 + 56)
        XCTAssertEqual(reducer.session.usage.cacheRead, 52253)
    }

    func testArtifactsRecorded() {
        var reducer = makeReducer()
        reducer.apply(lines([Fixtures.assistantToolUse]))
        XCTAssertEqual(reducer.session.recentCommands.last, "npm test")
    }

    func testProjectNameFromCwd() {
        var reducer = makeReducer()
        reducer.apply(lines([Fixtures.userPrompt]))
        XCTAssertEqual(reducer.session.projectName, "holocron")
        XCTAssertEqual(reducer.session.gitBranch, "main")
    }

    private func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }
}
