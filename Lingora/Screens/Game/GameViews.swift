import SwiftUI

/// Today: XP ring toward the daily goal, streak with freezes, and the three daily quests.
struct DailyGoalCard: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme
    @State private var showStreak = false
    @State private var showShop = false
    @State private var chestResult: String?

    var body: some View {
        let xp = model.today.xp, goal = max(1, model.s.settings.dailyXPGoal)
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                ZStack {
                    Circle().stroke(theme.chip, lineWidth: 8)
                    Circle().trim(from: 0, to: min(1, Double(xp) / Double(goal)))
                        .stroke(theme.a, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.5), value: xp)
                    VStack(spacing: 0) {
                        Text(verbatim: "\(xp)").font(.fig(18, .bold))
                        Text(verbatim: "/\(goal) XP").font(.fig(10, .semibold)).foregroundStyle(theme.muted)
                    }
                }
                .frame(width: 70, height: 70)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(xp >= goal ? L("Daily goal reached") : L("Daily goal")).font(.fig(16, .bold))
                        if model.doubleXPActive {
                            Text(verbatim: "2× XP").font(.fig(11, .bold)).foregroundStyle(.white)
                                .padding(.horizontal, 6).frame(height: 20).background(Color.orange, in: Capsule())
                        }
                    }
                    Button { showStreak = true } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "flame.fill").foregroundStyle(model.practisedToday ? Color.orange : theme.muted)
                            Text(L("%lld days", model.streak)).font(.fig(14, .semibold))
                            if model.s.streakFreezes > 0 {
                                Image(systemName: "snowflake").foregroundStyle(Color.cyan)
                                Text(verbatim: "\(model.s.streakFreezes)").font(.fig(14, .semibold))
                            }
                            Image(systemName: "chevron.forward").font(.system(size: 11, weight: .bold)).foregroundStyle(theme.muted)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("Streak calendar"))
                }
                Spacer(minLength: 0)
                Button { showShop = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "diamond.fill").foregroundStyle(Color.cyan)
                        Text(verbatim: "\(model.s.gems)").font(.fig(15, .bold)).foregroundStyle(theme.text)
                    }
                    .padding(.horizontal, 10).frame(height: 32).background(theme.chip, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("Shop · %lld gems", model.s.gems))
            }
            if model.chestReady {
                Button {
                    let r = model.openChest()
                    chestResult = r.doubleXP ? L("Double XP for 15 minutes!") : L("+%lld gems", r.gems)
                    SoundFX.play(.done)
                    Haptics.success()
                } label: {
                    Label(L("Open today's chest"), systemImage: "gift.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle(kind: .accent, height: 44))
            } else if let chestResult {
                Label(chestResult, systemImage: "gift.fill").font(.fig(14, .semibold)).foregroundStyle(theme.ad)
            }
            if let r = model.s.repairDay {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "bandage.fill").padding(.top, 2)
                    Text(L("You missed %@. Finish 2 lessons today to repair your streak (%lld/2).",
                           DateUtil.format(DateUtil.date(r), "EEEE"), min(2, model.today.lessons)))
                        .font(.fig(13))
                }
                .tintedNote(theme.errorTint, theme.errorText, radius: 14)
            }
            Rectangle().fill(theme.line).frame(height: 1)
            Text(L("Daily quests")).font(.fig(13, .semibold)).foregroundStyle(theme.muted)
            ForEach(model.todaysQuests) { q in QuestRow(quest: q) }
        }
        .card()
        .sheet(isPresented: $showShop) {
            ShopView().environmentObject(model).environment(\.theme, model.theme)
                .presentationDetents([.medium, .large]).presentationCornerRadius(28)
        }
        .sheet(isPresented: $showStreak) {
            StreakView()
                .environmentObject(model)
                .environment(\.theme, model.theme)
                .presentationDetents([.large])
                .presentationCornerRadius(28)
        }
    }
}

