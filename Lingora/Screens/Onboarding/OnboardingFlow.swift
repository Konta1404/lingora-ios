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
            BackButton(systemName: close ? "xmark" : "chevron.backward") {
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

/// Apple · Google · OpenAI sign-in buttons, shared by Welcome and Email.
struct SocialSignInButtons: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme
    var compact = false

    var body: some View {
        VStack(spacing: 10) {
            Button { model.signInWithOpenAI() } label: {
                Label(L("Continue with OpenAI"), systemImage: "sparkles")
            }
            .buttonStyle(PrimaryButtonStyle(kind: compact ? .chip : .accent, height: compact ? 52 : 54))
            .disabled(!Backend.isConfigured || Backend.usesEmulators)

            SignInWithAppleButton(.continue) { req in
                AuthService.shared.prepare(req)
            } onCompletion: { result in
                model.signInWithApple(result)
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: compact ? 52 : 54)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            Button { model.signInWithGoogle() } label: {
                HStack(spacing: 10) {
                    Text("G").font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(LinearGradient(colors: [Color(hex: 0x4285F4), Color(hex: 0x34A853), Color(hex: 0xFBBC05), Color(hex: 0xEA4335)],
                                                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    Text(L("Continue with Google"))
                }
            }
            .buttonStyle(PrimaryButtonStyle(kind: .white, height: compact ? 52 : 54))
            .disabled(!Backend.isConfigured || Backend.usesEmulators)
        }
        .disabled(model.authBusy)
        .overlay { if model.authBusy { ProgressView().tint(theme.a) } }
    }
}

// MARK: - Welcome

struct WelcomeView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 9, style: .continuous).fill(theme.a).frame(width: 30, height: 30)
                            .overlay(Text(verbatim: "L").font(.fig(17, .bold)).foregroundStyle(.white))
                        Text(verbatim: "Lingora").font(.fig(20, .bold))
                    }
                    .padding(.top, 12)

                    FlowLayout(spacing: 8) {
                        ForEach(Catalog.welcomeHellos, id: \.self) { key in
                            if let l = Catalog.byKey[key] {
                                let h = theme.colors(for: l.hue)
                                Text(verbatim: l.hello)
                                    .font(.fig(15, .semibold))
                                    .foregroundStyle(h.deep)
                                    .padding(.horizontal, 14).frame(height: 38)
                                    .background(h.tint, in: Capsule())
                            }
                        }
                    }
                    .padding(.top, 18)

                    Text(L("Learn any language, at your own pace."))
                        .font(.fig(38, .bold, relativeTo: .largeTitle))
                        .tracking(-0.76)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(L("ChatGPT plans your week, adapts it every day and practises with you. Learn with friends, on every device."))
                        .font(.fig(16))
                        .foregroundStyle(theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    if !Backend.isConfigured {
                        Text(L("Offline mode: add GoogleService-Info.plist to turn on accounts and ChatGPT."))
                            .font(.fig(13)).foregroundStyle(theme.muted)
                    } else if Backend.usesEmulators {
                        Text(L("Local test server: sign up with email."))
                            .font(.fig(13)).foregroundStyle(theme.muted)
                    }
                }
                .padding(.horizontal, 20)
            }
            .scrollBounceBehavior(.basedOnSize)

            VStack(spacing: 10) {
                SocialSignInButtons()

                Button { model.onboardingPath.append(.email(login: false)) } label: {
                    Label(L("Continue with email"), systemImage: "envelope")
                }
                .buttonStyle(PrimaryButtonStyle(kind: .chip))

                HStack(spacing: 4) {
                    Text(L("Have an account?")).foregroundStyle(theme.muted)
                    Button(L("Log in")) { model.onboardingPath.append(.email(login: true)) }
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
    @State private var formError: String?

    private var signup: Bool { !startInLogin }

    var body: some View {
        VStack(spacing: 0) {
            SetupHeader()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ScreenTitle(text: signup ? L("Create your account") : L("Welcome back"))
                        .padding(.bottom, 4)
                    if signup {
                        LingoraField(label: L("Name"), text: $name, contentType: .name, error: errors["name"])
                    }
                    LingoraField(label: L("Email"), text: $email, keyboard: .emailAddress, contentType: .emailAddress, error: errors["email"])
                    LingoraField(label: L("Password"), text: $password, secure: true,
                                 contentType: signup ? .newPassword : .password, error: errors["password"])
                    if let formError {
                        Text(formError).font(.fig(14)).foregroundStyle(theme.errorText)
                    }

                    Button(model.authBusy ? L("One moment…") : (signup ? L("Create account") : L("Log in")), action: submit)
                        .buttonStyle(.primary)
                        .disabled(model.authBusy)
                        .padding(.top, 6)

                    if !signup && Backend.isConfigured {
                        Button(L("Forgot password?")) {
                            Task {
                                do {
                                    try await AuthService.shared.sendPasswordReset(to: email.trimmingCharacters(in: .whitespaces))
                                    model.toast = L("Check your inbox for a reset link.")
                                } catch {
                                    formError = AuthService.message(for: error)
                                }
                            }
                        }
                        .font(.fig(14, .semibold)).foregroundStyle(theme.ad)
                        .frame(maxWidth: .infinity)
                    }

                    HStack(spacing: 4) {
                        Text(signup ? L("Already have an account?") : L("New here?")).foregroundStyle(theme.muted)
                        Button(signup ? L("Log in") : L("Create account")) {
                            withAnimation { startInLogin.toggle(); errors = [:]; formError = nil }
                        }
                        .font(.fig(15, .semibold)).foregroundStyle(theme.ad)
                    }
                    .frame(maxWidth: .infinity)

                    HStack(spacing: 12) {
                        Rectangle().fill(theme.line).frame(height: 1)
                        Text(L("or")).font(.fig(13)).foregroundStyle(theme.muted)
                        Rectangle().fill(theme.line).frame(height: 1)
                    }
                    .padding(.vertical, 4)

                    SocialSignInButtons(compact: true)
                }
                .padding(20)
            }
        }
        .background(theme.ground)
    }

    private func submit() {
        var e: [String: String] = [:]
        if signup && name.trimmingCharacters(in: .whitespaces).isEmpty { e["name"] = L("Please add your name") }
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        if trimmed.range(of: "^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$", options: .regularExpression) == nil {
            e["email"] = L("That email doesn’t look right")
        }
        if password.count < 8 { e["password"] = L("Use at least 8 characters") }
        withAnimation { errors = e; formError = nil }
        guard e.isEmpty else { return }
        Task {
            if let err = await model.signInWithEmail(name: name, email: trimmed, password: password, createAccount: signup) {
                withAnimation { formError = err }
            }
        }
    }
}
