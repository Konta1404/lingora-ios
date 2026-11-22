import SwiftUI

struct FriendsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme
    @State private var tab = 0
    @State private var newChallenge: ChallengeKind?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    ScreenTitle(text: L("Friends"))
                    Spacer()
                    if model.socialAvailable {
                        PillButton(title: L("Add"), icon: "plus", bg: theme.a, fg: .white) { model.showAddFriend = true }
                    }
                }
                if !model.socialAvailable {
                    signedOut
                } else {
                    nudges
                    requests
                    segmented
                    switch tab {
                    case 0: feed
                    case 1: board
                    default: challenges
                    }
                }
            }
            .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 20)
        }
        .background(theme.ground)
        .task { await model.refreshSocial() }
        .refreshable { await model.refreshSocial() }
        .sheet(item: $newChallenge) { kind in
            StartChallengeSheet(type: kind.id)
                .environmentObject(model)
                .environment(\.theme, model.theme)
                .presentationDetents([.medium, .large])
                .presentationCornerRadius(28)
        }
    }

    private var signedOut: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Learn with friends")).font(.fig(17, .bold))
            Text(L("Friends, challenges and shared plans need a Lingora account. Log out in Me and sign in to turn them on."))
                .font(.fig(14)).foregroundStyle(theme.muted)
        }
        .card()
    }

    @ViewBuilder
    private var nudges: some View {
        if let n = model.social?.nudges, !n.isEmpty {
            let names = Array(Set(n.map(\.name))).sorted()
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "hand.wave").padding(.top, 2)
                Text(names.count == 1 ? L("%@ nudged you — a few minutes today?", names[0])
                                      : L("%@ and %@ nudged you — a few minutes today?", names.dropLast().joined(separator: ", "), names.last!))
                    .font(.fig(14))
                Spacer(minLength: 0)
                Button { model.dismissNudges() } label: { Image(systemName: "xmark").font(.system(size: 12, weight: .bold)) }
                    .accessibilityLabel(L("Dismiss"))
            }
            .tintedNote(theme.at, theme.ad, radius: theme.radius)
        }
    }

    @ViewBuilder
    private var requests: some View {
        if let incoming = model.social?.incoming, !incoming.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(incoming.enumerated()), id: \.element.id) { i, p in
                    HStack(spacing: 12) {
                        Avatar(initial: p.initial, hue: Hue(h: p.hue), size: 40, uid: p.uid, photo: p.photoVersion)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: p.name).font(.fig(15, .semibold))
                            Text(L("wants to be friends · %@", p.atHandle)).font(.fig(13)).foregroundStyle(theme.muted)
                        }
                        Spacer(minLength: 4)
                        PillButton(title: L("Decline"), bg: theme.chip, fg: theme.text, height: 32) {
                            Task { await model.respond(to: p.uid, accept: false) }
                        }
                        PillButton(title: L("Accept"), bg: theme.a, fg: .white, height: 32) {
                            Task { await model.respond(to: p.uid, accept: true) }
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .overlay(alignment: .top) { if i > 0 { Rectangle().fill(theme.line).frame(height: 1) } }
                }
            }
            .card(padding: 0)
        }
    }

    private var segmented: some View {
        HStack(spacing: 0) {
            ForEach(Array([L("Activity"), L("This week"), L("Challenges")].enumerated()), id: \.offset) { i, label in
                Button { withAnimation(.easeInOut(duration: 0.2)) { tab = i } } label: {
                    Text(label).font(.fig(14, .semibold)).foregroundStyle(theme.text)
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .background(tab == i ? theme.card : .clear, in: Capsule())
                        .shadow(color: tab == i ? theme.shadow.opacity(0.1) : .clear, radius: 2, y: 1)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(tab == i ? .isSelected : [])
            }
        }
        .padding(3)
        .frame(height: 36)
        .background(theme.chip, in: Capsule())
    }

    private func empty(_ text: String, button: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(text).font(.fig(14)).foregroundStyle(theme.muted)
            if let button {
                Button(button) { model.showAddFriend = true }
                    .buttonStyle(PrimaryButtonStyle(kind: .accent, height: 44))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: Activity

    @ViewBuilder
    private var feed: some View {
        let items = model.social?.feed ?? []
        if model.social == nil && model.socialLoading {
            ProgressView().frame(maxWidth: .infinity).padding(30)
        } else if items.isEmpty {
            empty(model.friends.isEmpty ? L("Add friends to see what they practise and cheer each other on.")
                                        : L("Nothing yet this week. Finish a task and your friends will see it here."),
                  button: model.friends.isEmpty ? L("Add friends") : nil)
        } else {
            VStack(spacing: 10) {
                ForEach(items) { item in
                    let mine = item.uid == model.signedInUID
                    VStack(alignment: .leading, spacing: 12) {
                        Button { if !mine { model.friendsPath.append(item.uid) } } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Avatar(initial: String(item.name.first ?? "?").uppercased(), hue: Hue(h: item.hue), size: 40, uid: item.uid, photo: item.photo ?? 0)
                                VStack(alignment: .leading, spacing: 2) {
                                    (Text(mine ? L("You") : item.firstName).font(.fig(15, .bold)) + Text(verbatim: " " + FeedText.text(item)).font(.fig(15)))
                                        .multilineTextAlignment(.leading)
                                    Text(verbatim: FeedText.ago(item.date)).font(.fig(13)).foregroundStyle(theme.muted)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                        .buttonStyle(.plain)
                        HStack(spacing: 8) {
                            PillButton(title: L("Cheer · %lld", item.cheers),
                                       icon: item.cheeredByMe ? "heart.fill" : "heart",
                                       bg: item.cheeredByMe ? theme.at : theme.chip,
                                       fg: item.cheeredByMe ? theme.ad : theme.text, height: 34) {
                                model.cheer(item)
                            }
                            .disabled(mine)
                            if item.type == "plan", !mine, let id = item.planId {
                                PillButton(title: L("Join plan"), bg: theme.a, fg: .white, height: 34) {
                                    Task { await model.joinPlan(id) }
                                }
                            }
                        }
                        .padding(.leading, 52)
                    }
                    .card(padding: 14)
                }
            }
        }
    }

    // MARK: This week

    @ViewBuilder
    private var board: some View {
        if model.friends.isEmpty {
            empty(L("Your weekly board fills up once you add friends."), button: L("Add friends"))
        } else {
            boardList
        }
    }

    private var boardList: some View {
        var rows = model.friends.map {
            BoardRow(id: $0.uid, name: $0.name, initial: $0.initial, hue: $0.hue,
                     minutes: $0.weekMinutes, streak: $0.streak, today: $0.practisedToday, isMe: false,
                     photo: $0.photoVersion, hidden: $0.sharesActivity == false, unread: $0.unread ?? 0)
        }
        rows.append(BoardRow(id: "me", name: L("You"), initial: model.s.user?.initial ?? "Y", hue: theme.accent.hue,
                             minutes: model.myWeekMinutes, streak: model.streak, today: model.practisedToday, isMe: true,
                             photo: model.myPhoto, hidden: false, unread: 0))
        rows.sort { $0.minutes > $1.minutes }
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in
                let nudged = model.nudgedToday.contains(r.id)
                HStack(spacing: 12) {
                    Text(verbatim: "\(i + 1)").font(.fig(14, .bold)).foregroundStyle(theme.muted).frame(width: 18)
                    Avatar(initial: r.initial, hue: Hue(h: r.hue), size: 36, uid: r.isMe ? model.signedInUID : r.id, photo: r.photo)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: r.name).font(.fig(15, .semibold))
                        Text(r.hidden ? L("Keeps activity private") : L("%lld-day streak · %@", r.streak, r.today ? L("practised today") : L("not yet today")))
                            .font(.fig(12)).foregroundStyle(theme.muted)
                    }
                    Spacer(minLength: 0)
                    if r.unread > 0 {
                        Text(verbatim: "\(r.unread)").font(.fig(12, .bold)).foregroundStyle(.white)
                            .frame(minWidth: 22, minHeight: 22).background(theme.a, in: Capsule())
                            .accessibilityLabel(L("%lld unread", r.unread))
                    }
                    if !r.isMe && !r.today && !r.hidden {
                        PillButton(title: nudged ? L("Nudged") : L("Nudge"), bg: nudged ? theme.at : theme.chip,
                                   fg: nudged ? theme.ad : theme.text, height: 30) {
                            if !nudged { model.nudge(r.id) }
                        }
                    }
                    if !r.hidden { Text(L("%lld min", r.minutes)).font(.fig(14, .semibold)) }
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(r.isMe ? theme.at : .clear)
                .overlay(alignment: .top) { if i > 0 { Rectangle().fill(theme.line).frame(height: 1) } }
                .contentShape(Rectangle())
                .onTapGesture { if !r.isMe { model.friendsPath.append(r.id) } }
            }
        }
        .card(padding: 0)
        .clipShape(RoundedRectangle(cornerRadius: theme.radius, style: .continuous))
    }

    // MARK: Challenges

    private var challenges: some View {
        let list = model.social?.challenges ?? []
        let newOnes = [("duel", L("Streak duel"), L("Practise every day for a week, side by side")),
                       ("sprint", L("Minutes sprint"), L("A shared minutes goal for the next 7 days")),
                       ("plan", L("Learn the same plan"), L("Send your plan; friends follow it with you"))]
        return VStack(alignment: .leading, spacing: 10) {
            ForEach(list) { c in ChallengeCard(c: c) }
            SectionLabel(text: L("Start something new")).padding(.top, list.isEmpty ? 0 : 8)
            VStack(spacing: 0) {
                ForEach(Array(newOnes.enumerated()), id: \.element.0) { i, n in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(n.1).font(.fig(15, .semibold))
                            Text(n.2).font(.fig(13)).foregroundStyle(theme.muted)
                        }
                        Spacer()
                        PillButton(title: L("Start"), bg: theme.chip, fg: theme.text, height: 34) {
                            if model.friends.isEmpty { model.showAddFriend = true } else { newChallenge = ChallengeKind(id: n.0) }
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .overlay(alignment: .top) { if i > 0 { Rectangle().fill(theme.line).frame(height: 1) } }
                }
            }
            .card(padding: 0)
        }
    }
}

