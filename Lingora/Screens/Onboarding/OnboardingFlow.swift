import SwiftUI
import AuthenticationServices

struct OnboardingFlow: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack(path: $model.onboardingPath) {
            WelcomeView()
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: OnboardingStep.self) { step in
                    Group {
                        switch step {
                        case .email(let login): EmailView(startInLogin: login)
                        case .connect: ConnectView()
                        case .languages: LanguagesView(addMode: false)
                        case .levels: LevelsView(addMode: false)
                        case .plan: PlanView(fromOnboarding: true)
                        }
                    }
                    .toolbar(.hidden, for: .navigationBar)
                }
        }
    }
}

/// Header with a back button and optional step dots.
struct SetupHeader: View {
    @Environment(\.dismiss) private var dismiss
    var step: Int? = nil
    var close = false
    var onBack: (() -> Void)? = nil

    var body: some View {
        HStack {
            BackButton(systemName: close ? "xmark" : "chevron.left") {
                if let onBack { onBack() } else { dismiss() }
            }
            Spacer()
            if let step { StepDots(current: step, total: 3) }
            Spacer()
            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }
}

// MARK: - Welcome

struct WelcomeView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme
    @State private var showChatGPT = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 9, style: .continuous).fill(theme.a).frame(width: 30, height: 30)
                            .overlay(Text("L").font(.fig(17, .bold)).foregroundStyle(.white))
                        Text("Lingora").font(.fig(20, .bold))
                    }
                    .padding(.top, 12)

                    FlowLayout(spacing: 8) {
                        ForEach(Catalog.welcomeHellos, id: \.self) { key in
                            if let l = Catalog.byKey[key] {
                                let h = theme.colors(for: l.hue)
                                Text(l.hello)
                                    .font(.fig(15, .semibold))
                                    .foregroundStyle(h.deep)
                                    .padding(.horizontal, 14).frame(height: 38)
                                    .background(h.tint, in: Capsule())
                            }
                        }
                    }
                    .padding(.top, 18)

                    Text("Learn any language, at your own pace.")
                        .font(.fig(38, .bold, relativeTo: .largeTitle))
                        .tracking(-0.76)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("ChatGPT plans your week, adapts it every day and practises with you. Learn with friends, on every device.")
                        .font(.fig(16))
                        .foregroundStyle(theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
            }
            .scrollBounceBehavior(.basedOnSize)

            VStack(spacing: 10) {
                Button { showChatGPT = true } label: {
                    Label("Continue with ChatGPT", systemImage: "sparkles")
                }
                .buttonStyle(.primary)

                SignInWithAppleButton(.continue) { req in
                    req.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    model.signInWithApple(result)
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                Button { model.onboardingPath.append(.email(login: false)) } label: {
                    Label("Continue with email", systemImage: "envelope")
                }
                .buttonStyle(PrimaryButtonStyle(kind: .chip))

                HStack(spacing: 4) {
                    Text("Have an account?").foregroundStyle(theme.muted)
                    Button("Log in") { model.onboardingPath.append(.email(login: true)) }
                        .font(.fig(15, .semibold))
                        .foregroundStyle(theme.ad)
                }
                .font(.fig(15))
                .padding(.top, 6)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .background(theme.ground)
        .sheet(isPresented: $showChatGPT) {
            ChatGPTSheet(mode: .signIn)
        }
    }
}

// MARK: - Email

