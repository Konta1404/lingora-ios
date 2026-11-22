import Foundation
import UIKit
import AuthenticationServices
import CryptoKit
import FirebaseCore
import FirebaseAuth
import GoogleSignIn

/// Sign in with Apple, Google, OpenAI (OIDC) and email — all through Firebase Auth.
struct AuthResult {
    var uid: String?
    var name: String
    var email: String
    var method: AuthMethod
}

enum AuthError: LocalizedError {
    case notConfigured, missingToken, cancelled, chatGPT(String)
    var errorDescription: String? {
        switch self {
        case .notConfigured: L("The Lingora server isn't set up in this build.")
        case .missingToken: L("Sign-in didn't return a token. Please try again.")
        case .cancelled: L("Sign-in was cancelled.")
        case .chatGPT(let message): message
        }
    }
}

@MainActor
final class AuthService: NSObject {
    static let shared = AuthService()


    private var currentNonce: String?
    private var appleContinuation: CheckedContinuation<ASAuthorization, Error>?

    // MARK: Apple

    /// Configure the native SignInWithAppleButton request (adds a hashed nonce for Firebase).
    func prepare(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonce()
        currentNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)
    }

    func completeApple(_ authorization: ASAuthorization) async throws -> AuthResult {
        guard let cred = authorization.credential as? ASAuthorizationAppleIDCredential else { throw AuthError.missingToken }
        let name = [cred.fullName?.givenName, cred.fullName?.familyName].compactMap { $0 }.joined(separator: " ")
        guard Backend.isConfigured else {
            return AuthResult(uid: nil, name: name, email: cred.email ?? "", method: .apple)
        }
        guard let tokenData = cred.identityToken, let token = String(data: tokenData, encoding: .utf8),
              let nonce = currentNonce else { throw AuthError.missingToken }
        let credential = OAuthProvider.appleCredential(withIDToken: token, rawNonce: nonce, fullName: cred.fullName)
        let result = try await Auth.auth().signIn(with: credential)
        if !name.isEmpty, result.user.displayName == nil {
            let change = result.user.createProfileChangeRequest()
            change.displayName = name
            try? await change.commitChanges()
        }
        return AuthResult(uid: result.user.uid, name: result.user.displayName ?? name,
                          email: result.user.email ?? cred.email ?? "", method: .apple)
    }

    // MARK: Google

    func signInWithGoogle() async throws -> AuthResult {
        guard Backend.isConfigured, !Backend.usesEmulators, let clientID = FirebaseApp.app()?.options.clientID else { throw AuthError.notConfigured }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        guard let root = Self.topViewController() else { throw AuthError.missingToken }
        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: root)
        guard let idToken = result.user.idToken?.tokenString else { throw AuthError.missingToken }
        let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: result.user.accessToken.tokenString)
        let auth = try await Auth.auth().signIn(with: credential)
        return AuthResult(uid: auth.user.uid, name: auth.user.displayName ?? result.user.profile?.name ?? "",
                          email: auth.user.email ?? "", method: .google)
    }

    // MARK: Sign in with ChatGPT

    struct ChatGPTFinish: Decodable { var ok: Bool; var customToken: String?; var name: String?; var email: String? }
    private struct StartResponse: Decodable { var url: String }
    private var webSession: ASWebAuthenticationSession?

    /// Runs the Sign in with ChatGPT flow. Signed-in users link their plan; otherwise ChatGPT becomes their account.
    /// Returns an AuthResult when this created a new sign-in, nil when it linked an existing account.
    func continueWithChatGPT() async throws -> AuthResult? {
        guard Backend.isConfigured else { throw AuthError.notConfigured }
        let start: StartResponse = try await Backend.callAllowingSignedOut("chatgptAuthStart", [:])
        guard let url = URL(string: start.url) else { throw AuthError.missingToken }

        let callback: URL = try await withCheckedThrowingContinuation { cont in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "lingora") { url, error in
                if let url { cont.resume(returning: url) }
                else if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin { cont.resume(throwing: AuthError.cancelled) }
                else { cont.resume(throwing: error ?? AuthError.missingToken) }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            webSession = session
            session.start()
        }
        webSession = nil

        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func item(_ n: String) -> String? { items.first { $0.name == n }?.value }
        switch item("status") {
        case "ok": break
        case "cancelled": throw AuthError.cancelled
        default: throw AuthError.chatGPT(item("message") ?? L("Sign in with ChatGPT didn't finish. Please try again."))
        }

        let finish: ChatGPTFinish = try await Backend.callAllowingSignedOut("chatgptAuthFinish", ["state": item("state") ?? ""])
        guard finish.ok else { throw AuthError.chatGPT(L("Sign in with ChatGPT didn't finish. Please try again.")) }
        guard let token = finish.customToken else { return nil }   // linked to the current account
        let auth = try await Auth.auth().signIn(withCustomToken: token)
        return AuthResult(uid: auth.user.uid, name: finish.name ?? auth.user.displayName ?? "",
                          email: finish.email ?? auth.user.email ?? "", method: .openai)
    }

    // MARK: Email

    func email(name: String, email: String, password: String, createAccount: Bool) async throws -> AuthResult {
        guard Backend.isConfigured else {
            return AuthResult(uid: nil, name: name, email: email, method: .email)
        }
        let result: AuthDataResult
        if createAccount {
            result = try await Auth.auth().createUser(withEmail: email, password: password)
            let change = result.user.createProfileChangeRequest()
            change.displayName = name
            try? await change.commitChanges()
        } else {
            result = try await Auth.auth().signIn(withEmail: email, password: password)
        }
        return AuthResult(uid: result.user.uid, name: createAccount ? name : (result.user.displayName ?? ""),
                          email: result.user.email ?? email, method: .email)
    }

    func sendPasswordReset(to email: String) async throws {
        guard Backend.isConfigured else { throw AuthError.notConfigured }
        try await Auth.auth().sendPasswordReset(withEmail: email)
    }

    func signOut() {
        guard Backend.isConfigured else { return }
        GIDSignIn.sharedInstance.signOut()
        try? Auth.auth().signOut()
    }

    func deleteAccount() async throws {
        guard Backend.isConfigured, let user = Auth.auth().currentUser else { return }
        try await user.delete()
    }

    // MARK: Helpers

    static func message(for error: Error) -> String {
        if let e = error as? AuthError { return e.errorDescription ?? "" }
        let ns = error as NSError
        if ns.domain == AuthErrorDomain, let code = AuthErrorCode(rawValue: ns.code) {
            switch code {
            case .wrongPassword, .invalidCredential, .userNotFound: return L("That email or password isn't right.")
            case .emailAlreadyInUse: return L("An account with this email already exists. Log in instead.")
            case .weakPassword: return L("Use at least 8 characters")
            case .invalidEmail: return L("That email doesn’t look right")
            case .networkError: return L("No connection. Check your internet and try again.")
            default: break
            }
        }
        return error.localizedDescription
    }

    static func isCancellation(_ error: Error) -> Bool {
        if (error as? ASAuthorizationError)?.code == .canceled { return true }
        let ns = error as NSError
        if ns.domain == "com.google.GIDSignIn", ns.code == -5 { return true }
        if ns.domain == AuthErrorDomain, AuthErrorCode(rawValue: ns.code) == .webContextCancelled { return true }
        return false
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var vc = scene?.windows.first { $0.isKeyWindow }?.rootViewController
        while let presented = vc?.presentedViewController { vc = presented }
        return vc
    }

    private static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var generator = SystemRandomNumberGenerator()
        while result.count < length { result.append(charset[Int(generator.next() % UInt64(charset.count))]) }
        return result
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

extension AuthService: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows).first { $0.isKeyWindow } ?? ASPresentationAnchor()
        }
    }
}
