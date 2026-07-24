import AVKit
import AuthenticationServices
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct BandView: View {
    @EnvironmentObject private var auth: BandAuthSession
    @EnvironmentObject private var store: BandStore
    @EnvironmentObject private var notifications: BandNotificationStore
    @State private var showCreateBand = false
    @State private var showJoinBand = false
    @State private var showNotifications = false
    @State private var showSettings = false

    var body: some View {
        Group {
            switch auth.state {
            case .restoring:
                BandLoadingView(message: "Opening your Band space…")
            case .signedOut:
                BandAccountRequiredView()
            case let .needsProfile(user):
                BandProfileSetupView(user: user)
            case let .signedIn(user):
                signedInContent(user: user)
            case let .failed(message):
                BandFailureView(message: message) { auth.retryAfterFailure() }
            }
        }
        .task { await auth.restore() }
        .onChange(of: auth.currentUser?.id) { _, userID in
            guard let userID else { store.clear(); return }
            Task {
                await store.load(userID: userID)
                await notifications.load()
            }
        }
        .onAppear {
            if let user = auth.currentUser {
                Task {
                    await store.load(userID: user.id)
                    await notifications.load()
                }
            }
        }
        .sheet(isPresented: $showCreateBand) { BandCreateView() }
        .sheet(isPresented: $showJoinBand) { BandJoinView() }
        .sheet(isPresented: $showNotifications) { BandNotificationsView() }
        .sheet(isPresented: $showSettings) { BandSettingsView() }
        .sheet(
            isPresented: Binding(
                get: { store.pendingInvitationToken != nil },
                set: { if !$0 { store.pendingInvitationToken = nil } }
            )
        ) {
            if let token = store.pendingInvitationToken { BandInvitationAcceptanceView(token: token) }
        }
    }

    @ViewBuilder
    private func signedInContent(user: BandUser) -> some View {
        if store.isLoading && store.bands.isEmpty {
            BandLoadingView(message: "Loading your Bands…")
        } else if let error = store.errorMessage, store.bands.isEmpty {
            BandFailureView(message: error) { Task { await store.load(userID: user.id, force: true) } }
        } else if store.bands.isEmpty {
            BandWelcomeView(
                create: { showCreateBand = true },
                join: { showJoinBand = true }
            )
        } else {
            BandWorkspaceView(
                showCreateBand: $showCreateBand,
                showJoinBand: $showJoinBand,
                showNotifications: $showNotifications,
                showSettings: $showSettings
            )
        }
    }
}

struct BandAccountRequiredView: View {
    @EnvironmentObject private var auth: BandAuthSession

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 60)
                Image(systemName: "person.3.sequence.fill")
                    .font(.system(size: 54, weight: .light))
                    .foregroundStyle(STEWTheme.gold)
                    .accessibilityHidden(true)
                VStack(spacing: 10) {
                    Text("Make music together")
                        .font(.largeTitle.weight(.medium))
                        .multilineTextAlignment(.center)
                    Text("Band is a private space for sharing song ideas, project takes, feedback, and inspiration with people you trust.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                SignInWithAppleButton(.continue) { request in
                    auth.configureAppleSignIn(request)
                } onCompletion: { result in
                    Task { await auth.completeAppleSignIn(result) }
                }
                .signInWithAppleButtonStyle(.black)
                .frame(maxWidth: .infinity, minHeight: 50, maxHeight: 50)
                .disabled(auth.isWorking)
                .accessibilityIdentifier("band-sign-in-with-apple")
                if auth.isWorking {
                    ProgressView("Signing in…")
                        .accessibilityIdentifier("band-sign-in-progress")
                }
                Text("A STEW Account syncs completed learning and game progress across your devices and unlocks Band. You can still play locally as a guest.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .adaptiveContentWidth(560)
        }
        .accessibilityIdentifier("band-account-required")
    }
}

struct BandProfileSetupView: View {
    @EnvironmentObject private var auth: BandAuthSession
    let user: BandUser?
    @State private var username = ""
    @State private var displayName = ""
    @State private var birthYear = Calendar.current.component(.year, from: .now) - 18
    @State private var acceptsTerms = false

    var body: some View {
        Form {
            Section {
                Text("One quick setup")
                    .font(.title.weight(.medium))
                Text("Choose how your bandmates will see you. Your birth year is used only to confirm that you are 13 or older and is not stored.")
                    .foregroundStyle(.secondary)
            }
            Section("Profile") {
                TextField("username", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityHint("3 to 30 lowercase letters, numbers, or underscores")
                TextField("Display name", text: $displayName)
                Picker("Birth year", selection: $birthYear) {
                    ForEach((1900...Calendar.current.component(.year, from: .now)).reversed(), id: \.self) {
                        Text(String($0)).tag($0)
                    }
                }
            }
            Section {
                Toggle("I accept the Terms and Privacy Policy", isOn: $acceptsTerms)
                if let user {
                    Link("Read Terms", destination: user.termsURL)
                    Link("Read Privacy Policy", destination: user.privacyURL)
                }
            }
            Section {
                Button("Finish setup") {
                    Task {
                        await auth.completeProfile(
                            username: username,
                            displayName: displayName,
                            birthYear: birthYear,
                            acceptsTerms: acceptsTerms
                        )
                    }
                }
                .disabled(username.count < 3 || displayName.isEmpty || !acceptsTerms || auth.isWorking)
            }
        }
        .adaptiveFormWidth()
        .onAppear { displayName = user?.displayName ?? "" }
        .accessibilityIdentifier("band-profile-setup")
    }
}

private struct BandWelcomeView: View {
    let create: () -> Void
    let join: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Spacer(minLength: 52)
                ZStack {
                    Circle().fill(STEWTheme.gold.opacity(0.14)).frame(width: 116, height: 116)
                    Image(systemName: "music.note.house.fill")
                        .font(.system(size: 46, weight: .light))
                        .foregroundStyle(STEWTheme.gold)
                }
                Text("Make music together")
                    .font(.largeTitle.weight(.medium))
                    .multilineTextAlignment(.center)
                Text("Create a private Band for your projects, or join bandmates with a single-use invitation.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                VStack(spacing: 12) {
                    Button("Create Band", action: create)
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                    Button("Join with Invite", action: join)
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(28)
            .adaptiveContentWidth(560)
        }
        .accessibilityIdentifier("band-welcome")
    }
}

private struct BandWorkspaceView: View {
    @EnvironmentObject private var store: BandStore
    @EnvironmentObject private var notifications: BandNotificationStore
    @Binding var showCreateBand: Bool
    @Binding var showJoinBand: Bool
    @Binding var showNotifications: Bool
    @Binding var showSettings: Bool