struct QuestRow: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme
    let quest: Quest

    var body: some View {
        let done = model.questDone(quest)
        let p = min(quest.target, quest.progress(model.today, minutes: model.todayMinutes))
        HStack(spacing: 12) {
            Image(systemName: done ? "checkmark" : quest.icon).font(.system(size: 14, weight: .bold))
                .foregroundStyle(done ? .white : theme.ad)
                .frame(width: 34, height: 34).background(done ? theme.a : theme.at, in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(quest.title).font(.fig(14, .semibold)).strikethrough(done, color: theme.muted)
                    Spacer()
                    Text(verbatim: done ? "+\(quest.reward) XP" : "\(p)/\(quest.target)").font(.fig(12, .semibold)).foregroundStyle(theme.muted)
                }
                ProgressBar(value: Double(p) / Double(max(1, quest.target)), height: 5)
            }
        }
    }
}

/// Month calendar of practice days, current and best streak, freezes.
struct StreakView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var month = DateUtil.calendar.date(from: DateUtil.calendar.dateComponents([.year, .month], from: Date())) ?? Date()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(L("Streak")).font(.fig(24, .bold))
                    Spacer()
                    BackButton(systemName: "xmark") { dismiss() }
                }
                .padding(.top, 20)
                HStack(spacing: 10) {
                    stat("\(model.streak)", L("day streak"), icon: "flame.fill", color: .orange)
                    stat("\(model.s.bestStreak)", L("best streak"), icon: "trophy.fill", color: theme.a)
                    stat("\(model.s.streakFreezes)/2", L("freezes"), icon: "snowflake", color: .cyan)
                }
                calendar
                if model.streak > 0 {
                    ShareCardButton(card: ShareCard(icon: "flame.fill", value: "\(model.streak)", title: L("day streak"),
                                                    subtitle: L("Learning languages every day with Lingora"), color: .orange))
                        .frame(maxWidth: .infinity)
                }
                Text(L("A streak freeze covers one missed day. You earn one for every 7 days of streak and can keep two. Missed a day without one? Finish 2 lessons the next day to repair it."))
                    .font(.fig(13)).foregroundStyle(theme.muted)
            }
            .padding(.horizontal, 20).padding(.bottom, 24)
        }
        .background(theme.ground)
    }

    private var calendar: some View {
        let cal = DateUtil.calendar
        let days = cal.range(of: .day, in: .month, for: month)?.count ?? 30
        let lead = DateUtil.weekdayIndex(month)
        let symbols = (0..<7).map { i in DateUtil.format(cal.date(byAdding: .day, value: i, to: DateUtil.weekStart()) ?? Date(), "EEEEE") }
        return VStack(spacing: 12) {
            HStack {
                Button { month = cal.date(byAdding: .month, value: -1, to: month) ?? month } label: { Image(systemName: "chevron.backward") }
                    .accessibilityLabel(L("Previous month"))
                Spacer()
                Text(DateUtil.format(month, "MMMMy")).font(.fig(16, .bold))
                Spacer()
                Button { month = cal.date(byAdding: .month, value: 1, to: month) ?? month } label: { Image(systemName: "chevron.forward") }
                    .disabled(cal.isDate(month, equalTo: Date(), toGranularity: .month))
                    .accessibilityLabel(L("Next month"))
            }
            .font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.text)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(0..<7, id: \.self) { i in Text(verbatim: symbols[i]).font(.fig(11, .semibold)).foregroundStyle(theme.muted) }
                ForEach(0..<lead, id: \.self) { _ in Color.clear.frame(height: 36) }
                ForEach(1...days, id: \.self) { d in
                    let date = cal.date(byAdding: .day, value: d - 1, to: month) ?? month
                    let k = DateUtil.dayKey(date)
                    let active = (model.s.activity[k] ?? 0) >= 60
                    let frozen = model.s.frozenDays.contains(k)
                    let isToday = cal.isDateInToday(date)
                    Text(verbatim: "\(d)").font(.fig(13, active || isToday ? .bold : .regular))
                        .foregroundStyle(active ? .white : frozen ? Color.cyan : theme.text)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(active ? Color.orange : frozen ? Color.cyan.opacity(0.18) : .clear, in: Circle())
                        .overlay(Circle().strokeBorder(isToday ? theme.a : .clear, lineWidth: 2))
                }
            }
        }
        .card()
    }

    private func stat(_ value: String, _ label: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(color)
            Text(verbatim: value).font(.fig(22, .bold))
            Text(label).font(.fig(12, .semibold)).foregroundStyle(theme.muted).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 14)
    }
}

