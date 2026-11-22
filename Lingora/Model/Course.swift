import Foundation
import AVFoundation

// MARK: - Course content

/// A course: sections → units → lessons. A unit holds words and sentences; its lessons and their
/// exercises are generated from them, so new units only need content, not hand-written exercises.
struct CourseItem: Codable, Hashable {
    var t: String     // target language
    var en: String    // meaning (English; shown in the app's language when a translation is available)
}

struct CourseUnit: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var tip: String?
    var words: [CourseItem]
    var sentences: [CourseItem]
}

struct CourseSection: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var level: String
    var units: [CourseUnit]
}

struct Course: Codable, Hashable {
    var lang: String
    var sections: [CourseSection]
}

/// Lesson kinds inside every unit, in order.
enum LessonKind: Int, CaseIterable, Codable {
    case words1, words2, sentences, review
    var title: String {
        switch self {
        case .words1: L("New words")
        case .words2: L("More words")
        case .sentences: L("Sentences")
        case .review: L("Unit review")
        }
    }
    var icon: String {
        switch self {
        case .words1, .words2: "textformat.abc"
        case .sentences: "text.bubble"
        case .review: "star.fill"
        }
    }
}

struct CourseLesson: Identifiable, Hashable {
    var unit: CourseUnit
    var kind: LessonKind
    var id: String { "\(unit.id)#\(kind.rawValue)" }
}

enum CourseLibrary {
    private static var cache: [String: Course] = [:]

    /// Built-in courses shipped with the app (Resources/course_<lang>.json).
    static func builtIn(_ lang: String) -> Course? {
        if let c = cache[lang] { return c }
        guard let url = Bundle.main.url(forResource: "course_\(lang)", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let c = try? JSONDecoder().decode(Course.self, from: data) else { return nil }
        cache[lang] = c
        return c
    }

    static func lessons(_ course: Course) -> [CourseLesson] {
        course.sections.flatMap { $0.units }.flatMap { u in LessonKind.allCases.map { CourseLesson(unit: u, kind: $0) } }
    }
}

// MARK: - Exercises

enum Exercise: Identifiable, Hashable {
    /// Target word → pick its meaning.
    case meaning(id: String, item: CourseItem, options: [String])
    /// Meaning → pick the target word.
    case pickWord(id: String, item: CourseItem, options: [String])
    /// Tap the matching pairs.
    case match(id: String, items: [CourseItem])
    /// Meaning shown → build the target sentence from tiles.
    case buildTarget(id: String, item: CourseItem, tiles: [String])
    /// Target sentence shown → build its meaning from tiles (needs the meaning in the app's language).
    case buildMeaning(id: String, item: CourseItem, tiles: [String])
    /// Sentence with one word missing → pick it.
    case fillBlank(id: String, item: CourseItem, blank: Int, options: [String])
    /// Hear a word → pick it.
    case listenPick(id: String, item: CourseItem, options: [String])
    /// Hear a sentence → type it.
    case listenType(id: String, item: CourseItem)
    /// Meaning shown → type the target.
    case typeTarget(id: String, item: CourseItem)
    /// Read the sentence aloud.
    case speak(id: String, item: CourseItem)

    var id: String {
        switch self {
        case .meaning(let id, _, _), .pickWord(let id, _, _), .match(let id, _), .buildTarget(let id, _, _),
             .buildMeaning(let id, _, _), .fillBlank(let id, _, _, _), .listenPick(let id, _, _),
             .listenType(let id, _), .typeTarget(let id, _), .speak(let id, _): id
        }
    }

