import Foundation

enum AppDestination: String, CaseIterable, Identifiable {
    case account = "Account"
    case songwriting = "Songwriting"
    case jam = "Jam"
    case band = "Band"
    case earTraining = "Ear Training"
    case visualizer = "Visualizer"
    case games = "Games"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .account: "person.crop.circle"
        case .songwriting: "pencil.line"
        case .jam: "waveform"
        case .band: "person.3"
        case .earTraining: "ear"
        case .visualizer: "music.note.list"
        case .games: "puzzlepiece.extension"
        }
    }
}

struct ChatMessage: Identifiable, Codable, Equatable {
    enum Role: String, Codable { case user, assistant }
    let id: UUID
    let role: Role
    let content: String

    init(id: UUID = UUID(), role: Role, content: String) {
        self.id = id
        self.role = role
        self.content = content
    }
}

struct Quota: Codable, Equatable {
    let remaining: Int
    let limit: Int
    let resetAt: Date
}

enum ChatMode: String, Codable { case general, songwriting, earExplanation = "ear_explanation", theoryChat = "theory_chat" }

struct ChatRequestBody: Encodable {
    struct HistoryItem: Encodable { let role: String; let content: String }
    let message: String
    let mode: ChatMode
    let history: [HistoryItem]
    let installationId: String

    enum CodingKeys: String, CodingKey {
        case message, mode, history
        case installationId = "installation_id"
    }
}

struct ChatResponseBody: Decodable {
    let response: String
    let remaining: Int?
    let limit: Int?
    let resetAt: Date?

    enum CodingKeys: String, CodingKey {
        case response, remaining, limit
        case resetAt = "reset_at"
    }
}

struct TheoryResponse: Decodable {
    let notes: [String]
}