/// Me: badges with up to five tiers each.
struct AchievementsSection: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme
    @State private var selected: Achievement?

    private func value(_ a: Achievement) -> Int { model.achievementValue(a.kind) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: L("Achievements")).padding(.top, 6)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 12) {
                ForEach(Achievement.all) { a in
                    let lv = a.level(for: value(a))
                    Button { selected = selected == a ? nil : a } label: {
                        VStack(spacing: 6) {
                            Image(systemName: a.icon).font(.system(size: 20, weight: .bold))
                                .foregroundStyle(lv.reached > 0 ? .white : theme.muted)
                                .frame(width: 54, height: 54)
                                .background(lv.reached > 0 ? theme.a : theme.chip, in: Circle())
                                .overlay(Circle().strokeBorder(selected == a ? theme.ad : .clear, lineWidth: 2))
                            HStack(spacing: 1) {
                                ForEach(0..<a.tiers.count, id: \.self) { i in
                                    Image(systemName: "star.fill").font(.system(size: 7))
                                        .foregroundStyle(i < lv.reached ? Color.orange : theme.chip2)
                                }
                            }
                            Text(a.title).font(.fig(11, .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(a.title), \(lv.reached)/\(a.tiers.count)")
                }
            }
            if let a = selected {
                let v = value(a), lv = a.level(for: v)
                VStack(alignment: .leading, spacing: 6) {
                    Text(a.title).font(.fig(15, .bold))
                    if lv.reached > 0 {
                        ShareCardButton(card: ShareCard(icon: a.icon, value: String(repeating: "★", count: lv.reached), title: a.title,
                                                        subtitle: a.detail(a.tiers[lv.reached - 1]), color: Color(hex: 0xE8A33D)))
                    }
                    if let next = lv.next {
                        Text(a.detail(next)).font(.fig(13)).foregroundStyle(theme.muted)
                        ProgressBar(value: Double(v) / Double(next), height: 6)
                        Text(verbatim: "\(v) / \(next)").font(.fig(12, .semibold)).foregroundStyle(theme.muted)
                    } else {
                        Text(L("All levels reached!")).font(.fig(13)).foregroundStyle(theme.muted)
                    }
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.at, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .card()
    }
}

/// Full-screen moments: daily goal, streak milestone, quest done, streak repaired.
struct CelebrationView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme
    let c: AppModel.Celebration
    @State private var pop = false

    var body: some View {
        ZStack {
            theme.ground.opacity(0.96).ignoresSafeArea()
            Confetti().ignoresSafeArea().allowsHitTesting(false)
            VStack(spacing: 18) {
                Spacer()
                Image(systemName: icon).font(.system(size: 52, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 120, height: 120).background(color, in: Circle())
                    .scaleEffect(pop ? 1 : 0.4)
                Text(title).font(.fig(28, .bold)).multilineTextAlignment(.center)
                Text(subtitle).font(.fig(16)).foregroundStyle(theme.muted).multilineTextAlignment(.center)
                Spacer()
                ShareCardButton(card: ShareCard(icon: icon, value: shareValue, title: title, subtitle: subtitle, color: color))
                Button(L("Continue")) { model.celebration = nil }.buttonStyle(.primary)
            }
            .padding(24)
        }
        .onAppear {
            SoundFX.play(.done)
            Haptics.success()
            withAnimation(.spring(duration: 0.5, bounce: 0.5)) { pop = true }
        }
    }

    private var shareValue: String {
        switch c {
        case .dailyGoal(let g): "\(g) XP"
        case .streak(let n): "\(n)"
        case .quest(_, let xp): "+\(xp) XP"
        case .repaired: "\(model.streak)"
        }
    }

    private var icon: String {
        switch c {
        case .dailyGoal: "target"
        case .streak: "flame.fill"
        case .quest: "flag.checkered"
        case .repaired: "bandage.fill"
        }
    }
    private var color: Color {
        switch c {
        case .streak, .repaired: .orange
        default: theme.a
        }
    }
    private var title: String {
        switch c {
        case .dailyGoal: L("Daily goal reached!")
        case .streak(let n): L("%lld-day streak!", n)
        case .quest: L("Quest complete!")
        case .repaired: L("Streak repaired!")
        }
    }
    private var subtitle: String {
        switch c {
        case .dailyGoal(let g): L("You earned %lld XP today. See you tomorrow?", g)
        case .streak: L("Keep it going — a little every day is how languages stick.")
        case .quest(let t, let xp): "\(t) · +\(xp) XP"
        case .repaired: L("Your streak is back where it was.")
        }
    }
}

/// Falling confetti, drawn with Canvas.
struct Confetti: View {
    private let pieces: [(x: Double, speed: Double, size: Double, hue: Double, spin: Double)] = (0..<70).map { _ in
        (Double.random(in: 0...1), Double.random(in: 0.12...0.3), Double.random(in: 6...11), Double.random(in: 0...1), Double.random(in: 1...4))
    }
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSince(start)
                for p in pieces {
                    let y = (t * p.speed * size.height + p.x * 300).truncatingRemainder(dividingBy: size.height + 40) - 20
                    let x = p.x * size.width + sin(t * p.spin + p.x * 10) * 18
                    var c = ctx
                    c.translateBy(x: x, y: y)
                    c.rotate(by: .radians(t * p.spin))
                    c.fill(Path(CGRect(x: -p.size / 2, y: -p.size / 4, width: p.size, height: p.size / 2)),
                           with: .color(Color(hue: p.hue, saturation: 0.6, brightness: 0.95)))
                }
            }
        }
    }
}

/// Friends tab: a weekly shared goal with one friend.
struct FriendsQuestCard: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        if let p = model.questPartner {
            let goal = AppModel.friendsQuestGoal
            let mine = model.myWeekXP, theirs = p.weekXP ?? 0
            let done = mine + theirs >= goal
            let claimed = model.s.claimedQuests.contains(model.friendsQuestKey)
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "person.2.fill").foregroundStyle(.white)
                        .frame(width: 36, height: 36).background(theme.a, in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text(L("Friends Quest")).font(.fig(16, .bold))
                        Text(L("Earn %lld XP together with %@ this week", goal, p.firstName)).font(.fig(13)).foregroundStyle(theme.muted)
                    }
                    Spacer(minLength: 0)
                    Text(L("%lld days left", LeagueStyle.daysLeft)).font(.fig(12, .semibold)).foregroundStyle(theme.ad)
                }
                GeometryReader { g in
                    let w = g.size.width
                    ZStack(alignment: .leading) {
                        Capsule().fill(theme.chip)
                        HStack(spacing: 0) {
                            Rectangle().fill(theme.a).frame(width: w * min(1, Double(mine) / Double(goal)))
                            Rectangle().fill(Hue(h: p.hue).base).frame(width: w * min(max(0, 1 - Double(mine) / Double(goal)), Double(theirs) / Double(goal)))
                        }
                        .clipShape(Capsule())
                    }
                }
                .frame(height: 12)
                HStack {
                    Label(L("You · %lld XP", mine), systemImage: "circle.fill").font(.fig(12)).foregroundStyle(theme.ad)
                    Spacer()
                    Label(L("%@ · %lld XP", p.firstName, theirs), systemImage: "circle.fill").font(.fig(12)).foregroundStyle(Hue(h: p.hue).deep)
                }
                if done && !claimed {
                    Button(L("Claim 25 XP")) { model.claimFriendsQuest() }.buttonStyle(PrimaryButtonStyle(kind: .accent, height: 44))
                } else if claimed {
                    Label(L("Quest complete!"), systemImage: "checkmark.seal.fill").font(.fig(14, .semibold)).foregroundStyle(theme.ad)
                }
            }
            .card()
        }
    }
}

