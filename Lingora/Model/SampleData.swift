import Foundation

/// Copy and sample content carried over from the design prototype (LingoraApp2.dc.html).
enum Catalog {
    // key: (name, native, hello, thanks, hue)
    static let raw: [(String, String, String, String, String, Double)] = [
        ("es", "Spanish", "Español", "Hola", "Gracias", 45), ("fr", "French", "Français", "Bonjour", "Merci", 240),
        ("ja", "Japanese", "日本語", "こんにちは", "ありがとう", 340), ("de", "German", "Deutsch", "Hallo", "Danke", 150),
        ("it", "Italian", "Italiano", "Ciao", "Grazie", 110), ("ko", "Korean", "한국어", "안녕하세요", "감사합니다", 300),
        ("pt", "Portuguese", "Português", "Olá", "Obrigado", 75), ("zh", "Mandarin", "中文", "你好", "谢谢", 15),
        ("en", "English", "English", "Hello", "Thank you", 200), ("ar", "Arabic", "العربية", "مرحبا", "شكرا", 180),
        ("nl", "Dutch", "Nederlands", "Hallo", "Dank je", 60), ("sv", "Swedish", "Svenska", "Hej", "Tack", 220),
        ("tr", "Turkish", "Türkçe", "Merhaba", "Teşekkürler", 25), ("pl", "Polish", "Polski", "Cześć", "Dziękuję", 0),
        ("el", "Greek", "Ελληνικά", "Γειά σου", "Ευχαριστώ", 260), ("hi", "Hindi", "हिन्दी", "नमस्ते", "धन्यवाद", 90),
        ("ru", "Russian", "Русский", "Привет", "Спасибо", 280), ("uk", "Ukrainian", "Українська", "Привіт", "Дякую", 230),
        ("hr", "Croatian", "Hrvatski", "Bok", "Hvala", 130), ("sw", "Swahili", "Kiswahili", "Habari", "Asante", 160),
        ("vi", "Vietnamese", "Tiếng Việt", "Xin chào", "Cảm ơn", 320), ("he", "Hebrew", "עברית", "שלום", "תודה", 205),
        ("no", "Norwegian", "Norsk", "Hei", "Takk", 215), ("fi", "Finnish", "Suomi", "Hei", "Kiitos", 190),
        ("id", "Indonesian", "Bahasa Indonesia", "Halo", "Terima kasih", 100), ("th", "Thai", "ไทย", "สวัสดี", "ขอบคุณ", 50),
        ("ca", "Catalan", "Català", "Hola", "Gràcies", 35), ("ga", "Irish", "Gaeilge", "Dia duit", "Go raibh maith agat", 140)
    ]

    static let all: [Language] = raw.map {
        Language(key: $0.0, code: $0.0.uppercased(), name: $0.1, native: $0.2, hello: $0.3, thanks: $0.4, hue: $0.5)
    }
    static let byKey: [String: Language] = Dictionary(uniqueKeysWithValues: all.map { ($0.key, $0) })
    static let popular = ["es", "fr", "ja", "de", "it", "ko", "pt", "zh"]
    static let welcomeHellos = ["es", "ja", "fr", "de", "it", "ko", "pt", "sw", "hi"]

    static let greeting: [String: String] = [
        "es": "Buenos días", "it": "Buongiorno", "ja": "おはよう", "de": "Guten Morgen",
        "fr": "Bonjour", "en": "Good morning", "pt": "Bom dia", "ko": "좋은 아침"
    ]

    static let goals = ["Travel", "Work", "Exams", "Conversation", "Culture & media", "Moving abroad", "Family"]
    static let times = [15, 20, 30, 45, 60]
}

/// Offline content per language: lesson fallback + tutor scene and seed.
struct LanguageContent {
    var grammar: String
    var scene: String
    var lesson: LessonContent
    var tutorOpener: String
    var replies: [String]
    var suggestions: [String]

