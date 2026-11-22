import SwiftUI
import Combine
import AuthenticationServices
import UserNotifications
import FirebaseAuth

enum AppTab: Hashable { case today, plan, tutor, friends, me }

enum OnboardingStep: Hashable {
    case email(login: Bool)
    case languages
    case levels
    case plan
}

enum MeRoute: Hashable { case addLanguage, addLevels }

@MainActor
final class AppModel: ObservableObject {
    @Published var s: PersistedState
    @Published var vocab: VocabProgressStore

    // Auth
    @Published var signedInUID: String?
    @Published var authBusy = false
    /// The user's own ChatGPT plan, connected through Sign in with ChatGPT.
    @Published var chatGPT: AIService.ChatGPTStatus?

    // Navigation
    @Published var tab: AppTab = .today
    @Published var onboardingPath: [OnboardingStep] = []
    @Published var mePath: [MeRoute] = []
    @Published var friendsPath: [String] = []          // friend ids
    @Published var planLang: String?
    @Published var tutorLang: String?
    @Published var lessonTask: PlanTask?
    @Published var showAddFriend = false
    @Published var showWords = false

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
    private var authHandle: AuthStateDidChangeListenerHandle?
    private var cloudLoaded = false

    let ai = AIService()

    nonisolated private static func file(_ name: String) -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(name)
    }

    init() {
        s = (try? Data(contentsOf: Self.file("lingora-state.json"))).flatMap { try? JSONDecoder().decode(PersistedState.self, from: $0) } ?? PersistedState()
        vocab = (try? Data(contentsOf: Self.file("lingora-vocab.json"))).flatMap { try? JSONDecoder().decode(VocabProgressStore.self, from: $0) } ?? VocabProgressStore()

        $s.dropFirst()
            .debounce(for: .milliseconds(600), scheduler: RunLoop.main)
            .sink { [weak self] state in
                if let data = try? JSONEncoder().encode(state) { try? data.write(to: Self.file("lingora-state.json"), options: .atomic) }
                if let uid = self?.signedInUID, self?.cloudLoaded == true { CloudSync.save(state: state, uid: uid) }
            }
            .store(in: &bag)
        $vocab.dropFirst()
            .debounce(for: .seconds(2), scheduler: RunLoop.main)
            .sink { [weak self] store in
                if let data = try? JSONEncoder().encode(store) { try? data.write(to: Self.file("lingora-vocab.json"), options: .atomic) }
                if let uid = self?.signedInUID, self?.cloudLoaded == true { CloudSync.save(vocab: store, uid: uid) }
            }
            .store(in: &bag)

        if Backend.isConfigured {
            signedInUID = Auth.auth().currentUser?.uid
            authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
                Task { @MainActor in self?.authChanged(uid: user?.uid) }
            }
        }
    }

    // MARK: - Derived

    var theme: Theme { Theme(accent: s.settings.accent, direction: s.settings.direction, languageTints: s.settings.languageTints) }
    /// ChatGPT features run on the user's own ChatGPT plan, through the Lingora backend.
    var aiAvailable: Bool { Backend.isConfigured && signedInUID != nil && chatGPT?.connected == true }

    func language(_ key: String) -> Language? {
        if var l = Catalog.byKey[key] {
            l.name = AppLocale.languageName(code: key, fallback: l.name)
            return l
        }
        return s.customLanguages[key]
    }
    var languages: [Language] { s.learning.compactMap(language) }
    func level(_ key: String) -> Level { s.levels[key] ?? .a1 }
    func hue(_ l: Language) -> Hue { theme.colors(for: l.hue) }
    func content(_ key: String) -> LanguageContent {
        LanguageContent.forLanguage(language(key) ?? Catalog.byKey["es"]!)
    }
    var learnsGerman: Bool { s.learning.contains("de") }

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

    private func authChanged(uid: String?) {
        guard uid != signedInUID || !cloudLoaded else { return }
        signedInUID = uid
        cloudLoaded = false
        chatGPT = nil
        guard let uid else { return }
        Task { await refreshChatGPT() }
        Task {
            let (remoteState, remoteVocab) = await CloudSync.load(uid: uid)
            if let remoteState, remoteState.onboarded, !(s.onboarded && s.user?.uid == uid && s.plans.count >= remoteState.plans.count) {
                var merged = remoteState
                merged.user = s.user?.uid == uid ? s.user : remoteState.user
                s = merged
            }
            if var remoteVocab, remoteVocab.words.count > vocab.words.count {
                remoteVocab.translations = vocab.translations
                vocab = remoteVocab
            }
            cloudLoaded = true
            CloudSync.save(state: s, uid: uid)
        }
    }

    private func finishSignIn(_ r: AuthResult) {
        let name = r.name.trimmingCharacters(in: .whitespaces)
        let finalName = name.isEmpty ? (s.user?.name ?? r.email.components(separatedBy: "@").first?.capitalized ?? L("Friend")) : name
        s.user = UserProfile(uid: r.uid, name: finalName, email: r.email, handle: Self.handle(from: finalName),
                             authMethod: Backend.isConfigured ? r.method : .local)
        if r.uid != nil { signedInUID = r.uid }
        if s.onboarded && !s.learning.isEmpty { return }
        // Cloud state may finish onboarding for a returning user; otherwise continue setup.
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            if !s.onboarded { onboardingPath = [.languages] }
        }
    }

    private func run(_ work: @escaping () async throws -> AuthResult) {
        authBusy = true
        Task {
            defer { authBusy = false }
            do {
                finishSignIn(try await work())
            } catch {
                if !AuthService.isCancellation(error) { toast = AuthService.message(for: error) }
            }
        }
    }

    func signInWithApple(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth): run { try await AuthService.shared.completeApple(auth) }
        case .failure(let error):
            if !AuthService.isCancellation(error) { toast = L("Apple sign-in didn't work: %@", error.localizedDescription) }
        }
    }

    func signInWithGoogle() { run { try await AuthService.shared.signInWithGoogle() } }
    /// Welcome screen: ChatGPT becomes the Lingora account and powers the AI.
    func signInWithChatGPT() {
        authBusy = true
        Task {
            defer { authBusy = false }
            do {
                let result = try await AuthService.shared.continueWithChatGPT()
                if let result { finishSignIn(result) }
                await refreshChatGPT()
            } catch {
                if !AuthService.isCancellation(error) { toast = chatGPTMessage(error) }
            }
        }
    }

    /// Me → ChatGPT: link the user's own plan to their current account.
    func connectChatGPT() {
        guard signedInUID != nil else { toast = L("Sign in to use ChatGPT features."); return }
        signInWithChatGPT()
    }

    func disconnectChatGPT() {
        Task {
            chatGPT = try? await ai.disconnectChatGPT()
        }
    }

    func refreshChatGPT() async {
        guard Backend.isConfigured, signedInUID != nil else { chatGPT = nil; return }
        chatGPT = try? await ai.chatGPTStatus()
    }

    /// Friendly text for errors from ChatGPT-powered calls.
    func chatGPTMessage(_ error: Error) -> String {
        switch Backend.reason(of: error) {
        case "not-configured": return L("Sign in with ChatGPT isn't available in Lingora yet.")
        case "not-connected", "revoked":
            chatGPT = AIService.ChatGPTStatus(connected: false, email: nil, model: nil)
            return L("Connect your ChatGPT account in Me to use AI features.")
        case "not-eligible": return L("Using your plan in Lingora needs ChatGPT Plus or Pro.")
        case "limit": return L("Your ChatGPT plan limit for Lingora is used up for now. Try again later.")
        default: return AuthService.message(for: error)
        }
    }

    /// Returns an error message to show under the form, or nil on success.
    func signInWithEmail(name: String, email: String, password: String, createAccount: Bool) async -> String? {
        authBusy = true
        defer { authBusy = false }
        do {
            finishSignIn(try await AuthService.shared.email(name: name, email: email, password: password, createAccount: createAccount))
            return nil
        } catch {
            return AuthService.message(for: error)
        }
    }

    func logOut() {
        AuthService.shared.signOut()
        signedInUID = nil
        cloudLoaded = false
        chatGPT = nil
        s = PersistedState()
        vocab = VocabProgressStore()
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
                                          native: L("Taught by ChatGPT"), hello: "Hello", thanks: "Thanks",
                                          hue: 270, isCustom: true)
        if !s.learning.contains(key) { s.learning.append(key) }
        s.levels[key] = s.levels[key] ?? .a1
    }

    // MARK: - Plans

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

        if aiAvailable {
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
        await ticker.value
        for (k, p) in results { s.plans[k] = p }
        s.adaptedOn = nil
        s.adaptNote = nil
        if failed { planNotice = L("ChatGPT couldn't be reached for some plans, so we used a standard plan for now.") }
        planStep = 4
        try? await Task.sleep(for: .milliseconds(400))
        generating = false
        planLang = targets.first?.key
        Haptics.success()
    }

    nonisolated private static func convert(_ p: AIService.AIPlan, lang: Language, weekStart: Date) -> WeeklyPlan {
        var days = p.days.prefix(7).enumerated().map { di, d in
            PlanDay(focus: d.focus, tasks: d.tasks.prefix(3).enumerated().map { ti, t in
                PlanTask(id: "\(lang.key)-\(di)-\(ti)", langKey: lang.key, type: t.type, title: t.title,
                         minutes: min(20, max(3, t.minutes)))
            })
        }
        while days.count < 7 { days.append(PlanDay(focus: L("Rest & review"), tasks: [])) }
        return WeeklyPlan(langKey: lang.key, weekStart: weekStart, days: Array(days), rationale: p.rationale, generatedByAI: true)
    }

    func adaptTodayIfNeeded() async {
        let today = DateUtil.dayKey()
        guard s.settings.adaptDaily, aiAvailable, s.adaptedOn != today, !adaptInFlight,
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
            // Keep the planned tasks.
        }
    }

    // MARK: - Tasks & lessons

    func open(_ t: PlanTask) {
        if t.type == .roleplay {
            tutorLang = t.langKey
            tab = .tutor
        } else if t.type == .vocabulary && t.langKey == "de" {
            showWords = true
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
        guard aiAvailable, let l = language(t.langKey) else { return fallback }
        do {
            var c = try await ai.lesson(language: l, level: level(t.langKey), task: t)
            if c.question.options.count < 2 { return fallback }
            c.question.answer = min(max(0, c.question.answer), c.question.options.count - 1)
            lessonCache[cacheKey] = c
            return c
        } catch {
            toast = L("ChatGPT couldn't prepare this lesson, so here's a standard one.")
            return fallback
        }
    }

    func checkWriting(_ t: PlanTask, lesson: LessonContent, answer: String) async -> AIService.WritingCheck {
        let offline = AIService.WritingCheck(
            correct: false,
            feedback: answer.trimmingCharacters(in: .whitespaces).isEmpty
                ? L("No worries — try saying it out loud once before moving on.")
                : L("Nice work. Compare word order with the model answer."),
            modelAnswer: lesson.writing.modelAnswer)
        guard aiAvailable, let l = language(t.langKey) else { return offline }
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

        if aiAvailable {
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
                toast = chatGPTMessage(error)
            }
        }
        try? await Task.sleep(for: .milliseconds(1100))
        let replies = content(key).replies
        msgs.append(ChatMessage(role: .ai, text: replies[replyIndex % replies.count]))
        replyIndex += 1
        s.tutorThreads[key] = msgs
        markRoleplayIfEarned(key)
    }

    private func markRoleplayIfEarned(_ key: String) {
        let mine = (s.tutorThreads[key] ?? []).filter { $0.role == .me }.count
        guard mine >= 3, let rp = todayTasks.first(where: { $0.langKey == key && $0.type == .roleplay }), !isDone(rp) else { return }
        complete(rp, score: 3)
        toast = L("Roleplay done — nicely handled.")
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

        let svc: AIService? = aiAvailable ? ai : nil
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

    nonisolated private static func correction(_ svc: AIService?, message: String, language: Language?) async -> AIService.Correction? {
        guard let svc, let language else { return nil }
        return try? await svc.correct(message: message, language: language)
    }

    func toggle(_ set: WritableKeyPath<PersistedState, Set<String>>, _ id: String) {
        if s[keyPath: set].contains(id) { s[keyPath: set].remove(id) } else { s[keyPath: set].insert(id) }
        Haptics.tap()
    }

    // MARK: - German vocabulary

    var vocabLanguage: String { AppLocale.tag }

    func translations(for id: String) -> [String] {
        vocab.translations[normalizedVocabLang]?[id] ?? []
    }

    var normalizedVocabLang: String {
        let parts = vocabLanguage.replacingOccurrences(of: "_", with: "-").split(separator: "-").map(String.init)
        guard let lang = parts.first?.lowercased() else { return "en" }
        if let script = parts.first(where: { $0.count == 4 }) { return "\(lang)-\(script.prefix(1).uppercased())\(script.dropFirst().lowercased())" }
        return lang
    }

    /// Fetches translations into the user's language for words that don't have one cached yet.
    func prefetchTranslations(for words: [VocabWord]) async {
        // Cached translations are shared by everyone; new ones need the user's ChatGPT plan.
        guard Backend.isConfigured, signedInUID != nil else { return }
        let lang = normalizedVocabLang
        let missing = words.map(\.id).filter { vocab.translations[lang]?[$0] == nil }
        guard !missing.isEmpty else { return }
        for chunk in stride(from: 0, to: missing.count, by: 40).map({ Array(missing[$0..<min($0 + 40, missing.count)]) }) {
            do {
                let res = try await ai.translateWords(ids: chunk)
                var table = vocab.translations[lang] ?? [:]
                for (id, t) in res.translations { table[id] = t }
                vocab.translations[lang] = table
            } catch {
                toast = L("Couldn't load translations — %@", Backend.message(for: error))
                return
            }
        }
    }

    func recordVocab(_ id: String, correct: Bool) {
        VocabEngine.record(&vocab, id: id, correct: correct)
    }

    // MARK: - Reminders

    func setReminders(_ on: Bool) {
        s.settings.reminders = on
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["daily"])
        guard on else { return }
        let title = L("A calm ten minutes?")
        let body = L("Today's tasks are ready whenever you are.")
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
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
