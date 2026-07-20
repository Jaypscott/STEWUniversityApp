import Foundation

enum BandWorkspaceTab: String, CaseIterable, Identifiable {
    case home = "Home"
    case projects = "Projects"
    case members = "Members"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .home: "house.fill"
        case .projects: "music.note.list"
        case .members: "person.3.fill"
        }
    }
}

@MainActor
final class BandStore: ObservableObject {
    @Published private(set) var bands: [BandSummary] = []
    @Published var selectedBandID: UUID?
    @Published var selectedTab: BandWorkspaceTab = .home
    @Published private(set) var posts: [BandPost] = []
    @Published private(set) var projects: [BandProject] = []
    @Published private(set) var members: [BandMember] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published var pendingInvitationToken: String?

    let provider: any BandProviding
    private var currentUserID: UUID?

    init(
        provider: (any BandProviding)? = nil,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) {
        if let provider {
            self.provider = provider
        } else if arguments.contains("--ui-testing-band-demo") {
            self.provider = DemoBandProvider(populated: true)
        } else if arguments.contains("--ui-testing-band-empty") {
            self.provider = DemoBandProvider(populated: false)
        } else {
            self.provider = BandAPIClient.shared
        }
    }

    var selectedBand: BandSummary? {
        bands.first { $0.id == selectedBandID }
    }

    var featuredProject: BandProject? {
        guard let projectID = selectedBand?.featuredProjectID else { return nil }
        return projects.first { $0.id == projectID }
    }

    func project(_ id: UUID?) -> BandProject? {
        guard let id else { return nil }
        return projects.first { $0.id == id }
    }

