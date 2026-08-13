import Foundation
import Security

struct AIConfiguration: Equatable {
    var host: String
    var port: Int
    var useTLS: Bool
    var token: String
    var deviceID: String

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
            deviceID: UserDefaults.standard.string(forKey: "noco.ai.device") ?? ""
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

@MainActor
final class AIClient: ObservableObject {
    @Published var configuration: AIConfiguration = .stored
    @Published private(set) var reachability: AIReachability = .unknown
    @Published private(set) var lastCheckedAt: Date?
    @Published private(set) var pluginStatus: RunningPluginStatus?
    @Published var lastError: String?
    @Published var conversationID: String?

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 6
        config.timeoutIntervalForResource = 45
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    func testConnection() async {
        lastCheckedAt = .now
        guard configuration.isPaired else {
            reachability = .unpaired
            return
        }
        guard let url = configuration.apiURL("/api/v1/running/status") else {
            reachability = .unreachable
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyAuth(&request)
        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                reachability = .connected
                pluginStatus = try? JSONDecoder().decode(RunningPluginStatus.self, from: data)
                lastError = nil
            } else {
                reachability = .unreachable
            }
        } catch {
            // Fallback: companion ping
            if await pingCompanion() {
                reachability = .connected
            } else {
                reachability = .unreachable
                lastError = error.localizedDescription
            }
        }
    }

    func pair(with payload: PairingPayload) async -> Bool {
        var config = configuration
        config.host = payload.lanHost?.isEmpty == false ? payload.lanHost! : payload.host
        config.port = payload.port
        config.useTLS = false
        configuration = config

        guard let url = configuration.apiURL("/api/v1/pair") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode([
            "pin": payload.pin,
            "device_name": "NOCO RUNNING",
            "deviceName": "NOCO RUNNING"
        ])
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let token = json["token"] as? String, !token.isEmpty else {
                lastError = "PIN ungültig oder abgelaufen — neuen QR auf dem PC scannen"
                return false
            }
            config.token = token
            config.deviceID = (json["device_id"] as? String) ?? (json["deviceId"] as? String) ?? ""
            config.persist()
            configuration = config
            reachability = .connected
            lastError = nil
            await testConnection()
            return true
        } catch {
            lastError = error.localizedDescription
            reachability = .unreachable
            return false
        }
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
        if let remote: RunningAnalyzeResponse = await post("/api/v1/running/analyze", body: Body(run_id: run.id.uuidString)),
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
        struct Body: Encodable {
            var question: String
            var conversation_id: String?
            var run_id: String?
        }
        if let remote: RunningAskResponse = await post(
            "/api/v1/running/ask",
            body: Body(question: question, conversation_id: conversationID, run_id: runID?.uuidString)
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
        var ctx = context
        ctx.question = question
        return OfflineCoach.answer(question: question, context: ctx)
    }

    func importText(_ text: String) async -> ImportedRunDraft {
        // Text import stays local; PC gets structured runs via /running/import after save.
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
        let payload = runs.map(RunningPayloadMapper.pluginRun)
        struct Wrap: Encodable { var runs: [[String: AnyCodable]] }
        // Encode as raw JSON array/object without AnyCodable complexity
        guard let url = configuration.apiURL("/api/v1/running/import") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuth(&request)
        request.timeoutInterval = 30
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: ["runs": payload])
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            reachability = .connected
            return try? JSONDecoder().decode(RunningImportResponse.self, from: data)
        } catch {
            reachability = .unreachable
            return nil
        }
    }

    private func pingCompanion() async -> Bool {
        guard let url = configuration.apiURL("/api/v1/ping") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyAuth(&request)
        do {
            let (_, response) = try await session.data(for: request)
            return (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
        } catch {
            return false
        }
    }

    private func post<T: Decodable, B: Encodable>(_ path: String, body: B) async -> T? {
        guard configuration.isPaired else { return nil }
        if reachability == .unreachable, lastCheckedAt != nil {
            await testConnection()
            if reachability == .unreachable { return nil }
        }
        guard let url = configuration.apiURL(path) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuth(&request)
        request.timeoutInterval = 35
        do {
            request.httpBody = try JSONEncoder().encode(body)
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            reachability = .connected
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            reachability = .unreachable
            return nil
        }
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