private struct ChallengeKind: Identifiable { let id: String }

private struct BoardRow: Identifiable {
    var id: String
    var name: String
    var initial: String
    var hue: Double
    var minutes: Int
    var streak: Int
    var today: Bool
    var isMe: Bool
    var photo: Int
    var hidden: Bool
    var unread: Int
}

/// Turns a feed item (type + params from the backend) into a sentence in the reader's language.
enum FeedText {
    static func language(_ key: String?, fallback: String?) -> String {
        guard let key, !key.isEmpty else { return fallback ?? "" }
        if key.hasPrefix("x-") { return fallback ?? key }
        return AppLocale.languageName(code: key, fallback: fallback ?? key)
    }

    static func text(_ item: Social.FeedItem) -> String {
        let p = item.params
        switch item.type {
        case "roleplay":
            return L("finished a roleplay in %@: “%@”", language(p["langKey"], fallback: p["lang"]), p["title"] ?? "")
        case "lesson":
            let kind = TaskType(rawValue: p["kind"] ?? "")?.label.lowercased() ?? ""
            return L("finished a %@ task in %@: “%@”", kind, language(p["langKey"], fallback: p["lang"]), p["title"] ?? "")
        case "vocab":
            return L("practised %@ German words · %@ right", p["count"] ?? "0", p["right"] ?? "0")
        case "plan":
            return L("shared a plan: %@ · %@", language(p["lang"], fallback: p["lang"]), p["title"] ?? "")
        case "streak":
            return L("reached a %@-day streak", p["days"] ?? "")
        default:
            return L("practised today")
        }
    }

