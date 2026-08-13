import Foundation
import Network

/// Warm local-network permission and provide ATS-safe cleartext HTTP for LAN/Tailscale.
enum LocalNetworkHTTP {
    static func warmUp(host: String, port: Int) {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else { return }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready, .failed, .cancelled:
                connection.cancel()
            default:
                break
            }
        }
        connection.start(queue: .global(qos: .utility))
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) {
            connection.cancel()
        }
    }

    static func data(for request: URLRequest, timeout: TimeInterval = 20) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url, let host = url.host else {
            throw URLError(.badURL)
        }
        let port = url.port ?? 4747
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else {
            throw URLError(.badURL)
        }

        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            var resumed = false
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if !resumed { resumed = true; cont.resume() }
                case .failed(let error):
                    if !resumed { resumed = true; cont.resume(throwing: error) }
                case .cancelled:
                    if !resumed { resumed = true; cont.resume(throwing: URLError(.cancelled)) }
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if !resumed {
                    resumed = true
                    connection.cancel()
                    cont.resume(throwing: URLError(.timedOut))
                }
            }
        }

        let path = url.path.isEmpty ? "/" : url.path
        let query = url.query.map { "?\($0)" } ?? ""
        var headerLines = [
            "\(request.httpMethod ?? "GET") \(path)\(query) HTTP/1.1",
            "Host: \(host)",
            "Connection: close",
            "Accept: */*"
        ]
        if let headers = request.allHTTPHeaderFields {
            for (key, value) in headers where key.lowercased() != "host" {
                headerLines.append("\(key): \(value)")
            }
        }
        let body = request.httpBody ?? Data()
        if !body.isEmpty {
            headerLines.append("Content-Length: \(body.count)")
        }
        var payload = Data((headerLines.joined(separator: "\r\n") + "\r\n\r\n").utf8)
        payload.append(body)
        try await send(connection, payload)

        let raw = try await receiveAll(connection, timeout: timeout)
        connection.cancel()
        return try parseHTTP(url: url, data: raw)
    }

    private static func send(_ connection: NWConnection, _ data: Data) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { cont.resume(throwing: error) }
                else { cont.resume() }
            })
        }
    }

    private static func receiveAll(_ connection: NWConnection, timeout: TimeInterval) async throws -> Data {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            var buffer = Data()
            var resumed = false
            func finish(_ result: Result<Data, Error>) {
                guard !resumed else { return }
                resumed = true
                cont.resume(with: result)
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                finish(.failure(URLError(.timedOut)))
            }
            func loop() {
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { content, _, isComplete, error in
                    if let error {
                        finish(.failure(error))
                        return
                    }
                    if let content { buffer.append(content) }
                    if isComplete {
                        finish(.success(buffer))
                    } else {
                        loop()
                    }
                }
            }
            loop()
        }
    }

    private static func parseHTTP(url: URL, data: Data) throws -> (Data, HTTPURLResponse) {
        guard let text = String(data: data, encoding: .utf8),
              let headerEnd = text.range(of: "\r\n\r\n") else {
            throw URLError(.badServerResponse)
        }
        let headerPart = String(text[..<headerEnd.lowerBound])
        let bodyOffset = text.distance(from: text.startIndex, to: headerEnd.upperBound)
        let body = data.dropFirst(bodyOffset)
        let lines = headerPart.split(separator: "\r\n")
        guard let statusLine = lines.first,
              let codeString = statusLine.split(separator: " ").dropFirst().first,
              let code = Int(codeString) else {
            throw URLError(.badServerResponse)
        }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2 {
                headers[String(parts[0]).trimmingCharacters(in: .whitespaces)] =
                    String(parts[1]).trimmingCharacters(in: .whitespaces)
            }
        }
        guard let response = HTTPURLResponse(url: url, statusCode: code, httpVersion: "HTTP/1.1", headerFields: headers) else {
            throw URLError(.badServerResponse)
        }
        return (Data(body), response)
    }
}
