import SwiftUI

/// A one-minute level check built on the CEFR "can do" statements.
/// Works for every language, no network needed.
struct PlacementView: View {
    let lang: Language
    var onDone: (Level) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @State private var index = 0
    @State private var answers: [Int] = []   // 0 no, 1 a little, 2 yes

    struct Statement { let level: Level; let text: String }

    static let statements: [Statement] = [
        .init(level: .a1, text: "I can say hello, introduce myself and say where I'm from."),
        .init(level: .a1, text: "I can understand simple words like numbers, days and prices."),
        .init(level: .a2, text: "I can order food, ask for directions and shop for basics."),
        .init(level: .a2, text: "I can talk about my family, my job and what I did yesterday."),
        .init(level: .b1, text: "I can handle most travel situations and explain a problem."),
        .init(level: .b1, text: "I can follow the main points of clear talk about familiar topics."),
        .init(level: .b2, text: "I can follow TV news and give my opinion with reasons."),
        .init(level: .b2, text: "I can chat with native speakers without much effort on either side."),
        .init(level: .c1, text: "I can understand long, complex texts and notice implied meaning."),
        .init(level: .c1, text: "I can speak fluently at work or in study without searching for words."),
        .init(level: .c2, text: "I can understand almost everything I hear or read with ease."),
        .init(level: .c2, text: "I can express fine shades of meaning, even in complex situations."),
    ]

    /// Highest level where both statements got at least "a little" and one got "yes".
    static func result(_ answers: [Int]) -> Level {
        var best = Level.a1
        for level in Level.allCases {
            let idx = statements.indices.filter { statements[$0].level == level }
            let got = idx.compactMap { answers[safe: $0] }
            guard got.count == idx.count, got.allSatisfy({ $0 >= 1 }), got.contains(2) else { break }
            best = level.next
            if level == .c2 { best = .c2 }
        }
        return best
    }

    private var finished: Bool { index >= Self.statements.count }

    var body: some View {
        VStack(spacing: 0) {
            SetupHeader(close: true)
            if finished { resultView } else { question }
        }
        .background(theme.ground)
    }

    private var question: some View {
        let st = Self.statements[index]
        return VStack(alignment: .leading, spacing: 18) {
            ProgressView(value: Double(index), total: Double(Self.statements.count)).tint(theme.a)
            Text(L("Level check · %@", lang.name)).font(.fig(14, .semibold)).foregroundStyle(theme.muted)
            Text(L(st.text)).font(.fig(24, .semibold)).fixedSize(horizontal: false, vertical: true)
                .id(index).transition(.opacity)
            Spacer()
            VStack(spacing: 10) {
                answer(L("Yes, easily"), 2)
                answer(L("A little"), 1)
                answer(L("Not yet"), 0)
            }
        }
        .padding(20)
    }

    private func answer(_ title: String, _ v: Int) -> some View {
        Button(title) {
            Haptics.tap()
            answers.append(v)
            // Two "not yet" in a row ends the check early.
            let tail = answers.suffix(2)
            withAnimation(.easeOut(duration: 0.2)) {
                if tail.count == 2, tail.allSatisfy({ $0 == 0 }) { index = Self.statements.count }
                else { index += 1 }
            }
        }
        .buttonStyle(PrimaryButtonStyle(kind: v == 2 ? .accent : .chip, height: 52))
    }

    private var resultView: some View {
        let lv = Self.result(answers)
        return VStack(spacing: 16) {
            Spacer()
            Text(lv.code).font(.fig(64, .bold)).foregroundStyle(theme.a)
            Text(lv.label).font(.fig(22, .semibold))
            Text(L("Your course starts here. You can still jump ahead or go back any time."))
                .font(.fig(16)).foregroundStyle(theme.muted).multilineTextAlignment(.center)
            Spacer()
            Button(L("Use %@", lv.code)) { onDone(lv); Haptics.success(); dismiss() }
                .buttonStyle(.primary)
        }
        .padding(20)
    }
}
