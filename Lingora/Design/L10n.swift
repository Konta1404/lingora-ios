import SwiftUI

/// Localized UI string from Localizable.xcstrings (keys are the English text).
func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

/// Localized format string, e.g. L("%lld of %lld done", done, total).
func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: NSLocalizedString(key, comment: ""), locale: Locale.current, arguments: args)
}

/// Text that renders **bold** / _italic_ markdown from an already-localized string.
func MD(_ s: String) -> Text {
    if let a = try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
        return Text(a)
    }
    return Text(s)
}

enum AppLocale {
    /// The user's preferred language as a BCP-47 tag (e.g. "sr-Latn-ME"). Sent to the backend so ChatGPT answers in it.
    static var tag: String { Locale.preferredLanguages.first ?? "en" }

    /// Language name in the user's own language, e.g. "Spanish" → "španski" on a Serbian phone.
    static func languageName(code: String, fallback: String) -> String {
        Locale.current.localizedString(forLanguageCode: code)?.capitalized(with: Locale.current) ?? fallback
    }

    static var isGermanUI: Bool { Locale.current.language.languageCode?.identifier == "de" }
}
