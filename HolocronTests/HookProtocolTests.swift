import XCTest

final class HookProtocolTests: XCTestCase {
    func testEnvelopeRoundTrip() throws {
        let envelope = HookEnvelope(
            v: HookWire.protocolVersion,
            event: .preToolUse,
            context: HookProcessContext(
                pid: 123, ppid: 45, tty: "/dev/ttys003",
                itermSessionId: "w0t2p0:6BF9A6A4-0000-4444-8888-ABCDEF012345",
                termSessionId: nil, termProgram: "iTerm.app", isOrca: false
            ),
            payload: .object([
                "session_id": .string("abc"),
                "tool_name": .string("Bash"),
                "tool_input": .object(["command": .string("rm -rf build")]),
                "permission_mode": .string("default"),
            ])
        )
        let data = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(HookEnvelope.self, from: data)
        XCTAssertEqual(decoded.event, .preToolUse)
        XCTAssertTrue(decoded.event.expectsReply)
        XCTAssertEqual(decoded.context.itermSessionId, envelope.context.itermSessionId)

        let info = PreToolUseInfo(payload: decoded.payload)
        XCTAssertEqual(info.toolName, "Bash")
        XCTAssertEqual(info.toolInput["command"]?.stringValue, "rm -rf build")
        XCTAssertEqual(info.permissionMode, "default")
    }

    func testReplyStdoutJSONShapes() throws {
        let allow = HookReply(action: .allow, reason: nil).stdoutJSON()
        let denyReply = HookReply(action: .deny, reason: "nope").stdoutJSON()
        let passthrough = HookReply.passthrough.stdoutJSON()

        XCTAssertNil(passthrough)

        let allowJSON = try XCTUnwrap(allow)
        let parsed = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(allowJSON.utf8)) as? [String: Any])
        let specific = try XCTUnwrap(parsed["hookSpecificOutput"] as? [String: Any])
        XCTAssertEqual(specific["hookEventName"] as? String, "PreToolUse")
        XCTAssertEqual(specific["permissionDecision"] as? String, "allow")

        let denyJSON = try XCTUnwrap(denyReply)
        XCTAssertTrue(denyJSON.contains("\"permissionDecision\":\"deny\"")
            || denyJSON.contains("\"permissionDecision\" : \"deny\""))
    }

    func testAnswerBecomesDenyWithReason() throws {
        let json = try XCTUnwrap(
            HookReply(action: .answer, reason: "User picked: Option A").stdoutJSON())
        let parsed = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(json.utf8)) as? [String: Any])
        let specific = try XCTUnwrap(parsed["hookSpecificOutput"] as? [String: Any])
        XCTAssertEqual(specific["permissionDecision"] as? String, "deny")
        XCTAssertEqual(specific["permissionDecisionReason"] as? String, "User picked: Option A")
    }

    func testAskUserQuestionParsing() {
        let input: JSONValue = .object([
            "questions": .array([
                .object([
                    "question": .string("Which database?"),
                    "header": .string("DB choice"),
                    "multiSelect": .bool(false),
                    "options": .array([
                        .object(["label": .string("PostgreSQL"), "description": .string("relational")]),
                        .object(["label": .string("SQLite")]),
                    ]),
                ])
            ])
        ])
        let parsed = AskUserQuestionInput(toolInput: input)
        XCTAssertEqual(parsed?.questions.count, 1)
        XCTAssertEqual(parsed?.questions.first?.options.count, 2)
        XCTAssertEqual(parsed?.questions.first?.options.first?.label, "PostgreSQL")
        XCTAssertNil(AskUserQuestionInput(toolInput: .object([:])))
    }

    func testTerminalAttachmentGUIDExtraction() {
        let context = HookProcessContext(
            pid: 1, ppid: 2, tty: "/dev/ttys001",
            itermSessionId: "w0t2p0:6BF9A6A4-1234-4444-8888-ABCDEF012345",
            termSessionId: nil, termProgram: "iTerm.app", isOrca: false
        )
        XCTAssertEqual(
            TerminalAttachment(context: context).itermGUID,
            "6BF9A6A4-1234-4444-8888-ABCDEF012345"
        )
    }
}
