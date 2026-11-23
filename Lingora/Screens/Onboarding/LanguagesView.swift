import SwiftUI

/// Step 2 of 3 — also reached from Me → Add a language.
struct LanguagesView: View {
    let addMode: Bool
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme
    @State private var query = ""
    @State private var initialLearning: [String] = []

    private var q: String { query.trimmingCharacters(in: .whitespaces).lowercased() }
    private var allLanguages: [Language] { Catalog.all.compactMap { model.language($0.key) } + model.s.customLanguages.values.sorted { $0.name < $1.name } }

    private var matches: [Language]? {
        guard !q.isEmpty else { return nil }
        return allLanguages.filter {
            $0.name.lowercased().contains(q) || $0.native.lowercased().contains(q)
                || (Catalog.byKey[$0.key]?.name.lowercased().contains(q) ?? false)
        }
    }

    private var list: [Language] {
        if let matches { return matches }
        let popular = Catalog.popular.compactMap { model.language($0) }
        let custom = model.s.customLanguages.values.sorted { $0.name < $1.name }
        let rest = Catalog.all.filter { !Catalog.popular.contains($0.key) }.compactMap { model.language($0.key) }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        return popular + custom + rest
    }

    private var exact: Bool { allLanguages.contains { $0.name.lowercased() == q || Catalog.byKey[$0.key]?.name.lowercased() == q } }

    private var listLabel: String {
        guard let m = matches else { return L("Popular, then all languages") }
        return m.isEmpty ? L("Not in our list — ChatGPT can still teach it") : L("Matches: %lld", m.count)
    }

    var body: some View {
        VStack(spacing: 0) {
            SetupHeader(step: addMode ? nil : 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ScreenTitle(text: addMode ? L("Add a language") : L("What do you want to learn?"))
                    Text(L("Pick as many as you like. You can study them at the same time."))
                        .font(.fig(16)).foregroundStyle(theme.muted)

                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").foregroundStyle(theme.muted)
                        TextField(L("Search any language"), text: $query)
                            .font(.fig(16))
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .onSubmit { if !q.isEmpty && !exact { add() } }
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 52)
                    .background(theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(theme.line, lineWidth: 1.5))

                    if !q.isEmpty && !exact {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(L("ChatGPT can teach “%@” — even if it's not in our list.", query.trimmingCharacters(in: .whitespaces)))
                                .font(.fig(14))
                            Button(L("Add %@", query.trimmingCharacters(in: .whitespaces)), action: add)
                                .buttonStyle(PrimaryButtonStyle(kind: .accent, height: 44))
                        }
                        .tintedNote(theme.at, theme.ad, radius: theme.radius)
                    }

                    SectionLabel(text: listLabel).padding(.top, 2)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                        ForEach(list) { l in
                            LanguageCard(language: l, selected: model.s.learning.contains(l.key)) { model.toggle(l.key) }
                        }
                    }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)

            // Bottom tray
            VStack(spacing: 10) {
                if !model.languages.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(model.languages) { l in
                                let h = theme.colors(for: l.hue)
                                Button { model.toggle(l.key) } label: {
                                    HStack(spacing: 6) {
                                        Text(l.name).font(.fig(14, .semibold))
                                        Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                                    }
                                    .foregroundStyle(h.deep)
                                    .padding(.horizontal, 12).frame(height: 34)
                                    .background(h.tint, in: Capsule())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(L("Remove %@", l.name))
                            }
                        }
                    }
                }
                Button(ctaLabel) {
                    if addMode { model.mePath.append(.addLevels) } else { model.onboardingPath.append(.levels) }
                }
                .buttonStyle(.primary)
                .disabled(model.languages.isEmpty || (addMode && newKeys.isEmpty))
            }
            .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 12)
            .background(theme.ground)
        }
        .background(theme.ground)
        .onAppear { if initialLearning.isEmpty { initialLearning = model.s.learning } }
    }

    private var newKeys: [String] { model.s.learning.filter { !initialLearning.contains($0) || model.s.plans[$0] == nil } }

    private var ctaLabel: String {
        let n = model.languages.count
        if n == 0 { return L("Pick at least one language") }
        return L("Continue with %lld (languages)", n)
    }

    private func add() {
        model.addCustom(query)
        query = ""
        Haptics.tap()
    }
}

struct LanguageCard: View {
    @Environment(\.theme) private var theme
    let language: Language
    let selected: Bool
    let action: () -> Void

