import SwiftUI

/// A voice call with the tutor: hold to speak, the tutor answers aloud, captions on screen, feedback at the end.
struct TutorCallView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    let lang: String
    @StateObject private var dictation = Dictation()
    @State private var heard = ""
    @State private var started = Date()
    @State private var startCount = 0
    @State private var ended = false
    @State private var feedback: AIService.CallFeedback?
    @State private var loadingFeedback = false
    @State private var captions = true

    private var messages: [ChatMessage] { model.tutorMessages(lang) }
    private var callMessages: [ChatMessage] { Array(messages.dropFirst(startCount)) }
    private var lastTutor: ChatMessage? { messages.last { $0.role == .ai } }

    var body: some View {
        let l = model.language(lang)
        let h = l.map { theme.colors(for: $0.hue) } ?? Hue(h: theme.accent.hue)
        VStack(spacing: 0) {
            if ended {
                summary(l)
            } else {
                HStack {
                    Button { captions.toggle() } label: {
                        Image(systemName: captions ? "captions.bubble.fill" : "captions.bubble").font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(theme.text).frame(width: 44, height: 44).background(theme.chip, in: Circle())
                    }
                    .accessibilityLabel(L("Captions"))
                    Spacer()
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        let s = Int(Date().timeIntervalSince(started))
                        Text(verbatim: String(format: "%d:%02d", s / 60, s % 60)).font(.fig(15, .semibold)).foregroundStyle(theme.muted)
                    }
                }
                .padding(.horizontal, 20).padding(.top, 12)
                Spacer()
                ZStack {
                    if model.tutorTyping {
                        Circle().fill(h.tint).frame(width: 190, height: 190)
                            .phaseAnimator([1.0, 1.12]) { c, p in c.scaleEffect(p) } animation: { _ in .easeInOut(duration: 0.6) }
                    }
                    Image(systemName: "person.wave.2.fill").font(.system(size: 54)).foregroundStyle(.white)
                        .frame(width: 150, height: 150).background(h.base, in: Circle())
                }
                Text(L("%@ tutor", l?.name ?? "")).font(.fig(22, .bold)).padding(.top, 16)
                Text(model.tutorTyping ? L("Thinking…") : dictation.isRecording ? L("Listening…") : L("Hold the button and speak"))
                    .font(.fig(15)).foregroundStyle(theme.muted)
                if captions {
                    VStack(spacing: 10) {
                        if let t = lastTutor { Text(t.text).font(.fig(17, .semibold)).multilineTextAlignment(.center) }
                        if !heard.isEmpty { Text(heard).font(.fig(15)).foregroundStyle(theme.muted).multilineTextAlignment(.center) }
                    }
                    .padding(.horizontal, 28).padding(.top, 20)
                }
                Spacer()
                HStack(spacing: 40) {
                    Button { Speaker.shared.say(lastTutor?.text ?? "", lang: lang) } label: {
                        Image(systemName: "arrow.counterclockwise").font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(theme.text).frame(width: 60, height: 60).background(theme.chip, in: Circle())
                    }
                    .accessibilityLabel(L("Repeat"))
                    HoldToTalkButton(dictation: dictation) {
                        heard = ""
                        dictation.press(language: lang) { heard = $0 }
                    }
                    .scaleEffect(1.4)
                    Button { endCall() } label: {
                        Image(systemName: "phone.down.fill").font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white).frame(width: 60, height: 60).background(Color.red, in: Circle())
                    }
                    .accessibilityLabel(L("End call"))
                }
                .padding(.bottom, 40)
            }
        }
        .background(theme.ground)
        .onAppear {
            startCount = messages.count
            dictation.prepare(language: lang)
            if let t = lastTutor?.text { Speaker.shared.say(t, lang: lang) }
        }
        .onDisappear { dictation.shutdown() }
        .onChange(of: dictation.isRecording) { _, rec in
            // Released: send what was said, then read the reply aloud.
            guard !rec else { return }
            let said = heard.trimmingCharacters(in: .whitespaces)
            guard !said.isEmpty else { return }
            Task {
                try? await Task.sleep(for: .milliseconds(350))   // let the final words arrive
                let text = heard.trimmingCharacters(in: .whitespaces)
                await model.sendTutor(text.isEmpty ? said : text, lang: lang)
                heard = ""
                if let t = lastTutor?.text { Speaker.shared.say(t, lang: lang) }
            }
        }
    }

    private func endCall() {
        dictation.shutdown()
        withAnimation { ended = true }
        guard model.aiAvailable, let l = model.language(lang), callMessages.contains(where: { $0.role == .me }) else { return }
        loadingFeedback = true
        Task {
            feedback = try? await model.ai.callFeedback(language: l, level: model.level(lang), history: callMessages)
            loadingFeedback = false
        }
    }

    private func summary(_ l: Language?) -> some View {
        let said = callMessages.filter { $0.role == .me }.count
        let fixes = callMessages.filter { $0.role == .correction }
        let mins = max(1, Int(Date().timeIntervalSince(started)) / 60)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(L("Call ended")).font(.fig(28, .bold)).padding(.top, 30)
                Text(L("%lld min · you spoke %lld times", mins, said)).font(.fig(15)).foregroundStyle(theme.muted)
                if loadingFeedback {
                    ProgressView(L("ChatGPT is reviewing your call…")).frame(maxWidth: .infinity).padding(20)
                }
                if let f = feedback {
                    Text(f.summary).font(.fig(16)).card()
                    if !f.strengths.isEmpty {
                        SectionLabel(text: L("What went well"))
                        ForEach(f.strengths, id: \.self) { s in Label(s, systemImage: "checkmark.circle.fill").font(.fig(14)) }
                    }
                    if !f.fixes.isEmpty {
                        SectionLabel(text: L("To work on"))
                        ForEach(f.fixes, id: \.self) { c in CorrectionBubble(wrong: c.wrong, right: c.right, note: c.note) }
                    }
                } else if !fixes.isEmpty {
                    SectionLabel(text: L("To work on"))
                    ForEach(fixes) { c in CorrectionBubble(wrong: c.wrong ?? "", right: c.right ?? "", note: c.note ?? "") }
                }
                SectionLabel(text: L("Transcript"))
                ForEach(callMessages.filter { $0.role != .correction }) { m in
                    ChatBubble(text: m.text, mine: m.role == .me, speakLang: lang)
                }
                Button(L("Done")) { dismiss() }.buttonStyle(.primary).padding(.top, 10)
            }
            .padding(.horizontal, 20).padding(.bottom, 24)
        }
    }
}