    var instruction: String {
        switch self {
        case .meaning: L("What does this mean?")
        case .pickWord: L("Select the correct word")
        case .match: L("Tap the matching pairs")
        case .buildTarget: L("Write this in your new language")
        case .buildMeaning: L("Translate this sentence")
        case .fillBlank: L("Fill in the blank")
        case .listenPick: L("What do you hear?")
        case .listenType: L("Type what you hear")
        case .typeTarget: L("Type this in your new language")
        case .speak: L("Read this aloud")
        }
    }
}

enum LessonBuilder {
    /// Makes the exercises for one lesson. `meanings` = the units' English meanings in the app's language.
    static func exercises(for lesson: CourseLesson, meanings: [String: String], allowSpeaking: Bool) -> [Exercise] {
        let u = lesson.unit
        let half = max(1, u.words.count / 2)
        let m: (CourseItem) -> CourseItem = { CourseItem(t: $0.t, en: meanings[$0.en] ?? $0.en) }
        let words = u.words.map(m), sentences = u.sentences.map(m)
        var out: [Exercise] = []
        var n = 0
        func next() -> String { n += 1; return "\(lesson.id)-\(n)" }
        func others<T: Equatable>(_ pool: [T], not x: T, count: Int) -> [T] { Array(pool.filter { $0 != x }.shuffled().prefix(count)) }

        switch lesson.kind {
        case .words1, .words2:
            let set = lesson.kind == .words1 ? Array(words.prefix(half)) : Array(words.dropFirst(half))
            for w in set {
                out.append(.meaning(id: next(), item: w, options: (others(words.map(\.en), not: w.en, count: 2) + [w.en]).shuffled()))
            }
            out.append(.match(id: next(), items: Array(set.shuffled().prefix(4))))
            for w in set.shuffled().prefix(2) {
                out.append(.listenPick(id: next(), item: w, options: (others(words.map(\.t), not: w.t, count: 2) + [w.t]).shuffled()))
            }
            for w in set.shuffled().prefix(2) {
                out.append(.pickWord(id: next(), item: w, options: (others(words.map(\.t), not: w.t, count: 2) + [w.t]).shuffled()))
            }
            if let w = set.randomElement() { out.append(.typeTarget(id: next(), item: w)) }
        case .sentences:
            for s in sentences.prefix(3) { out.append(.buildTarget(id: next(), item: s, tiles: tiles(s.t, extra: words.map(\.t)))) }
            for s in sentences.dropFirst(3).prefix(2) { out.append(.buildMeaning(id: next(), item: s, tiles: tiles(s.en, extra: words.map(\.en)))) }
            if let s = sentences.randomElement() { out.append(fill(s, id: next(), pool: words.map(\.t))) }
            if let s = sentences.randomElement() { out.append(.listenType(id: next(), item: s)) }
            if allowSpeaking, let s = sentences.randomElement() { out.append(.speak(id: next(), item: s)) }
        case .review:
            out.append(.match(id: next(), items: Array(words.shuffled().prefix(5))))
            for w in words.shuffled().prefix(2) { out.append(.typeTarget(id: next(), item: w)) }
            for s in sentences.shuffled().prefix(2) { out.append(.buildTarget(id: next(), item: s, tiles: tiles(s.t, extra: words.map(\.t)))) }
            if let s = sentences.randomElement() { out.append(fill(s, id: next(), pool: words.map(\.t))) }
            if let s = sentences.randomElement() { out.append(.listenType(id: next(), item: s)) }
            if allowSpeaking, let s = sentences.randomElement() { out.append(.speak(id: next(), item: s)) }
            if let w = words.randomElement() { out.append(.listenPick(id: next(), item: w, options: (others(words.map(\.t), not: w.t, count: 2) + [w.t]).shuffled())) }
        }
        return out
    }

    /// The sentence's words plus a few distractors, shuffled.
    static func tiles(_ sentence: String, extra: [String]) -> [String] {
        let own = Check.words(sentence)
        let distract = extra.flatMap(Check.words).filter { w in !own.contains { Check.norm($0) == Check.norm(w) } }
        return (own + Array(Set(distract)).shuffled().prefix(min(3, max(2, own.count / 2)))).shuffled()
    }

    private static func fill(_ s: CourseItem, id: String, pool: [String]) -> Exercise {
        let ws = Check.words(s.t)
        let idx = ws.indices.max { ws[$0].count < ws[$1].count } ?? 0
        let answer = ws[idx]
        let distract = Array(Set(pool.flatMap(Check.words)).filter { Check.norm($0) != Check.norm(answer) }.shuffled().prefix(2))
        return .fillBlank(id: id, item: s, blank: idx, options: (distract + [answer]).shuffled())
    }
}

// MARK: - Checking answers

enum Check {
    enum Result: Equatable { case right, typo(String), wrong(String) }