    static let builtIn: [String: LanguageContent] = [
        "es": .init(grammar: "Ser vs. estar", scene: L("Ordering tapas in Madrid"),
                    lesson: .init(card: .init(front: "la cuenta", back: L("the bill"), example: "La cuenta, por favor."),
                                  question: .init(prompt: "Mi hermana ___ cansada hoy.", options: ["es", "está", "son", "ser"], answer: 1, why: L("Temporary states use estar.")),
                                  writing: .init(prompt: L("Translate: “I would like a coffee, please.”"), modelAnswer: "Quisiera un café, por favor.")),
                    tutorOpener: "¡Hola! ¿Qué te pongo?",
                    replies: ["Muy bien. ¿Para tomar aquí o para llevar?", "Son 6,50 euros. ¿Algo más?", "¡Perfecto! Que aproveche."],
                    suggestions: ["Agua con gas, por favor.", "¿Qué me recomienda?", "¿Puedo pagar con tarjeta?"]),
        "it": .init(grammar: "Partitive articles", scene: L("Ordering at a bar in Rome"),
                    lesson: .init(card: .init(front: "il conto", back: L("the bill"), example: "Il conto, per favore."),
                                  question: .init(prompt: "Vorrei ___ pane, per favore.", options: ["del", "dello", "della", "dei"], answer: 0, why: L("Pane is masculine and starts with a consonant, so del.")),
                                  writing: .init(prompt: L("Translate: “I would like a coffee, please.”"), modelAnswer: "Vorrei un caffè, per favore.")),
                    tutorOpener: "Buongiorno! Cosa prende?",
                    replies: ["Ottimo. Desidera anche un cornetto?", "Sono 3 euro. Paga alla cassa, grazie.", "Perfetto, buona giornata!"],
                    suggestions: ["Al banco, grazie.", "Cosa mi consiglia?", "Posso pagare con la carta?"]),
        "ja": .init(grammar: "Particles を and が", scene: L("Ordering at a Tokyo café"),
                    lesson: .init(card: .init(front: "お会計", back: L("the bill"), example: "お会計お願いします。"),
                                  question: .init(prompt: "コーヒー＿ください。", options: ["を", "が", "に", "で"], answer: 0, why: L("を marks the thing you are asking for.")),
                                  writing: .init(prompt: L("Translate: “A coffee, please.”"), modelAnswer: "コーヒーをください。")),
                    tutorOpener: "いらっしゃいませ！ご注文は？",
                    replies: ["ご一緒にケーキはいかがですか？", "500円です。", "ありがとうございました！"],
                    suggestions: ["ホットでお願いします。", "おすすめは何ですか？", "カードで払えますか？"]),
        "de": .init(grammar: "Dative articles", scene: L("Ordering at a café in Berlin"),
                    lesson: .init(card: .init(front: "die Rechnung", back: L("the bill"), example: "Die Rechnung, bitte."),
                                  question: .init(prompt: "Ich gebe ___ Kellner das Trinkgeld.", options: ["der", "dem", "den", "des"], answer: 1, why: L("“geben” takes the dative: der Kellner → dem Kellner.")),
                                  writing: .init(prompt: L("Translate: “I would like a coffee, please.”"), modelAnswer: "Ich hätte gern einen Kaffee, bitte.")),
                    tutorOpener: "Guten Morgen! Was darf es sein?",
                    replies: ["Sehr gut! Möchten Sie auch etwas essen?", "Das macht 4,20 Euro.", "Einen schönen Tag noch!"],
                    suggestions: ["Mit Milch, bitte.", "Was empfehlen Sie?", "Kann ich mit Karte zahlen?"])
    ]

    static func forLanguage(_ l: Language) -> LanguageContent {
        if let c = builtIn[l.key] { return c }
        let others = ["Merci", "Danke", "Gracias"].filter { $0 != l.thanks }.prefix(2)
        return .init(grammar: L("Basic sentence order"), scene: L("Introducing yourself"),
                     lesson: .init(card: .init(front: l.hello, back: L("hello"), example: L("%@! — the everyday greeting.", l.hello)),
                                   question: .init(prompt: L("How do you say “thank you” in %@?", l.name), options: [l.hello, l.thanks] + others, answer: 1, why: L("%@ is the everyday way to say thanks.", l.thanks)),
                                   writing: .init(prompt: L("Write “Good morning, how are you?” in %@.", l.name), modelAnswer: L("ChatGPT checks your answer and suggests a natural version."))),
                     tutorOpener: L("%@! Let’s practise %@. Tell me a little about yourself.", l.hello, l.name),
                     replies: [L("Great start — tell me more."), L("Nice! What do you do for work?"), L("Lovely. Let’s keep going tomorrow.")],
                     suggestions: [l.hello, l.thanks, L("How do I say…?")])
    }
}

