import Foundation
import Security

struct AIConfiguration: Equatable {
    var host: String
    var port: Int
    var useTLS: Bool
    var token: String

    static var stored: AIConfiguration {
        AIConfiguration(
            host: UserDefaults.standard.string(forKey: "noco.ai.host") ?? "192.168.1.10",
            port: UserDefaults.standard.object(forKey: "noco.ai.port") as? Int ?? 8787,
            useTLS: UserDefaults.standard.bool(forKey: "noco.ai.tls"),
            token: KeychainStore.read(key: "noco.ai.token") ?? ""
        )
    }

    func persist() {
        UserDefaults.standard.set(host, forKey: "noco.ai.host")
        UserDefaults.standard.set(port, forKey: "noco.ai.port")
        UserDefaults.standard.set(useTLS, forKey: "noco.ai.tls")
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
}

@MainActor
final class AIClient: ObservableObject {
    @Published var configuration: AIConfiguration = .stored
    @Published private(set) var reachability: AIReachability = .unknown
    @Published private(set) var lastCheckedAt: Date?

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 4
        config.timeoutIntervalForResource = 20
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    func testConnection() async {
        lastCheckedAt = .now
        guard let url = configuration.baseURL?.appending(path: "/health") else {
            reachability = .unreachable
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyAuth(&request)
        do {
            let (_, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                reachability = .connected
            } else {
                reachability = .unreachable
            }
        } catch {
            reachability = .unreachable
        }
    }

    func analyze(run: RunSummaryDTO, context: AthleteContext) async -> CoachReply {
        if let remote: CoachReply = await post("/v1/analyze", body: AnalyzeBody(run: run, context: context)) {
            return remote
        }
        return OfflineCoach.analyze(run: run, context: context)
    }

    func chat(question: String, context: AthleteContext) async -> CoachReply {
        var ctx = context
        ctx.question = question
        if let remote: CoachReply = await post("/v1/chat", body: ctx) {
            return remote
        }
        return OfflineCoach.answer(question: question, context: ctx)
    }

    func importText(_ text: String) async -> ImportedRunDraft {
        struct Payload: Codable { var text: String }
        if let remote: ImportedRunDraft = await post("/v1/import", body: Payload(text: text)) {
            return remote
        }
        return LocalRunImporter.parse(text)
    }

    func recommendRoute(context: AthleteContext) async -> String {
        struct Hint: Codable { var message: String }
        if let remote: Hint = await post("/v1/recommend", body: context) {
            return remote.message
        }
        return OfflineCoach.routeHint(context: context)
    }

    private struct AnalyzeBody: Codable {
        var run: RunSummaryDTO
        var context: AthleteContext
    }

    private func post<T: Decodable, B: Encodable>(_ path: String, body: B) async -> T? {
        if reachability == .unreachable, lastCheckedAt != nil {
            await testConnection()
            if reachability == .unreachable { return nil }
        }
        guard let url = configuration.baseURL?.appending(path: path) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuth(&request)
        request.timeoutInterval = 12
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
        }
    }
}
