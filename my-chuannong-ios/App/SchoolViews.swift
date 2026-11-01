import SwiftUI
import WebKit

struct SchoolBindingView: View {
    @Environment(SchoolSession.self) private var school
    @State private var vpn = false
    @State private var error: String?
    @State private var unbind = false
    @State private var connecting = false
    @State private var connectionTask: Task<Void, Never>?
    @Environment(\.scenePhase) private var phase
    var body: some View {
        ConsentGate {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 20) {
                        Image(systemName: school.isBound ? "checkmark.circle" : "person.text.rectangle")
                            .font(.system(size: 48)).foregroundStyle(ChuannongTheme.green).accessibilityHidden(true)
                        if school.isBound {
                            Text("学校账号已绑定").font(.title2.bold()).foregroundStyle(ChuannongTheme.green)
                            Text((school.identity?.name ?? "川农同学") + " · " + (school.identity?.studentID ?? ""))
                            NavigationLink("查看课表") { TimetableView() }.buttonStyle(.borderedProminent).controlSize(.large).accessibilityIdentifier("binding-timetable")
                        } else {
                            Text("绑定学号").font(.title2.bold())
                            if connecting || school.network == .checking {
                                ProgressView(school.network == .checking ? "正在检查学校会话…" : "正在完成教务认证与学号绑定…").frame(maxWidth: .infinity)
                            } else {
                                Button("川农 e 认证登录") {
                                    connect()
                                }.buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth: .infinity).disabled(school.busy)
                            }
                        }
                    }.multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(24).background(ChuannongTheme.card, in: RoundedRectangle(cornerRadius: 24))
                    HStack(spacing: 12) {
                        if school.network == .checking || connecting {
                            ProgressView()
                            Text(connecting ? "正在连接校园网络…" : "正在检测校园网络…")
                        } else {
                            Label(school.network == .connected ? "校园网络已连接" : school.network == .notConnected ? "校园网络未连接" : "校园网络尚未确认",
                                  systemImage: school.network == .connected ? "globe" : school.network == .notConnected ? "xmark.circle" : "questionmark.circle")
                                .foregroundStyle(school.network == .connected ? ChuannongTheme.green : Color.primary)
                            Spacer(minLength: 8)
                            if school.isBound && school.network == .notConnected {
                                Button("连接") { connect() }
                                    .disabled(school.busy).accessibilityIdentifier("binding-connect-network")
                                    .accessibilityLabel("连接校园网络")
                            } else {
                                Button {
                                    connectionTask?.cancel()
                                    connectionTask = Task { await school.checkNetwork(); error = school.message }
                                } label: { Image(systemName: "arrow.clockwise").frame(minWidth: 32, minHeight: 44) }
                                    .disabled(school.busy).accessibilityIdentifier("binding-check-network")
                                    .accessibilityLabel("重新检测校园网络")
                            }
                        }
                    }.font(.body).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20).padding(.vertical, 12)
                        .background(ChuannongTheme.card, in: RoundedRectangle(cornerRadius: 16))
                    if let error { Text(error).font(.subheadline).foregroundStyle(.primary) }
                    if school.isBound { Button("解绑学校账号与清除会话", role: .destructive) { unbind = true } }
                }.padding(20)
            }.background(ChuannongTheme.background)
            .task {
                await school.checkNetwork()
                guard !Task.isCancelled, !school.isBound, !vpn, school.network == .connected else { return }
                connect()
            }
        }.navigationTitle("绑定学号").navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $vpn, onDismiss: {
            connectionTask = Task { await school.checkNetwork(); error = school.message }
        }) {
            NavigationStack { SchoolAuthenticationView() }.environment(school)
        }
        .onChange(of: school.identity?.verifiedAt) { _, _ in error = nil }
        .onDisappear { if !vpn { connectionTask?.cancel() } }
        .onChange(of: phase) { _, value in if value != .active { connectionTask?.cancel() } }
        .confirmationDialog("清除学校会话？", isPresented: $unbind, titleVisibility: .visible) {
            Button("清除", role: .destructive) { Task { do { try school.clearCurrentData(); try await school.forget(); error = nil } catch { self.error = error.localizedDescription } } }
        } message: { Text("清除本应用学校会话及当前账号学习缓存；平台账号保持登录。") }
    }
    private func connect() {
        guard !connecting else { return }
        connectionTask?.cancel(); connectionTask = Task { await bindUnified() }
    }
    private func bindUnified() async {
        guard !connecting, !school.busy else { return }
        connecting = true; error = nil
        defer { connecting = false }
        do {
            await school.checkNetwork()
            try Task.checkCancellation()
            if school.network == .notConnected { vpn = true; return }
            guard school.network == .connected else { error = school.message; return }
            if !school.isBound { try await school.authenticateAcademicUnified() }
        } catch is CancellationError {} catch {
            if SchoolAuthentication.requiresAuthentication(error) { vpn = true }
            else { self.error = error.localizedDescription }
        }
    }
}

