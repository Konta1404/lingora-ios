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
        "es": .init(grammar: "Ser vs. estar", scene: "Ordering tapas in Madrid",
                    lesson: .init(card: .init(front: "la cuenta", back: "the bill", example: "La cuenta, por favor."),
                                  question: .init(prompt: "Mi hermana ___ cansada hoy.", options: ["es", "está", "son", "ser"], answer: 1, why: "Temporary states use estar."),
                                  writing: .init(prompt: "Translate: “I would like a coffee, please.”", modelAnswer: "Quisiera un café, por favor.")),
                    tutorOpener: "¡Hola! ¿Qué te pongo?",
                    replies: ["Muy bien. ¿Para tomar aquí o para llevar?", "Son 6,50 euros. ¿Algo más?", "¡Perfecto! Que aproveche."],
                    suggestions: ["Agua con gas, por favor.", "¿Qué me recomienda?", "¿Puedo pagar con tarjeta?"]),
        "it": .init(grammar: "Partitive articles", scene: "Ordering at a bar in Rome",
                    lesson: .init(card: .init(front: "il conto", back: "the bill", example: "Il conto, per favore."),
                                  question: .init(prompt: "Vorrei ___ pane, per favore.", options: ["del", "dello", "della", "dei"], answer: 0, why: "Pane is masculine and starts with a consonant, so del."),
                                  writing: .init(prompt: "Translate: “I would like a coffee, please.”", modelAnswer: "Vorrei un caffè, per favore.")),
                    tutorOpener: "Buongiorno! Cosa prende?",
                    replies: ["Ottimo. Desidera anche un cornetto?", "Sono 3 euro. Paga alla cassa, grazie.", "Perfetto, buona giornata!"],
                    suggestions: ["Al banco, grazie.", "Cosa mi consiglia?", "Posso pagare con la carta?"]),
        "ja": .init(grammar: "Particles を and が", scene: "Ordering at a Tokyo café",
                    lesson: .init(card: .init(front: "お会計", back: "the bill", example: "お会計お願いします。"),
                                  question: .init(prompt: "コーヒー＿ください。", options: ["を", "が", "に", "で"], answer: 0, why: "を marks the thing you are asking for."),
                                  writing: .init(prompt: "Translate: “A coffee, please.”", modelAnswer: "コーヒーをください。")),
                    tutorOpener: "いらっしゃいませ！ご注文は？",
                    replies: ["ご一緒にケーキはいかがですか？", "500円です。", "ありがとうございました！"],
                    suggestions: ["ホットでお願いします。", "おすすめは何ですか？", "カードで払えますか？"]),
        "de": .init(grammar: "Dative articles", scene: "Ordering at a café in Berlin",
                    lesson: .init(card: .init(front: "die Rechnung", back: "the bill", example: "Die Rechnung, bitte."),
                                  question: .init(prompt: "Ich gebe ___ Kellner das Trinkgeld.", options: ["der", "dem", "den", "des"], answer: 1, why: "“geben” takes the dative: der Kellner → dem Kellner."),
                                  writing: .init(prompt: "Translate: “I would like a coffee, please.”", modelAnswer: "Ich hätte gern einen Kaffee, bitte.")),
                    tutorOpener: "Guten Morgen! Was darf es sein?",
                    replies: ["Sehr gut! Möchten Sie auch etwas essen?", "Das macht 4,20 Euro.", "Einen schönen Tag noch!"],
                    suggestions: ["Mit Milch, bitte.", "Was empfehlen Sie?", "Kann ich mit Karte zahlen?"])
    ]

    static func forLanguage(_ l: Language) -> LanguageContent {
        if let c = builtIn[l.key] { return c }
        let others = ["Merci", "Danke", "Gracias"].filter { $0 != l.thanks }.prefix(2)
        return .init(grammar: "Basic sentence order", scene: "Introducing yourself",
                     lesson: .init(card: .init(front: l.hello, back: "hello", example: "\(l.hello)! — the everyday greeting."),
                                   question: .init(prompt: "How do you say “thank you” in \(l.name)?", options: [l.hello, l.thanks] + others, answer: 1, why: "\(l.thanks) is the everyday way to say thanks."),
                                   writing: .init(prompt: "Write “Good morning, how are you?” in \(l.name).", modelAnswer: "ChatGPT checks your answer and suggests a natural version.")),
                     tutorOpener: "\(l.hello)! Let’s practise \(l.name). Tell me a little about yourself.",
                     replies: ["Great start — tell me more.", "Nice! What do you do for work?", "Lovely. Let’s keep going tomorrow."],
                     suggestions: [l.hello, l.thanks, "How do I say…?"])
    }
}

