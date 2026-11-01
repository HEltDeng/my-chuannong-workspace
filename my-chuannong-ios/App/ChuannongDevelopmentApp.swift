import SwiftUI

@main
struct ChuannongDevelopmentApp: App {
    @UIApplicationDelegateAdaptor(NotificationDelegate.self) private var notificationDelegate
    @State private var platform = PlatformSession(loadSaved: !Self.isReview)
    @State private var school = SchoolSession(loadSaved: !Self.isReview)
    @State private var configuration=ProductConfiguration()
    private static var isReview: Bool {
        #if DEBUG && targetEnvironment(simulator)
        ProcessInfo.processInfo.environment["MYCHUANNONG_PRIVACY_REVIEW"] == "1" || ProcessInfo.processInfo.environment["MYCHUANNONG_PHONE_REVIEW"] != nil
        #else
        false
        #endif
    }
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if let mode=ProcessInfo.processInfo.environment["MYCHUANNONG_PHONE_REVIEW"],let flow=PhoneAccountMode(rawValue:mode) {
                NavigationStack { PlatformLoginView(initialMode:flow) }.environment(platform).tint(ChuannongTheme.green)
            }
            else if Self.isReview { PrivacyReviewPreview() }
            else { RootView().environment(platform).environment(school).environment(configuration).tint(ChuannongTheme.green) }
            #else
            RootView().environment(platform).environment(school).environment(configuration).tint(ChuannongTheme.green)
            #endif
        }
    }
}


struct RootView: View {
    @Environment(PlatformSession.self) private var platform
    @Environment(SchoolSession.self) private var school
    @Environment(ProductConfiguration.self) private var configuration
    @AppStorage(PrivacyConsent.storageKey) private var consent = false
    @State private var tab = 0
    @State private var foreground=ForegroundServices()
    @State private var studentReporter=StudentSessionReporter()
    @State private var deepLink:String?
    @State private var followRevision=0
    @Environment(\.scenePhase) private var phase
    var body: some View {
        Group {
            if consent {
                TabView(selection: $tab) {
                    NavigationStack { HomeView() }.tabItem { Label("首页", systemImage: "house") }.tag(0)
                    NavigationStack { ServicesView(isActive: tab == 1, allowsNetwork: consent).navigationTitle("服务").navigationBarTitleDisplayMode(.inline) }
                        .tabItem { Label("服务", systemImage: "square.grid.2x2") }.tag(1)
                    NavigationStack { ProfileView() }.tabItem { Label("我的", systemImage: "person.crop.circle") }.tag(2)
                }
            } else { WelcomeView() }
        }
        .task(id: consent) { if consent { await school.restore() } }
        .task(id:"initial-school-\(phase)-\(consent)-\(school.identity?.studentID ?? "")-\(school.identity?.verifiedAt.timeIntervalSince1970 ?? 0)") {
            guard phase == .active,consent,school.isBound else{return}
            await school.syncAfterBinding()
        }
        .task(id:"school-session-\(phase)-\(consent)-\(school.sessionOwner ?? "")") {guard phase == .active,consent,school.sessionOwner != nil else{return};while !Task.isCancelled{await school.checkSessionExpiry();do{try await Task.sleep(for:.seconds(30))}catch{return}}}
        .onChange(of:phase){_,value in if value != .active{Task{try? await school.persistCookies()}}}
        .task(id:"\(phase)-\(consent)-\(platform.user?.id ?? "")-\(followRevision)") { if phase == .active && consent && platform.signedIn { await foreground.run(platform:platform) } }
        .task(id:"presence-\(phase)-\(consent)-\(platform.token ?? "")-\(school.identity?.studentID ?? "")-\(school.identity?.name ?? "")-\(school.identity?.grade ?? "")-\(school.identity?.admissionYear ?? 0)") {
            if phase == .active && consent { await studentReporter.run(platform: platform, school: school) }
        }
        .onChange(of:platform.user?.id){_,_ in foreground.clear()}
        .onReceive(NotificationCenter.default.publisher(for:.notificationFollowsChanged)){_ in foreground.followsChanged();followRevision+=1}
        .onOpenURL{url in guard consent,url.scheme=="mychuannong",let route=url.host,["schedule","notifications"].contains(route) else{return};deepLink=route}
        .sheet(isPresented:Binding(get:{deepLink != nil},set:{if !$0{deepLink=nil}})) { NavigationStack{Group{if deepLink=="schedule"{TimetableView()}else{PlatformGate{NotificationsView()}}}.toolbar{ToolbarItem(placement:.cancellationAction){Button("完成"){deepLink=nil}}}} }
        .alert(foreground.popup?.title ?? "服务消息",isPresented:Binding(get:{foreground.popup != nil},set:{if !$0{foreground.dismissPopup()}})){Button("知道了"){}}message:{Text(foreground.popup?["content"] ?? "")}
        .task(id: phase) { if phase == .active && consent { try? SchoolWidgets.update(school.snapshot); _ = try? await CourseNotifications.rebuild(school.snapshot) } }
        .task(id:"config-\(phase)-\(consent)"){guard phase == .active,consent else{return};while !Task.isCancelled{await configuration.refresh();do{try await Task.sleep(for:.seconds(30))}catch{return}}}
        .task(id:"academic-\(phase)-\(consent)"){guard phase == .active,consent else{return};await AcademicDataStore.shared.refresh()}
        .onChange(of:AcademicDataStore.shared.data?.contentFingerprint){_,_ in try? SchoolWidgets.update(school.snapshot);Task{_ = try? await CourseNotifications.rebuild(school.snapshot)}}
        .fullScreenCover(isPresented:Binding(get:{configuration.requiresUpdate},set:{_ in})){NavigationStack{AppUpdateView()}.interactiveDismissDisabled()}
        .fullScreenCover(item: Binding(get: { school.authenticationRequest }, set: { school.authenticationRequest = $0 })) { request in
            NavigationStack { SchoolAuthenticationView(resume: request) }.environment(school)
        }
        .task(id: consent) { if consent { await platform.restore() } }
    }
}

struct ConsentGate<Content: View>: View {
    @AppStorage(PrivacyConsent.storageKey) private var consent = false
    @ViewBuilder var content: () -> Content
    var body: some View {
        if consent { content() }
        else { WelcomeView() }
    }
}

struct PlatformGate<Content: View>: View {
    @Environment(PlatformSession.self) private var platform
    @ViewBuilder var content: () -> Content
    var body: some View { ConsentGate { if platform.signedIn { content() } else { PlatformLoginView() } } }
}

struct StatusMessage: View {
    let text: String
    var body: some View { Label(text, systemImage: "info.circle").font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
}

struct EmptyState: View {
    let title: String
    let message: String
    var icon = "tray"
    var body: some View { ContentUnavailableView(title, systemImage: icon, description: Text(message)) }
}

#if DEBUG
#Preview("完整主界面 · 本机预览") {
    AppVisualPreview()
}
#endif