struct CampusNetworkView: View {
    var body: some View { SchoolBindingView() }
}

struct VPNAuthenticationView: View {
    @Environment(SchoolSession.self) private var school
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @State private var state = SchoolBrowserState()
    @State private var failure: String?
    @State private var revision = 0
    var body: some View {
        ZStack {
            SchoolWebPage(url: AcademicRoute.portal, school: school, state: state, watchPortal: true)
            if !state.isAuthentication {
                VStack(spacing: 20) {
                    if let text = failure ?? state.error { Text(text).multilineTextAlignment(.center); Button("重新连接") { failure=nil;state.error=nil;state.web?.reload();revision+=1 }.buttonStyle(.borderedProminent) }
                    else { ProgressView(); Text("正在验证校园 VPN，请稍候……").foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity,maxHeight: .infinity).background(ChuannongTheme.background)
            }
        }.ignoresSafeArea(.keyboard,edges:.bottom)
        .navigationTitle("川农 e 认证").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("返回") { dismiss() } } }
        .task(id: "\(phase)-\(revision)") {
            guard phase == .active else{return}
            var attempted: String?
            var idleChecks=0
            while !Task.isCancelled {
                if let route=school.route,state.portalReady,!state.isAuthentication,attempted != route.prefix {
                    attempted=route.prefix;await school.checkNetwork()
                    if school.network == .connected {dismiss();return}
                    failure=school.message ?? "校园 VPN 验证失败，请检查网络后重新连接。";return
                }
                if !state.isAuthentication {idleChecks+=1} else {idleChecks=0}
                if idleChecks>35 {failure="校园 VPN 资源尚未加载完成，请重新连接。";return}
                do{try await Task.sleep(for:.seconds(1))}catch{return}
            }
        }
    }
}

struct SchoolBrowserView: View {
    let url: URL
    let title: String
    var serviceTarget: URL? = nil
    var canBind = false
    var expectedAccount: String?
    @Environment(SchoolSession.self) private var school
    @Environment(\.dismiss) private var dismiss
    @State private var bridge = SchoolBrowserState()
    @State private var error: String?
    var body: some View {
        VStack(spacing: 0) {
            if bridge.loading { ProgressView(bridge.reusingSession ? "正在恢复学校认证…" : "正在加载…").frame(maxWidth: .infinity).padding(6) }
            if let message = error ?? bridge.error { StatusMessage(text: message).padding(12) }
            SchoolWebPage(url: url, school: school, state: bridge, serviceTarget: serviceTarget)
        }
        .ignoresSafeArea(.keyboard,edges:.bottom)
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                Button { bridge.goBack() } label: { Image(systemName: "chevron.left") }.disabled(!bridge.canBack).accessibilityLabel("网页后退")
                Spacer()
                Button { bridge.web?.reload() } label: { Image(systemName: "arrow.clockwise") }.accessibilityLabel("重新加载网页")
                Spacer()
                if canBind {
                    Button("完成认证") {
                        Task { do { try await school.verifyBinding(expected:expectedAccount); dismiss() } catch { self.error = error.localizedDescription } }
                    }.disabled(school.busy || school.route == nil)
                }
            }
            if canBind { ToolbarItem(placement: .cancellationAction) { Button("返回") { dismiss() } } }
        }
        .task(id: bridge.navigationRevision) {
            guard canBind, bridge.navigationRevision > 0, let current = bridge.web?.url,
                  let route = school.route, route.contains(current), !current.path.hasSuffix(AcademicRoute.loginPath) else { return }
            do {
                try await school.verifyBinding(expected: expectedAccount)
                dismiss()
            } catch is CancellationError {} catch {
                if SchoolFailure.reason(error) == .changed { self.error = error.localizedDescription }
            }
        }
    }
}

@MainActor @Observable final class SchoolBrowserState {
    var web: WKWebView?
    var loading = false
    var canBack = false
    var error: String?
    var isAuthentication = false
    var portalReady = false
    var reusingSession = false
    var navigationRevision = 0
    func goBack() {
        guard let web,let item=web.backForwardList.backList.reversed().first(where:{!SchoolServiceNavigation.authentication($0.url)}) else{return}
        web.go(to:item)
    }
}