enum SampleFriends {
    static let friends: [Friend] = [
        .init(id: "yuki", name: "Yuki Tanaka", handle: "@yuki_t", langs: ["en"], streak: 54, weekMinutes: 210, practisedToday: true, hue: 340, chatLang: "en"),
        .init(id: "marco", name: "Marco Rossi", handle: "@marco", langs: ["es", "ja"], streak: 31, weekMinutes: 186, practisedToday: true, hue: 110, chatLang: "es"),
        .init(id: "lena", name: "Lena Weber", handle: "@lena.w", langs: ["it"], streak: 24, weekMinutes: 142, practisedToday: true, hue: 20, chatLang: "it"),
        .init(id: "sam", name: "Sam Okafor", handle: "@samo", langs: ["es"], streak: 9, weekMinutes: 98, practisedToday: false, hue: 240, chatLang: "es"),
        .init(id: "priya", name: "Priya Shah", handle: "@priya", langs: ["fr", "es"], streak: 4, weekMinutes: 64, practisedToday: false, hue: 300, chatLang: "fr")
    ]

    struct Suggested: Identifiable { var id: String; var name: String; var handle: String; var sub: String; var hue: Double }
    static let suggested: [Suggested] = [
        .init(id: "noah", name: "Noah Berg", handle: "@noahb", sub: "learning Spanish", hue: 200),
        .init(id: "mia", name: "Mia Costa", handle: "@miac", sub: "3 mutual friends", hue: 60),
        .init(id: "omar", name: "Omar Haddad", handle: "@omar.h", sub: "learning Japanese", hue: 160)
    ]

    struct FeedItem: Identifiable { var id: String; var friendID: String; var text: String; var time: String; var cheers: Int; var isPlan: Bool }
    static let feed: [FeedItem] = [
        .init(id: "lena0", friendID: "lena", text: "finished a roleplay in Italian: “Ordering at a bar in Rome”", time: "12 min ago", cheers: 3, isPlan: false),
        .init(id: "yuki1", friendID: "yuki", text: "reached a 54-day streak", time: "1 h ago", cheers: 8, isPlan: false),
        .init(id: "marco2", friendID: "marco", text: "shared a plan: Spanish for travel · 4 weeks", time: "3 h ago", cheers: 2, isPlan: true),
        .init(id: "sam3", friendID: "sam", text: "completed 3 ser vs. estar drills", time: "Yesterday", cheers: 1, isPlan: false)
    ]

