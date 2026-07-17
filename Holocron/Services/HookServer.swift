import Foundation

/// Unix-domain-socket server the `holocron-hook` processes connect to.
/// Plain BSD sockets + DispatchSource: no third-party dependency, zero cost
/// while idle.
final class HookServer {
    /// Called on the main actor. The reply closure MUST eventually be invoked
    /// exactly once for envelopes whose event `expectsReply`; for others it is
    /// a no-op.
    var onEnvelope: (@MainActor (HookEnvelope, @escaping @Sendable (HookReply) -> Void) -> Void)?

    private let socketURL: URL
    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private let queue = DispatchQueue(label: "fr.fabien-vincent.holocron.hook-server", qos: .userInitiated)
    /// Keeps accepted connections alive until they close themselves.
    private var connections: [ObjectIdentifier: Connection] = [:]

    init(socketURL: URL = HookWire.socketURL()) {
        self.socketURL = socketURL
    }

    deinit { stop() }

    func start() throws {
        stop()
        let directory = socketURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Stale socket from a previous run.
        unlink(socketURL.path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.EMFILE) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketURL.path.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            close(fd)
            throw POSIXError(.ENAMETOOLONG)
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { destination in
            pathBytes.withUnsafeBufferPointer { source in
                destination.copyMemory(from: UnsafeRawBufferPointer(
                    start: source.baseAddress, count: source.count))
            }
        }
        let bindResult = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { rebound in
                bind(fd, rebound, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0, listen(fd, 16) == 0 else {
            close(fd)
            throw POSIXError(.EADDRINUSE)
        }
        // Owner-only: hook decisions are a security boundary.
        chmod(socketURL.path, 0o600)

        listenFD = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptConnection() }
        source.resume()
        acceptSource = source
    }

    func stop() {
        acceptSource?.cancel()
        acceptSource = nil
        if listenFD >= 0 {
            close(listenFD)
            listenFD = -1
        }
        unlink(socketURL.path)
    }

    private func acceptConnection() {
        let clientFD = accept(listenFD, nil, nil)
        guard clientFD >= 0 else { return }

        let connection = Connection(fd: clientFD, queue: queue)
        let key = ObjectIdentifier(connection)
        connections[key] = connection
        connection.onClosed = { [weak self] in
            self?.queue.async { self?.connections.removeValue(forKey: key) }
        }
        connection.onLine = { [weak self, weak connection] data in
            guard let self else { connection?.closeNow(); return }
            guard let envelope = try? JSONDecoder().decode(HookEnvelope.self, from: data) else {
                connection?.closeNow()
                return
            }
            let expectsReply = envelope.event.expectsReply
            let reply: @Sendable (HookReply) -> Void = { [weak connection] reply in
                guard expectsReply else { return }
                connection?.send(reply)
            }
            if !expectsReply { connection?.closeNow() }
            let handler = self.onEnvelope
            Task { @MainActor in
                handler?(envelope, reply)
            }
        }
        connection.startReading()
    }
}

/// One accepted hook connection: reads a newline-terminated envelope, then
/// (optionally) writes back a newline-terminated reply and closes.
private final class Connection {
    var onLine: ((Data) -> Void)?
    var onClosed: (() -> Void)?

    private let fd: Int32
    private let queue: DispatchQueue
    private var readSource: DispatchSourceRead?
    private var buffer = Data()
    private var closed = false

    init(fd: Int32, queue: DispatchQueue) {
        self.fd = fd
        self.queue = queue
    }

    func startReading() {
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.drain() }
        source.setCancelHandler { [weak self] in
            guard let self, !self.closed else { return }
            self.closed = true
            close(self.fd)
            self.onClosed?()
        }
        source.resume()
        readSource = source
    }

    private func drain() {
        var chunk = [UInt8](repeating: 0, count: 16 * 1024)
        let n = read(fd, &chunk, chunk.count)
        if n <= 0 {
            // EOF or error before a full line: nothing to answer.
            closeNow()
            return
        }
        buffer.append(contentsOf: chunk[0..<n])
        if buffer.count > 4 * 1024 * 1024 {
            closeNow()
            return
        }
        if let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let line = buffer.subdata(in: buffer.startIndex..<newline)
            // Stop reading; the connection now only waits for a reply (if any).
            readSource?.setEventHandler {}
            onLine?(line)
            onLine = nil
        }
    }

    func send(_ reply: HookReply) {
        queue.async { [self] in
            guard !closed else { return }
            guard var data = try? JSONEncoder().encode(reply) else {
                closeNow()
                return
            }
            data.append(UInt8(ascii: "\n"))
            data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                var sent = 0
                while sent < raw.count {
                    let n = write(fd, raw.baseAddress!.advanced(by: sent), raw.count - sent)
                    if n <= 0 { break }
                    sent += n
                }
            }
            closeNow()
        }
    }

    func closeNow() {
        guard !closed else {
            return
        }
        if let readSource {
            readSource.cancel()  // cancel handler closes fd + notifies onClosed
        } else {
            closed = true
            close(fd)
            onClosed?()
        }
    }
}