    func load(userID: UUID, force: Bool = false) async {
        if isLoading || (!force && currentUserID == userID && !bands.isEmpty) { return }
        if currentUserID != userID { selectedTab = .home }
        currentUserID = userID
        isLoading = true
        errorMessage = nil
        do {
            bands = try await provider.fetchBands()
            let saved = UserDefaults.standard.string(forKey: selectionKey(userID)).flatMap(UUID.init)
            selectedBandID = bands.contains(where: { $0.id == saved }) ? saved : bands.first?.id
            if let selectedBandID { await loadWorkspace(bandID: selectedBandID) }
            else { clearWorkspace() }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func selectBand(_ bandID: UUID) async {
        guard bandID != selectedBandID else { return }
        selectedBandID = bandID
        if let currentUserID {
            UserDefaults.standard.set(bandID.uuidString, forKey: selectionKey(currentUserID))
        }
        await loadWorkspace(bandID: bandID)
    }

    func loadWorkspace(bandID: UUID) async {
        isLoading = true
        errorMessage = nil
        do {
            async let loadedPosts = provider.fetchPosts(bandID: bandID, projectID: nil)
            async let loadedProjects = provider.fetchProjects(bandID: bandID)
            async let loadedMembers = provider.fetchMembers(bandID: bandID)
            posts = try await loadedPosts
            projects = try await loadedProjects
            members = try await loadedMembers
            sortBoard()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func createBand(name: String, description: String) async -> Bool {
        do {
            let band = try await provider.createBand(name: name, description: description)
            bands.insert(band, at: 0)
            selectedBandID = band.id
            if let currentUserID {
                UserDefaults.standard.set(band.id.uuidString, forKey: selectionKey(currentUserID))
            }
            clearWorkspace()
            members = try await provider.fetchMembers(bandID: band.id)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func createProject(_ draft: BandDraftProject) async -> Bool {
        guard let bandID = selectedBandID else { return false }
        do {
            let project = try await provider.createProject(bandID: bandID, draft: draft)
            projects.insert(project, at: 0)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func updateAppearance(
        logoAssetID: UUID?,
        accentColorHex: String?,
        featuredProjectID: UUID?
    ) async -> Bool {
        guard let bandID = selectedBandID else { return false }
        do {
            let updated = try await provider.updateBandAppearance(
                bandID: bandID,
                logoAssetID: logoAssetID,
                accentColorHex: accentColorHex,
                featuredProjectID: featuredProjectID
            )
            if let index = bands.firstIndex(where: { $0.id == updated.id }) {
                bands[index] = updated
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func createPost(_ draft: BandDraftPost, projectID: UUID? = nil, assetIDs: [UUID] = []) async -> Bool {
        guard let bandID = selectedBandID else { return false }
        do {
            let post = try await provider.createPost(
                bandID: bandID,
                projectID: projectID,
                draft: draft,
                assetIDs: assetIDs
            )
            if projectID == nil {
                posts.insert(post, at: 0)
                sortBoard()
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func updatePost(_ post: BandPost, draft: BandDraftPost) async -> Bool {
        guard let bandID = selectedBandID else { return false }
        do {
            let updated = try await provider.updatePost(
                bandID: bandID, postID: post.id, draft: draft
            )
            replacePost(updated)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func setPinned(_ post: BandPost, isPinned: Bool) async -> Bool {
        guard let bandID = selectedBandID else { return false }
        do {
            let updated = try await provider.setPostPinned(
                bandID: bandID, postID: post.id, isPinned: isPinned
            )
            replacePost(updated)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func deletePost(_ post: BandPost) async -> Bool {
        guard let bandID = selectedBandID else { return false }
        do {
            try await provider.deletePost(bandID: bandID, postID: post.id)
            posts.removeAll { $0.id == post.id }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func createInvitation() async throws -> BandInvitation {
        guard let bandID = selectedBandID else {
            throw BandAPIError.server(code: "band_required", message: "Choose a Band first.", field: nil)
        }
        return try await provider.createInvitation(bandID: bandID)
    }

    func pendingInvitations() async throws -> [BandPendingInvitation] {
        guard let bandID = selectedBandID else { return [] }
        return try await provider.fetchInvitations(bandID: bandID)
    }

    func revokeInvitation(_ invitationID: UUID) async throws {
        guard let bandID = selectedBandID else { return }
        try await provider.revokeInvitation(bandID: bandID, invitationID: invitationID)
    }

    func changeRole(for userID: UUID, to role: BandRole) async throws {
        guard let bandID = selectedBandID else { return }
        let changed = try await provider.changeMemberRole(bandID: bandID, userID: userID, role: role)
        if let index = members.firstIndex(where: { $0.userID == userID }) { members[index] = changed }
    }

    func removeMember(_ userID: UUID) async throws {
        guard let bandID = selectedBandID else { return }
        try await provider.removeMember(bandID: bandID, userID: userID)
        members.removeAll { $0.userID == userID }
    }

    func transferOwnership(to userID: UUID) async throws {
        guard let bandID = selectedBandID else { return }
        try await provider.transferOwnership(bandID: bandID, userID: userID)
        members = try await provider.fetchMembers(bandID: bandID)
        bands = try await provider.fetchBands()
    }

    func invitationPreview(token: String) async throws -> BandInvitationPreview {
        try await provider.previewInvitation(token: token)
    }

    func acceptInvitation(token: String) async throws {
        let band = try await provider.acceptInvitation(token: token)
        if !bands.contains(where: { $0.id == band.id }) { bands.insert(band, at: 0) }
        pendingInvitationToken = nil
        await selectBand(band.id)
    }

    func comments(for postID: UUID) async throws -> [BandComment] {
        guard let bandID = selectedBandID else { return [] }
        return try await provider.fetchComments(bandID: bandID, postID: postID)
    }

    func addComment(to postID: UUID, body: String) async throws -> BandComment {
        guard let bandID = selectedBandID else {
            throw BandAPIError.server(code: "band_required", message: "Choose a Band first.", field: nil)
        }
        return try await provider.createComment(bandID: bandID, postID: postID, body: body, mentions: [])
    }

    func react(to postID: UUID, with reaction: BandReactionKind) async throws {
        guard let bandID = selectedBandID else { return }
        try await provider.react(bandID: bandID, postID: postID, reaction: reaction)
    }

    func tracks(for projectID: UUID) async throws -> [BandTrack] {
        guard let bandID = selectedBandID else { return [] }
        return try await provider.fetchTracks(bandID: bandID, projectID: projectID)
    }

    func createTrack(projectID: UUID, name: String, part: BandPartKind, customLabel: String?) async throws -> BandTrack {
        guard let bandID = selectedBandID else {
            throw BandAPIError.server(code: "band_required", message: "Choose a Band first.", field: nil)
        }
        return try await provider.createTrack(
            bandID: bandID,
            projectID: projectID,
            name: name,
            part: part,
            customLabel: customLabel
        )
    }

    func takes(for trackID: UUID) async throws -> [BandTake] {
        guard let bandID = selectedBandID else { return [] }
        return try await provider.fetchTakes(bandID: bandID, trackID: trackID)
    }

    func createTake(trackID: UUID, assetID: UUID, takeNumber: Int, notes: String) async throws -> BandTake {
        guard let bandID = selectedBandID else {
            throw BandAPIError.server(code: "band_required", message: "Choose a Band first.", field: nil)
        }
        return try await provider.createTake(
            bandID: bandID,
            trackID: trackID,
            assetID: assetID,
            takeNumber: takeNumber,
            notes: notes
        )
    }

    func refresh() async {
        guard let selectedBandID else { return }
        await loadWorkspace(bandID: selectedBandID)
    }

    func clear() {
        bands = []
        selectedBandID = nil
        selectedTab = .home
        currentUserID = nil
        clearWorkspace()
    }

    private func clearWorkspace() {
        posts = []
        projects = []
        members = []
    }

    private func replacePost(_ post: BandPost) {
        if let index = posts.firstIndex(where: { $0.id == post.id }) {
            posts[index] = post
        }
        sortBoard()
    }

    private func sortBoard() {
        posts.sort {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            if $0.isPinned {
                return ($0.pinnedAt ?? .distantPast) > ($1.pinnedAt ?? .distantPast)
            }
            return $0.createdAt > $1.createdAt
        }
    }

    private func selectionKey(_ userID: UUID) -> String { "stew.band.selected.\(userID)" }
}

@MainActor
final class BandNotificationStore: ObservableObject {
    @Published private(set) var notifications: [BandNotification] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    let provider: any BandProviding

    init(provider: (any BandProviding)? = nil, arguments: [String] = ProcessInfo.processInfo.arguments) {
        if let provider { self.provider = provider }
        else if arguments.contains("--ui-testing-band-demo") {
            self.provider = DemoBandProvider(populated: true)
        } else { self.provider = BandAPIClient.shared }
    }

    var unreadCount: Int { notifications.filter { $0.readAt == nil }.count }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do { notifications = try await provider.fetchNotifications() }
        catch { errorMessage = error.localizedDescription }
    }

    func markAllRead() async {
        do {
            try await provider.markNotificationsRead()
            notifications = notifications.map {
                BandNotification(
                    id: $0.id,
                    bandID: $0.bandID,
                    actorUserID: $0.actorUserID,
                    kind: $0.kind,
                    relatedEntityType: $0.relatedEntityType,
                    relatedEntityID: $0.relatedEntityID,
                    createdAt: $0.createdAt,
                    readAt: Date()
                )
            }
        } catch { errorMessage = error.localizedDescription }
    }
}

actor DemoBandProvider: BandProviding {
    private var bands: [BandSummary]
    private var projects: [BandProject]
    private var posts: [BandPost]
    private var members: [BandMember]
    private var notifications: [BandNotification]
    private let userID = BandAuthSession.demoUser.id

    init(populated: Bool) {
        let now = Date()
        let bandID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        let projectID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
        bands = populated ? [BandSummary(
            id: bandID,
            name: "Golden Hour",
            description: "A private place for our songs, takes, and ideas.",
            ownerUserID: userID,
            imageAssetID: nil,
            accentColorHex: "#3D7C78",
            featuredProjectID: projectID,
            usedBytes: 86_000_000,
            reservedBytes: 0,
            archivedAt: nil,
            createdAt: now.addingTimeInterval(-86_400 * 30),
            role: .owner,
            memberCount: 3
        )] : []
        projects = populated ? [BandProject(
            id: projectID,
            bandID: bandID,
            title: "Open Skies",
            description: "Warm soul groove with a wide chorus.",
            artworkAssetID: nil,
            musicalKey: "A Major",
            bpm: 92,
            timeSignature: "4/4",
            status: .recording,
            createdByUserID: userID,
            archivedAt: nil,
            createdAt: now.addingTimeInterval(-86_400 * 5),
            updatedAt: now.addingTimeInterval(-3_600)
        )] : []
        posts = populated ? [
            BandPost(
                id: UUID(uuidString: "30000000-0000-0000-0000-000000000001")!,
                bandID: bandID,
                projectID: nil,
                referencedProjectID: nil,
                authorUserID: userID,
                authorDisplayName: "Jaylon",
                body: "Warm, open, and made for a late-summer drive.",
                externalURL: nil,
                cardKind: .note,
                cardSize: .compact,
                isPinned: true,
                pinnedAt: now.addingTimeInterval(-600),
                createdAt: now.addingTimeInterval(-1_800),
                editedAt: nil,
                deletedAt: nil,
                attachments: []
            ),
            BandPost(
                id: UUID(uuidString: "30000000-0000-0000-0000-000000000002")!,
                bandID: bandID,
                projectID: nil,
                referencedProjectID: nil,
                authorUserID: userID,
                authorDisplayName: "Mia",
                body: "Golden light, soft grain, and room to breathe.",
                externalURL: nil,
                cardKind: .image,
                cardSize: .tall,
                isPinned: false,
                pinnedAt: nil,
                createdAt: now.addingTimeInterval(-2_400),
                editedAt: nil,
                deletedAt: nil,
                attachments: []
            ),
            BandPost(
                id: UUID(uuidString: "30000000-0000-0000-0000-000000000003")!,
                bandID: bandID,
                projectID: nil,
                referencedProjectID: nil,
                authorUserID: userID,
                authorDisplayName: "Noah",
                body: "A reference for the space around the chorus.",
                externalURL: URL(string: "https://example.com/reference"),
                cardKind: .link,
                cardSize: .compact,
                isPinned: false,
                pinnedAt: nil,
                createdAt: now.addingTimeInterval(-3_000),
                editedAt: nil,
                deletedAt: nil,
                attachments: []
            ),
            BandPost(
                id: UUID(uuidString: "30000000-0000-0000-0000-000000000004")!,
                bandID: bandID,
                projectID: nil,
                referencedProjectID: projectID,
                authorUserID: userID,
                authorDisplayName: "Jaylon",
                body: "Everything we’re building toward right now.",
                externalURL: nil,
                cardKind: .project,
                cardSize: .wide,
                isPinned: false,
                pinnedAt: nil,
                createdAt: now.addingTimeInterval(-3_600),
                editedAt: nil,
                deletedAt: nil,
                attachments: []
            )
        ] : []
        members = populated ? [
            BandMember(userID: userID, username: "jaylon", displayName: "Jaylon", role: .owner, joinedAt: now.addingTimeInterval(-86_400 * 30)),
            BandMember(userID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, username: "mia", displayName: "Mia", role: .admin, joinedAt: now.addingTimeInterval(-86_400 * 20)),
            BandMember(userID: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, username: "noah", displayName: "Noah", role: .member, joinedAt: now.addingTimeInterval(-86_400 * 10))
        ] : []
        notifications = populated ? [BandNotification(
            id: UUID(),
            bandID: bandID,
            actorUserID: members.dropFirst().first?.userID,
            kind: .reply,
            relatedEntityType: "post",
            relatedEntityID: posts.first?.id,
            createdAt: now.addingTimeInterval(-900),
            readAt: nil
        )] : []
    }

    func fetchBands() -> [BandSummary] { bands }
    func createBand(name: String, description: String) -> BandSummary {
        let band = BandSummary(id: UUID(), name: name, description: description, ownerUserID: userID, imageAssetID: nil, accentColorHex: "#E6A817", featuredProjectID: nil, usedBytes: 0, reservedBytes: 0, archivedAt: nil, createdAt: Date(), role: .owner, memberCount: 1)
        bands.insert(band, at: 0); return band
    }
    func updateBandAppearance(bandID: UUID, logoAssetID: UUID?, accentColorHex: String?, featuredProjectID: UUID?) -> BandSummary {
        let index = bands.firstIndex { $0.id == bandID }!
        let current = bands[index]
        let updated = BandSummary(
            id: current.id,
            name: current.name,
            description: current.description,
            ownerUserID: current.ownerUserID,
            imageAssetID: logoAssetID,
            accentColorHex: accentColorHex ?? "#E6A817",
            featuredProjectID: featuredProjectID,
            usedBytes: current.usedBytes,
            reservedBytes: current.reservedBytes,
            archivedAt: current.archivedAt,
            createdAt: current.createdAt,
            role: current.role,
            memberCount: current.memberCount
        )
        bands[index] = updated
        return updated
    }
    func fetchProjects(bandID: UUID) -> [BandProject] { projects.filter { $0.bandID == bandID } }
    func createProject(bandID: UUID, draft: BandDraftProject) -> BandProject {
        let item = BandProject(id: UUID(), bandID: bandID, title: draft.title, description: draft.description, artworkAssetID: nil, musicalKey: draft.musicalKey, bpm: draft.bpm, timeSignature: draft.timeSignature, status: draft.status, createdByUserID: userID, archivedAt: nil, createdAt: Date(), updatedAt: Date())
        projects.insert(item, at: 0); return item
    }
    func fetchTracks(bandID: UUID, projectID: UUID) -> [BandTrack] { [] }
    func createTrack(bandID: UUID, projectID: UUID, name: String, part: BandPartKind, customLabel: String?) -> BandTrack {
        BandTrack(id: UUID(), projectID: projectID, name: name, partKind: part, customPartLabel: customLabel, createdByUserID: userID, createdAt: Date())
    }
    func fetchTakes(bandID: UUID, trackID: UUID) -> [BandTake] { [] }
    func createTake(bandID: UUID, trackID: UUID, assetID: UUID, takeNumber: Int, notes: String) -> BandTake {
        BandTake(id: UUID(), projectTrackID: trackID, assetID: assetID, takeNumber: takeNumber, versionLabel: nil, startOffsetMilliseconds: 0, notes: notes, createdByUserID: userID, createdAt: Date())
    }
    func fetchPosts(bandID: UUID, projectID: UUID?) -> [BandPost] {
        posts.filter {
            $0.bandID == bandID && (projectID == nil ? $0.projectID == nil : $0.projectID == projectID)
        }
    }
    func createPost(bandID: UUID, projectID: UUID?, draft: BandDraftPost, assetIDs: [UUID]) -> BandPost {
        let size: BandCardSize = switch draft.cardKind {
        case .note, .link: .compact
        case .image: assetIDs.count > 1 ? .wide : .tall
        case .project: .wide
        }
        let item = BandPost(id: UUID(), bandID: bandID, projectID: projectID, referencedProjectID: draft.referencedProjectID, authorUserID: userID, authorDisplayName: "Jaylon", body: draft.body, externalURL: URL(string: draft.externalURL), cardKind: draft.cardKind, cardSize: size, isPinned: false, pinnedAt: nil, createdAt: Date(), editedAt: nil, deletedAt: nil, attachments: [])
        posts.insert(item, at: 0); return item
    }
    func updatePost(bandID: UUID, postID: UUID, draft: BandDraftPost) -> BandPost {
        let index = posts.firstIndex { $0.id == postID }!
        let current = posts[index]
        let updated = copyPost(
            current,
            body: draft.body,
            externalURL: draft.cardKind == .link ? URL(string: draft.externalURL) : current.externalURL,
            referencedProjectID: draft.cardKind == .project ? draft.referencedProjectID : current.referencedProjectID
        )
        posts[index] = updated
        return updated
    }
    func setPostPinned(bandID: UUID, postID: UUID, isPinned: Bool) -> BandPost {
        let index = posts.firstIndex { $0.id == postID }!
        let updated = copyPost(posts[index], isPinned: isPinned, pinnedAt: isPinned ? Date() : nil)
        posts[index] = updated
        return updated
    }
    func deletePost(bandID: UUID, postID: UUID) { posts.removeAll { $0.id == postID } }
    func fetchComments(bandID: UUID, postID: UUID) -> [BandComment] { [] }
    func createComment(bandID: UUID, postID: UUID, body: String, mentions: [UUID]) -> BandComment {
        BandComment(id: UUID(), postID: postID, authorUserID: userID, authorDisplayName: "Jaylon", parentCommentID: nil, body: body, createdAt: Date(), editedAt: nil, deletedAt: nil)
    }
    func react(bandID: UUID, postID: UUID, reaction: BandReactionKind) {}
    func fetchMembers(bandID: UUID) -> [BandMember] { members }
    func changeMemberRole(bandID: UUID, userID: UUID, role: BandRole) -> BandMember {
        let index = members.firstIndex { $0.userID == userID }!
        let current = members[index]
        let changed = BandMember(userID: current.userID, username: current.username, displayName: current.displayName, role: role, joinedAt: current.joinedAt)
        members[index] = changed
        return changed
    }
    func removeMember(bandID: UUID, userID: UUID) { members.removeAll { $0.userID == userID } }
    func transferOwnership(bandID: UUID, userID: UUID) {
        members = members.map {
            BandMember(
                userID: $0.userID,
                username: $0.username,
                displayName: $0.displayName,
                role: $0.userID == userID ? .owner : ($0.role == .owner ? .admin : $0.role),
                joinedAt: $0.joinedAt
            )
        }
    }
    func createInvitation(bandID: UUID) -> BandInvitation { BandInvitation(id: UUID(), bandID: bandID, url: URL(string: "https://example.com/band/invite/demo")!, expiresAt: Date().addingTimeInterval(604_800), status: "pending") }
    func fetchInvitations(bandID: UUID) -> [BandPendingInvitation] { [] }
    func revokeInvitation(bandID: UUID, invitationID: UUID) {}
    func previewInvitation(token: String) -> BandInvitationPreview {
        BandInvitationPreview(
            bandID: bands.first?.id ?? UUID(),
            bandName: bands.first?.name ?? "Golden Hour",
            inviterDisplayName: "Mia",
            expiresAt: Date().addingTimeInterval(604_800)
        )
    }
    func acceptInvitation(token: String) -> BandSummary {
        if let band = bands.first { return band }
        return createBand(name: "Golden Hour", description: "A private place to make music together.")
    }
    func fetchBlockedUsers() -> [BandUser] { [] }
    func blockUser(_ userID: UUID) {}
    func unblockUser(_ userID: UUID) {}
    func report(bandID: UUID, targetType: String, targetID: UUID, reason: BandReportReason, note: String) -> BandContentReport {
        BandContentReport(id: UUID(), reporterUserID: userID, bandID: bandID, targetType: targetType, targetID: targetID, reason: reason, note: note, status: .open, resolvedByUserID: nil, resolutionNote: nil, createdAt: Date(), resolvedAt: nil)
    }
    func fetchAdminReports() -> [BandContentReport] { [] }
    func resolveReport(reportID: UUID, status: BandReportStatus, note: String, removeContent: Bool, suspendUser: Bool) -> BandContentReport {
        BandContentReport(id: reportID, reporterUserID: userID, bandID: bands.first?.id ?? UUID(), targetType: "post", targetID: UUID(), reason: .other, note: "", status: status, resolvedByUserID: userID, resolutionNote: note, createdAt: Date(), resolvedAt: Date())
    }
    func fetchNotifications() -> [BandNotification] { notifications }
    func markNotificationsRead() { notifications = notifications.map { BandNotification(id: $0.id, bandID: $0.bandID, actorUserID: $0.actorUserID, kind: $0.kind, relatedEntityType: $0.relatedEntityType, relatedEntityID: $0.relatedEntityID, createdAt: $0.createdAt, readAt: Date()) } }

    private func copyPost(
        _ current: BandPost,
        body: String? = nil,
        externalURL: URL? = nil,
        referencedProjectID: UUID? = nil,
        isPinned: Bool? = nil,
        pinnedAt: Date? = nil
    ) -> BandPost {
        BandPost(
            id: current.id,
            bandID: current.bandID,
            projectID: current.projectID,
            referencedProjectID: referencedProjectID ?? current.referencedProjectID,
            authorUserID: current.authorUserID,
            authorDisplayName: current.authorDisplayName,
            body: body ?? current.body,
            externalURL: externalURL ?? current.externalURL,
            cardKind: current.cardKind,
            cardSize: current.cardSize,
            isPinned: isPinned ?? current.isPinned,
            pinnedAt: isPinned == nil ? current.pinnedAt : pinnedAt,
            createdAt: current.createdAt,
            editedAt: body == nil ? current.editedAt : Date(),
            deletedAt: current.deletedAt,
            attachments: current.attachments
        )
    }
}