    var body: some View {
        let accent = store.selectedBand?.accentTheme ?? BandAccentTheme(hex: nil)
        VStack(spacing: 0) {
            HStack {
                Menu {
                    ForEach(store.bands) { band in
                        Button {
                            Task { await store.selectBand(band.id) }
                        } label: {
                            Label(band.name, systemImage: band.id == store.selectedBandID ? "checkmark" : "person.3")
                        }
                    }
                    Divider()
                    Button("Create another Band", systemImage: "plus") { showCreateBand = true }
                    Button("Join with Invite", systemImage: "link") { showJoinBand = true }
                } label: {
                    HStack(spacing: 8) {
                        BandLogoView(
                            assetID: store.selectedBand?.imageAssetID,
                            name: store.selectedBand?.name ?? "Band",
                            accent: accent,
                            size: 46
                        )
                        Text(store.selectedBand?.name ?? "Choose Band")
                            .font(.title2.weight(.medium))
                            .lineLimit(1)
                            .foregroundStyle(.primary)
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(accent.color)
                    }
                }
                Spacer()
                Button { showNotifications = true } label: {
                    Image(systemName: notifications.unreadCount > 0 ? "bell.badge.fill" : "bell")
                        .frame(width: 38, height: 38)
                        .foregroundStyle(accent.color)
                }
                .accessibilityLabel(notifications.unreadCount > 0 ? "Notifications, \(notifications.unreadCount) unread" : "Notifications")
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape")
                        .frame(width: 38, height: 38)
                        .foregroundStyle(accent.color)
                }
                .accessibilityLabel("Band settings")
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)

            BandPageIndicator(selection: store.selectedTab, accent: accent)
                .padding(.horizontal, 18)
                .padding(.bottom, 10)

            TabView(selection: $store.selectedTab) {
                BandHomeView()
                    .tag(BandWorkspaceTab.home)
                    .accessibilityIdentifier("band-home-page")

                BandProjectsView()
                    .tag(BandWorkspaceTab.projects)
                    .accessibilityIdentifier("band-projects-page")

                BandMembersView()
                    .tag(BandWorkspaceTab.members)
                    .accessibilityIdentifier("band-members-page")
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .accessibilityLabel("Band sections")
            .accessibilityHint("Swipe left or right to move between Home, Projects, and Members")
        }
        .tint(accent.color)
        .adaptiveContentWidth()
        .navigationDestination(for: BandRoute.self) { route in
            switch route {
            case let .post(post): BandPostDetailView(post: post)
            case let .project(project): BandProjectDetailView(project: project)
            }
        }
        .overlay {
            if store.isLoading { ProgressView().controlSize(.large).padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18)) }
        }
        .accessibilityIdentifier("band-workspace")
    }
}

private struct BandLogoView: View {
    let assetID: UUID?
    let name: String
    let accent: BandAccentTheme
    let size: CGFloat

    var body: some View {
        Group {
            if let assetID {
                BandAssetPlayerView(assetID: assetID, kind: .image)
            } else {
                RoundedRectangle(cornerRadius: size * 0.24)
                    .fill(accent.color)
                    .overlay {
                        Text(String(name.prefix(1)).uppercased())
                            .font(.system(size: size * 0.42, weight: .semibold))
                            .foregroundStyle(accent.onAccent)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24))
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.24)
                .stroke(accent.color.opacity(0.5), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name) Band logo")
    }
}

private struct BandPageIndicator: View {
    let selection: BandWorkspaceTab
    let accent: BandAccentTheme

    private var pageNumber: Int {
        (BandWorkspaceTab.allCases.firstIndex(of: selection) ?? 0) + 1
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: selection.systemImage)
            Text(selection.rawValue)
                .fontWeight(.semibold)
            Text("\(pageNumber) of \(BandWorkspaceTab.allCases.count)")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(accent.softColor, in: Capsule())
        .overlay {
            Capsule()
                .stroke(accent.color.opacity(0.72), lineWidth: 1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(selection.rawValue), page \(pageNumber) of \(BandWorkspaceTab.allCases.count)")
        .accessibilityIdentifier("band-section-indicator")
    }
}

private struct BandHomeView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var store: BandStore
    @State private var composing = false

    var body: some View {
        let accent = store.selectedBand?.accentTheme ?? BandAccentTheme(hex: nil)
        ScrollView {
            VStack(spacing: 14) {
                if let errorMessage = store.errorMessage {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "wifi.exclamationmark")
                            .foregroundStyle(accent.color)
                        Text(errorMessage)
                            .font(.footnote)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button("Retry") { Task { await store.refresh() } }
                            .font(.footnote.weight(.semibold))
                    }
                    .padding(14)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
                }
                if let featured = store.featuredProject {
                    NavigationLink(value: BandRoute.project(featured)) {
                        BandFeaturedProjectCard(project: featured, accent: accent)
                    }
                    .buttonStyle(.plain)
                }

                Button { composing = true } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Add to Board")
                        Spacer()
                    }
                    .font(.headline)
                    .foregroundStyle(accent.onAccent)
                    .padding(16)
                    .background(accent.color, in: RoundedRectangle(cornerRadius: 18))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("band-add-to-board")

                if store.posts.isEmpty {
                    ContentUnavailableView(
                        "Build your Band’s world",
                        systemImage: "rectangle.3.group.bubble",
                        description: Text("Add an image, note, link, or project to shape the mood together.")
                    )
                    .padding(.top, 32)
                } else {
                    BandMoodBoardLayout(
                        spacing: 12,
                        columns: moodBoardColumns
                    ) {
                        ForEach(store.posts) { post in
                            BandMoodBoardItem(post: post, accent: accent)
                                .layoutValue(key: BandCardSizeLayoutKey.self, value: post.cardSize)
                        }
                    }
                }
            }
            .padding(18)
        }
        .refreshable { await store.refresh() }
        .sheet(isPresented: $composing) { BandBoardComposer() }
    }

    private var moodBoardColumns: Int {
        if dynamicTypeSize.isAccessibilitySize { return 1 }
        return horizontalSizeClass == .regular ? 3 : 2
    }
}

