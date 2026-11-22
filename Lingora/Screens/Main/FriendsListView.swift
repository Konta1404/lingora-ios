import SwiftUI

/// All friends: search, requests, open a chat, remove.
struct FriendsListView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var removing: Social.Person?

    private var friends: [Social.Person] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: "@", with: "")
        let all = model.friends.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        guard !q.isEmpty else { return all }
        return all.filter { $0.name.lowercased().contains(q) || $0.handle.lowercased().contains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                BackButton { dismiss() }
                Text(L("Friends")).font(.fig(22, .bold))
                Text(verbatim: "\(model.friends.count)").font(.fig(15, .semibold)).foregroundStyle(theme.muted)
                Spacer()
                PillButton(title: L("Add"), icon: "plus", bg: theme.a, fg: .white) { model.showAddFriend = true }
            }
            .padding(.horizontal, 20).padding(.vertical, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if model.friends.count > 5 {
                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass").foregroundStyle(theme.muted)
                            TextField(L("Search friends"), text: $query)
                                .font(.fig(16)).textInputAutocapitalization(.never).autocorrectionDisabled()
                        }
                        .padding(.horizontal, 16).frame(height: 48)
                        .background(theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(theme.line, lineWidth: 1.5))
                    }

                    if let incoming = model.social?.incoming, !incoming.isEmpty, query.isEmpty {
                        SectionLabel(text: L("Friend requests"))
                        VStack(spacing: 0) {
                            ForEach(Array(incoming.enumerated()), id: \.element.id) { i, p in
                                HStack(spacing: 12) {
                                    Avatar(initial: p.initial, hue: Hue(h: p.hue), size: 40, uid: p.uid, photo: p.photoVersion)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(verbatim: p.name).font(.fig(15, .semibold))
                                        Text(verbatim: p.atHandle).font(.fig(13)).foregroundStyle(theme.muted)
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

                    if !model.friends.isEmpty && query.isEmpty { SectionLabel(text: L("All friends")) }
                    VStack(spacing: 0) {
                        if friends.isEmpty {
                            Text(model.friends.isEmpty ? L("No friends yet. Add someone by username or send your invite link.")
                                                       : L("No friends match “%@”.", query))
                                .font(.fig(14)).foregroundStyle(theme.muted).padding(16)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        ForEach(Array(friends.enumerated()), id: \.element.id) { i, f in
                            FriendListRow(friend: f, separator: i > 0, showStats: true) { removing = f }
                        }
                    }
                    .card(padding: 0)
                }
                .padding(.horizontal, 20).padding(.bottom, 24)
            }
            .refreshable { await model.refreshSocial() }
        }
        .background(theme.ground)
        .task { await model.refreshSocial() }
        .confirmationDialog(L("Remove %@ from friends?", removing?.name ?? ""), isPresented: Binding(
            get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            Button(L("Remove friend"), role: .destructive) {
                if let r = removing { Task { await model.removeFriend(r.uid) } }
                removing = nil
            }
        } message: {
            Text(L("You'll stop seeing each other's activity and chat. You can add each other again later."))
        }
    }
}

/// One friend: photo, name, last message or stats, unread count, Remove. Tapping opens the chat.
struct FriendListRow: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme
    let friend: Social.Person
    var separator = false
    var showStats = false
    var onRemove: () -> Void

    var body: some View {
        let f = friend
        HStack(spacing: 12) {
            Button {
                model.tab = .friends
                model.friendsPath = [f.uid]
            } label: {
                HStack(spacing: 12) {
                    Avatar(initial: f.initial, hue: Hue(h: f.hue), size: 44, uid: f.uid, photo: f.photoVersion)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: f.name).font(.fig(15, .semibold))
                        Text(verbatim: subtitle).font(.fig(13)).foregroundStyle(theme.muted).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    if let fs = f.friendStreak, fs > 0 {
                        Label("\(fs)", systemImage: "flame.fill").font(.fig(12, .bold)).foregroundStyle(Color.orange)
                            .accessibilityLabel(L("%lld-day Friend Streak", fs))
                    }
                    if let n = f.unread, n > 0 {
                        Text(verbatim: "\(n)").font(.fig(12, .bold)).foregroundStyle(.white)
                            .frame(minWidth: 22, minHeight: 22).background(theme.a, in: Capsule())
                            .accessibilityLabel(L("%lld unread", n))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button(L("Remove"), action: onRemove)
                .font(.fig(13, .semibold)).foregroundStyle(theme.muted)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .overlay(alignment: .top) { if separator { Rectangle().fill(theme.line).frame(height: 1) } }
    }

    private var subtitle: String {
        let f = friend
        if let m = f.lastMessage, !m.isEmpty { return f.lastFromMe == true ? L("You: %@", m) : m }
        if showStats {
            if f.sharesActivity == false { return "\(f.atHandle) · \(L("Keeps activity private"))" }
            return "\(f.atHandle) · \(L("%lld-day streak · %@", f.streak, f.practisedToday ? L("practised today") : L("not yet today")))"
        }
        return f.atHandle
    }
}