    struct ChatSeed { var seed: [ChatMessage]; var replies: [String]; var suggestion: String }
    static let chats: [String: ChatSeed] = [
        "it": .init(seed: [.init(role: .them, text: "Ciao Ana! Com’è andata la giornata?"),
                           .init(role: .me, text: "Ciao! È stato bene, ho lavorato molto."),
                           .init(role: .correction, wrong: "È stato bene", right: "È andata bene", note: "“Andare” fits better for how a day went."),
                           .init(role: .them, text: "Anche io! Stasera guardo un film italiano.")],
                    replies: ["Che bello! Quale film?", "Domani facciamo la sfida dei 20 minuti?", "A domani, buona serata!"],
                    suggestion: "Che film guardi? Io adoro Fellini."),
        "es": .init(seed: [.init(role: .them, text: "¡Hola! ¿Practicamos un poco?"),
                           .init(role: .me, text: "¡Sí! Hoy soy muy cansada."),
                           .init(role: .correction, wrong: "soy muy cansada", right: "estoy muy cansada", note: "Temporary states use estar."),
                           .init(role: .them, text: "Jaja, yo también. ¿Qué hiciste hoy?")],
                    replies: ["¡Qué bien! Cuéntame más.", "¿Hacemos el reto de 20 minutos mañana?", "¡Hasta mañana!"],
                    suggestion: "Fui al mercado y compré fruta."),
        "en": .init(seed: [.init(role: .them, text: "Hi! Shall we practise some English?"),
                           .init(role: .me, text: "Yes! I am learning since two years."),
                           .init(role: .correction, wrong: "I am learning since two years", right: "I’ve been learning for two years", note: "Use the present perfect continuous + “for”."),
                           .init(role: .them, text: "Nice! What got you started?")],
                    replies: ["Love that. Tell me more!", "Up for the 20-minute challenge tomorrow?", "Talk tomorrow!"],
                    suggestion: "A trip to London, actually!"),
        "fr": .init(seed: [.init(role: .them, text: "Salut ! On pratique un peu ?"),
                           .init(role: .me, text: "Oui ! Je suis allé au marché hier."),
                           .init(role: .correction, wrong: "Je suis allé", right: "Je suis allée", note: "The participle agrees with a female subject."),
                           .init(role: .them, text: "Super ! Qu’est-ce que tu as acheté ?")],
                    replies: ["Génial, raconte-moi !", "On fait le défi des 20 minutes demain ?", "À demain !"],
                    suggestion: "J’ai acheté des fruits et du fromage.")
    ]
}

/// Offline weekly plan, used when ChatGPT isn't connected or a request fails.
enum FallbackPlanner {
    static func plan(for lang: Language, index: Int, weekStart: Date, goals: [String]) -> WeeklyPlan {
        let c = LanguageContent.forLanguage(lang)
        let today: [(TaskType, String, Int, Bool)] = index % 2 == 0
            ? [(.vocabulary, "Café & restaurant words", 6, false), (.roleplay, c.scene, 8, false)]
            : [(.grammar, c.grammar, 7, true), (.listening, "Short dialogue at the counter", 6, false)]
        let raw: [(String, [(TaskType, String, Int, Bool)])] = [
            ("Vocabulary & listening", [(.vocabulary, "Everyday phrases", 6, false), (.listening, "Ordering at the counter", 5, false)]),
            ("Grammar & writing", [(.grammar, c.grammar, 7, false), (.writing, "Describe your usual order", 5, false)]),
            ("Reading & speaking", [(.reading, "A neighbourhood café", 6, false), (.speaking, "Shadow a native speaker", 6, false)]),
            ("Roleplay", [(.roleplay, "Asking for directions", 10, false)]),
            ("Mixed practice · adjusted", today),
            ("Reading & culture", [(.reading, "Local food markets", 8, false), (.vocabulary, "New verbs · 10 cards", 5, false)]),
            ("Weekly check-in", [(.grammar, "Mixed quiz", 8, false), (.roleplay, "Free conversation with a friend", 8, false)])
        ]
        // Rotate so the "adjusted" mixed day lands on today.
        let todayIdx = DateUtil.weekdayIndex(Date())
        let rotated = (0..<7).map { raw[($0 - todayIdx + 4 + 7) % 7] }
        let days = rotated.enumerated().map { di, d in
            PlanDay(focus: d.0, tasks: d.1.enumerated().map { ti, t in
                PlanTask(id: "\(lang.key)-\(di)-\(ti)", langKey: lang.key, type: t.0, title: t.1, minutes: t.2, adapted: t.3)
            })
        }
        let g = goals.prefix(2).joined(separator: " and ").lowercased()
        return WeeklyPlan(langKey: lang.key, weekStart: weekStart, days: days,
                          rationale: "You chose \(g.isEmpty ? "general practice" : g), so most of your \(lang.name) time goes to listening and speaking. \(c.grammar) is spaced out so it sticks.",
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

    static func format(_ d: Date, _ template: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.setLocalizedDateFormatFromTemplate(template)
        return f.string(from: d)
    }

    static let shortDays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
}
