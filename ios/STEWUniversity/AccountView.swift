import SwiftUI

struct AccountView: View {
    @EnvironmentObject private var account: AccountSession
    @EnvironmentObject private var progress: ProgressSyncCoordinator
    @State private var showDeleteConfirmation = false
    @State private var accountError: String?

    var body: some View {
        Group {
            switch account.state {
            case .restoring:
                ProgressView("Restoring your STEW Account…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .signedOut:
                BandAccountRequiredView()
            case let .needsProfile(user):
                BandProfileSetupView(user: user)
            case let .signedIn(user):
                signedInView(user)
            case let .failed(message):
                ContentUnavailableView(
                    "Account unavailable",
                    systemImage: "person.crop.circle.badge.exclamationmark",
                    description: Text(message)
                )
            }
        }
        .task { await account.restore() }
        .alert("Delete STEW Account?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Account", role: .destructive) {
                Task {
                    do { try await account.deleteAccount() }
                    catch { accountError = error.localizedDescription }
                }
            }
        } message: {
            Text("This removes synced learning progress, game statistics, Band data, and account access. This cannot be undone.")
        }
        .alert(
            "Account action failed",
            isPresented: Binding(
                get: { accountError != nil },
                set: { if !$0 { accountError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: { Text(accountError ?? "Please try again.") }
    }

    private func signedInView(_ user: BandUser) -> some View {
        Form {
            Section("STEW Account") {
                LabeledContent("Name", value: user.displayName ?? "Musician")
                LabeledContent("Username", value: user.username.map { "@\($0)" } ?? "Not set")
            }

            Section("Progress sync") {
                Label(progress.status.title, systemImage: syncSymbol)
                    .foregroundStyle(progress.status == .attention ? .orange : .primary)
                LabeledContent("Pending activity", value: "\(progress.pendingActivityCount)")
                if let date = progress.lastSuccessfulSync {
                    LabeledContent("Last synced") {
                        Text(date, style: .relative)
                    }
                }
                if let snapshot = progress.latestSnapshot {
                    LabeledContent("Account XP", value: "\(snapshot.account.xp)")
                    LabeledContent("Level", value: snapshot.account.levelTitle)
                    LabeledContent("Account time zone", value: snapshot.preferences.timeZone)
                }
                if let message = progress.errorMessage {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
                Button("Sync now") { Task { await progress.synchronize() } }
                    .disabled(progress.status == .syncing)
                Button("Use this device’s time zone") {
                    Task { await progress.updateTimeZoneToCurrent() }
                }
            }

            Section("Privacy and support") {
                Link("Privacy Policy", destination: user.privacyURL)
                Link("Terms of Use", destination: user.termsURL)
                Link("Support", destination: user.supportURL)
            }

            Section {
                Button("Sign out") { Task { await account.logout() } }
                Button("Delete account", role: .destructive) { showDeleteConfirmation = true }
            }
        }
        .adaptiveFormWidth()
        .refreshable { await progress.synchronize() }
        .accessibilityIdentifier("stew-account-screen")
    }

    private var syncSymbol: String {
        switch progress.status {
        case .guest: "iphone"
        case .idle: "checkmark.icloud"
        case .syncing: "arrow.triangle.2.circlepath.icloud"
        case .offline: "icloud.slash"
        case .attention: "exclamationmark.icloud"
        }
    }
}

struct ProgressImportChoiceView: View {
    @EnvironmentObject private var progress: ProgressSyncCoordinator

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: "arrow.triangle.2.circlepath.icloud.fill")
                        .font(.system(size: 54, weight: .light))
                        .foregroundStyle(STEWTheme.gold)
                    VStack(spacing: 10) {
                        Text("Choose your account progress")
                            .font(.largeTitle.weight(.medium))
                            .multilineTextAlignment(.center)
                        Text("This choice can be made once. Use your iPhone as the primary device if it contains the progress you want to keep.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    VStack(spacing: 12) {
                        Button("Use progress from this device") {
                            Task { await progress.chooseDeviceProgress() }
                        }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                        Button("Use account progress") {
                            Task { await progress.chooseAccountProgress() }
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                    }
                    Text("Other devices will adopt the selected account snapshot. Guest progress remains independent on each device when signed out.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    if let message = progress.errorMessage {
                        Text(message).font(.footnote).foregroundStyle(.red)
                    }
                }
                .padding(24)
                .adaptiveContentWidth(560)
            }
            .navigationTitle("Progress Sync")
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled()
        .accessibilityIdentifier("progress-import-choice")
    }
}
