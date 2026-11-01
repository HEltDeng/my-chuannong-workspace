import SwiftUI
import UIKit
import ImageIO
import CryptoKit
import Observation
import UserNotifications

@MainActor @Observable final class AvatarStore {
    private(set) var data:Data?
    private static func file(_ owner:String)throws->URL {
        let folder=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appending(path:"Avatars",directoryHint:.isDirectory)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        var values=URLResourceValues();values.isExcludedFromBackup=true;var directory=folder;try directory.setResourceValues(values)
        return folder.appending(path:SHA256.hash(data:Data(owner.utf8)).map{String(format:"%02x",$0)}.joined()+".jpg")
    }
    func load(owner:String?){guard let owner,let url=try? Self.file(owner) else{data=nil;return};data=try? Data(contentsOf:url)}
    func save(_ raw:Data,owner:String)async throws{
        let jpeg=try await Task.detached(priority:.userInitiated){
            guard raw.count<=20_000_000,let source=CGImageSourceCreateWithData(raw as CFData,nil),let image=CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceThumbnailMaxPixelSize:512] as CFDictionary) else{throw APIError.server(422,"图片无法读取")}
            let out=NSMutableData();guard let target=CGImageDestinationCreateWithData(out,"public.jpeg" as CFString,1,nil) else{throw APIError.server(422,"图片无法保存")};CGImageDestinationAddImage(target,image,[kCGImageDestinationLossyCompressionQuality:0.85] as CFDictionary);guard CGImageDestinationFinalize(target) else{throw APIError.server(422,"图片无法保存")};return out as Data
        }.value
        try jpeg.write(to:Self.file(owner),options:[.atomic,.completeFileProtection]);data=jpeg
    }
}
struct AvatarImage:View {
    let data:Data?
    var body:some View{Group{if let data,let image=UIImage(data:data){Image(uiImage:image).resizable().scaledToFill()}else{DefaultAccountAvatar()}}.clipShape(Circle()).accessibilityLabel("头像")}
}
struct OfficialWebsiteView:View {
    var body:some View {
        ScrollView{VStack(spacing:22){Image(systemName:"globe.asia.australia").font(.system(size:48)).foregroundStyle(ChuannongTheme.green);Text("官网筹备中").font(.title.bold());NavigationLink("隐私政策"){LegalView(kind:.privacy)};NavigationLink("用户协议"){LegalView(kind:.agreement)};NavigationLink("服务说明"){ServiceInformationView()};NavigationLink("联系与反馈"){PlatformGate{FeedbackView()}}}.frame(maxWidth:.infinity).padding(24)}.navigationTitle("我的川农官网")
    }
}
struct PrivacySettingsView:View {
    var body:some View{List{NavigationLink("关于我的川农"){AboutView()};NavigationLink("隐私政策"){LegalView(kind:.privacy)};NavigationLink("用户协议"){LegalView(kind:.agreement)};NavigationLink("服务说明"){ServiceInformationView()};NavigationLink("第三方 SDK / 服务清单"){PrivacyInventoryView(personal:false)};NavigationLink("个人信息清单"){PrivacyInventoryView(personal:true)}}.navigationTitle("隐私与合规")}
}
struct PrivacyInventoryView:View {
    let personal:Bool
    var body:some View { LegalView(kind: personal ? .collection : .thirdParties) }
}

