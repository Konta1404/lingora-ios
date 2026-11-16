import SwiftUI
import Combine
import AuthenticationServices
import UserNotifications

enum AppTab: Hashable { case today, plan, tutor, friends, me }

enum OnboardingStep: Hashable {
    case email(login: Bool)
    case connect
    case languages
    case levels
    case plan
}

enum MeRoute: Hashable { case addLanguage, addLevels }

@MainActor
final class AppModel: ObservableObject {
    @Published var s: PersistedState
    @Published var apiKey: String?

    // Navigation
    @Published var tab: AppTab = .today
    @Published var onboardingPath: [OnboardingStep] = []
    @Published var mePath: [MeRoute] = []
    @Published var friendsPath: [String] = []          // friend ids
    @Published var planLang: String?
    @Published var tutorLang: String?
    @Published var lessonTask: PlanTask?
    @Published var showAddFriend = false

    // Plan generation
    @Published var generating = false
    @Published var planStep = 0
    @Published var planNotice: String?

    // Chat
    @Published var tutorTyping = false
    @Published var tutorSuggestions: [String: [String]] = [:]
    @Published var friendTyping = false
    @Published var toast: String?

    // Lessons
    @Published var lessonCache: [String: LessonContent] = [:]

    private var replyIndex = 0
    private var friendReplyIndex = 0
    private var bag = Set<AnyCancellable>()
    private var adaptInFlight = false

