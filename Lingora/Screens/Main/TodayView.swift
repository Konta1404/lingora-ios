import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        let tasks = model.todayTasks
        let done = tasks.filter(model.isDone)
        let left = tasks.reduce(0) { $0 + $1.minutes } - done.reduce(0) { $0 + $1.minutes }
        let next = tasks.first { !model.isDone($0) }
        let user = model.s.user

        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text(verbatim: DateUtil.format(Date(), "EEEEdMMMM")).font(.fig(14, .semibold)).foregroundStyle(theme.muted)
                        Spacer()
                        Label(L("%lld days", model.streak), systemImage: "flame")
                            .font(.fig(14, .semibold))
                            .padding(.horizontal, 12).frame(height: 32)
                            .background(theme.card, in: Capsule())
                            .overlay(Capsule().strokeBorder(theme.cardBorder, lineWidth: 1))
                    }
                    ScreenTitle(text: "\(Catalog.greeting[model.s.learning.first ?? ""] ?? L("Good morning")), \(user?.firstName ?? "")")

                    // Summary
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(L("%lld of %lld done", done.count, tasks.count)).font(.fig(14, .semibold))
                            Spacer()
                            Text(left > 0 ? L("%lld min left", left) : L("All done for today")).font(.fig(14)).foregroundStyle(theme.muted)
                        }
                        ProgressBar(value: tasks.isEmpty ? 0 : Double(done.count) / Double(tasks.count))
                        FlowLayout(spacing: 8) {
                            ForEach(model.languages) { l in
                                let h = theme.colors(for: l.hue)
                                let ts = tasks.filter { $0.langKey == l.key }
                                HStack(spacing: 6) {
                                    Text(l.code).font(.fig(9, .bold)).foregroundStyle(.white)
                                        .frame(width: 22, height: 22).background(h.base, in: Circle())
                                    Text(verbatim: "\(ts.filter(model.isDone).count)/\(ts.count)").font(.fig(13, .semibold))
                                }
                                .foregroundStyle(h.deep)
                                .padding(.leading, 4).padding(.trailing, 10).frame(height: 30)
                                .background(h.tint, in: Capsule())
                            }
                        }
                    }
                    .card()

                    if model.planIsStale {
                        VStack(alignment: .leading, spacing: 10) {
                            MD(L("**A new week.** Let %@ plan it around how last week went.", model.aiAvailable ? "ChatGPT" : "Lingora"))
                            Button(L("Plan my week")) {
                                model.tab = .plan
                                Task { await model.buildPlans() }
                            }
                            .buttonStyle(PrimaryButtonStyle(kind: .accent, height: 44))
                        }
                        .tintedNote(theme.at, theme.ad, radius: theme.radius)
                    } else if model.s.settings.adaptDaily, model.aiAvailable, let note = model.s.adaptNote {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "sparkles").padding(.top, 2)
                            MD(L("**Adjusted for today.** %@", note))
                        }
                        .tintedNote(theme.at, theme.ad, radius: theme.radius)
                    }

                    // Friends strip
                    Button { model.tab = .friends } label: {
                        let today = model.friends.filter(\.practisedToday)
                        HStack(spacing: 12) {
                            HStack(spacing: -8) {
                                ForEach(today.prefix(5)) { f in Avatar(initial: f.initial, hue: Hue(h: f.hue), size: 32, ring: theme.card, uid: f.uid, photo: f.photoVersion) }
                            }
                            Text(friendsLine(today.map(\.firstName))).font(.fig(14)).foregroundStyle(theme.text)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.muted)
                        }
                        .card(padding: 12)
                    }
                    .buttonStyle(.plain)

                    DailyGoalCard()

                    ForEach(model.courseLanguages) { l in
                        CourseSummaryCard(lang: l)
                    }

                    if model.learnsGerman {
                        Button { model.showWords = true } label: { WordsSummaryCard() }
                            .buttonStyle(.plain)
                    }

                    SectionLabel(text: L("Today's tasks")).padding(.top, 4)

                    VStack(spacing: 0) {
                        ForEach(Array(tasks.enumerated()), id: \.element.id) { i, t in
                            TaskRow(task: t, showSeparator: i > 0)
                        }
                        if tasks.isEmpty {
                            Text(L("No tasks today. Enjoy the rest.")).font(.fig(15)).foregroundStyle(theme.muted).padding(16)
                        }
                    }
                    .card(padding: 0)
                }
                .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 16)
            }

            Button(next.map { L("Continue: %@ · %@", model.language($0.langKey)?.name ?? "", $0.type.label.lowercased()) } ?? L("All done — see you tomorrow")) {
                if let next { model.open(next) }
            }
            .buttonStyle(.primary)
            .disabled(next == nil)
            .padding(.horizontal, 20).padding(.vertical, 10)
        }
        .background(theme.ground)
        .refreshable {
            await model.adaptTodayIfNeeded()
            await model.refreshSocial()
        }
    }

    private func friendsLine(_ names: [String]) -> String {
        if let n = model.social?.nudges.first { return L("%@ nudged you — a few minutes today?", n.name) }
        if let r = model.social?.incoming.first { return L("%@ wants to be friends", r.name) }
        switch names.count {
        case 0: return model.friends.isEmpty ? L("Invite friends to learn together") : L("None of your friends has practised yet today")
        case 1: return L("%@ practised today", names[0])
        default: return L("%@ and %@ practised today", names.dropLast().joined(separator: ", "), names.last!)
        }
    }
}

struct TaskRow: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme
    let task: PlanTask
    let showSeparator: Bool

    var body: some View {
        let l = model.language(task.langKey)
        let h = theme.colors(for: l?.hue ?? theme.accent.hue)
        let done = model.isDone(task)
        HStack(spacing: 12) {
            Button { model.open(task) } label: {
                HStack(spacing: 12) {
                    CodeBadge(code: l?.code ?? "", hue: h, size: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(verbatim: "\(task.type.label) · \(L("%lld min", task.minutes))").font(.fig(12, .semibold)).foregroundStyle(theme.muted)
                            if task.adapted && model.s.settings.adaptDaily && model.aiAvailable {
                                Text(L("adjusted")).font(.fig(12, .semibold)).foregroundStyle(theme.ad)
                                    .padding(.horizontal, 8).padding(.vertical, 1)
                                    .background(theme.at, in: Capsule())
                            }
                        }
                        Text(task.title).font(.fig(15, .semibold)).strikethrough(done)
                            .multilineTextAlignment(.leading)
                    }
                    .opacity(done ? 0.55 : 1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button { withAnimation(.easeInOut(duration: 0.2)) { model.toggleDone(task) } } label: {
                ZStack {
                    Circle().strokeBorder(done ? theme.a : theme.chip2, lineWidth: 2)
                        .background(Circle().fill(done ? theme.a : .clear))
                        .frame(width: 26, height: 26)
                    if done { Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white) }
                }
                .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(done ? L("Mark not done") : L("Mark done"))
        }
        .padding(.leading, 16).padding(.trailing, 6).padding(.vertical, 4)
        .overlay(alignment: .top) { if showSeparator { Rectangle().fill(theme.line).frame(height: 1) } }
    }
}
