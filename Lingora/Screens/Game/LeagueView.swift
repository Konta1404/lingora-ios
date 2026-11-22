import SwiftUI

enum LeagueStyle {
    static func color(_ tier: Int) -> Color {
        [Color(red: 0.72, green: 0.45, blue: 0.25), Color(white: 0.62), Color(red: 0.93, green: 0.73, blue: 0.16),
         Color(red: 0.2, green: 0.45, blue: 0.9), Color(red: 0.86, green: 0.2, blue: 0.3), Color(red: 0.15, green: 0.68, blue: 0.42),
         Color(red: 0.6, green: 0.35, blue: 0.85), Color(red: 0.82, green: 0.8, blue: 0.86), Color(white: 0.22),
         Color(red: 0.3, green: 0.8, blue: 0.95)][min(max(tier, 0), 9)]
    }
    static func name(_ tier: Int) -> String {
        [L("Bronze"), L("Silver"), L("Gold"), L("Sapphire"), L("Ruby"), L("Emerald"), L("Amethyst"), L("Pearl"), L("Obsidian"), L("Diamond")][min(max(tier, 0), 9)]
    }
    static var daysLeft: Int {
        let end = DateUtil.calendar.date(byAdding: .day, value: 7, to: DateUtil.weekStart()) ?? Date()
        return max(0, DateUtil.calendar.dateComponents([.day], from: DateUtil.calendar.startOfDay(for: Date()), to: end).day ?? 0)
    }
}

/// Today: your league, rank and XP this week.
struct LeagueCard: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme
    @State private var open = false

    var body: some View {
        let l = model.league
        let tier = l?.tier ?? 0
        Button { open = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "shield.lefthalf.filled").font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 44, height: 44).background(LeagueStyle.color(tier), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("%@ League", LeagueStyle.name(tier))).font(.fig(16, .bold))
                    if let l, l.joined, let me = l.members.firstIndex(where: \.me) {
                        Text(L("Place %lld of %lld · %lld XP this week", me + 1, l.members.count, l.members[me].xp))
                            .font(.fig(13)).foregroundStyle(theme.muted)
                    } else {
                        Text(L("Earn XP this week to join")).font(.fig(13)).foregroundStyle(theme.muted)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward").font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.muted)
            }
            .card(padding: 14)
        }
        .buttonStyle(.plain)
        .task { await model.refreshLeague() }
        .sheet(isPresented: $open) {
            LeagueView()
                .environmentObject(model)
                .environment(\.theme, model.theme)
                .presentationDetents([.large])
                .presentationCornerRadius(28)
        }
    }
}

/// The weekly league table: top 7 move up, bottom 5 move down.
struct LeagueView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let l = model.league
        let tier = l?.tier ?? 0
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Spacer()
                    BackButton(systemName: "xmark") { dismiss() }
                }
                .padding(.top, 16)
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        ForEach(0..<10, id: \.self) { t in
                            Image(systemName: "shield.lefthalf.filled").font(.system(size: t == tier ? 30 : 16, weight: .bold))
                                .foregroundStyle(t <= tier ? LeagueStyle.color(t) : theme.chip2)
                        }
                    }
                    Text(L("%@ League", LeagueStyle.name(tier))).font(.fig(24, .bold))
                    Text(L("%lld days left · top 7 move up, bottom 5 move down", LeagueStyle.daysLeft))
                        .font(.fig(13)).foregroundStyle(theme.muted).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)

                if let prev = l?.previous {
                    Text(prev == "promoted" ? L("You moved up last week. Well done!")
                         : prev == "demoted" ? L("You moved down last week. A few lessons a day gets you back up.")
                         : L("You stayed in your league last week."))
                        .font(.fig(14)).frame(maxWidth: .infinity, alignment: .leading)
                        .tintedNote(prev == "demoted" ? theme.errorTint : theme.at, prev == "demoted" ? theme.errorText : theme.ad, radius: 14)
                }

                if let l, l.joined, let me = l.members.firstIndex(where: \.me) {
                    ShareCardButton(card: ShareCard(icon: "shield.lefthalf.filled", value: "#\(me + 1)", title: L("%@ League", LeagueStyle.name(tier)),
                                                    subtitle: L("%lld XP this week", l.members[me].xp), color: LeagueStyle.color(tier)))
                        .frame(maxWidth: .infinity)
                }
                if !model.socialAvailable {
                    Text(L("Leagues need a Lingora account.")).font(.fig(14)).foregroundStyle(theme.muted).card()
                } else if let l, l.joined {
                    table(l)
                } else {
                    Text(L("Finish a lesson this week to join a league of up to 30 learners at your level."))
                        .font(.fig(14)).foregroundStyle(theme.muted).card()
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 24)
        }
        .background(theme.ground)
        .refreshable { await model.refreshLeague() }
    }

    private func table(_ l: Social.League) -> some View {
        let promote = l.promote ?? 0, demote = l.demote ?? 0, n = l.members.count
        return VStack(spacing: 0) {
            ForEach(Array(l.members.enumerated()), id: \.element.id) { i, m in
                if promote > 0 && i == promote && i < n {
                    zoneLine(L("Promotion zone"), color: theme.a)
                }
                if demote > 0 && i == n - demote && i > 0 {
                    zoneLine(L("Demotion zone"), color: theme.errorText)
                }
                HStack(spacing: 12) {
                    Text(verbatim: "\(i + 1)").font(.fig(14, .bold))
                        .foregroundStyle(i < promote ? theme.ad : demote > 0 && i >= n - demote ? theme.errorText : theme.muted)
                        .frame(width: 24)
                    Avatar(initial: String(m.name.first ?? "?").uppercased(), hue: Hue(h: m.hue), size: 36, uid: m.uid, photo: m.photo)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: m.me ? L("You") : m.name).font(.fig(15, .semibold))
                        if m.streak > 0 {
                            Label("\(m.streak)", systemImage: "flame.fill").font(.fig(12)).foregroundStyle(theme.muted)
                        }
                    }
                    Spacer()
                    Text(verbatim: "\(m.xp) XP").font(.fig(14, .semibold))
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(m.me ? theme.at : .clear)
                .contentShape(Rectangle())
                .onTapGesture { model.profileUID = m.uid }
            }
        }
        .card(padding: 0)
        .clipShape(RoundedRectangle(cornerRadius: theme.radius, style: .continuous))
    }

    private func zoneLine(_ title: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Rectangle().fill(color.opacity(0.5)).frame(height: 1.5)
            Text(title).font(.fig(11, .bold)).foregroundStyle(color)
            Rectangle().fill(color.opacity(0.5)).frame(height: 1.5)
        }
        .padding(.horizontal, 14).padding(.vertical, 4)
    }
}
