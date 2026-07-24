import Foundation

enum BandRole: String, Codable, CaseIterable, Sendable {
    case owner
    case admin
    case member

    var title: String { rawValue.capitalized }
    var canManageMembers: Bool { self == .owner || self == .admin }
    var canManageAppearance: Bool { self == .owner || self == .admin }
}

enum BandCardKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case note
    case image
    case link
    case project

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .note: "note.text"
        case .image: "photo.on.rectangle"
        case .link: "link"
        case .project: "music.note.list"
        }
    }
}

enum BandCardSize: String, Codable, Sendable {
    case compact
    case tall
    case wide
}

enum BandPartKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case vocals
    case guitar
    case bass
    case drums
    case keys
    case other

    var id: String { rawValue }
    var title: String {
        switch self {
        case .vocals: "Vocals"
        case .guitar: "Guitar"
        case .bass: "Bass"
        case .drums: "Drums"
        case .keys: "Piano / Keys"
        case .other: "Other"
        }
    }
    var symbol: String {
        switch self {
        case .vocals: "mic"
        case .guitar: "guitars"
        case .bass: "music.note"
        case .drums: "circle.grid.cross"
        case .keys: "pianokeys"
        case .other: "waveform"
        }
    }
}

enum BandProjectStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case idea
    case recording
    case review
    case complete

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum BandAssetKind: String, Codable, Sendable { case audio, video, image }
enum BandAssetStatus: String, Codable, Sendable { case pending, uploading, processing, ready, failed }
enum BandReactionKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case heart
    case fire
    case applause
    case listening

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .heart: "heart.fill"
        case .fire: "flame.fill"
        case .applause: "hands.clap.fill"
        case .listening: "ear.fill"
        }
    }
    var title: String { rawValue.capitalized }
}

enum BandNotificationKind: String, Codable, Sendable {
    case mention
    case reply
    case reaction
    case newTake = "new_take"
    case roleChanged = "role_changed"
    case removed
    case reportReceived = "report_received"

    var title: String {
        switch self {
        case .mention: "You were mentioned"
        case .reply: "New reply"
        case .reaction: "New reaction"
        case .newTake: "New take shared"
        case .roleChanged: "Your role changed"
        case .removed: "Band access changed"
        case .reportReceived: "Safety report received"
        }
    }
}

struct BandUser: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let username: String?
    let displayName: String?
    let isPlatformAdmin: Bool
    let profileComplete: Bool
    let termsURL: URL
    let privacyURL: URL
    let supportURL: URL
}

struct BandSummary: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var description: String
    let ownerUserID: UUID
    let imageAssetID: UUID?
    let accentColorHex: String
    let featuredProjectID: UUID?
    let usedBytes: Int64
    let reservedBytes: Int64
    let archivedAt: Date?
    let createdAt: Date
    let role: BandRole?
    let memberCount: Int?

    var isArchived: Bool { archivedAt != nil }
}

struct BandMember: Identifiable, Codable, Equatable, Sendable {
    var id: UUID { userID }
    let userID: UUID
    let username: String?
    let displayName: String?
    let role: BandRole
    let joinedAt: Date
}

struct BandProject: Identifiable, Codable, Equatable, Hashable, Sendable {
    let id: UUID
    let bandID: UUID
    var title: String
    var description: String
    let artworkAssetID: UUID?
    var musicalKey: String?
    var bpm: Int?
    var timeSignature: String?
    var status: BandProjectStatus
    let createdByUserID: UUID
    let archivedAt: Date?
    let createdAt: Date
    let updatedAt: Date

    var isArchived: Bool { archivedAt != nil }
}

struct BandTrack: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let projectID: UUID
    let name: String
    let partKind: BandPartKind
    let customPartLabel: String?
    let createdByUserID: UUID
    let createdAt: Date

    var partTitle: String { customPartLabel ?? partKind.title }
}

