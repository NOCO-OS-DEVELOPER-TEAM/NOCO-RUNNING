import Foundation
import Security

struct AIConfiguration: Equatable {
    var host: String
    var port: Int
    var useTLS: Bool
    var token: String
    var deviceID: String
    var alternateHosts: [String]

    static var stored: AIConfiguration {
        let storedPort = UserDefaults.standard.object(forKey: "noco.ai.port") as? Int
        let token = KeychainStore.read(key: "noco.ai.token") ?? ""
        // Migrate old local FastAPI default (8787) to NOCO AI companion (4747) when unpaired.
        let port: Int = {
            if let storedPort {
                if storedPort == 8787, token.isEmpty { return 4747 }
                return storedPort
            }
            return 4747
        }()
        return AIConfiguration(
            host: UserDefaults.standard.string(forKey: "noco.ai.host") ?? "",
            port: port,
            useTLS: UserDefaults.standard.bool(forKey: "noco.ai.tls"),
            token: token,
            deviceID: UserDefaults.standard.string(forKey: "noco.ai.device") ?? "",
            alternateHosts: UserDefaults.standard.stringArray(forKey: "noco.ai.hosts") ?? []
        )
    }

    var isPaired: Bool {
        !host.isEmpty && !token.isEmpty
    }

    func persist() {
        UserDefaults.standard.set(host, forKey: "noco.ai.host")
        UserDefaults.standard.set(port, forKey: "noco.ai.port")
        UserDefaults.standard.set(useTLS, forKey: "noco.ai.tls")
        UserDefaults.standard.set(deviceID, forKey: "noco.ai.device")
        UserDefaults.standard.set(alternateHosts, forKey: "noco.ai.hosts")
        if token.isEmpty {
            KeychainStore.delete(key: "noco.ai.token")
        } else {
            KeychainStore.write(key: "noco.ai.token", value: token)
        }
    }

    var baseURL: URL? {
        var components = URLComponents()
        components.scheme = useTLS ? "https" : "http"
        components.host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        components.port = port
        return components.url
    }

    func apiURL(_ path: String) -> URL? {
        guard let base = baseURL else { return nil }
        return base.appending(path: path.hasPrefix("/") ? String(path.dropFirst()) : path)
    }
}

