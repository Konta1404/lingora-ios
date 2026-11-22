import SwiftUI
import GoogleSignIn
import UserNotifications

@main
struct LingoraApp: App {
    @StateObject private var model: AppModel

    init() {
        FontRegistrar.registerAll()
        Backend.configure()
        UNUserNotificationCenter.current().delegate = NotificationRouter.shared
        MessageAlerts.registerBackgroundRefresh()
        _model = StateObject(wrappedValue: AppModel())
    }
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var router = NotificationRouter.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environment(\.theme, model.theme)
                .tint(model.theme.a)
                .preferredColorScheme(model.s.settings.appearance.scheme)
                .onOpenURL { url in if !model.handle(url: url) { _ = GIDSignIn.sharedInstance.handle(url) } }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background { MessageAlerts.scheduleBackgroundRefresh() }
                    if phase == .active {
                        model.maintainStreak()
                        Task { await model.pollSocial() }
                    }
                }
                .onChange(of: router.openFriend) { _, friend in
                    guard let friend else { return }
                    model.tab = .friends
                    model.friendsPath = friend.isEmpty ? [] : [friend]
                    router.openFriend = nil
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack(alignment: .top) {
            theme.ground.ignoresSafeArea()
            Group {
                if model.s.user != nil && model.s.onboarded {
                    MainTabView()
                } else {
                    OnboardingFlow()
                }
            }
            .transition(.opacity)
            // iPad: keep a comfortable reading width instead of stretching phone layouts edge to edge.
            .frame(maxWidth: UIDevice.current.userInterfaceIdiom == .pad ? 720 : .infinity)
            .frame(maxWidth: .infinity)
            if let c = model.celebration {
                CelebrationView(c: c)
                    .transition(.opacity)
                    .zIndex(2)
            }
            if let toast = model.toast {
                ToastView(text: toast)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: toast) {
                        try? await Task.sleep(for: .seconds(3.2))
                        withAnimation { model.toast = nil }
                    }
            }
        }
        .defersSystemGestures(on: model.chatOnScreen ? .bottom : [])
        .font(.fig(15))
        .foregroundStyle(theme.text)
        .animation(.easeInOut(duration: 0.25), value: model.s.onboarded)
        .animation(.easeInOut(duration: 0.25), value: model.toast)
    }
}

struct ToastView: View {
    @Environment(\.theme) private var theme
    let text: String
    var body: some View {
        Text(text)
            .font(.fig(14, .medium))
            .foregroundStyle(theme.onDark)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(theme.text, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .accessibilityAddTraits(.isStaticText)
    }
}

struct MainTabView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        TabView(selection: $model.tab) {
            NavigationStack { TodayView().toolbar(.hidden, for: .navigationBar) }
                .tabItem { Label(L("Today"), systemImage: "house") }
                .tag(AppTab.today)
            NavigationStack { PlanView(fromOnboarding: false).toolbar(.hidden, for: .navigationBar) }
                .tabItem { Label(L("Plan"), systemImage: "calendar") }
                .tag(AppTab.plan)
            NavigationStack { TutorView().toolbar(.hidden, for: .navigationBar) }
                .tabItem { Label(L("Tutor"), systemImage: "bubble.left") }
                .tag(AppTab.tutor)
            NavigationStack(path: $model.friendsPath) {
                FriendsView()
                    .toolbar(.hidden, for: .navigationBar)
                    .navigationDestination(for: String.self) { id in
                        FriendChatView(friendID: id)
                            .toolbar(.hidden, for: .navigationBar)
                            .toolbar(.hidden, for: .tabBar)
                    }
            }
            .tabItem { Label(L("Friends"), systemImage: "person.2") }
            .badge(model.friendsBadge)
            .tag(AppTab.friends)
            NavigationStack(path: $model.mePath) {
                MeView()
                    .toolbar(.hidden, for: .navigationBar)
                    .navigationDestination(for: MeRoute.self) { route in
                        Group {
                            switch route {
                            case .addLanguage: LanguagesView(addMode: true)
                            case .addLevels: LevelsView(addMode: true)
                            case .friends: FriendsListView()
                            }
                        }
                        .toolbar(.hidden, for: .navigationBar)
                        .toolbar(.hidden, for: .tabBar)
                    }
            }
            .tabItem { Label(L("Me"), systemImage: "person") }
            .tag(AppTab.me)
        }
        .fullScreenCover(item: $model.lessonTask) { task in
            LessonView(task: task)
                .environmentObject(model)
                .environment(\.theme, model.theme)
        }
        .fullScreenCover(item: Binding(get: { model.courseLang.map(CourseLangID.init) }, set: { model.courseLang = $0?.id })) { c in
            CourseMapView(lang: c.id)
                .environmentObject(model)
                .environment(\.theme, model.theme)
        }
        .fullScreenCover(isPresented: $model.showWords) {
            WordsView()
                .environmentObject(model)
                .environment(\.theme, model.theme)
        }
        .sheet(item: Binding(get: { model.profileUID.map(CourseLangID.init) }, set: { model.profileUID = $0?.id })) { p in
            ProfileView(uid: p.id)
                .environmentObject(model)
                .environment(\.theme, model.theme)
                .presentationDetents([.large])
                .presentationCornerRadius(28)
        }
        .sheet(isPresented: $model.showAddFriend) {
            AddFriendsSheet()
                .environmentObject(model)
                .environment(\.theme, model.theme)
                .presentationDetents([.large])
                .presentationCornerRadius(28)
        }
        .task { await model.adaptTodayIfNeeded() }
        .task {
            // Check for new messages, requests and nudges while the app is open.
            while !Task.isCancelled {
                await model.pollSocial()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }
}

private struct CourseLangID: Identifiable { let id: String }