    static func ago(_ date: Date) -> String {
        if Date().timeIntervalSince(date) < 60 { return L("just now") }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }
}

private struct ChallengeCard: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme
    let c: Social.Challenge

    private var title: String {
        switch c.type {
        case "duel": L("7-day streak duel")
        case "sprint": L("Minutes sprint · %lld min", c.goal)
        default: L("Same plan · %@", FeedText.language(c.lang, fallback: c.title))
        }
    }

    private var left: String {
        guard let end = c.endDay else { return L("Ongoing") }
        let today = DateUtil.dayKey()
        if end < today { return L("Finished") }
        if end == today { return L("Ends today") }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        let days = f.date(from: end).map { DateUtil.calendar.dateComponents([.day], from: DateUtil.calendar.startOfDay(for: Date()), to: $0).day ?? 0 } ?? 0
        return L("%lld days left", days)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: title).font(.fig(17, .bold))
                    Text(verbatim: c.rows.map { $0.uid == model.signedInUID ? L("You") : $0.name }.joined(separator: ", "))
                        .font(.fig(13)).foregroundStyle(theme.muted)
                }
                Spacer()
                Text(verbatim: left).font(.fig(12, .semibold)).foregroundStyle(theme.ad)
                    .padding(.horizontal, 10).frame(height: 26).background(theme.at, in: Capsule())
            }
            if c.type != "plan" {
                ForEach(c.rows, id: \.uid) { row in
                    let mine = row.uid == model.signedInUID
                    let target = Double(max(1, c.goal))
                    HStack(spacing: 10) {
                        Text(verbatim: mine ? L("You") : row.name.split(separator: " ").first.map(String.init) ?? row.name)
                            .font(.fig(13, .semibold)).frame(width: 64, alignment: .leading).lineLimit(1)
                        ProgressBar(value: min(1, Double(row.value) / target), color: mine ? theme.a : Hue(h: row.hue).base)
                        Text(verbatim: c.type == "duel" ? "\(row.value)/\(c.goal)" : "\(row.value)m")
                            .font(.fig(13, .semibold)).foregroundStyle(theme.muted).frame(width: 44, alignment: .trailing)
                    }
                }
            }
            if !c.pending.isEmpty {
                Text(L("Waiting for %@", c.pending.joined(separator: ", "))).font(.fig(13)).foregroundStyle(theme.muted)
            }
            if c.invitedMe {
                HStack(spacing: 8) {
                    Text(L("%@ invited you", c.creatorName)).font(.fig(13, .semibold))
                    Spacer()
                    PillButton(title: L("Decline"), bg: theme.chip, fg: theme.text, height: 32) {
                        Task { await model.respondChallenge(c, accept: false) }
                    }
                    PillButton(title: L("Join"), bg: theme.a, fg: .white, height: 32) {
                        Task { await model.respondChallenge(c, accept: true) }
                    }
                }
            } else {
                HStack {
                    if c.type == "plan", c.creator != model.signedInUID, let id = c.planId {
                        Button(L("Use this plan again")) { Task { await model.joinPlan(id) } }
                            .font(.fig(13, .semibold)).foregroundStyle(theme.ad)
                    }
                    Spacer()
                    Button(L("Leave")) { Task { await model.leaveChallenge(c) } }
                        .font(.fig(13)).foregroundStyle(theme.muted)
                }
            }
        }
        .card()
    }
}