struct SchoolWebPage: UIViewRepresentable {
    let url: URL
    let school: SchoolSession
    let state: SchoolBrowserState
    var watchPortal = false
    var serviceTarget: URL? = nil
    func makeCoordinator() -> Coordinator { Coordinator(school: school, state: state, watchPortal: watchPortal, serviceTarget: serviceTarget) }
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration(); config.websiteDataStore = school.dataStore
        config.userContentController.addUserScript(WKUserScript(source:SchoolWebPresentation.authentication,injectionTime:.atDocumentStart,forMainFrameOnly:true))
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator; web.uiDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = true
        state.web = web
        context.coordinator.initialLoad=Task { await school.restore();guard !Task.isCancelled,state.web===web else{return};web.load(URLRequest(url:url)) }
        return web
    }
    func updateUIView(_ web: WKWebView, context: Context) {}
    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) {
        coordinator.initialLoad?.cancel();coordinator.inspection?.cancel();coordinator.ssoTask?.cancel(); web.stopLoading(); web.navigationDelegate = nil; web.uiDelegate = nil; coordinator.state.web = nil
        Task { try? await coordinator.school.persistCookies() }
    }
    @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let school: SchoolSession
        let state: SchoolBrowserState
        let watchPortal: Bool
        var journey: SchoolServiceJourney?
        var triedStudentHall = false
        var inspection: Task<Void,Never>?
        var initialLoad:Task<Void,Never>?
        var ssoTask:Task<Void,Never>?
        var ssoAttempts:[String:Date]=[:]
        init(school: SchoolSession, state: SchoolBrowserState, watchPortal: Bool, serviceTarget: URL?) { self.school = school; self.state = state; self.watchPortal=watchPortal; self.journey=serviceTarget.map{SchoolServiceJourney(target:$0)} }
        func webView(_ web: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            if action.targetFrame?.isMainFrame != false {ssoTask?.cancel();ssoTask=nil}
            guard let url = action.request.url, SchoolURLPolicy.allows(url) else {
                state.error = "该链接不属于学校 HTTPS 服务，请返回学校页面。"; decisionHandler(.cancel); return
            }
            if action.targetFrame?.isMainFrame != false,action.request.httpMethod == "GET",let request=SchoolSSORequest(url) {
                ssoAttempts=ssoAttempts.filter{Date.now.timeIntervalSince($0.value)<60}
                if ssoAttempts[request.attemptKey]==nil,ssoAttempts.count<64 {
                    ssoAttempts[request.attemptKey] = .now;state.reusingSession=true;decisionHandler(.cancel);ssoTask?.cancel()
                    let owner=school.sessionOwner
                    state.reusingSession=true;state.loading=true
                    ssoTask=Task {
                        do {
                            let destination=try await school.ssoDestination(url)
                            guard !Task.isCancelled,(owner==nil || school.sessionOwner==owner),state.web===web else{return}
                            ssoTask=nil;state.reusingSession=false
                            web.load(URLRequest(url:destination ?? SchoolSSORequest.reuseURL(url) ?? url))
                        } catch is CancellationError {}
                        catch {
                            guard !Task.isCancelled,state.web===web else{return}
                            ssoTask=nil;state.reusingSession=false;state.loading=false;state.error=error.localizedDescription
                        }
                    };return
                }
            }
            decisionHandler(.allow)
        }
        func webView(_ web: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = action.request.url, SchoolURLPolicy.allows(url) { web.load(action.request) }; return nil
        }
        func webView(_ web: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { state.loading = true; state.error = nil; if watchPortal{state.isAuthentication=false;state.portalReady=false;web.isHidden=true};inspection?.cancel() }
        func webView(_ web: WKWebView, didFinish navigation: WKNavigation!) {
            state.loading = false; state.reusingSession=false
            state.navigationRevision += 1
            state.canBack = web.backForwardList.backList.contains{!SchoolServiceNavigation.authentication($0.url)}
            inspection?.cancel()
            inspection=Task {
                var checks=0,checkedOwner=false
                repeat {
                    guard !Task.isCancelled else{return}
                    if let document=try? await SchoolPageReader.document(web) {
                        guard !Task.isCancelled,let documentURL=URL(string:document.url),web.url==documentURL else{return}
                        await school.observe(document)
                        guard !Task.isCancelled,web.url==documentURL else{return}
                        if !checkedOwner,!document.authenticationRequired,let current=URL(string:document.url),!SchoolServiceNavigation.authentication(current),school.ssoOwner==nil {
                            checkedOwner=true
                            do {_ = try await school.confirmUnifiedSession()}
                            catch is CancellationError {return}
                            catch {state.error=error.localizedDescription;return}
                        }
                        guard !Task.isCancelled,web.url==documentURL else{return}
                        if let current=URL(string:document.url),journey != nil {
                            switch journey!.finished(school.canonicalSchoolURL(current)) {
                            case .returnToTarget:
                                web.load(URLRequest(url:journey!.target));return
                            case .failed:
                                state.error="学校认证已返回，但服务页面尚未打开，请重新加载。";return
                            case .ready:break
                            case .wait:break
                            }
                        }
                        if watchPortal {
                            let current=web.url
                            let authHost=current?.host=="auth.sicau.edu.cn"
                            let authPath=current?.path.contains("/wui") == true || current?.path=="/login"
                            state.isAuthentication=authHost || authPath || document.authenticationRequired || document.challengeRequired == true
                            state.portalReady = current?.host == "webvpn.sicau.edu.cn" && ["/", "/portal", "/m/portal"].contains(current?.path ?? "") && document.links.contains(where: { $0.label.contains("jiaowu.sicau.edu.cn") }) && !state.isAuthentication
                            web.isHidden = !state.isAuthentication
                        }
                    }
                    try? await school.persistCookies()
                    checks+=1
                    if !watchPortal && (journey == nil || journey?.reached == true || checks>=20){return}
                    do{try await Task.sleep(for:.milliseconds(watchPortal ? 1000 : 500))}catch{return}
                } while true
            }
        }
        func webView(_ web: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed(web,error:error) }
        func webView(_ web: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed(web,error:error) }
        private func failed(_ web: WKWebView,error: Error) {
            if (error as NSError).code==NSURLErrorCancelled {return}
            if state.reusingSession, (error as NSError).domain == "WebKitErrorDomain", (error as NSError).code == 102 { return }
            if !triedStudentHall,journey?.target.host=="xsgz.sicau.edu.cn",web.url.map({!SchoolServiceNavigation.authentication($0)}) ?? true {
                triedStudentHall=true;web.load(URLRequest(url:SchoolServiceNavigation.studentHall));return
            }
            state.loading=false;state.reusingSession=false;state.error=error.localizedDescription
        }
    }
}

