import Foundation

enum AuthMethod: String, Codable {
    case openai, apple, google, email, local
    var label: String {
        switch self {
        case .openai: "ChatGPT"
        case .apple: "Apple"
        case .google: "Google"
        case .email: L("Email & password")
        case .local: L("This iPhone only")
        }
    }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = AuthMethod(rawValue: raw == "chatgpt" ? "openai" : raw) ?? .local
    }
}

struct UserProfile: Codable, Equatable {
    var uid: String? = nil
    var name: String
    var email: String
    var handle: String
    var authMethod: AuthMethod
    var appleUserID: String?

    var firstName: String { name.split(separator: " ").first.map(String.init) ?? name }
    var initial: String { String(name.first ?? "A").uppercased() }
}

struct Language: Codable, Hashable, Identifiable {
    var key: String        // ISO code or "x-<slug>" for custom languages
    var code: String       // Two-letter badge
    var name: String
    var native: String
    var hello: String
    var thanks: String
    var hue: Double
    var isCustom: Bool = false
    var id: String { key }
}

enum Level: Int, Codable, CaseIterable, Identifiable {
    case a1, a2, b1, b2, c1
    var id: Int { rawValue }
    var code: String { ["A1", "A2", "B1", "B2", "C1"][rawValue] }
    var label: String { [L("Beginner"), L("Elementary"), L("Intermediate"), L("Upper-intermediate"), L("Advanced")][rawValue] }
    var next: Level { Level(rawValue: min(rawValue + 1, 4)) ?? .c1 }
}

enum TaskType: String, Codable, CaseIterable {
    case vocabulary, listening, speaking, reading, writing, grammar, roleplay
    var label: String {
        switch self {
        case .vocabulary: L("Vocabulary")
        case .listening: L("Listening")
        case .speaking: L("Speaking")
        case .reading: L("Reading")
        case .writing: L("Writing")
        case .grammar: L("Grammar")
        case .roleplay: L("Roleplay")
        }
    }
}

struct PlanTask: Codable, Hashable, Identifiable {
    var id: String
    var langKey: String
    var type: TaskType
    var title: String
    var minutes: Int
    var adapted: Bool = false
}

struct PlanDay: Codable, Hashable {
    var focus: String
    var tasks: [PlanTask]
}

struct WeeklyPlan: Codable, Hashable {
    var langKey: String
    var weekStart: Date       // Monday 00:00 of the plan's week
    var days: [PlanDay]       // 7 entries, Monday first
    var rationale: String
    var generatedByAI: Bool
}

struct ChatMessage: Codable, Identifiable, Hashable {
    enum Role: String, Codable { case ai, me, them, correction }
    var id = UUID()
    var role: Role
    var text: String = ""
    var wrong: String? = nil
    var right: String? = nil
    var note: String? = nil
}

struct LessonContent: Codable, Hashable {
    struct Card: Codable, Hashable { var front: String; var back: String; var example: String }
    struct Question: Codable, Hashable { var prompt: String; var options: [String]; var answer: Int; var why: String }
    struct Writing: Codable, Hashable { var prompt: String; var modelAnswer: String }
    var card: Card
    var question: Question
    var writing: Writing
}

struct TaskResult: Codable, Hashable {
    var taskID: String
    var langKey: String
    var title: String
    var type: TaskType
    var score: Int          // 0–3
    var date: Date
}

struct AppSettings: Codable, Equatable {
    var adaptDaily = true
    var reminders = true
    var accent: Accent = .sage
    var direction: Direction = .cards
    var languageTints = true
    /// Friends see my feed, streak and minutes.
    var shareActivity = true
    /// Notify me about new messages, friend requests and nudges.
    var notifyMessages = true
    var appearance: Appearance = .system
    /// Speaking exercises in course lessons ("Can't speak now" turns them off).
    var speakingExercises = true

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        func v<T: Decodable>(_ k: CodingKeys, _ fallback: T) -> T { (try? c.decodeIfPresent(T.self, forKey: k)) ?? fallback }
        adaptDaily = v(.adaptDaily, d.adaptDaily)
        reminders = v(.reminders, d.reminders)
        accent = v(.accent, d.accent)
        direction = v(.direction, d.direction)
        languageTints = v(.languageTints, d.languageTints)
        shareActivity = v(.shareActivity, d.shareActivity)
        notifyMessages = v(.notifyMessages, d.notifyMessages)
        appearance = v(.appearance, d.appearance)
        speakingExercises = v(.speakingExercises, d.speakingExercises)
    }
}

