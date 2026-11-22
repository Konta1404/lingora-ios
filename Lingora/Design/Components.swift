import SwiftUI
import UIKit

// MARK: - Card

struct CardModifier: ViewModifier {
    @Environment(\.theme) private var theme
    var padding: CGFloat? = 16
    var radius: CGFloat?

    func body(content: Content) -> some View {
        let r = radius ?? theme.radius
        content
            .padding(padding ?? 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.card, in: RoundedRectangle(cornerRadius: r, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: r, style: .continuous).strokeBorder(theme.cardBorder, lineWidth: 1))
            .shadow(color: theme.isOpen ? .clear : theme.shadow.opacity(0.04), radius: 1, y: 1)
            .shadow(color: theme.isOpen ? .clear : theme.shadow.opacity(0.05), radius: 10, y: 6)
    }
}

extension View {
    func card(padding: CGFloat? = 16, radius: CGFloat? = nil) -> some View {
        modifier(CardModifier(padding: padding, radius: radius))
    }

    /// Tinted note block (accent tint background, deep text).
    func tintedNote(_ bg: Color, _ fg: Color, radius: CGFloat) -> some View {
        self.font(.fig(14))
            .foregroundStyle(fg)
            .padding(.vertical, 14).padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(bg, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    enum Kind { case accent, dark, chip, white }
    var kind: Kind = .accent
    var height: CGFloat = 54

    func makeBody(configuration: Configuration) -> some View {
        let (bg, fg): (Color, Color) = {
            switch kind {
            case .accent: return (configuration.isPressed ? theme.ad : theme.a, .white)
            case .dark: return (theme.text, theme.onDark)
            case .chip: return (configuration.isPressed ? theme.chip2 : theme.chip, theme.text)
            case .white: return (configuration.isPressed ? theme.chip : theme.paper, theme.text)
            }
        }()
        configuration.label
            .font(.fig(16, .semibold))
            .foregroundStyle(fg)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(bg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(kind == .white ? theme.line : .clear, lineWidth: 1.5))
            .opacity(isEnabled ? 1 : 0.5)
            .contentShape(Rectangle())
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
    static var dark: PrimaryButtonStyle { PrimaryButtonStyle(kind: .dark) }
    static var secondary: PrimaryButtonStyle { PrimaryButtonStyle(kind: .chip, height: 52) }
}

/// Round pill button (chips, small actions).
struct PillButton: View {
    let title: String
    var icon: String? = nil
    var bg: Color
    var fg: Color
    var height: CGFloat = 36
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon).font(.system(size: 13, weight: .semibold)) }
                Text(title).font(.fig(14, .semibold))
            }
            .padding(.horizontal, 14)
            .frame(minHeight: height)
            .foregroundStyle(fg)
            .background(bg, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct CircleIconButton: View {
    @Environment(\.theme) private var theme
    let systemName: String
    var size: CGFloat = 40
    var bg: Color? = nil
    var fg: Color? = nil
    var label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(fg ?? theme.text)
                .frame(width: size, height: size)
                .background(bg ?? theme.chip, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct BackButton: View {
    var systemName = "chevron.backward"
    var action: () -> Void
    var body: some View {
        CircleIconButton(systemName: systemName, label: systemName == "xmark" ? L("Close") : L("Back"), action: action)
    }
}

// MARK: - Badges & avatars

struct CodeBadge: View {
    let code: String
    let hue: Hue
    var size: CGFloat = 36
    var filled = false

    var body: some View {
        Text(code)
            .font(.fig(max(9, size * 0.33), .bold))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(filled ? .white : hue.deep)
            .frame(width: size, height: size)
            .background(filled ? hue.base : hue.tint, in: Circle())
    }
}

struct Avatar: View {
    let initial: String
    let hue: Hue
    var size: CGFloat = 40
    var ring: Color? = nil
    /// Profile photo: the person's uid and photo version (0 = no photo → initial).
    var uid: String? = nil
    var photo: Int = 0
    @ObservedObject private var store = AvatarStore.shared

    var body: some View {
        let image = uid.flatMap { photo > 0 ? store.image(uid: $0, version: photo) : nil }
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Text(initial)
                    .font(.fig(size * 0.4, .bold))
                    .foregroundStyle(hue.deep)
            }
        }
        .frame(width: size, height: size)
        .background(hue.tint)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(ring ?? .clear, lineWidth: 2))
        .task(id: "\(uid ?? "")-\(photo)") {
            if let uid, photo > 0 { await store.load(uid: uid, version: photo) }
        }
    }
}

// MARK: - Progress, dots, titles

struct ProgressBar: View {
    @Environment(\.theme) private var theme
    var value: Double
    var color: Color? = nil
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.chip)
                Capsule().fill(color ?? theme.a)
                    .frame(width: max(0, min(1, value)) * geo.size.width)
            }
        }
        .frame(height: height)
        .animation(.easeInOut(duration: 0.45), value: value)
    }
}

struct StepDots: View {
    @Environment(\.theme) private var theme
    let current: Int
    let total: Int
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(i == current ? theme.a : theme.chip2)
                    .frame(width: i == current ? 22 : 6, height: 6)
            }
        }
        .accessibilityLabel(L("Step %lld of %lld", current + 1, total))
    }
}

