import SwiftUI

/// The course path for one language: sections → units → lessons, unlocked in order.
struct CourseMapView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State var lang: String
    @State private var playing: CourseLesson?
    @State private var openTip: String?

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
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(course.sections) { section in
                                sectionHeader(section, hue: h)
                                ForEach(Array(section.units.enumerated()), id: \.element.id) { i, unit in
                                    unitCard(unit, number: i + 1, course: course, hue: h).id(unit.id)
                                }
                            }
                            Text(L("More units are on the way."))
                                .font(.fig(13)).foregroundStyle(theme.muted).frame(maxWidth: .infinity).padding(.vertical, 8)
                        }
                        .padding(.horizontal, 20).padding(.bottom, 24)
                    }
                    .onAppear {
                        if let next = model.nextLesson(lang) { proxy.scrollTo(next.unit.id, anchor: .center) }
                    }
                }
                Button(model.nextLesson(lang).map { L("Continue: %@", $0.unit.title) } ?? L("Course complete")) {
                    playing = model.nextLesson(lang)
                }
                .buttonStyle(.primary)
                .disabled(model.nextLesson(lang) == nil)
                .padding(.horizontal, 20).padding(.vertical, 10)
            } else {
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: "books.vertical").font(.system(size: 34)).foregroundStyle(theme.muted)
                    Text(L("The built-in course covers German for now. Units for other languages will come from ChatGPT."))
                        .font(.fig(15)).foregroundStyle(theme.muted).multilineTextAlignment(.center)
                }
                .padding(32)
                Spacer()
            }
        }
        .background(theme.ground)
        .fullScreenCover(item: $playing) { lesson in
            LessonPlayerView(lesson: lesson, lang: lang)
                .environmentObject(model)
                .environment(\.theme, model.theme)
        }
    }

    private func sectionHeader(_ s: CourseSection, hue: Hue) -> some View {
        HStack(spacing: 10) {
            Text(verbatim: s.level).font(.fig(12, .bold)).foregroundStyle(.white)
                .padding(.horizontal, 10).frame(height: 24).background(hue.base, in: Capsule())
            Text(L(s.title)).font(.fig(17, .bold))
            Spacer()
        }
        .padding(.top, 8)
    }

    private func unitCard(_ u: CourseUnit, number: Int, course: Course, hue: Hue) -> some View {
        let lessons = LessonKind.allCases.map { CourseLesson(unit: u, kind: $0) }
        let done = lessons.filter(model.isDone).count
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Unit %lld", number)).font(.fig(12, .semibold)).foregroundStyle(theme.muted)
                    Text(L(u.title)).font(.fig(17, .bold))
                }
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

/// Today: where you are in a language's course, one tap to continue.
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
                        Text(next.map { "\(L($0.unit.title)) · \($0.kind.title)" } ?? L("Course complete"))
                            .font(.fig(13)).foregroundStyle(theme.muted).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Text(next == nil ? L("Review") : p.done == 0 ? L("Start") : L("Continue"))
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