enum KeychainStore {
    static func write(key: String, value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "noco.running",
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func read(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "noco.running",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "noco.running"
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum AIReachability: Equatable {
    case unknown
    case connected
    case unreachable
    case unpaired
}

struct PairingPayload: Equatable {
    var host: String
    var port: Int
    var pin: String
    var lanHost: String?
    var remoteHost: String?

    static func parse(_ raw: String) -> PairingPayload? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{"),
           let data = trimmed.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let host = (json["host"] as? String) ?? (json["lanHost"] as? String) ?? ""
            let port = (json["port"] as? Int) ?? Int(json["port"] as? String ?? "") ?? 4747
            let pin = (json["pin"] as? String) ?? ""
            guard !host.isEmpty, !pin.isEmpty else { return nil }
            return PairingPayload(
                host: host,
                port: port,
                pin: pin,
                lanHost: json["lanHost"] as? String,
                remoteHost: json["remoteHost"] as? String
            )
        }

        guard let comps = URLComponents(string: trimmed),
              comps.scheme == "nocoai",
              comps.host == "pair" || comps.path.contains("pair") else {
            // Also accept plain query fragment
            if let comps = URLComponents(string: trimmed.replacingOccurrences(of: "nocoai://pair?", with: "https://pair.local/?")) {
                return fromQuery(comps.queryItems ?? [])
            }
            return nil
        }
        return fromQuery(comps.queryItems ?? [])
    }

    private static func fromQuery(_ items: [URLQueryItem]) -> PairingPayload? {
        let map = Dictionary(uniqueKeysWithValues: items.compactMap { item -> (String, String)? in
            guard let value = item.value, !value.isEmpty else { return nil }
            return (item.name, value)
        })
        let host = map["host"] ?? map["lanHost"] ?? ""
        let pin = map["pin"] ?? ""
        let port = Int(map["port"] ?? "4747") ?? 4747
        guard !host.isEmpty, !pin.isEmpty else { return nil }
        return PairingPayload(
            host: host,
            port: port,
            pin: pin,
            lanHost: map["lanHost"],
            remoteHost: map["remoteHost"]
        )
    }
}

struct RunningPluginStatus: Decodable {
    var success: Bool?
    var ollama: Bool?
    var runs: Int?
    var distanceKm: Double?
    var lastRunAt: String?
}

struct RunningAskResponse: Decodable {
    var success: Bool?
    var answer: String?
    var conversation_id: String?
    var model: String?
}

struct RunningAnalyzeResponse: Decodable {
    var success: Bool?
    var analysis: RunningAnalysisDTO?
}

struct RunningAnalysisDTO: Decodable {
    var summary: String?
    var insights: [String]?
    var recommendations: [String]?
    var confidence: Double?
}

struct RunningImportResponse: Decodable {
    var success: Bool?
    var imported: Int?
    var updated: Int?
    var rejected: Int?
}

struct CompanionChatResponse: Decodable {
    var content: String?
    var conversation_id: String?
    var message: CompanionChatMessage?
}

struct CompanionChatMessage: Decodable {
    var content: String?
}

private enum AuthProbe {
    case ok
    case unauthorized
    case failed
}

@MainActor
final class AIClient: ObservableObject {
    @Published var configuration: AIConfiguration = .stored
    @Published private(set) var reachability: AIReachability = .unknown
    @Published private(set) var lastCheckedAt: Date?
    @Published private(set) var pluginStatus: RunningPluginStatus?
    @Published var lastError: String?
    @Published var conversationID: String?
    @Published private(set) var candidateHosts: [String] = []

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 180
        config.waitsForConnectivity = false
        config.allowsExpensiveNetworkAccess = true
        config.allowsConstrainedNetworkAccess = true
        return URLSession(configuration: config)
    }()

    func testConnection() async {
        lastCheckedAt = .now
        guard configuration.isPaired else {
            reachability = .unpaired
            return
        }
        warmLocalNetwork()
        for host in alternateHosts() {
            let pingOK = await pingCompanion(host: host)
            guard pingOK else { continue }
            let auth = await probeAuth(host: host)
            switch auth {
            case .ok:
                if host != configuration.host {
                    var config = configuration
                    config.host = host
                    config.persist()
                    configuration = config
                }
                reachability = .connected
                lastError = nil
                // Plugin status is slower (Ollama) — never block "online" on it.
                Task { _ = await probeRunningStatus(host: host) }
                return
            case .unauthorized:
                lastError = "Token ungültig — bitte neu per QR koppeln"
                reachability = .unpaired
                return
            case .failed:
                // Ping works; treat as connected so chat can still hit /chat.
                if host != configuration.host {
                    var config = configuration
                    config.host = host
                    config.persist()
                    configuration = config
                }
                reachability = .connected
                lastError = "PC erreichbar — Auth-Status unklar, Chat wird trotzdem versucht."
                return
            }
        }
        reachability = .unreachable
        lastError = "PC nicht erreichbar. Gleiches WLAN? Firewall Port 4747? NOCO AI gestartet? iOS: Lokales Netzwerk erlauben."
    }

    func pair(with payload: PairingPayload) async -> Bool {
        let hosts = [payload.lanHost, payload.host, payload.remoteHost]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        candidateHosts = Array(NSOrderedSet(array: hosts)) as? [String] ?? hosts
        let pin = payload.pin
        let port = payload.port == 0 ? 4747 : payload.port

        for host in candidateHosts {
            LocalNetworkHTTP.warmUp(host: host, port: port)
            if let tokenPack = await attemptPair(host: host, port: port, pin: pin) {
                var config = configuration
                config.host = host
                config.port = port
                config.useTLS = false
                config.token = tokenPack.token
                config.deviceID = tokenPack.deviceID
                config.alternateHosts = candidateHosts
                config.persist()
                configuration = config
                await testConnection()
                if reachability == .connected {
                    lastError = nil
                    return true
                }
                // Keep token even if status flickers — ping might still work after permission grant.
                if await pingCompanion(host: host) {
                    reachability = .connected
                    lastError = nil
                    return true
                }
            }
        }
        lastError = "Kopplung fehlgeschlagen — neuen QR scannen, Lokales Netzwerk erlauben, Port 4747."
        reachability = .unreachable
        return false
    }

    func unpair() {
        var config = configuration
        config.token = ""
        config.deviceID = ""
        config.persist()
        configuration = config
        reachability = .unpaired
        pluginStatus = nil
    }

    func analyze(run: RunSummaryDTO, context: AthleteContext) async -> CoachReply {
        struct Body: Encodable { var run_id: String }
        await ensureOnline()
        if let remote: RunningAnalyzeResponse = await post("/api/v1/running/analyze", body: Body(run_id: run.id.uuidString), timeout: 120),
           let analysis = remote.analysis {
            let insight = ([analysis.summary].compactMap { $0 } + (analysis.insights ?? [])).joined(separator: " ")
            return CoachReply(
                title: "KI-Analyse",
                insight: insight.isEmpty ? (analysis.summary ?? "Analyse fertig.") : insight,
                recommendation: analysis.recommendations?.first,
                mood: "coach",
                source: "noco-ai"
            )
        }
        return OfflineCoach.analyze(run: run, context: context)
    }

    func chat(question: String, context: AthleteContext, runID: UUID? = nil) async -> CoachReply {
        struct AskBody: Encodable {
            var question: String
            var conversation_id: String?
            var run_id: String?
            var source: String
        }
        await ensureOnline()
        if configuration.isPaired, reachability == .connected || reachability == .unknown {
            if let remote: RunningAskResponse = await post(
                "/api/v1/running/ask",
                body: AskBody(
                    question: question,
                    conversation_id: conversationID,
                    run_id: runID?.uuidString,
                    source: "running_app"
                ),
                timeout: 120
            ), let answer = remote.answer, !answer.isEmpty {
                if let id = remote.conversation_id { conversationID = id }
                return CoachReply(
                    title: "Coach",
                    insight: answer,
                    recommendation: nil,
                    mood: "coach",
                    source: remote.model.map { "noco-ai:\($0)" } ?? "noco-ai"
                )
            }
            // Companion chat fallback (same token) if Running-Plugin ask fails.
            if let content = await companionChat(question: question, context: context) {
                return CoachReply(
                    title: "Coach",
                    insight: content,
                    recommendation: nil,
                    mood: "coach",
                    source: "noco-ai"
                )
            }
        }
        var ctx = context
        ctx.question = question
        return OfflineCoach.answer(question: question, context: ctx)
    }

    func fetchRemoteQuestions() async -> [String] {
        guard configuration.isPaired else { return [] }
        await ensureOnline()
        guard reachability == .connected else { return [] }
        guard var components = URLComponents(string: "http://\(configuration.host)") else { return [] }
        components.port = configuration.port
        components.path = "/api/v1/running/questions"
        guard let url = components.url else { return [] }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyAuth(&request)
        request.timeoutInterval = 12
        do {
            let (data, response) = try await perform(request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = json["questions"] as? [[String: Any]] else { return [] }
            return items.compactMap { item in
                (item["question"] as? String) ?? (item["text"] as? String)
            }.filter { !$0.isEmpty }
        } catch {
            return []
        }
    }

    func importText(_ text: String) async -> ImportedRunDraft {
        return LocalRunImporter.parse(text)
    }

    func recommendRoute(context: AthleteContext) async -> String {
        let reply = await chat(
            question: "Welche Distanz und Art von Lauf passt heute zu mir? Kurz empfehlen.",
            context: context
        )
        return reply.insight
    }

    func pushRuns(_ runs: [Run]) async -> RunningImportResponse? {
        await ensureOnline()
        let payload = runs.map(RunningPayloadMapper.pluginRun)
        guard let url = configuration.apiURL("/api/v1/running/import") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuth(&request)
        request.timeoutInterval = 45
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["runs": payload])
        do {
            let (data, response) = try await perform(request)
            guard let http = response as? HTTPURLResponse else { return nil }
            if (200..<300).contains(http.statusCode) {
                reachability = .connected
                return try? JSONDecoder().decode(RunningImportResponse.self, from: data)
            }
            if http.statusCode == 401 {
                lastError = "Token ungültig — bitte neu per QR koppeln"
                reachability = .unpaired
            }
            return nil
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    private func ensureOnline() async {
        if !configuration.isPaired {
            reachability = .unpaired
            return
        }
        if reachability != .connected {
            await testConnection()
        }
    }

    private func warmLocalNetwork() {
        LocalNetworkHTTP.warmUp(host: configuration.host, port: configuration.port)
    }

    private func alternateHosts() -> [String] {
        var hosts = candidateHosts + configuration.alternateHosts
        if !configuration.host.isEmpty { hosts.insert(configuration.host, at: 0) }
        return Array(NSOrderedSet(array: hosts)) as? [String] ?? hosts
    }

    private func attemptPair(host: String, port: Int, pin: String) async -> (token: String, deviceID: String)? {
        guard var components = URLComponents(string: "http://\(host)") else { return nil }
        components.port = port
        components.path = "/api/v1/pair"
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "pin": pin,
            "device_name": "NOCO RUNNING",
            "deviceName": "NOCO RUNNING"
        ])
        do {
            let (data, response) = try await perform(request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let token = json["token"] as? String, !token.isEmpty else {
                return nil
            }
            let deviceID = (json["device_id"] as? String) ?? (json["deviceId"] as? String) ?? ""
            return (token, deviceID)
        } catch {
            return nil
        }
    }

    private func probeRunningStatus(host: String) async -> Bool {
        guard var components = URLComponents(string: "http://\(host)") else { return false }
        components.port = configuration.port
        components.path = "/api/v1/running/status"
        guard let url = components.url else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyAuth(&request)
        request.timeoutInterval = 12
        do {
            let (data, response) = try await perform(request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return false
            }
            pluginStatus = try? JSONDecoder().decode(RunningPluginStatus.self, from: data)
            return true
        } catch {
            return false
        }
    }

    private func pingCompanion(host: String? = nil) async -> Bool {
        let target = host ?? configuration.host
        guard var components = URLComponents(string: "http://\(target)") else { return false }
        components.port = configuration.port
        components.path = "/api/v1/ping"
        guard let url = components.url else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        do {
            let (_, response) = try await perform(request)
            return (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
        } catch {
            return false
        }
    }

    private func post<T: Decodable, B: Encodable>(_ path: String, body: B, timeout: TimeInterval) async -> T? {
        guard configuration.isPaired else { return nil }
        guard let url = configuration.apiURL(path) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuth(&request)
        request.timeoutInterval = timeout
        do {
            request.httpBody = try JSONEncoder().encode(body)
            let (data, response) = try await perform(request)
            guard let http = response as? HTTPURLResponse else { return nil }
            if (200..<300).contains(http.statusCode) {
                reachability = .connected
                return try JSONDecoder().decode(T.self, from: data)
            }
            // 503 = model unavailable — connection is fine
            if http.statusCode == 503 {
                reachability = .connected
                lastError = "Ollama/Modell auf dem PC nicht bereit"
                return nil
            }
            if http.statusCode == 401 {
                lastError = "Token ungültig — neu koppeln"
                reachability = .unpaired
            }
            return nil
        } catch {
            // Retry once via cleartext NW after short reconnect
            await testConnection()
            guard reachability == .connected, let url = configuration.apiURL(path) else { return nil }
            var retry = URLRequest(url: url)
            retry.httpMethod = "POST"
            retry.setValue("application/json", forHTTPHeaderField: "Content-Type")
            applyAuth(&retry)
            retry.timeoutInterval = timeout
            retry.httpBody = try? JSONEncoder().encode(body)
            do {
                let (data, response) = try await perform(retry)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                lastError = error.localizedDescription
                return nil
            }
        }
    }

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            // ATS / local-network flake → Network.framework cleartext
            let (data, http) = try await LocalNetworkHTTP.data(for: request, timeout: max(12, request.timeoutInterval))
            return (data, http)
        }
    }

    private func probeAuth(host: String) async -> AuthProbe {
        guard var components = URLComponents(string: "http://\(host)") else { return .failed }
        components.port = configuration.port
        components.path = "/api/v1/status"
        guard let url = components.url else { return .failed }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyAuth(&request)
        request.timeoutInterval = 10
        do {
            let (_, response) = try await perform(request)
            guard let http = response as? HTTPURLResponse else { return .failed }
            if (200..<300).contains(http.statusCode) { return .ok }
            if http.statusCode == 401 { return .unauthorized }
            return .failed
        } catch {
            return .failed
        }
    }

    private func companionChat(question: String, context: AthleteContext) async -> String? {
        struct ChatBody: Encodable {
            var message: String
            var conversation_id: String?
            var stream: Bool
            var mode: String
            var source: String
        }
        let blurb = """
        [NOCO RUNNING Kontext — nur echte Werte]
        Athlet: \(context.athleteName.isEmpty ? "unbekannt" : context.athleteName)
        Woche: \(String(format: "%.1f", context.weekDistanceMeters / 1000)) km
        Monat: \(String(format: "%.1f", context.monthDistanceMeters / 1000)) km
        Typische Pace: \(context.typicalPaceSecondsPerKm.map { RunFormatters.paceClock($0) } ?? "–")
        Läufe gespeichert: \(context.runCount)
        Frage: \(question)
        """
        guard let remote: CompanionChatResponse = await post(
            "/api/v1/chat",
            body: ChatBody(
                message: blurb,
                conversation_id: conversationID,
                stream: false,
                mode: "flash",
                source: "noco_running"
            ),
            timeout: 120
        ) else { return nil }
        if let id = remote.conversation_id { conversationID = id }
        let text = remote.content ?? remote.message?.content
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    private func applyAuth(_ request: inout URLRequest) {
        let token = configuration.token.trimmingCharacters(in: .whitespacesAndNewlines)
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue(token, forHTTPHeaderField: "X-NOCO-Token")
        }
    }
}

enum RunningPayloadMapper {
    static func pluginRun(_ run: Run) -> [String: Any] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let day = DateFormatter()
        day.calendar = Calendar(identifier: .gregorian)
        day.locale = Locale(identifier: "en_US_POSIX")
        day.dateFormat = "yyyy-MM-dd"

