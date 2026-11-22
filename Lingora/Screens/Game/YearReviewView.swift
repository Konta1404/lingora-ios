import SwiftUI

/// Your year in Lingora: time, XP, lessons, days, top language, best streak.
struct YearReviewView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0

    /// "3 h 25 min" in the iPhone's language.
    static func duration(_ seconds: Int) -> String {
        let f = DateComponentsFormatter()
        f.unitsStyle = .abbreviated
        f.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute]
        return f.string(from: TimeInterval(max(60, seconds))) ?? ""
    }

    private var year: String { String(DateUtil.dayKey().prefix(4)) }
    private var t: YearTotal { model.s.yearTotals[year] ?? YearTotal() }

    var body: some View {
        let top = t.xpByLanguage.max { $0.value < $1.value }
        let topName = top.flatMap { model.language($0.key)?.name } ?? "—"
        let cards: [(String, String, String, Color)] = [
            ("calendar", L("Your %@ in Lingora", year), L("Let's look back."), theme.a),
            ("clock.fill", Self.duration(t.seconds), L("spent learning"), .orange),
            ("sun.max.fill", "\(t.daysActive.count)", L("days you practised"), .yellow),
            ("bolt.fill", "\(t.xp) XP", L("earned"), theme.a),
            ("book.fill", "\(t.lessons)", L("lessons finished"), .blue),
            ("flame.fill", "\(model.s.bestStreak)", L("days: your best streak"), .red),
            ("star.fill", topName, L("your top language"), .purple),
            ("hands.clap.fill", L("See you next year!"), L("Keep going — every day counts."), theme.a),
        ]
        ZStack {
            theme.ground.ignoresSafeArea()
            TabView(selection: $page) {
                ForEach(Array(cards.enumerated()), id: \.offset) { i, c in
                    VStack(spacing: 18) {
                        Spacer()
                        Image(systemName: c.0).font(.system(size: 46, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 120, height: 120).background(c.3, in: Circle())
                        Text(verbatim: c.1).font(.fig(34, .bold)).multilineTextAlignment(.center)
                        Text(c.2).font(.fig(18)).foregroundStyle(theme.muted).multilineTextAlignment(.center)
                        Spacer()
                        Spacer()
                    }
                    .padding(28)
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            VStack {
                HStack {
                    Spacer()
                    BackButton(systemName: "xmark") { dismiss() }
                }
                .padding(.horizontal, 20).padding(.top, 12)
                Spacer()
            }
            if page == 7 { Confetti().ignoresSafeArea().allowsHitTesting(false) }
        }
    }
}
