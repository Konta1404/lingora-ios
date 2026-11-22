import Foundation
import AVFoundation

// MARK: - Course content

/// A course: sections → units → lessons. A unit holds words and sentences; its lessons and their
/// exercises are generated from them, so new units only need content, not hand-written exercises.
struct CourseItem: Codable, Hashable {
    var t: String     // target language
    var en: String    // meaning (English; shown in the app's language when a translation is available)
    var img: String? = nil   // picture (emoji) for picture exercises
}

/// A line and its natural reply, for "pick the right answer in the conversation".
struct CourseDialogue: Codable, Hashable {
    var q: CourseItem
    var a: CourseItem
    var wrong: [String]
}

struct CourseUnit: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var tip: String?
    var words: [CourseItem]
    var sentences: [CourseItem]
    var dialogues: [CourseDialogue]? = nil
    /// Curriculum topic id; a unit without words is a topic not written yet.
    var topic: String? = nil
    var isPlaceholder: Bool { words.isEmpty }
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

enum LessonMode: Hashable {
    case normal
    /// Mistakes or mixed review — doesn't unlock anything.
    case practice
    /// Test to skip ahead: passing marks every lesson before section `index` done.
    case jump(section: Int)
    /// Only listening exercises.
    case listening
    /// Only speaking exercises.
    case speaking
    /// 60-second speed round.
    case speed
}

struct CourseLesson: Identifiable, Hashable {
    var unit: CourseUnit
    var kind: LessonKind
    var mode: LessonMode = .normal
    var id: String {
        switch mode {
        case .normal: "\(unit.id)#\(kind.rawValue)"
        case .practice: "practice-\(unit.id)"
        case .jump(let s): "jump-\(unit.id)-\(s)"
        case .listening: "listening-\(unit.id)"
        case .speaking: "speaking-\(unit.id)"
        case .speed: "speed-\(unit.id)"
        }
    }
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
        course.sections.flatMap { $0.units }.filter { !$0.isPlaceholder }.flatMap { u in LessonKind.allCases.map { CourseLesson(unit: u, kind: $0) } }
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
    /// Word shown → pick its picture.
    case pickPicture(id: String, item: CourseItem, options: [CourseItem])
    /// Picture shown → type the word.
    case pictureCard(id: String, item: CourseItem)
    /// Someone says something → pick the right reply.
    case reply(id: String, dialogue: CourseDialogue, options: [String])
    /// Meaning shown → say it in the language.
    case speakTranslation(id: String, item: CourseItem)

    var id: String {
        switch self {
        case .meaning(let id, _, _), .pickWord(let id, _, _), .match(let id, _), .buildTarget(let id, _, _),
             .buildMeaning(let id, _, _), .fillBlank(let id, _, _, _), .listenPick(let id, _, _),
             .listenType(let id, _), .typeTarget(let id, _), .speak(let id, _), .pickPicture(let id, _, _),
             .pictureCard(let id, _), .reply(let id, _, _), .speakTranslation(let id, _): id
        }
    }

