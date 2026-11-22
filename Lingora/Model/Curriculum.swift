import Foundation

/// The CEFR topic list (A1–C2) every language follows: level → category → topic.
/// Each topic becomes a course unit; built-in content fills some, ChatGPT writes the rest on demand.
struct Curriculum: Decodable {
    struct Name: Decodable, Hashable { var sr: String; var en: String }
    struct Topic: Decodable, Hashable, Identifiable { var id: String; var sr: String; var en: String }
    struct Category: Decodable, Hashable, Identifiable { var id: String; var name: Name; var topics: [Topic] }
    struct Level: Decodable, Hashable { var level: String; var name: Name; var description: Name; var categories: [Category] }
    var levels: [Level]

    static let shared: Curriculum = {
        guard let url = Bundle.main.url(forResource: "curriculum", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let c = try? JSONDecoder().decode(Curriculum.self, from: data) else { return Curriculum(levels: []) }
        return c
    }()

    /// Built-in units placed on their topic (German A1 so far).
    static let builtInTopics: [String: String] = [
        "de-a1-1-1": "a1-greetings-and-goodbyes", "de-a1-1-2": "a1-introducing-yourself", "de-a1-1-3": "a1-restaurants-and-cafes",
        "de-a1-1-4": "a1-family-members", "de-a1-1-5": "a1-numbers", "de-a1-2-1": "a1-basic-food", "de-a1-2-2": "a1-places-in-town",
        "de-a1-2-3": "a1-morning-routine", "de-a1-2-4": "a1-hobbies-and-interests", "de-a1-2-5": "a1-weather",
    ]

    /// Topic names in the app's language: Serbian as written, English otherwise
    /// (translated on the fly elsewhere when the phone uses another language).
    static var usesSerbian: Bool { (Locale.current.language.languageCode?.identifier ?? "") == "sr" }
    static func name(_ n: Name) -> String { usesSerbian ? n.sr : n.en }
    static func name(_ t: Topic) -> String { usesSerbian ? t.sr : t.en }

    func topic(_ id: String) -> (Topic, Level)? {
        for l in levels { for c in l.categories { if let t = c.topics.first(where: { $0.id == id }) { return (t, l) } } }
        return nil
    }
}