    /// Words without punctuation, keeping their original form.
    static func words(_ s: String) -> [String] {
        s.components(separatedBy: .whitespaces)
            .map { $0.trimmingCharacters(in: .punctuationCharacters.union(.symbols)) }
            .filter { !$0.isEmpty }
    }

    /// Lowercased, punctuation removed, German spellings folded (ä = ae, ß = ss), single spaces.
    static func norm(_ s: String) -> String {
        var t = s.lowercased()
        for (a, b) in [("ä", "ae"), ("ö", "oe"), ("ü", "ue"), ("ß", "ss"), ("’", "'")] { t = t.replacingOccurrences(of: a, with: b) }
        t = t.folding(options: [.diacriticInsensitive], locale: nil)
        let kept = t.unicodeScalars.map { CharacterSet.letters.union(.decimalDigits).union(.whitespaces).contains($0) ? Character($0) : " " }
        return String(kept).split(separator: " ").joined(separator: " ")
    }

    /// Typed answers: exact (after folding) is right; one slip per 8 letters counts with a note.
    static func typed(_ answer: String, expected: String) -> Result {
        let a = norm(answer), e = norm(expected)
        if a == e { return .right }
        if !a.isEmpty, distance(a, e) <= max(1, e.count / 8) { return .typo(expected) }
        return .wrong(expected)
    }

    /// Tiles: same words in the same order.
    static func tiles(_ chosen: [String], expected: String) -> Result {
        norm(chosen.joined(separator: " ")) == norm(expected) ? .right : .wrong(expected)
    }

    /// Speech: most words recognised in order.
    static func spoken(_ heard: String, expected: String) -> Result {
        let h = norm(heard).split(separator: " "), e = norm(expected).split(separator: " ")
        guard !e.isEmpty else { return .wrong(expected) }
        let hit = e.filter { h.contains($0) }.count
        return Double(hit) / Double(e.count) >= 0.75 ? .right : .wrong(expected)
    }

    static func distance(_ a: String, _ b: String) -> Int {
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

// MARK: - Audio

/// Reads target-language words and sentences aloud.
@MainActor
final class Speaker {
    static let shared = Speaker()
    private let synth: AVSpeechSynthesizer = {
        let s = AVSpeechSynthesizer()
        // Let the synthesizer handle its own audio: no session switching on the main thread,
        // and no clash with the microphone used for dictation.
        s.usesApplicationAudioSession = false
        return s
    }()
    private static var voices: [String: AVSpeechSynthesisVoice] = [:]

    /// The best voice installed for the language: Premium, then Enhanced, then the default one.
    static func bestVoice(for lang: String) -> AVSpeechSynthesisVoice? {
        let id = Dictation.locale(for: lang).identifier.replacingOccurrences(of: "_", with: "-")
        if let v = voices[id] { return v }
        let code = String(id.prefix(2))
        let all = AVSpeechSynthesisVoice.speechVoices()
        let exact = all.filter { $0.language == id }
        let pool = exact.isEmpty ? all.filter { $0.language.hasPrefix(code) } : exact
        let v = pool.max { $0.quality.rawValue < $1.quality.rawValue } ?? AVSpeechSynthesisVoice(language: id)
        voices[id] = v
        return v
    }

    /// True when only the basic (compact) voice is installed for the language.
    static func hasOnlyBasicVoice(_ lang: String) -> Bool {
        (bestVoice(for: lang)?.quality ?? .default) == .default
    }

    func say(_ text: String, lang: String, slow: Bool = false) {
        synth.stopSpeaking(at: .immediate)
        let u = AVSpeechUtterance(string: text)
        u.voice = Self.bestVoice(for: lang)
        u.rate = slow ? 0.32 : 0.45
        synth.speak(u)
    }
}