    var isSpeaking: Bool {
        switch self {
        case .speak, .speakTranslation: true
        default: false
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
        case .pickPicture: L("Which picture is it?")
        case .pictureCard: L("What is this?")
        case .reply: L("Choose the right answer")
        case .speakTranslation: L("Say this in your new language")
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
        let md: (CourseDialogue) -> CourseDialogue = { CourseDialogue(q: m($0.q), a: m($0.a), wrong: $0.wrong) }
        var out: [Exercise] = []
        var n = 0
        func next() -> String { n += 1; return "\(lesson.id)-\(n)" }
        func others<T: Equatable>(_ pool: [T], not x: T, count: Int) -> [T] { Array(pool.filter { $0 != x }.shuffled().prefix(count)) }

        // Alphabet practice: letter ↔ sound, by ear and by matching (no typing in another script).
        if u.id.hasPrefix("alphabet-") {
            let chars = u.words.map(\.t), sounds = u.words.map(\.en)
            func three(_ pool: [String], _ x: String) -> [String] { (Array(pool.filter { $0 != x }.shuffled().prefix(2)) + [x]).shuffled() }
            var out: [Exercise] = []
            for (i, w) in u.words.shuffled().enumerated() {
                switch i % 3 {
                case 0: out.append(.meaning(id: next(), item: w, options: three(sounds, w.en)))
                case 1: out.append(.pickWord(id: next(), item: w, options: three(chars, w.t)))
                default: out.append(.listenPick(id: next(), item: w, options: three(chars, w.t)))
                }
            }
            out.insert(.match(id: next(), items: Array(u.words.shuffled().prefix(5))), at: min(3, out.count))
            return out
        }

        switch lesson.mode {
        case .normal: break
        case .listening:
            let wordPool = words.map(\.t)
            var out: [Exercise] = words.shuffled().prefix(5).map { w in
                Exercise.listenPick(id: next(), item: w, options: (Array(wordPool.filter { $0 != w.t }.shuffled().prefix(2)) + [w.t]).shuffled())
            }
            out += sentences.shuffled().prefix(5).map { Exercise.listenType(id: next(), item: $0) }
            return out.shuffled()
        case .speaking:
            var out = (Array(sentences.shuffled().prefix(5)) + Array(words.shuffled().prefix(2))).map { Exercise.speak(id: next(), item: $0) }
            out += sentences.filter { Check.words($0.t).count <= 6 }.shuffled().prefix(3).map { Exercise.speakTranslation(id: next(), item: $0) }
            return out.shuffled()
        case .speed:
            // Quick taps only; the player stops at 60 seconds.
            let wordPool = words.map(\.t), meaningPool = words.map(\.en)
            func three(_ pool: [String], _ x: String) -> [String] { (Array(pool.filter { $0 != x }.shuffled().prefix(2)) + [x]).shuffled() }
            var out: [Exercise] = []
            for _ in 0..<3 {
                for (i, w) in words.shuffled().enumerated() {
                    out.append(i % 2 == 0 ? Exercise.meaning(id: next(), item: w, options: three(meaningPool, w.en))
                                          : Exercise.pickWord(id: next(), item: w, options: three(wordPool, w.t)))
                }
            }
            return out
        default:
            return mixed(words: words, sentences: sentences, count: lesson.mode == .practice ? 12 : 15, next: next)
        }

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
            let pics = words.filter { $0.img != nil }
            for w in set.filter({ $0.img != nil }).shuffled().prefix(2) where pics.count >= 3 {
                out.append(.pickPicture(id: next(), item: w, options: (Array(pics.filter { $0.t != w.t }.shuffled().prefix(2)) + [w]).shuffled()))
            }
            if let w = set.filter({ $0.img != nil }).randomElement() { out.append(.pictureCard(id: next(), item: w)) }
        case .sentences:
            for s in sentences.prefix(3) { out.append(.buildTarget(id: next(), item: s, tiles: tiles(s.t, extra: words.map(\.t)))) }
            for s in sentences.dropFirst(3).prefix(2) { out.append(.buildMeaning(id: next(), item: s, tiles: tiles(s.en, extra: words.map(\.en)))) }
            if let s = sentences.randomElement() { out.append(fill(s, id: next(), pool: words.map(\.t))) }
            if let s = sentences.randomElement() { out.append(.listenType(id: next(), item: s)) }
            if allowSpeaking, let s = sentences.randomElement() { out.append(.speak(id: next(), item: s)) }
            for d in (u.dialogues ?? []).map(md) { out.append(.reply(id: next(), dialogue: d, options: (d.wrong + [d.a.t]).shuffled())) }
            if allowSpeaking, let s = sentences.filter({ Check.words($0.t).count <= 6 }).randomElement() {
                out.append(.speakTranslation(id: next(), item: s))
            }
        case .review:
            out.append(.match(id: next(), items: Array(words.shuffled().prefix(5))))
            for w in words.shuffled().prefix(2) { out.append(.typeTarget(id: next(), item: w)) }
            for s in sentences.shuffled().prefix(2) { out.append(.buildTarget(id: next(), item: s, tiles: tiles(s.t, extra: words.map(\.t)))) }
            if let s = sentences.randomElement() { out.append(fill(s, id: next(), pool: words.map(\.t))) }
            if let s = sentences.randomElement() { out.append(.listenType(id: next(), item: s)) }
            if allowSpeaking, let s = sentences.randomElement() { out.append(.speak(id: next(), item: s)) }
            if let w = words.randomElement() { out.append(.listenPick(id: next(), item: w, options: (others(words.map(\.t), not: w.t, count: 2) + [w.t]).shuffled())) }
            if let d = (u.dialogues ?? []).randomElement().map(md) { out.append(.reply(id: next(), dialogue: d, options: (d.wrong + [d.a.t]).shuffled())) }
            if let w = words.filter({ $0.img != nil }).randomElement() { out.append(.pictureCard(id: next(), item: w)) }
        }
        return out
    }

