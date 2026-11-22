import SwiftUI
import AVFoundation

struct LessonView: View {
    let task: PlanTask
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var content: LessonContent?
    @State private var step = 0
    @State private var flipped = false
    @State private var knew = false
    @State private var choice: Int?
    @State private var written = ""
    @State private var check: AIService.WritingCheck?
    @State private var checking = false
    @State private var startedAt = Date()
    @State private var speaking = false
    @State private var speech = AVSpeechSynthesizer()

    private var lang: Language? { model.language(task.langKey) }
    private var score: Int {
        guard let c = content else { return 0 }
        let writingOK = check?.correct == true || written.split(separator: " ").count >= 3
        return (knew ? 1 : 0) + (choice == c.question.answer ? 1 : 0) + (writingOK ? 1 : 0)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                BackButton(systemName: "xmark") { dismiss() }
                ProgressBar(value: Double(min(step + 1, 3)) / 3)
                Text(L("%lld of %lld", min(step + 1, 3), 3)).font(.fig(13, .semibold)).foregroundStyle(theme.muted)
            }
            .padding(.horizontal, 20).padding(.vertical, 8)

            if let content {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if step < 3 {
                            HStack(spacing: 8) {
                                if let lang { CodeBadge(code: lang.code, hue: theme.colors(for: lang.hue), size: 28) }
                                Text(verbatim: "\(task.type.label) · \(task.title)").font(.fig(13, .semibold)).foregroundStyle(theme.muted)
                            }
                        }
                        switch step {
                        case 0: flashcard(content)
                        case 1: gapFill(content)
                        case 2: writing(content)
                        default: doneView
                        }
                    }
                    .padding(20)
                    .animation(.easeInOut(duration: 0.25), value: step)
                }
                .scrollDismissesKeyboard(.interactively)
                footer(content)
            } else {
                Spacer()
                VStack(spacing: 12) {
                    ProgressView().tint(theme.a)
                    Text(model.aiAvailable ? L("ChatGPT is preparing your lesson…") : L("Preparing your lesson…"))
                        .font(.fig(15)).foregroundStyle(theme.muted)
                }
                Spacer()
            }
        }
        .background(theme.ground.ignoresSafeArea())
        .task {
            if content == nil {
                content = await model.lessonContent(for: task)
                startedAt = Date()
            }
        }
    }

    // MARK: Steps

    private func flashcard(_ c: LessonContent) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("New word")).font(.fig(theme.titleSize, .bold)).tracking(-0.6)
            Button { withAnimation(.spring(duration: 0.35)) { flipped = true } } label: {
                VStack(spacing: 14) {
                    HStack {
                        Spacer()
                        Button { speak(c.card.front) } label: {
                            Label(speaking ? L("Playing…") : L("Listen"), systemImage: "speaker.wave.2")
                                .font(.fig(13, .semibold)).foregroundStyle(theme.ad)
                                .padding(.horizontal, 12).frame(height: 32).background(theme.at, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 10)
                    Text(c.card.front).font(.fig(34, .bold)).multilineTextAlignment(.center)
                    if flipped {
                        Text(c.card.back).font(.fig(18, .semibold)).foregroundStyle(theme.ad)
                        Text(c.card.example).font(.fig(15)).foregroundStyle(theme.muted).multilineTextAlignment(.center)
                    }
                    Spacer(minLength: 10)
                }
                .padding(18)
                .frame(maxWidth: .infinity, minHeight: 280)
                .background(theme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(theme.cardBorder, lineWidth: 1))
                .shadow(color: theme.shadow.opacity(theme.isOpen ? 0 : 0.06), radius: 14, y: 6)
            }
            .buttonStyle(.plain)
            Text(flipped ? L("Be honest — it shapes tomorrow.") : L("Tap the card to see the meaning"))
                .font(.fig(14)).foregroundStyle(theme.muted).frame(maxWidth: .infinity)
        }
    }

    private func gapFill(_ c: LessonContent) -> some View {
        let answered = choice != nil
        return VStack(alignment: .leading, spacing: 14) {
            Text(L("Fill the gap")).font(.fig(theme.titleSize, .bold)).tracking(-0.6)
            Text(c.question.prompt).font(.fig(22, .semibold)).card(padding: 18)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(Array(c.question.options.enumerated()), id: \.offset) { i, o in
                    let correct = i == c.question.answer
                    let picked = i == choice
                    Button {
                        guard !answered else { return }
                        withAnimation { choice = i }
                        if correct { Haptics.success() } else { Haptics.tap() }
                    } label: {
                        Text(o).font(.fig(18, .semibold))
                            .strikethrough(answered && picked && !correct)
                            .foregroundStyle(answered && correct ? theme.ad : theme.text)
                            .frame(maxWidth: .infinity, minHeight: 64)
                            .background(answered && correct ? theme.at : theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(answered && correct ? theme.a : theme.line, lineWidth: answered && correct ? 2 : 1.5))
                            .opacity(answered && !correct && !picked ? 0.5 : 1)
                    }
                    .buttonStyle(.plain)
                }
            }
            if answered {
                VStack(alignment: .leading, spacing: 4) {
                    Text(choice == c.question.answer ? L("Yes, that’s it.") : L("Almost.")).font(.fig(15, .bold))
                    Text(c.question.why)
                }
                .tintedNote(theme.at, theme.ad, radius: theme.radius)
                .transition(.opacity)
            }
        }
    }

    private func writing(_ c: LessonContent) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("Your turn")).font(.fig(theme.titleSize, .bold)).tracking(-0.6)
            Text(c.writing.prompt).font(.fig(17, .semibold))
            TextEditor(text: $written)
                .font(.fig(16))
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(minHeight: 120)
                .background(theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(theme.line, lineWidth: 1.5))
                .disabled(check != nil)
            if let check {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("Model answer")).font(.fig(12, .semibold)).foregroundStyle(theme.muted)
                    Text(check.modelAnswer).font(.fig(17, .semibold))
                }
                .card()
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "sparkles").padding(.top, 2)
                    Text(check.feedback)
                }
                .tintedNote(theme.at, theme.ad, radius: theme.radius)
            }
        }
    }

    private var doneView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark").font(.system(size: 30, weight: .bold)).foregroundStyle(.white)
                .frame(width: 72, height: 72).background(theme.a, in: Circle())
                .padding(.top, 40)
            Text(L("Nicely done")).font(.fig(theme.titleSize, .bold))
            Text(verbatim: "\(lang?.name ?? "") · \(task.title)").font(.fig(15)).foregroundStyle(theme.muted)
            HStack(spacing: 10) {
                stat(L("Correct"), "\(score)/3")
                stat(L("Time"), L("%lld min", max(1, Int(Date().timeIntervalSince(startedAt) / 60))))
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.fig(13, .semibold)).foregroundStyle(theme.muted)
            Text(value).font(.fig(24, .bold))
        }
        .card()
    }

    // MARK: Footer

    @ViewBuilder
    private func footer(_ c: LessonContent) -> some View {
        Group {
            switch step {
            case 0:
                HStack(spacing: 10) {
                    Button(L("Not yet")) { knew = false; step = 1 }.buttonStyle(PrimaryButtonStyle(kind: .chip))
                    Button(L("I knew it")) { knew = true; step = 1 }.buttonStyle(.primary)
                }
                .disabled(!flipped)
            case 1:
                Button(L("Continue")) { step = 2 }.buttonStyle(.primary).disabled(choice == nil)
            case 2:
                Button(check != nil ? L("Finish") : (checking ? L("Checking…") : L("Check my answer"))) {
                    if check != nil { step = 3; return }
                    checking = true
                    Task {
                        let result = await model.checkWriting(task, lesson: c, answer: written)
                        withAnimation { check = result }
                        checking = false
                    }
                }
                .buttonStyle(.primary)
                .disabled(checking)
            default:
                Button(L("Back to today")) {
                    model.complete(task, score: score)
                    model.tab = .today
                    dismiss()
                }
                .buttonStyle(.primary)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
    }

    private func speak(_ text: String) {
        let u = AVSpeechUtterance(string: text)
        if let lang, !lang.isCustom { u.voice = AVSpeechSynthesisVoice(language: lang.key) }
        u.rate = 0.42
        speaking = true
        speech.speak(u)
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            speaking = false
        }
    }
}
