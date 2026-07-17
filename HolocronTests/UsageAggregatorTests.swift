import XCTest

final class UsageAggregatorTests: XCTestCase {
    private func session(id: String, lastActivity: Date, output: Int) -> AgentSession {
        var session = AgentSession(id: id, transcriptURL: URL(fileURLWithPath: "/tmp/\(id).jsonl"))
        session.lastActivityAt = lastActivity
        session.usage.output = output
        session.usage.input = 10
        return session
    }

    func testRollingWindowFiltersOldSessions() {
        let now = Date()
        let sessions = [
            session(id: "fresh", lastActivity: now.addingTimeInterval(-600), output: 100),
            session(id: "stale", lastActivity: now.addingTimeInterval(-6 * 3600), output: 900),
        ]
        let window = UsageAggregator.rollingWindow(sessions: sessions, now: now)
        XCTAssertEqual(window.output, 100)
        XCTAssertEqual(window.sessionCount, 1)
        XCTAssertEqual(window.totalNonCache, 110)
    }

    func testTokenFormatting() {
        XCTAssertEqual(UsageAggregator.format(tokens: 512), "512")
        XCTAssertEqual(UsageAggregator.format(tokens: 12_300), "12.3k")
        XCTAssertEqual(UsageAggregator.format(tokens: 2_450_000), "2.45M")
    }
}
