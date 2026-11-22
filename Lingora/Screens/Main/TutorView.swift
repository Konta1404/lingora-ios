import SwiftUI

struct TutorView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme
    @State private var draft = ""

    private var key: String {
        if let t = model.tutorLang, model.s.learning.contains(t) { return t }
        return model.s.learning.first ?? "es"
    }

    var body: some View {
        let lang = model.language(key)
        let messages = model.tutorMessages(key)

        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    ScreenTitle(text: L("Tutor"))
                    Spacer()
                    Menu {
                        Button(L("Start a fresh conversation"), systemImage: "arrow.clockwise") { model.resetTutor(key) }
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(theme.text).frame(width: 40, height: 40).background(theme.chip, in: Circle())
                    }
                    .accessibilityLabel(L("More"))
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(model.languages) { l in
                            let h = theme.colors(for: l.hue)
                            let on = l.key == key
                            PillButton(title: l.name, bg: on ? h.tint : theme.chip, fg: on ? h.deep : theme.text) {
                                model.tutorLang = l.key
                            }
                        }
                    }
                }
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "theatermasks").padding(.top, 2)
                    MD(L("**Roleplay:** %@", model.tutorScene(key)))
                }
                .tintedNote(theme.at, theme.ad, radius: theme.radius)
            }
            .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 8)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(messages) { m in
                            switch m.role {
                            case .correction:
                                CorrectionBubble(wrong: m.wrong ?? "", right: m.right ?? "", note: m.note ?? "")
                            default:
                                ChatBubble(text: m.text, mine: m.role == .me)
                            }
                        }
                        if model.tutorTyping {
                            TypingIndicator(label: L("Tutor is typing…")).id("typing")
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 20).padding(.vertical, 8)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: messages.count) { withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
                .onChange(of: model.tutorTyping) { withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
                .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.suggestions(key), id: \.self) { s in
                        PillButton(title: s, bg: theme.card, fg: theme.text) { send(s) }
                            .overlay(Capsule().strokeBorder(theme.line, lineWidth: 1))
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.top, 4)

            ChatInputBar(text: $draft, placeholder: L("Reply in %@…", lang?.name ?? ""), disabled: model.tutorTyping,
                         speechLanguage: lang?.key) {
                send(draft)
            }
        }
        .background(theme.ground)
    }

    private func send(_ text: String) {
        let k = key
        draft = ""
        Task { await model.sendTutor(text, lang: k) }
    }
}
