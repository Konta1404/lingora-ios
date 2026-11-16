import SwiftUI

/// ChatGPT sign-in / connect sheet.
/// "Sign in with ChatGPT" is a limited OpenAI preview, so this build connects with an OpenAI API key instead.
struct ChatGPTSheet: View {
    enum Mode { case signIn, connect }
    let mode: Mode

    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var key = ""
    @State private var busy = false
    @State private var error: String?

    private var items: [String] {
        mode == .signIn
            ? ["Create and update learning plans", "Adapt tasks from your results", "Be your conversation tutor"]
            : ["Create and update learning plans", "Adapt tasks from your results", "Be your conversation tutor", "It never reads your other chats"]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Capsule().fill(theme.chip2).frame(width: 40, height: 5).frame(maxWidth: .infinity).padding(.top, 8)

                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(theme.ad)
                        .frame(width: 52, height: 52)
                        .background(theme.at, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ChatGPT").font(.fig(13, .semibold)).foregroundStyle(theme.muted)
                        Text(mode == .signIn ? "Sign in to Lingora" : "Allow Lingora access?").font(.fig(22, .bold))
                    }
                }

                Text(mode == .signIn ? "Use ChatGPT to power your study plans." : "Lingora will be able to:")
                    .font(.fig(15)).foregroundStyle(theme.muted)

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(items, id: \.self) { item in
                        Label {
                            Text(item).font(.fig(15))
                        } icon: {
                            Image(systemName: "checkmark").font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white).frame(width: 22, height: 22).background(theme.a, in: Circle())
                        }
                    }
                }
                .card()

                if mode == .signIn {
                    LingoraField(label: "Your name", text: $name, contentType: .name)
                }
                LingoraField(label: "OpenAI API key", text: $key, secure: true, error: error)
                Text("Sign in with ChatGPT is in limited preview, so this build connects with your OpenAI API key. It stays in your iPhone's Keychain. Create one at platform.openai.com.")
                    .font(.fig(13)).foregroundStyle(theme.muted)

                HStack(spacing: 10) {
                    Button("Cancel") { dismiss() }
                        .buttonStyle(.secondary)
                    Button(busy ? "Connecting…" : (mode == .signIn ? "Continue" : "Allow"), action: submit)
                        .buttonStyle(.primary)
                        .disabled(busy || key.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .background(theme.ground)
        .presentationDetents([.large])
        .presentationCornerRadius(28)
        .interactiveDismissDisabled(busy)
    }

    private func submit() {
        busy = true
        error = nil
        Task {
            do {
                if mode == .signIn {
                    try await model.signInWithChatGPT(name: name, key: key)
                } else {
                    try await model.connect(key: key)
                }
                try? await Task.sleep(for: .milliseconds(300))
                Haptics.success()
                dismiss()
            } catch {
                self.error = (error as? OpenAIService.AIError)?.errorDescription ?? error.localizedDescription
            }
            busy = false
        }
    }
}
