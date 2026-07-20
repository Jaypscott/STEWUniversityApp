import Foundation
import Security

enum BandAPIError: LocalizedError, Equatable {
    case authenticationRequired
    case server(code: String, message: String, field: String?)
    case invalidResponse
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .authenticationRequired: "Sign in to use Band."
        case let .server(_, message, _): message
        case .invalidResponse: "The Band service returned an unreadable response."
        case let .transport(message): message
        }
    }
}

protocol BandProviding: Sendable {
    func fetchBands() async throws -> [BandSummary]
    func createBand(name: String, description: String) async throws -> BandSummary
    func updateBandAppearance(bandID: UUID, logoAssetID: UUID?, accentColorHex: String?, featuredProjectID: UUID?) async throws -> BandSummary
    func fetchProjects(bandID: UUID) async throws -> [BandProject]
    func createProject(bandID: UUID, draft: BandDraftProject) async throws -> BandProject
    func fetchTracks(bandID: UUID, projectID: UUID) async throws -> [BandTrack]
    func createTrack(bandID: UUID, projectID: UUID, name: String, part: BandPartKind, customLabel: String?) async throws -> BandTrack
    func fetchTakes(bandID: UUID, trackID: UUID) async throws -> [BandTake]
    func createTake(bandID: UUID, trackID: UUID, assetID: UUID, takeNumber: Int, notes: String) async throws -> BandTake
    func fetchPosts(bandID: UUID, projectID: UUID?) async throws -> [BandPost]
    func createPost(bandID: UUID, projectID: UUID?, draft: BandDraftPost, assetIDs: [UUID]) async throws -> BandPost
    func updatePost(bandID: UUID, postID: UUID, draft: BandDraftPost) async throws -> BandPost
    func setPostPinned(bandID: UUID, postID: UUID, isPinned: Bool) async throws -> BandPost
    func deletePost(bandID: UUID, postID: UUID) async throws
    func fetchComments(bandID: UUID, postID: UUID) async throws -> [BandComment]
    func createComment(bandID: UUID, postID: UUID, body: String, mentions: [UUID]) async throws -> BandComment
    func react(bandID: UUID, postID: UUID, reaction: BandReactionKind) async throws
    func fetchMembers(bandID: UUID) async throws -> [BandMember]
    func changeMemberRole(bandID: UUID, userID: UUID, role: BandRole) async throws -> BandMember
    func removeMember(bandID: UUID, userID: UUID) async throws
    func transferOwnership(bandID: UUID, userID: UUID) async throws
    func createInvitation(bandID: UUID) async throws -> BandInvitation
    func fetchInvitations(bandID: UUID) async throws -> [BandPendingInvitation]
    func revokeInvitation(bandID: UUID, invitationID: UUID) async throws
    func previewInvitation(token: String) async throws -> BandInvitationPreview
    func acceptInvitation(token: String) async throws -> BandSummary
    func fetchBlockedUsers() async throws -> [BandUser]
    func blockUser(_ userID: UUID) async throws
    func unblockUser(_ userID: UUID) async throws
    func report(bandID: UUID, targetType: String, targetID: UUID, reason: BandReportReason, note: String) async throws -> BandContentReport
    func fetchAdminReports() async throws -> [BandContentReport]
    func resolveReport(reportID: UUID, status: BandReportStatus, note: String, removeContent: Bool, suspendUser: Bool) async throws -> BandContentReport
    func fetchNotifications() async throws -> [BandNotification]
    func markNotificationsRead() async throws
}

protocol BandMediaProviding: Sendable {
    func createUploadSlot(
        bandID: UUID,
        projectID: UUID?,
        kind: BandAssetKind,
        filename: String,
        contentType: String,
        byteSize: Int64
    ) async throws -> BandUploadSlot
    func completeUpload(assetID: UUID) async throws -> BandAsset
    func fetchAsset(assetID: UUID) async throws -> BandAsset
    func mediaAccess(assetID: UUID) async throws -> BandMediaAccess
}

