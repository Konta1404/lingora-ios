import Foundation

/// Talks to the OpenAI Chat Completions API using Structured Outputs (strict JSON schemas).
///
/// For this first build the app calls OpenAI directly with a key the user enters (kept in the Keychain).
/// Before shipping to the App Store, move these calls behind your own backend so no key lives on device.
struct OpenAIService {
    enum AIError: LocalizedError {
        case noKey, http(Int, String), refusal(String), badResponse
        var errorDescription: String? {
            switch self {
            case .noKey: "ChatGPT isn't connected."
            case .http(let code, let msg): "OpenAI returned \(code): \(msg)"
            case .refusal(let r): r
            case .badResponse: "Unexpected response from OpenAI."
            }
        }
    }

    var apiKey: String?
    var model: String
    private let base = URL(string: "https://api.openai.com/v1")!

    init(apiKey: String?, model: String) {
        self.apiKey = apiKey
        self.model = model
    }

    // MARK: Public API

    func validate(key: String) async throws {
        var req = URLRequest(url: base.appendingPathComponent("models"))
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 20
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw AIError.http(code, Self.message(from: data)) }
    }

    struct AIPlan: Decodable {
        struct Day: Decodable { var focus: String; var tasks: [AITask] }
        var rationale: String
        var days: [Day]
    }
    struct AITask: Decodable { var type: TaskType; var title: String; var minutes: Int }

    func weeklyPlan(language: Language, level: Level, goals: [String], minutesPerDay: Int, todayIndex: Int) async throws -> AIPlan {
        let schema = obj([
            "rationale": str("2 sentences, addressed to the learner, explaining why the week looks like this."),
            "days": arr(obj([
                "focus": str("Short focus label, e.g. 'Grammar & writing'."),
                "tasks": arr(taskSchema(adapted: false), min: 1, max: 3)
            ]), min: 7, max: 7)
        ])
        let user = """
        Build a 7-day study plan (Monday first) for \(language.name)\(language.isCustom ? " (a language the learner typed in themselves)" : "").
        Level: \(level.code) \(level.label). Goals: \(goals.joined(separator: ", ")).
        Time per day for this language: about \(minutesPerDay) minutes in total, split into 1–3 tasks.
        Today is day \(todayIndex + 1) of the week. Mix vocabulary, listening, speaking, reading, writing, grammar and roleplay.
        Task titles are short and concrete (e.g. "Ordering tapas in Madrid", "Ser vs. estar"). Write titles in English.
        """
        return try await complete(name: "weekly_plan", schema: schema, system: Self.tone, user: user)
    }

    struct AIAdaptation: Decodable {
        struct Lang: Decodable { var key: String; var tasks: [AdaptedTask] }
        struct AdaptedTask: Decodable { var type: TaskType; var title: String; var minutes: Int; var adapted: Bool }
        var note: String
        var languages: [Lang]
    }

    func adaptToday(languages: [(Language, Level, [PlanTask])], recent: [TaskResult]) async throws -> AIAdaptation {
        let schema = obj([
            "note": str("One or two calm sentences explaining what changed today and why."),
            "languages": arr(obj([
                "key": str("The language key exactly as given."),
                "tasks": arr(taskSchema(adapted: true), min: 1, max: 3)
            ]))
        ])
        let langs = languages.map { item -> String in
            let (l, lv, tasks) = item
            return "- key \(l.key): \(l.name) \(lv.code). Planned today: " + tasks.map { "\($0.type.rawValue) '\($0.title)' \($0.minutes)m" }.joined(separator: "; ")
        }.joined(separator: "\n")
        let res = recent.suffix(12).map { "\($0.langKey) \($0.type.rawValue) '\($0.title)': \($0.score)/3" }.joined(separator: "\n")
        let user = """
        Adapt today's tasks to how the learner has been doing. Keep total minutes roughly the same.
        Only change what the results justify; mark changed or added tasks with adapted=true.
        Languages:
        \(langs)
        Recent results (score out of 3):
        \(res.isEmpty ? "none yet" : res)
        """
        return try await complete(name: "daily_adaptation", schema: schema, system: Self.tone, user: user)
    }

    func lesson(language: Language, level: Level, task: PlanTask) async throws -> LessonContent {
        let schema = obj([
            "card": obj([
                "front": str("A word or short phrase in \(language.name), native script."),
                "back": str("Its English meaning."),
                "example": str("A short example sentence in \(language.name).")
            ]),
            "question": obj([
                "prompt": str("A gap-fill sentence in \(language.name) with ___ for the gap, or a short question."),
                "options": arr(str("Answer option."), min: 4, max: 4),
                "answer": ["type": "integer", "description": "0-based index of the correct option."],
                "why": str("One-sentence explanation in English.")
            ]),
            "writing": obj([
                "prompt": str("A short writing task in English, e.g. Translate: “…”."),
                "modelAnswer": str("A natural model answer in \(language.name).")
            ])
        ])
        let user = """
        Create a 3-step micro-lesson for a \(level.code) learner of \(language.name).
        Task: \(task.type.label) — "\(task.title)" (\(task.minutes) min).
        Step 1 flashcard, step 2 a 4-option gap fill with exactly one correct answer, step 3 a one-sentence writing task.
        """
        return try await complete(name: "lesson", schema: schema, system: Self.tone, user: user)
    }

    struct WritingCheck: Decodable { var correct: Bool; var feedback: String; var modelAnswer: String }

    func checkWriting(language: Language, prompt: String, modelAnswer: String, answer: String) async throws -> WritingCheck {
        let schema = obj([
            "correct": ["type": "boolean"],
            "feedback": str("1–2 kind sentences in English: what was good, what to fix."),
            "modelAnswer": str("The most natural version in \(language.name), ideally close to the learner's own wording.")
        ])
        let user = """
        Language: \(language.name). Task: \(prompt)
        Reference answer: \(modelAnswer)
        Learner wrote: \(answer.isEmpty ? "(nothing)" : answer)
        """
        return try await complete(name: "writing_check", schema: schema, system: Self.tone, user: user)
    }

    struct TutorTurn: Decodable {
        var hasCorrection: Bool
        var wrong: String
        var right: String
        var note: String
        var reply: String
        var suggestions: [String]
    }

    func tutorTurn(language: Language, level: Level, scene: String, history: [ChatMessage]) async throws -> TutorTurn {
        let schema = obj([
            "hasCorrection": ["type": "boolean", "description": "True only if the learner's last message has a real mistake."],
            "wrong": str("The exact wrong fragment from the learner's last message, or empty."),
            "right": str("The corrected fragment, or empty."),
            "note": str("One short English explanation, or empty."),
            "reply": str("Your next in-character line in \(language.name), suited to \(level.code)."),
            "suggestions": arr(str("A short reply the learner could send next, in \(language.name)."), min: 3, max: 3)
        ])
        let transcript = history.compactMap { m -> String? in
            switch m.role {
            case .ai: "Tutor: \(m.text)"
            case .me: "Learner: \(m.text)"
            default: nil
            }
        }.joined(separator: "\n")
        let user = """
        Roleplay scene: \(scene). You play the other person in the scene and stay in character in \(language.name).
        Learner level: \(level.code). Keep replies to one or two short sentences.
        Conversation so far:
        \(transcript)
        """
        return try await complete(name: "tutor_turn", schema: schema, system: Self.tone, user: user)
    }

    struct Correction: Decodable { var hasCorrection: Bool; var wrong: String; var right: String; var note: String }

    func correct(message: String, language: Language) async throws -> Correction {
        let schema = obj([
            "hasCorrection": ["type": "boolean"],
            "wrong": str("Exact wrong fragment, or empty."),
            "right": str("Corrected fragment, or empty."),
            "note": str("One short English explanation, or empty.")
        ])
        let user = "The learner sent this \(language.name) message to a friend: \"\(message)\". Point out at most one real mistake. Ignore style and punctuation."
        return try await complete(name: "correction", schema: schema, system: Self.tone, user: user)
    }

    // MARK: Plumbing

    private static let tone = """
    You are Lingora's language coach. Calm, encouraging, low-pressure. Never shame mistakes.
    Respond only with JSON that matches the schema.
    """

    private func complete<T: Decodable>(name: String, schema: [String: Any], system: String, user: String) async throws -> T {
        guard let apiKey, !apiKey.isEmpty else { throw AIError.noKey }
        var body: [String: Any] = [
            "model": model,
            "messages": [["role": "system", "content": system], ["role": "user", "content": user]],
            "response_format": ["type": "json_schema", "json_schema": ["name": name, "strict": true, "schema": schema]]
        ]
        if model.hasPrefix("gpt-5") || model.hasPrefix("o") { body["reasoning_effort"] = "low" }

        var req = URLRequest(url: base.appendingPathComponent("chat/completions"))
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 90
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw AIError.http(code, Self.message(from: data)) }

        let env = try JSONDecoder().decode(Envelope.self, from: data)
        guard let msg = env.choices.first?.message else { throw AIError.badResponse }
        if let r = msg.refusal { throw AIError.refusal(r) }
        guard let content = msg.content?.data(using: .utf8) else { throw AIError.badResponse }
        return try JSONDecoder().decode(T.self, from: content)
    }

    private struct Envelope: Decodable {
        struct Choice: Decodable {
            struct Msg: Decodable { var content: String?; var refusal: String? }
            var message: Msg
        }
        var choices: [Choice]
    }

    private static func message(from data: Data) -> String {
        struct E: Decodable { struct Inner: Decodable { var message: String }; var error: Inner }
        return (try? JSONDecoder().decode(E.self, from: data).error.message) ?? String(data: data, encoding: .utf8) ?? ""
    }

    // Schema helpers (strict mode: every property required, no extra properties).
    private func obj(_ props: [String: Any]) -> [String: Any] {
        ["type": "object", "properties": props, "required": Array(props.keys).sorted(), "additionalProperties": false]
    }
    private func str(_ d: String) -> [String: Any] { ["type": "string", "description": d] }
    private func arr(_ items: [String: Any], min: Int? = nil, max: Int? = nil) -> [String: Any] {
        // Counts go in the description: older models reject minItems/maxItems in strict mode.
        var a: [String: Any] = ["type": "array", "items": items]
        switch (min, max) {
        case let (lo?, hi?) where lo == hi: a["description"] = "Exactly \(lo) items."
        case let (lo?, hi?): a["description"] = "Between \(lo) and \(hi) items."
        default: break
        }
        return a
    }
    private func taskSchema(adapted: Bool) -> [String: Any] {
        var p: [String: Any] = [
            "type": ["type": "string", "enum": TaskType.allCases.map(\.rawValue)],
            "title": str("Short task title in English."),
            "minutes": ["type": "integer", "description": "Minutes, 4–15."]
        ]
        if adapted { p["adapted"] = ["type": "boolean"] }
        return obj(p)
    }
}
