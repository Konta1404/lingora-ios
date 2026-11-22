import SwiftUI
import AVFoundation

/// Today: one entry to every kind of practice.
struct PracticeCard: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme
    let lang: Language
    @State private var open = false

    var body: some View {
        let due = model.dueWordCount(lang.key)
        Button { open = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "dumbbell.fill").font(.system(size: 17, weight: .bold)).foregroundStyle(theme.ad)
                    .frame(width: 44, height: 44).background(theme.at, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Practice")).font(.fig(16, .bold))
                    Text(due > 0 ? L("%lld words to review · stories, listening, speaking", due)
                                 : L("Stories, listening, speaking and your mistakes"))
                        .font(.fig(13)).foregroundStyle(theme.muted).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward").font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.muted)
            }
            .card(padding: 14)
        }
        .buttonStyle(.plain)
        .fullScreenCover(isPresented: $open) {
            PracticeView(lang: lang.key)
                .environmentObject(model)
                .environment(\.theme, model.theme)
        }
    }
}

struct PracticeView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    let lang: String
    @State private var playing: CourseLesson?
    @State private var story: Story?
    @State private var showWords = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                BackButton(systemName: "xmark") { dismiss() }
                Text(L("Practice")).font(.fig(22, .bold))
                Spacer()
            }
            .padding(.horizontal, 20).padding(.vertical, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        tile(L("Words"), sub: L("%lld due", model.dueWordCount(lang)), icon: "character.book.closed.fill",
                             lesson: model.wordsLesson(lang))
                        tile(L("Mistakes"), sub: L("%lld saved", model.mistakeCount(lang)), icon: "arrow.uturn.backward",
                             lesson: model.mistakesLesson(lang))
                        tile(L("Listening"), sub: L("Ears only"), icon: "ear.fill", lesson: model.listeningLesson(lang))
                        tile(L("Speaking"), sub: L("Read aloud"), icon: "mic.fill", lesson: model.speakingLesson(lang))
                        tile(L("Speed round"), sub: L("60 seconds"), icon: "timer", lesson: model.speedLesson(lang))
                    }
                    Button { showWords = true } label: {
                        HStack {
                            Label(L("All my words"), systemImage: "list.bullet").font(.fig(15, .semibold))
                            Spacer()
                            Text(verbatim: "\(model.learnedWords(lang).count)").font(.fig(14)).foregroundStyle(theme.muted)
                            Image(systemName: "chevron.forward").font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.muted)
                        }
                        .card(padding: 14)
                    }
                    .buttonStyle(.plain)

                    let all = model.stories(lang)
                    ForEach([(L("Stories"), all.filter { $0.kind == nil }), (L("Reading"), all.filter { $0.kind == "reading" })], id: \.0) { section in
                        storyList(section.0, section.1)
                    }
                    if !all.isEmpty {
                        Text(L("Stories open as you finish the matching course units.")).font(.fig(12)).foregroundStyle(theme.muted)
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 24)
            }
        }
        .background(theme.ground)
        .fullScreenCover(item: $playing) { l in
            LessonPlayerView(lesson: l, lang: lang).environmentObject(model).environment(\.theme, model.theme)
        }
        .fullScreenCover(item: $story) { st in
            StoryPlayerView(story: st, lang: lang).environmentObject(model).environment(\.theme, model.theme)
        }
        .sheet(isPresented: $showWords) {
            WordListView(lang: lang).environmentObject(model).environment(\.theme, model.theme)
                .presentationDetents([.large]).presentationCornerRadius(28)
        }
    }

    @ViewBuilder
    private func storyList(_ title: String, _ stories: [Story]) -> some View {
                    if !stories.isEmpty {
                        SectionLabel(text: title).padding(.top, 6)
                        VStack(spacing: 0) {
                            ForEach(Array(stories.enumerated()), id: \.element.id) { i, st in
                                let open = model.storyUnlocked(st), done = model.s.storiesDone.contains(st.id)
                                Button { if open { story = st } } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: done ? "checkmark" : open ? "book.pages.fill" : "lock.fill")
                                            .font(.system(size: 15, weight: .bold))
                                            .foregroundStyle(done ? .white : open ? theme.ad : theme.muted)
                                            .frame(width: 40, height: 40).background(done ? theme.a : open ? theme.at : theme.chip, in: Circle())
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(L(st.title)).font(.fig(15, .semibold)).foregroundStyle(open ? theme.text : theme.muted)
                                            Text(verbatim: "\(st.level) · \(st.speakers.keys.sorted().joined(separator: " & "))")
                                                .font(.fig(12)).foregroundStyle(theme.muted)
                                        }
                                        Spacer()
                                    }
                                    .padding(.horizontal, 14).padding(.vertical, 10)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .disabled(!open)
                                .overlay(alignment: .top) { if i > 0 { Rectangle().fill(theme.line).frame(height: 1) } }
                            }
                        }
                        .card(padding: 0)
                    }
    }

    private func tile(_ title: String, sub: String, icon: String, lesson: CourseLesson?) -> some View {
        Button { playing = lesson } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon).font(.system(size: 18, weight: .bold)).foregroundStyle(lesson == nil ? theme.muted : theme.ad)
                Text(title).font(.fig(16, .bold))
                Text(lesson == nil ? L("Finish a lesson first") : sub).font(.fig(12)).foregroundStyle(theme.muted).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(padding: 14)
            .opacity(lesson == nil ? 0.6 : 1)
        }
        .buttonStyle(.plain)
        .disabled(lesson == nil)
    }
}

