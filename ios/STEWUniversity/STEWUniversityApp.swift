import SwiftUI
import SwiftData

@MainActor
@main
struct STEWUniversityApp: App {
    @UIApplicationDelegateAdaptor(STEWAppDelegate.self) private var appDelegate
    @StateObject private var earTrainingProgress: EarTrainingProgressStore
    @StateObject private var gameProgress: GameProgressStore
    @StateObject private var bandAuth: BandAuthSession
    @StateObject private var bandStore: BandStore
    @StateObject private var bandNotifications: BandNotificationStore
    @StateObject private var mediaUploads: MediaUploadManager
    @StateObject private var progressSync: ProgressSyncCoordinator
    private let progressContainer: ModelContainer

    init() {
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-reset-ear-training") {
            UserDefaults.standard.removeObject(forKey: "stew.earTraining.profile.v1")
        }
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-reset-games") {
            UserDefaults.standard.removeObject(forKey: "stew.games.profile.v1")
        }
        let earTrainingProgress = EarTrainingProgressStore()
        let gameProgress = GameProgressStore()
        let bandAuth = AccountSession()
        let schema = Schema([PendingProgressEvent.self, CachedAccountProgress.self])
        let container: ModelContainer
        do {
            container = try ModelContainer(for: schema)
        } catch {
            fatalError("Could not open the progress sync store: \(error.localizedDescription)")
        }
        progressContainer = container
        _earTrainingProgress = StateObject(wrappedValue: earTrainingProgress)
        _gameProgress = StateObject(wrappedValue: gameProgress)
        _bandAuth = StateObject(wrappedValue: bandAuth)
        _bandStore = StateObject(wrappedValue: BandStore())
        _bandNotifications = StateObject(wrappedValue: BandNotificationStore())
        _mediaUploads = StateObject(wrappedValue: MediaUploadManager())
        _progressSync = StateObject(
            wrappedValue: ProgressSyncCoordinator(
                context: ModelContext(container),
                account: bandAuth,
                earTraining: earTrainingProgress,
                games: gameProgress
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            AppShellView()
                .tint(STEWTheme.gold)
                .environmentObject(earTrainingProgress)
                .environmentObject(gameProgress)
                .environmentObject(bandAuth)
                .environmentObject(bandStore)
                .environmentObject(bandNotifications)
                .environmentObject(mediaUploads)
                .environmentObject(progressSync)
                .modelContainer(progressContainer)
        }
    }
}
