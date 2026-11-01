import SwiftUI
import PhotosUI

struct ProfileView: View {
    @Environment(PlatformSession.self) private var platform
    @Environment(SchoolSession.self) private var school
    @State private var avatar = AvatarStore()
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) { Text("我的").font(.system(size:30,weight:.black)) }
                NavigationLink { PlatformGate { AccountView() } } label: {
                    HStack(spacing:16) {
                        AvatarImage(data:avatar.data).frame(width:72,height:72)
                        VStack(alignment:.leading,spacing:10) {
                            HStack { Text(platform.user?.nickname ?? "川农同学").font(.system(size:20,weight:.semibold));Spacer();Text("编辑").font(.system(size:11)).foregroundStyle(ChuannongTheme.green) }
                            binding("我的川农账号",StudentPresentation.maskedPhone(platform.user?.phoneMasked))
                            binding("学号",StudentPresentation.maskedStudent(school.identity?.studentID))
                        }
                    }.padding(.horizontal,16).padding(.vertical,24).frame(minHeight:156).background(ChuannongTheme.card,in:RoundedRectangle(cornerRadius:24)).overlay(RoundedRectangle(cornerRadius:24).stroke(.secondary.opacity(0.12),lineWidth:0.5))
                }.buttonStyle(.plain)
                NavigationLink { OfficialWebsiteView() } label: {
                    HStack(spacing:14) {
                        Image(systemName:"globe.asia.australia").font(.system(size:28))
                        VStack(alignment:.leading,spacing:8) { Text("我的川农官网（最新消息）").font(.system(size:17,weight:.bold)) }
                        Spacer(minLength:0);Image(systemName:"chevron.right").font(.caption)
                    }.padding(20).foregroundStyle(.white).background(ChuannongTheme.green,in:RoundedRectangle(cornerRadius:22))
                }.buttonStyle(.plain)
                VStack(alignment:.leading,spacing:0) {
                    Text("主要设置").font(.system(size:17,weight:.semibold)).padding(.horizontal,18).padding(.top,18).padding(.bottom,8)
                    QQGroupSettingsRow()
                    SettingsLink("我的川农账号",icon:"person.crop.circle") { PlatformGate { AccountView() } }
                    SettingsLink("绑定学号",icon:"graduationcap") { SchoolBindingView() }
                    SettingsLink("上课提醒",icon:"bell.badge") { ReminderSettingsView() }
                    SettingsLink("桌面小组件",icon:"rectangle.3.group") { WidgetSettingsView() }
                    SettingsLink("通知设置",icon:"bell") { NotificationSettingsView() }
                    SettingsLink("检查更新",icon:"arrow.down.circle",last:true) { AppUpdateView() }
                }.background(ChuannongTheme.card,in:RoundedRectangle(cornerRadius:22))
                VStack(spacing:0) {
                    SettingsLink("隐私与合规",icon:"hand.raised") { PrivacySettingsView() }
                    SettingsLink("账号与数据管理",icon:"externaldrive",last:true) { AccountDataView() }
                }.background(ChuannongTheme.card,in:RoundedRectangle(cornerRadius:22))
            }.padding(.horizontal,16).padding(.top,12).padding(.bottom,28)
        }.background(ChuannongTheme.background).toolbar(.hidden,for:.navigationBar)
        .task(id:platform.user?.id) { avatar.load(owner:platform.user?.id) }
        .onAppear { avatar.load(owner:platform.user?.id) }
    }
    private func binding(_ name:String,_ value:String)->some View { HStack(spacing:8){Text(name).foregroundStyle(.secondary);Text(value)}.font(.system(size:12)) }
}