actor BandAPIClient: BandProviding, BandMediaProviding {
    static let shared = BandAPIClient()

    private let session: URLSession
    private let baseURL: URL
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let tokenStore: BandTokenStore
    private var accessToken: String?
    private var refreshTask: Task<BandAuthTokens, Error>?

    init(
        baseURL: URL? = nil,
        session: URLSession = .shared,
        tokenStore: BandTokenStore = BandTokenStore()
    ) {
        self.baseURL = baseURL
            ?? (Bundle.main.object(forInfoDictionaryKey: "BAND_API_BASE_URL") as? String).flatMap(URL.init(string:))
            ?? URL(string: "https://stew-university-backend.onrender.com")!
        self.session = session
        self.tokenStore = tokenStore
        decoder = BandJSONCoding.decoder()
        encoder = BandJSONCoding.encoder()
    }

    var hasStoredSession: Bool { tokenStore.refreshToken != nil }

    func authenticateWithApple(
        identityToken: String,
        authorizationCode: String,
        nonce: String,
        displayName: String?
    ) async throws -> BandAuthTokens {
        let body = AppleAuthBody(
            identityToken: identityToken,
            authorizationCode: authorizationCode,
            nonce: nonce,
            displayName: displayName
        )
        let tokens: BandAuthTokens = try await request(
            "v1/auth/apple", method: "POST", body: body, authenticated: false
        )
        save(tokens)
        return tokens
    }

    func restoreSession() async throws -> BandUser {
        _ = try await refreshAccessToken()
        return try await currentUser()
    }

    func currentUser() async throws -> BandUser {
        try await request("v1/me")
    }

    func completeProfile(
        username: String,
        displayName: String,
        birthYear: Int,
        acceptsTerms: Bool
    ) async throws -> BandUser {
        try await request(
            "v1/me/profile",
            method: "PATCH",
            body: ProfileBody(
                username: username,
                displayName: displayName,
                birthYear: birthYear,
                acceptsTerms: acceptsTerms
            )
        )
    }

    func registerDevice(token: String, environment: String, enabled: Bool = true) async throws {
        let _: EmptyResponse = try await request(
            "v1/me/devices",
            method: "PUT",
            body: DeviceBody(deviceToken: token, environment: environment, notificationsEnabled: enabled),
            acceptsEmptyResponse: true
        )
    }

    func logout() async {
        if let refreshToken = tokenStore.refreshToken {
            let _: EmptyResponse? = try? await request(
                "v1/auth/logout",
                method: "POST",
                body: RefreshBody(refreshToken: refreshToken),
                authenticated: false,
                acceptsEmptyResponse: true
            )
        }
        accessToken = nil
        tokenStore.refreshToken = nil
    }

    func deleteAccount(identityToken: String, authorizationCode: String, nonce: String) async throws {
        let _: EmptyResponse = try await request(
            "v1/me/account",
            method: "DELETE",
            body: AppleDeleteBody(
                identityToken: identityToken,
                authorizationCode: authorizationCode,
                nonce: nonce
            ),
            acceptsEmptyResponse: true
        )
        accessToken = nil
        tokenStore.refreshToken = nil
    }

    func fetchBands() async throws -> [BandSummary] { try await request("v1/bands") }

    func createBand(name: String, description: String) async throws -> BandSummary {
        try await request(
            "v1/bands", method: "POST", body: BandCreateBody(name: name, description: description)
        )
    }

    func updateBandAppearance(
        bandID: UUID,
        logoAssetID: UUID?,
        accentColorHex: String?,
        featuredProjectID: UUID?
    ) async throws -> BandSummary {
        try await request(
            "v1/bands/\(bandID)",
            method: "PATCH",
            body: BandAppearanceBody(
                imageAssetID: logoAssetID,
                accentColorHex: accentColorHex,
                featuredProjectID: featuredProjectID
            )
        )
    }

    func fetchProjects(bandID: UUID) async throws -> [BandProject] {
        let page: BandPage<BandProject> = try await request("v1/bands/\(bandID)/projects")
        return page.items
    }

    func createProject(bandID: UUID, draft: BandDraftProject) async throws -> BandProject {
        try await request(
            "v1/bands/\(bandID)/projects",
            method: "POST",
            body: ProjectBody(draft: draft)
        )
    }

    func fetchTracks(bandID: UUID, projectID: UUID) async throws -> [BandTrack] {
        try await request("v1/bands/\(bandID)/projects/\(projectID)/tracks")
    }

    func createTrack(
        bandID: UUID,
        projectID: UUID,
        name: String,
        part: BandPartKind,
        customLabel: String?
    ) async throws -> BandTrack {
        try await request(
            "v1/bands/\(bandID)/projects/\(projectID)/tracks",
            method: "POST",
            body: TrackBody(name: name, partKind: part, customPartLabel: customLabel)
        )
    }

    func fetchTakes(bandID: UUID, trackID: UUID) async throws -> [BandTake] {
        try await request("v1/bands/\(bandID)/tracks/\(trackID)/takes")
    }

    func createTake(
        bandID: UUID,
        trackID: UUID,
        assetID: UUID,
        takeNumber: Int,
        notes: String
    ) async throws -> BandTake {
        try await request(
            "v1/bands/\(bandID)/tracks/\(trackID)/takes",
            method: "POST",
            body: TakeBody(assetID: assetID, takeNumber: takeNumber, notes: notes)
        )
    }

    func fetchPosts(bandID: UUID, projectID: UUID?) async throws -> [BandPost] {
        var path = "v1/bands/\(bandID)/posts"
        if let projectID { path += "?project_id=\(projectID)" }
        else { path += "?surface=board" }
        let page: BandPage<BandPost> = try await request(path)
        return page.items
    }

    func createPost(
        bandID: UUID,
        projectID: UUID?,
        draft: BandDraftPost,
        assetIDs: [UUID]
    ) async throws -> BandPost {
        try await request(
            "v1/bands/\(bandID)/posts",
            method: "POST",
            body: PostBody(
                projectID: projectID,
                referencedProjectID: draft.referencedProjectID,
                cardKind: draft.cardKind,
                body: draft.body,
                externalURL: draft.externalURL.nilIfBlank,
                assetIDs: assetIDs,
                mentionedUserIDs: draft.mentionedUserIDs
            )
        )
    }

    func updatePost(
        bandID: UUID,
        postID: UUID,
        draft: BandDraftPost
    ) async throws -> BandPost {
        try await request(
            "v1/bands/\(bandID)/posts/\(postID)",
            method: "PATCH",
            body: PostContentUpdateBody(
                body: draft.body,
                externalURL: draft.cardKind == .link ? draft.externalURL.nilIfBlank : nil,
                referencedProjectID: draft.cardKind == .project ? draft.referencedProjectID : nil
            )
        )
    }

    func setPostPinned(
        bandID: UUID,
        postID: UUID,
        isPinned: Bool
    ) async throws -> BandPost {
        try await request(
            "v1/bands/\(bandID)/posts/\(postID)",
            method: "PATCH",
            body: PostPinBody(isPinned: isPinned)
        )
    }

    func deletePost(bandID: UUID, postID: UUID) async throws {
        let _: EmptyResponse = try await request(
            "v1/bands/\(bandID)/posts/\(postID)",
            method: "DELETE",
            acceptsEmptyResponse: true
        )
    }

    func fetchComments(bandID: UUID, postID: UUID) async throws -> [BandComment] {
        let page: BandPage<BandComment> = try await request(
            "v1/bands/\(bandID)/posts/\(postID)/comments"
        )
        return page.items
    }

    func createComment(
        bandID: UUID,
        postID: UUID,
        body: String,
        mentions: [UUID]
    ) async throws -> BandComment {
        try await request(
            "v1/bands/\(bandID)/posts/\(postID)/comments",
            method: "POST",
            body: CommentBody(body: body, mentionedUserIDs: mentions)
        )
    }

    func react(bandID: UUID, postID: UUID, reaction: BandReactionKind) async throws {
        let _: EmptyResponse = try await request(
            "v1/bands/\(bandID)/posts/\(postID)/reactions",
            method: "PUT",
            body: ReactionBody(kind: reaction),
            acceptsEmptyResponse: true
        )
    }

    func fetchMembers(bandID: UUID) async throws -> [BandMember] {
        try await request("v1/bands/\(bandID)/members")
    }

    func changeMemberRole(bandID: UUID, userID: UUID, role: BandRole) async throws -> BandMember {
        try await request(
            "v1/bands/\(bandID)/members/\(userID)",
            method: "PATCH",
            body: RoleBody(role: role)
        )
    }

    func removeMember(bandID: UUID, userID: UUID) async throws {
        let _: EmptyResponse = try await request(
            "v1/bands/\(bandID)/members/\(userID)",
            method: "DELETE",
            acceptsEmptyResponse: true
        )
    }

    func transferOwnership(bandID: UUID, userID: UUID) async throws {
        let _: EmptyResponse = try await request(
            "v1/bands/\(bandID)/ownership",
            method: "POST",
            body: OwnershipBody(userID: userID),
            acceptsEmptyResponse: true
        )
    }

    func createInvitation(bandID: UUID) async throws -> BandInvitation {
        try await request("v1/bands/\(bandID)/invitations", method: "POST", body: EmptyBody())
    }

    func fetchInvitations(bandID: UUID) async throws -> [BandPendingInvitation] {
        try await request("v1/bands/\(bandID)/invitations")
    }

    func revokeInvitation(bandID: UUID, invitationID: UUID) async throws {
        let _: EmptyResponse = try await request(
            "v1/bands/\(bandID)/invitations/\(invitationID)",
            method: "DELETE",
            acceptsEmptyResponse: true
        )
    }

    func previewInvitation(token: String) async throws -> BandInvitationPreview {
        try await request("v1/invitations/\(token)", authenticated: false)
    }

    func acceptInvitation(token: String) async throws -> BandSummary {
        try await request("v1/invitations/\(token)/accept", method: "POST", body: EmptyBody())
    }

    func fetchBlockedUsers() async throws -> [BandUser] {
        try await request("v1/me/blocked-users")
    }

    func blockUser(_ userID: UUID) async throws {
        let _: EmptyResponse = try await request(
            "v1/me/blocked-users/\(userID)", method: "PUT", body: EmptyBody(), acceptsEmptyResponse: true
        )
    }

    func unblockUser(_ userID: UUID) async throws {
        let _: EmptyResponse = try await request(
            "v1/me/blocked-users/\(userID)", method: "DELETE", acceptsEmptyResponse: true
        )
    }

    func report(
        bandID: UUID,
        targetType: String,
        targetID: UUID,
        reason: BandReportReason,
        note: String
    ) async throws -> BandContentReport {
        try await request(
            "v1/reports",
            method: "POST",
            body: ReportBody(
                bandID: bandID,
                targetType: targetType,
                targetID: targetID,
                reason: reason,
                note: note
            )
        )
    }

    func fetchAdminReports() async throws -> [BandContentReport] {
        try await request("v1/admin/reports")
    }

    func resolveReport(
        reportID: UUID,
        status: BandReportStatus,
        note: String,
        removeContent: Bool,
        suspendUser: Bool
    ) async throws -> BandContentReport {
        try await request(
            "v1/admin/reports/\(reportID)",
            method: "PATCH",
            body: ReportResolveBody(
                status: status,
                resolutionNote: note,
                removeContent: removeContent,
                suspendUser: suspendUser
            )
        )
    }

    func fetchNotifications() async throws -> [BandNotification] {
        let page: BandPage<BandNotification> = try await request("v1/notifications")
        return page.items
    }

    func markNotificationsRead() async throws {
        let _: EmptyResponse = try await request(
            "v1/notifications/read", method: "POST", body: EmptyBody(), acceptsEmptyResponse: true
        )
    }

    func createUploadSlot(
        bandID: UUID,
        projectID: UUID?,
        kind: BandAssetKind,
        filename: String,
        contentType: String,
        byteSize: Int64
    ) async throws -> BandUploadSlot {
        try await request(
            "v1/assets/uploads",
            method: "POST",
            body: UploadBody(
                bandID: bandID,
                projectID: projectID,
                kind: kind,
                filename: filename,
                contentType: contentType,
                byteSize: byteSize
            )
        )
    }

    func completeUpload(assetID: UUID) async throws -> BandAsset {
        try await request("v1/assets/\(assetID)/complete", method: "POST", body: EmptyBody())
    }

    func fetchAsset(assetID: UUID) async throws -> BandAsset {
        try await request("v1/assets/\(assetID)")
    }

    func mediaAccess(assetID: UUID) async throws -> BandMediaAccess {
        try await request("v1/assets/\(assetID)/access")
    }

    private func request<Response: Decodable>(
        _ path: String,
        method: String = "GET",
        authenticated: Bool = true,
        acceptsEmptyResponse: Bool = false,
        retryingAfterRefresh: Bool = false
    ) async throws -> Response {
        try await request(
            path,
            method: method,
            body: Optional<EmptyBody>.none,
            authenticated: authenticated,
            acceptsEmptyResponse: acceptsEmptyResponse,
            retryingAfterRefresh: retryingAfterRefresh
        )
    }

    private func request<Response: Decodable, Body: Encodable>(
        _ path: String,
        method: String = "GET",
        body: Body?,
        authenticated: Bool = true,
        acceptsEmptyResponse: Bool = false,
        retryingAfterRefresh: Bool = false
    ) async throws -> Response {
        guard let url = URL(string: path, relativeTo: baseURL.appending(path: "/")) else {
            throw BandAPIError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(body)
        }
        if authenticated {
            if accessToken == nil { _ = try await refreshAccessToken() }
            guard let accessToken else { throw BandAPIError.authenticationRequired }
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw BandAPIError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw BandAPIError.invalidResponse }
        if http.statusCode == 401, authenticated, !retryingAfterRefresh {
            _ = try await refreshAccessToken()
            return try await self.request(
                path,
                method: method,
                body: body,
                authenticated: authenticated,
                acceptsEmptyResponse: acceptsEmptyResponse,
                retryingAfterRefresh: true
            )
        }
        guard (200..<300).contains(http.statusCode) else {
            if let envelope = try? decoder.decode(BandErrorEnvelope.self, from: data) {
                throw BandAPIError.server(
                    code: envelope.detail.code,
                    message: envelope.detail.message,
                    field: envelope.detail.field
                )
            }
            throw BandAPIError.server(
                code: "http_\(http.statusCode)",
                message: "Band is temporarily unavailable.",
                field: nil
            )
        }
        if acceptsEmptyResponse && data.isEmpty, let empty = EmptyResponse() as? Response {
            return empty
        }
        do { return try decoder.decode(Response.self, from: data) }
        catch { throw BandAPIError.invalidResponse }
    }

    private func refreshAccessToken() async throws -> BandAuthTokens {
        if let refreshTask { return try await refreshTask.value }
        guard let refreshToken = tokenStore.refreshToken else {
            throw BandAPIError.authenticationRequired
        }
        let task = Task<BandAuthTokens, Error> {
            let tokens: BandAuthTokens = try await request(
                "v1/auth/refresh",
                method: "POST",
                body: RefreshBody(refreshToken: refreshToken),
                authenticated: false
            )
            save(tokens)
            return tokens
        }
        refreshTask = task
        defer { refreshTask = nil }
        do { return try await task.value }
        catch {
            accessToken = nil
            tokenStore.refreshToken = nil
            throw error
        }
    }

    private func save(_ tokens: BandAuthTokens) {
        accessToken = tokens.accessToken
        tokenStore.refreshToken = tokens.refreshToken
    }

}