/// Pick friends (and a goal or plan) for a new challenge.
private struct StartChallengeSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    let type: String
    @State private var picked: Set<String> = []
    @State private var goal = 60
    @State private var planLang: String?
    @State private var busy = false

    private var title: String {
        switch type {
        case "duel": L("Streak duel")
        case "sprint": L("Minutes sprint")
        default: L("Learn the same plan")
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(title).font(.fig(24, .bold))
                    Spacer()
                    BackButton(systemName: "xmark") { dismiss() }
                }
                .padding(.top, 20)
                Text(type == "duel" ? L("Pick one friend.") : L("Pick up to five friends.")).font(.fig(14)).foregroundStyle(theme.muted)
                VStack(spacing: 0) {
                    ForEach(Array(model.friends.enumerated()), id: \.element.id) { i, f in
                        let on = picked.contains(f.uid)
                        Button {
                            if type == "duel" { picked = on ? [] : [f.uid] }
                            else if on { picked.remove(f.uid) } else if picked.count < 5 { picked.insert(f.uid) }
                            Haptics.tap()
                        } label: {
                            HStack(spacing: 12) {
                                Avatar(initial: f.initial, hue: Hue(h: f.hue), size: 36, uid: f.uid, photo: f.photoVersion)
                                Text(verbatim: f.name).font(.fig(15, .semibold))
                                Spacer()
                                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 20)).foregroundStyle(on ? theme.a : theme.muted)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .overlay(alignment: .top) { if i > 0 { Rectangle().fill(theme.line).frame(height: 1) } }
                    }
                }
                .card(padding: 0)

                if type == "sprint" {
                    Stepper(value: $goal, in: 20...600, step: 10) {
                        Text(L("Goal: %lld min each", goal)).font(.fig(15, .semibold))
                    }
                    .card(padding: 14)
                }
                if type == "plan" {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("Which plan?")).font(.fig(15, .semibold))
                        FlowLayout(spacing: 8) {
                            ForEach(model.languages.filter { model.s.plans[$0.key] != nil }) { l in
                                let on = (planLang ?? model.s.learning.first) == l.key
                                PillButton(title: l.name, bg: on ? theme.a : theme.chip, fg: on ? .white : theme.text, height: 34) {
                                    planLang = l.key
                                }
                            }
                        }
                    }
                    .card(padding: 14)
                }

                Button(busy ? L("Sending…") : L("Send invite")) {
                    busy = true
                    Task {
                        let ok = await model.startChallenge(type: type, friends: Array(picked),
                                                            goalMinutes: type == "sprint" ? goal : nil,
                                                            planLang: type == "plan" ? (planLang ?? model.s.learning.first) : nil)
                        busy = false
                        if ok { dismiss() }
                    }
                }
                .buttonStyle(.primary)
                .disabled(picked.isEmpty || busy)
            }
            .padding(.horizontal, 20).padding(.bottom, 20)
        }
        .background(theme.ground)
    }
}

