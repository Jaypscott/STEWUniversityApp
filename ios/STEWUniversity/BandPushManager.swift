import UIKit
import UserNotifications

extension Notification.Name {
    static let bandNotificationRoute = Notification.Name("BandNotificationRoute")
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
            let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            if allowed { UIApplication.shared.registerForRemoteNotifications() }
            await refreshStatus()
        } catch { await refreshStatus() }
    }

    func registerCachedTokenIfAvailable() async {
        guard let token = UserDefaults.standard.string(forKey: tokenKey) else { return }
        try? await BandAPIClient.shared.registerDevice(token: token, environment: environment)
    }

    func receivedDeviceToken(_ data: Data) {
        let token = data.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(token, forKey: tokenKey)
        Task { try? await BandAPIClient.shared.registerDevice(token: token, environment: environment) }
    }

    private var environment: String {
        #if DEBUG
        "sandbox"
        #else
        "production"
        #endif
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
