import SwiftUI
import Translation

/// A chat message. Tap it to translate it into the iPhone's language (Apple Translation, on device);
/// tap again to hide the translation.
struct ChatBubble: View {
    @Environment(\.theme) private var theme
    let text: String
    let mine: Bool
    var translatable = true
    /// Language key to read the message in (nil = no Listen option).
    var speakLang: String? = nil

    @State private var showTranslation = false
    @State private var translated: String?
    @State private var failed = false
    @State private var sheet = false
    @State private var config: AnyObject?   // TranslationSession.Configuration on iOS 18

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: mine ? 20 : 6,
                               bottomTrailingRadius: mine ? 6 : 20, topTrailingRadius: 20)
    }

    var body: some View {
        VStack(alignment: mine ? .trailing : .leading, spacing: 4) {
            VStack(alignment: .leading, spacing: 6) {
                Text(text)
                    .font(.fig(15))
                    .foregroundStyle(mine ? .white : theme.text)
                if showTranslation {
                    Rectangle().fill(mine ? Color.white.opacity(0.35) : theme.line).frame(height: 1)
                    Group {
                        if let translated {
                            Text(translated)
                        } else if failed {
                            Text(L("Couldn't translate this message."))
                        } else {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.mini)
                                Text(L("Translating…"))
                            }
                        }
                    }
                    .font(.fig(14))
                    .foregroundStyle(mine ? Color.white.opacity(0.9) : theme.muted)
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(mine ? theme.a : theme.card, in: shape)
            .overlay(shape.strokeBorder(mine ? .clear : theme.cardBorder, lineWidth: 1))
            .contentShape(shape)
            .onTapGesture { if translatable { toggle() } }
            .contextMenu {
                if let speakLang {
                    Button { Speaker.shared.say(text, lang: speakLang) } label: { Label(L("Listen"), systemImage: "speaker.wave.2") }
                }
                Button { UIPasteboard.general.string = text } label: { Label(L("Copy"), systemImage: "doc.on.doc") }
                if translatable {
                    Button { toggle() } label: {
                        Label(showTranslation ? L("Hide translation") : L("Translate"), systemImage: "translate")
                    }
                }
            }
            .accessibilityHint(translatable ? L("Double-tap to translate") : "")
        }
        .frame(maxWidth: 300, alignment: mine ? .trailing : .leading)
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
        .modifier(TranslationHook(text: text, config: $config, translated: $translated, failed: $failed, sheet: $sheet))
    }

    private func toggle() {
        Haptics.tap()
        if #available(iOS 18.0, *) {
            withAnimation(.easeInOut(duration: 0.2)) { showTranslation.toggle() }
            if showTranslation && translated == nil {
                failed = false
                if let c = config as? TranslationSession.Configuration {
                    var c = c
                    c.invalidate()
                    config = c as AnyObject
                } else {
                    config = TranslationSession.Configuration(source: nil, target: Locale.current.language) as AnyObject
                }
            }
        } else {
            sheet = true   // iOS 17.4+: Apple's translation sheet
        }
    }
}

/// Wires the Translation framework to the bubble (inline on iOS 18, system sheet on iOS 17.4).
private struct TranslationHook: ViewModifier {
    let text: String
    @Binding var config: AnyObject?
    @Binding var translated: String?
    @Binding var failed: Bool
    @Binding var sheet: Bool

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.translationTask(config as? TranslationSession.Configuration) { session in
                do {
                    let r = try await session.translate(text)
                    await MainActor.run { translated = r.targetText }
                } catch {
                    await MainActor.run { failed = true }
                }
            }
        } else if #available(iOS 17.4, *) {
            content.translationPresentation(isPresented: $sheet, text: text)
        } else {
            content
        }
    }
}
