import Foundation
import Security

enum APIError: LocalizedError {
    case invalidResponse
    case rateLimited(message: String, quota: Quota?, retryAfter: TimeInterval)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "The server returned an unreadable response."
        case let .rateLimited(message, _, _): message
        case let .server(message): message
        }
    }
}

actor APIClient {
    static let shared = APIClient()
    private let baseURL = URL(string: "https://stew-university-backend.onrender.com")!
    private let decoder: JSONDecoder
    private let encoder = JSONEncoder()

    init() {
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func chat(message: String, mode: ChatMode, history: [ChatMessage]) async throws -> (String, Quota?) {
        let body = ChatRequestBody(
            message: message,
            mode: mode,
            history: history.suffix(8).map { .init(role: $0.role.rawValue, content: $0.content) },
            installationId: InstallationIdentity.shared.value
        )
        var request = URLRequest(url: baseURL.appending(path: "chat"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }

        if http.statusCode == 429 {
            let retry = TimeInterval(http.value(forHTTPHeaderField: "Retry-After") ?? "60") ?? 60
            let payload = try? decoder.decode(RateLimitErrorEnvelope.self, from: data)
            throw APIError.rateLimited(
                message: payload?.detail.message ?? "Your AI limit has been reached. Please try again later.",
                quota: payload?.detail.quota,
                retryAfter: retry
            )
        }
        guard (200..<300).contains(http.statusCode) else {
            let payload = try? decoder.decode(ErrorEnvelope.self, from: data)
            throw APIError.server(payload?.detail ?? "The server is temporarily unavailable.")
        }
        let payload = try decoder.decode(ChatResponseBody.self, from: data)
        let quota: Quota?
        if let remaining = payload.remaining, let limit = payload.limit, let reset = payload.resetAt {
            quota = Quota(remaining: remaining, limit: limit, resetAt: reset)
        } else {
            quota = nil
        }
        return (payload.response, quota)
    }

    func notes(endpoint: String, body: [String: String]) async throws -> [String] {
        var request = URLRequest(url: baseURL.appending(path: endpoint))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.server("Music theory data is temporarily unavailable.")
        }
        return try decoder.decode(TheoryResponse.self, from: data).notes
    }
}

private struct ErrorEnvelope: Decodable { let detail: String }
private struct RateLimitErrorEnvelope: Decodable {
    struct Detail: Decodable {
        let message: String
        let remaining: Int
        let limit: Int
        let resetAt: Date
        var quota: Quota { Quota(remaining: remaining, limit: limit, resetAt: resetAt) }
        enum CodingKeys: String, CodingKey { case message, remaining, limit; case resetAt = "reset_at" }
    }
    let detail: Detail
}

final class InstallationIdentity: @unchecked Sendable {
    static let shared = InstallationIdentity()
    let value: String

    private init() {
        let service = "com.stewuniversity.ios"
        let account = "installation-id"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true
        ]
        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
           let data = item as? Data, let existing = String(data: data, encoding: .utf8) {
            value = existing
            return
        }
        let created = UUID().uuidString.lowercased()
        var add = query
        add.removeValue(forKey: kSecReturnData as String)
        add[kSecValueData as String] = Data(created.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
        value = created
    }
}
