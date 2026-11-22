import SwiftUI
import Contacts
import CoreImage.CIFilterBuiltins
import UIKit

struct AddFriendsSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [Social.Person] = []
    @State private var searching = false
    @State private var copied = false
    @State private var contacts: [Social.Person]?
    @State private var contactsBusy = false
    @State private var contactsNote: String?
    @State private var relations: [String: String] = [:]
    @State private var qr: UIImage?

    private var handle: String { model.s.user?.handle ?? "" }
    private var inviteURL: URL? {
        let h = handle.replacingOccurrences(of: "@", with: "")
        guard !h.isEmpty else { return nil }
        if let base = Backend.apiBaseURL { return base.appendingPathComponent("u").appendingPathComponent(h) }
        return URL(string: "lingora://add/\(h)")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(L("Add friends")).font(.fig(24, .bold))
                    Spacer()
                    BackButton(systemName: "xmark") { dismiss() }
                }
                .padding(.top, 20)

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(theme.muted)
                    TextField(L("Search by username"), text: $query)
                        .font(.fig(16)).textInputAutocapitalization(.never).autocorrectionDisabled()
                    if searching { ProgressView() }
                }
                .padding(.horizontal, 16).frame(height: 52)
                .background(theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(theme.line, lineWidth: 1.5))

                if query.trimmingCharacters(in: .whitespaces).count >= 2 {
                    people(results, emptyText: searching ? nil : L("No one found. Share your link instead."))
                }

                if let contacts {
                    SectionLabel(text: L("From your contacts"))
                    people(contacts, emptyText: L("None of your contacts are on Lingora yet. Send them your link."))
                }
                if let contactsNote {
                    Text(contactsNote).font(.fig(13)).foregroundStyle(theme.muted)
                }

                if let out = model.social?.outgoing, !out.isEmpty {
                    SectionLabel(text: L("Requests you sent"))
                    people(out.map { var p = $0; p.relation = "requested"; return p }, emptyText: nil)
                }

                HStack(spacing: 10) {
                    Button {
                        if let inviteURL { UIPasteboard.general.string = inviteURL.absoluteString }
                        copied = true
                        Haptics.success()
                    } label: {
                        Label(copied ? L("Link copied") : L("Copy invite link"), systemImage: copied ? "checkmark" : "link")
                    }
                    .buttonStyle(.secondary)
                    .disabled(inviteURL == nil)
                    Button(action: findContacts) {
                        Label(contactsBusy ? L("Looking…") : L("From contacts"), systemImage: "person.crop.circle")
                    }
                    .buttonStyle(.secondary)
                    .disabled(contactsBusy)
                }

                if let inviteURL {
                    VStack(spacing: 12) {
                        Group {
                            if let qr = qr ?? QRCode.cached(inviteURL.absoluteString) {
                                Image(uiImage: qr).interpolation(.none).resizable().scaledToFit()
                                    .accessibilityLabel(L("QR code for your invite link"))
                            } else {
                                ProgressView()
                            }
                        }
                        .frame(width: 170, height: 170)
                        .padding(12).background(.white, in: RoundedRectangle(cornerRadius: 16))
                        .task(id: inviteURL) { qr = await QRCode.make(inviteURL.absoluteString) }
                        Text(L("Scan to add %@", handle)).font(.fig(15, .semibold))
                        ShareLink(item: inviteURL, message: Text(L("Learn languages with me on Lingora"))) {
                            Label(L("Share"), systemImage: "square.and.arrow.up").font(.fig(14, .semibold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .card()
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 20)
        }
        .background(theme.ground)
        .task(id: query) { await search() }
    }

    @ViewBuilder
    private func people(_ list: [Social.Person], emptyText: String?) -> some View {
        if list.isEmpty {
            if let emptyText { Text(emptyText).font(.fig(14)).foregroundStyle(theme.muted).padding(.horizontal, 4) }
        } else {
            VStack(spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.element.id) { i, p in
                    let rel = relations[p.uid] ?? p.relation ?? "none"
                    HStack(spacing: 12) {
                        Avatar(initial: p.initial, hue: Hue(h: p.hue), size: 40, uid: p.uid, photo: p.photoVersion)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: p.name).font(.fig(15, .semibold))
                            Text(verbatim: subtitle(p)).font(.fig(13)).foregroundStyle(theme.muted).lineLimit(1)
                        }
                        Spacer()
                        switch rel {
                        case "friend":
                            Text(L("Friends")).font(.fig(13, .semibold)).foregroundStyle(theme.ad)
                        case "requested":
                            Text(L("Requested")).font(.fig(13, .semibold)).foregroundStyle(theme.muted)
                        default:
                            PillButton(title: rel == "incoming" ? L("Accept") : L("Add"), bg: theme.a, fg: .white, height: 34) {
                                Task {
                                    if let r = await model.addFriend(uid: p.uid) { relations[p.uid] = r }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .overlay(alignment: .top) { if i > 0 { Rectangle().fill(theme.line).frame(height: 1) } }
                }
            }
            .card(padding: 0)
        }
    }

    private func subtitle(_ p: Social.Person) -> String {
        let langs = p.langs.prefix(3).map { FeedText.language($0, fallback: $0) }
        return langs.isEmpty ? p.atHandle : L("%@ · learning %@", p.atHandle, ListFormatter.localizedString(byJoining: langs))
    }

    private func search() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { results = []; return }
        try? await Task.sleep(for: .milliseconds(350))
        if Task.isCancelled { return }
        searching = true
        defer { searching = false }
        if let r = try? await Social.search(q), !Task.isCancelled { results = r }
    }

    private func findContacts() {
        contactsBusy = true
        contactsNote = nil
        Task {
            defer { contactsBusy = false }
            let store = CNContactStore()
            do {
                guard try await store.requestAccess(for: .contacts) else {
                    contactsNote = L("Allow Contacts in Settings to find friends.")
                    return
                }
                let emails = try await Task.detached(priority: .userInitiated) { () -> [String] in
                    var out: [String] = []
                    let req = CNContactFetchRequest(keysToFetch: [CNContactEmailAddressesKey as CNKeyDescriptor])
                    try CNContactStore().enumerateContacts(with: req) { c, _ in
                        out.append(contentsOf: c.emailAddresses.map { $0.value as String })
                    }
                    return out
                }.value
                contacts = try await Social.matchContacts(emails: emails)
                contactsNote = L("Only a fingerprint of each email address is checked; your contacts aren't uploaded.")
            } catch {
                contactsNote = Backend.message(for: error)
            }
        }
    }
}

/// QR codes for invite links. Core Image setup is slow (~0.5 s the first time), so codes are made off the
/// main thread with one shared context and cached; the app prepares yours right after sign-in.
enum QRCode {
    private static let context = CIContext(options: [.cacheIntermediates: false])
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: UIImage] = [:]

    static func cached(_ string: String) -> UIImage? {
        lock.lock(); defer { lock.unlock() }
        return cache[string]
    }

    static func make(_ string: String) async -> UIImage? {
        if let c = cached(string) { return c }
        return await Task.detached(priority: .userInitiated) { image(for: string) }.value
    }

    static func image(for string: String) -> UIImage? {
        if let c = cached(string) { return c }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cg = context.createCGImage(output, from: output.extent) else { return nil }
        let img = UIImage(cgImage: cg)
        lock.lock(); cache[string] = img; lock.unlock()
        return img
    }
}
