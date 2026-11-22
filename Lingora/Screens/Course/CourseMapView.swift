import SwiftUI

/// The course path for one language: CEFR levels → categories → topics (units) → 4 lessons each.
struct CourseMapView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State var lang: String
    @State private var playing: CourseLesson?
    @State private var openTip: String?
    @State private var alphabet: String?
    @State private var names: [String: String] = [:]

    /// English names shown in another app language go through Apple Translation once.
    private var needsNames: Bool {
        let code = Locale.current.language.languageCode?.identifier ?? "en"
        return code != "en" && code != "sr"
    }
    private func show(_ english: String, _ native: String) -> String {
        Curriculum.usesSerbian ? native : (names[english] ?? english)
    }

    var body: some View {
        let language = model.language(lang)
        let h = language.map { theme.colors(for: $0.hue) } ?? Hue(h: theme.accent.hue)
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                BackButton(systemName: "xmark") { dismiss() }
                VStack(alignment: .leading, spacing: 0) {
                    Text(L("%@ course", language?.name ?? "")).font(.fig(20, .bold))
                    let p = model.courseProgress(lang)
                    Text(L("%lld of %lld lessons", p.done, p.total)).font(.fig(13)).foregroundStyle(theme.muted)
                }
                Spacer()
                if model.courseLanguages.count > 1 {
                    Menu {
                        ForEach(model.courseLanguages) { l in Button(l.name) { lang = l.key } }
                    } label: {
                        Image(systemName: "globe").font(.system(size: 16, weight: .semibold)).foregroundStyle(theme.text)
                            .frame(width: 40, height: 40).background(theme.chip, in: Circle())
                    }
                    .accessibilityLabel(L("Change language"))
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 8)

            if let course = model.course(lang) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            if let a = Alphabet.forLanguage(lang) { alphabetCard(a, hue: h) }
                            practiceRow(hue: h)
                            ForEach(Array(course.sections.enumerated()), id: \.element.id) { si, section in
                                if si == 0 || course.sections[si - 1].level != section.level {
                                    levelHeader(section.level, hue: h).id("level-\(section.level)")
                                }
                                sectionHeader(section, index: si, course: course, hue: h)
                                ForEach(section.units) { unit in
                                    Group {
                                        if unit.isPlaceholder {
                                            placeholderCard(unit, course: course, hue: h)
                                        } else {
                                            unitCard(unit, course: course, hue: h)
                                        }
                                    }
                                    .id(unit.id)
                                }
                            }
                        }
                        .padding(.horizontal, 20).padding(.bottom, 24)
                    }
                    .scrollBounceBehavior(.basedOnSize, axes: [.horizontal])
                    .onAppear {
                        let target = model.nextLesson(lang)?.unit.id ?? model.nextPlaceholder(lang)?.id
                        if let target { DispatchQueue.main.async { proxy.scrollTo(target, anchor: .center) } }
                    }
                }
                bottomButton()
            } else {
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: "books.vertical").font(.system(size: 34)).foregroundStyle(theme.muted)
                    Text(L("The built-in course covers German for now. Sign in to have ChatGPT write units for other languages."))
                        .font(.fig(15)).foregroundStyle(theme.muted).multilineTextAlignment(.center)
                }
                .padding(32)
                Spacer()
            }
        }
        .background(theme.ground)
        .modifier(TextTranslator(texts: needsNames ? allEnglishNames : [], done: { names = $0 }))
        .fullScreenCover(isPresented: Binding(get: { alphabet != nil }, set: { if !$0 { alphabet = nil } })) {
            if let a = alphabet.flatMap(Alphabet.forLanguage) {
                AlphabetView(alphabet: a).environmentObject(model).environment(\.theme, model.theme)
            }
        }
        .fullScreenCover(item: $playing) { lesson in
            LessonPlayerView(lesson: lesson, lang: lang)
                .environmentObject(model)
                .environment(\.theme, model.theme)
        }
    }

    private var allEnglishNames: [String] {
        Curriculum.shared.levels.flatMap { l in [l.name.en, l.description.en] + l.categories.flatMap { [$0.name.en] + $0.topics.map(\.en) } }
    }

    @ViewBuilder
    private func bottomButton() -> some View {
        if let next = model.nextLesson(lang) {
            Button(L("Continue: %@", model.unitTitle(next.unit))) { playing = next }
                .buttonStyle(.primary)
                .padding(.horizontal, 20).padding(.vertical, 10)
        } else if let p = model.nextPlaceholder(lang), model.canWriteUnits {
            Button(model.writingUnit != nil ? L("ChatGPT is writing the next unit…") : L("Write the next unit")) {
                Task { await model.writeUnit(p, lang: lang) }
            }
            .buttonStyle(.primary)
            .disabled(model.writingUnit != nil)
            .padding(.horizontal, 20).padding(.vertical, 10)
        }
    }

    private func alphabetCard(_ a: Alphabet, hue: Hue) -> some View {
        Button { alphabet = a.lang } label: {
            HStack(spacing: 12) {
                Text(verbatim: a.letters.first?.char ?? "").font(.system(size: 24, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 44, height: 44).background(hue.base, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(a.name).font(.fig(16, .bold))
                    Text(L("Learn to read and write the letters")).font(.fig(13)).foregroundStyle(theme.muted)
                }
                Spacer()
                Image(systemName: "chevron.forward").font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.muted)
            }
            .card(padding: 12)
        }
        .buttonStyle(.plain)
    }

    private func levelHeader(_ code: String, hue: Hue) -> some View {
        let lv = Curriculum.shared.levels.first { $0.level == code }
        let mine = model.level(lang).code == code
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text(verbatim: code).font(.fig(20, .heavy)).foregroundStyle(.white)
                    .padding(.horizontal, 12).frame(height: 36).background(hue.deep, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 0) {
                    Text(lv.map { show($0.name.en, $0.name.sr) } ?? code).font(.fig(18, .bold))
                    if mine { Text(L("Your level")).font(.fig(12, .semibold)).foregroundStyle(hue.deep) }
                }
            }
            if let lv { Text(show(lv.description.en, lv.description.sr)).font(.fig(13)).foregroundStyle(theme.muted) }
        }
        .padding(.top, 18)
    }

    private func sectionHeader(_ s: CourseSection, index: Int, course: Course, hue: Hue) -> some View {
        let cat = Curriculum.shared.levels.flatMap(\.categories).first { s.id.hasSuffix("-\($0.id)") }
        let firstLocked = s.units.first.map { !model.unitOpen($0, in: course) } ?? false
        let realUnits = s.units.filter { !$0.isPlaceholder }
        let done = realUnits.filter(model.unitDone).count
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(cat.map { show($0.name.en, $0.name.sr) } ?? L(s.title)).font(.fig(16, .bold))
                Text(L("%lld of %lld topics", done, s.units.count)).font(.fig(12)).foregroundStyle(theme.muted)
            }
            Spacer()
            if index > 0 && firstLocked && !s.units.allSatisfy(\.isPlaceholder) {
                PillButton(title: L("Jump here"), icon: "forward.fill", bg: hue.tint, fg: hue.deep, height: 32) {
                    playing = model.jumpLesson(lang, to: index)
                }
            }
        }
        .padding(.top, 6)
    }

    private func placeholderCard(_ u: CourseUnit, course: Course, hue: Hue) -> some View {
        let open = model.unitOpen(u, in: course)
        let writing = model.writingUnit == u.id
        let title = u.topic.flatMap { Curriculum.shared.topic($0) }.map { show($0.0.en, $0.0.sr) } ?? u.title
        return HStack(spacing: 12) {
            Image(systemName: open ? "sparkles" : "lock.fill").font(.system(size: 15, weight: .bold))
                .foregroundStyle(open ? hue.deep : theme.muted)
                .frame(width: 40, height: 40).background(open ? hue.tint : theme.chip, in: Circle())
            Text(title).font(.fig(15, .semibold)).foregroundStyle(open ? theme.text : theme.muted)
            Spacer(minLength: 4)
            if open && model.canWriteUnits {
                if writing {
                    ProgressView()
                } else {
                    PillButton(title: L("Write"), icon: "sparkles", bg: hue.base, fg: .white, height: 32) {
                        Task { await model.writeUnit(u, lang: lang) }
                    }
                    .disabled(model.writingUnit != nil)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(theme.card.opacity(open ? 1 : 0.6), in: RoundedRectangle(cornerRadius: theme.radius, style: .continuous))
    }

    @ViewBuilder
    private func practiceRow(hue: Hue) -> some View {
        let mistakes = model.mistakesLesson(lang)
        let review = model.reviewLesson(lang)
        if mistakes != nil || review != nil {
            HStack(spacing: 10) {
                if let mistakes {
                    practiceButton(L("Mistakes · %lld", model.mistakeCount(lang)), icon: "arrow.uturn.backward", hue: hue) { playing = mistakes }
                }
                if let review {
                    practiceButton(L("Mixed review"), icon: "shuffle", hue: hue) { playing = review }
                }
            }
        }
    }

    private func practiceButton(_ title: String, icon: String, hue: Hue, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.fig(14, .semibold)).foregroundStyle(hue.deep)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(hue.tint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func unitCard(_ u: CourseUnit, course: Course, hue: Hue) -> some View {
        let lessons = LessonKind.allCases.map { CourseLesson(unit: u, kind: $0) }
        let done = lessons.filter(model.isDone).count
        let title = u.topic.flatMap { Curriculum.shared.topic($0) }.map { show($0.0.en, $0.0.sr) } ?? L(u.title)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Text(title).font(.fig(17, .bold))
                Spacer()
                if u.tip != nil {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { openTip = openTip == u.id ? nil : u.id }
                    } label: {
                        Image(systemName: "lightbulb").font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(openTip == u.id ? .white : hue.deep)
                            .frame(width: 36, height: 36)
                            .background(openTip == u.id ? hue.base : hue.tint, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("Grammar tip"))
                }
            }
            if openTip == u.id, let tip = u.tip {
                Text(L(tip)).font(.fig(14)).foregroundStyle(theme.text)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(hue.tint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            HStack(spacing: 0) {
                ForEach(Array(lessons.enumerated()), id: \.element.id) { i, l in
                    if i > 0 {
                        Rectangle().fill(model.isDone(lessons[i - 1]) ? hue.base : theme.chip2).frame(height: 3)
                    }
                    node(l, course: course, hue: hue)
                }
            }
            ProgressBar(value: Double(done) / Double(lessons.count), color: hue.base, height: 6)
        }
        .card()
    }

    private func node(_ l: CourseLesson, course: Course, hue: Hue) -> some View {
        let done = model.isDone(l)
        let open = model.isUnlocked(l, in: course)
        let current = open && !done
        return Button { if open { playing = l } } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle().fill(done ? hue.base : current ? hue.tint : theme.chip)
                        .frame(width: 54, height: 54)
                    if current {
                        Circle().strokeBorder(hue.base, lineWidth: 3).frame(width: 62, height: 62)
                    }
                    Image(systemName: done ? "checkmark" : open ? l.kind.icon : "lock.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(done ? .white : current ? hue.deep : theme.muted)
                }
                .frame(width: 62, height: 62)
                Text(l.kind.title).font(.fig(11, .semibold)).foregroundStyle(open ? theme.text : theme.muted)
                    .lineLimit(1).minimumScaleFactor(0.7).frame(width: 70)
            }
        }
        .buttonStyle(.plain)
        .disabled(!open)
        .accessibilityLabel("\(l.kind.title), \(done ? L("done") : open ? L("ready") : L("locked"))")
    }
}

struct CourseSummaryCard: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme
    let lang: Language

    var body: some View {
        let h = theme.colors(for: lang.hue)
        let p = model.courseProgress(lang.key)
        let next = model.nextLesson(lang.key)
        Button { model.courseLang = lang.key } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    CodeBadge(code: lang.code, hue: h, size: 40, filled: true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("%@ course", lang.name)).font(.fig(16, .bold))
                        Text(next.map { "\(model.unitTitle($0.unit)) · \($0.kind.title)" }
                             ?? model.nextPlaceholder(lang.key).map { L("Next: %@", model.unitTitle($0)) }
                             ?? (p.total == 0 ? L("ChatGPT writes your first unit") : L("Course complete")))
                            .font(.fig(13)).foregroundStyle(theme.muted).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Text(p.total == 0 || p.done == 0 ? L("Start") : next == nil ? L("Review") : L("Continue"))
                        .font(.fig(14, .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 14).frame(height: 34).background(h.base, in: Capsule())
                }
                ProgressBar(value: p.total == 0 ? 0 : Double(p.done) / Double(p.total), color: h.base, height: 6)
            }
            .card()
        }
        .buttonStyle(.plain)
    }
}