enum BandJSONCoding {
    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .custom { path in
            let source = path.last?.stringValue ?? ""
            let parts = source.split(separator: "_").map(String.init)
            guard parts.count > 1 else { return BandCodingKey(source) }
            let key = parts[0] + parts.dropFirst().map { part in
                part == "id" || part == "ids" ? part.uppercased() : part.capitalized
            }.joined()
            return BandCodingKey(key)
        }
        decoder.dateDecodingStrategy = .custom(decodeDate)
        return decoder
    }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func decodeDate(_ decoder: Decoder) throws -> Date {
        let value = try decoder.singleValueContainer().decode(String.self)
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        let standard = ISO8601DateFormatter()
        if let date = standard.date(from: value) { return date }
        throw DecodingError.dataCorruptedError(
            in: try decoder.singleValueContainer(), debugDescription: "Invalid ISO-8601 date"
        )
    }
}

private struct BandCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil
    init(_ stringValue: String) { self.stringValue = stringValue }
    init?(stringValue: String) { self.init(stringValue) }
    init?(intValue: Int) { return nil }
}

final class BandTokenStore: @unchecked Sendable {
    private let service = "com.stewuniversity.ios.band"
    private let account = "refresh-token"

    var refreshToken: String? {
        get {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true
            ]
            var item: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
                  let data = item as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        }
        set {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account
            ]
            SecItemDelete(query as CFDictionary)
            guard let newValue else { return }
            var add = query
            add[kSecValueData as String] = Data(newValue.utf8)
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(add as CFDictionary, nil)
        }
    }
}