struct ScreenTitle: View {
    @Environment(\.theme) private var theme
    let text: String
    var body: some View {
        Text(text)
            .font(.fig(theme.titleSize, .bold, relativeTo: .largeTitle))
            .tracking(-0.02 * theme.titleSize)
            .foregroundStyle(theme.text)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct SectionLabel: View {
    @Environment(\.theme) private var theme
    let text: String
    var body: some View {
        Text(text).font(.fig(13, .semibold)).foregroundStyle(theme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Inputs

struct LingoraField: View {
    @Environment(\.theme) private var theme
    let label: String
    @Binding var text: String
    var secure = false
    var keyboard: UIKeyboardType = .default
    var contentType: UITextContentType? = nil
    var error: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.fig(13, .semibold)).foregroundStyle(theme.muted)
            Group {
                if secure {
                    SecureField("", text: $text)
                } else {
                    TextField("", text: $text)
                        .keyboardType(keyboard)
                }
            }
            .textContentType(contentType)
            .textInputAutocapitalization(keyboard == .emailAddress || secure ? .never : .words)
            .autocorrectionDisabled(keyboard == .emailAddress || secure)
            .font(.fig(16))
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(error == nil ? theme.line : theme.errorBorder, lineWidth: 1.5))
            if let error {
                Text(error).font(.fig(13)).foregroundStyle(theme.errorText)
            }
        }
    }
}

struct LingoraSwitch: View {
    @Environment(\.theme) private var theme
    @Binding var isOn: Bool
    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { isOn.toggle() }
            Haptics.tap()
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? theme.a : theme.chip2).frame(width: 50, height: 30)
                Circle().fill(.white).frame(width: 24, height: 24)
                    .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                    .padding(3)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isOn ? L("On") : L("Off"))
    }
}

// MARK: - Chat bits

struct TypingIndicator: View {
    @Environment(\.theme) private var theme
    let label: String
    @State private var phase = 0.0
    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(0..<3) { i in
                    Circle().fill(theme.muted).frame(width: 6, height: 6)
                        .opacity(0.35 + 0.65 * max(0, sin(phase + Double(i) * 0.9)))
                }
            }
            Text(label).font(.fig(13)).foregroundStyle(theme.muted)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(theme.card, in: UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 6, bottomTrailingRadius: 20, topTrailingRadius: 20))
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { phase = .pi * 2 } }
    }
}

struct CorrectionBubble: View {
    @Environment(\.theme) private var theme
    let wrong: String
    let right: String
    let note: String
    var header: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let header {
                Label(header, systemImage: "lock.fill")
                    .font(.fig(12, .semibold))
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(wrong).strikethrough().opacity(0.7)
                Image(systemName: "arrow.forward").font(.system(size: 11, weight: .bold))
                Text(right).font(.fig(15, .bold))
            }
            .font(.fig(15))
            Text(note).font(.fig(13))
        }
        .foregroundStyle(theme.ad)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(theme.at, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .frame(maxWidth: 300, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

/// Hold to record, release to stop (like a voice message).
struct HoldToTalkButton: View {
    @Environment(\.theme) private var theme
    @ObservedObject var dictation: Dictation
    var onPress: () -> Void
    @State private var holding = false

    var body: some View {
        let on = holding || dictation.isRecording
        Image(systemName: on ? "waveform" : "mic")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(on ? .white : theme.text)
            .symbolEffect(.variableColor.iterative, isActive: dictation.isRecording)
            .frame(width: 48, height: 48)
            .background(on ? theme.a : theme.chip, in: Circle())
            .scaleEffect(holding ? 1.15 : 1)
            .animation(.spring(duration: 0.25), value: holding)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !holding else { return }
                        holding = true
                        onPress()
                    }
                    .onEnded { _ in
                        holding = false
                        dictation.release()
                    }
            )
            .accessibilityLabel(L("Hold to talk"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { if dictation.isRecording { dictation.release() } else { onPress() } }
    }
}

/// Mic · text field · send — 48pt each.
struct ChatInputBar: View {
    @Environment(\.theme) private var theme
    @Binding var text: String
    let placeholder: String
    var disabled = false
    /// Lingora language key to dictate in (nil → the iPhone's language).
    var speechLanguage: String? = nil
    var onSend: () -> Void
    @FocusState private var focused: Bool
    @StateObject private var dictation = Dictation()

    var body: some View {
        HStack(spacing: 8) {
            HoldToTalkButton(dictation: dictation) {
                // Each recording replaces what was in the field.
                text = ""
                dictation.press(language: speechLanguage) { text = $0 }
            }
            TextField(placeholder, text: $text)
                .font(.fig(15))
                .focused($focused)
                .submitLabel(.send)
                .onSubmit(onSend)
                .padding(.horizontal, 18)
                .frame(height: 48)
                .background(theme.card, in: Capsule())
                .overlay(Capsule().strokeBorder(theme.line, lineWidth: 1))
            CircleIconButton(systemName: "paperplane.fill", size: 48, bg: theme.a, fg: .white, label: L("Send")) {
                dictation.stop()
                onSend()
            }
                .disabled(disabled || text.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(disabled || text.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
        .background(theme.ground)
        .overlay(alignment: .top) {
            if let err = dictation.error {
                Text(err).font(.fig(12)).foregroundStyle(theme.muted).padding(.horizontal, 20).offset(y: -14)
                    .onTapGesture { dictation.error = nil }
            }
        }
        .onDisappear { dictation.stop() }
    }
}

// MARK: - Layout

/// Simple wrapping layout for chips and pills.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > maxW { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing
            rowH = max(rowH, s.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}

// MARK: - Haptics

enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    /// Recording started: one firm tap.
    static func recordStart() { UIImpactFeedbackGenerator(style: .heavy).impactOccurred(intensity: 1) }
    /// Recording stopped: two soft taps, so it feels different from the start.
    static func recordStop() {
        let g = UIImpactFeedbackGenerator(style: .medium)
        g.impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { g.impactOccurred(intensity: 0.7) }
    }
}

// MARK: - Swipe-back with hidden navigation bars

extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}