struct NotificationSettingsView:View {
    @Environment(PlatformSession.self) private var platform
    @State private var permission="正在读取"
    @State private var undetermined=false
    @State private var error:String?
    @Environment(\.scenePhase) private var phase
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:16){
                VStack(alignment:.leading,spacing:12){
                    HStack{Text("系统通知权限");Spacer();Text(permission).font(.caption).foregroundStyle(.secondary);Button("管理"){if let url=URL(string:UIApplication.openNotificationSettingsURLString){UIApplication.shared.open(url)}}}
                    if undetermined{Button("开启通知"){Task{do{_ = try await UNUserNotificationCenter.current().requestAuthorization(options:[.alert,.sound,.badge]);await readPermission()}catch{self.error=error.localizedDescription}}}.frame(maxWidth:.infinity)}
                    if let error{StatusMessage(text:error)}
                }.padding(18).background(ChuannongTheme.card,in:RoundedRectangle(cornerRadius:20))
                VStack(alignment:.leading,spacing:12){
                    if platform.signedIn{NotificationFollowControls()}
                    else{NavigationLink("登录账号"){PlatformGate{AccountView()}}.frame(maxWidth:.infinity)}
                }.frame(maxWidth:.infinity,alignment:.leading).padding(18).background(ChuannongTheme.card,in:RoundedRectangle(cornerRadius:20))
            }.padding(16)
        }.background(ChuannongTheme.background).navigationTitle("通知设置").navigationBarTitleDisplayMode(.inline).task(id:phase){guard phase == .active else{return};await readPermission()}
    }
    private func readPermission() async {let s=await UNUserNotificationCenter.current().notificationSettings();undetermined=s.authorizationStatus == .notDetermined;permission = [.authorized,.provisional,.ephemeral].contains(s.authorizationStatus) ? "已允许" : s.authorizationStatus == .denied ? "未允许" : "尚未开启"}
}

extension Notification.Name {static let notificationFollowsChanged=Notification.Name("cn.notificationFollowsChanged")}

struct NotificationFollowControls:View {
    @Environment(PlatformSession.self) private var platform
    @State private var follows=RemoteContent()
    @State private var busy=false
    var body:some View {
        if follows.loading{ProgressView("正在读取关注设置…")}
        if follows.loaded{ForEach(follows.value["items"].list,id:\.self){item in Toggle(item["title"].text,isOn:Binding(get:{item["following"].boolean},set:{enabled in update(item["module"].text,enabled:enabled)})).disabled(busy).accessibilityLabel("关注"+item["title"].text)}}
        if let error=follows.error{StatusMessage(text:error);Button("重新读取"){Task{await reload()}}.frame(maxWidth:.infinity).disabled(busy || follows.loading)}
        Color.clear.frame(height:0).task(id:platform.user?.id){await reload()}
    }
    private func reload() async {
        await follows.load("notifications/follows",session:platform)
    }
    private func update(_ module:String,enabled:Bool){
        guard !busy,let owner=platform.user?.id else{return};busy=true
        Task{defer{busy=false};do{
            _ = try await platform.perform("notifications/follows/"+module,method:"PUT",body:["following":.bool(enabled)])
            guard platform.user?.id==owner else{return}
            if !enabled{
                let center=UNUserNotificationCenter.current(),delivered=await center.deliveredNotifications()
                center.removeDeliveredNotifications(withIdentifiers:delivered.filter{$0.request.content.userInfo["module"] as? String==module && $0.request.content.userInfo["owner"] as? String==owner}.map{$0.request.identifier})
            }
            NotificationCenter.default.post(name:.notificationFollowsChanged,object:nil)
            await reload()
            if enabled{let center=UNUserNotificationCenter.current();if await center.notificationSettings().authorizationStatus == .notDetermined{_ = try await center.requestAuthorization(options:[.alert,.sound,.badge])}}
        }catch{follows.error=error.localizedDescription}}
    }
}

struct DefaultAccountAvatar:View {
    var body:some View{GeometryReader{geometry in Canvas{context,size in
        let scale=min(size.width,size.height)/96
        context.scaleBy(x:scale,y:scale)
        context.fill(Path(ellipseIn:CGRect(x:0,y:0,width:96,height:96)),with:.color(Color(hex:0xDEEFE5)))
        context.fill(Path(ellipseIn:CGRect(x:34,y:20,width:28,height:28)),with:.color(ChuannongTheme.green))
        var body=Path();body.move(to:CGPoint(x:22,y:77));body.addCurve(to:CGPoint(x:48,y:53),control1:CGPoint(x:22,y:62.6),control2:CGPoint(x:33.6,y:53));body.addCurve(to:CGPoint(x:74,y:77),control1:CGPoint(x:62.4,y:53),control2:CGPoint(x:74,y:62.6));body.addLine(to:CGPoint(x:74,y:80));body.addLine(to:CGPoint(x:22,y:80));body.closeSubpath();context.fill(body,with:.color(ChuannongTheme.green))
    }}}
}