/// Everything the app persists between launches.
struct PersistedState: Codable {
    var user: UserProfile?
    var onboarded = false
    var learning: [String] = []
    var customLanguages: [String: Language] = [:]
    var levels: [String: Level] = [:]
    var goals: [String] = ["Travel", "Conversation"]
    var dailyMinutes = 30
    var plans: [String: WeeklyPlan] = [:]
    var done: [String: Bool] = [:]               // "yyyy-MM-dd|taskID"
    var results: [TaskResult] = []
    var adaptNote: String? = nil
    var adaptedOn: String? = nil                  // "yyyy-MM-dd"
    var tutorThreads: [String: [ChatMessage]] = [:]
    /// Seconds practised per day ("yyyy-MM-dd"). Streaks and weekly minutes come from this.
    var activity: [String: Int] = [:]
    /// Progress points per language toward the next level.
    var xp: [String: Int] = [:]
    /// Finished course lessons ("<unit id>#<lesson kind>").
    var courseDone: Set<String> = []
    var settings = AppSettings()

    init() {}

    /// Decodes whatever is present so older saves (and cloud copies) never wipe progress.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PersistedState()
        func v<T: Decodable>(_ k: CodingKeys, _ fallback: T) -> T { (try? c.decodeIfPresent(T.self, forKey: k)) ?? fallback }
        user = (try? c.decodeIfPresent(UserProfile.self, forKey: .user)) ?? nil
        onboarded = v(.onboarded, d.onboarded)
        learning = v(.learning, d.learning)
        customLanguages = v(.customLanguages, d.customLanguages)
        levels = v(.levels, d.levels)
        goals = v(.goals, d.goals)
        dailyMinutes = v(.dailyMinutes, d.dailyMinutes)
        plans = v(.plans, d.plans)
        done = v(.done, d.done)
        results = v(.results, d.results)
        adaptNote = (try? c.decodeIfPresent(String.self, forKey: .adaptNote)) ?? nil
        adaptedOn = (try? c.decodeIfPresent(String.self, forKey: .adaptedOn)) ?? nil
        tutorThreads = v(.tutorThreads, d.tutorThreads)
        activity = v(.activity, d.activity)
        xp = v(.xp, d.xp)
        courseDone = v(.courseDone, d.courseDone)
        settings = v(.settings, d.settings)
    }
}

/// Streaks, minutes and level progress, all derived from what the learner actually did.
enum Progress {
    /// Points needed to move from one level to the next.
    static let pointsPerLevel = 600

    static func streak(_ activity: [String: Int], today: Date = Date()) -> Int {
        let cal = DateUtil.calendar
        var d = cal.startOfDay(for: today)
        if (activity[DateUtil.dayKey(d)] ?? 0) < 60 { d = cal.date(byAdding: .day, value: -1, to: d) ?? d }
        var n = 0
        while (activity[DateUtil.dayKey(d)] ?? 0) >= 60 {
            n += 1
            d = cal.date(byAdding: .day, value: -1, to: d) ?? d
        }
        return n
    }

    static func minutes(_ activity: [String: Int], since start: Date, until end: Date = Date()) -> Int {
        let from = DateUtil.dayKey(start), to = DateUtil.dayKey(end)
        return activity.filter { $0.key >= from && $0.key <= to }.values.reduce(0, +) / 60
    }

    /// Minutes per day for the server (recent days only).
    static func recentMinutes(_ activity: [String: Int], days: Int = 8) -> [String: Int] {
        let cal = DateUtil.calendar
        var out: [String: Int] = [:]
        for i in 0..<days {
            guard let d = cal.date(byAdding: .day, value: -i, to: Date()) else { continue }
            let k = DateUtil.dayKey(d)
            if let s = activity[k], s > 0 { out[k] = s / 60 }
        }
        return out
    }
}
