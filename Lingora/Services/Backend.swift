import Foundation
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

/// Firebase wiring. The app also runs without Firebase (no GoogleService-Info.plist): accounts stay on the
/// device and ChatGPT features fall back to built-in content.
enum Backend {
    static let region = "europe-west1"

    private(set) static var isConfigured = false

    static func configure() {
        guard !isConfigured,
              Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else { return }
        FirebaseApp.configure()
        isConfigured = true
    }

    static var currentUID: String? { isConfigured ? Auth.auth().currentUser?.uid : nil }

    /// Calls a Cloud Function and decodes its JSON result.
    static func call<T: Decodable>(_ name: String, _ payload: [String: Any]) async throws -> T {
        guard isConfigured else { throw BackendError.notConfigured }
        guard Auth.auth().currentUser != nil else { throw BackendError.signedOut }
        let result = try await Functions.functions(region: region).httpsCallable(name).call(payload)
        let data = try JSONSerialization.data(withJSONObject: result.data, options: [.fragmentsAllowed])
        return try JSONDecoder().decode(T.self, from: data)
    }

    enum BackendError: LocalizedError {
        case notConfigured, signedOut
        var errorDescription: String? {
            switch self {
            case .notConfigured: L("The Lingora server isn't set up in this build.")
            case .signedOut: L("Sign in to use ChatGPT features.")
            }
        }
    }

    static func message(for error: Error) -> String {
        let ns = error as NSError
        if ns.domain == FunctionsErrorDomain, let msg = ns.userInfo[NSLocalizedDescriptionKey] as? String { return msg }
        return error.localizedDescription
    }
}

/// Keeps the user's state in Firestore so it follows them across devices.
enum CloudSync {
    private static var db: Firestore { Firestore.firestore() }

    static func load(uid: String) async -> (state: PersistedState?, vocab: VocabProgressStore?) {
        guard Backend.isConfigured else { return (nil, nil) }
        do {
            async let userDoc = db.collection("users").document(uid).getDocument()
            async let vocabDoc = db.collection("users").document(uid).collection("data").document("vocab").getDocument()
            let (u, v) = try await (userDoc, vocabDoc)
            let state = (u.get("state") as? String).flatMap { try? JSONDecoder().decode(PersistedState.self, from: Data($0.utf8)) }
            let vocab = (v.get("progress") as? String).flatMap { try? JSONDecoder().decode(VocabProgressStore.self, from: Data($0.utf8)) }
            return (state, vocab)
        } catch {
            return (nil, nil)
        }
    }

    static func save(state: PersistedState, uid: String) {
        guard Backend.isConfigured, let data = try? JSONEncoder().encode(state),
              let json = String(data: data, encoding: .utf8) else { return }
        db.collection("users").document(uid).setData([
            "state": json,
            "name": state.user?.name ?? "",
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
    }

    static func save(vocab: VocabProgressStore, uid: String) {
        var slim = vocab
        slim.translations = [:]   // the translation cache lives server-side; only progress is synced
        guard Backend.isConfigured, let data = try? JSONEncoder().encode(slim),
              let json = String(data: data, encoding: .utf8) else { return }
        db.collection("users").document(uid).collection("data").document("vocab").setData([
            "progress": json,
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
    }
}