private struct BandErrorEnvelope: Decodable {
    struct Detail: Decodable { let code: String; let message: String; let field: String? }
    let detail: Detail
}
private struct EmptyBody: Encodable {}
private struct EmptyResponse: Codable { init() {} }
private struct AppleAuthBody: Encodable { let identityToken: String; let authorizationCode: String; let nonce: String; let displayName: String? }
private struct AppleDeleteBody: Encodable { let identityToken: String; let authorizationCode: String; let nonce: String }
private struct RefreshBody: Encodable { let refreshToken: String }
private struct ProfileBody: Encodable { let username: String; let displayName: String; let birthYear: Int; let acceptsTerms: Bool }
private struct DeviceBody: Encodable { let deviceToken: String; let environment: String; let notificationsEnabled: Bool }
private struct BandCreateBody: Encodable { let name: String; let description: String }
private struct BandAppearanceBody: Encodable {
    let imageAssetID: UUID?
    let accentColorHex: String?
    let featuredProjectID: UUID?

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let imageAssetID { try container.encode(imageAssetID, forKey: .imageAssetID) }
        else { try container.encodeNil(forKey: .imageAssetID) }
        if let accentColorHex { try container.encode(accentColorHex, forKey: .accentColorHex) }
        else { try container.encodeNil(forKey: .accentColorHex) }
        if let featuredProjectID { try container.encode(featuredProjectID, forKey: .featuredProjectID) }
        else { try container.encodeNil(forKey: .featuredProjectID) }
    }

    private enum CodingKeys: String, CodingKey {
        case imageAssetID
        case accentColorHex
        case featuredProjectID
    }
}
private struct ProjectBody: Encodable {
    let title: String; let description: String; let musicalKey: String?; let bpm: Int?; let timeSignature: String?; let status: BandProjectStatus
    init(draft: BandDraftProject) {
        title = draft.title; description = draft.description; musicalKey = draft.musicalKey.nilIfBlank
        bpm = draft.bpm; timeSignature = draft.timeSignature.nilIfBlank; status = draft.status
    }
}
private struct TrackBody: Encodable { let name: String; let partKind: BandPartKind; let customPartLabel: String? }
private struct TakeBody: Encodable { let assetID: UUID; let takeNumber: Int; let notes: String }
private struct PostBody: Encodable { let projectID: UUID?; let referencedProjectID: UUID?; let cardKind: BandCardKind; let body: String; let externalURL: String?; let assetIDs: [UUID]; let mentionedUserIDs: [UUID] }
private struct PostContentUpdateBody: Encodable { let body: String; let externalURL: String?; let referencedProjectID: UUID? }
private struct PostPinBody: Encodable { let isPinned: Bool }
private struct CommentBody: Encodable { let body: String; let mentionedUserIDs: [UUID] }
private struct ReactionBody: Encodable { let kind: BandReactionKind }
private struct RoleBody: Encodable { let role: BandRole }
private struct OwnershipBody: Encodable { let userID: UUID }
private struct ReportBody: Encodable { let bandID: UUID; let targetType: String; let targetID: UUID; let reason: BandReportReason; let note: String }
private struct ReportResolveBody: Encodable { let status: BandReportStatus; let resolutionNote: String; let removeContent: Bool; let suspendUser: Bool }
private struct UploadBody: Encodable { let bandID: UUID; let projectID: UUID?; let kind: BandAssetKind; let filename: String; let contentType: String; let byteSize: Int64 }

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
