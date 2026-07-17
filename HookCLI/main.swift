import Foundation

// holocron-hook — the bridge Claude Code invokes on hook events.
//
// Usage (wired into ~/.claude/settings.json by the Holocron app):
//   holocron-hook pretooluse | posttooluse | notification | stop
//                | sessionstart | sessionend
//
// Behavior:
// - Reads the hook JSON payload from stdin (schema owned by Claude Code).
// - Forwards it, plus process context (tty, ITERM_SESSION_ID, Orca markers),
//   to the Holocron app over a Unix domain socket.
// - For PreToolUse only: waits for the user's decision from the notch and
//   prints the corresponding hookSpecificOutput JSON on stdout.
// - FAIL-OPEN BY DESIGN: if the app is not running, the socket is dead, or
//   the wait times out, it exits 0 with no output — Claude Code's normal
//   permission flow takes over. This binary must never wedge a session.

func failOpen() -> Never {
    exit(0)
}

// MARK: - Arguments

guard CommandLine.arguments.count >= 2,
      let event = HookEvent(rawValue: CommandLine.arguments[1].lowercased()) else {
    FileHandle.standardError.write(Data("usage: holocron-hook <event>\n".utf8))
    exit(0)
}

// MARK: - Read stdin payload

let stdinData = FileHandle.standardInput.readDataToEndOfFile()
let payload: JSONValue = {
    guard !stdinData.isEmpty else { return .null }
    return (try? JSONDecoder().decode(JSONValue.self, from: stdinData)) ?? .null
}()

let envelope = HookEnvelope(
    v: HookWire.protocolVersion,
    event: event,
    context: HookProcessContext.capture(),
    payload: payload
)

// MARK: - Connect to the app

let socketPath = ProcessInfo.processInfo.environment["HOLOCRON_SOCKET"]
    ?? HookWire.socketURL().path

let fd = socket(AF_UNIX, SOCK_STREAM, 0)
guard fd >= 0 else { failOpen() }
defer { close(fd) }

var addr = sockaddr_un()
addr.sun_family = sa_family_t(AF_UNIX)
let pathBytes = socketPath.utf8CString
guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else { failOpen() }
withUnsafeMutableBytes(of: &addr.sun_path) { destination in
    pathBytes.withUnsafeBufferPointer { source in
        destination.copyMemory(from: UnsafeRawBufferPointer(
            start: source.baseAddress, count: source.count))
    }
}

let connectResult = withUnsafePointer(to: &addr) { pointer in
    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { rebound in
        connect(fd, rebound, socklen_t(MemoryLayout<sockaddr_un>.size))
    }
}
guard connectResult == 0 else { failOpen() }

// Send timeout: the app should drain instantly; do not linger.
var sendTimeout = timeval(tv_sec: 5, tv_usec: 0)
setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &sendTimeout, socklen_t(MemoryLayout<timeval>.size))

// Receive timeout: how long a permission card may sit unanswered before this
// hook gives up and falls back to the terminal prompt. Must stay below the
// hook timeout configured in settings.json (600s by default).
let waitSeconds = ProcessInfo.processInfo.environment["HOLOCRON_HOOK_WAIT_SECONDS"]
    .flatMap(Int.init) ?? 570
var recvTimeout = timeval(tv_sec: waitSeconds, tv_usec: 0)
setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &recvTimeout, socklen_t(MemoryLayout<timeval>.size))

// MARK: - Send envelope

let encoder = JSONEncoder()
guard var messageData = try? encoder.encode(envelope) else { failOpen() }
messageData.append(UInt8(ascii: "\n"))

var sent = 0
messageData.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
    while sent < raw.count {
        let n = write(fd, raw.baseAddress!.advanced(by: sent), raw.count - sent)
        if n <= 0 { break }
        sent += n
    }
}
guard sent == messageData.count else { failOpen() }

// MARK: - Wait for reply (blocking events only)

guard event.expectsReply else { exit(0) }

var replyData = Data()
var buffer = [UInt8](repeating: 0, count: 4096)
while !replyData.contains(UInt8(ascii: "\n")) {
    let n = read(fd, &buffer, buffer.count)
    if n <= 0 { failOpen() }  // timeout, EOF, or error → fail open
    replyData.append(contentsOf: buffer[0..<n])
    if replyData.count > 1024 * 1024 { failOpen() }
}

guard let newline = replyData.firstIndex(of: UInt8(ascii: "\n")) else { failOpen() }
let line = replyData.subdata(in: replyData.startIndex..<newline)
guard let reply = try? JSONDecoder().decode(HookReply.self, from: line) else { failOpen() }

if let stdout = reply.stdoutJSON() {
    print(stdout)
}
exit(0)