private struct BandFeaturedProjectCard: View {
    let project: BandProject
    let accent: BandAccentTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Featured project", systemImage: "star.fill")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(project.status.title)
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(accent.color)
            Text(project.title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)
            if !project.description.isEmpty {
                Text(project.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack(spacing: 14) {
                if let key = project.musicalKey, !key.isEmpty {
                    Label(key, systemImage: "music.quarternote.3")
                }
                if let bpm = project.bpm {
                    Label("\(bpm) BPM", systemImage: "metronome")
                }
                Spacer()
                Image(systemName: "arrow.right.circle.fill")
                    .font(.title3)
                    .foregroundStyle(accent.color)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(accent.softColor, in: RoundedRectangle(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(accent.color.opacity(0.62), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("band-featured-project")
    }
}

private struct BandMoodBoardItem: View {
    @EnvironmentObject private var auth: BandAuthSession
    @EnvironmentObject private var store: BandStore
    let post: BandPost
    let accent: BandAccentTheme
    @State private var editing = false
    @State private var reporting = false
    @State private var confirmingDelete = false

    private var isAuthor: Bool { auth.currentUser?.id == post.authorUserID }
    private var canManage: Bool { store.selectedBand?.role?.canManageAppearance == true }

    var body: some View {
        NavigationLink(value: BandRoute.post(post)) {
            BandMoodBoardCard(post: post, accent: accent)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if isAuthor {
                Button("Edit card", systemImage: "pencil") { editing = true }
            }
            if canManage {
                Button(
                    post.isPinned ? "Unpin card" : "Pin card",
                    systemImage: post.isPinned ? "pin.slash" : "pin.fill"
                ) {
                    Task { _ = await store.setPinned(post, isPinned: !post.isPinned) }
                }
            }
            if !isAuthor {
                Button("Report card", systemImage: "exclamationmark.bubble") { reporting = true }
            }
            if isAuthor || canManage {
                Button("Remove card", systemImage: "trash", role: .destructive) {
                    confirmingDelete = true
                }
            }
        }
        .sheet(isPresented: $editing) { BandBoardComposer(editing: post) }
        .sheet(isPresented: $reporting) {
            BandReportView(targetType: "post", targetID: post.id)
        }
        .confirmationDialog("Remove this board card?", isPresented: $confirmingDelete) {
            Button("Remove", role: .destructive) {
                Task { _ = await store.deletePost(post) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

private struct BandMoodBoardCard: View {
    @EnvironmentObject private var store: BandStore
    let post: BandPost
    let accent: BandAccentTheme

    private var minimumHeight: CGFloat {
        switch post.cardSize {
        case .compact: 154
        case .tall: 292
        case .wide: 184
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                BandAvatar(name: post.authorDisplayName, size: 28)
                Text(post.authorDisplayName ?? "Band member")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if post.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption)
                        .foregroundStyle(accent.color)
                        .accessibilityLabel("Pinned")
                }
            }

            cardContent

            Spacer(minLength: 0)
            HStack(spacing: 12) {
                Image(systemName: "heart")
                Image(systemName: "bubble.left")
                Spacer()
                Text(post.createdAt, style: .relative)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: minimumHeight, alignment: .topLeading)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(
                    post.isPinned ? accent.color.opacity(0.75) : Color(.separator).opacity(0.45),
                    lineWidth: post.isPinned ? 1.2 : 0.5
                )
        }
        .foregroundStyle(.primary)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("band-board-card-\(post.cardKind.rawValue)")
    }

    @ViewBuilder private var cardContent: some View {
        switch post.cardKind {
        case .note:
            Image(systemName: "quote.opening")
                .font(.title3)
                .foregroundStyle(accent.color)
            Text(post.body)
                .font(.body.weight(.medium))
                .lineLimit(6)
        case .image:
            if let first = post.attachments.first {
                BandAssetPlayerView(assetID: first.id, kind: .image)
                    .frame(height: post.cardSize == .tall ? 190 : 128)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(alignment: .bottomTrailing) {
                        if post.attachments.count > 1 {
                            Text("+\(post.attachments.count - 1)")
                                .font(.caption.weight(.bold))
                                .padding(7)
                                .background(.regularMaterial, in: Circle())
                                .padding(7)
                        }
                    }
            } else {
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        LinearGradient(
                            colors: [accent.color.opacity(0.88), accent.color.opacity(0.24)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 170)
                    .overlay {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.largeTitle)
                            .foregroundStyle(accent.onAccent.opacity(0.9))
                    }
            }
            if !post.body.isEmpty {
                Text(post.body).font(.subheadline).lineLimit(3)
            }
        case .link:
            Image(systemName: "link.circle.fill")
                .font(.title)
                .foregroundStyle(accent.color)
            Text(post.externalURL?.host ?? "Reference link")
                .font(.headline)
                .lineLimit(2)
            if !post.body.isEmpty {
                Text(post.body).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            }
        case .project:
            Image(systemName: "music.note.list")
                .font(.title2)
                .foregroundStyle(accent.color)
            if let project = store.project(post.referencedProjectID) {
                Text(project.title).font(.title3.weight(.semibold))
                Text(project.status.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(accent.color)
                if !post.body.isEmpty {
                    Text(post.body).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
            } else {
                Text("Project unavailable").font(.headline)
            }
        }
    }

    private var cardBackground: Color {
        post.cardKind == .note ? accent.softColor : Color(.secondarySystemBackground)
    }
}

private struct BandCardSizeLayoutKey: LayoutValueKey {
    static let defaultValue: BandCardSize = .compact
}

private struct BandMoodBoardLayout: Layout {
    let spacing: CGFloat
    let columns: Int

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) -> CGSize {
        let width = proposal.width ?? 360
        let result = placements(width: width, subviews: subviews)
        return CGSize(width: width, height: result.height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) {
        let result = placements(width: bounds.width, subviews: subviews)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: frame.width, height: frame.height)
            )
        }
    }

    private func placements(width: CGFloat, subviews: Subviews) -> (frames: [CGRect], height: CGFloat) {
        let resolvedColumns = max(1, columns)
        let columnWidth = resolvedColumns == 1
            ? width
            : max(0, (width - spacing * CGFloat(resolvedColumns - 1)) / CGFloat(resolvedColumns))
        var columnY = Array(repeating: CGFloat.zero, count: resolvedColumns)
        var frames: [CGRect] = []

        for subview in subviews {
            let cardSize = subview[BandCardSizeLayoutKey.self]
            if resolvedColumns == 1 || cardSize == .wide {
                let y = columnY.max() ?? 0
                let measured = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
                let frame = CGRect(x: 0, y: y, width: width, height: measured.height)
                frames.append(frame)
                let nextY = frame.maxY + spacing
                columnY = Array(repeating: nextY, count: resolvedColumns)
            } else {
                let column = columnY.indices.min(by: { columnY[$0] < columnY[$1] }) ?? 0
                let measured = subview.sizeThatFits(
                    ProposedViewSize(width: columnWidth, height: nil)
                )
                let frame = CGRect(
                    x: CGFloat(column) * (columnWidth + spacing),
                    y: columnY[column],
                    width: columnWidth,
                    height: measured.height
                )
                frames.append(frame)
                columnY[column] = frame.maxY + spacing
            }
        }
        return (frames, max(columnY.max() ?? 0, 0) - (frames.isEmpty ? 0 : spacing))
    }
}

private struct BandPostCard: View {
    @EnvironmentObject private var store: BandStore
    let post: BandPost

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                BandAvatar(name: post.authorDisplayName)
                VStack(alignment: .leading, spacing: 2) {
                    Text(post.authorDisplayName ?? "Band member").font(.headline)
                    Text(post.createdAt, style: .relative).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            if post.deletedAt != nil {
                Text("This post was removed.").italic().foregroundStyle(.secondary)
            } else {
                Text(post.body).frame(maxWidth: .infinity, alignment: .leading)
                if let url = post.externalURL {
                    Link(destination: url) {
                        Label(url.host ?? url.absoluteString, systemImage: "link")
                            .font(.subheadline)
                            .lineLimit(1)
                    }
                }
                if let project = store.project(post.referencedProjectID) {
                    NavigationLink(value: BandRoute.project(project)) {
                        Label(project.title, systemImage: "music.note.list")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                if !post.attachments.isEmpty {
                    BandAttachmentGrid(assets: post.attachments)
                }
            }
            HStack(spacing: 18) {
                Label("React", systemImage: "heart")
                Label("Comment", systemImage: "bubble.left")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .stewSurface()
        .accessibilityElement(children: .contain)
    }
}

private struct BandBoardComposer: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: BandStore
    @EnvironmentObject private var uploads: MediaUploadManager
    let editing: BandPost?
    @State private var selectedKind: BandCardKind?
    @State private var bodyText: String
    @State private var link: String
    @State private var selectedProjectID: UUID?
    @State private var photos: [PhotosPickerItem] = []
    @State private var isSending = false
    @State private var errorMessage: String?

    init(editing: BandPost? = nil) {
        self.editing = editing
        _selectedKind = State(initialValue: editing?.cardKind)
        _bodyText = State(initialValue: editing?.body ?? "")
        _link = State(initialValue: editing?.externalURL?.absoluteString ?? "")
        _selectedProjectID = State(initialValue: editing?.referencedProjectID)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let selectedKind {
                    editor(for: selectedKind)
                    if editing == nil {
                        Section {
                            Button("Choose a different card type", systemImage: "chevron.left") {
                                self.selectedKind = nil
                                errorMessage = nil
                            }
                        }
                    }
                } else {
                    Section("Choose a card type") {
                        ForEach(BandCardKind.allCases) { kind in
                            Button {
                                selectedKind = kind
                            } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: kind.symbol)
                                        .font(.title2)
                                        .frame(width: 34)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(kind.title).font(.headline)
                                        Text(cardDescription(kind))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .foregroundStyle(.primary)
                                .padding(.vertical, 5)
                            }
                            .accessibilityIdentifier("band-card-type-\(kind.rawValue)")
                        }
                    }
                }
                if isSending { Section { ProgressView("Preparing and uploading…") } }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
                Section {
                    Text("Audio and video are shared inside song projects so every take stays organized.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .adaptiveFormWidth()
            .navigationTitle(editing == nil ? "Add to Board" : "Edit card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                if selectedKind != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(editing == nil ? "Add" : "Save") { Task { await send() } }
                            .disabled(!canSend)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func editor(for kind: BandCardKind) -> some View {
        switch kind {
        case .note:
            Section("Note") {
                TextEditor(text: $bodyText)
                    .frame(minHeight: 150)
                    .accessibilityLabel("Board note")
            }
        case .image:
            let photoSelectionLabel = photos.isEmpty
                ? "Choose one to four images"
                : "\(photos.count) image(s) selected"
            Section("Image") {
                if editing == nil {
                    PhotosPicker(selection: $photos, maxSelectionCount: 4, matching: .images) {
                        Label(photoSelectionLabel, systemImage: "photo.on.rectangle")
                    }
                } else {
                    Label("Images can’t be replaced after posting", systemImage: "lock")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                TextField("Optional caption", text: $bodyText, axis: .vertical)
            }
        case .link:
            Section("Reference link") {
                TextField("https://example.com", text: $link)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .accessibilityIdentifier("band-board-link")
                TextField("Optional caption", text: $bodyText, axis: .vertical)
                Text("STEW displays the site name but does not fetch a link preview.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .project:
            Section("Band project") {
                if store.projects.isEmpty {
                    Label("Create a project before adding a project card", systemImage: "music.note.list")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Project", selection: $selectedProjectID) {
                        Text("Choose a project").tag(Optional<UUID>.none)
                        ForEach(store.projects.filter { !$0.isArchived }) { project in
                            Text(project.title).tag(Optional(project.id))
                        }
                    }
                }
                TextField("Optional caption", text: $bodyText, axis: .vertical)
            }
        }
    }

    private var canSend: Bool {
        guard !isSending, let selectedKind else { return false }
        switch selectedKind {
        case .note:
            return !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .image:
            return editing != nil || !photos.isEmpty
        case .link:
            return isValidWebLink(link)
        case .project:
            return selectedProjectID != nil
        }
    }

    private func cardDescription(_ kind: BandCardKind) -> String {
        switch kind {
        case .note: "Lyrics, quotes, and creative direction"
        case .image: "Photos, artwork, and visual references"
        case .link: "A web reference with an optional caption"
        case .project: "Bring an active Band project onto the board"
        }
    }

    private func isValidWebLink(_ value: String) -> Bool {
        guard let components = URLComponents(string: value.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return false
        }
        return ["http", "https"].contains(components.scheme?.lowercased() ?? "")
            && components.host?.isEmpty == false
    }

    private func send() async {
        guard let bandID = store.selectedBandID, let selectedKind else { return }
        isSending = true
        defer { isSending = false }
        do {
            var assetIDs: [UUID] = []
            if editing == nil && selectedKind == .image {
                for item in photos {
                    guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                    let fileURL = try BandImagePreparation.temporaryJPEG(
                        from: data, maximumPixelSize: 2_400
                    )
                    defer { try? FileManager.default.removeItem(at: fileURL) }
                    guard let transferID = await uploads.enqueue(
                        fileURL: fileURL,
                        bandID: bandID,
                        projectID: nil,
                        kind: .image,
                        contentType: "image/jpeg"
                    ) else { throw BandAPIError.transport("A photo could not be prepared.") }
                    assetIDs.append(try await uploads.waitUntilReady(transferID))
                }
            }
            let draft = BandDraftPost(
                cardKind: selectedKind,
                body: bodyText,
                externalURL: link,
                referencedProjectID: selectedProjectID,
                mentionedUserIDs: []
            )
            let succeeded: Bool
            if let editing {
                succeeded = await store.updatePost(editing, draft: draft)
            } else {
                succeeded = await store.createPost(draft, assetIDs: assetIDs)
            }
            if succeeded { dismiss() }
            else { errorMessage = store.errorMessage }
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct BandPostDetailView: View {
    @EnvironmentObject private var store: BandStore
    let post: BandPost
    @State private var comments: [BandComment] = []
    @State private var comment = ""
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var reporting = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                BandPostCard(post: post)
                HStack {
                    ForEach(BandReactionKind.allCases) { reaction in
                        Button {
                            Task { try? await store.react(to: post.id, with: reaction) }
                        } label: {
                            Image(systemName: reaction.symbol).frame(width: 38, height: 38)
                        }
                        .accessibilityLabel(reaction.title)
                    }
                    Spacer()
                }
                .padding(.horizontal, 4)
                Divider()
                if isLoading { ProgressView() }
                else if comments.isEmpty { Text("No comments yet.").foregroundStyle(.secondary).frame(maxWidth: .infinity) }
                ForEach(comments) { item in
                    HStack(alignment: .top, spacing: 10) {
                        BandAvatar(name: item.authorDisplayName, size: 32)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.authorDisplayName ?? "Band member").font(.subheadline.weight(.semibold))
                            Text(item.deletedAt == nil ? item.body : "This comment was removed.")
                            Text(item.createdAt, style: .relative).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .stewSurface()
                }
                HStack(alignment: .bottom) {
                    TextField("Add a comment", text: $comment, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                    Button("Send") { Task { await sendComment() } }
                        .disabled(comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if let errorMessage { Text(errorMessage).font(.footnote).foregroundStyle(.red) }
            }
            .padding(18)
        }
        .navigationTitle("Post")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadComments() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Report post", systemImage: "exclamationmark.bubble", role: .destructive) { reporting = true }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .sheet(isPresented: $reporting) { BandReportView(targetType: "post", targetID: post.id) }
    }

    private func loadComments() async {
        do { comments = try await store.comments(for: post.id) }
        catch { errorMessage = error.localizedDescription }
        isLoading = false
    }

    private func sendComment() async {
        do {
            comments.append(try await store.addComment(to: post.id, body: comment))
            comment = ""
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct BandProjectsView: View {
    @EnvironmentObject private var store: BandStore
    @State private var creating = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                Button { creating = true } label: {
                    Label("New song project", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                if store.projects.isEmpty {
                    ContentUnavailableView(
                        "No projects yet",
                        systemImage: "music.note.list",
                        description: Text("Create a project to organize tracks and versioned takes.")
                    ).padding(.top, 28)
                } else {
                    ForEach(store.projects) { project in
                        NavigationLink(value: BandRoute.project(project)) {
                            BandProjectCard(project: project)
                        }.buttonStyle(.plain)
                    }
                }
            }.padding(18)
                .adaptiveContentWidth(900)
        }
        .refreshable { await store.refresh() }
        .sheet(isPresented: $creating) { BandCreateProjectView() }
    }
}

private struct BandProjectCard: View {
    let project: BandProject
    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 14)
                .fill(STEWTheme.gold.opacity(0.14))
                .frame(width: 62, height: 62)
                .overlay { Image(systemName: "music.note").font(.title2).foregroundStyle(STEWTheme.gold) }
            VStack(alignment: .leading, spacing: 5) {
                HStack { Text(project.title).font(.headline); Spacer(); BandStatusPill(status: project.status) }
                Text(project.description.isEmpty ? "No description" : project.description)
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                HStack(spacing: 12) {
                    if let musicalKey = project.musicalKey { Label(musicalKey, systemImage: "music.quarternote.3") }
                    if let bpm = project.bpm { Text("\(bpm) BPM") }
                    if let time = project.timeSignature { Text(time) }
                }.font(.caption).foregroundStyle(.secondary)
            }
        }
        .stewSurface()
    }
}

private struct BandCreateProjectView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: BandStore
    @State private var draft = BandDraftProject()

    var body: some View {
        NavigationStack {
            Form {
                Section("Song") {
                    TextField("Project title", text: $draft.title)
                    TextField("Description", text: $draft.description, axis: .vertical)
                }
                Section("Musical details") {
                    TextField("Key (optional)", text: $draft.musicalKey)
                    TextField("BPM (optional)", value: $draft.bpm, format: .number).keyboardType(.numberPad)
                    TextField("Time signature", text: $draft.timeSignature)
                    Picker("Status", selection: $draft.status) {
                        ForEach(BandProjectStatus.allCases) { Text($0.title).tag($0) }
                    }
                }
            }
            .adaptiveFormWidth()
            .navigationTitle("New project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { Task { if await store.createProject(draft) { dismiss() } } }
                        .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct BandProjectDetailView: View {
    @EnvironmentObject private var store: BandStore
    let project: BandProject
    @State private var tracks: [BandTrack] = []
    @State private var creatingTrack = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                BandProjectCard(project: project)
                HStack {
                    Text("Tracks").font(.title2.weight(.medium))
                    Spacer()
                    Button("Add track", systemImage: "plus") { creatingTrack = true }
                }
                if tracks.isEmpty {
                    ContentUnavailableView(
                        "No tracks yet",
                        systemImage: "waveform",
                        description: Text("Add Lead Vocal, Guitar, Drums, Keys, or a custom part.")
                    )
                } else {
                    ForEach(tracks) { track in
                        NavigationLink {
                            BandTrackDetailView(project: project, track: track)
                        } label: {
                            HStack {
                                Image(systemName: track.partKind.symbol).foregroundStyle(STEWTheme.gold).frame(width: 30)
                                VStack(alignment: .leading) {
                                    Text(track.name).font(.headline)
                                    Text(track.partTitle).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(); Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }.stewSurface()
                        }.buttonStyle(.plain)
                    }
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            }
            .padding(18)
            .adaptiveContentWidth(900, alignment: .leading)
        }
        .navigationTitle(project.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .sheet(isPresented: $creatingTrack) {
            BandCreateTrackView(project: project) { tracks.append($0) }
        }
    }

    private func reload() async {
        do { tracks = try await store.tracks(for: project.id) }
        catch { errorMessage = error.localizedDescription }
    }
}

private struct BandCreateTrackView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: BandStore
    let project: BandProject
    let created: (BandTrack) -> Void
    @State private var name = ""
    @State private var part: BandPartKind = .vocals
    @State private var customLabel = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Track name, e.g. Lead Vocal", text: $name)
                Picker("Part", selection: $part) {
                    ForEach(BandPartKind.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                }
                if part == .other { TextField("Custom part", text: $customLabel) }
            }
            .adaptiveFormWidth()
            .navigationTitle("Add track")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Task {
                            if let track = try? await store.createTrack(
                                projectID: project.id,
                                name: name,
                                part: part,
                                customLabel: part == .other ? customLabel : nil
                            ) { created(track); dismiss() }
                        }
                    }.disabled(name.isEmpty || (part == .other && customLabel.isEmpty))
                }
            }
        }
    }
}

private struct BandTrackDetailView: View {
    @EnvironmentObject private var store: BandStore
    @EnvironmentObject private var uploads: MediaUploadManager
    let project: BandProject
    let track: BandTrack
    @State private var takes: [BandTake] = []
    @State private var importing = false
    @State private var notes = ""
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                Label(track.partTitle, systemImage: track.partKind.symbol)
                if takes.isEmpty { Text("No takes yet. Add the first audio or video version.").foregroundStyle(.secondary) }
                ForEach(takes) { take in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Take \(take.takeNumber)").font(.headline)
                        if !take.notes.isEmpty { Text(take.notes).font(.subheadline).foregroundStyle(.secondary) }
                        BandAssetPlayerView(assetID: take.assetID, kind: .audio)
                    }
                }
            }
            Section("New take") {
                TextField("Notes (optional)", text: $notes, axis: .vertical)
                Button("Choose audio or video file", systemImage: "square.and.arrow.up") { importing = true }
            }
            let active = uploads.transfers.filter { $0.projectID == project.id && $0.phase != .ready }
            if !active.isEmpty {
                Section("Uploads") { ForEach(active) { BandUploadRow(transfer: $0) } }
            }
            if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
        }
        .navigationTitle(track.name)
        .task {
            do { takes = try await store.takes(for: track.id) }
            catch { errorMessage = error.localizedDescription }
        }
        .fileImporter(
            isPresented: $importing,
            allowedContentTypes: [.audio, .movie, .mpeg4Movie, .quickTimeMovie],
            allowsMultipleSelection: false
        ) { result in
            guard case let .success(urls) = result, let url = urls.first else { return }
            Task { await upload(url) }
        }
    }

    private func upload(_ sourceURL: URL) async {
        guard let bandID = store.selectedBandID else { return }
        let scoped = sourceURL.startAccessingSecurityScopedResource()
        defer { if scoped { sourceURL.stopAccessingSecurityScopedResource() } }
        let isVideo = ["mp4", "mov"].contains(sourceURL.pathExtension.lowercased())
        let contentType = Self.contentType(for: sourceURL)
        guard let transferID = await uploads.enqueue(
            fileURL: sourceURL,
            bandID: bandID,
            projectID: project.id,
            kind: isVideo ? .video : .audio,
            contentType: contentType
        ) else { return }
        do {
            let assetID = try await uploads.waitUntilReady(transferID)
            let take = try await store.createTake(
                trackID: track.id,
                assetID: assetID,
                takeNumber: (takes.map(\.takeNumber).max() ?? 0) + 1,
                notes: notes
            )
            takes.append(take)
            notes = ""
        } catch { errorMessage = error.localizedDescription }
    }

    private static func contentType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "m4a": "audio/mp4"
        case "mp3": "audio/mpeg"
        case "wav": "audio/wav"
        case "aac": "audio/aac"
        case "caf": "audio/x-caf"
        case "mp4": "video/mp4"
        case "mov": "video/quicktime"
        default: "application/octet-stream"
        }
    }
}

private struct BandMembersView: View {
    @EnvironmentObject private var store: BandStore
    @EnvironmentObject private var auth: BandAuthSession
    @State private var showingInvite = false
    @State private var reportingMember: BandMember?
    @State private var actionError: String?

    var body: some View {
        List {
            Section {
                Button("Invite a bandmate", systemImage: "person.badge.plus") { showingInvite = true }
            }
            Section("\(store.members.count) members") {
                ForEach(store.members) { member in
                    HStack(spacing: 12) {
                        BandAvatar(name: member.displayName)
                        VStack(alignment: .leading) {
                            Text(member.displayName ?? member.username ?? "Band member").font(.headline)
                            if let username = member.username { Text("@\(username)").font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        Text(member.role.title)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(STEWTheme.gold.opacity(member.role == .owner ? 0.18 : 0.08), in: Capsule())
                        if member.userID != auth.currentUser?.id {
                            memberMenu(member)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            if let actionError { Section { Text(actionError).foregroundStyle(.red) } }
        }
        .adaptiveContentWidth(900)
        .refreshable { await store.refresh() }
        .sheet(isPresented: $showingInvite) { BandInviteShareView() }
        .sheet(item: $reportingMember) { member in
            BandReportView(targetType: "user", targetID: member.userID)
        }
    }

    @ViewBuilder
    private func memberMenu(_ member: BandMember) -> some View {
        let actorRole = store.selectedBand?.role ?? .member
        Menu {
            if actorRole == .owner, member.role != .owner {
                if member.role == .admin {
                    Button("Make member", systemImage: "person") { perform { try await store.changeRole(for: member.userID, to: .member) } }
                } else {
                    Button("Make admin", systemImage: "person.badge.key") { perform { try await store.changeRole(for: member.userID, to: .admin) } }
                }
                Button("Transfer ownership", systemImage: "crown") { perform { try await store.transferOwnership(to: member.userID) } }
            }
            if (actorRole == .owner && member.role != .owner) || (actorRole == .admin && member.role == .member) {
                Button("Remove from Band", systemImage: "person.badge.minus", role: .destructive) {
                    perform { try await store.removeMember(member.userID) }
                }
            }
            Divider()
            Button("Block user", systemImage: "person.crop.circle.badge.xmark") {
                perform { try await store.provider.blockUser(member.userID) }
            }
            Button("Report user", systemImage: "exclamationmark.bubble", role: .destructive) {
                reportingMember = member
            }
        } label: {
            Image(systemName: "ellipsis.circle").frame(width: 36, height: 36)
        }
        .accessibilityLabel("Actions for \(member.displayName ?? member.username ?? "member")")
    }

    private func perform(_ action: @escaping @MainActor () async throws -> Void) {
        Task {
            do { try await action(); actionError = nil }
            catch { actionError = error.localizedDescription }
        }
    }
}

private struct BandInviteShareView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: BandStore
    @State private var invitation: BandInvitation?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "person.badge.plus").font(.system(size: 48)).foregroundStyle(STEWTheme.gold)
                Text("Invite one bandmate").font(.title2.weight(.medium))
                Text("This private link works once and expires after seven days.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
                if let invitation {
                    ShareLink(item: invitation.url) {
                        Label("Share invitation", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }.buttonStyle(.borderedProminent)
                    Text(invitation.url.absoluteString).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                } else if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                    Button("Try again") { Task { await create() } }
                } else { ProgressView("Creating secure invitation…") }
                Spacer()
            }
            .padding(24)
            .navigationTitle("Invite")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await create() }
        }
    }
    private func create() async {
        do { invitation = try await store.createInvitation() }
        catch { errorMessage = error.localizedDescription }
    }
}

private struct BandJoinView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: BandStore
    @State private var invite = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Invitation link") {
                    TextField("Paste invitation link or token", text: $invite)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Section {
                    Button("Review invitation") {
                        store.pendingInvitationToken = token
                        dismiss()
                    }.disabled(token.isEmpty)
                }
            }
            .adaptiveFormWidth()
            .navigationTitle("Join a Band")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
    private var token: String {
        let trimmed = invite.trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(string: trimmed)?.lastPathComponent ?? trimmed
    }
}

private struct BandInvitationAcceptanceView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: BandStore
    let token: String
    @State private var preview: BandInvitationPreview?
    @State private var errorMessage: String?
    @State private var accepting = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Image(systemName: "person.3.fill").font(.system(size: 48)).foregroundStyle(STEWTheme.gold)
                if let preview {
                    Text("Join \(preview.bandName)?").font(.title.weight(.medium)).multilineTextAlignment(.center)
                    Text("\(preview.inviterDisplayName) invited you to collaborate privately.")
                        .foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button(accepting ? "Joining…" : "Join Band") {
                        accepting = true
                        Task {
                            do { try await store.acceptInvitation(token: token); dismiss() }
                            catch { errorMessage = error.localizedDescription; accepting = false }
                        }
                    }.buttonStyle(.borderedProminent).disabled(accepting)
                } else if let errorMessage {
                    ContentUnavailableView("Invitation unavailable", systemImage: "link.badge.plus", description: Text(errorMessage))
                } else { ProgressView("Checking invitation…") }
                Spacer()
            }
            .padding(24)
            .navigationTitle("Band invitation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .task {
                do { preview = try await store.invitationPreview(token: token) }
                catch { errorMessage = error.localizedDescription }
            }
        }
    }
}