// MARK: - Practice with a friend

struct FriendChatView: View {
    let friendID: String
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var suggesting = false
    @State private var confirmRemove = false

    var body: some View {
        let f = model.friend(friendID)
        let lang = f.flatMap { model.chatLanguage(with: $0) }
        let messages = model.chats[friendID] ?? []

        VStack(spacing: 0) {
            HStack(spacing: 12) {
                BackButton { dismiss() }
                if let f { Avatar(initial: f.initial, hue: Hue(h: f.hue), size: 40, uid: f.uid, photo: f.photoVersion) }
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: f?.name ?? "").font(.fig(16, .bold))
                    Text(lang.map { L("Practising %@ together", $0.name) } ?? (f?.atHandle ?? ""))
                        .font(.fig(13)).foregroundStyle(theme.muted)
                }
                Spacer()
                Menu {
                    if let f, !f.practisedToday {
                        Button(L("Nudge")) { model.nudge(f.uid) }
                    }
                    Button(L("Remove friend"), role: .destructive) { confirmRemove = true }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 16, weight: .semibold)).foregroundStyle(theme.text)
                        .frame(width: 40, height: 40).background(theme.chip, in: Circle())
                }
                .accessibilityLabel(L("More"))
            }
            .padding(.horizontal, 20).padding(.vertical, 8)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if messages.isEmpty {
                            Text(L("Say hi in %@. ChatGPT points out one mistake at a time — only you see it.", lang?.name ?? ""))
                                .font(.fig(14)).foregroundStyle(theme.muted).multilineTextAlignment(.center).padding(.top, 30)
                        }
                        ForEach(messages) { m in
                            ChatBubble(text: m.text, mine: m.mine, speakLang: lang?.key)
                            if let c = m.correction {
                                CorrectionBubble(wrong: c.wrong, right: c.right, note: c.note, header: L("ChatGPT · only you see this"))
                            }
                        }
                        if model.friendSending {
                            TypingIndicator(label: model.aiAvailable ? L("Checking your message…") : L("Sending…"))
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 20).padding(.vertical, 8)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: messages.count) { withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
                .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
            }

            if model.aiAvailable {
                HStack {
                    PillButton(title: suggesting ? L("Thinking…") : L("Suggest a reply"), icon: "sparkles",
                               bg: theme.at, fg: theme.ad, height: 34) {
                        guard !suggesting else { return }
                        suggesting = true
                        Task {
                            if let s = await model.suggestReply(to: friendID) { draft = s }
                            suggesting = false
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 20).padding(.top, 4)
            }

            ChatInputBar(text: $draft, placeholder: L("Write in %@…", lang?.name ?? ""), disabled: model.friendSending,
                         speechLanguage: lang?.key) {
                let t = draft
                draft = ""
                Task { await model.sendFriend(t, to: friendID) }
            }
        }
        .background(theme.ground)
        .onAppear { model.openChat = friendID }
        .onDisappear { if model.openChat == friendID { model.openChat = nil } }
        .task(id: friendID) {
            // Poll while the chat is open.
            while !Task.isCancelled {
                await model.loadChat(friendID)
                try? await Task.sleep(for: .seconds(5))
            }
        }
        .confirmationDialog(L("Remove %@ from friends?", f?.name ?? ""), isPresented: $confirmRemove, titleVisibility: .visible) {
            Button(L("Remove friend"), role: .destructive) { Task { await model.removeFriend(friendID) } }
        }
    }
}
