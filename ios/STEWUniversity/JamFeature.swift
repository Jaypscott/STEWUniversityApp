import Combine
import Foundation

enum JamInstrument: String, CaseIterable, Codable, Identifiable, Sendable {
    case guitar
    case bass
    case drums
    case keys
    case vocals

    var id: String { rawValue }

    var title: String {
        switch self {
        case .guitar: "Guitar"
        case .bass: "Bass"
        case .drums: "Drums"
        case .keys: "Piano / Keys"
        case .vocals: "Vocals"
        }
    }

    var symbol: String {
        switch self {
        case .guitar: "guitars"
        case .bass: "music.note"
        case .drums: "circle.grid.cross"
        case .keys: "pianokeys"
        case .vocals: "mic"
        }
    }
}

enum JamDifficulty: String, Codable, CaseIterable, Sendable {
    case beginner
    case developing
    case advanced

    var title: String { rawValue.capitalized }
}

struct JamTrack: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let title: String
    let supportedInstruments: [JamInstrument]
    let genre: String
    let musicalKey: String
    let bpm: Int
    let duration: TimeInterval
    let difficulty: JamDifficulty
    let practicePrompt: String?
    let artworkURL: URL?
    let audioURL: URL

    enum CodingKeys: String, CodingKey {
        case id, title, genre, bpm, duration, difficulty
        case supportedInstruments = "supported_instruments"
        case musicalKey = "musical_key"
        case practicePrompt = "practice_prompt"
        case artworkURL = "artwork_url"
        case audioURL = "audio_url"
    }
}

protocol JamCatalogProviding: Sendable {
    func fetchTracks() async throws -> [JamTrack]
}

struct EmptyJamCatalogProvider: JamCatalogProviding {
    func fetchTracks() async throws -> [JamTrack] { [] }
}

enum JamCatalogState: Equatable {
    case idle
    case loading
    case loaded([JamTrack])
    case failed(String)
}

@MainActor
final class JamViewModel: ObservableObject {
    @Published private(set) var state: JamCatalogState = .idle

    private let provider: any JamCatalogProviding

    init(provider: any JamCatalogProviding = EmptyJamCatalogProvider()) {
        self.provider = provider
    }

    func loadIfNeeded() async {
        guard state == .idle else { return }
        await load()
    }

    func retry() async {
        await load()
    }

    func tracks(for instrument: JamInstrument) -> [JamTrack] {
        guard case let .loaded(tracks) = state else { return [] }
        return tracks.filter { $0.supportedInstruments.contains(instrument) }
    }

    private func load() async {
        state = .loading
        do {
            state = .loaded(try await provider.fetchTracks())
        } catch {
            state = .failed("We couldn’t load the backing tracks. Check your connection and try again.")
        }
    }
}
