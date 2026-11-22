import Foundation

// MARK: - Data

enum VocabLevel: String, CaseIterable, Codable, Identifiable {
    case a1 = "A1", a2 = "A2", b1 = "B1"
    var id: String { rawValue }
    var previous: VocabLevel? {
        switch self {
        case .a1: nil
        case .a2: .a1
        case .b1: .a2
        }
    }
}

struct VocabWord: Decodable, Identifiable, Hashable {
    enum POS: String, Decodable { case noun, verb, other }

    let id: String
    let level: VocabLevel
    let pos: POS
    let de: String
    let article: String?
    let articles: [String]?
    let plural: String?
    let pluralOnly: Bool?
    let perfekt: String?
    let reflexive: Bool?
    let example: String?
    let exampleEn: String?

    var acceptedArticles: [String] { articles ?? [article].compactMap { $0 } }
    var isPluralOnly: Bool { pluralOnly == true }
    var hasNoPlural: Bool { pos == .noun && !isPluralOnly && plural == nil }
    /// "die Karte, die Karten" / "fahren — ist gefahren"
    var fullForm: String {
        switch pos {
        case .noun:
            let arts = acceptedArticles.joined(separator: "/")
            if isPluralOnly { return "die \(de) (Pl.)" }
            return "\(arts) \(de), " + (plural.map { "die \($0)" } ?? L("no plural"))
        case .verb: return "\(de) — \(perfekt ?? "")"
        case .other: return de
        }
    }
}

enum VocabBank {
    static let words: [VocabWord] = {
        struct File: Decodable { var words: [VocabWord] }
        guard let url = Bundle.main.url(forResource: "vocab_de", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data) else { return [] }
        return file.words
    }()
    static let byID: [String: VocabWord] = Dictionary(uniqueKeysWithValues: words.map { ($0.id, $0) })
    static func words(in level: VocabLevel) -> [VocabWord] { words.filter { $0.level == level } }
}

// MARK: - Progress (spaced repetition)

struct WordProgress: Codable, Hashable {
    var box = 0              // 0 = learning; 3+ = mastered
    var due = Date()
    var seen = 0
    var correct = 0
    var lastAnswered: Date?

    static let masteredBox = 3
    var isMastered: Bool { box >= Self.masteredBox }
}

struct VocabProgressStore: Codable, Equatable {
    var words: [String: WordProgress] = [:]
    /// Cached translations: language tag → word id → accepted translations.
    var translations: [String: [String: [String]]] = [:]
    var newPerSession = 8
    var sessionSize = 15
    var streakDays: [String] = []

    func progress(_ id: String) -> WordProgress? { words[id] }

    func mastered(in level: VocabLevel) -> Int {
        VocabBank.words(in: level).filter { words[$0.id]?.isMastered == true }.count
    }

    func isUnlocked(_ level: VocabLevel) -> Bool {
        guard let prev = level.previous else { return true }
        return isUnlocked(prev) && mastered(in: prev) == VocabBank.words(in: prev).count
    }

    /// The level new words come from: the first one that isn't fully mastered.
    var currentLevel: VocabLevel {
        VocabLevel.allCases.first { mastered(in: $0) < VocabBank.words(in: $0).count } ?? .b1
    }
}

// MARK: - Session building & answer checking

enum VocabEngine {
    /// Intervals after a correct answer, indexed by the new box.
    static let intervals: [TimeInterval] = [0, 10 * 60, 86_400, 3 * 86_400, 7 * 86_400, 21 * 86_400, 60 * 86_400]

    /// Due reviews first (any unlocked level), then a few random new words from the current level only.
    static func buildSession(_ store: VocabProgressStore, now: Date = Date()) -> [VocabWord] {
        let current = store.currentLevel
        let unlocked = VocabLevel.allCases.filter { store.isUnlocked($0) }
        let pool = VocabBank.words.filter { unlocked.contains($0.level) }

        let due = pool
            .compactMap { w -> (VocabWord, WordProgress)? in
                guard let p = store.words[w.id], p.seen > 0, p.due <= now else { return nil }
                return (w, p)
            }
            .sorted { ($0.1.box, $0.1.due) < ($1.1.box, $1.1.due) }
            .map(\.0)

        let fresh = VocabBank.words(in: current)
            .filter { (store.words[$0.id]?.seen ?? 0) == 0 }
            .shuffled()

        var session = Array(due.prefix(store.sessionSize))
        let room = max(0, store.sessionSize - session.count)
        session += fresh.prefix(min(room, store.newPerSession))
        // If nothing is due yet, keep practising the words still being learned in this level.
        if session.isEmpty {
            session = VocabBank.words(in: current)
                .filter { store.words[$0.id].map { !$0.isMastered } ?? false }
                .shuffled()
                .prefix(store.sessionSize)
                .map { $0 }
        }
        return session.shuffled()
    }

