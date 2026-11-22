import Foundation

/// ChatGPT features, served by Lingora's Firebase Cloud Functions (see backend/functions).
/// The OpenAI key lives only on the server; the app sends the user's language so replies come back in it.
struct AIService {
    struct AIPlan: Decodable {
        struct Day: Decodable { var focus: String; var tasks: [AITask] }
        var rationale: String
        var days: [Day]
    }
    struct AITask: Decodable { var type: TaskType; var title: String; var minutes: Int }

    struct AIAdaptation: Decodable {
        struct Lang: Decodable { var key: String; var tasks: [AdaptedTask] }
        struct AdaptedTask: Decodable { var type: TaskType; var title: String; var minutes: Int; var adapted: Bool }
        var note: String
        var languages: [Lang]
    }

    struct WritingCheck: Decodable { var correct: Bool; var feedback: String; var modelAnswer: String }

    struct TutorTurn: Decodable {
        var hasCorrection: Bool
        var wrong: String
        var right: String
        var note: String
        var reply: String
        var suggestions: [String]
    }

    struct Correction: Decodable { var hasCorrection: Bool; var wrong: String; var right: String; var note: String }

    struct Translations: Decodable { var language: String; var translations: [String: [String]] }
    struct TranslationCheck: Decodable { var correct: Bool; var note: String }

    private var ui: String { AppLocale.tag }

    private func lang(_ l: Language) -> [String: Any] {
        ["key": l.key, "name": l.name, "isCustom": l.isCustom]
    }

    func weeklyPlan(language: Language, level: Level, goals: [String], minutesPerDay: Int, todayIndex: Int) async throws -> AIPlan {
        try await Backend.call("weeklyPlan", [
            "language": lang(language), "level": level.code, "goals": goals,
            "minutesPerDay": minutesPerDay, "todayIndex": todayIndex, "uiLanguage": ui
        ])
    }

    func adaptToday(languages: [(Language, Level, [PlanTask])], recent: [TaskResult]) async throws -> AIAdaptation {
        try await Backend.call("adaptToday", [
            "languages": languages.map { item -> [String: Any] in
                let (l, lv, tasks) = item
                return ["key": l.key, "name": l.name, "level": lv.code,
                        "tasks": tasks.map { ["type": $0.type.rawValue, "title": $0.title, "minutes": $0.minutes] }]
            },
            "recent": recent.suffix(12).map { ["langKey": $0.langKey, "type": $0.type.rawValue, "title": $0.title, "score": $0.score] },
            "uiLanguage": ui
        ])
    }

    func lesson(language: Language, level: Level, task: PlanTask) async throws -> LessonContent {
        try await Backend.call("lesson", [
            "language": lang(language), "level": level.code,
            "task": ["type": task.type.rawValue, "title": task.title, "minutes": task.minutes], "uiLanguage": ui
        ])
    }

    func checkWriting(language: Language, prompt: String, modelAnswer: String, answer: String) async throws -> WritingCheck {
        try await Backend.call("checkWriting", [
            "language": lang(language), "prompt": prompt, "modelAnswer": modelAnswer, "answer": answer, "uiLanguage": ui
        ])
    }

    func tutorTurn(language: Language, level: Level, scene: String, history: [ChatMessage]) async throws -> TutorTurn {
        try await Backend.call("tutorTurn", [
            "language": lang(language), "level": level.code, "scene": scene,
            "history": history.filter { $0.role == .ai || $0.role == .me }.map { ["role": $0.role.rawValue, "text": $0.text] },
            "uiLanguage": ui
        ])
    }

    func correct(message: String, language: Language) async throws -> Correction {
        try await Backend.call("correctMessage", ["language": lang(language), "message": message, "uiLanguage": ui])
    }

    func translateWords(ids: [String]) async throws -> Translations {
        try await Backend.call("translateWords", ["ids": ids, "targetLanguage": ui])
    }

    func checkTranslation(id: String, answer: String, accepted: [String]) async throws -> TranslationCheck {
        try await Backend.call("checkTranslation", ["id": id, "answer": answer, "accepted": accepted, "targetLanguage": ui])
    }
}