/// Offline weekly plan, used when ChatGPT isn't connected or a request fails.
enum FallbackPlanner {
    static func plan(for lang: Language, index: Int, weekStart: Date, goals: [String]) -> WeeklyPlan {
        let c = LanguageContent.forLanguage(lang)
        let today: [(TaskType, String, Int, Bool)] = index % 2 == 0
            ? [(.vocabulary, L("Café & restaurant words"), 6, false), (.roleplay, c.scene, 8, false)]
            : [(.grammar, c.grammar, 7, true), (.listening, L("Short dialogue at the counter"), 6, false)]
        let raw: [(String, [(TaskType, String, Int, Bool)])] = [
            (L("Vocabulary & listening"), [(.vocabulary, L("Everyday phrases"), 6, false), (.listening, L("Ordering at the counter"), 5, false)]),
            (L("Grammar & writing"), [(.grammar, c.grammar, 7, false), (.writing, L("Describe your usual order"), 5, false)]),
            (L("Reading & speaking"), [(.reading, L("A neighbourhood café"), 6, false), (.speaking, L("Shadow a native speaker"), 6, false)]),
            (L("Roleplay"), [(.roleplay, L("Asking for directions"), 10, false)]),
            (L("Mixed practice · adjusted"), today),
            (L("Reading & culture"), [(.reading, L("Local food markets"), 8, false), (.vocabulary, L("New verbs · 10 cards"), 5, false)]),
            (L("Weekly check-in"), [(.grammar, L("Mixed quiz"), 8, false), (.roleplay, L("Free conversation with a friend"), 8, false)])
        ]
        // Rotate so the "adjusted" mixed day lands on today.
        let todayIdx = DateUtil.weekdayIndex(Date())
        let rotated = (0..<7).map { raw[($0 - todayIdx + 4 + 7) % 7] }
        let days = rotated.enumerated().map { di, d in
            PlanDay(focus: d.0, tasks: d.1.enumerated().map { ti, t in
                PlanTask(id: "\(lang.key)-\(di)-\(ti)", langKey: lang.key, type: t.0, title: t.1, minutes: t.2, adapted: t.3)
            })
        }
        let g = goals.prefix(2).map { L($0).lowercased() }.joined(separator: L(" and "))
        return WeeklyPlan(langKey: lang.key, weekStart: weekStart, days: days,
                          rationale: L("You chose %@, so most of your %@ time goes to listening and speaking. %@ is spaced out so it sticks.",
                                       g.isEmpty ? L("general practice") : g, lang.name, c.grammar),
                          generatedByAI: false)
    }
}

enum DateUtil {
    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        c.timeZone = .current
        return c
    }

    /// Monday = 0 … Sunday = 6
    static func weekdayIndex(_ d: Date) -> Int { (calendar.component(.weekday, from: d) + 5) % 7 }

    static func weekStart(_ d: Date = Date()) -> Date {
        let start = calendar.startOfDay(for: d)
        return calendar.date(byAdding: .day, value: -weekdayIndex(d), to: start) ?? start
    }

    static func dayKey(_ d: Date = Date()) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    /// "yyyy-MM-dd" → noon that day (safe across time zones).
    static func date(_ key: String) -> Date {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: key).flatMap { calendar.date(byAdding: .hour, value: 12, to: $0) } ?? Date()
    }

    static func format(_ d: Date, _ template: String) -> String {
        let f = DateFormatter()
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate(template)
        return f.string(from: d)
    }

    /// Localized short weekday names, Monday first.
    static var shortDays: [String] {
        var c = Calendar.current
        c.locale = .current
        let s = c.shortWeekdaySymbols           // Sunday first
        return Array(s[1...]) + [s[0]]
    }
}
