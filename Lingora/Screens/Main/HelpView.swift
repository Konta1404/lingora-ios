import SwiftUI
import UniformTypeIdentifiers

/// Help & support: answers to common questions and a way to write to us.
struct HelpView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var open: Int?
    @State private var message = ""
    @State private var sending = false
    @State private var sent = false

    private var faq: [(String, String)] {
        [
            (L("How do streaks work?"), L("Practise at least a minute a day to keep your streak. A streak freeze covers a missed day; you earn one every 7 days or buy one in the shop.")),
            (L("Why are some features greyed out?"), L("ChatGPT features need your own ChatGPT plan connected in Me. Friends, leagues and profiles need a Lingora account.")),
            (L("How do I change the app language?"), L("Lingora follows your iPhone's language. Change it in Settings → Lingora → Language.")),
            (L("Why don't I get notifications right away?"), L("Lingora checks for messages in the background, which iOS runs from time to time. Instant notifications need Apple push, which isn't set up yet.")),
            (L("How do I hide my activity from friends?"), L("Turn off Me → Settings → Share my activity. Friends then only see your name and photo.")),
            (L("How do I delete my account?"), L("Me → Delete account. Your synced progress is removed and this can't be undone.")),
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(L("Help & support")).font(.fig(24, .bold))
                    Spacer()
                    BackButton(systemName: "xmark") { dismiss() }
                }
                .padding(.top, 20)
                VStack(spacing: 0) {
                    ForEach(Array(faq.enumerated()), id: \.offset) { i, q in
                        Button { withAnimation { open = open == i ? nil : i } } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(q.0).font(.fig(15, .semibold)).foregroundStyle(theme.text).multilineTextAlignment(.leading)
                                    Spacer()
                                    Image(systemName: open == i ? "chevron.up" : "chevron.down").font(.system(size: 12, weight: .bold)).foregroundStyle(theme.muted)
                                }
                                if open == i { Text(q.1).font(.fig(14)).foregroundStyle(theme.muted).multilineTextAlignment(.leading) }
                            }
                            .padding(14).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .overlay(alignment: .top) { if i > 0 { Rectangle().fill(theme.line).frame(height: 1) } }
                    }
                }
                .card(padding: 0)

                SectionLabel(text: L("Write to us")).padding(.top, 6)
                if model.socialAvailable {
                    TextField(L("Tell us what's wrong or what you'd like"), text: $message, axis: .vertical)
                        .lineLimit(4...10).font(.fig(15)).padding(14)
                        .background(theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(theme.line, lineWidth: 1.5))
                    Button(sent ? L("Thanks — we got it!") : sending ? L("Sending…") : L("Send")) { send() }
                        .buttonStyle(.primary)
                        .disabled(sending || sent || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } else {
                    Text(L("Sign in to send us a message.")).font(.fig(14)).foregroundStyle(theme.muted)
                }
                Text(verbatim: "Lingora \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""))")
                    .font(.fig(12)).foregroundStyle(theme.muted).frame(maxWidth: .infinity).padding(.top, 8)
            }
            .padding(.horizontal, 20).padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize, axes: [.horizontal])
        .background(theme.ground)
    }

    private func send() {
        sending = true
        let text = message
        Task {
            struct Ok: Decodable {}
            do {
                let _: Ok = try await Backend.call("sendFeedback", [
                    "text": text, "app": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
                    "device": "\(UIDevice.current.model) \(UIDevice.current.systemVersion)", "uiLanguage": AppLocale.tag,
                ])
                sent = true
            } catch {
                model.toast = Backend.message(for: error)
            }
            sending = false
        }
    }
}

/// Everything Lingora keeps about you on this iPhone, as a JSON file.
struct ExportFile: Transferable {
    /// Built only when the share sheet asks for it.
    let make: () async -> Data
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { await $0.make() }
            .suggestedFileName("lingora-export.json")
    }
}
