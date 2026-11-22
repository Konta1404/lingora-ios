import SwiftUI

/// A learner's public page: photo, languages, streak, XP, league, achievements, and what you can do with them.
struct ProfileView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    let uid: String
    @State private var p: Social.PublicProfile?
    @State private var failed = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack {
                    Spacer()
                    BackButton(systemName: "xmark") { dismiss() }
                }
                .padding(.top, 16)
                if let p {
                    content(p)
                } else if failed {
                    Text(L("Couldn't load this profile.")).font(.fig(15)).foregroundStyle(theme.muted).padding(40)
                } else {
                    ProgressView().padding(60)
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize, axes: [.horizontal])
        .background(theme.ground)
        .task {
            do { p = try await Social.profile(uid: uid) } catch { failed = true }
        }
    }

    @ViewBuilder
    private func content(_ p: Social.PublicProfile) -> some View {
        VStack(spacing: 8) {
            Avatar(initial: String(p.name.first ?? "?").uppercased(), hue: Hue(h: p.hue), size: 96, uid: p.uid, photo: p.photo ?? 0)
            Text(verbatim: p.name).font(.fig(24, .bold))
            Text(verbatim: "@\(p.handle)").font(.fig(14)).foregroundStyle(theme.muted)
            if let j = p.joined {
                Text(L("Learning since %@", DateUtil.format(Date(timeIntervalSince1970: j / 1000), "MMMMy")))
                    .font(.fig(13)).foregroundStyle(theme.muted)
            }
            if !p.langs.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(p.langs, id: \.self) { k in
                        Text(FeedText.language(k, fallback: k)).font(.fig(13, .semibold)).foregroundStyle(theme.ad)
                            .padding(.horizontal, 10).frame(height: 28).background(theme.at, in: Capsule())
                    }
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)

        actions(p)

        if p.sharesActivity == false && p.relation != "me" {
            Text(L("%@ keeps their activity private.", p.name.split(separator: " ").first.map(String.init) ?? p.name))
                .font(.fig(14)).foregroundStyle(theme.muted).card()
        } else {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                stat("flame.fill", "\(p.streak)", L("day streak"), .orange)
                stat("bolt.fill", "\(p.stats?.totalXP ?? 0)", L("total XP"), theme.a)
                stat("shield.lefthalf.filled", p.league.map { LeagueStyle.name($0) } ?? "—", L("league"), LeagueStyle.color(p.league ?? 0))
                stat("person.2.fill", "\(p.friendsCount)", L("friends"), .blue)
                stat("book.fill", "\(p.stats?.lessons ?? 0)", L("lessons finished"), .purple)
                stat("trophy.fill", "\(p.stats?.bestStreak ?? 0)", L("best streak"), .red)
            }
            if let ach = p.stats?.achievements, ach.values.contains(where: { $0 > 0 }) {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: L("Achievements"))
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 12) {
                        ForEach(Achievement.all.filter { (ach[$0.kind.rawValue] ?? 0) > 0 }) { a in
                            let n = ach[a.kind.rawValue] ?? 0
                            VStack(spacing: 6) {
                                Image(systemName: a.icon).font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
                                    .frame(width: 54, height: 54).background(theme.a, in: Circle())
                                HStack(spacing: 1) {
                                    ForEach(0..<a.tiers.count, id: \.self) { i in
                                        Image(systemName: "star.fill").font(.system(size: 7)).foregroundStyle(i < n ? Color.orange : theme.chip2)
                                    }
                                }
                                Text(a.title).font(.fig(11, .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                            }
                        }
                    }
                }
                .card()
            }
        }
    }

    @ViewBuilder
    private func actions(_ p: Social.PublicProfile) -> some View {
        HStack(spacing: 10) {
            switch p.relation {
            case "friend":
                Button(L("Message")) {
                    dismiss()
                    model.tab = .friends
                    model.friendsPath = [p.uid]
                }
                .buttonStyle(PrimaryButtonStyle(kind: .accent, height: 46))
            case "me":
                ShareLink(item: inviteURL(p)) {
                    Label(L("Share my profile"), systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle(kind: .accent, height: 46))
            case "requested":
                Button(L("Requested")) {}.buttonStyle(PrimaryButtonStyle(kind: .chip, height: 46)).disabled(true)
            default:
                Button(p.relation == "incoming" ? L("Accept") : L("Add friend")) {
                    Task {
                        if let r = await model.addFriend(uid: p.uid) { self.p?.relation = r }
                    }
                }
                .buttonStyle(PrimaryButtonStyle(kind: .accent, height: 46))
            }
        }
    }

    private func inviteURL(_ p: Social.PublicProfile) -> URL {
        if let base = Backend.apiBaseURL { return base.appendingPathComponent("u").appendingPathComponent(p.handle) }
        return URL(string: "lingora://add/\(p.handle)")!
    }

    private func stat(_ icon: String, _ value: String, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(color)
            Text(verbatim: value).font(.fig(20, .bold)).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.fig(12, .semibold)).foregroundStyle(theme.muted).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 14)
    }
}
