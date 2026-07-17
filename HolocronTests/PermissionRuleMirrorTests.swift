import XCTest

final class PermissionRuleMirrorTests: XCTestCase {
    func testWholeToolRule() {
        let mirror = PermissionRuleMirror(allowPatterns: ["Read"])
        XCTAssertTrue(mirror.allows(toolName: "Read",
                                    toolInput: .object(["file_path": .string("/etc/hosts")])))
        XCTAssertFalse(mirror.allows(toolName: "Bash",
                                     toolInput: .object(["command": .string("ls")])))
    }

    func testBashPrefixRule() {
        let mirror = PermissionRuleMirror(allowPatterns: ["Bash(git:*)", "Bash(npm run test:*)"])
        XCTAssertTrue(mirror.allows(toolName: "Bash",
                                    toolInput: .object(["command": .string("git status")])))
        XCTAssertTrue(mirror.allows(toolName: "Bash",
                                    toolInput: .object(["command": .string("npm run test:unit")])))
        XCTAssertFalse(mirror.allows(toolName: "Bash",
                                     toolInput: .object(["command": .string("rm -rf /")])))
    }

    func testExactBashRule() {
        let mirror = PermissionRuleMirror(allowPatterns: ["Bash(ls)"])
        XCTAssertTrue(mirror.allows(toolName: "Bash",
                                    toolInput: .object(["command": .string("ls")])))
        XCTAssertFalse(mirror.allows(toolName: "Bash",
                                     toolInput: .object(["command": .string("ls -la")])))
    }

    func testGlobFileRule() {
        let mirror = PermissionRuleMirror(allowPatterns: ["Edit(*.md)"])
        XCTAssertTrue(mirror.allows(toolName: "Edit",
                                    toolInput: .object(["file_path": .string("README.md")])))
        XCTAssertFalse(mirror.allows(toolName: "Edit",
                                     toolInput: .object(["file_path": .string("main.swift")])))
    }

    func testDomainRule() {
        let mirror = PermissionRuleMirror(allowPatterns: ["WebFetch(domain:example.com)"])
        XCTAssertTrue(mirror.allows(toolName: "WebFetch",
                                    toolInput: .object(["url": .string("https://api.example.com/x")])))
        XCTAssertFalse(mirror.allows(toolName: "WebFetch",
                                     toolInput: .object(["url": .string("https://evil.com/")])))
    }

    func testUnparsableRulesFailClosed() {
        let mirror = PermissionRuleMirror(allowPatterns: ["Bash(unclosed", ""])
        XCTAssertFalse(mirror.allows(toolName: "Bash",
                                     toolInput: .object(["command": .string("unclosed")])))
    }

    func testGlobMatcher() {
        XCTAssertTrue(PermissionRuleMirror.globMatch(pattern: "src/*.ts", subject: "src/a.ts"))
        XCTAssertTrue(PermissionRuleMirror.globMatch(pattern: "*", subject: "anything"))
        XCTAssertFalse(PermissionRuleMirror.globMatch(pattern: "a?c", subject: "abbc"))
    }
}
