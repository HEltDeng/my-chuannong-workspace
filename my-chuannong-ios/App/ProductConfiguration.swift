import SwiftUI
import Observation

struct NavigationItem:Decodable,Identifiable {
    var id:String;var actionId:String;var title:String;var order:Int;var section:String;var visible:Bool;var featureKey:String?
    var route:FeatureRoute?{FeatureRoute(rawValue:actionId)}
}
@MainActor @Observable final class ProductConfiguration {
    private(set) var navigation:[NavigationItem]=[]
    private(set) var flags:[String:JSONValue]=[:]
    private(set) var release:JSONValue = .null
    private let client=APIClient()
    private struct Catalogue:Decodable{var navigation:[NavigationItem]}
    init(previewFlags: [String: JSONValue]? = nil){if let previewFlags {flags=previewFlags} else if let data=UserDefaults.standard.data(forKey:"services.availability.v1"),let cached=try? JSONDecoder().decode([String:JSONValue].self,from:data){flags=cached};if let url=Bundle.main.url(forResource:"app-catalogue",withExtension:"json"),let raw=try? Data(contentsOf:url),let value=try? JSONDecoder().decode(Catalogue.self,from:raw){navigation=value.navigation}}
    func refresh()async {
        do {
            let data:JSONValue=try await client.request("public/bootstrap",query:["schemaVersion":"1","appVersionCode":Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "1","platform":"ios"])
            try Task.checkCancellation()
            flags=Dictionary(data["flags"].list.map{($0["key"].text,$0)},uniquingKeysWith:{$1})
            if let cached=try? JSONEncoder().encode(flags){UserDefaults.standard.set(cached,forKey:"services.availability.v1")}
            if data["schemaVersion"].number==1,let raw=try? JSONEncoder().encode(data["config"]),let config=try? JSONDecoder().decode(Catalogue.self,from:raw),Set(config.navigation.map(\.id)).count==config.navigation.count{navigation=config.navigation.filter{$0.route != nil}}
            if data["updatePolicy"]["platform"].text=="ios"{release=data["updatePolicy"]}
        }catch{}
    }
    func entries(_ section:String)->[NavigationItem]{let key=["学习":"learning","生活":"life","校外园地":"off_campus"][section];return navigation.filter{$0.section==key && $0.visible && $0.route != nil}.sorted{($0.order,$0.id)<($1.order,$1.id)}}
    func availability(_ route: FeatureRoute) -> ServiceAvailability {
        guard let key = ServiceAvailability.key(for: route.id) ?? navigation.first(where: { $0.actionId == route.id })?.featureKey else { return ServiceAvailability() }
        return ServiceAvailability(flag: flags[key] ?? .null)
    }
    var requiresUpdate:Bool{release["platform"].text=="ios" && release["published"].boolean && release["bundleId"].text==Bundle.main.bundleIdentifier && release["minimumBuildNumber"].number>(Double(Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "1") ?? 1)}
}
struct AppUpdateView:View {
    @State private var value:JSONValue = .null
    @State private var error:String?
    @State private var busy=false
    @State private var revision=0
    private var currentBuild:Double{Double(Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "1") ?? 1}
    private var storeURL:URL?{guard let url=CampusContract.externalURL(value["storeUrl"].text),url.host=="apps.apple.com" else{return nil};return url}
    var body:some View {
        ConsentGate{List {
            Section {Text("我的川农").font(.title2.bold());LabeledContent("当前版本",value:Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "0.1.0")}
            if busy{ProgressView("正在检查更新…")}
            if let error{StatusMessage(text:error)}
            else if value != .null {
                if !value["published"].boolean {Text("iOS 正式版本尚未发布").foregroundStyle(.secondary)}
                else if value["bundleId"].text != Bundle.main.bundleIdentifier {Text("当前为开发版本；正式版本信息如下。");releaseInformation}
                else if value["buildNumber"].number>currentBuild {Text("发现新版本").font(.headline);releaseInformation}
                else{Text("已是最新版本")}
            }
            Button("重新检查"){revision+=1}.frame(maxWidth:.infinity).disabled(busy)
        }}.navigationTitle("检查更新").task(id:revision){guard UserDefaults.standard.bool(forKey:PrivacyConsent.storageKey) else{return};busy=true;defer{busy=false};do{let response:JSONValue=try await APIClient().request("public/ios-release");guard response["platform"].text=="ios" else{throw APIError.invalidResponse};value=response;error=nil}catch is CancellationError{}catch{self.error="暂时无法检查 iOS 更新，请稍后重试。"}}
    }
    @ViewBuilder private var releaseInformation:some View{LabeledContent("版本",value:value["versionName"].text);Text(value["releaseNotes"].text);if let storeURL{Link("前往 App Store",destination:storeURL)}}
}

struct ServiceAvailabilityGuard: ViewModifier {
    let route: FeatureRoute
    @Environment(ProductConfiguration.self) private var configuration
    func body(content: Content) -> some View {
        let availability = configuration.availability(route)
        if availability.isOpen { content }
        else { ServiceUnavailableView(title: route.title, availability: availability) }
    }
}
extension View {
    func serviceAvailability(_ route: FeatureRoute) -> some View { modifier(ServiceAvailabilityGuard(route: route)) }
}
struct ServiceUnavailableView: View {
    let title: String
    let availability: ServiceAvailability
    var body: some View {
        VStack(spacing: 18) {
            Text(availability.title).font(.title3.weight(.medium)).foregroundStyle(.secondary).accessibilityIdentifier("service-unavailable-status")
            if !availability.message.isEmpty { Text(availability.message).multilineTextAlignment(.center) }
            if let date = availability.expectedAt { Text(availability.timeLabel + "：" + date.formatted(.dateTime.month().day().hour().minute())).font(.subheadline) }
        }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(uiColor: .systemBackground))
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
    }
}
