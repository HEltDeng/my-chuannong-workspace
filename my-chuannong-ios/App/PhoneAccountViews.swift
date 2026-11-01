import SwiftUI

struct PlatformLoginView: View {
    @Environment(PlatformSession.self) private var platform
    @Environment(\.dismiss) private var dismiss
    @AppStorage(PrivacyConsent.storageKey) private var consent = false
    @State private var mode: PhoneAccountMode
    @State private var phone = ""
    @State private var nickname = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var code = ""
    @State private var challenge: SMSChallenge?
    @State private var resendAt = Date.distantPast
    @State private var expiresAt = Date.distantPast
    @State private var now = Date()
    @State private var capabilities: PhoneAuthCapabilities?
    @State private var availabilityError: String?
    @State private var error: String?
    @State private var message: String?
    @State private var remind = false
    @FocusState private var focus: String?
    init(initialMode: PhoneAccountMode = .login) { _mode = State(initialValue: initialMode) }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Image(systemName:"leaf.fill").font(.system(size:54)).foregroundStyle(ChuannongTheme.green)
                    .frame(width:64,height:64).accessibilityLabel("我的川农")
                Text(mode.title).font(.system(size:24,weight:.bold)).multilineTextAlignment(.center)
                VStack(spacing:16) {
                    if mode == .register {
                        field("昵称",hint:"昵称",text:$nickname,id:"nickname").onChange(of:nickname){_,v in nickname=String(v.prefix(30))}
                    }
                    field("手机号",hint:mode == .verify ? "当前账号的注册手机号" : "11 位手机号",text:$phone,id:"phone")
                        .keyboardType(.phonePad).textContentType(.telephoneNumber)
                        .onChange(of:phone){_,v in
                            phone=String(v.filter{$0.isASCII && $0.isNumber}.prefix(11));challenge=nil;code=""
                        }
                    if mode != .login {
                        if !smsAvailable {
                            HStack { Text(availabilityError ?? "短信验证待开通");Spacer();Button("刷新"){Task{await loadCapabilities()}} }
                                .font(.subheadline).accessibilityIdentifier("sms-availability")
                        }
                        HStack(alignment:.bottom,spacing:12) {
                            field("短信验证码",hint:"6 位验证码",text:$code,id:"sms-code")
                                .keyboardType(.numberPad).textContentType(.oneTimeCode)
                                .onChange(of:code){_,v in code=String(v.filter{$0.isASCII && $0.isNumber}.prefix(6))}
                            Button(remaining > 0 ? "\(remaining) 秒" : "获取验证码") { sendCode() }
                                .buttonStyle(.bordered).frame(minHeight:48)
                                .disabled(platform.busy || !smsAvailable || !CampusContract.validPhone(phone) || remaining > 0)
                                .accessibilityIdentifier("request-sms-code")
                        }
                    }
                    if mode != .verify {
                        passwordField(mode == .reset ? "新密码" : "密码",text:$password,id:"password")
                    }
                    if mode.needsNewPassword {
                        passwordField("确认密码",text:$confirmation,id:"confirm-password")
                    }
                    if mode.needsNewPassword,!confirmation.isEmpty,confirmation != password {
                        Text("两次输入的密码不一致").font(.subheadline).foregroundStyle(.red).frame(maxWidth:.infinity,alignment:.leading)
                    }
                    if let error { Text(error).font(.subheadline).foregroundStyle(.red).frame(maxWidth:.infinity,alignment:.leading) }
                    if let message { Text(message).font(.subheadline).foregroundStyle(ChuannongTheme.green).frame(maxWidth:.infinity,alignment:.leading) }
                    Button {
                        focus=nil
                        if mode.needsNewPassword { remind=true } else { submit() }
                    } label: {
                        HStack { if platform.busy { ProgressView().tint(.white) };Text(submitTitle) }.frame(maxWidth:.infinity,minHeight:42)
                    }.buttonStyle(.borderedProminent).disabled(!canSubmit).accessibilityIdentifier("account-submit")
                    if mode != .verify {
                        if mode == .login {
                            Button("忘记密码") { switchMode(.reset) }.disabled(platform.busy)
                        }
                        Button(mode == .login ? "创建账号" : "返回登录") { switchMode(mode == .login ? .register : .login) }.disabled(platform.busy)
                    }
                    NavigationLink("隐私政策与用户协议") { LegalView() }.font(.subheadline)
                }.padding(18).background(ChuannongTheme.card,in:RoundedRectangle(cornerRadius:20))
            }.padding(.horizontal,22).padding(.vertical,24)
        }.background(ChuannongTheme.background).navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively).tint(ChuannongTheme.green)
            .disabled(platform.busy)
            .alert("请牢记密码",isPresented:$remind) {
                Button("确认并继续") { submit() };Button("返回检查",role:.cancel) {}
            } message: { Text(PhoneAccountRules.reminder) }
            .task {
                await loadCapabilities()
                while !Task.isCancelled {
                    do { try await Task.sleep(for:.seconds(1)) } catch { return }
                    now=Date()
                }
            }
    }
    private var smsAvailable:Bool { capabilities?.availablePurposes.contains(mode.purpose) == true }
    private var remaining:Int { max(0,Int(ceil(resendAt.timeIntervalSince(now)))) }
    private var submitTitle:String {
        switch mode { case .login:"登录";case .register:"注册并进入";case .reset:"重置密码";case .verify:"确认验证" }
    }
    private var canSubmit:Bool {
        guard !platform.busy,CampusContract.validPhone(phone) else{return false}
        if mode == .login { return CampusContract.validPassword(password) }
        guard challenge != nil,expiresAt > now,PhoneAccountRules.validCode(code) else{return false}
        if mode == .verify { return true }
        return PhoneAccountRules.validConfirmation(password:password,confirmation:confirmation) && (mode != .register || !nickname.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
    }
    private func field(_ title:String,hint:String,text:Binding<String>,id:String)->some View {
        VStack(alignment:.leading,spacing:8) { Text(title).font(.subheadline)
            TextField(hint,text:text).textInputAutocapitalization(.never).autocorrectionDisabled().focused($focus,equals:id)
                .padding(13).overlay(RoundedRectangle(cornerRadius:12).stroke(.secondary.opacity(0.3))).accessibilityIdentifier(id)
        }
    }
    private func passwordField(_ title:String,text:Binding<String>,id:String)->some View {
        VStack(alignment:.leading,spacing:8) { Text(title).font(.subheadline)
            SecureField(mode == .login ? "请输入密码" : "至少 8 位",text:text).textContentType(mode == .login ? .password : .newPassword)
                .focused($focus,equals:id).padding(13).overlay(RoundedRectangle(cornerRadius:12).stroke(.secondary.opacity(0.3))).accessibilityIdentifier(id)
        }.onChange(of:text.wrappedValue){_,v in text.wrappedValue=String(v.prefix(200))}
    }
    private func switchMode(_ next:PhoneAccountMode) {
        mode=next;password="";confirmation="";code="";challenge=nil;error=nil;message=nil
    }
    private func loadCapabilities() async {
        do { capabilities=try await platform.phoneCapabilities();availabilityError=nil }
        catch { capabilities=nil;availabilityError="短信验证暂未开放，请稍后重试" }
    }
    private func sendCode() {
        guard remaining == 0 else{return};error=nil;message=nil;focus=nil
        Task { do {
            let result=try await platform.requestSMS(phone:phone,mode:mode)
            challenge=result;code="";resendAt=Date().addingTimeInterval(Double(result.retryAfter));expiresAt=Date().addingTimeInterval(Double(result.expiresIn))
            message="若手机号符合当前操作条件，验证码将发送至该手机，5 分钟内有效。";focus="sms-code"
        } catch { self.error=error.localizedDescription } }
    }
    private func submit() {
        guard canSubmit else{return};error=nil;message=nil
        Task { do {
            switch mode {
            case .login,.register:
                try await platform.authenticate(phone:phone,password:password,nickname:mode == .register ? nickname : nil,consented:consent,
                    confirmPassword:confirmation,challengeId:challenge?.challengeId,code:code)
                password="";confirmation="";code=""
            case .reset:
                let result=try await platform.resetPassword(phone:phone,password:password,confirmation:confirmation,challengeId:challenge?.challengeId ?? "",code:code)
                switchMode(.login);message="密码已重置，请重新登录。今日剩余找回次数：\(result.remainingToday)。"
            case .verify:
                try await platform.verifyPhone(challengeId:challenge?.challengeId ?? "",code:code);code="";dismiss()
            }
        } catch { self.error=error.localizedDescription } }
    }
}

#if DEBUG
#Preview("创建平台账号") {
    NavigationStack { PlatformLoginView(initialMode:.register) }.environment(PlatformSession(loadSaved:false))
}
#endif
