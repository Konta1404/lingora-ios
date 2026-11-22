import Foundation

/// Latin letters for other scripts (Cyrillic, Greek, kana/kanji, Hangul, Arabic, Devanagari…).
enum Romanize {
    static let scripts: Set<String> = ["ja", "ru", "uk", "el", "zh", "ko", "ar", "hi", "he", "th", "bg"]
    static func needs(_ lang: String) -> Bool { scripts.contains(lang) }

    static func latin(_ text: String, lang: String) -> String? {
        guard needs(lang) else { return nil }
        if lang == "ja" { return japanese(text) }
        return text.applyingTransform(.toLatin, reverse: false)?.applyingTransform(.stripDiacritics, reverse: false) ?? nil
    }

    /// Japanese needs a dictionary reading (kanji are read per word), which the tokenizer provides.
    private static func japanese(_ text: String) -> String? {
        let ns = text as NSString
        let tok = CFStringTokenizerCreate(nil, ns, CFRange(location: 0, length: ns.length), kCFStringTokenizerUnitWord, Locale(identifier: "ja") as CFLocale)
        var out: [String] = []
        while CFStringTokenizerAdvanceToNextToken(tok) != [] {
            if let latin = CFStringTokenizerCopyCurrentTokenAttribute(tok, kCFStringTokenizerAttributeLatinTranscription) as? String {
                out.append(latin)
            } else {
                let r = CFStringTokenizerGetCurrentTokenRange(tok)
                out.append(ns.substring(with: NSRange(location: r.location, length: r.length)))
            }
        }
        return out.isEmpty ? nil : out.joined(separator: " ")
    }
}

/// Letters of a writing system with their sound, taught before the course for non-Latin languages.
struct Alphabet {
    var lang: String
    var name: String
    var letters: [(char: String, sound: String)]

    static func forLanguage(_ lang: String) -> Alphabet? {
        switch lang {
        case "ja":
            let rows = "a i u e o ka ki ku ke ko sa shi su se so ta chi tsu te to na ni nu ne no ha hi fu he ho ma mi mu me mo ya yu yo ra ri ru re ro wa wo n"
            let kana = "あ い う え お か き く け こ さ し す せ そ た ち つ て と な に ぬ ね の は ひ ふ へ ほ ま み む め も や ゆ よ ら り る れ ろ わ を ん"
            return Alphabet(lang: lang, name: L("Hiragana"), letters: Array(zip(kana.split(separator: " ").map(String.init), rows.split(separator: " ").map(String.init))).map { (char: $0.0, sound: $0.1) })
        case "ru":
            let c = "А Б В Г Д Е Ё Ж З И Й К Л М Н О П Р С Т У Ф Х Ц Ч Ш Щ Ъ Ы Ь Э Ю Я"
            let s = "a b v g d ye yo zh z i y k l m n o p r s t u f kh ts ch sh shch (hard) y (soft) e yu ya"
            return Alphabet(lang: lang, name: L("Cyrillic alphabet"), letters: Array(zip(c.split(separator: " ").map(String.init), s.split(separator: " ").map(String.init))).map { (char: $0.0, sound: $0.1) })
        case "el":
            let c = "Α Β Γ Δ Ε Ζ Η Θ Ι Κ Λ Μ Ν Ξ Ο Π Ρ Σ Τ Υ Φ Χ Ψ Ω"
            let s = "a v g d e z i th i k l m n x o p r s t i f kh ps o"
            return Alphabet(lang: lang, name: L("Greek alphabet"), letters: Array(zip(c.split(separator: " ").map(String.init), s.split(separator: " ").map(String.init))).map { (char: $0.0, sound: $0.1) })
        default:
            return nil
        }
    }

    /// Groups of 8 letters, each a practice lesson.
    var groups: [[(char: String, sound: String)]] {
        stride(from: 0, to: letters.count, by: 8).map { Array(letters[$0..<min($0 + 8, letters.count)]) }
    }

    func lesson(group i: Int) -> CourseLesson {
        let g = groups[i]
        let items = g.map { CourseItem(t: $0.char, en: $0.sound) }
        let unit = CourseUnit(id: "alphabet-\(lang)-\(i)", title: name, tip: nil, words: items, sentences: [])
        return CourseLesson(unit: unit, kind: .review, mode: .practice)
    }
}