struct BandTake: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let projectTrackID: UUID
    let assetID: UUID
    let takeNumber: Int
    let versionLabel: String?
    let startOffsetMilliseconds: Int
    let notes: String
    let createdByUserID: UUID
    let createdAt: Date
}

struct BandAsset: Identifiable, Codable, Equatable, Hashable, Sendable {
    let id: UUID
    let bandID: UUID
    let projectID: UUID?
    let uploadedByUserID: UUID
    let kind: BandAssetKind
    let status: BandAssetStatus
    let originalFilename: String
    let contentType: String
    let byteSize: Int64?
    let durationMilliseconds: Int?
    let failureReason: String?
    let createdAt: Date
}

struct BandPost: Identifiable, Codable, Equatable, Hashable, Sendable {
    let id: UUID
    let bandID: UUID
    let projectID: UUID?
    let referencedProjectID: UUID?
    let authorUserID: UUID
    let authorDisplayName: String?
    let body: String
    let externalURL: URL?
    let cardKind: BandCardKind
    let cardSize: BandCardSize
    let isPinned: Bool
    let pinnedAt: Date?
    let createdAt: Date
    let editedAt: Date?
    let deletedAt: Date?
    let attachments: [BandAsset]
}

struct BandComment: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let postID: UUID
    let authorUserID: UUID
    let authorDisplayName: String?
    let parentCommentID: UUID?
    let body: String
    let createdAt: Date
    let editedAt: Date?
    let deletedAt: Date?
}

struct BandNotification: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let bandID: UUID?
    let actorUserID: UUID?
    let kind: BandNotificationKind
    let relatedEntityType: String?
    let relatedEntityID: UUID?
    let createdAt: Date
    let readAt: Date?
}

struct BandInvitation: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let bandID: UUID
    let url: URL
    let expiresAt: Date
    let status: String
}

struct BandInvitationPreview: Codable, Equatable, Sendable {
    let bandID: UUID
    let bandName: String
    let inviterDisplayName: String
    let expiresAt: Date
}

struct BandPendingInvitation: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let bandID: UUID
    let createdByUserID: UUID
    let expiresAt: Date
    let status: String
    let createdAt: Date
}

enum BandReportReason: String, Codable, CaseIterable, Identifiable, Sendable {
    case harassment
    case explicitContent = "explicit_content"
    case hate
    case violence
    case copyright
    case spam
    case other

    var id: String { rawValue }
    var title: String {
        switch self {
        case .explicitContent: "Explicit content"
        default: rawValue.capitalized
        }
    }
}

enum BandReportStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case open
    case resolved
    case dismissed
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct BandContentReport: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let reporterUserID: UUID
    let bandID: UUID
    let targetType: String
    let targetID: UUID
    let reason: BandReportReason
    let note: String
    let status: BandReportStatus
    let resolvedByUserID: UUID?
    let resolutionNote: String?
    let createdAt: Date
    let resolvedAt: Date?
}

struct AccountAuthTokens: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
    let accessExpiresAt: Date
    let refreshExpiresAt: Date
    let profileRequired: Bool
}

typealias BandAuthTokens = AccountAuthTokens

struct BandPage<Item: Codable & Sendable>: Codable, Sendable {
    let items: [Item]
    let nextCursor: String?
}

struct BandUploadSlot: Codable, Sendable {
    let asset: BandAsset
    let uploadURL: URL
    let expiresAt: Date
    let requiredHeaders: [String: String]
}

struct BandMediaAccess: Codable, Sendable {
    let url: URL
    let expiresAt: Date
}

struct BandDraftProject: Sendable {
    var title = ""
    var description = ""
    var musicalKey = ""
    var bpm: Int?
    var timeSignature = "4/4"
    var status: BandProjectStatus = .idea
}

struct BandDraftPost: Sendable {
    var cardKind: BandCardKind = .note
    var body = ""
    var externalURL = ""
    var referencedProjectID: UUID?
    var mentionedUserIDs: [UUID] = []
}