struct ShopView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(L("Shop")).font(.fig(24, .bold))
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "diamond.fill").foregroundStyle(Color.cyan)
                        Text(verbatim: "\(model.s.gems)").font(.fig(17, .bold))
                    }
                    BackButton(systemName: "xmark") { dismiss() }
                }
                .padding(.top, 20)
                ForEach(ShopItem.allCases) { item in
                    HStack(spacing: 12) {
                        Image(systemName: item.icon).font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 46, height: 46).background(theme.a, in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).font(.fig(15, .bold))
                            Text(item.detail).font(.fig(12)).foregroundStyle(theme.muted)
                        }
                        Spacer(minLength: 4)
                        Button { model.buy(item) } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "diamond.fill").font(.system(size: 11))
                                Text(verbatim: "\(item.price)").font(.fig(14, .bold))
                            }
                            .foregroundStyle(model.canBuy(item) ? .white : theme.muted)
                            .padding(.horizontal, 12).frame(height: 34)
                            .background(model.canBuy(item) ? theme.a : theme.chip, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(!model.canBuy(item))
                    }
                    .card(padding: 14)
                }
                Text(L("Earn gems by finishing lessons, quests and your daily goal, and from the daily chest."))
                    .font(.fig(13)).foregroundStyle(theme.muted)
            }
            .padding(.horizontal, 20).padding(.bottom, 24)
        }
        .background(theme.ground)
    }
}

