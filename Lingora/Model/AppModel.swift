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

enum MeRoute: Hashable { case addLanguage, addLevels, friends }

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
    /// Language whose course map is open.
    @Published var courseLang: String?

    // Plan generation
    @Published var generating = false
    @Published var planStep = 0
    @Published var planNotice: String?

    // Chat
    @Published var tutorTyping = false
    @Published var tutorSuggestions: [String: [String]] = [:]
    @Published var friendSending = false
    @Published var toast: String?

    // Friends (from the Lingora backend)
    @Published var social: Social.Overview?
    @Published var socialLoading = false
    @Published var chats: [String: [Social.Message]] = [:]
    @Published var nudgedToday: Set<String> = []
    /// The friend chat on screen (no alerts for it).
    @Published var openChat: String?
    private var askedNotifications = false

    // Lessons
    @Published var lessonCache: [String: LessonContent] = [:]

    private var replyIndex = 0
    private var reportTask: Task<Void, Never>?
    private var syncedProfile = ""
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
                Haptics.enabled = state.settings.haptics
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
            if signedInUID != nil { prepareInviteQR() }
        }
        Haptics.enabled = s.settings.haptics
        maintainStreak()
        if s.settings.reminders || s.settings.streakAlerts { scheduleNotifications() }
        if Backend.isConfigured {
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
    var streak: Int { Progress.streak(s.activity, frozen: s.frozenDays) }
    var myWeekMinutes: Int { Progress.minutes(s.activity, since: DateUtil.weekStart()) }
    var practisedToday: Bool { (s.activity[DateUtil.dayKey()] ?? 0) >= 60 }
    /// 0…1 toward the next level, from finished tasks and vocabulary answers.
    func levelProgress(_ key: String) -> Double {
        min(1, Double(s.xp[key] ?? 0) / Double(Progress.pointsPerLevel))
    }

    var socialAvailable: Bool { Backend.isConfigured && signedInUID != nil }
    var friends: [Social.Person] { social?.friends ?? [] }
    /// A screen with the mic button is showing (friend chat or Tutor).
    var chatOnScreen: Bool { (tab == .friends && openChat != nil) || (tab == .tutor && lessonTask == nil && !showWords) }
    var friendsBadge: Int { social.map(MessageAlerts.unreadCount) ?? 0 }
    func friend(_ id: String) -> Social.Person? { friends.first { $0.uid == id } }

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
            await syncProfile()
            await refreshSocial()
            try? await Social.registerThisDevice()
        }
    }

    private func finishSignIn(_ r: AuthResult) {
        let name = r.name.trimmingCharacters(in: .whitespaces)
        let finalName = name.isEmpty ? (s.user?.name ?? r.email.components(separatedBy: "@").first?.capitalized ?? L("Friend")) : name
        s.user = UserProfile(uid: r.uid, name: finalName, email: r.email, handle: s.user?.handle ?? "",
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
        social = nil
        chats = [:]
        nudgedToday = []
        MessageAlerts.reset()
        MessageAlerts.setBadge(0)
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
        let key = "\(DateUtil.dayKey())|\(t.id)"
        if s.done[key] != true {
            rewardTask(key)
            let lang = language(t.langKey)?.name ?? ""
            logActivity(seconds: t.minutes * 60, lang: t.langKey, points: t.minutes * 2 + score * 5,
                        event: (t.type == .roleplay ? "roleplay" : "lesson",
                                ["langKey": t.langKey, "lang": lang, "title": t.title, "kind": t.type.rawValue]))
        }
        s.done[key] = true
        s.results.append(TaskResult(taskID: t.id, langKey: t.langKey, title: t.title, type: t.type, score: score, date: Date()))
        if s.results.count > 60 { s.results.removeFirst(s.results.count - 60) }
        Haptics.success()
    }

    func toggleDone(_ t: PlanTask) {
        let k = "\(DateUtil.dayKey())|\(t.id)"
        let undo = s.done[k] == true
        s.done[k] = undo ? nil : true
        if !undo { rewardTask(k) }
        logActivity(seconds: (undo ? -1 : 1) * t.minutes * 60, lang: t.langKey, points: (undo ? -1 : 1) * t.minutes * 2)
        Haptics.success()
    }

    // MARK: - Activity (streak, minutes, level progress)

    private func rewardTask(_ key: String) {
        if s.rewardedTasks.insert(key).inserted { s.gems += 5 }
    }

    /// Records practice time and level points, and tells friends (through the backend) when it's worth sharing.
    func logActivity(seconds: Int, lang: String? = nil, points: Int = 0, event: (String, [String: String])? = nil) {
        let today = DateUtil.dayKey()
        s.activity[today] = max(0, (s.activity[today] ?? 0) + seconds)
        if let lang, points != 0 { s.xp[lang] = max(0, (s.xp[lang] ?? 0) + points) }
        let year = String(today.prefix(4))
        s.yearTotals[year, default: YearTotal()].seconds = max(0, (s.yearTotals[year]?.seconds ?? 0) + seconds)
        if (s.activity[today] ?? 0) >= 60 { s.yearTotals[year, default: YearTotal()].daysActive.insert(today) }
        if let lang, points > 0 { s.yearTotals[year, default: YearTotal()].xpByLanguage[lang, default: 0] += points }
        if points != 0 { addXP(points) }
        afterProgress()
        guard socialAvailable else { return }
        reportTask?.cancel()
        let p = reportPayload
        if let event {
            let stats = lifetimeStats
            Task { try? await Social.report(days: p.days, xp: p.xp, frozen: p.frozen, stats: stats, event: (event.0, event.1)) }
        } else {
            reportTask = Task {
                try? await Task.sleep(for: .seconds(4))
                if Task.isCancelled { return }
                let p = self.reportPayload
                try? await Social.report(days: p.days, xp: p.xp, frozen: p.frozen, stats: self.lifetimeStats, event: nil)
            }
        }
    }

    /// Lifetime numbers for the public profile.
    var lifetimeStats: [String: Any] {
        var ach: [String: Int] = [:]
        for a in Achievement.all { ach[a.kind.rawValue] = a.level(for: achievementValue(a.kind)).reached }
        return ["totalXP": s.totalXP, "bestStreak": s.bestStreak, "lessons": lessonsCompleted, "words": wordsMastered,
                "stories": s.storiesDone.count, "achievements": ach]
    }

    func achievementValue(_ k: Achievement.Kind) -> Int {
        switch k {
        case .streak: s.bestStreak
        case .xp: s.totalXP
        case .lessons: lessonsCompleted
        case .perfect: perfectLessons
        case .words: wordsMastered
        case .friends: friends.count
        case .quests: questsCompleted
        }
    }

    /// Someone's public profile on screen.
    @Published var profileUID: String?

    /// Recent minutes, XP and frozen days for the server (streaks, leagues, friends).
    var reportPayload: (days: [String: Int], xp: [String: Int], frozen: [String]) {
        let cutoff = DateUtil.dayKey(DateUtil.calendar.date(byAdding: .day, value: -8, to: Date()) ?? Date())
        let xp = s.days.filter { $0.key >= cutoff && $0.value.xp > 0 }.mapValues(\.xp)
        return (Progress.recentMinutes(s.activity), xp, s.frozenDays.filter { $0 >= cutoff }.sorted())
    }

    // MARK: - League

    @Published var league: Social.League?

    func refreshLeague() async {
        guard socialAvailable else { return }
        let p = reportPayload
        try? await Social.report(days: p.days, xp: p.xp, frozen: p.frozen, event: nil)
        if let l = try? await Social.league() { league = l }
    }

    // MARK: - XP, streak, quests

    @Published var celebration: Celebration?

    enum Celebration: Equatable, Identifiable {
        case dailyGoal(Int), streak(Int), quest(String, Int), repaired
        var id: String { "\(self)" }
    }

    var today: DayStat { s.days[DateUtil.dayKey()] ?? DayStat() }
    var todayMinutes: Int { (s.activity[DateUtil.dayKey()] ?? 0) / 60 }
    var todaysQuests: [Quest] { Quest.forDay(DateUtil.dayKey()) }
    func questDone(_ q: Quest) -> Bool { s.claimedQuests.contains("\(DateUtil.dayKey())|\(q.id)") }
    var questsCompleted: Int { s.claimedQuests.filter { $0.contains("|") && !$0.hasPrefix("fq|") }.count }
    var lessonsCompleted: Int { max(s.yearTotals.values.reduce(0) { $0 + $1.lessons }, s.days.values.reduce(0) { $0 + $1.lessons }) }
    var perfectLessons: Int { s.days.values.reduce(0) { $0 + $1.perfect } }
    var wordsMastered: Int { vocab.words.values.filter { $0.box >= 3 }.count + s.courseDone.filter { $0.hasSuffix("#0") || $0.hasSuffix("#1") }.count * 4 }

    private func addXP(_ n: Int) {
        let k = DateUtil.dayKey()
        let before = s.days[k]?.xp ?? 0
        let n = n > 0 && doubleXPActive ? n * 2 : n
        s.days[k, default: DayStat()].xp = max(0, before + n)
        s.totalXP = max(0, s.totalXP + n)
        s.yearTotals[String(k.prefix(4)), default: YearTotal()].xp += n
        let goal = s.settings.dailyXPGoal
        if before < goal && before + n >= goal {
            celebration = .dailyGoal(goal)
            s.gems += 5
        }
    }

    func bumpDay(_ change: (inout DayStat) -> Void) {
        let k = DateUtil.dayKey()
        let before = s.days[k] ?? DayStat()
        change(&s.days[k, default: DayStat()])
        let after = s.days[k] ?? DayStat()
        let y = String(k.prefix(4))
        s.yearTotals[y, default: YearTotal()].lessons += after.lessons - before.lessons
        s.yearTotals[y, default: YearTotal()].tutorMessages += after.tutor - before.tutor
        afterProgress()
    }

    /// Claims finished quests, keeps best streak, earns freezes, completes a streak repair.
    func afterProgress() {
        let k = DateUtil.dayKey()
        for q in todaysQuests where !questDone(q) && q.progress(today, minutes: todayMinutes) >= q.target {
            s.claimedQuests.insert("\(k)|\(q.id)")
            s.days[k, default: DayStat()].quests += 1
            s.gems += 10
            addXP(q.reward)
            celebration = .quest(q.title, q.reward)
        }
        checkMonthly()
        if let r = s.repairDay, today.lessons >= 2 {
            s.frozenDays.insert(r)
            s.repairDay = nil
            celebration = .repaired
        }
        let st = streak
        if st > s.bestStreak {
            s.bestStreak = st
            if [3, 7, 14, 30, 50, 100, 200, 365].contains(st) { celebration = .streak(st) }
        }
        // One freeze for every 7 days of streak, up to 2 in reserve.
        if st >= 7, st / 7 > s.freezeAwardedAt / 7 {
            s.freezeAwardedAt = st
            s.streakFreezes = min(2, s.streakFreezes + 1)
        }
    }

    // Friends Quest: you and one friend (a new one each week) earn 300 XP together.

    static let friendsQuestGoal = 300

    var myWeekXP: Int {
        let ws = DateUtil.dayKey(DateUtil.weekStart())
        return s.days.filter { $0.key >= ws }.values.reduce(0) { $0 + $1.xp }
    }

    var questPartner: Social.Person? {
        let ws = DateUtil.dayKey(DateUtil.weekStart())
        return friends.filter { $0.sharesActivity != false }
            .min { Social.sha256(ws + $0.uid) < Social.sha256(ws + $1.uid) }
    }

    var friendsQuestKey: String { "fq|\(DateUtil.dayKey(DateUtil.weekStart()))" }

    func claimFriendsQuest() {
        guard !s.claimedQuests.contains(friendsQuestKey) else { return }
        s.claimedQuests.insert(friendsQuestKey)
        addXP(25)
        celebration = .quest(L("Friends Quest"), 25)
    }

    /// Progress, settings and word memory as one JSON file.
    var exportData: Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        var out: [String: Any] = [:]
        if let st = try? e.encode(s), let j = try? JSONSerialization.jsonObject(with: st) { out["progress"] = j }
        var slim = vocab
        slim.translations = [:]
        if let v = try? e.encode(slim), let j = try? JSONSerialization.jsonObject(with: v) { out["germanWords"] = j }
        out["exportedAt"] = ISO8601DateFormatter().string(from: Date())
        return (try? JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys])) ?? Data()
    }

    // MARK: - Gems & shop

    var doubleXPActive: Bool { (s.doubleXPUntil ?? .distantPast) > Date() }
    var chestReady: Bool { today.xp >= s.settings.dailyXPGoal && s.chestDay != DateUtil.dayKey() }

    func canBuy(_ item: ShopItem) -> Bool {
        guard s.gems >= item.price else { return false }
        switch item {
        case .freeze: return s.streakFreezes < 2
        case .doubleXP: return !doubleXPActive
        case .repair: return s.repairDay != nil
        }
    }

    func buy(_ item: ShopItem) {
        guard canBuy(item) else { return }
        s.gems -= item.price
        switch item {
        case .freeze: s.streakFreezes += 1
        case .doubleXP: s.doubleXPUntil = Date().addingTimeInterval(15 * 60)
        case .repair:
            if let r = s.repairDay { s.frozenDays.insert(r) }
            s.repairDay = nil
            celebration = .repaired
        }
        SoundFX.play(.right)
        Haptics.success()
    }

    /// The daily chest: gems, sometimes 15 minutes of Double XP.
    func openChest() -> (gems: Int, doubleXP: Bool) {
        guard chestReady else { return (0, false) }
        s.chestDay = DateUtil.dayKey()
        let roll = Int.random(in: 0..<100)
        if roll < 15 && !doubleXPActive {
            s.doubleXPUntil = Date().addingTimeInterval(15 * 60)
            return (0, true)
        }
        let g = [5, 10, 10, 15, 20, 30].randomElement() ?? 10
        s.gems += g
        return (g, false)
    }

    // Monthly challenge & events

    var monthQuests: Int { s.claimedQuests.filter { $0.hasPrefix(MonthlyChallenge.month) }.count }

    func checkMonthly() {
        let m = MonthlyChallenge.month
        if monthQuests >= MonthlyChallenge.goal && !s.monthlyBadges.contains(m) {
            s.monthlyBadges.insert(m)
            s.gems += 100
            addXP(100)
            celebration = .quest(L("%@ challenge", MonthlyChallenge.title(m)), 100)
        }
    }

    func eventProgress(_ e: LingoraEvent) -> Int {
        let days = s.days.filter { $0.key >= e.start && $0.key <= e.end }.values
        switch e.goal {
        case .lessons: return days.reduce(0) { $0 + $1.lessons }
        case .xp: return days.reduce(0) { $0 + $1.xp }
        }
    }

    func claimEvent(_ e: LingoraEvent) {
        guard eventProgress(e) >= e.target, !s.eventRewards.contains(e.id) else { return }
        s.eventRewards.insert(e.id)
        s.gems += e.gems
        SoundFX.play(.done)
        Haptics.success()
    }

    /// On launch and when the app comes back: use a freeze for a missed yesterday, or offer a repair.
    func maintainStreak() {
        let cal = DateUtil.calendar
        guard let y = cal.date(byAdding: .day, value: -1, to: Date()), let yy = cal.date(byAdding: .day, value: -2, to: Date()) else { return }
        let yesterday = DateUtil.dayKey(y)
        if let r = s.repairDay, r != yesterday { s.repairDay = nil }
        guard (s.activity[yesterday] ?? 0) < 60, !s.frozenDays.contains(yesterday) else { return }
        // Was there a streak going into yesterday?
        let dayBefore = DateUtil.dayKey(yy)
        guard (s.activity[dayBefore] ?? 0) >= 60 || s.frozenDays.contains(dayBefore) else { return }
        if s.streakFreezes > 0 {
            s.streakFreezes -= 1
            s.frozenDays.insert(yesterday)
            toast = L("A streak freeze saved your streak yesterday.")
        } else if s.repairDay == nil {
            s.repairDay = yesterday
        }
    }

    func finishVocabRound(right: Int, total: Int) {
        guard total > 0 else { return }
        logActivity(seconds: 0, event: ("vocab", ["count": String(total), "right": String(right)]))
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
        bumpDay { $0.tutor += 1 }
        logActivity(seconds: 45, lang: key, points: 2)
        tutorTyping = true
        defer { tutorTyping = false }

        if aiAvailable {
            do {
                let turn = try await ai.tutorTurn(language: l, level: level(key), scene: tutorScene(key), history: msgs,
                                                  memory: s.tutorMemory[key] ?? [])
                if let fact = turn.remember?.trimmingCharacters(in: .whitespacesAndNewlines), !fact.isEmpty {
                    var mem = s.tutorMemory[key] ?? []
                    if !mem.contains(fact) { mem.append(fact) }
                    s.tutorMemory[key] = Array(mem.suffix(20))
                }
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

    func syncProfile() async {
        guard socialAvailable, let name = s.user?.name else { return }
        if let handle = try? await Social.sync(name: name, langs: s.learning) {
            s.user?.handle = "@" + handle
            prepareInviteQR()
            syncedProfile = "\(name)|\(s.learning.joined(separator: ","))"
        }
    }

    func refreshSocial() async {
        guard socialAvailable else { social = nil; return }
        if syncedProfile != "\(s.user?.name ?? "")|\(s.learning.joined(separator: ","))" { await syncProfile() }
        socialLoading = true
        defer { socialLoading = false }
        do {
            social = try await Social.overview()
            if let shares = social?.me.sharesActivity, shares != s.settings.shareActivity { s.settings.shareActivity = shares }
        } catch {
            if social == nil { toast = L("Couldn't load friends — %@", Backend.message(for: error)) }
        }
    }

    /// Refreshes friends and announces anything new (messages, requests, nudges, invites).
    func pollSocial() async {
        guard socialAvailable else { return }
        await refreshSocial()
        guard let o = social else { return }
        UserDefaults.standard.set(s.settings.notifyMessages, forKey: MessageAlerts.enabledKey)
        if s.settings.notifyMessages && !askedNotifications {
            askedNotifications = true
            MessageAlerts.requestPermission()
        }
        let events = MessageAlerts.newEvents(in: o, openChat: openChat)
        MessageAlerts.setBadge(MessageAlerts.unreadCount(o))
        if s.settings.notifyMessages, let e = events.first {
            toast = e.friend != nil && e.id.hasPrefix("msg-") ? "\(e.title): \(e.body)" : e.body
            Haptics.tap()
        }
    }

    func setShareActivity(_ on: Bool) {
        s.settings.shareActivity = on
        Task {
            do {
                try await Social.setPrivacy(shareActivity: on)
                await refreshSocial()
            } catch {
                s.settings.shareActivity = !on
                toast = Backend.message(for: error)
            }
        }
    }

    func setNotifyMessages(_ on: Bool) {
        s.settings.notifyMessages = on
        UserDefaults.standard.set(on, forKey: MessageAlerts.enabledKey)
        if on { MessageAlerts.requestPermission() }
    }

    var myPhoto: Int { social?.me.photoVersion ?? 0 }

    /// Uploads a new profile photo (nil removes it).
    func setPhoto(_ image: UIImage?) async {
        guard socialAvailable, let uid = signedInUID else { return }
        do {
            let jpeg = image.flatMap { AvatarStore.prepare($0) }
            if image != nil && jpeg == nil { toast = L("That photo is too large."); return }
            let v = try await Social.setAvatar(jpeg)
            if let jpeg, let img = UIImage(data: jpeg) { AvatarStore.shared.set(img, uid: uid, version: v) }
            social?.me.photo = v
            Haptics.success()
            await refreshSocial()
        } catch {
            toast = Backend.message(for: error)
        }
    }

    /// The invite link for my username (also encoded in my QR code).
    var inviteLink: String? {
        let h = (s.user?.handle ?? "").replacingOccurrences(of: "@", with: "")
        guard !h.isEmpty else { return nil }
        if let base = Backend.apiBaseURL { return base.appendingPathComponent("u").appendingPathComponent(h).absoluteString }
        return "lingora://add/\(h)"
    }

    /// Makes the QR once per username and saves it on the device; afterwards it just loads.
    func prepareInviteQR() {
        if let link = inviteLink { QRCode.prepare(link) }
    }

    func changeHandle(_ handle: String) async -> String? {
        do {
            s.user?.handle = "@" + (try await Social.setHandle(handle))
            prepareInviteQR()
            await refreshSocial()
            return nil
        } catch {
            return Backend.message(for: error)
        }
    }

    /// Sends a friend request (or accepts theirs). Returns the new relation.
    @discardableResult
    func addFriend(uid: String? = nil, handle: String? = nil) async -> String? {
        do {
            let r = try await Social.request(uid: uid, handle: handle)
            Haptics.success()
            toast = r == "friend" ? L("You're now friends.") : L("Friend request sent.")
            await refreshSocial()
            return r
        } catch {
            toast = Backend.message(for: error)
            return nil
        }
    }

    func respond(to uid: String, accept: Bool) async {
        do {
            try await Social.respond(uid: uid, accept: accept)
            if accept { Haptics.success() }
            await refreshSocial()
        } catch {
            toast = Backend.message(for: error)
        }
    }

    func removeFriend(_ uid: String) async {
        do {
            try await Social.remove(uid: uid)
            friendsPath.removeAll { $0 == uid }
            await refreshSocial()
        } catch {
            toast = Backend.message(for: error)
        }
    }

    func cheer(_ item: Social.FeedItem) {
        guard var o = social, let i = o.feed.firstIndex(where: { $0.id == item.id && $0.uid == item.uid }) else { return }
        o.feed[i].cheeredByMe.toggle()
        o.feed[i].cheers += o.feed[i].cheeredByMe ? 1 : -1
        social = o
        Haptics.tap()
        Task {
            do { try await Social.cheer(owner: item.uid, id: item.id) } catch { await refreshSocial() }
        }
    }

    func nudge(_ uid: String) {
        nudgedToday.insert(uid)
        Haptics.tap()
        Task {
            do { try await Social.nudge(uid: uid) } catch {
                nudgedToday.remove(uid)
                toast = Backend.message(for: error)
            }
        }
    }

    func dismissNudges() {
        guard let ids = social?.nudges.map(\.id), !ids.isEmpty else { return }
        social?.nudges = []
        Task { try? await Social.markNudgesSeen(ids) }
    }

    func startChallenge(type: String, friends: [String], goalMinutes: Int? = nil, planLang: String? = nil) async -> Bool {
        do {
            var plan: WeeklyPlan?
            var title: String?
            if type == "plan" {
                guard let key = planLang, let p = s.plans[key] else { toast = L("Make a plan first."); return false }
                plan = p
                title = language(key)?.name
            }
            let end = type == "sprint" ? DateUtil.calendar.date(byAdding: .day, value: 6, to: Date()).map { DateUtil.dayKey($0) } : nil
            try await Social.createChallenge(type: type, friends: friends, goalMinutes: goalMinutes, endDay: end,
                                             lang: planLang, title: title, plan: plan)
            Haptics.success()
            toast = L("Invite sent.")
            await refreshSocial()
            return true
        } catch {
            toast = Backend.message(for: error)
            return false
        }
    }

    func respondChallenge(_ c: Social.Challenge, accept: Bool) async {
        do {
            try await Social.respondChallenge(id: c.id, accept: accept)
            if accept, c.type == "plan", let id = c.planId { await joinPlan(id) }
            await refreshSocial()
        } catch {
            toast = Backend.message(for: error)
        }
    }

    func leaveChallenge(_ c: Social.Challenge) async {
        do {
            try await Social.leaveChallenge(id: c.id)
            await refreshSocial()
        } catch {
            toast = Backend.message(for: error)
        }
    }

    func sharePlan(_ key: String) async {
        guard socialAvailable else { toast = L("Sign in to share plans with friends."); return }
        guard let plan = s.plans[key], let l = language(key) else { return }
        do {
            try await Social.sharePlan(plan, lang: key, title: plan.days.compactMap { $0.tasks.first?.title }.first ?? l.name)
            Haptics.success()
            toast = L("Plan shared with your friends.")
            await refreshSocial()
        } catch {
            toast = Backend.message(for: error)
        }
    }

    /// Copies a friend's shared plan into this week, adding the language if needed.
    func joinPlan(_ planId: String) async {
        do {
            let (key, shared) = try await Social.sharedPlan(id: planId)
            guard Catalog.byKey[key] != nil || s.customLanguages[key] != nil else {
                toast = L("This plan is for a language you can add in Me first.")
                return
            }
            if !s.learning.contains(key) { s.learning.append(key) }
            if s.levels[key] == nil { s.levels[key] = .a1 }
            let ws = DateUtil.weekStart()
            var plan = shared
            plan.weekStart = ws
            plan.days = plan.days.enumerated().map { di, d in
                PlanDay(focus: d.focus, tasks: d.tasks.enumerated().map { ti, t in
                    var t = t
                    t.id = "\(key)-\(di)-j\(ti)"
                    t.langKey = key
                    return t
                })
            }
            s.plans[key] = plan
            planLang = key
            Haptics.success()
            toast = L("Plan added to your week.")
        } catch {
            toast = Backend.message(for: error)
        }
    }

    /// The language two friends practise together: one I learn that they learn too, else my first.
    func chatLanguage(with f: Social.Person) -> Language? {
        (s.learning.first { f.langs.contains($0) } ?? s.learning.first).flatMap(language)
    }

    func loadChat(_ uid: String) async {
        guard socialAvailable else { return }
        if let m = try? await Social.messages(with: uid) {
            chats[uid] = m
            // Opening the chat marks it read on the server.
            if let i = social?.friends.firstIndex(where: { $0.uid == uid }), (social?.friends[i].unread ?? 0) > 0 {
                social?.friends[i].unread = 0
                MessageAlerts.setBadge(friendsBadge)
            }
        }
    }

    func sendFriend(_ text: String, to uid: String) async {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !friendSending, let f = friend(uid) else { return }
        friendSending = true
        defer { friendSending = false }
        let lang = chatLanguage(with: f)
        let pending = Social.Message(id: "local-\(UUID().uuidString)", mine: true, text: t,
                                     createdAt: Date().timeIntervalSince1970 * 1000, correction: nil)
        chats[uid, default: []].append(pending)
        do {
            _ = try await Social.send(t, to: uid, language: aiAvailable ? lang : nil)
            if let lang { logActivity(seconds: 30, lang: lang.key, points: 1) }
            await loadChat(uid)
        } catch {
            chats[uid]?.removeAll { $0.id == pending.id }
            toast = Backend.message(for: error)
        }
    }

    /// A reply idea from ChatGPT for the friend chat.
    func suggestReply(to uid: String) async -> String? {
        guard aiAvailable, let f = friend(uid), let l = chatLanguage(with: f) else { return nil }
        let history = (chats[uid] ?? []).suffix(12).map { ChatMessage(role: $0.mine ? .me : .ai, text: $0.text) }
        do {
            let turn = try await ai.tutorTurn(language: l, level: level(l.key),
                                              scene: L("Chatting with a friend who is also learning"), history: Array(history))
            return turn.suggestions.first
        } catch {
            toast = chatGPTMessage(error)
            return nil
        }
    }

    /// lingora://add/<username> — opened from an invite link or QR code.
    func handle(url: URL) -> Bool {
        guard url.scheme == "lingora", url.host == "add" else { return false }
        let handle = url.pathComponents.dropFirst().first ?? ""
        guard !handle.isEmpty else { return true }
        guard socialAvailable else { toast = L("Sign in first, then open the link again."); return true }
        tab = .friends
        Task { await addFriend(handle: handle) }
        return true
    }

    // MARK: - Course

    /// The course for a language: every CEFR topic (A1–C2) as a unit. Built-in content fills its topics,
    /// units ChatGPT wrote fill theirs, the rest are placeholders the learner can have written.
    func course(_ lang: String) -> Course? {
        let builtIn = CourseLibrary.builtIn(lang)?.sections.flatMap(\.units) ?? []
        var byTopic: [String: CourseUnit] = [:]
        for var u in builtIn {
            guard let t = Curriculum.builtInTopics[u.id] else { continue }
            u.topic = t
            byTopic[t] = u
        }
        for u in s.generatedUnits[lang] ?? [] { if let t = u.topic, byTopic[t] == nil { byTopic[t] = u } }
        if byTopic.isEmpty && !canWriteUnits { return nil }
        var sections: [CourseSection] = []
        for l in Curriculum.shared.levels {
            for c in l.categories {
                let units = c.topics.map { t in
                    byTopic[t.id] ?? CourseUnit(id: "\(lang)-\(t.id)", title: t.en, tip: nil, words: [], sentences: [], topic: t.id)
                }
                sections.append(CourseSection(id: "\(lang)-\(c.id)", title: c.name.en, level: l.level, units: units))
            }
        }
        // Units written before the curriculum existed.
        let legacy = (s.generatedUnits[lang] ?? []).filter { $0.topic == nil }
        if !legacy.isEmpty {
            sections.append(CourseSection(id: "\(lang)-more", title: "Written for you", level: level(lang).code, units: legacy))
        }
        return Course(lang: lang, sections: sections)
    }

    var canWriteUnits: Bool { Backend.isConfigured && signedInUID != nil }

    var courseLanguages: [Language] { languages.filter { course($0.key) != nil } }

    @Published var writingUnit: String?

    func isDone(_ l: CourseLesson) -> Bool { s.courseDone.contains(l.id) }

    func unitDone(_ u: CourseUnit) -> Bool {
        !u.isPlaceholder && LessonKind.allCases.allSatisfy { isDone(CourseLesson(unit: u, kind: $0)) }
    }

    /// Index of the first unit at the learner's level: everything up to it is open.
    private func placementStart(_ units: [(CourseUnit, String)], lang: String) -> Int {
        let code = level(lang).code
        return units.firstIndex { $0.1 == code } ?? 0
    }

    /// A unit opens when the unit before it is finished; units up to your level are open from the start.
    func unitOpen(_ u: CourseUnit, in course: Course) -> Bool {
        let units = course.sections.flatMap { s in s.units.map { ($0, s.level) } }
        guard let i = units.firstIndex(where: { $0.0.id == u.id }) else { return false }
        if i <= placementStart(units, lang: course.lang) { return true }
        return unitDone(units[i - 1].0)
    }

    /// Lessons inside an open unit go in order.
    func isUnlocked(_ l: CourseLesson, in course: Course) -> Bool {
        guard !l.unit.isPlaceholder, unitOpen(l.unit, in: course) else { return false }
        guard let k = LessonKind(rawValue: l.kind.rawValue - 1) else { return true }
        return isDone(CourseLesson(unit: l.unit, kind: k))
    }

    func nextLesson(_ lang: String) -> CourseLesson? {
        guard let c = course(lang) else { return nil }
        let open = CourseLibrary.lessons(c).filter { !isDone($0) && isUnlocked($0, in: c) }
        let startCode = level(lang).code
        let atLevel = c.sections.filter { $0.level >= startCode }.flatMap(\.units).map(\.id)
        return open.first { atLevel.contains($0.unit.id) } ?? open.first
    }

    /// The next topic that's open and not written yet.
    func nextPlaceholder(_ lang: String) -> CourseUnit? {
        guard let c = course(lang) else { return nil }
        return c.sections.flatMap(\.units).first { $0.isPlaceholder && unitOpen($0, in: c) }
    }

    /// Has ChatGPT write the unit for a topic (shared cache first, so most learners get it instantly).
    func writeUnit(_ unit: CourseUnit, lang: String) async {
        guard let l = language(lang), let topicId = unit.topic, let found = Curriculum.shared.topic(topicId), writingUnit == nil else { return }
        let (topic, lvl) = found
        writingUnit = unit.id
        defer { writingUnit = nil }
        do {
            var u = try await ai.courseUnit(language: l, level: Level.from(code: lvl.level) ?? level(lang), topic: topic.en, topicId: topic.id)
            u.id = unit.id
            u.topic = topic.id
            s.generatedUnits[lang, default: []].removeAll { $0.id == u.id }
            s.generatedUnits[lang, default: []].append(u)
            Haptics.success()
        } catch {
            toast = chatGPTMessage(error)
        }
    }

    /// Display names: the curriculum's (Serbian or English), built-in titles through the string catalog.
    func unitTitle(_ u: CourseUnit) -> String {
        if let t = u.topic, let (topic, _) = Curriculum.shared.topic(t) { return Curriculum.name(topic) }
        return L(u.title)
    }

    func courseProgress(_ lang: String) -> (done: Int, total: Int) {
        guard let c = course(lang) else { return (0, 0) }
        let all = CourseLibrary.lessons(c)
        return (all.filter(isDone).count, all.count)
    }

    // Words (every language)

    /// Spaced repetition for course words: right → next box (1, 2, 4, 8, 16 days), wrong → back to box 0.
    func recordWord(_ item: CourseItem, right: Bool, lang: String) {
        let key = "\(lang)|\(item.t)"
        var m = s.wordMemory[key] ?? WordMemory()
        m.seen += 1
        if right { m.box = min(5, m.box + 1) } else { m.box = 0; m.wrong += 1 }
        let days = [0, 1, 2, 4, 8, 16][m.box]
        m.due = DateUtil.dayKey(DateUtil.calendar.date(byAdding: .day, value: days, to: Date()) ?? Date())
        s.wordMemory[key] = m
    }

    func memory(_ item: CourseItem, lang: String) -> WordMemory? { s.wordMemory["\(lang)|\(item.t)"] }

    /// Words from units you've started, with their memory.
    func learnedWords(_ lang: String) -> [CourseItem] {
        guard let c = course(lang) else { return [] }
        return c.sections.flatMap(\.units).filter { isDone(CourseLesson(unit: $0, kind: .words1)) }.flatMap(\.words)
    }

    /// Weakest and due words first.
    func wordsLesson(_ lang: String) -> CourseLesson? {
        let today = DateUtil.dayKey()
        let words = learnedWords(lang).sorted { a, b in
            let ma = memory(a, lang: lang), mb = memory(b, lang: lang)
            let da = (ma?.due ?? "") <= today, db = (mb?.due ?? "") <= today
            if da != db { return da }
            return (ma?.box ?? 0) < (mb?.box ?? 0)
        }
        guard words.count >= 4 else { return nil }
        let unit = CourseUnit(id: "words-\(lang)", title: "Words", tip: nil, words: Array(words.prefix(12)), sentences: [])
        return CourseLesson(unit: unit, kind: .review, mode: .practice)
    }

    func dueWordCount(_ lang: String) -> Int {
        let today = DateUtil.dayKey()
        return learnedWords(lang).filter { (memory($0, lang: lang)?.due ?? "") <= today }.count
    }

    func listeningLesson(_ lang: String) -> CourseLesson? {
        reviewLesson(lang).map { CourseLesson(unit: $0.unit, kind: .review, mode: .listening) }
    }

    func speedLesson(_ lang: String) -> CourseLesson? {
        guard let w = wordsLesson(lang) else { return nil }
        let unit = CourseUnit(id: "speed-\(lang)", title: "Speed round", tip: nil, words: learnedWords(lang), sentences: [])
        return w.unit.words.count >= 4 ? CourseLesson(unit: unit, kind: .review, mode: .speed) : nil
    }

    func speakingLesson(_ lang: String) -> CourseLesson? {
        reviewLesson(lang).map { CourseLesson(unit: $0.unit, kind: .review, mode: .speaking) }
    }

    // Stories

    func stories(_ lang: String) -> [Story] { StoryLibrary.stories(lang) }

    func storyUnlocked(_ st: Story) -> Bool {
        guard let u = st.unit else { return true }
        return s.courseDone.contains("\(u)#0")
    }

    func finishStory(_ st: Story, lang: String, correct: Int, seconds: Int) -> Int {
        let first = !s.storiesDone.contains(st.id)
        s.storiesDone.insert(st.id)
        s.yearTotals[String(DateUtil.dayKey().prefix(4)), default: YearTotal()].stories += 1
        let xp = 10 + correct * 2
        bumpDay { $0.practice += 1 }
        logActivity(seconds: max(60, seconds), lang: lang, points: xp,
                    event: first ? ("lesson", ["langKey": lang, "lang": language(lang)?.name ?? "", "title": st.title, "kind": TaskType.reading.rawValue]) : nil)
        return xp
    }

    // Mistakes & practice

    func noteMistake(_ item: CourseItem, sentence: Bool, lang: String) {
        let kp: WritableKeyPath<PersistedState, [String: [CourseItem]]> = sentence ? \.mistakeSentences : \.mistakeWords
        var list = s[keyPath: kp][lang] ?? []
        list.removeAll { $0.t == item.t }
        list.append(item)
        s[keyPath: kp][lang] = Array(list.suffix(40))
    }

    func clearMistake(_ item: CourseItem, lang: String) {
        s.mistakeWords[lang]?.removeAll { $0.t == item.t }
        s.mistakeSentences[lang]?.removeAll { $0.t == item.t }
    }

    func mistakeCount(_ lang: String) -> Int { (s.mistakeWords[lang]?.count ?? 0) + (s.mistakeSentences[lang]?.count ?? 0) }

    /// A practice session from your mistakes.
    func mistakesLesson(_ lang: String) -> CourseLesson? {
        let w = s.mistakeWords[lang] ?? [], se = s.mistakeSentences[lang] ?? []
        guard w.count + se.count >= 3 else { return nil }
        let unit = CourseUnit(id: "mistakes-\(lang)", title: "Your mistakes", tip: nil, words: w, sentences: se)
        return CourseLesson(unit: unit, kind: .review, mode: .practice)
    }

    /// Mixed review over everything finished so far.
    func reviewLesson(_ lang: String) -> CourseLesson? {
        guard let c = course(lang) else { return nil }
        let units = c.sections.flatMap(\.units).filter { u in isDone(CourseLesson(unit: u, kind: .words1)) }
        guard !units.isEmpty else { return nil }
        let unit = CourseUnit(id: "review-\(lang)", title: "Mixed review", tip: nil,
                              words: units.flatMap(\.words), sentences: units.flatMap(\.sentences))
        return CourseLesson(unit: unit, kind: .review, mode: .practice)
    }

    /// Test to skip to `section`: everything before it, mixed.
    func jumpLesson(_ lang: String, to section: Int) -> CourseLesson? {
        guard let c = course(lang), section > 0, section < c.sections.count else { return nil }
        let units = c.sections.prefix(section).flatMap(\.units)
        let unit = CourseUnit(id: "jump-\(lang)", title: "Jump ahead", tip: nil,
                              words: units.flatMap(\.words), sentences: units.flatMap(\.sentences))
        return CourseLesson(unit: unit, kind: .review, mode: .jump(section: section))
    }

    /// Records a finished lesson: practice time, level points and a feed update.
    /// Returns the points, or nil when a jump test wasn't passed.
    func finishLesson(_ l: CourseLesson, lang: String, correct: Int, total: Int, seconds: Int) -> Int {
        if l.unit.id.hasPrefix("alphabet-") { s.courseDone.insert(l.unit.id) }
        if l.mode != .normal {
            let passed = total > 0 && Double(correct) / Double(total) >= 0.8
            if case .jump(let section) = l.mode, passed, let c = course(lang) {
                for u in c.sections.prefix(section).flatMap(\.units) {
                    for k in LessonKind.allCases { s.courseDone.insert(CourseLesson(unit: u, kind: k).id) }
                }
            }
            let xp = 5 + correct
            bumpDay { $0.practice += 1; if correct == total { $0.perfect += 1 } }
            logActivity(seconds: max(60, seconds), lang: lang, points: xp)
            return xp
        }
        bumpDay { $0.lessons += 1; if correct == total { $0.perfect += 1 } }
        s.practiceHours = Array((s.practiceHours + [DateUtil.calendar.component(.hour, from: Date())]).suffix(30))
        scheduleNotifications()
        s.gems += correct == total ? 10 : 5
        let first = !isDone(l)
        s.courseDone.insert(l.id)
        let xp = 10 + correct + (first ? 5 : 0)
        let kind: TaskType = l.kind == .sentences ? .writing : .vocabulary
        logActivity(seconds: max(60, seconds), lang: lang, points: xp,
                    event: first ? ("lesson", ["langKey": lang, "lang": language(lang)?.name ?? "",
                                                "title": "\(l.unit.title) · \(l.kind.title)", "kind": kind.rawValue]) : nil)
        Haptics.success()
        return xp
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
        logActivity(seconds: 20, lang: "de", points: correct ? 2 : 0)
    }

    // MARK: - Reminders

    func setReminders(_ on: Bool) {
        s.settings.reminders = on
        if on { MessageAlerts.requestPermission() }
        scheduleNotifications()
    }

    /// The hour you usually practise (median of the last practice times), 19:00 until we know.
    var usualHour: Int {
        let h = s.practiceHours.suffix(20).sorted()
        return h.isEmpty ? 19 : h[h.count / 2]
    }

    /// Daily reminder at your usual hour, "streak at risk" in the evening if you haven't practised,
    /// and a Sunday summary. Re-planned whenever you practise or open the app.
    func scheduleNotifications() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["daily", "streak-risk", "weekly"])
        let cal = DateUtil.calendar
        let now = Date()

        if s.settings.reminders {
            let c = UNMutableNotificationContent()
            c.title = L("A calm ten minutes?")
            c.body = L("Today's tasks are ready whenever you are.")
            var comps = DateComponents()
            comps.hour = usualHour
            comps.minute = 0
            center.add(UNNotificationRequest(identifier: "daily", content: c,
                                             trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)))
        }

        if s.settings.streakAlerts, streak > 0 || practisedToday {
            // Next evening without practice: today at 21:00 if not done yet, otherwise tomorrow.
            let day = practisedToday ? cal.date(byAdding: .day, value: 1, to: now) ?? now : now
            if var fire = cal.date(bySettingHour: 21, minute: 0, second: 0, of: day), fire > now || !practisedToday {
                if fire <= now { fire = now.addingTimeInterval(60 * 30) }
                let n = practisedToday ? streak : max(1, streak)
                let c = UNMutableNotificationContent()
                c.title = L("Your %lld-day streak is at risk", n)
                c.body = s.streakFreezes > 0 ? L("A few minutes today keeps it going. You have a streak freeze, just in case.")
                                             : L("A few minutes today keeps it going.")
                c.sound = .default
                let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
                center.add(UNNotificationRequest(identifier: "streak-risk", content: c,
                                                 trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
            }
        }

        if s.settings.weeklySummary {
            let c = UNMutableNotificationContent()
            c.title = L("Your week in Lingora")
            c.body = L("See your minutes, XP and streak for the week.")
            var comps = DateComponents()
            comps.weekday = 1      // Sunday
            comps.hour = 18
            center.add(UNNotificationRequest(identifier: "weekly", content: c,
                                             trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)))
        }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
