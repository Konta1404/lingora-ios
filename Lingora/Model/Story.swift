import Foundation

/// A short dialogue read by two voices, with comprehension questions between the lines.
struct Story: Codable, Identifiable, Hashable {
    struct Line: Codable, Hashable {
        var s: String?          // speaker
        var t: String?          // text in the language
        var en: String?         // meaning
        var q: String?          // question (English)
        var options: [String]?
        var a: Int?
        var isQuestion: Bool { q != nil }
    }
    var id: String
    var title: String
    var level: String
    var unit: String?           // unlocks after this unit's first lesson
    var speakers: [String: String]   // name → "f" / "m"
    var lines: [Line]

    /// Every English text, for translation into the app's language.
    var englishTexts: [String] {
        [title] + lines.flatMap { [$0.en, $0.q].compactMap { $0 } + ($0.options ?? []) }
    }
}

enum StoryLibrary {
    private static var cache: [String: [Story]] = [:]
    static func stories(_ lang: String) -> [Story] {
        if let c = cache[lang] { return c }
        guard let url = Bundle.main.url(forResource: "stories_\(lang)", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([Story].self, from: data) else { return [] }
        cache[lang] = list
        return list
    }
}

/// How well a course word is known: Leitner box 0…5 and the day it's due again.
struct WordMemory: Codable, Hashable {
    var box = 0
    var due = ""
    var seen = 0
    var wrong = 0
}