private struct BandCreateView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: BandStore
    @State private var name = ""
    @State private var description = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Band details") {
                    TextField("Band name", text: $name)
                    TextField("What are you making together?", text: $description, axis: .vertical)
                }
                Section {
                    Text("Bands are private. You decide who joins through single-use invitation links.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .adaptiveFormWidth()
            .navigationTitle("Create Band")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { Task { if await store.createBand(name: name, description: description) { dismiss() } } }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct BandNotificationsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var notifications: BandNotificationStore

    var body: some View {
        NavigationStack {
            List {
                if notifications.notifications.isEmpty {
                    ContentUnavailableView("You’re all caught up", systemImage: "bell")
                }
                ForEach(notifications.notifications) { item in
                    HStack(alignment: .top, spacing: 12) {
                        Circle().fill(item.readAt == nil ? STEWTheme.gold : Color.secondary.opacity(0.2)).frame(width: 9, height: 9).padding(.top, 7)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.kind.title).font(.headline)
                            Text(item.createdAt, style: .relative).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Notifications")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Mark all read") { Task { await notifications.markAllRead() } } }
            }
            .task { await notifications.load() }
        }
    }
}

private struct BandSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: BandAuthSession
    @EnvironmentObject private var store: BandStore
    @EnvironmentObject private var uploads: MediaUploadManager
    @ObservedObject private var push = BandPushManager.shared
    @State private var showDeleteConfirmation = false
    @State private var showAppearanceSettings = false
    @State private var accountError: String?

    var body: some View {
        NavigationStack {
            List {
                if let band = store.selectedBand {
                    Section("Band") {
                        LabeledContent("Name", value: band.name)
                        LabeledContent("Your role", value: band.role?.title ?? "Member")
                        LabeledContent("Members", value: String(band.memberCount ?? store.members.count))
                        ProgressView(value: Double(band.usedBytes + band.reservedBytes), total: Double(2 * 1024 * 1024 * 1024)) {
                            Text("Media storage")
                        } currentValueLabel: {
                            Text(ByteCountFormatter.string(fromByteCount: band.usedBytes + band.reservedBytes, countStyle: .file))
                        }
                    }
                    if band.role?.canManageAppearance == true {
                        Section("Appearance") {
                            Button {
                                showAppearanceSettings = true
                            } label: {
                                Label("Logo, color, and featured project", systemImage: "paintpalette")
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("band-appearance-settings-link")
                        }
                    }
                }
                if !uploads.transfers.isEmpty {
                    Section("Media uploads") { ForEach(uploads.transfers) { BandUploadRow(transfer: $0) } }
                }
                Section("Safety and privacy") {
                    NavigationLink("Pending invitations") { BandPendingInvitationsView() }
                    NavigationLink("Blocked users") { BandBlockedUsersView() }
                    if auth.currentUser?.isPlatformAdmin == true {
                        NavigationLink("Platform safety review") { BandSafetyQueueView() }
                    }
                    if let user = auth.currentUser {
                        Link("Privacy Policy", destination: user.privacyURL)
                        Link("Terms of Use", destination: user.termsURL)
                        Link("Support and safety contact", destination: user.supportURL)
                    }
                }
                Section("Notifications") {
                    if push.authorizationStatus == .authorized || push.authorizationStatus == .provisional {
                        Label("Push notifications enabled", systemImage: "bell.badge.fill")
                    } else {
                        Button("Enable push notifications", systemImage: "bell.badge") {
                            Task { await push.requestAuthorization() }
                        }
                    }
                    Text("Push uses generic text and routing IDs only. Media and message content stay out of the notification payload.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Account") {
                    Button("Sign out") { Task { store.clear(); await auth.logout(); dismiss() } }
                    Button("Delete account", role: .destructive) { showDeleteConfirmation = true }
                    if let accountError { Text(accountError).foregroundStyle(.red).font(.footnote) }
                }
            }
            .navigationTitle("Band settings")
            .navigationDestination(isPresented: $showAppearanceSettings) {
                BandAppearanceSettingsView()
            }
            .task { await push.refreshStatus() }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .alert("Delete your account?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Continue with Apple", role: .destructive) {
                    Task {
                        do { try await auth.deleteAccount(); store.clear(); dismiss() }
                        catch { accountError = error.localizedDescription }
                    }
                }
            } message: {
                Text("Owners must transfer or delete every owned Band first. Deletion removes your shared content and media permanently.")
            }
        }
    }
}

