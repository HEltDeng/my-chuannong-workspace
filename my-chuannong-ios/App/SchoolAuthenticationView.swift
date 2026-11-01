import SwiftUI

/// A full-screen, top-aligned login. Refresh owns the continuation, so authentication
/// never sends the student to settings or requires a second press of Refresh.
struct SchoolAuthenticationView: View {
    var resume: SchoolAuthenticationRequest?
    @Environment(SchoolSession.self) private var school
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @State private var account = ""
    @State private var password = ""
    @State private var code = ""
    @State private var challenge: SchoolChallenge?
    @State private var saved = false
    @State private var loading = false
    @State private var submitting = false
    @State private var error: String?
    @State private var task: Task<Void, Never>?
    @State private var official = false
    @FocusState private var field: Field?
    private enum Field { case account, password, code }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if submitting {
                    ProgressView("正在登录并刷新…").frame(maxWidth: .infinity).padding(.top, 32)
                } else {
                    if !saved {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("学号").font(.subheadline.weight(.medium))
                            TextField("", text: $account, prompt: Text("请输入学号").foregroundStyle(Color(uiColor: .label)))
                                .textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                                .focused($field, equals: .account).submitLabel(.next).onSubmit { field = .password }
                                .accessibilityIdentifier("school-account").authInput()
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            Text("密码").font(.subheadline.weight(.medium))
                            SecureField("", text: $password, prompt: Text("请输入川农 e 密码").foregroundStyle(Color(uiColor: .label)))
                                .textContentType(.password).focused($field, equals: .password)
                                .submitLabel(.next).onSubmit { field = .code }
                                .accessibilityIdentifier("school-password").authInput()
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("验证码").font(.subheadline.weight(.medium))
                        HStack(spacing: 12) {
                            TextField("", text: $code, prompt: Text("请输入验证码").foregroundStyle(Color(uiColor: .label)))
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .focused($field, equals: .code).submitLabel(.go).onSubmit { submit() }
                                .accessibilityIdentifier("school-verification-code").authInput()
                            Button { reloadChallenge() } label: {
                                if let challenge, let image = UIImage(data: challenge.image) {
                                    Image(uiImage: image).resizable().scaledToFit().frame(width: 120, height: 48)
                                } else { ProgressView().frame(width: 120, height: 48) }
                            }.disabled(loading).accessibilityLabel("更换验证码")
                        }
                    }
                    if let error { Text(error).font(.subheadline).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true) }
                    Button { submit() } label: {
                        Text(saved ? "验证并继续" : "登录").font(.body.weight(.semibold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 15)
                            .background(ChuannongTheme.green, in: RoundedRectangle(cornerRadius: 14))
                    }.buttonStyle(.plain)
                        .disabled(loading || challenge == nil || account.isEmpty || password.isEmpty || code.isEmpty)
                        .accessibilityIdentifier("school-auth-submit")
                    if saved { Button("修改登录密码") { saved = false; password = ""; field = .password }.font(.subheadline) }
                    if error != nil { Button("打开学校认证页面") { official = true }.font(.subheadline) }
                }
            }.foregroundStyle(.primary).frame(maxWidth: 480, alignment: .leading).frame(maxWidth: .infinity)
                .padding(.horizontal, 24).padding(.top, 28).padding(.bottom, 24)
        }
        .background(Color(uiColor: .systemBackground))
        .navigationTitle(saved ? "学校验证" : "川农 e 登录").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { task?.cancel(); dismiss() } } }
        .task {
            account = school.sessionOwner ?? ""
            do {
                if let credential = try school.savedCredential() { account = credential.account; password = credential.password; saved = true }
            } catch { self.error = error.localizedDescription }
            await loadChallenge()
        }
        .onDisappear { if !official { task?.cancel(); password = ""; code = "" } }
        .onChange(of: phase) { _, value in if value != .active { task?.cancel() } }
        .fullScreenCover(isPresented: $official, onDismiss: {
            task = Task {
                await school.checkNetwork()
                guard school.network == .connected else { return }
                do { try await school.authenticateAcademicUnified(); await finish() }
                catch { self.error = error.localizedDescription }
            }
        }) { NavigationStack { VPNAuthenticationView() }.environment(school) }
    }
    private func reloadChallenge() { task?.cancel(); task = Task { await loadChallenge() } }
    private func loadChallenge() async {
        loading = true; challenge = nil; code = ""; defer { loading = false }
        do { challenge = try await school.authenticationChallenge() }
        catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
    private func submit() {
        guard !submitting, !loading, let challenge, !account.isEmpty, !password.isEmpty, !code.isEmpty else { return }
        field = nil; error = nil; submitting = true
        task = Task {
            defer { submitting = false }
            do {
                if let resume, school.sessionOwner != resume.owner { throw SchoolFailure.changed }
                try await school.authenticateUnified(SchoolCredential(account: account.trimmingCharacters(in: .whitespacesAndNewlines), password: password), code: code, challenge: challenge)
                await finish()
            } catch is CancellationError {} catch {
                self.error = error.localizedDescription
                if SchoolFailure.reason(error) == .credentials { saved = false; password = "" }
                await loadChallenge()
            }
        }
    }
    private func finish() async {
        if let resume {
            do { try await school.resumeRefresh(resume) }
            catch is CancellationError { return }
            catch { self.error = error.localizedDescription; return }
        }
        guard !Task.isCancelled else { return }
        dismiss()
    }
}

private extension View {
    func authInput() -> some View {
        self.font(.body).foregroundStyle(.primary).padding(14)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}