struct SettingsLink<Destination:View>:View {
    let title:String;let icon:String;var last:Bool;let destination:()->Destination
    init(_ title:String,icon:String,last:Bool=false,@ViewBuilder destination:@escaping()->Destination){self.title=title;self.icon=icon;self.last=last;self.destination=destination}
    var body:some View {
        VStack(spacing:0) {
            NavigationLink(destination:destination) { HStack(spacing:14) { Image(systemName:icon).font(.system(size:20)).foregroundStyle(ChuannongTheme.green).frame(width:24);Text(title).font(.system(size:15));Spacer();Image(systemName:"chevron.right").font(.system(size:12,weight:.semibold)).foregroundStyle(.tertiary) }.padding(.horizontal,18).frame(minHeight:58).contentShape(Rectangle()) }.buttonStyle(.plain)
            if !last{Divider().padding(.leading,56)}
        }
    }
}

struct AccountView: View {
    @Environment(PlatformSession.self) private var platform
    @Environment(SchoolSession.self) private var school
    @State private var nickname = ""
    @State private var error: String?
    @State private var saving = false
    @State private var action = ""
    @State private var confirm = false
    @State private var avatar = AvatarStore()
    @State private var photo: PhotosPickerItem?
    var body: some View {
        let avatarData = avatar.data
        let avatarSaving = saving
        ScrollView {
            VStack(alignment:.leading,spacing:20) {
                VStack(alignment:.leading,spacing:14){
                    Text("我的川农账号").font(.system(size:18,weight:.bold))
                    PhotosPicker(selection:$photo,matching:.images) { HStack { AvatarImage(data:avatarData).frame(width:64,height:64);Text(avatarSaving ? "正在保存…" : "修改头像") } }.disabled(saving)
                    binding("手机号",StudentPresentation.maskedPhone(platform.user?.phoneMasked));binding("学号",StudentPresentation.maskedStudent(school.identity?.studentID))
                    VStack(alignment:.leading,spacing:8){Text("昵称").font(.subheadline);TextField("昵称",text:$nickname).padding(14).overlay(RoundedRectangle(cornerRadius:12).stroke(.secondary.opacity(0.3)))}.onChange(of:nickname){_,value in nickname=String(value.prefix(30))}
                    Button{saving=true;Task{defer{saving=false};do{try await platform.nickname(nickname.trimmingCharacters(in:.whitespacesAndNewlines));error="昵称已更新"}catch{self.error=error.localizedDescription}}}label:{Text("保存昵称").frame(maxWidth:.infinity).padding(.vertical,7)}.buttonStyle(.borderedProminent).disabled(saving || nickname.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || nickname.trimmingCharacters(in:.whitespacesAndNewlines)==platform.user?.nickname)
                    HStack { Text("手机号验证");Spacer();Text(platform.user?.phoneVerified == true ? "已验证" : "待验证") }
                    if platform.user?.phoneVerified != true {
                        NavigationLink("验证绑定手机号") { PlatformLoginView(initialMode: .verify) }
                    }
                    NavigationLink("找回 / 重置密码") { PlatformLoginView(initialMode: .reset) }
                    NavigationLink("学生资料") { StudentIdentityView() }
                    if let reason=platform.user?.accountStatusReason,!reason.isEmpty{StatusMessage(text:reason)}
                    if let error{StatusMessage(text:error)}
                }.padding(18).background(ChuannongTheme.card,in:RoundedRectangle(cornerRadius:20))
                Button{action="切换账号";confirm=true}label:{Text("切换账号").frame(maxWidth:.infinity).padding(.vertical,6)}.buttonStyle(.bordered)
                Button("退出登录"){action="退出登录";confirm=true}.foregroundStyle(.secondary).frame(maxWidth:.infinity)
                NavigationLink("注销账号"){DeleteAccountView()}.foregroundStyle(.red).frame(maxWidth:.infinity)
            }.padding(.horizontal,18).padding(.vertical,14)
        }.background(ChuannongTheme.background).navigationTitle("账号与安全").navigationBarTitleDisplayMode(.inline).scrollDismissesKeyboard(.interactively)
        .task(id:platform.user?.id){nickname=platform.user?.nickname ?? "";avatar.load(owner:platform.user?.id)}
        .task(id:photo) {
            guard let photo,let owner=platform.user?.id else{return};saving=true;defer{saving=false}
            do{guard let raw=try await photo.loadTransferable(type:Data.self),raw.count<=20_000_000 else{throw APIError.server(422,"请选择 20MB 以内的图片")};try Task.checkCancellation();guard platform.user?.id==owner else{return};try await avatar.save(raw,owner:owner);error="头像已保存"}catch{self.error=error.localizedDescription}
        }
        .confirmationDialog(action,isPresented:$confirm,titleVisibility:.visible){Button("确认",role:.destructive){Task{try? await platform.logout()}}}message:{Text(action=="切换账号" ? "退出当前我的川农账号后，可登录其他我的川农账号。" : "确认退出我的川农账号？")}
    }
    private func binding(_ name:String,_ value:String)->some View{HStack(spacing:10){Text(name).foregroundStyle(.secondary);Text(value)}.font(.subheadline)}
}

