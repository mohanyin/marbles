import Foundation
import Network

final class IngestServer: @unchecked Sendable {
    private(set) var url: URL = IngestConstants.defaultURL()
    private(set) var token: String = ""
    private var listener: NWListener?
    private let apply: @Sendable (Data) -> Void
    private let queue = DispatchQueue(label: "dev.marbles.ingest")

    init(apply: @escaping @Sendable (Data) -> Void) {
        self.apply = apply
    }

    func start() {
        token = IngestAuth.loadOrCreateToken(at: IngestConstants.ingestFileURL)
        var port = IngestConstants.defaultPort
        for _ in 0..<8 {
            if bind(port: port) {
                url = IngestConstants.defaultURL(port: port)
                writeIngestFile()
                return
            }
            port += 1
        }
        writeIngestFile()
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func bind(port: Int) -> Bool {
        do {
            guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else { return false }
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: nwPort)
            let listener = try NWListener(using: parameters)
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            let locked = DispatchSemaphore(value: 0)
            var ok = false
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    ok = true
                    locked.signal()
                case .failed, .cancelled:
                    ok = false
                    locked.signal()
                default:
                    break
                }
            }
            listener.start(queue: queue)
            if locked.wait(timeout: .now() + 0.4) == .timedOut {
                listener.cancel()
                return false
            }
            if ok {
                self.listener = listener
                return true
            }
            listener.cancel()
            return false
        } catch {
            return false
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        read(connection, buffer: Data())
    }

    private func read(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if error != nil {
                connection.cancel()
                return
            }
            var next = buffer
            if let data { next.append(data) }
            if let request = HTTPRequest.parse(next) {
                self.respond(connection, to: request)
                return
            }
            if isComplete || next.count > 256 * 1024 {
                self.fail(connection)
                return
            }
            self.read(connection, buffer: next)
        }
    }

    private func respond(_ connection: NWConnection, to request: HTTPRequest) {
        let allowed = request.method == "POST" && (request.path == "/hook" || request.path.hasPrefix("/hook?"))
        guard allowed else {
            send(connection, status: 404, reason: "Not Found", body: Data())
            return
        }
        let provided = request.header(IngestAuth.headerName)
        guard IngestAuth.matches(provided, secret: token) else {
            send(connection, status: 401, reason: "Unauthorized", body: Data())
            return
        }
        apply(request.body)
        send(connection, status: 204, reason: "No Content", body: Data())
    }

    private func fail(_ connection: NWConnection) {
        send(connection, status: 400, reason: "Bad Request", body: Data())
    }

    private func send(_ connection: NWConnection, status: Int, reason: String, body: Data) {
        let header = "HTTP/1.1 \(status) \(reason)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        var payload = Data(header.utf8)
        payload.append(body)
        connection.send(content: payload, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func writeIngestFile() {
        let directory = IngestConstants.applicationSupport
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let payload = ["url": url.absoluteString, "token": token]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]) {
            try? data.write(to: IngestConstants.ingestFileURL, options: .atomic)
            IngestAuth.restrictFile(at: IngestConstants.ingestFileURL)
        }
    }
}

private struct HTTPRequest {
    var method: String
    var path: String
    var headers: [String: String]
    var body: Data

    func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }

    static func parse(_ data: Data) -> HTTPRequest? {
        guard let range = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headerData = data.subdata(in: data.startIndex..<range.lowerBound)
        guard let headerText = String(data: headerData, encoding: .utf8) else { return nil }
        let lines = headerText.split(whereSeparator: \.isNewline).map(String.init)
        guard let request = lines.first else { return nil }
        let parts = request.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        var length = 0
        for line in lines.dropFirst() {
            let pieces = line.split(separator: ":", maxSplits: 1)
            guard pieces.count == 2 else { continue }
            let name = pieces[0].trimmingCharacters(in: .whitespaces).lowercased()
            let value = pieces[1].trimmingCharacters(in: .whitespaces)
            headers[name] = value
            if name == "content-length" {
                length = Int(value) ?? 0
            }
        }
        let bodyStart = range.upperBound
        let available = data.endIndex - bodyStart
        guard available >= length else { return nil }
        let body = data.subdata(in: bodyStart..<bodyStart.advanced(by: length))
        return HTTPRequest(method: String(parts[0]), path: String(parts[1]), headers: headers, body: body)
    }
}