/// Every course word you've met, with how well you know it.
struct WordListView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    let lang: String
    @State private var meanings: [String: String] = [:]
    @State private var query = ""

    var body: some View {
        let all = model.learnedWords(lang)
        let q = Check.norm(query)
        let shown = q.isEmpty ? all : all.filter { Check.norm($0.t).contains(q) || Check.norm(meanings[$0.en] ?? $0.en).contains(q) }
        VStack(spacing: 0) {
            HStack {
                Text(L("My words")).font(.fig(24, .bold))
                Text(verbatim: "\(all.count)").font(.fig(16, .semibold)).foregroundStyle(theme.muted)
                Spacer()
                BackButton(systemName: "xmark") { dismiss() }
            }
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 8)
            TextField(L("Search"), text: $query).font(.fig(16)).textInputAutocapitalization(.never).autocorrectionDisabled()
                .padding(.horizontal, 16).frame(height: 44)
                .background(theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(theme.line, lineWidth: 1.5))
                .padding(.horizontal, 20).padding(.bottom, 8)
            if all.isEmpty {
                Spacer()
                Text(L("Words appear here as you finish lessons.")).font(.fig(15)).foregroundStyle(theme.muted)
                Spacer()
            } else {
                List(shown, id: \.t) { w in
                    let m = model.memory(w, lang: lang)
                    Button { Speaker.shared.say(w.t, lang: lang) } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(w.t).font(.fig(16, .semibold)).foregroundStyle(theme.text)
                                Text(meanings[w.en] ?? w.en).font(.fig(13)).foregroundStyle(theme.muted)
                            }
                            Spacer()
                            HStack(spacing: 3) {
                                ForEach(0..<5, id: \.self) { i in
                                    Capsule().fill(i < (m?.box ?? 0) ? theme.a : theme.chip2).frame(width: 6, height: 14)
                                }
                            }
                            .accessibilityLabel(L("Strength %lld of 5", m?.box ?? 0))
                        }
                    }
                    .listRowBackground(theme.card)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .background(theme.ground)
        .modifier(TextTranslator(texts: all.map(\.en), done: { meanings = $0 }))
    }
}

