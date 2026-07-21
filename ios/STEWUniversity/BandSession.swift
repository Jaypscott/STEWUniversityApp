import AuthenticationServices
import CryptoKit
import Foundation
import Security
import UIKit

enum BandAuthState: Equatable {
    case restoring
    case signedOut
    case needsProfile(BandUser?)
    case signedIn(BandUser)
    case failed(String)
}

@MainActor
final class BandAuthSession: ObservableObject {
    @Published private(set) var state: BandAuthState
    @Published private(set) var isWorking = false

    let client: BandAPIClient
    private var signInCoordinator: AppleSignInCoordinator?
    private var revocationObserver: NSObjectProtocol?
    private var pendingSignInNonce: String?
    private let arguments: [String]

    init(client: BandAPIClient = .shared, arguments: [String] = ProcessInfo.processInfo.arguments) {
        self.client = client
        self.arguments = arguments
        if arguments.contains("--ui-testing-band-demo") || arguments.contains("--ui-testing-band-empty") {
            state = .signedIn(Self.demoUser)
        } else if arguments.contains("--ui-testing-band-signed-out") {
            state = .signedOut
        } else {
            state = .restoring
        }
        revocationObserver = NotificationCenter.default.addObserver(
            forName: ASAuthorizationAppleIDProvider.credentialRevokedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.logout() }
        }
    }

    func restore() async {
        guard state == .restoring else { return }
        if arguments.contains("--ui-testing-band-demo") || arguments.contains("--ui-testing-band-empty") {
            state = .signedIn(Self.demoUser)
            return
        }
        do {
            let user = try await client.restoreSession()
            state = user.profileComplete ? .signedIn(user) : .needsProfile(user)
        }
        catch { state = .signedOut }
    }

    func signIn() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false; signInCoordinator = nil }
        do {
            let coordinator = AppleSignInCoordinator()
            signInCoordinator = coordinator
            let result = try await coordinator.authorize()
            try await authenticate(result)
        } catch let error as ASAuthorizationError where error.code == .canceled {
            state = .signedOut
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func configureAppleSignIn(_ request: ASAuthorizationAppleIDRequest) {
        guard !isWorking else { return }
        isWorking = true
        let nonce = Self.randomNonce()
        pendingSignInNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.hashedNonce(nonce)
    }

    func completeAppleSignIn(_ result: Result<ASAuthorization, Error>) async {
        defer { isWorking = false; pendingSignInNonce = nil }
        do {
            let authorization = try result.get()
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let codeData = credential.authorizationCode,
                  let identityToken = String(data: tokenData, encoding: .utf8),
                  let authorizationCode = String(data: codeData, encoding: .utf8),
                  let nonce = pendingSignInNonce else {
                throw BandAPIError.invalidResponse
            }
            let formatter = PersonNameComponentsFormatter()
            let displayName = credential.fullName.map { formatter.string(from: $0) }
            try await authenticate(
                AppleAuthorizationResult(
                    identityToken: identityToken,
                    authorizationCode: authorizationCode,
                    rawNonce: nonce,
                    displayName: displayName?.isEmpty == false ? displayName : nil
                )
            )
        } catch let error as ASAuthorizationError where error.code == .canceled {
            state = .signedOut
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func completeProfile(
        username: String,
        displayName: String,
        birthYear: Int,
        acceptsTerms: Bool
    ) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            state = .signedIn(
                try await client.completeProfile(
                    username: username,
                    displayName: displayName,
                    birthYear: birthYear,
                    acceptsTerms: acceptsTerms
                )
            )
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func logout() async {
        await client.logout()
        state = .signedOut
    }

    func deleteAccount() async throws {
        let coordinator = AppleSignInCoordinator()
        signInCoordinator = coordinator
        let result = try await coordinator.authorize()
        try await client.deleteAccount(
            identityToken: result.identityToken,
            authorizationCode: result.authorizationCode,
            nonce: result.rawNonce
        )
        signInCoordinator = nil
        state = .signedOut
    }

    func retryAfterFailure() {
        state = .restoring
        Task { await restore() }
    }

    var currentUser: BandUser? {
        if case let .signedIn(user) = state { return user }
        return nil
    }

    private func authenticate(_ result: AppleAuthorizationResult) async throws {
        let tokens = try await client.authenticateWithApple(
            identityToken: result.identityToken,
            authorizationCode: result.authorizationCode,
            nonce: result.rawNonce,
            displayName: result.displayName
        )
        if tokens.profileRequired {
            state = .needsProfile(try? await client.currentUser())
        } else {
            state = .signedIn(try await client.currentUser())
        }
    }

    private static func hashedNonce(_ nonce: String) -> String {
        SHA256.hash(data: Data(nonce.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func randomNonce(length: Int = 32) -> String {
        let characters = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var bytes = [UInt8](repeating: 0, count: length)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            return UUID().uuidString
        }
        return String(bytes.map { characters[Int($0) % characters.count] })
    }

    nonisolated static let demoUser = BandUser(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        username: "jaylon",
        displayName: "Jaylon",
        isPlatformAdmin: true,
        profileComplete: true,
        termsURL: URL(string: "https://example.com/terms")!,
        privacyURL: URL(string: "https://example.com/privacy")!,
        supportURL: URL(string: "https://example.com/support")!
    )
}

private struct AppleAuthorizationResult {
    let identityToken: String
    let authorizationCode: String
    let rawNonce: String
    let displayName: String?
}

private final class AppleSignInCoordinator: NSObject,
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding
{
    private var continuation: CheckedContinuation<AppleAuthorizationResult, Error>?
    private var rawNonce = ""
    private var controller: ASAuthorizationController?

    @MainActor
    func authorize() async throws -> AppleAuthorizationResult {
        rawNonce = Self.randomNonce()
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = SHA256.hash(data: Data(rawNonce.utf8)).map { String(format: "%02x", $0) }.joined()
        let controller = ASAuthorizationController(authorizationRequests: [request])
        self.controller = controller
        controller.delegate = self
        controller.presentationContextProvider = self
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            controller.performRequests()
        }
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let codeData = credential.authorizationCode,
              let identityToken = String(data: tokenData, encoding: .utf8),
              let authorizationCode = String(data: codeData, encoding: .utf8) else {
            continuation?.resume(throwing: BandAPIError.invalidResponse)
            continuation = nil
            return
        }
        let formatter = PersonNameComponentsFormatter()
        let name = credential.fullName.map { formatter.string(from: $0) }
        continuation?.resume(
            returning: AppleAuthorizationResult(
                identityToken: identityToken,
                authorizationCode: authorizationCode,
                rawNonce: rawNonce,
                displayName: name?.isEmpty == false ? name : nil
            )
        )
        continuation = nil
        self.controller = nil
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        continuation?.resume(throwing: error)
        continuation = nil
        self.controller = nil
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) {
            return window
        }
        guard let scene = scenes.first else {
            preconditionFailure("Sign in with Apple requires an active window scene.")
        }
        return ASPresentationAnchor(windowScene: scene)
    }

    private static func randomNonce(length: Int = 32) -> String {
        let characters = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var bytes = [UInt8](repeating: 0, count: length)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            return UUID().uuidString
        }
        return String(bytes.map { characters[Int($0) % characters.count] })
    }
}