    var body: some View {
        let h = theme.colors(for: language.hue)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    CodeBadge(code: language.code, hue: h, size: 38, filled: true)
                    Spacer()
                    if selected {
                        Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 22, height: 22).background(theme.a, in: Circle())
                    }
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(language.name).font(.fig(16, .semibold)).foregroundStyle(theme.text)
                    Text(language.native).font(.fig(13)).foregroundStyle(theme.muted).lineLimit(1)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(selected ? theme.a : theme.cardBorder, lineWidth: selected ? 2 : 1))
            .shadow(color: theme.isOpen ? .clear : theme.shadow.opacity(0.05), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Levels & goals (step 3 of 3)

struct LevelsView: View {
    let addMode: Bool
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme
    @State private var checking: Language?

    var body: some View {
        VStack(spacing: 0) {
            SetupHeader(step: addMode ? nil : 2)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ScreenTitle(text: L("Your level and goals"))
                    Text(L("A rough guess is fine. ChatGPT adjusts as you go."))
                        .font(.fig(16)).foregroundStyle(theme.muted)

                    ForEach(model.languages) { l in
                        let h = theme.colors(for: l.hue)
                        let lv = model.level(l.key)
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 10) {
                                CodeBadge(code: l.code, hue: h, size: 36, filled: true)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(l.name).font(.fig(16, .semibold))
                                    Text(lv.label).font(.fig(13)).foregroundStyle(theme.muted)
                                }
                            }
                            HStack(spacing: 6) {
                                ForEach(Level.allCases) { level in
                                    let on = level == lv
                                    Button {
                                        model.s.levels[l.key] = level
                                        Haptics.tap()
                                    } label: {
                                        Text(level.code).font(.fig(14, .semibold))
                                            .foregroundStyle(on ? .white : theme.text)
                                            .frame(maxWidth: .infinity, minHeight: 38)
                                            .background(on ? theme.a : theme.chip, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(Text(verbatim: "\(level.code) \(level.label)"))
                                }
                            }
                            Button { checking = l } label: {
                                Label(L("Not sure? Take a 1-minute level check"), systemImage: "checklist")
                                    .font(.fig(14, .semibold)).foregroundStyle(theme.a)
                            }
                            .buttonStyle(.plain)
                        }
                        .card()
                    }

                    SectionLabel(text: L("Goals")).padding(.top, 6)
                    FlowLayout(spacing: 8) {
                        ForEach(Catalog.goals, id: \.self) { g in
                            let on = model.s.goals.contains(g)
                            PillButton(title: L(g), bg: on ? theme.a : theme.chip, fg: on ? .white : theme.text, height: 38) {
                                if on { model.s.goals.removeAll { $0 == g } } else { model.s.goals.append(g) }
                                Haptics.tap()
                            }
                        }
                    }

                    SectionLabel(text: L("Daily time")).padding(.top, 6)
                    FlowLayout(spacing: 8) {
                        ForEach(Catalog.times, id: \.self) { t in
                            let on = model.s.dailyMinutes == t
                            PillButton(title: L("%lld min", t), bg: on ? theme.a : theme.chip, fg: on ? .white : theme.text, height: 38) {
                                model.s.dailyMinutes = t
                                Haptics.tap()
                            }
                        }
                    }
                    Text(splitNote).font(.fig(13)).foregroundStyle(theme.muted)
                }
                .padding(20)
            }
            VStack {
                Button(model.aiAvailable ? L("Build my plans with ChatGPT") : L("Build my plans"), action: build)
                    .buttonStyle(.primary)
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
        }
        .background(theme.ground)
        .sheet(item: $checking) { l in
            PlacementView(lang: l) { model.s.levels[l.key] = $0 }
        }
    }

    private var splitNote: String {
        let n = model.languages.count
        return n > 1
            ? L("About %lld min per language each day. ChatGPT balances them across the week.", Int((Double(model.s.dailyMinutes) / Double(n)).rounded()))
            : L("ChatGPT spreads this across skills through the week.")
    }

    private func build() {
        if addMode {
            model.mePath = []
            model.tab = .plan
            // Re-plan everything so the daily minutes are re-split across all languages.
            Task { await model.buildPlans() }
        } else {
            model.onboardingPath.append(.plan)
            Task { await model.buildPlans() }
        }
    }
}