struct AccountDataView: View {
    @Environment(SchoolSession.self) private var school
    @State private var confirm=false
    @State private var message:String?
    var body:some View {
        List {
            NavigationLink("注销账号"){PlatformGate{AccountView()}}
            Button("清除缓存"){confirm=true}.frame(maxWidth:.infinity)
            if let message{StatusMessage(text:message)}
        }.navigationTitle("账号与数据管理")
        .confirmationDialog("清除缓存",isPresented:$confirm,titleVisibility:.visible){Button("清除",role:.destructive){do{try school.clearLearningCaches();URLCache.shared.removeAllCachedResponses();message="学习数据缓存已清除，账号登录状态已保留"}catch{message=error.localizedDescription}}}message:{Text("确定清除课表（含自定义课程）、成绩和考试缓存吗？清除后需重新获取，账号登录状态不会受到影响。")}
    }
}

struct DeleteAccountView: View {
    @Environment(PlatformSession.self) private var platform
    @State private var password = ""
    @State private var confirm = false
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        Form {
            Section { Text("注销将删除平台账号及后台关联数据。Android 和 iOS 共用该账号，注销后两端都无法继续使用此账号。此操作无法撤销。"); SecureField("当前平台账号密码", text: $password).textContentType(.password) }
            if let error { StatusMessage(text: error) }
            Button("申请注销", role: .destructive) { confirm = true }.frame(maxWidth:.infinity).disabled(password.isEmpty || busy)
            if busy { ProgressView("正在提交…") }
        }.navigationTitle("注销账号")
        .confirmationDialog("永久注销平台账号？", isPresented: $confirm, titleVisibility: .visible) {
            Button("确认注销", role: .destructive) { busy = true; Task { defer { busy = false }; do { try await platform.deleteAccount(password: password); password = "" } catch { self.error = error.localizedDescription } } }
        }
    }
}

struct AboutView: View {
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:18){
                Text("我的川农").font(.system(size:28,weight:.black))
                Text("面向四川农业大学同学的轻量校园生活工具，集中展示常用校园信息、课程服务与实用入口。").font(.system(size:16)).foregroundStyle(.secondary).lineSpacing(9)
                VStack(alignment:.leading,spacing:4){Text("当前版本").font(.system(size:14)).foregroundStyle(.secondary);Text(Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "0.1.0").font(.system(size:20,weight:.bold))}.frame(maxWidth:.infinity,alignment:.leading).padding(18).background(ChuannongTheme.card,in:RoundedRectangle(cornerRadius:22))
                NavigationLink{OfficialWebsiteView()}label:{Text("访问我的川农官网").frame(maxWidth:.infinity).padding(.vertical,8)}.buttonStyle(.borderedProminent)
                Text("产品介绍、最新消息和详细说明请前往官网查看。").font(.system(size:14)).foregroundStyle(.secondary).lineSpacing(7)
                NavigationLink("检查更新"){AppUpdateView()}.frame(maxWidth:.infinity)
            }.padding(.horizontal,18).padding(.vertical,20)
        }.background(ChuannongTheme.background).navigationTitle("关于我的川农").navigationBarTitleDisplayMode(.inline)
    }
}
