import SwiftUI

/// The writing system of a language: every letter with its sound, tap to hear, practise in groups of 8.
struct AlphabetView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    let alphabet: Alphabet
    @State private var playing: CourseLesson?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(alphabet.name).font(.fig(22, .bold))
                Spacer()
                BackButton(systemName: "xmark") { dismiss() }
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                        ForEach(Array(alphabet.letters.enumerated()), id: \.offset) { _, l in
                            Button { Speaker.shared.say(l.char, lang: alphabet.lang, slow: true) } label: {
                                VStack(spacing: 2) {
                                    Text(verbatim: l.char).font(.system(size: 28, weight: .semibold)).foregroundStyle(theme.text)
                                    Text(verbatim: l.sound).font(.fig(12)).foregroundStyle(theme.muted)
                                }
                                .frame(maxWidth: .infinity, minHeight: 66)
                                .background(theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    SectionLabel(text: L("Practise"))
                    ForEach(Array(alphabet.groups.enumerated()), id: \.offset) { i, g in
                        let lesson = alphabet.lesson(group: i)
                        let done = model.s.courseDone.contains(lesson.unit.id)
                        Button { playing = lesson } label: {
                            HStack(spacing: 12) {
                                Image(systemName: done ? "checkmark" : "character").font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(done ? .white : theme.ad)
                                    .frame(width: 40, height: 40).background(done ? theme.a : theme.at, in: Circle())
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(L("Letters %lld", i + 1)).font(.fig(15, .semibold))
                                    Text(verbatim: g.map(\.char).joined(separator: " ")).font(.fig(14)).foregroundStyle(theme.muted)
                                }
                                Spacer()
                                Image(systemName: "chevron.forward").font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.muted)
                            }
                            .card(padding: 12)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 24)
            }
        }
        .background(theme.ground)
        .fullScreenCover(item: $playing) { l in
            LessonPlayerView(lesson: l, lang: alphabet.lang).environmentObject(model).environment(\.theme, model.theme)
        }
    }
}