private struct BandAppearanceSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: BandStore
    @EnvironmentObject private var uploads: MediaUploadManager
    @State private var accentColor = BandAccentTheme(hex: nil).color
    @State private var logoAssetID: UUID?
    @State private var featuredProjectID: UUID?
    @State private var selectedLogo: PhotosPickerItem?
    @State private var initialized = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        let preview = BandAccentTheme(hex: BandAccentTheme.hex(from: accentColor))
        let logoSelectionLabel = selectedLogo == nil ? "Choose logo" : "New logo selected"
        Form {
            Section("Preview") {
                HStack(spacing: 14) {
                    BandLogoView(
                        assetID: logoAssetID,
                        name: store.selectedBand?.name ?? "Band",
                        accent: preview,
                        size: 64
                    )
                    VStack(alignment: .leading, spacing: 5) {
                        Text(store.selectedBand?.name ?? "Band")
                            .font(.title3.weight(.semibold))
                        Text("Your Band’s private creative space")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Accent color") {
                ColorPicker("Band color", selection: $accentColor, supportsOpacity: false)
                Button("Reset to STEW gold", systemImage: "arrow.counterclockwise") {
                    accentColor = BandAccentTheme(hex: nil).color
                }
                Text("The app automatically chooses readable foreground colors in light and dark mode.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Band logo") {
                PhotosPicker(selection: $selectedLogo, matching: .images) {
                    Label(logoSelectionLabel, systemImage: "photo.badge.plus")
                }
                if logoAssetID != nil || selectedLogo != nil {
                    Button("Remove logo", role: .destructive) {
                        logoAssetID = nil
                        selectedLogo = nil
                    }
                }
                Text("Logos are normalized to a high-quality square-friendly JPEG and shown with rounded corners.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Featured project") {
                Picker("Project", selection: $featuredProjectID) {
                    Text("None").tag(Optional<UUID>.none)
                    ForEach(store.projects.filter { !$0.isArchived }) { project in
                        Text(project.title).tag(Optional(project.id))
                    }
                }
                Text("The featured project appears as a full-width card above the mood board.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if isSaving { Section { ProgressView("Saving Band appearance…") } }
            if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
        }
        .adaptiveFormWidth()
        .navigationTitle("Band appearance")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("band-appearance-settings")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save() } }
                    .disabled(isSaving)
            }
        }
        .task {
            guard !initialized, let band = store.selectedBand else { return }
            initialized = true
            accentColor = band.accentTheme.color
            logoAssetID = band.imageAssetID
            featuredProjectID = band.featuredProjectID
        }
    }

    private func save() async {
        guard let bandID = store.selectedBandID else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            var resolvedLogoID = logoAssetID
            if let selectedLogo {
                guard let data = try await selectedLogo.loadTransferable(type: Data.self) else {
                    throw BandImagePreparationError.unreadableImage
                }
                let url = try BandImagePreparation.temporaryJPEG(
                    from: data, maximumPixelSize: 1_024
                )
                defer { try? FileManager.default.removeItem(at: url) }
                guard let transferID = await uploads.enqueue(
                    fileURL: url,
                    bandID: bandID,
                    projectID: nil,
                    kind: .image,
                    contentType: "image/jpeg"
                ) else {
                    throw BandAPIError.transport("The Band logo could not be prepared.")
                }
                resolvedLogoID = try await uploads.waitUntilReady(transferID)
            }
            let succeeded = await store.updateAppearance(
                logoAssetID: resolvedLogoID,
                accentColorHex: BandAccentTheme.hex(from: accentColor),
                featuredProjectID: featuredProjectID
            )
            if succeeded { dismiss() }
            else { errorMessage = store.errorMessage }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct BandBlockedUsersView: View {
    @EnvironmentObject private var store: BandStore
    @State private var users: [BandUser] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    var body: some View {
        List {
            if isLoading { ProgressView() }
            if !isLoading && users.isEmpty {
                ContentUnavailableView(
                    "No blocked users",
                    systemImage: "person.crop.circle.badge.xmark",
                    description: Text("People you block are hidden from your feed and cannot mention or react to you.")
                )
            }
            ForEach(users) { user in
                HStack {
                    BandAvatar(name: user.displayName)
                    VStack(alignment: .leading) {
                        Text(user.displayName ?? "Band member")
                        if let username = user.username { Text("@\(username)").font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    Button("Unblock") {
                        Task {
                            do { try await store.provider.unblockUser(user.id); users.removeAll { $0.id == user.id } }
                            catch { errorMessage = error.localizedDescription }
                        }
                    }.buttonStyle(.bordered)
                }
            }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
        }
        .navigationTitle("Blocked users")
        .task {
            do { users = try await store.provider.fetchBlockedUsers() }
            catch { errorMessage = error.localizedDescription }
            isLoading = false
        }
    }
}

private struct BandSafetyQueueView: View {
    @EnvironmentObject private var store: BandStore
    @State private var reports: [BandContentReport] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    var body: some View {
        List {
            if isLoading { ProgressView() }
            if !isLoading && reports.isEmpty {
                ContentUnavailableView(
                    "No open reports",
                    systemImage: "checkmark.shield",
                    description: Text("Platform-admin reports that need review appear here.")
                )
            }
            ForEach(reports) { report in
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Text(report.reason.title).font(.headline); Spacer(); Text(report.targetType.capitalized).font(.caption).foregroundStyle(.secondary) }
                    if !report.note.isEmpty { Text(report.note).font(.subheadline) }
                    Text(report.createdAt, style: .relative).font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Dismiss") { resolve(report, status: .dismissed, remove: false, suspend: false) }
                        Button("Remove") { resolve(report, status: .resolved, remove: true, suspend: false) }
                        Button("Remove + suspend", role: .destructive) { resolve(report, status: .resolved, remove: true, suspend: true) }
                    }.font(.caption)
                }.padding(.vertical, 4)
            }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
        }
        .navigationTitle("Safety review")
        .task { await load() }
    }
    private func load() async {
        do { reports = try await store.provider.fetchAdminReports() }
        catch { errorMessage = error.localizedDescription }
        isLoading = false
    }
    private func resolve(_ report: BandContentReport, status: BandReportStatus, remove: Bool, suspend: Bool) {
        Task {
            do {
                _ = try await store.provider.resolveReport(reportID: report.id, status: status, note: "Reviewed in the iOS safety queue.", removeContent: remove, suspendUser: suspend)
                reports.removeAll { $0.id == report.id }
            } catch { errorMessage = error.localizedDescription }
        }
    }
}

private struct BandPendingInvitationsView: View {
    @EnvironmentObject private var store: BandStore
    @State private var invitations: [BandPendingInvitation] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    var body: some View {
        List {
            if isLoading { ProgressView() }
            if !isLoading && invitations.isEmpty {
                ContentUnavailableView("No pending invitations", systemImage: "envelope.open")
            }
            ForEach(invitations) { invitation in
                HStack {
                    VStack(alignment: .leading) {
                        Text("Single-use invitation")
                        Text("Expires \(invitation.expiresAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Revoke", role: .destructive) {
                        Task {
                            do { try await store.revokeInvitation(invitation.id); invitations.removeAll { $0.id == invitation.id } }
                            catch { errorMessage = error.localizedDescription }
                        }
                    }
                }
            }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
        }
        .navigationTitle("Pending invitations")
        .task {
            do { invitations = try await store.pendingInvitations() }
            catch { errorMessage = error.localizedDescription }
            isLoading = false
        }
    }
}

private struct BandReportView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: BandStore
    let targetType: String
    let targetID: UUID
    @State private var reason: BandReportReason = .harassment
    @State private var note = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    var body: some View {
        NavigationStack {
            Form {
                Picker("Reason", selection: $reason) {
                    ForEach(BandReportReason.allCases) { Text($0.title).tag($0) }
                }
                TextField("Optional details", text: $note, axis: .vertical)
                Text("Reports are visible only to the platform safety team.")
                    .font(.footnote).foregroundStyle(.secondary)
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            }
            .adaptiveFormWidth()
            .navigationTitle("Report \(targetType)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        Task {
                            guard let bandID = store.selectedBandID else { return }
                            isSending = true
                            do {
                                _ = try await store.provider.report(bandID: bandID, targetType: targetType, targetID: targetID, reason: reason, note: note)
                                dismiss()
                            } catch { errorMessage = error.localizedDescription; isSending = false }
                        }
                    }.disabled(isSending)
                }
            }
        }
    }
}