    static func record(_ store: inout VocabProgressStore, id: String, correct: Bool, now: Date = Date()) {
        var p = store.words[id] ?? WordProgress()
        p.seen += 1
        p.lastAnswered = now
        if correct {
            p.correct += 1
            p.box = min(p.box + 1, intervals.count - 1)
            p.due = now.addingTimeInterval(intervals[p.box])
        } else {
            p.box = 0
            p.due = now
        }
        store.words[id] = p
        let day = DateUtil.dayKey(now)
        if store.streakDays.last != day { store.streakDays.append(day); store.streakDays = Array(store.streakDays.suffix(60)) }
    }

    // MARK: Normalising answers

    static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "ß", with: "ss")
            .components(separatedBy: CharacterSet.alphanumerics.union(.whitespaces).inverted).joined()
            .split(separator: " ").joined(separator: " ")
    }

    /// German answers keep umlauts (Garten ≠ Gärten) but accept ae/oe/ue and ss spellings.
    static func foldGerman(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: "ß", with: "ss")
            .replacingOccurrences(of: "ae", with: "ä")
            .replacingOccurrences(of: "oe", with: "ö")
            .replacingOccurrences(of: "ue", with: "ü")
            .components(separatedBy: CharacterSet.letters.union(.whitespaces).inverted).joined()
            .split(separator: " ").joined(separator: " ")
    }

    private static let germanPronouns: Set<String> = ["ich", "du", "er", "sie", "es", "wir", "ihr", "man"]

    static func checkArticle(_ picked: String?, _ word: VocabWord) -> Bool {
        guard let picked else { return false }
        return word.acceptedArticles.contains(picked)
    }

    static func checkPlural(_ answer: String, noPlural: Bool, _ word: VocabWord) -> Bool {
        if word.isPluralOnly { return true }
        if word.hasNoPlural { return noPlural || foldGerman(answer) == "" || foldGerman(answer) == "kein plural" }
        guard !noPlural, let expected = word.plural else { return false }
        var a = foldGerman(answer)
        if a.hasPrefix("die ") { a.removeFirst(4) }
        return a == foldGerman(expected)
    }

    static func checkPerfekt(_ answer: String, _ word: VocabWord) -> Bool {
        guard let expected = word.perfekt else { return true }
        var words = foldGerman(answer).split(separator: " ").map(String.init)
        if let first = words.first, germanPronouns.contains(first) { words.removeFirst() }
        words.removeAll { $0 == "sich" }
        let exp = expected.lowercased().split(separator: " ").map(String.init).filter { $0 != "sich" }
        guard let participle = exp.last.map(foldGerman), let auxPart = exp.first,
              words.count == 2, words[1] == participle else { return false }
        let auxOptions = auxPart.split(separator: "/").map(String.init)   // "hat/ist"
        let given = words[0] == "habe" || words[0] == "hast" ? "hat" : (words[0] == "bin" || words[0] == "bist" ? "ist" : words[0])
        return auxOptions.contains(given)
    }

    /// Local check against known translations (case, accents, articles and tiny typos are forgiven).
    static func checkTranslation(_ answer: String, accepted: [String]) -> Bool {
        let a = stripLead(fold(answer))
        guard !a.isEmpty else { return false }
        let options = accepted.flatMap { $0.split(whereSeparator: { ",;/".contains($0) }).map(String.init) }
            .map { stripLead(fold($0)) }
            .filter { !$0.isEmpty }
        return options.contains { $0 == a || ($0.count >= 5 && levenshtein($0, a) <= 1) }
    }

    private static func stripLead(_ s: String) -> String {
        let leads = ["to ", "the ", "a ", "an ", "der ", "die ", "das ", "el ", "la ", "le ", "les ", "il ", "lo ", "o ", "os ", "as "]
        for l in leads where s.hasPrefix(l) && s.count > l.count + 1 { return String(s.dropFirst(l.count)) }
        return s
    }

    static func levenshtein(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        for i in 1...a.count {
            var cur = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            prev = cur
        }
        return prev[b.count]
    }
}
