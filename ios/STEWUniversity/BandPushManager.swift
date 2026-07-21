import UIKit
import UserNotifications

extension Notification.Name {
    static let bandNotificationRoute = Notification.Name("BandNotificationRoute")
    static let progressInvalidated = Notification.Name("ProgressInvalidated")
}

@MainActor
final class ProgressPushRefreshHandler {
    static let shared = ProgressPushRefreshHandler()
    var refresh: (() async -> Void)?

    func handle() async { await refresh?() }
}

@MainActor
final class BandPushManager: NSObject, ObservableObject {
    static let shared = BandPushManager()
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    private let tokenKey = "stew.band.device-token"

    func refreshStatus() async {
        authorizationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func requestAuthorization() async {
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            UIApplication.shared.registerForRemoteNotifications()
            await refreshStatus()
        } catch { await refreshStatus() }
    }

    func registerForBackgroundUpdates() async {
        UIApplication.shared.registerForRemoteNotifications()
        await refreshStatus()
    }

    func registerCachedTokenIfAvailable() async {
        guard let token = UserDefaults.standard.string(forKey: tokenKey) else { return }
        try? await BandAPIClient.shared.registerDevice(
            token: token,
            installationID: AppInstallation.identifier,
            environment: environment,
            enabled: alertsEnabled
        )
    }

    func receivedDeviceToken(_ data: Data) {
        let token = data.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(token, forKey: tokenKey)
        Task {
            await refreshStatus()
            try? await BandAPIClient.shared.registerDevice(
                token: token,
                installationID: AppInstallation.identifier,
                environment: environment,
                enabled: alertsEnabled
            )
        }
    }

    private var environment: String {
        #if DEBUG
        "sandbox"
        #else
        "production"
        #endif
    }

    private var alertsEnabled: Bool {
        [.authorized, .provisional, .ephemeral].contains(authorizationStatus)
    }
}

final class STEWAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in BandPushManager.shared.receivedDeviceToken(deviceToken) }
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        guard userInfo["kind"] as? String == "progress_updated" else {
            completionHandler(.noData)
            return
        }
        NotificationCenter.default.post(name: .progressInvalidated, object: nil)
        Task { @MainActor in
            await ProgressPushRefreshHandler.shared.handle()
            completionHandler(.newData)
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        NotificationCenter.default.post(name: .bandNotificationRoute, object: nil)
    }
}