/// Today: this month's quest challenge and any running events.
struct ChallengesCard: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        let m = MonthlyChallenge.month
        let n = model.monthQuests, goal = MonthlyChallenge.goal
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: model.s.monthlyBadges.contains(m) ? "rosette" : "calendar").font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white).frame(width: 36, height: 36).background(Color.purple, in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("%@ challenge", MonthlyChallenge.title(m))).font(.fig(15, .bold))
                    Text(L("Complete %lld daily quests this month for a badge", goal)).font(.fig(12)).foregroundStyle(theme.muted)
                }
                Spacer(minLength: 0)
                Text(verbatim: "\(min(n, goal))/\(goal)").font(.fig(13, .bold)).foregroundStyle(theme.muted)
            }
            ProgressBar(value: Double(n) / Double(goal), color: .purple, height: 6)
            ForEach(LingoraEvent.active()) { e in
                let p = model.eventProgress(e), claimed = model.s.eventRewards.contains(e.id)
                Rectangle().fill(theme.line).frame(height: 1)
                HStack(spacing: 10) {
                    Image(systemName: e.icon).font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 36, height: 36).background(Color.orange, in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text(e.title).font(.fig(15, .bold))
                        Text("\(e.detail) · +\(e.gems) 💎").font(.fig(12)).foregroundStyle(theme.muted)
                    }
                    Spacer(minLength: 0)
                    if claimed {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(theme.a)
                    } else if p >= e.target {
                        PillButton(title: L("Claim"), bg: theme.a, fg: .white, height: 32) { model.claimEvent(e) }
                    } else {
                        Text(verbatim: "\(p)/\(e.target)").font(.fig(13, .bold)).foregroundStyle(theme.muted)
                    }
                }
                if !claimed { ProgressBar(value: Double(p) / Double(e.target), color: .orange, height: 6) }
            }
        }
        .card()
    }
}
