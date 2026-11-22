import Foundation

/// ChatGPT features, served by Lingora's Firebase Cloud Functions (lingora-backend).
/// They run on the user's own ChatGPT plan (Sign in with ChatGPT); the app sends the user's language
/// so replies come back in it.
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
        var remember: String?
    }

    struct Correction: Decodable { var hasCorrection: Bool; var wrong: String; var right: String; var note: String }

    struct Translations: Decodable { var language: String; var translations: [String: [String]] }
    struct TranslationCheck: Decodable { var correct: Bool; var note: String }

    struct ChatGPTStatus: Decodable, Equatable { var connected: Bool; var email: String?; var model: String? }

    /// Next course unit (words + sentences), written by ChatGPT or taken from the shared cache.
    func courseUnit(language: Language, level: Level, topic: String, topicId: String) async throws -> CourseUnit {
        try await Backend.call("courseUnit", [
            "language": ["name": language.name, "key": language.key, "isCustom": language.isCustom],
            "level": level.code, "topic": topic, "topicId": topicId, "uiLanguage": AppLocale.tag,
        ])
    }

    func chatGPTStatus() async throws -> ChatGPTStatus { try await Backend.call("chatgptStatus", [:]) }
    func disconnectChatGPT() async throws -> ChatGPTStatus { try await Backend.call("chatgptDisconnect", [:]) }

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

    func tutorTurn(language: Language, level: Level, scene: String, history: [ChatMessage], memory: [String] = []) async throws -> TutorTurn {
        try await Backend.call("tutorTurn", [
            "language": lang(language), "level": level.code, "scene": scene,
            "history": history.filter { $0.role == .ai || $0.role == .me }.map { ["role": $0.role.rawValue, "text": $0.text] },
            "memory": memory,
            "uiLanguage": ui
        ])
    }

    struct Explanation: Decodable { var explanation: String }
    func explainAnswer(language: Language, task: String, prompt: String, expected: String, answer: String) async throws -> String {
        let r: Explanation = try await Backend.call("explainAnswer", [
            "language": lang(language), "task": task, "prompt": prompt, "expected": expected, "answer": answer, "uiLanguage": ui
        ])
        return r.explanation
    }

    struct CallFeedback: Decodable {
        struct Fix: Decodable, Hashable { var wrong: String; var right: String; var note: String }
        var summary: String
        var strengths: [String]
        var fixes: [Fix]
    }
    func callFeedback(language: Language, level: Level, history: [ChatMessage]) async throws -> CallFeedback {
        try await Backend.call("callFeedback", [
            "language": lang(language), "level": level.code,
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
