import SwiftUI

struct FriendsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme
    @State private var tab = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    ScreenTitle(text: L("Friends"))
                    Spacer()
                    PillButton(title: L("Add"), icon: "plus", bg: theme.a, fg: .white) { model.showAddFriend = true }
                }
                segmented
                switch tab {
                case 0: feed
                case 1: board
                default: challenges
                }
            }
            .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 20)
        }
        .background(theme.ground)
    }

    private var segmented: some View {
        HStack(spacing: 0) {
            ForEach(Array([L("Activity"), L("This week"), L("Challenges")].enumerated()), id: \.offset) { i, label in
                Button { withAnimation(.easeInOut(duration: 0.2)) { tab = i } } label: {
                    Text(label).font(.fig(14, .semibold)).foregroundStyle(theme.text)
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .background(tab == i ? theme.card : .clear, in: Capsule())
                        .shadow(color: tab == i ? Color(hex: 0x2b2a28, opacity: 0.1) : .clear, radius: 2, y: 1)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(tab == i ? .isSelected : [])
            }
        }
        .padding(3)
        .frame(height: 36)
        .background(theme.chip, in: Capsule())
    }

    // MARK: Activity

    private var feed: some View {
        VStack(spacing: 10) {
            ForEach(SampleFriends.feed) { item in
                if let f = model.friend(item.friendID) {
                    let cheered = model.s.cheered.contains(item.id)
                    let joined = model.s.joined.contains(item.id)
                    VStack(alignment: .leading, spacing: 12) {
                        Button { model.friendsPath.append(f.id) } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Avatar(initial: f.initial, hue: Hue(h: f.hue), size: 40)
                                VStack(alignment: .leading, spacing: 2) {
                                    (Text(verbatim: f.firstName).font(.fig(15, .bold)) + Text(verbatim: " \(item.text)").font(.fig(15)))
                                        .multilineTextAlignment(.leading)
                                    Text(item.time).font(.fig(13)).foregroundStyle(theme.muted)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                        .buttonStyle(.plain)
                        HStack(spacing: 8) {
                            PillButton(title: L("Cheer · %lld", item.cheers + (cheered ? 1 : 0)),
                                       icon: cheered ? "heart.fill" : "heart",
                                       bg: cheered ? theme.at : theme.chip, fg: cheered ? theme.ad : theme.text, height: 34) {
                                model.toggle(\.cheered, item.id)
                            }
                            if item.isPlan {
                                PillButton(title: joined ? L("Joined") : L("Join plan"), icon: joined ? "checkmark" : nil,
                                           bg: joined ? theme.at : theme.a, fg: joined ? theme.ad : .white, height: 34) {
                                    model.toggle(\.joined, item.id)
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

    private var board: some View {
        var rows = model.friends.map {
            BoardRow(id: $0.id, name: $0.name, initial: $0.initial, hue: $0.hue,
                     minutes: $0.weekMinutes, streak: $0.streak, today: $0.practisedToday, isMe: false)
        }
        rows.append(BoardRow(id: "me", name: L("You"), initial: model.s.user?.initial ?? "Y", hue: theme.accent.hue,
                             minutes: model.myWeekMinutes, streak: model.s.streak, today: true, isMe: true))
        rows.sort { $0.minutes > $1.minutes }
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in
                let nudged = model.s.nudged.contains(r.id)
                HStack(spacing: 12) {
                    Text(verbatim: "\(i + 1)").font(.fig(14, .bold)).foregroundStyle(theme.muted).frame(width: 18)
                    Avatar(initial: r.initial, hue: Hue(h: r.hue), size: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(r.name).font(.fig(15, .semibold))
                        Text(L("%lld-day streak · %@", r.streak, r.today ? L("practised today") : L("not yet today")))
                            .font(.fig(12)).foregroundStyle(theme.muted)
                    }
                    Spacer(minLength: 0)
                    if !r.isMe && !r.today {
                        PillButton(title: nudged ? L("Nudged") : L("Nudge"), bg: nudged ? theme.at : theme.chip,
                                   fg: nudged ? theme.ad : theme.text, height: 30) {
                            if !nudged { model.toggle(\.nudged, r.id) }
                        }
                    }
                    Text(L("%lld min", r.minutes)).font(.fig(14, .semibold))
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
        let sprintMine = 20 + model.doneMinutesToday
        let you = theme.a
        let active: [Challenge] = [
            Challenge(title: L("7-day streak duel"), who: L("You and Marco"), left: L("2 days left"),
                      note: L("Day 5 of 7 — you’re both still in."),
                      rows: [.init(name: L("You"), value: 5.0 / 7, label: "5/7", color: you),
                             .init(name: "Marco", value: 5.0 / 7, label: "5/7", color: Hue(h: 110).base)]),
            Challenge(title: L("Weekend sprint"), who: L("You, Lena and Priya"), left: L("Ends Sunday"),
                      note: L("Everyone aims for 60 min — finish together, celebrate together."),
                      rows: [.init(name: L("You"), value: min(1, Double(sprintMine) / 60), label: "\(sprintMine)m", color: you),
                             .init(name: "Lena", value: 0.75, label: "45m", color: Hue(h: 20).base),
                             .init(name: "Priya", value: 0.25, label: "15m", color: Hue(h: 300).base)])
        ]
        let newOnes = [("duel", L("Streak duel"), L("Keep a streak going with a friend")),
                       ("sprint", L("Minutes sprint"), L("A shared goal for the weekend")),
                       ("plan", L("Learn the same plan"), L("ChatGPT builds one plan for both of you"))]
        return VStack(alignment: .leading, spacing: 10) {
            ForEach(active, id: \.title) { c in
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: c.title).font(.fig(17, .bold))
                            Text(verbatim: c.who).font(.fig(13)).foregroundStyle(theme.muted)
                        }
                        Spacer()
                        Text(verbatim: c.left).font(.fig(12, .semibold)).foregroundStyle(theme.ad)
                            .padding(.horizontal, 10).frame(height: 26).background(theme.at, in: Capsule())
                    }
                    ForEach(c.rows, id: \.name) { row in
                        HStack(spacing: 10) {
                            Text(row.name).font(.fig(13, .semibold)).frame(width: 46, alignment: .leading)
                            ProgressBar(value: row.value, color: row.color)
                            Text(row.label).font(.fig(13, .semibold)).foregroundStyle(theme.muted).frame(width: 38, alignment: .trailing)
                        }
                    }
                    Text(c.note).font(.fig(13)).foregroundStyle(theme.muted)
                }
                .card()
            }
            SectionLabel(text: L("Start something new")).padding(.top, 8)
            VStack(spacing: 0) {
                ForEach(Array(newOnes.enumerated()), id: \.element.0) { i, n in
                    let on = model.s.startedChallenges.contains(n.0)
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(n.1).font(.fig(15, .semibold))
                            Text(n.2).font(.fig(13)).foregroundStyle(theme.muted)
                        }
                        Spacer()
                        PillButton(title: on ? L("Invite sent") : L("Start"), bg: on ? theme.at : theme.chip, fg: on ? theme.ad : theme.text, height: 34) {
                            if !on { model.toggle(\.startedChallenges, n.0) }
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

private struct BoardRow: Identifiable {
    var id: String
    var name: String
    var initial: String
    var hue: Double
    var minutes: Int
    var streak: Int
    var today: Bool
    var isMe: Bool
}

private struct Challenge {
    struct Row { var name: String; var value: Double; var label: String; var color: Color }
    var title: String
    var who: String
    var left: String
    var note: String
    var rows: [Row]
}

// MARK: - Practice with a friend

struct FriendChatView: View {
    let friendID: String
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""

    var body: some View {
        let f = model.friend(friendID)
        let langName = f.flatMap { model.language($0.chatLang)?.name } ?? ""
        let messages = model.friendMessages(friendID)

        VStack(spacing: 0) {
            HStack(spacing: 12) {
                BackButton { dismiss() }
                if let f { Avatar(initial: f.initial, hue: Hue(h: f.hue), size: 40) }
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: f?.name ?? "").font(.fig(16, .bold))
                    Text(L("Practising %@ together", langName)).font(.fig(13)).foregroundStyle(theme.muted)
                }
                Spacer()
            }
            .padding(.horizontal, 20).padding(.vertical, 8)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(messages) { m in
                            switch m.role {
                            case .correction:
                                CorrectionBubble(wrong: m.wrong ?? "", right: m.right ?? "", note: m.note ?? "",
                                                 header: L("ChatGPT · only you see this"))
                            default:
                                ChatBubble(text: m.text, mine: m.role == .me)
                            }
                        }
                        if model.friendTyping {
                            TypingIndicator(label: L("%@ is typing…", f?.firstName ?? ""))
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 20).padding(.vertical, 8)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: messages.count) { withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
                .onChange(of: model.friendTyping) { withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
                .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
            }

            HStack {
                PillButton(title: L("Suggest a reply"), icon: "sparkles", bg: theme.at, fg: theme.ad, height: 34) {
                    if let f, let s = SampleFriends.chats[f.chatLang]?.suggestion { draft = s }
                }
                Spacer()
            }
            .padding(.horizontal, 20).padding(.top, 4)

            ChatInputBar(text: $draft, placeholder: L("Write in %@…", langName), disabled: model.friendTyping) {
                let t = draft
                draft = ""
                Task { await model.sendFriend(t, to: friendID) }
            }
        }
        .background(theme.ground)
    }
}
