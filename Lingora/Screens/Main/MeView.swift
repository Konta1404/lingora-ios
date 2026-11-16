import SwiftUI

struct MeView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme
    @State private var showConnect = false
    @State private var confirmLogout = false

    var body: some View {
        let user = model.s.user
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    Avatar(initial: user?.initial ?? "A", hue: Hue(h: theme.accent.hue), size: 60)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(user?.name ?? "").font(.fig(22, .bold))
                        Text(user?.handle ?? "").font(.fig(14)).foregroundStyle(theme.muted)
                    }
                }
                .padding(.top, 10)

                HStack(spacing: 10) {
                    stat("\(model.s.streak)", "day streak", icon: "flame")
                    stat("\(model.myWeekMinutes)", "min this week", icon: "clock")
                    stat("\(model.friends.count + model.s.addedFriends.count)", "friends", icon: "person.2")
                }

                SectionLabel(text: "My languages").padding(.top, 6)
                VStack(spacing: 0) {
                    ForEach(Array(model.languages.enumerated()), id: \.element.id) { i, l in
                        let h = theme.colors(for: l.hue)
                        let lv = model.level(l.key)
                        Button {
                            model.planLang = l.key
                            model.tab = .plan
                        } label: {
                            HStack(spacing: 12) {
                                CodeBadge(code: l.code, hue: h, size: 36, filled: true)
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(l.name).font(.fig(15, .semibold))
                                        Spacer()
                                        Text("\(lv.code) → \(lv.next.code)").font(.fig(13, .semibold)).foregroundStyle(theme.muted)
                                    }
                                    ProgressBar(value: progress(l.key, index: i), color: h.base, height: 6)
                                }
                                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.muted)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .overlay(alignment: .top) { if i > 0 { Rectangle().fill(theme.line).frame(height: 1) } }
                    }
                    Button { model.mePath.append(.addLanguage) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "plus").font(.system(size: 14, weight: .bold)).foregroundStyle(theme.ad)
                                .frame(width: 36, height: 36).background(theme.at, in: Circle())
                            Text("Add a language").font(.fig(15, .semibold))
                            Spacer()
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .top) { Rectangle().fill(theme.line).frame(height: 1) }
                }
                .card(padding: 0)

                SectionLabel(text: "Settings").padding(.top, 6)
                VStack(spacing: 0) {
                    row("ChatGPT", sub: model.connected ? "Connected · plans, tasks and tutor on" : "Not connected · using standard plans", first: true) {
                        PillButton(title: model.connected ? "Disconnect" : "Connect",
                                   bg: model.connected ? theme.chip : theme.a, fg: model.connected ? theme.text : .white, height: 32) {
                            if model.connected { model.disconnect() } else { showConnect = true }
                        }
                    }
                    if model.connected {
                        row("Model", sub: "Used for plans, lessons and the tutor") {
                            TextField("gpt-5-mini", text: $model.s.settings.model)
                                .font(.fig(14, .semibold)).multilineTextAlignment(.trailing)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .frame(maxWidth: 140)
                        }
                    }
                    row("Adapt tasks daily", sub: "ChatGPT adjusts today from your results") {
                        LingoraSwitch(isOn: $model.s.settings.adaptDaily)
                    }
                    row("Daily reminder", sub: "A gentle nudge at 19:00") {
                        LingoraSwitch(isOn: Binding(get: { model.s.settings.reminders }, set: { model.setReminders($0) }))
                    }
                    row("Signed in with", sub: user?.email ?? "") {
                        Text(user?.authMethod.label ?? "").font(.fig(14, .semibold)).foregroundStyle(theme.muted)
                    }
                    row("Devices", sub: "Sync to iPad and Mac is coming next") {
                        Text("This iPhone").font(.fig(14, .semibold)).foregroundStyle(theme.muted)
                    }
                }
                .card(padding: 0)

                SectionLabel(text: "Appearance").padding(.top, 6)
                VStack(spacing: 0) {
                    row("Accent", first: true) {
                        HStack(spacing: 10) {
                            ForEach(Accent.allCases) { a in
                                Button { model.s.settings.accent = a } label: {
                                    Circle().fill(Hue(h: a.hue).base).frame(width: 26, height: 26)
                                        .overlay(Circle().strokeBorder(.white, lineWidth: model.s.settings.accent == a ? 3 : 0))
                                        .overlay(Circle().strokeBorder(Hue(h: a.hue).base, lineWidth: model.s.settings.accent == a ? 1.5 : 0).padding(-2))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(a.label)
                            }
                        }
                    }
                    row("Style") {
                        Picker("Style", selection: $model.s.settings.direction) {
                            ForEach(Direction.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented).frame(maxWidth: 180)
                    }
                    row("Per-language colours") {
                        LingoraSwitch(isOn: $model.s.settings.languageTints)
                    }
                }
                .card(padding: 0)

                Button("Log out") { confirmLogout = true }
                    .font(.fig(16, .semibold))
                    .foregroundStyle(theme.errorText)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .padding(.top, 6)
            }
            .padding(.horizontal, 20).padding(.bottom, 24)
        }
        .background(theme.ground)
        .sheet(isPresented: $showConnect) { ChatGPTSheet(mode: .connect) }
        .confirmationDialog("Log out of Lingora?", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("Log out", role: .destructive) { model.logOut() }
        } message: {
            Text("Your plans and progress on this iPhone will be cleared.")
        }
    }

    private func progress(_ key: String, index: Int) -> Double {
        let scores = model.s.results.filter { $0.langKey == key }.map(\.score)
        let base = [0.64, 0.38, 0.22, 0.15][index % 4]
        guard !scores.isEmpty else { return base }
        return min(0.95, base + Double(scores.reduce(0, +)) / 120)
    }

    private func stat(_ value: String, _ label: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.ad)
            Text(value).font(.fig(22, .bold))
            Text(label).font(.fig(12, .semibold)).foregroundStyle(theme.muted).lineLimit(1).minimumScaleFactor(0.8)
        }
        .card(padding: 14)
    }

    private func row<Trailing: View>(_ title: String, sub: String? = nil, first: Bool = false,
                                     @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.fig(15, .semibold))
                if let sub, !sub.isEmpty { Text(sub).font(.fig(13)).foregroundStyle(theme.muted) }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(minHeight: 56)
        .overlay(alignment: .top) { if !first { Rectangle().fill(theme.line).frame(height: 1) } }
    }
}
