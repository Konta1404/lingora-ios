import SwiftUI
import AVFoundation

/// Summary card used on Today and Me.
struct WordsSummaryCard: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        let level = model.vocab.currentLevel
        let total = VocabBank.words(in: level).count
        let mastered = model.vocab.mastered(in: level)
        let h = theme.colors(for: 150)
        HStack(spacing: 12) {
            Text(verbatim: "DE").font(.fig(12, .bold)).foregroundStyle(.white)
                .frame(width: 40, height: 40).background(h.base, in: Circle())
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(L("German words")).font(.fig(15, .semibold))
                    Spacer()
                    Text(L("%@ · %lld/%lld mastered", level.rawValue, mastered, total))
                        .font(.fig(12, .semibold)).foregroundStyle(theme.muted)
                }
                ProgressBar(value: total == 0 ? 0 : Double(mastered) / Double(total), color: h.base, height: 6)
            }
            Image(systemName: "chevron.forward").font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.muted)
        }
        .card(padding: 14)
    }
}

struct WordsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    enum Phase { case overview, question, result, summary }
    enum Verdict { case right, wrong, unknown, checking }

    @State private var phase: Phase = .overview
    @State private var session: [VocabWord] = []
    @State private var index = 0
    @State private var requeued: [String: Int] = [:]
    @State private var loading = false

    // answer
    @State private var meaning = ""
    @State private var article: String?
    @State private var plural = ""
    @State private var noPlural = false
    @State private var perfekt = ""

    // result
    @State private var meaningVerdict: Verdict = .unknown
    @State private var meaningNote = ""
    @State private var articleOK = true
    @State private var pluralOK = true
    @State private var perfektOK = true
    @State private var rightCount = 0
    @State private var answeredCount = 0
    @State private var speech = AVSpeechSynthesizer()

    private var word: VocabWord? { session[safe: index] }
    private var languageName: String {
        Locale.current.localizedString(forLanguageCode: String(model.normalizedVocabLang.prefix { $0 != "-" }))?.capitalized(with: .current) ?? model.normalizedVocabLang
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                BackButton(systemName: "xmark") { dismiss() }
                if phase == .question || phase == .result {
                    ProgressBar(value: session.isEmpty ? 0 : Double(index) / Double(session.count))
                    Text(verbatim: "\(min(index + 1, session.count))/\(session.count)").font(.fig(13, .semibold)).foregroundStyle(theme.muted)
                } else {
                    Spacer()
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch phase {
                    case .overview: overview
                    case .question, .result: if let word { card(word) }
                    case .summary: summary
                    }
                }
                .padding(20)
                .animation(.easeInOut(duration: 0.2), value: phase)
            }
            .scrollDismissesKeyboard(.interactively)

            footer
                .padding(.horizontal, 20).padding(.vertical, 10)
        }
        .background(theme.ground.ignoresSafeArea())
    }

    // MARK: Overview

    private var overview: some View {
        let store = model.vocab
        let current = store.currentLevel
        return VStack(alignment: .leading, spacing: 14) {
            ScreenTitle(text: L("German words"))
            Text(L("Goethe-Institut word lists, A1 → A2 → B1. Words come in random order. Nouns need their article and plural, verbs their Perfekt."))
                .font(.fig(15)).foregroundStyle(theme.muted)

            VStack(spacing: 0) {
                ForEach(Array(VocabLevel.allCases.enumerated()), id: \.element) { i, level in
                    let total = VocabBank.words(in: level).count
                    let mastered = store.mastered(in: level)
                    let unlocked = store.isUnlocked(level)
                    HStack(spacing: 12) {
                        Text(verbatim: level.rawValue).font(.fig(14, .bold))
                            .foregroundStyle(unlocked ? .white : theme.muted)
                            .frame(width: 40, height: 40)
                            .background(unlocked ? theme.a : theme.chip, in: Circle())
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(L("%lld of %lld mastered", mastered, total)).font(.fig(14, .semibold))
                                Spacer()
                                if !unlocked { Image(systemName: "lock.fill").font(.system(size: 12)).foregroundStyle(theme.muted) }
                                else if level == current { Text(L("now")).font(.fig(12, .semibold)).foregroundStyle(theme.ad)
                                    .padding(.horizontal, 8).padding(.vertical, 2).background(theme.at, in: Capsule()) }
                            }
                            ProgressBar(value: total == 0 ? 0 : Double(mastered) / Double(total), height: 6)
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .overlay(alignment: .top) { if i > 0 { Rectangle().fill(theme.line).frame(height: 1) } }
                    .opacity(unlocked ? 1 : 0.6)
                }
            }
            .card(padding: 0)

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lock.open").padding(.top, 2)
                Text(L("New words only come from %@ until you've mastered every %@ word. A word is mastered after 3 right answers in a row, spread over at least two days.",
                       current.rawValue, current.rawValue))
            }
            .tintedNote(theme.at, theme.ad, radius: theme.radius)

            if !model.aiAvailable {
                Text(L("Without ChatGPT, you check your own translations. Sign in to have them checked for you."))
                    .font(.fig(13)).foregroundStyle(theme.muted)
            }
        }
    }

    // MARK: Card

    @ViewBuilder
    private func card(_ w: VocabWord) -> some View {
        let answered = phase == .result
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text(verbatim: w.level.rawValue).font(.fig(12, .bold)).foregroundStyle(theme.ad)
                    .padding(.horizontal, 10).frame(height: 26).background(theme.at, in: Capsule())
                Text(posLabel(w)).font(.fig(13, .semibold)).foregroundStyle(theme.muted)
                Spacer()
                Button { speak(w) } label: {
                    Label(L("Listen"), systemImage: "speaker.wave.2").font(.fig(13, .semibold)).foregroundStyle(theme.ad)
                        .padding(.horizontal, 12).frame(height: 32).background(theme.at, in: Capsule())
                }
                .buttonStyle(.plain)
            }

            Text(verbatim: answered ? w.fullForm : w.de)
                .font(.fig(answered ? 26 : 34, .bold))
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
                .padding(.vertical, 18)
                .card()

            // Meaning
            LingoraField(label: L("Meaning in %@", languageName), text: $meaning)
                .disabled(answered)
            if answered { meaningResult(w) }

            if w.pos == .noun {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("Article")).font(.fig(13, .semibold)).foregroundStyle(theme.muted)
                    HStack(spacing: 8) {
                        ForEach(["der", "die", "das"], id: \.self) { a in
                            let on = article == a
                            let correct = w.acceptedArticles.contains(a)
                            Button { if !answered { article = a; Haptics.tap() } } label: {
                                Text(verbatim: a).font(.fig(17, .semibold))
                                    .foregroundStyle(on && !answered ? .white : (answered && correct ? theme.ad : theme.text))
                                    .frame(maxWidth: .infinity, minHeight: 48)
                                    .background(answered ? (correct ? theme.at : theme.card) : (on ? theme.a : theme.card),
                                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(answered && correct ? theme.a : (answered && on ? theme.errorBorder : theme.line), lineWidth: 1.5))
                                    .strikethrough(answered && on && !correct)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if w.isPluralOnly {
                    Text(L("This noun is only used in the plural.")).font(.fig(13)).foregroundStyle(theme.muted)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        LingoraField(label: L("Plural"), text: $plural, error: answered && !pluralOK ? L("Plural: %@", w.plural.map { "die \($0)" } ?? L("no plural")) : nil)
                            .disabled(answered || noPlural)
                            .textInputAutocapitalization(.words)
                        Button { if !answered { noPlural.toggle(); if noPlural { plural = "" } } } label: {
                            Label(L("No plural"), systemImage: noPlural ? "checkmark.square.fill" : "square")
                                .font(.fig(14, .semibold)).foregroundStyle(noPlural ? theme.ad : theme.muted)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if w.pos == .verb {
                LingoraField(label: L("Perfekt (e.g. hat gemacht, ist gefahren)"), text: $perfekt,
                             error: answered && !perfektOK ? L("Perfekt: %@", w.perfekt ?? "") : nil)
                    .disabled(answered)
                    .textInputAutocapitalization(.never)
            }

            if answered, let ex = w.example {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: ex).font(.fig(15, .semibold))
                    if let en = w.exampleEn { Text(verbatim: en).font(.fig(13)).foregroundStyle(theme.muted) }
                }
                .card(padding: 14)
            }
        }
    }

    @ViewBuilder
    private func meaningResult(_ w: VocabWord) -> some View {
        let accepted = model.translations(for: w.id)
        VStack(alignment: .leading, spacing: 8) {
            switch meaningVerdict {
            case .checking:
                HStack(spacing: 8) { ProgressView().tint(theme.a); Text(L("ChatGPT is checking…")) }
            case .right:
                Label(L("Right"), systemImage: "checkmark.circle.fill").font(.fig(14, .bold))
            case .wrong:
                Label(L("Not quite"), systemImage: "xmark.circle.fill").font(.fig(14, .bold))
            case .unknown:
                Text(L("Did you know the meaning?")).font(.fig(14, .bold))
                HStack(spacing: 8) {
                    PillButton(title: L("I knew it"), bg: theme.a, fg: .white) { meaningVerdict = .right }
                    PillButton(title: L("I didn't"), bg: theme.chip, fg: theme.text) { meaningVerdict = .wrong }
                }
            }
            if !accepted.isEmpty {
                Text(verbatim: accepted.joined(separator: ", ")).font(.fig(15, .semibold))
            } else if meaningVerdict == .unknown, let en = w.exampleEn {
                Text(L("Hint from the example: %@", en)).font(.fig(13))
            }
            if !meaningNote.isEmpty { Text(verbatim: meaningNote).font(.fig(13)) }
        }
        .tintedNote(meaningVerdict == .wrong ? Color(hex: 0xf6e9e4) : theme.at,
                    meaningVerdict == .wrong ? theme.errorText : theme.ad, radius: 16)
    }

    // MARK: Summary

    private var summary: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark").font(.system(size: 30, weight: .bold)).foregroundStyle(.white)
                .frame(width: 72, height: 72).background(theme.a, in: Circle())
                .padding(.top, 30)
            Text(L("Round done")).font(.fig(theme.titleSize, .bold))
            Text(L("%lld of %lld right", rightCount, answeredCount)).font(.fig(16)).foregroundStyle(theme.muted)
            WordsSummaryCard()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Footer & flow

    @ViewBuilder
    private var footer: some View {
        switch phase {
        case .overview:
            Button(loading ? L("Getting words ready…") : L("Start practice"), action: start)
                .buttonStyle(.primary)
                .disabled(loading || VocabBank.words.isEmpty)
        case .question:
            Button(L("Check"), action: check)
                .buttonStyle(.primary)
                .disabled(!canCheck)
        case .result:
            Button(L("Continue"), action: next)
                .buttonStyle(.primary)
                .disabled(meaningVerdict == .unknown || meaningVerdict == .checking)
        case .summary:
            HStack(spacing: 10) {
                Button(L("Done")) { dismiss() }.buttonStyle(PrimaryButtonStyle(kind: .chip))
                Button(L("Another round"), action: start).buttonStyle(.primary)
            }
        }
    }

    private var canCheck: Bool {
        guard let w = word else { return false }
        if w.pos == .noun && article == nil { return false }
        return true
    }

    private func start() {
        loading = true
        Task {
            let s = VocabEngine.buildSession(model.vocab)
            await model.prefetchTranslations(for: s)
            session = s
            index = 0
            requeued = [:]
            rightCount = 0
            answeredCount = 0
            resetAnswer()
            loading = false
            phase = s.isEmpty ? .summary : .question
        }
    }

    private func resetAnswer() {
        meaning = ""; article = nil; plural = ""; noPlural = false; perfekt = ""
        meaningVerdict = .unknown; meaningNote = ""
        articleOK = true; pluralOK = true; perfektOK = true
    }

    private func check() {
        guard let w = word else { return }
        if w.pos == .noun {
            articleOK = VocabEngine.checkArticle(article, w)
            pluralOK = VocabEngine.checkPlural(plural, noPlural: noPlural, w)
        }
        if w.pos == .verb { perfektOK = VocabEngine.checkPerfekt(perfekt, w) }

        let accepted = model.translations(for: w.id)
        let answer = meaning.trimmingCharacters(in: .whitespaces)
        if answer.isEmpty {
            meaningVerdict = .wrong
        } else if !accepted.isEmpty && VocabEngine.checkTranslation(answer, accepted: accepted) {
            meaningVerdict = .right
        } else if model.aiAvailable {
            meaningVerdict = .checking
            Task {
                do {
                    let r = try await model.ai.checkTranslation(id: w.id, answer: answer, accepted: accepted)
                    meaningVerdict = r.correct ? .right : .wrong
                    meaningNote = r.note
                    if model.translations(for: w.id).isEmpty { await model.prefetchTranslations(for: [w]) }
                } catch {
                    meaningVerdict = .unknown
                }
            }
        } else {
            meaningVerdict = .unknown   // self-grade
        }
        withAnimation { phase = .result }
        if articleOK && pluralOK && perfektOK { Haptics.tap() }
    }

    private func next() {
        guard let w = word else { return }
        let ok = meaningVerdict == .right && articleOK && pluralOK && perfektOK
        model.recordVocab(w.id, correct: ok)
        answeredCount += 1
        if ok {
            rightCount += 1
            Haptics.success()
        } else if (requeued[w.id] ?? 0) < 2 {
            requeued[w.id, default: 0] += 1
            session.insert(w, at: min(session.count, index + 4))
        }
        resetAnswer()
        if index + 1 < session.count {
            index += 1
            phase = .question
        } else {
            phase = .summary
        }
    }

    private func posLabel(_ w: VocabWord) -> String {
        switch w.pos {
        case .noun: L("Noun")
        case .verb: L("Verb")
        case .other: L("Word")
        }
    }

    private func speak(_ w: VocabWord) {
        let text = w.pos == .noun ? "\(w.article ?? "") \(w.de)" : w.de
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "de-DE")
        u.rate = 0.42
        speech.speak(u)
    }
}