private struct BandAttachmentGrid: View {
    let assets: [BandAsset]
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(assets.prefix(4)) { asset in
                BandAssetPlayerView(assetID: asset.id, kind: asset.kind)
                    .frame(minHeight: asset.kind == .image ? 120 : 54)
            }
        }
    }
}

private struct BandAssetPlayerView: View {
    let assetID: UUID
    let kind: BandAssetKind
    @State private var player: AVPlayer?
    @State private var imageURL: URL?
    @State private var failed = false

    var body: some View {
        Group {
            if kind == .image {
                AsyncImage(url: imageURL) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() }
                    else if phase.error != nil || failed { Color.secondary.opacity(0.12).overlay { Image(systemName: "photo") } }
                    else { ProgressView() }
                }.clipShape(RoundedRectangle(cornerRadius: 12))
            } else if kind == .video, let player {
                VideoPlayer(player: player).frame(minHeight: 180).clipShape(RoundedRectangle(cornerRadius: 12))
            } else if let player {
                HStack {
                    Button { player.timeControlStatus == .playing ? player.pause() : player.play() } label: {
                        Image(systemName: player.timeControlStatus == .playing ? "pause.circle.fill" : "play.circle.fill").font(.title)
                    }
                    Text("Authorized Band media").font(.caption).foregroundStyle(.secondary)
                }
            } else if failed {
                Label("Media unavailable", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.secondary)
            } else { ProgressView() }
        }
        .task {
            do {
                let access = try await BandAPIClient.shared.mediaAccess(assetID: assetID)
                if kind == .image { imageURL = access.url }
                else { player = AVPlayer(url: access.url) }
            } catch { failed = true }
        }
        .onDisappear { player?.pause() }
    }
}