    /// Practice and jump tests: a shuffled mix over all the given words and sentences.
    private static func mixed(words: [CourseItem], sentences: [CourseItem], count: Int, next: () -> String) -> [Exercise] {
        var out: [Exercise] = []
        let wordPool = words.map(\.t), meaningPool = words.map(\.en)
        func three<T: Equatable>(_ pool: [T], _ x: T) -> [T] { (Array(pool.filter { $0 != x }.shuffled().prefix(2)) + [x]).shuffled() }
        for (i, w) in words.shuffled().prefix(count / 2).enumerated() {
            switch i % 4 {
            case 0: out.append(.meaning(id: next(), item: w, options: three(meaningPool, w.en)))
            case 1: out.append(.typeTarget(id: next(), item: w))
            case 2: out.append(.listenPick(id: next(), item: w, options: three(wordPool, w.t)))
            default: out.append(.pickWord(id: next(), item: w, options: three(wordPool, w.t)))
            }
        }
        for (i, s) in sentences.shuffled().prefix(count - out.count).enumerated() {
            switch i % 3 {
            case 0: out.append(.buildTarget(id: next(), item: s, tiles: tiles(s.t, extra: wordPool)))
            case 1: out.append(.listenType(id: next(), item: s))
            default: out.append(fill(s, id: next(), pool: wordPool))
            }
        }
        if words.count >= 4 { out.insert(.match(id: next(), items: Array(words.shuffled().prefix(4))), at: min(2, out.count)) }
        return out.shuffled()
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

    /// The best voice of a gender, for story characters (falls back to the best voice).
    static func voice(for lang: String, gender: AVSpeechSynthesisVoiceGender) -> AVSpeechSynthesisVoice? {
        let id = Dictation.locale(for: lang).identifier.replacingOccurrences(of: "_", with: "-")
        let pool = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(String(id.prefix(2))) && $0.gender == gender }
        return pool.max { ($0.quality.rawValue, $0.language == id ? 1 : 0) < ($1.quality.rawValue, $1.language == id ? 1 : 0) }
    }

    /// True when only the basic (compact) voice is installed for the language.
    static func hasOnlyBasicVoice(_ lang: String) -> Bool {
        (bestVoice(for: lang)?.quality ?? .default) == .default
    }

    func say(_ text: String, lang: String, slow: Bool = false, gender: AVSpeechSynthesisVoiceGender? = nil) {
        synth.stopSpeaking(at: .immediate)
        let u = AVSpeechUtterance(string: text)
        u.voice = gender.flatMap { Self.voice(for: lang, gender: $0) } ?? Self.bestVoice(for: lang)
        u.rate = slow ? 0.32 : 0.45
        synth.speak(u)
    }
}
