import SwiftUI

struct MeView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme
    @State private var confirmLogout = false
    @State private var confirmDelete = false

    var body: some View {
        let user = model.s.user
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    Avatar(initial: user?.initial ?? "A", hue: Hue(h: theme.accent.hue), size: 60)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: user?.name ?? "").font(.fig(22, .bold))
                        Text(verbatim: user?.handle ?? "").font(.fig(14)).foregroundStyle(theme.muted)
                    }
                }
                .padding(.top, 10)

                HStack(spacing: 10) {
                    stat("\(model.s.streak)", L("day streak"), icon: "flame")
                    stat("\(model.myWeekMinutes)", L("min this week"), icon: "clock")
                    stat("\(model.friends.count + model.s.addedFriends.count)", L("friends"), icon: "person.2")
                }

                SectionLabel(text: L("My languages")).padding(.top, 6)
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
                                        Text(verbatim: l.name).font(.fig(15, .semibold))
                                        Spacer()
                                        Text(verbatim: "\(lv.code) → \(lv.next.code)").font(.fig(13, .semibold)).foregroundStyle(theme.muted)
                                    }
                                    ProgressBar(value: progress(l.key, index: i), color: h.base, height: 6)
                                }
                                Image(systemName: "chevron.forward").font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.muted)
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
                            Text(L("Add a language")).font(.fig(15, .semibold))
                            Spacer()
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .top) { Rectangle().fill(theme.line).frame(height: 1) }
                }
                .card(padding: 0)

                Button { model.showWords = true } label: {
                    WordsSummaryCard()
                }
                .buttonStyle(.plain)

                SectionLabel(text: L("Settings")).padding(.top, 6)
                VStack(spacing: 0) {
                    row(L("ChatGPT"), sub: aiStatus, first: true) {
                        Image(systemName: model.aiAvailable ? "checkmark.circle.fill" : "exclamationmark.circle")
                            .foregroundStyle(model.aiAvailable ? theme.a : theme.muted)
                    }
                    row(L("Adapt tasks daily"), sub: L("ChatGPT adjusts today from your results")) {
                        LingoraSwitch(isOn: $model.s.settings.adaptDaily)
                    }
                    row(L("Daily reminder"), sub: L("A gentle nudge at 19:00")) {
                        LingoraSwitch(isOn: Binding(get: { model.s.settings.reminders }, set: { model.setReminders($0) }))
                    }
                    row(L("App language"), sub: L("Lingora follows your iPhone's language. ChatGPT answers in it too.")) {
                        Button(L("Change")) {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }
                        .font(.fig(14, .semibold)).foregroundStyle(theme.ad)
                    }
                }
                .card(padding: 0)

                SectionLabel(text: L("Appearance")).padding(.top, 6)
                VStack(spacing: 0) {
                    row(L("Accent"), first: true) {
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
                    row(L("Style")) {
                        Picker(L("Style"), selection: $model.s.settings.direction) {
                            ForEach(Direction.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented).frame(maxWidth: 180)
                    }
                    row(L("Per-language colours")) {
                        LingoraSwitch(isOn: $model.s.settings.languageTints)
                    }
                }
                .card(padding: 0)

                SectionLabel(text: L("Account")).padding(.top, 6)
                VStack(spacing: 0) {
                    row(L("Signed in with"), sub: user?.email ?? "", first: true) {
                        Text(verbatim: user?.authMethod.label ?? "").font(.fig(14, .semibold)).foregroundStyle(theme.muted)
                    }
                    row(L("Sync"), sub: model.signedInUID != nil ? L("Your progress syncs to your account.") : L("Progress is saved on this iPhone only.")) {
                        Image(systemName: model.signedInUID != nil ? "icloud" : "iphone").foregroundStyle(theme.muted)
                    }
                }
                .card(padding: 0)

                Button(L("Log out")) { confirmLogout = true }
                    .font(.fig(16, .semibold))
                    .foregroundStyle(theme.errorText)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .padding(.top, 6)
                if model.signedInUID != nil {
                    Button(L("Delete account")) { confirmDelete = true }
                        .font(.fig(14))
                        .foregroundStyle(theme.muted)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 24)
        }
        .background(theme.ground)
        .confirmationDialog(L("Log out of Lingora?"), isPresented: $confirmLogout, titleVisibility: .visible) {
            Button(L("Log out"), role: .destructive) { model.logOut() }
        } message: {
            Text(model.signedInUID != nil ? L("Your progress stays in your account.") : L("Your plans and progress on this iPhone will be cleared."))
        }
        .confirmationDialog(L("Delete your account?"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(L("Delete account"), role: .destructive) {
                Task {
                    do {
                        try await AuthService.shared.deleteAccount()
                        model.logOut()
                    } catch {
                        model.toast = L("For security, log out and sign in again, then delete your account.")
                    }
                }
            }
        } message: {
            Text(L("This removes your account and synced progress. It can't be undone."))
        }
    }

    private var aiStatus: String {
        if !Backend.isConfigured { return L("Offline mode · using standard plans") }
        return model.aiAvailable ? L("On · plans, lessons and tutor run on the Lingora server") : L("Sign in to turn it on")
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
            Text(verbatim: value).font(.fig(22, .bold))
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
