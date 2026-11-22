import SwiftUI
import Translation

/// Translates English texts into the iPhone's language once (Apple Translation, iOS 18), then calls `done`
/// with original → translation. English phones, older iOS or a failure → an empty map (English is shown).
struct TextTranslator: ViewModifier {
    let texts: [String]
    let done: ([String: String]) -> Void
    @State private var config: AnyObject?
    @State private var finished = false

    private var needsTranslation: Bool {
        (Locale.current.language.languageCode?.identifier ?? "en") != "en"
    }

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *), needsTranslation {
            content
                .onAppear {
                    config = TranslationSession.Configuration(source: Locale.Language(identifier: "en"),
                                                              target: Locale.current.language) as AnyObject
                    // Don't keep the learner waiting if the language pack isn't there.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 8) { finish([:]) }
                }
                .translationTask(config as? TranslationSession.Configuration) { session in
                    let unique = Array(Set(texts))
                    let requests = unique.map { TranslationSession.Request(sourceText: $0, clientIdentifier: $0) }
                    do {
                        let res = try await session.translations(from: requests)
                        var map: [String: String] = [:]
                        for r in res { if let id = r.clientIdentifier { map[id] = r.targetText } }
                        await MainActor.run { finish(map) }
                    } catch {
                        await MainActor.run { finish([:]) }
                    }
                }
        } else {
            content.onAppear { finish([:]) }
        }
    }

    private func finish(_ map: [String: String]) {
        guard !finished else { return }
        finished = true
        done(map)
    }
}
