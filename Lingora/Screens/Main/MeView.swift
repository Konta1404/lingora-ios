import SwiftUI
import PhotosUI

struct MeView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme
    @State private var confirmLogout = false
    @State private var confirmDelete = false
    @State private var editHandle = false
    @State private var newHandle = ""
    @State private var showDevices = false
    @State private var photoItem: PhotosPickerItem?
    @State private var photoBusy = false
    @State private var removing: Social.Person?

    var body: some View {
        let user = model.s.user
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    if model.socialAvailable {
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Avatar(initial: user?.initial ?? "A", hue: Hue(h: theme.accent.hue), size: 60,
                                   uid: model.signedInUID, photo: model.myPhoto)
                                .overlay(alignment: .bottomTrailing) {
                                    Image(systemName: photoBusy ? "hourglass" : "camera.fill")
                                        .font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                                        .frame(width: 22, height: 22).background(theme.a, in: Circle())
                                        .overlay(Circle().strokeBorder(theme.ground, lineWidth: 2))
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L("Change profile photo"))
                        .contextMenu {
                            if model.myPhoto > 0 {
                                Button(L("Remove photo"), role: .destructive) { Task { await model.setPhoto(nil) } }
                            }
                        }
                    } else {
                        Avatar(initial: user?.initial ?? "A", hue: Hue(h: theme.accent.hue), size: 60)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: user?.name ?? "").font(.fig(22, .bold))
                        Text(verbatim: user?.handle ?? "").font(.fig(14)).foregroundStyle(theme.muted)
                    }
                }
                .padding(.top, 10)

                HStack(spacing: 10) {
                    stat("\(model.streak)", L("day streak"), icon: "flame")
                    stat("\(model.myWeekMinutes)", L("min this week"), icon: "clock")
                    stat("\(model.friends.count)", L("friends"), icon: "person.2")
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
                                    ProgressBar(value: model.levelProgress(l.key), color: h.base, height: 6)
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

                if model.socialAvailable { friendsSection }

                SectionLabel(text: L("Settings")).padding(.top, 6)
                VStack(spacing: 0) {
                    row(L("ChatGPT"), sub: aiStatus, first: true) {
                        if Backend.isConfigured && model.signedInUID != nil {
                            let on = model.chatGPT?.connected == true
                            PillButton(title: on ? L("Disconnect") : L("Connect"),
                                       bg: on ? theme.chip : theme.a, fg: on ? theme.text : .white, height: 32) {
                                if on { model.disconnectChatGPT() } else { model.connectChatGPT() }
                            }
                            .disabled(model.authBusy)
                        }
                    }
                    row(L("Adapt tasks daily"), sub: L("ChatGPT adjusts today from your results")) {
                        LingoraSwitch(isOn: $model.s.settings.adaptDaily)
                    }
                    row(L("Daily reminder"), sub: L("A gentle nudge at 19:00")) {
                        LingoraSwitch(isOn: Binding(get: { model.s.settings.reminders }, set: { model.setReminders($0) }))
                    }
                    if model.socialAvailable {
                        row(L("Message notifications"), sub: L("New messages, friend requests, nudges and invites")) {
                            LingoraSwitch(isOn: Binding(get: { model.s.settings.notifyMessages }, set: { model.setNotifyMessages($0) }))
                        }
                        row(L("Share my activity"), sub: model.s.settings.shareActivity
                            ? L("Friends see your updates, streak and minutes")
                            : L("Hidden — friends only see your name and photo")) {
                            LingoraSwitch(isOn: Binding(get: { model.s.settings.shareActivity }, set: { model.setShareActivity($0) }))
                        }
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
                    if model.socialAvailable {
                        row(L("Username"), sub: L("Friends find you by %@", user?.handle ?? "")) {
                            Button(L("Change")) {
                                newHandle = (user?.handle ?? "").replacingOccurrences(of: "@", with: "")
                                editHandle = true
                            }
                            .font(.fig(14, .semibold)).foregroundStyle(theme.ad)
                        }
                        row(L("Devices"), sub: L("Where you're signed in")) {
                            Button(L("Show")) { showDevices = true }
                                .font(.fig(14, .semibold)).foregroundStyle(theme.ad)
                        }
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
        .task { await model.refreshChatGPT() }
        .alert(L("Choose a username"), isPresented: $editHandle) {
            TextField(L("username"), text: $newHandle)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            Button(L("Cancel"), role: .cancel) {}
            Button(L("Save")) {
                let h = newHandle
                Task { if let err = await model.changeHandle(h) { model.toast = err } }
            }
        } message: {
            Text(L("3–20 letters, numbers, dots or underscores."))
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            photoBusy = true
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                    await model.setPhoto(img)
                } else {
                    model.toast = L("Couldn't open that photo.")
                }
                photoBusy = false
                photoItem = nil
            }
        }
        .confirmationDialog(L("Remove %@ from friends?", removing?.name ?? ""), isPresented: Binding(
            get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            Button(L("Remove friend"), role: .destructive) {
                if let r = removing { Task { await model.removeFriend(r.uid) } }
                removing = nil
            }
        } message: {
            Text(L("You'll stop seeing each other's activity and chat. You can add each other again later."))
        }
        .sheet(isPresented: $showDevices) {
            DevicesSheet()
                .environmentObject(model)
                .environment(\.theme, model.theme)
                .presentationDetents([.medium, .large])
                .presentationCornerRadius(28)
        }
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

    private var friendsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(text: L("Friends"))
                Spacer()
                Button(L("Add")) { model.showAddFriend = true }
                    .font(.fig(14, .semibold)).foregroundStyle(theme.ad)
            }
            .padding(.top, 6)
            VStack(spacing: 0) {
                if model.friends.isEmpty {
                    Text(L("No friends yet. Add someone by username or send your invite link."))
                        .font(.fig(14)).foregroundStyle(theme.muted).padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(Array(model.friends.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }.enumerated()),
                        id: \.element.id) { i, f in
                    HStack(spacing: 12) {
                        Button {
                            model.tab = .friends
                            model.friendsPath = [f.uid]
                        } label: {
                            HStack(spacing: 12) {
                                Avatar(initial: f.initial, hue: Hue(h: f.hue), size: 40, uid: f.uid, photo: f.photoVersion)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(verbatim: f.name).font(.fig(15, .semibold))
                                    Text(verbatim: friendSubtitle(f)).font(.fig(13)).foregroundStyle(theme.muted).lineLimit(1)
                                }
                                Spacer(minLength: 4)
                                if let n = f.unread, n > 0 {
                                    Text(verbatim: "\(n)").font(.fig(12, .bold)).foregroundStyle(.white)
                                        .frame(minWidth: 22, minHeight: 22).background(theme.a, in: Capsule())
                                        .accessibilityLabel(L("%lld unread", n))
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Button(L("Remove")) { removing = f }
                            .font(.fig(13, .semibold)).foregroundStyle(theme.muted)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .overlay(alignment: .top) { if i > 0 { Rectangle().fill(theme.line).frame(height: 1) } }
                }
            }
            .card(padding: 0)
        }
    }

    private func friendSubtitle(_ f: Social.Person) -> String {
        if let m = f.lastMessage, !m.isEmpty { return (f.lastFromMe == true ? L("You: %@", m) : m) }
        return f.atHandle
    }

    private var aiStatus: String {
        if !Backend.isConfigured { return L("Offline mode · using standard plans") }
        if model.signedInUID == nil { return L("Sign in to turn it on") }
        if let s = model.chatGPT, s.connected {
            return s.email.map { L("Uses your ChatGPT plan · %@", $0) } ?? L("Uses your ChatGPT plan")
        }
        return L("Not connected · using standard plans. Connect your ChatGPT Plus or Pro plan to turn on AI.")
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

/// Devices signed in to this account (registered by the app on sign-in).
struct DevicesSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var devices: [Social.Device]?
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(L("Devices")).font(.fig(24, .bold))
                    Spacer()
                    BackButton(systemName: "xmark") { dismiss() }
                }
                .padding(.top, 20)
                if let devices {
                    VStack(spacing: 0) {
                        ForEach(Array(devices.enumerated()), id: \.element.id) { i, d in
                            let this = d.id == Social.deviceID
                            HStack(spacing: 12) {
                                Image(systemName: "iphone").font(.system(size: 18)).foregroundStyle(theme.ad)
                                    .frame(width: 36, height: 36).background(theme.at, in: Circle())
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(verbatim: d.name.isEmpty ? d.model : d.name).font(.fig(15, .semibold))
                                    Text(verbatim: this ? L("This iPhone · %@", d.os)
                                                        : "\(d.os) · \(FeedText.ago(Date(timeIntervalSince1970: d.lastSeen / 1000)))")
                                        .font(.fig(13)).foregroundStyle(theme.muted)
                                }
                                Spacer()
                                if !this {
                                    Button(L("Remove")) {
                                        Task {
                                            try? await Social.removeDevice(d.id)
                                            self.devices = try? await Social.devices()
                                        }
                                    }
                                    .font(.fig(13, .semibold)).foregroundStyle(theme.muted)
                                }
                            }
                            .padding(.horizontal, 14).padding(.vertical, 12)
                            .overlay(alignment: .top) { if i > 0 { Rectangle().fill(theme.line).frame(height: 1) } }
                        }
                    }
                    .card(padding: 0)
                    Text(L("Removing a device here only hides it from this list. To sign out everywhere, change your password or remove Lingora from your Apple, Google or ChatGPT account settings."))
                        .font(.fig(13)).foregroundStyle(theme.muted)
                } else if let error {
                    Text(error).font(.fig(14)).foregroundStyle(theme.muted)
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(30)
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 20)
        }
        .background(theme.ground)
        .task {
            do {
                try? await Social.registerThisDevice()
                devices = try await Social.devices()
            } catch {
                self.error = Backend.message(for: error)
            }
        }
    }
}
