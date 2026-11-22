import SwiftUI
import Translation

/// Plays one course lesson: exercises one by one, Check → feedback → Continue, missed ones come back once.
struct LessonPlayerView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    let lesson: CourseLesson
    let lang: String

    @State private var meanings: [String: String]?
    @State private var queue: [Exercise] = []
    @State private var total = 0
    @State private var index = 0
    @State private var result: Check.Result?
    @State private var firstTryRight = 0
    @State private var missed: Set<String> = []
    @State private var started = Date()
    @State private var earned: Int?
    @State private var confirmQuit = false
    // Answer state for the current exercise
    @State private var picked: String?
    @State private var chosenTiles: [Int] = []
    @State private var typed = ""
    @State private var heard = ""
    @State private var matched: Set<String> = []
    @State private var matchLeft: String?
    @State private var matchRight: String?
    @State private var matchMiss = false
    @StateObject private var dictation = Dictation()
    @FocusState private var fieldFocused: Bool

    private var ex: Exercise? { queue[safe: index] }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                BackButton(systemName: "xmark") { if earned == nil && index > 0 { confirmQuit = true } else { dismiss() } }
                ProgressBar(value: total == 0 ? 0 : Double(min(index, total)) / Double(total))
                    .animation(.easeInOut(duration: 0.3), value: index)
            }
            .padding(.horizontal, 20).padding(.vertical, 10)

            if let earned {
                finished(earned)
            } else if meanings == nil {
                Spacer()
                ProgressView(L("Preparing your lesson…"))
                Spacer()
            } else if let ex {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(ex.instruction).font(.fig(22, .bold))
                        exerciseBody(ex)
                    }
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .id(ex.id)
                }
                .scrollDismissesKeyboard(.interactively)
                footer(ex)
            }
        }
        .background(theme.ground)
        .modifier(TextTranslator(texts: lesson.unit.words.map(\.en) + lesson.unit.sentences.map(\.en), done: { meanings = $0; build() }))
        .confirmationDialog(L("Quit this lesson?"), isPresented: $confirmQuit, titleVisibility: .visible) {
            Button(L("Quit"), role: .destructive) { dismiss() }
        } message: {
            Text(L("Your progress in this lesson will be lost."))
        }
    }

    // MARK: Flow

    private var isJump: Bool {
        if case .jump = lesson.mode { return true }
        return false
    }

    private var passedJump: Bool { total > 0 && Double(firstTryRight) / Double(total) >= 0.8 }

    private func build() {
        SoundFX.enabled = model.s.settings.soundEffects
        let list = LessonBuilder.exercises(for: lesson, meanings: meanings ?? [:],
                                           allowSpeaking: model.s.settings.speakingExercises)
        queue = list
        total = list.count
        started = Date()
        prepare()
    }

    private func prepare() {
        picked = nil; chosenTiles = []; typed = ""; heard = ""; matched = []; matchLeft = nil; matchRight = nil
        result = nil
        if let ex { autoplay(ex) }
    }

    private func autoplay(_ ex: Exercise) {
        switch ex {
        case .meaning(_, let item, _), .listenPick(_, let item, _), .listenType(_, let item), .buildMeaning(_, let item, _):
            Speaker.shared.say(item.t, lang: lang)
        default: break
        }
    }

    private func check(_ ex: Exercise) {
        let r: Check.Result
        switch ex {
        case .meaning(_, let item, _): r = picked == item.en ? .right : .wrong(item.en)
        case .pickWord(_, let item, _), .listenPick(_, let item, _): r = picked == item.t ? .right : .wrong(item.t)
        case .fillBlank(_, let item, let blank, _):
            let answer = Check.words(item.t)[blank]
            r = Check.norm(picked ?? "") == Check.norm(answer) ? .right : .wrong(item.t)
        case .buildTarget(_, let item, let tiles): r = Check.tiles(chosenTiles.map { tiles[$0] }, expected: item.t)
        case .buildMeaning(_, let item, let tiles): r = Check.tiles(chosenTiles.map { tiles[$0] }, expected: item.en)
        case .listenType(_, let item), .typeTarget(_, let item): r = Check.typed(typed, expected: item.t)
        case .speak(_, let item): r = Check.spoken(heard, expected: item.t)
        case .match: r = .right
        }
        result = r
        fieldFocused = false
        dictation.stop()
        let it = item(of: ex)
        switch r {
        case .right, .typo:
            if !missed.contains(ex.id) { firstTryRight += 1 }
            Haptics.success()
            SoundFX.play(.right)
            if lesson.mode == .practice, let it { model.clearMistake(it.0, lang: lang) }
            if let it, !it.1 { model.recordWord(it.0, right: true, lang: lang) }
        case .wrong:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            SoundFX.play(.wrong)
            if let it { model.noteMistake(it.0, sentence: it.1, lang: lang) }
            if let it, !it.1 { model.recordWord(it.0, right: false, lang: lang) }
            if !missed.contains(ex.id) {
                missed.insert(ex.id)
                queue.append(ex)        // comes back once at the end
            }
        }
        // Hear the right answer after a miss.
        if r != .right, let t = target(of: ex) { Speaker.shared.say(t, lang: lang) }
    }

    /// The word or sentence an exercise is about, with its original (English) meaning; true = sentence.
    private func item(of ex: Exercise) -> (CourseItem, Bool)? {
        let found: (CourseItem, Bool)?
        switch ex {
        case .meaning(_, let i, _), .pickWord(_, let i, _), .listenPick(_, let i, _), .typeTarget(_, let i): found = (i, false)
        case .buildTarget(_, let i, _), .buildMeaning(_, let i, _), .fillBlank(_, let i, _, _), .listenType(_, let i), .speak(_, let i): found = (i, true)
        case .match: found = nil
        }
        guard var f = found else { return nil }
        if let original = meanings?.first(where: { $0.value == f.0.en })?.key { f.0.en = original }
        return f
    }

    private func target(of ex: Exercise) -> String? {
        switch ex {
        case .buildTarget(_, let i, _), .typeTarget(_, let i), .listenType(_, let i), .fillBlank(_, let i, _, _): i.t
        default: nil
        }
    }

    private func next() {
        if index + 1 < queue.count {
            index += 1
            prepare()
        } else {
            let secs = Int(Date().timeIntervalSince(started))
            SoundFX.play(.done)
            withAnimation { earned = model.finishLesson(lesson, lang: lang, correct: firstTryRight, total: total, seconds: secs) }
        }
    }

    private var canCheck: Bool {
        guard let ex else { return false }
        switch ex {
        case .meaning, .pickWord, .listenPick, .fillBlank: return picked != nil
        case .buildTarget, .buildMeaning: return !chosenTiles.isEmpty
        case .listenType, .typeTarget: return !typed.trimmingCharacters(in: .whitespaces).isEmpty
        case .speak: return !heard.isEmpty && !dictation.isRecording
        case .match(_, let items): return matched.count == items.count
        }
    }

    // MARK: Footer

    @ViewBuilder
    private func footer(_ ex: Exercise) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let result {
                switch result {
                case .right:
                    Label(L("Correct!"), systemImage: "checkmark.circle.fill").font(.fig(18, .bold)).foregroundStyle(theme.ad)
                case .typo(let answer):
                    Label(L("Almost — watch the spelling"), systemImage: "checkmark.circle.fill").font(.fig(17, .bold)).foregroundStyle(theme.ad)
                    Text(answer).font(.fig(15))
                case .wrong(let answer):
                    Label(L("Correct answer:"), systemImage: "xmark.circle.fill").font(.fig(17, .bold)).foregroundStyle(theme.errorText)
                    Text(answer).font(.fig(16, .semibold))
                }
                Button(L("Continue"), action: next).buttonStyle(.primary)
            } else {
                HStack(spacing: 10) {
                    if case .speak = ex {
                        Button(L("Can't speak now")) {
                            model.s.settings.speakingExercises = false
                            next()
                        }
                        .buttonStyle(PrimaryButtonStyle(kind: .chip))
                    }
                    Button(L("Check")) { check(ex) }.buttonStyle(.primary).disabled(!canCheck)
                }
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(resultTint.ignoresSafeArea(edges: .bottom))
        .animation(.easeInOut(duration: 0.2), value: result)
    }

    private var resultTint: Color {
        switch result {
        case .right, .typo: theme.at
        case .wrong: theme.errorTint
        case nil: theme.ground
        }
    }

    // MARK: Exercises

    @ViewBuilder
    private func exerciseBody(_ ex: Exercise) -> some View {
        switch ex {
        case .meaning(_, let item, let options):
            promptCard(item.t, speak: true)
            choices(options)
        case .pickWord(_, let item, let options):
            promptCard(item.en, speak: false)
            choices(options, speak: true)
        case .listenPick(_, let item, let options):
            listenButtons(item.t)
            choices(options, speak: true)
        case .fillBlank(_, let item, let blank, let options):
            let ws = Check.words(item.t)
            let shown = ws.enumerated().map { $0.offset == blank ? (picked ?? "_____") : $0.element }.joined(separator: " ")
            promptCard(shown, speak: false, sub: item.en)
            choices(options, speak: true)
        case .buildTarget(_, let item, let tiles):
            promptCard(item.en, speak: false)
            tileBoard(tiles, speak: true)
        case .buildMeaning(_, let item, let tiles):
            promptCard(item.t, speak: true)
            tileBoard(tiles, speak: false)
        case .listenType(_, let item):
            listenButtons(item.t)
            answerField(L("Type in %@", model.language(lang)?.name ?? ""))
        case .typeTarget(_, let item):
            promptCard(item.en, speak: false)
            answerField(L("Type in %@", model.language(lang)?.name ?? ""))
        case .speak(_, let item):
            promptCard(item.t, speak: true, sub: item.en)
            VStack(spacing: 12) {
                HoldToTalkButton(dictation: dictation) {
                    heard = ""
                    dictation.press(language: lang) { heard = $0 }
                }
                Text(heard.isEmpty ? L("Hold the mic and read the sentence") : heard)
                    .font(.fig(15)).foregroundStyle(heard.isEmpty ? theme.muted : theme.text)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity).padding(.top, 20)
            .onAppear { dictation.prepare(language: lang) }
            .onDisappear { dictation.shutdown() }
        case .match(_, let items):
            matchBoard(items)
        }
    }

    private func promptCard(_ text: String, speak: Bool, sub: String? = nil) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if speak {
                Button { Speaker.shared.say(text, lang: lang) } label: {
                    Image(systemName: "speaker.wave.2.fill").font(.system(size: 18)).foregroundStyle(.white)
                        .frame(width: 44, height: 44).background(theme.a, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("Play audio"))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(text).font(.fig(20, .semibold))
                    .onTapGesture { if speak { Speaker.shared.say(text, lang: lang) } }
                if let sub { Text(sub).font(.fig(14)).foregroundStyle(theme.muted) }
            }
            Spacer(minLength: 0)
        }
        .card()
    }

    private func listenButtons(_ text: String) -> some View {
        HStack(spacing: 14) {
            Button { Speaker.shared.say(text, lang: lang) } label: {
                Image(systemName: "speaker.wave.2.fill").font(.system(size: 28)).foregroundStyle(.white)
                    .frame(width: 84, height: 84).background(theme.a, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .accessibilityLabel(L("Play audio"))
            Button { Speaker.shared.say(text, lang: lang, slow: true) } label: {
                Image(systemName: "tortoise.fill").font(.system(size: 20)).foregroundStyle(theme.ad)
                    .frame(width: 60, height: 60).background(theme.at, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .accessibilityLabel(L("Play slowly"))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity).padding(.vertical, 8)
    }

    private func choices(_ opts: [String], speak: Bool = false) -> some View {
        VStack(spacing: 10) {
            ForEach(opts, id: \.self) { o in
                let on = picked == o
                Button {
                    guard result == nil else { return }
                    picked = o
                    Haptics.tap()
                    if speak { Speaker.shared.say(o, lang: lang) }
                } label: {
                    Text(o).font(.fig(17, .semibold)).foregroundStyle(on ? theme.ad : theme.text)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(on ? theme.at : theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(on ? theme.a : theme.line, lineWidth: on ? 2 : 1.5))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func tileBoard(_ tiles: [String], speak: Bool) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            FlowLayout(spacing: 8) {
                ForEach(Array(chosenTiles.enumerated()), id: \.offset) { pos, i in
                    tile(tiles[i], filled: true) { if result == nil { chosenTiles.remove(at: pos); Haptics.tap() } }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            .padding(12)
            .overlay(alignment: .bottom) { Rectangle().fill(theme.line).frame(height: 1.5) }
            FlowLayout(spacing: 8) {
                ForEach(Array(tiles.enumerated()), id: \.offset) { i, w in
                    let used = chosenTiles.contains(i)
                    tile(w, filled: !used) {
                        guard !used && result == nil else { return }
                        chosenTiles.append(i)
                        Haptics.tap()
                        if speak { Speaker.shared.say(w, lang: lang) }
                    }
                        .opacity(used ? 0.35 : 1)
                }
            }
        }
    }

    private func tile(_ word: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(word).font(.fig(16, .semibold)).foregroundStyle(theme.text)
                .padding(.horizontal, 14).frame(height: 42)
                .background(filled ? theme.card : theme.chip, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(theme.line, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    private func answerField(_ placeholder: String) -> some View {
        TextField(placeholder, text: $typed, axis: .vertical)
            .font(.fig(18)).lineLimit(1...4)
            .textInputAutocapitalization(.never).autocorrectionDisabled()
            .focused($fieldFocused)
            .disabled(result != nil)
            .padding(16)
            .background(theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(theme.line, lineWidth: 1.5))
            .onAppear { fieldFocused = true }
    }

    private func matchBoard(_ items: [CourseItem]) -> some View {
        // Fixed shuffles per exercise: left = target words, right = meanings.
        let left = items.map(\.t).sorted { Check.norm($0) < Check.norm($1) }
        let right = items.map(\.en).sorted { $0.count < $1.count }
        return HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 10) {
                ForEach(left, id: \.self) { t in matchCell(t, selected: matchLeft == t, done: matched.contains(t)) { pickMatch(left: t, items: items) } }
            }
            VStack(spacing: 10) {
                ForEach(right, id: \.self) { m in
                    let done = items.contains { $0.en == m && matched.contains($0.t) }
                    matchCell(m, selected: matchRight == m, done: done) { pickMatch(right: m, items: items) }
                }
            }
        }
        .modifier(Shake(animatableData: matchMiss ? 1 : 0))
    }

    private func matchCell(_ text: String, selected: Bool, done: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text).font(.fig(15, .semibold)).foregroundStyle(done ? theme.muted : selected ? theme.ad : theme.text)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 54).padding(.horizontal, 6)
                .background(selected ? theme.at : theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(selected ? theme.a : theme.line, lineWidth: selected ? 2 : 1.5))
                .opacity(done ? 0.4 : 1)
        }
        .buttonStyle(.plain)
        .disabled(done || result != nil)
    }

    private func pickMatch(left: String? = nil, right: String? = nil, items: [CourseItem]) {
        if let left { matchLeft = left; Speaker.shared.say(left, lang: lang) }
        if let right { matchRight = right }
        guard let l = matchLeft, let r = matchRight else { Haptics.tap(); return }
        if items.contains(where: { $0.t == l && $0.en == r }) {
            matched.insert(l)
            Haptics.tap()
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            withAnimation(.default) { matchMiss.toggle() }
        }
        matchLeft = nil
        matchRight = nil
    }

    // MARK: Done

    private func finished(_ xp: Int) -> some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "star.fill").font(.system(size: 44)).foregroundStyle(.white)
                .frame(width: 104, height: 104).background(theme.a, in: Circle())
            Text(finishTitle).font(.fig(28, .bold)).multilineTextAlignment(.center)
            if isJump {
                Text(passedJump ? L("Everything before this section is now marked as done.")
                                : L("You need 80% to jump ahead. Keep going from where you are — you'll get there."))
                    .font(.fig(15)).foregroundStyle(theme.muted).multilineTextAlignment(.center)
            }
            HStack(spacing: 12) {
                stat("+\(xp)", L("points"))
                stat("\(total == 0 ? 100 : firstTryRight * 100 / total)%", L("accuracy"))
                stat(minutes, L("time"))
            }
            Spacer()
            Button(L("Continue")) { dismiss() }.buttonStyle(.primary)
        }
        .padding(20)
    }

    private var finishTitle: String {
        switch lesson.mode {
        case .normal: L("Lesson complete!")
        case .practice: L("Practice done!")
        case .jump: passedJump ? L("You jumped ahead!") : L("Not quite yet")
        }
    }

    private var minutes: String {
        let s = Int(Date().timeIntervalSince(started))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(verbatim: value).font(.fig(22, .bold))
            Text(label).font(.fig(12, .semibold)).foregroundStyle(theme.muted)
        }
        .frame(maxWidth: .infinity).card(padding: 14)
    }
}

private struct Shake: GeometryEffect {
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 8 * sin(animatableData * .pi * 4), y: 0))
    }
}