struct EmailView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme
    @State var startInLogin: Bool
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var errors: [String: String] = [:]
    @State private var showChatGPT = false

    private var signup: Bool { !startInLogin }

    var body: some View {
        VStack(spacing: 0) {
            SetupHeader()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ScreenTitle(text: signup ? "Create your account" : "Welcome back")
                        .padding(.bottom, 4)
                    if signup {
                        LingoraField(label: "Name", text: $name, contentType: .name, error: errors["name"])
                    }
                    LingoraField(label: "Email", text: $email, keyboard: .emailAddress, contentType: .emailAddress, error: errors["email"])
                    LingoraField(label: "Password", text: $password, secure: true,
                                 contentType: signup ? .newPassword : .password, error: errors["password"])

                    Button(signup ? "Create account" : "Log in", action: submit)
                        .buttonStyle(.primary)
                        .padding(.top, 6)

                    HStack(spacing: 4) {
                        Text(signup ? "Already have an account?" : "New here?").foregroundStyle(theme.muted)
                        Button(signup ? "Log in" : "Create account") {
                            withAnimation { startInLogin.toggle(); errors = [:] }
                        }
                        .font(.fig(15, .semibold)).foregroundStyle(theme.ad)
                    }
                    .frame(maxWidth: .infinity)

                    HStack(spacing: 12) {
                        Rectangle().fill(theme.line).frame(height: 1)
                        Text("or").font(.fig(13)).foregroundStyle(theme.muted)
                        Rectangle().fill(theme.line).frame(height: 1)
                    }
                    .padding(.vertical, 4)

                    Button { showChatGPT = true } label: { Label("Continue with ChatGPT", systemImage: "sparkles") }
                        .buttonStyle(.secondary)
                    SignInWithAppleButton(.continue) { req in
                        req.requestedScopes = [.fullName, .email]
                    } onCompletion: { model.signInWithApple($0) }
                        .signInWithAppleButtonStyle(.black)
                        .frame(height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .padding(20)
            }
        }
        .background(theme.ground)
        .sheet(isPresented: $showChatGPT) { ChatGPTSheet(mode: .signIn) }
    }

    private func submit() {
        var e: [String: String] = [:]
        if signup && name.trimmingCharacters(in: .whitespaces).isEmpty { e["name"] = "Please add your name" }
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        if trimmed.range(of: "^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$", options: .regularExpression) == nil {
            e["email"] = "That email doesn’t look right"
        }
        if password.count < 8 { e["password"] = "Use at least 8 characters" }
        withAnimation { errors = e }
        guard e.isEmpty else { return }
        model.signInWithEmail(name: name, email: trimmed, login: !signup)
    }
}

// MARK: - Connect ChatGPT (step 1 of 3)

struct ConnectView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme
    @State private var showSheet = false

    private let points = [
        ("A weekly plan for each language", "ChatGPT shapes a calm week around your goals and time."),
        ("Tasks that adapt every day", "Found something tricky? Tomorrow gets a short review."),
        ("A patient tutor in any language", "Roleplay real moments, with gentle corrections.")
    ]

    var body: some View {
        VStack(spacing: 0) {
            SetupHeader(step: 0)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ScreenTitle(text: "Connect ChatGPT")
                    Text("Lingora uses ChatGPT to plan, adapt and practise with you.")
                        .font(.fig(16)).foregroundStyle(theme.muted)
                        .padding(.bottom, 4)
                    ForEach(Array(points.enumerated()), id: \.offset) { i, p in
                        HStack(alignment: .top, spacing: 14) {
                            Text("\(i + 1)").font(.fig(15, .bold)).foregroundStyle(theme.ad)
                                .frame(width: 32, height: 32).background(theme.at, in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.0).font(.fig(16, .semibold))
                                Text(p.1).font(.fig(14)).foregroundStyle(theme.muted)
                            }
                        }
                        .card()
                    }
                    Label("Lingora only sees what you do in Lingora. It never reads your other chats.", systemImage: "lock")
                        .font(.fig(13)).foregroundStyle(theme.muted)
                        .padding(.top, 4)

                    if model.connected {
                        Label("ChatGPT connected", systemImage: "checkmark.circle.fill")
                            .font(.fig(14, .semibold))
                            .tintedNote(theme.at, theme.ad, radius: theme.radius)
                    }
                }
                .padding(20)
            }
            VStack(spacing: 10) {
                if model.connected {
                    Button("Continue") { model.onboardingPath.append(.languages) }.buttonStyle(.primary)
                } else {
                    Button { showSheet = true } label: { Label("Connect ChatGPT account", systemImage: "sparkles") }
                        .buttonStyle(.primary)
                    Button("Skip for now") { model.onboardingPath.append(.languages) }
                        .buttonStyle(.secondary)
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 12)
        }
        .background(theme.ground)
        .sheet(isPresented: $showSheet) { ChatGPTSheet(mode: .connect) }
    }
}
