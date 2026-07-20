import SwiftUI

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

    init() {
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-reset-ear-training") {
            UserDefaults.standard.removeObject(forKey: "stew.earTraining.profile.v1")
        }
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-reset-games") {
            UserDefaults.standard.removeObject(forKey: "stew.games.profile.v1")
        }
        _earTrainingProgress = StateObject(wrappedValue: EarTrainingProgressStore())
        _gameProgress = StateObject(wrappedValue: GameProgressStore())
        _bandAuth = StateObject(wrappedValue: BandAuthSession())
        _bandStore = StateObject(wrappedValue: BandStore())
        _bandNotifications = StateObject(wrappedValue: BandNotificationStore())
        _mediaUploads = StateObject(wrappedValue: MediaUploadManager())
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
        }
    }
}