private struct BandUploadRow: View {
    @EnvironmentObject private var uploads: MediaUploadManager
    let transfer: BandUploadTransfer
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(transfer.localFileURL.lastPathComponent, systemImage: transfer.kind == .image ? "photo" : "waveform")
                    .font(.subheadline).lineLimit(1)
                Spacer(); Text(transfer.phase.title).font(.caption).foregroundStyle(.secondary)
            }
            if transfer.phase == .uploading { ProgressView(value: transfer.progress) }
            if let failure = transfer.failureMessage { Text(failure).font(.caption).foregroundStyle(.red) }
            if transfer.phase == .failed {
                Button("Retry") { Task { await uploads.retry(transfer.id) } }.font(.caption)
            } else if [.preparing, .uploading, .processing].contains(transfer.phase) {
                Button("Cancel", role: .destructive) { uploads.cancel(transfer.id) }.font(.caption)
            }
        }
    }
}

private struct BandAvatar: View {
    let name: String?
    var size: CGFloat = 40
    var body: some View {
        Circle()
            .fill(STEWTheme.gold.opacity(0.18))
            .frame(width: size, height: size)
            .overlay {
                Text(String((name ?? "B").prefix(1)).uppercased())
                    .font(.system(size: size * 0.38, weight: .semibold)).foregroundStyle(STEWTheme.gold)
            }
            .accessibilityHidden(true)
    }
}

private struct BandStatusPill: View {
    let status: BandProjectStatus
    var body: some View {
        Text(status.title)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(STEWTheme.gold.opacity(0.14), in: Capsule())
    }
}

private struct BandLoadingView: View {
    let message: String
    var body: some View {
        VStack(spacing: 14) { ProgressView(); Text(message).foregroundStyle(.secondary) }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct BandFailureView: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        ContentUnavailableView {
            Label("Band is unavailable", systemImage: "wifi.exclamationmark")
        } description: { Text(message) } actions: { Button("Try again", action: retry).buttonStyle(.borderedProminent) }
    }
}

private enum BandRoute: Hashable {
    case post(BandPost)
    case project(BandProject)
}