        var gps: [[String: Any]] = []
        for point in run.points.sorted(by: { $0.timestamp < $1.timestamp }).prefix(400) {
            gps.append([
                "lat": point.latitude,
                "lng": point.longitude,
                "t": formatter.string(from: point.timestamp),
                "ele": point.altitude
            ])
        }

        var body: [String: Any] = [
            "id": run.id.uuidString,
            "clientRunId": run.id.uuidString,
            "date": day.string(from: run.startedAt),
            "startTime": formatter.string(from: run.startedAt),
            "distanceKm": run.distanceMeters / 1000,
            "durationSec": run.durationSeconds,
            "source": run.source == .appleHealth ? "import" : "iphone"
        ]
        if let ended = run.endedAt { body["endTime"] = formatter.string(from: ended) }
        if let pace = run.averagePaceSecondsPerKm { body["avgPaceSecPerKm"] = pace }
        if let best = run.splits.min(by: { $0.paceSecondsPerKm < $1.paceSecondsPerKm })?.paceSecondsPerKm {
            body["bestPaceSecPerKm"] = best
        }
        body["avgSpeedKmh"] = run.averageSpeedMPS * 3.6
        if let hr = run.averageHeartRate { body["avgHeartRate"] = hr }
        if let cal = run.calories { body["calories"] = cal }
        body["elevationGainM"] = run.elevationGainMeters
        if let route = run.routeName { body["routeName"] = route }
        if let notes = run.notes { body["notes"] = notes }
        if let temp = run.weatherTempC {
            body["weather"] = [
                "temperatureC": temp,
                "condition": run.weatherSymbol ?? "unknown"
            ]
        }
        if !gps.isEmpty { body["gps"] = gps }
        return body
    }
}

/// Minimal helper kept for compile safety if needed later.
struct AnyCodable: Encodable {
    var value: Any
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let v as String: try container.encode(v)
        case let v as Int: try container.encode(v)
        case let v as Double: try container.encode(v)
        case let v as Bool: try container.encode(v)
        default: try container.encodeNil()
        }
    }
}