    nonisolated private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("lingora-state.json")
    }

    init() {
        if let data = try? Data(contentsOf: Self.fileURL),
           let saved = try? JSONDecoder().decode(PersistedState.self, from: data) {
            s = saved
        } else {
            s = PersistedState()
        }
        apiKey = Keychain.get("openai")
        $s.dropFirst()
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { state in
                if let data = try? JSONEncoder().encode(state) { try? data.write(to: Self.fileURL, options: .atomic) }
            }
            .store(in: &bag)
    }

    // MARK: - Derived

    var theme: Theme { Theme(accent: s.settings.accent, direction: s.settings.direction, languageTints: s.settings.languageTints) }
    var connected: Bool { !(apiKey ?? "").isEmpty }
    var ai: OpenAIService { OpenAIService(apiKey: apiKey, model: s.settings.model) }

    func language(_ key: String) -> Language? { Catalog.byKey[key] ?? s.customLanguages[key] }
    var languages: [Language] { s.learning.compactMap(language) }
    func level(_ key: String) -> Level { s.levels[key] ?? .a1 }
    func hue(_ l: Language) -> Hue { theme.colors(for: l.hue) }
    func content(_ key: String) -> LanguageContent {
        LanguageContent.forLanguage(language(key) ?? Catalog.byKey["es"]!)
    }

    var todayIndex: Int { DateUtil.weekdayIndex(Date()) }
    var planIsStale: Bool {
        let ws = DateUtil.weekStart()
        return s.plans.values.contains { !DateUtil.calendar.isDate($0.weekStart, inSameDayAs: ws) }
    }

    var todayTasks: [PlanTask] {
        s.learning.flatMap { key in s.plans[key]?.days[safe: todayIndex]?.tasks ?? [] }
    }

    func isDone(_ t: PlanTask) -> Bool { s.done["\(DateUtil.dayKey())|\(t.id)"] == true }

    var doneMinutesToday: Int { todayTasks.filter(isDone).reduce(0) { $0 + $1.minutes } }
    var myWeekMinutes: Int { 131 + doneMinutesToday }

    var friends: [Friend] { SampleFriends.friends }
    func friend(_ id: String) -> Friend? { friends.first { $0.id == id } }

    // MARK: - Auth

    func signInWithEmail(name: String, email: String, login: Bool) {
        let n = name.trimmingCharacters(in: .whitespaces)
        let existing = s.user
        s.user = UserProfile(name: n.isEmpty ? (existing?.name ?? email.components(separatedBy: "@").first?.capitalized ?? "Friend") : n,
                             email: email.trimmingCharacters(in: .whitespaces),
                             handle: Self.handle(from: n.isEmpty ? email : n),
                             authMethod: .email)
        if login && !s.learning.isEmpty && !s.plans.isEmpty {
            s.onboarded = true
        } else {
            onboardingPath.append(connected ? .languages : .connect)
        }
    }

    func signInWithApple(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard let cred = auth.credential as? ASAuthorizationAppleIDCredential else { return }
            let name = [cred.fullName?.givenName, cred.fullName?.familyName].compactMap { $0 }.joined(separator: " ")
            let finalName = name.isEmpty ? (s.user?.name ?? "Friend") : name
            s.user = UserProfile(name: finalName,
                                 email: cred.email ?? s.user?.email ?? "Private relay",
                                 handle: Self.handle(from: finalName),
                                 authMethod: .apple,
                                 appleUserID: cred.user)
            onboardingPath.append(connected ? .languages : .connect)
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            toast = "Apple sign-in didn't work: \(error.localizedDescription)"
        }
    }

    /// Validates and stores the key. Used by both "Continue with ChatGPT" and "Connect ChatGPT".
    func connect(key: String) async throws {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        try await ai.validate(key: k)
        Keychain.set(k, for: "openai")
        apiKey = k
    }

    func signInWithChatGPT(name: String, key: String) async throws {
        try await connect(key: key)
        let n = name.trimmingCharacters(in: .whitespaces).isEmpty ? "Friend" : name.trimmingCharacters(in: .whitespaces)
        s.user = UserProfile(name: n, email: "Signed in with ChatGPT", handle: Self.handle(from: n), authMethod: .chatgpt)
        onboardingPath.append(.languages)
    }

    func disconnect() {
        Keychain.set(nil, for: "openai")
        apiKey = nil
    }

    func logOut() {
        disconnect()
        s = PersistedState()
        onboardingPath = []
        mePath = []
        friendsPath = []
        tab = .today
        lessonCache = [:]
    }

    private static func handle(from name: String) -> String {
        let parts = name.lowercased().split(separator: " ")
        guard let first = parts.first else { return "@you" }
        let last = parts.dropFirst().first.map { "." + String($0.prefix(1)) } ?? ""
        return "@" + first.filter { $0.isLetter || $0.isNumber } + last
    }

    // MARK: - Languages

    func toggle(_ key: String) {
        if let i = s.learning.firstIndex(of: key) { s.learning.remove(at: i) } else {
            s.learning.append(key)
            if s.levels[key] == nil { s.levels[key] = .a1 }
        }
        Haptics.tap()
    }

    func addCustom(_ query: String) {
        let name = query.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let key = "x-" + name.lowercased().split(separator: " ").joined(separator: "-")
        let nm = name.prefix(1).uppercased() + name.dropFirst()
        s.customLanguages[key] = Language(key: key, code: String(nm.prefix(2)).uppercased(), name: nm,
                                          native: "Taught by ChatGPT", hello: "Hello", thanks: "Thanks",
                                          hue: 270, isCustom: true)
        if !s.learning.contains(key) { s.learning.append(key) }
        s.levels[key] = s.levels[key] ?? .a1
    }

    // MARK: - Plans

    /// Builds plans for the given languages (all when nil). Runs the 4-step progress animation meanwhile.
    func buildPlans(only keys: [String]? = nil) async {
        let targets = (keys ?? s.learning).compactMap(language)
        guard !targets.isEmpty, !generating else { return }
        generating = true
        planStep = 0
        planNotice = nil

        let ticker = Task { @MainActor in
            for i in 1...3 {
                try? await Task.sleep(for: .milliseconds(700))
                if Task.isCancelled { return }
                self.planStep = max(self.planStep, i)
            }
        }

        let ws = DateUtil.weekStart()
        let perLang = max(5, s.dailyMinutes / max(1, s.learning.count))
        let goals = s.goals
        let levels = s.levels
        let svc = ai
        let today = todayIndex
        var results: [String: WeeklyPlan] = [:]
        var failed = false

        if connected {
            await withTaskGroup(of: (String, WeeklyPlan?).self) { group in
                for l in targets {
                    group.addTask {
                        do {
                            let p = try await svc.weeklyPlan(language: l, level: levels[l.key] ?? .a1, goals: goals,
                                                             minutesPerDay: perLang, todayIndex: today)
                            return (l.key, Self.convert(p, lang: l, weekStart: ws))
                        } catch {
                            return (l.key, nil)
                        }
                    }
                }
                for await (k, p) in group { if let p { results[k] = p } else { failed = true } }
            }
        }
        for (i, l) in targets.enumerated() where results[l.key] == nil {
            results[l.key] = FallbackPlanner.plan(for: l, index: i, weekStart: ws, goals: goals)
        }
        // Keep at least ~2.8s so the steps read calmly.
        await ticker.value
        for (k, p) in results { s.plans[k] = p }
        s.adaptedOn = nil
        s.adaptNote = nil
        if failed { planNotice = "ChatGPT couldn't be reached for some plans, so we used a standard plan for now." }
        planStep = 4
        try? await Task.sleep(for: .milliseconds(400))
        generating = false
        planLang = targets.first?.key
        Haptics.success()
    }

    nonisolated private static func convert(_ p: OpenAIService.AIPlan, lang: Language, weekStart: Date) -> WeeklyPlan {
        var days = p.days.prefix(7).enumerated().map { di, d in
            PlanDay(focus: d.focus, tasks: d.tasks.prefix(3).enumerated().map { ti, t in
                PlanTask(id: "\(lang.key)-\(di)-\(ti)", langKey: lang.key, type: t.type, title: t.title,
                         minutes: min(20, max(3, t.minutes)))
            })
        }
        while days.count < 7 { days.append(PlanDay(focus: "Rest & review", tasks: [])) }
        return WeeklyPlan(langKey: lang.key, weekStart: weekStart, days: Array(days), rationale: p.rationale, generatedByAI: true)
    }

    /// ChatGPT adapts today's tasks once a day, based on recent results.
    func adaptTodayIfNeeded() async {
        let today = DateUtil.dayKey()
        guard s.settings.adaptDaily, connected, s.adaptedOn != today, !adaptInFlight,
              !s.results.isEmpty, !s.plans.isEmpty, !planIsStale else { return }
        adaptInFlight = true
        defer { adaptInFlight = false }
        let idx = todayIndex
        let input = languages.map { ($0, level($0.key), s.plans[$0.key]?.days[safe: idx]?.tasks ?? []) }
        do {
            let out = try await ai.adaptToday(languages: input, recent: s.results)
            for lang in out.languages {
                guard var plan = s.plans[lang.key], plan.days.indices.contains(idx) else { continue }
                plan.days[idx].tasks = lang.tasks.prefix(3).enumerated().map { i, t in
                    PlanTask(id: "\(lang.key)-\(idx)-a\(i)", langKey: lang.key, type: t.type, title: t.title,
                             minutes: min(20, max(3, t.minutes)), adapted: t.adapted)
                }
                s.plans[lang.key] = plan
            }
            s.adaptNote = out.note
            s.adaptedOn = today
        } catch {
            // Quietly keep the planned tasks.
        }
    }

    // MARK: - Tasks & lessons

    func open(_ t: PlanTask) {
        if t.type == .roleplay {
            tutorLang = t.langKey
            tab = .tutor
        } else {
            lessonTask = t
        }
    }

    func complete(_ t: PlanTask, score: Int) {
        s.done["\(DateUtil.dayKey())|\(t.id)"] = true
        s.results.append(TaskResult(taskID: t.id, langKey: t.langKey, title: t.title, type: t.type, score: score, date: Date()))
        if s.results.count > 60 { s.results.removeFirst(s.results.count - 60) }
        Haptics.success()
    }

    func toggleDone(_ t: PlanTask) {
        let k = "\(DateUtil.dayKey())|\(t.id)"
        s.done[k] = s.done[k] == true ? nil : true
        Haptics.success()
    }

    func lessonContent(for t: PlanTask) async -> LessonContent {
        let cacheKey = "\(DateUtil.dayKey())|\(t.id)"
        if let c = lessonCache[cacheKey] { return c }
        let fallback = content(t.langKey).lesson
        guard connected, let l = language(t.langKey) else { return fallback }
        do {
            var c = try await ai.lesson(language: l, level: level(t.langKey), task: t)
            if c.question.options.count < 2 { return fallback }
            c.question.answer = min(max(0, c.question.answer), c.question.options.count - 1)
            lessonCache[cacheKey] = c
            return c
        } catch {
            toast = "ChatGPT couldn't prepare this lesson, so here's a standard one."
            return fallback
        }
    }

    func checkWriting(_ t: PlanTask, lesson: LessonContent, answer: String) async -> OpenAIService.WritingCheck {
        let offline = OpenAIService.WritingCheck(
            correct: false,
            feedback: answer.trimmingCharacters(in: .whitespaces).isEmpty
                ? "No worries — try saying it out loud once before moving on."
                : "Nice work. Compare word order with the model answer.",
            modelAnswer: lesson.writing.modelAnswer)
        guard connected, let l = language(t.langKey) else { return offline }
        do {
            return try await ai.checkWriting(language: l, prompt: lesson.writing.prompt,
                                             modelAnswer: lesson.writing.modelAnswer, answer: answer)
        } catch {
            return offline
        }
    }

    // MARK: - Tutor

    func tutorScene(_ key: String) -> String {
        if let rp = todayTasks.first(where: { $0.langKey == key && $0.type == .roleplay }) { return rp.title }
        return content(key).scene
    }

    func tutorMessages(_ key: String) -> [ChatMessage] {
        s.tutorThreads[key] ?? [ChatMessage(role: .ai, text: content(key).tutorOpener)]
    }

    func suggestions(_ key: String) -> [String] { tutorSuggestions[key] ?? content(key).suggestions }

    func resetTutor(_ key: String) {
        s.tutorThreads[key] = nil
        tutorSuggestions[key] = nil
    }

    func sendTutor(_ text: String, lang key: String) async {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !tutorTyping, let l = language(key) else { return }
        var msgs = tutorMessages(key)
        msgs.append(ChatMessage(role: .me, text: t))
        s.tutorThreads[key] = msgs
        tutorTyping = true
        defer { tutorTyping = false }

        if connected {
            do {
                let turn = try await ai.tutorTurn(language: l, level: level(key), scene: tutorScene(key), history: msgs)
                if turn.hasCorrection, !turn.right.isEmpty {
                    msgs.append(ChatMessage(role: .correction, wrong: turn.wrong, right: turn.right, note: turn.note))
                }
                msgs.append(ChatMessage(role: .ai, text: turn.reply))
                if !turn.suggestions.isEmpty { tutorSuggestions[key] = Array(turn.suggestions.prefix(3)) }
                s.tutorThreads[key] = msgs
                markRoleplayIfEarned(key)
                return
            } catch {
                toast = "ChatGPT didn't answer — \(error.localizedDescription)"
            }
        }
        try? await Task.sleep(for: .milliseconds(1100))
        let replies = content(key).replies
        msgs.append(ChatMessage(role: .ai, text: replies[replyIndex % replies.count]))
        replyIndex += 1
        s.tutorThreads[key] = msgs
        markRoleplayIfEarned(key)
    }

    /// Three replies in today's roleplay language count as finishing that roleplay.
    private func markRoleplayIfEarned(_ key: String) {
        let mine = (s.tutorThreads[key] ?? []).filter { $0.role == .me }.count
        guard mine >= 3, let rp = todayTasks.first(where: { $0.langKey == key && $0.type == .roleplay }), !isDone(rp) else { return }
        complete(rp, score: 3)
        toast = "Roleplay done — nicely handled."
    }

    // MARK: - Friends

    func friendMessages(_ id: String) -> [ChatMessage] {
        guard let f = friend(id) else { return [] }
        return s.friendThreads[id] ?? SampleFriends.chats[f.chatLang]?.seed ?? []
    }

    func sendFriend(_ text: String, to id: String) async {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !friendTyping, let f = friend(id), let seed = SampleFriends.chats[f.chatLang] else { return }
        var msgs = friendMessages(id)
        msgs.append(ChatMessage(role: .me, text: t))
        s.friendThreads[id] = msgs
        friendTyping = true
        defer { friendTyping = false }

        let svc: OpenAIService? = connected ? ai : nil
        let lang = language(f.chatLang)
        async let correction = Self.correction(svc, message: t, language: lang)
        try? await Task.sleep(for: .milliseconds(1400))
        if let c = await correction, c.hasCorrection, !c.right.isEmpty {
            msgs.append(ChatMessage(role: .correction, wrong: c.wrong, right: c.right, note: c.note))
        }
        msgs.append(ChatMessage(role: .them, text: seed.replies[friendReplyIndex % seed.replies.count]))
        friendReplyIndex += 1
        s.friendThreads[id] = msgs
    }

    nonisolated private static func correction(_ svc: OpenAIService?, message: String, language: Language?) async -> OpenAIService.Correction? {
        guard let svc, let language else { return nil }
        return try? await svc.correct(message: message, language: language)
    }

    func toggle(_ set: WritableKeyPath<PersistedState, Set<String>>, _ id: String) {
        if s[keyPath: set].contains(id) { s[keyPath: set].remove(id) } else { s[keyPath: set].insert(id) }
        Haptics.tap()
    }

    // MARK: - Reminders

    func setReminders(_ on: Bool) {
        s.settings.reminders = on
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["daily"])
        guard on else { return }
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "A calm ten minutes?"
            content.body = "Today's tasks are ready whenever you are."
            var comps = DateComponents()
            comps.hour = 19
            let req = UNNotificationRequest(identifier: "daily", content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: true))
            center.add(req)
        }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
