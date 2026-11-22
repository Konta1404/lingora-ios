import SwiftUI

struct PlanView: View {
    let fromOnboarding: Bool
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme
    @State private var selectedDay: Int?

    private var langKey: String? {
        if let p = model.planLang, model.s.learning.contains(p) { return p }
        return model.s.learning.first
    }

    var body: some View {
        VStack(spacing: 0) {
            if fromOnboarding {
                SetupHeader()
            }
            if model.generating || langKey.flatMap({ model.s.plans[$0] }) == nil {
                generatingView
            } else if let key = langKey, let lang = model.language(key), let plan = model.s.plans[key] {
                ready(lang: lang, plan: plan)
            }
        }
        .background(theme.ground)
    }

    // MARK: Generating

    private var generatingView: some View {
        let steps = [
            L("Reading your goals"),
            L("Placing you: %@", model.languages.map { "\($0.code) \(model.level($0.key).code)" }.joined(separator: " · ")),
            L("Splitting %lld min across %lld (languages)", model.s.dailyMinutes, model.languages.count),
            L("Writing today's tasks")
        ]
        return VStack(alignment: .leading, spacing: 18) {
            Spacer()
            ScreenTitle(text: model.aiAvailable ? L("ChatGPT is building your week") : L("Building your week"))
            ProgressBar(value: Double(model.planStep) / 4)
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(steps.enumerated()), id: \.offset) { i, label in
                    let done = i < model.planStep
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(done ? theme.a : theme.chip2).frame(width: 24, height: 24)
                            if done { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white) }
                        }
                        Text(label).font(.fig(15, i == model.planStep ? .bold : .medium))
                    }
                    .opacity(i <= model.planStep ? 1 : 0.4)
                    .animation(.easeInOut(duration: 0.3), value: model.planStep)
                }
            }
            .card()
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 20)
    }

    // MARK: Ready

    @ViewBuilder
    private func ready(lang: Language, plan: WeeklyPlan) -> some View {
        let h = theme.colors(for: lang.hue)
        let sel = selectedDay ?? model.todayIndex
        let day = plan.days[safe: sel] ?? PlanDay(focus: "", tasks: [])
        let date = DateUtil.calendar.date(byAdding: .day, value: sel, to: plan.weekStart) ?? Date()

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScreenTitle(text: fromOnboarding ? L("Your week is ready") : L("This week"))
                    .padding(.top, fromOnboarding ? 0 : 10)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(model.languages) { l in
                            let lh = theme.colors(for: l.hue)
                            let on = l.key == lang.key
                            Button { model.planLang = l.key } label: {
                                HStack(spacing: 6) {
                                    Text(l.code).font(.fig(10, .bold))
                                        .foregroundStyle(on ? .white : theme.text)
                                        .frame(width: 24, height: 24)
                                        .background(on ? lh.base : theme.card, in: Circle())
                                    Text(verbatim: "\(l.name) · \(model.level(l.key).code)").font(.fig(14, .semibold))
                                }
                                .foregroundStyle(on ? lh.deep : theme.text)
                                .padding(.leading, 5).padding(.trailing, 12).frame(height: 36)
                                .background(on ? lh.tint : theme.chip, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                HStack(spacing: 6) {
                    ForEach(0..<7, id: \.self) { i in
                        let on = i == sel
                        let d = DateUtil.calendar.date(byAdding: .day, value: i, to: plan.weekStart) ?? Date()
                        let dotColor: Color = {
                            if i < model.todayIndex && didPractise(plan: plan, day: i) { return on ? .white : h.base }
                            if i == model.todayIndex { return on ? .white : theme.muted }
                            return .clear
                        }()
                        Button { selectedDay = i } label: {
                            VStack(spacing: 4) {
                                Text(verbatim: DateUtil.shortDays[i]).font(.fig(12, .semibold)).opacity(0.8)
                                Text(verbatim: "\(DateUtil.calendar.component(.day, from: d))").font(.fig(17, .bold))
                                Circle().fill(dotColor).frame(width: 5, height: 5)
                            }
                            .foregroundStyle(on ? .white : theme.text)
                            .frame(maxWidth: .infinity, minHeight: 70)
                            .background(on ? h.base : theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(on ? .clear : theme.cardBorder, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(DateUtil.format(date, "EEEEdMMMM")).font(.fig(17, .bold))
                            Text(day.focus).font(.fig(14)).foregroundStyle(theme.muted)
                        }
                        Spacer()
                        Text(L("%lld min", day.tasks.reduce(0) { $0 + $1.minutes })).font(.fig(14, .semibold)).foregroundStyle(theme.muted)
                    }
                    ForEach(day.tasks) { t in
                        HStack(spacing: 12) {
                            Circle().fill(h.base).frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(t.type.label).font(.fig(12, .semibold)).foregroundStyle(theme.muted)
                                Text(t.title).font(.fig(15, .semibold))
                            }
                            Spacer()
                            Text(L("%lld min", t.minutes)).font(.fig(13)).foregroundStyle(theme.muted)
                        }
                        .padding(.top, 10)
                        .overlay(alignment: .top) { Rectangle().fill(theme.line).frame(height: 1) }
                    }
                    if day.tasks.isEmpty {
                        Text(L("A rest day. Nothing planned.")).font(.fig(14)).foregroundStyle(theme.muted)
                    }
                }
                .card()

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "sparkles").padding(.top, 2)
                    MD(L("**Why this plan.** %@", plan.rationale))
                }
                .tintedNote(theme.at, theme.ad, radius: theme.radius)

                if let notice = model.planNotice {
                    Text(notice).font(.fig(13)).foregroundStyle(theme.muted)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }

        HStack(spacing: 10) {
            if fromOnboarding {
                Button(L("Redo")) { Task { await model.buildPlans() } }
                    .buttonStyle(PrimaryButtonStyle(kind: .chip))
                    .frame(width: 110)
                Button(L("Start my week")) {
                    model.s.onboarded = true
                    model.onboardingPath = []
                    model.tab = .today
                }
                .buttonStyle(.primary)
            } else {
                Button { Task { await model.buildPlans() } } label: {
                    Label(model.aiAvailable ? L("Ask ChatGPT to re-plan") : L("Re-plan my week"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(PrimaryButtonStyle(kind: .chip))
                if model.socialAvailable {
                    Button { Task { await model.sharePlan(lang.key) } } label: {
                        Label(L("Share"), systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(PrimaryButtonStyle(kind: .chip))
                    .frame(width: 120)
                }
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    private func didPractise(plan: WeeklyPlan, day: Int) -> Bool {
        guard let date = DateUtil.calendar.date(byAdding: .day, value: day, to: plan.weekStart) else { return false }
        let k = DateUtil.dayKey(date)
        return plan.days[safe: day]?.tasks.contains { model.s.done["\(k)|\($0.id)"] == true } ?? false
    }
}