struct SchoolGate<Content: View>: View {
    @Environment(SchoolSession.self) private var school
    @ViewBuilder var content: () -> Content
    var body: some View {
        if school.isBound { content() }
        else {
            VStack(spacing: 22) {
                EmptyState(title: "尚未绑定学校账号", message: "完成学校身份验证后，可以把本人的课表、成绩与考试保存在这台设备。", icon: "graduationcap")
                NavigationLink("绑定学校账号") { SchoolBindingView() }.buttonStyle(.borderedProminent).padding(.bottom, 36)
            }
        }
    }
}

struct SyncStatus: View {
    let page: SchoolPage
    @Environment(SchoolSession.self) private var school
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error = school.errors[page.rawValue] {
                Text(error).font(.subheadline).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
            }
            if let date = school.snapshot.updated[page.rawValue] {
                Text("更新于 \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.primary)
            } else { Text("尚未同步").font(.caption).foregroundStyle(.primary) }
        }
    }
}

struct SchoolRefresh: View {
    let page: SchoolPage
    @Environment(SchoolSession.self) private var school
    @State private var task: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        Button {
            task?.cancel(); task = Task { await school.sync(page) }
        } label: { if school.busy { ProgressView() } else { Image(systemName: "arrow.clockwise") } }
        .accessibilityLabel("刷新学校数据").disabled(school.busy)
        .onDisappear { task?.cancel() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { task?.cancel() } }
    }
}

struct AcademicServiceView: View {
    @Environment(SchoolSession.self) private var school
    @Environment(\.scenePhase) private var phase
    @State private var destination: URL?
    @State private var error: String?
    @State private var revision = 0
    var body: some View {
        Group {
            if !school.isBound { SchoolBindingView() }
            else if let destination { SchoolBrowserView(url: destination, title: "教务系统") }
            else if let error {
                VStack(spacing: 20) {
                    StatusMessage(text: error)
                    Button("重新连接") { self.error = nil; revision += 1 }.buttonStyle(.borderedProminent)
                    NavigationLink("连接校园网络") { SchoolBindingView() }
                }.padding(24)
            } else { ProgressView("正在恢复教务会话…") }
        }
        .task(id: "\(school.identity?.studentID ?? "")-\(phase)-\(revision)") {
            guard phase == .active, school.isBound, destination == nil, error == nil else { return }
            do { destination = try await school.academicWebEntry() }
            catch is CancellationError {}
            catch { self.error = error.localizedDescription }
        }
    }
}

struct SchoolServiceView:View {
    let url:URL
    let title:String
    @Environment(SchoolSession.self) private var school
    var body:some View {
        ConsentGate {
            SchoolBrowserView(url:SchoolServiceNavigation.initial(url,gateway:school.resolved(url)),title:title,serviceTarget:url)
        }.navigationTitle(title)
    }
}