/// Plays a story: lines appear one by one with two voices, questions in between, optional listen-only mode.
struct StoryPlayerView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    let story: Story
    let lang: String
    @State private var shown = 1
    @State private var answers: [Int: Int] = [:]
    @State private var revealed: Set<Int> = []
    @State private var listenOnly = false
    @State private var meanings: [String: String] = [:]
    @State private var showMeaning: Set<Int> = []
    @State private var started = Date()
    @State private var earned: Int?

    private var current: Story.Line? { story.lines[safe: shown - 1] }
    private var waitingForAnswer: Bool { (current?.isQuestion ?? false) && answers[shown - 1] == nil }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                BackButton(systemName: "xmark") { dismiss() }
                ProgressBar(value: Double(shown) / Double(story.lines.count))
                Button { listenOnly.toggle() } label: {
                    Image(systemName: listenOnly ? "ear.fill" : "text.alignleft").font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(listenOnly ? .white : theme.text)
                        .frame(width: 40, height: 40).background(listenOnly ? theme.a : theme.chip, in: Circle())
                }
                .accessibilityLabel(listenOnly ? L("Show text") : L("Listen only"))
            }
            .padding(.horizontal, 20).padding(.vertical, 10)

            if let earned {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "book.closed.fill").font(.system(size: 40)).foregroundStyle(.white)
                        .frame(width: 100, height: 100).background(theme.a, in: Circle())
                    Text(L("Story complete!")).font(.fig(28, .bold))
                    Text(verbatim: "+\(earned) XP").font(.fig(18, .semibold)).foregroundStyle(theme.ad)
                    Spacer()
                    Button(L("Continue")) { dismiss() }.buttonStyle(.primary)
                }
                .padding(20)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(meanings[story.title] ?? L(story.title)).font(.fig(24, .bold)).padding(.bottom, 6)
                            ForEach(0..<shown, id: \.self) { i in
                                line(i).id(i)
                            }
                        }
                        .padding(.horizontal, 20).padding(.bottom, 20)
                    }
                    .onChange(of: shown) { withAnimation { proxy.scrollTo(shown - 1, anchor: .bottom) } }
                }
                Button(shown >= story.lines.count ? L("Finish") : L("Continue")) { advance() }
                    .buttonStyle(.primary)
                    .disabled(waitingForAnswer)
                    .padding(.horizontal, 20).padding(.vertical, 10)
            }
        }
        .background(theme.ground)
        .modifier(TextTranslator(texts: story.englishTexts, done: { meanings = $0 }))
        .onAppear { play(0) }
    }

    @ViewBuilder
    private func line(_ i: Int) -> some View {
        let l = story.lines[i]
        if l.isQuestion, let q = l.q, let options = l.options {
            VStack(alignment: .leading, spacing: 10) {
                Label(meanings[q] ?? q, systemImage: "questionmark.circle.fill").font(.fig(16, .bold)).foregroundStyle(theme.ad)
                ForEach(Array(options.enumerated()), id: \.offset) { oi, o in
                    let picked = answers[i] == oi, right = oi == l.a
                    let answered = answers[i] != nil
                    Button {
                        guard !answered else { return }
                        answers[i] = oi
                        if right { SoundFX.play(.right); Haptics.success() } else { SoundFX.play(.wrong) }
                    } label: {
                        Text(meanings[o] ?? o).font(.fig(15, .semibold))
                            .foregroundStyle(answered && (right || picked) ? (right ? theme.ad : theme.errorText) : theme.text)
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(answered && right ? theme.at : answered && picked ? theme.errorTint : theme.card,
                                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(theme.line, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .card()
        } else if let t = l.t {
            let speaker = l.s ?? ""
            let female = story.speakers[speaker] == "f"
            let hidden = listenOnly && !revealed.contains(i)
            HStack(alignment: .top, spacing: 10) {
                Avatar(initial: String(speaker.prefix(1)), hue: Hue(h: female ? 340 : 210), size: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: speaker).font(.fig(12, .semibold)).foregroundStyle(theme.muted)
                    Button {
                        if hidden { revealed.insert(i) } else { play(i) }
                    } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "speaker.wave.2.fill").font(.system(size: 13)).foregroundStyle(theme.ad).padding(.top, 3)
                            Text(hidden ? L("Tap to show the text") : t).font(.fig(17, hidden ? .regular : .semibold))
                                .foregroundStyle(hidden ? theme.muted : theme.text).multilineTextAlignment(.leading)
                        }
                    }
                    .buttonStyle(.plain)
                    if showMeaning.contains(i), let en = l.en {
                        Text(meanings[en] ?? en).font(.fig(14)).foregroundStyle(theme.muted)
                    } else if !hidden {
                        Button(L("Show meaning")) { showMeaning.insert(i) }.font(.fig(12, .semibold)).foregroundStyle(theme.ad)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private func play(_ i: Int) {
        guard let l = story.lines[safe: i], let t = l.t else { return }
        let g: AVSpeechSynthesisVoiceGender = story.speakers[l.s ?? ""] == "f" ? .female : .male
        Speaker.shared.say(t, lang: lang, gender: g)
    }

    private func advance() {
        if shown >= story.lines.count {
            let correct = story.lines.indices.filter { story.lines[$0].isQuestion && answers[$0] == story.lines[$0].a }.count
            SoundFX.play(.done)
            withAnimation { earned = model.finishStory(story, lang: lang, correct: correct, seconds: Int(Date().timeIntervalSince(started))) }
            return
        }
        shown += 1
        play(shown - 1)
    }
}
