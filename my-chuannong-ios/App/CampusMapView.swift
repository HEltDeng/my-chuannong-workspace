import SwiftUI
import Observation
#if canImport(MAMapKit) && !targetEnvironment(simulator)
@preconcurrency import MAMapKit
@preconcurrency import AMapSearchKit
@preconcurrency import AMapFoundationKit
#endif

@MainActor enum AMapConfiguration {
    static var key:String{let v=Bundle.main.object(forInfoDictionaryKey:"AMapAPIKey") as? String ?? "";return v.hasPrefix("$(") ? "" : v.trimmingCharacters(in:.whitespacesAndNewlines)}
    static func initialize() {
        guard UserDefaults.standard.bool(forKey:"amap.consent.v1"),!key.isEmpty else{return}
        #if canImport(MAMapKit) && !targetEnvironment(simulator)
        MAMapView.updatePrivacyShow(.didShow,privacyInfo:.didContain);MAMapView.updatePrivacyAgree(.didAgree)
        AMapSearchAPI.updatePrivacyShow(.didShow,privacyInfo:.didContain);AMapSearchAPI.updatePrivacyAgree(.didAgree)
        AMapServices.shared().apiKey=key;AMapServices.shared().enableHTTPS=true
        #endif
    }
}
@MainActor @Observable final class CampusMapStore {
    private(set) var data:[MapCampus:CampusMapData]=[:]
    private(set) var loading=false
    var error:String?
    private struct Snapshot:Decodable{var verifiedAtEpochMs:Double;var campuses:[String:CampusMapData]}
    private struct Extra:Decodable {var id:String;var name:String;var lat:Double;var lng:Double;var campus:String}
    private struct Extras:Decodable{var places:[Extra]}
    private struct Cache:Codable{var date:Date;var data:CampusMapData}
    var places:[MapPlace]{MapCampus.allCases.flatMap{campus in data[campus].map{CampusCatalogue.places($0,campus:campus)} ?? []}}
    func load(selected:MapCampus,refresh:Bool=false) async {
        guard !loading else{return};loading=true;defer{loading=false};error=nil
        let bundle=Bundle.main.url(forResource:"amap-campus-snapshot",withExtension:"json").flatMap{try? Data(contentsOf:$0)}.flatMap{try? JSONDecoder().decode(Snapshot.self,from:$0)}
        for campus in [selected]+MapCampus.allCases.filter({$0 != selected}) {
            do {
                try Task.checkCancellation()
                if !refresh,let cached=try? JSONDecoder().decode(Cache.self,from:Data(contentsOf:cacheURL(campus))),Date.now.timeIntervalSince(cached.date)>=0,Date.now.timeIntervalSince(cached.date)<7*86400{data[campus]=withExtras(cached.data,campus:campus);continue}
                if !refresh,let bundle,abs(Date.now.timeIntervalSince1970-bundle.verifiedAtEpochMs/1000)<7*86400,let value=bundle.campuses[campus.id]{data[campus]=withExtras(value,campus:campus);continue}
                #if canImport(MAMapKit) && !targetEnvironment(simulator)
                AMapConfiguration.initialize();let reader=AMapPOIReader();let value=try await reader.load(campus)
                try Task.checkCancellation();let complete=withExtras(value,campus:campus);data[campus]=complete
                try? JSONEncoder().encode(Cache(date:.now,data:complete)).write(to:cacheURL(campus),options:.atomic)
                #else
                if let value=bundle?.campuses[campus.id]{data[campus]=withExtras(value,campus:campus)}
                error="当前模拟器不支持此版本高德地图 SDK；地点目录来自已核对的本机数据。请在 iPhone 上验证实时地图。"
                #endif
            }catch is CancellationError{return}catch{self.error="高德地点加载失败，请重试；已加载地点保留。"}
        }
    }
    private func cacheURL(_ campus:MapCampus)->URL{FileManager.default.urls(for:.cachesDirectory,in:.userDomainMask)[0].appending(path:"amap-"+campus.id+".json")}
    private func withExtras(_ value:CampusMapData,campus:MapCampus)->CampusMapData {
        guard let url=Bundle.main.url(forResource:"amap-verified-buildings",withExtension:"json"),let raw=try? Data(contentsOf:url),let extras=try? JSONDecoder().decode(Extras.self,from:raw) else{return value}
        let extra=extras.places.filter{$0.campus==campus.id}.map{MapPOI(id:$0.id,name:$0.name,lat:$0.lat,lng:$0.lng)}.filter{$0.valid && $0.distance(to:value.center)<1800}
        var seen=Set<String>();return CampusMapData(center:value.center,pois:(value.pois+extra).filter{seen.insert($0.id).inserted})
    }
}
@MainActor @Observable final class CampusCamera {
    #if canImport(MAMapKit) && !targetEnvironment(simulator)
    weak var map:MAMapView?
    #endif
    var error:String?
    func reset(_ center:MapPOI?){
        #if canImport(MAMapKit) && !targetEnvironment(simulator)
        guard let center else{return};map?.setCenter(CLLocationCoordinate2D(latitude:center.lat,longitude:center.lng),animated:true);map?.setZoomLevel(16.6,animated:true);map?.setCameraDegree(45,animated:true,duration:0.5)
        #endif
    }
    func pitch(){
        #if canImport(MAMapKit) && !targetEnvironment(simulator)
        if let map{map.setCameraDegree(map.cameraDegree>5 ? 0 : 45,animated:true,duration:0.5)}
        #endif
    }
    func rotate(){
        #if canImport(MAMapKit) && !targetEnvironment(simulator)
        if let map{map.setRotationDegree(map.rotationDegree+30,animated:true,duration:0.5)}
        #endif
    }
    func zoom(_ amount:Double){
        #if canImport(MAMapKit) && !targetEnvironment(simulator)
        if let map{map.setZoomLevel(min(20,max(3,map.zoomLevel+amount)),animated:true)}
        #endif
    }
    func focus(_ poi:MapPOI){
        #if canImport(MAMapKit) && !targetEnvironment(simulator)
        map?.setCenter(CLLocationCoordinate2D(latitude:poi.lat,longitude:poi.lng),animated:true);map?.setZoomLevel(18,animated:true)
        #endif
    }
}
struct CampusMapView:View {
    @AppStorage("amap.consent.v1") private var agreed=false
    @Environment(\.scenePhase) private var phase
    @Environment(\.colorScheme) private var colorScheme
    @State private var consentDialog=false
    @State private var privacy=false
    @State private var campus=MapCampus.chengdu
    @State private var category=MapCategory.all
    @State private var query=""
    @State private var selected:String?
    @State private var store=CampusMapStore()
    @State private var camera=CampusCamera()
    @State private var expanded=false
    @FocusState private var focused:Bool
    private var results:[MapPlace]{CampusCatalogue.visible(store.places,campus:campus,category:category,query:query).sorted{query.isEmpty && $0.id==selected && $1.id != selected}}
    var body:some View {
        ConsentGate {
            if !agreed || AMapConfiguration.key.isEmpty {
                VStack(spacing:20){Image(systemName:"map").font(.system(size:52)).foregroundStyle(ChuannongTheme.green);Text(AMapConfiguration.key.isEmpty ? "高德地图暂未配置" : "使用高德地图查看校园").font(.title2.bold());Text(AMapConfiguration.key.isEmpty ? "iOS 地图配置完成后，可使用三校区地图与地点搜索。" : "查看校内建筑、搜索地点，支持俯视与立体视角。").foregroundStyle(.secondary).multilineTextAlignment(.center);Button("启用高德地图"){consentDialog=true}.buttonStyle(.borderedProminent).disabled(AMapConfiguration.key.isEmpty)}.padding(28)
            }else{mapContent}
        }.navigationTitle("校园地图").navigationBarTitleDisplayMode(.inline)
        .alert("使用高德校园地图",isPresented:$consentDialog){Button("同意并启用"){agreed=true};Button("查看隐私政策"){privacy=true};Button("暂不启用",role:.cancel){}}message:{Text("高德地图由北京高德图强科技有限公司提供。联网加载底图与校园地点时，SDK 会处理地图视野、地点查询词、IP、设备与系统参数等必要信息。本功能不启用手机定位，不读取学校账号或学习数据。")}
        .sheet(isPresented:$privacy){SafariPage(url:URL(string:"https://lbs.amap.com/pages/privacy/")!)}
        .task(id:"\(phase)-\(agreed)"){guard phase == .active,agreed,!AMapConfiguration.key.isEmpty else{return};AMapConfiguration.initialize();await store.load(selected:campus)}
    }
    private var mapContent:some View {
        GeometryReader{geometry in
            ZStack(alignment:.top){
                #if canImport(MAMapKit) && !targetEnvironment(simulator)
                NativeCampusMap(center:store.data[campus]?.center,places:store.places.filter{$0.campus==campus},visible:Set(results.map(\.id)),selected:selected,camera:camera,dark:colorScheme == .dark,onSelect:select)
                #else
                ChuannongTheme.green.opacity(0.08).overlay{Text("实时底图需在支持的 iPhone 环境打开").font(.footnote).foregroundStyle(.secondary)}
                #endif
                VStack(spacing:12){
                    Text("SICAU  /  探索你的校园").font(.system(size:10,weight:.medium)).tracking(1).foregroundStyle(.secondary)
                    Picker("校区",selection:$campus){ForEach(MapCampus.allCases){Text($0.title).tag($0)}}.pickerStyle(.segmented).padding(6).background(ChuannongTheme.card,in:RoundedRectangle(cornerRadius:16))
                    HStack{Spacer();VStack(spacing:10){control("scope","查看全校"){camera.reset(store.data[campus]?.center)};control("square.3.layers.3d","切换俯视与立体"){camera.pitch()};control("rotate.right","旋转地图"){camera.rotate()};control("plus","放大地图"){camera.zoom(0.5)};control("minus","缩小地图"){camera.zoom(-0.5)}}}.opacity(expanded ? 0 : 1)
                    Spacer()
                }.padding(16)
                VStack{Spacer();placePanel.frame(height:expanded ? max(260,geometry.size.height-100) : min(282,geometry.size.height*0.48)).background(ChuannongTheme.card,in:UnevenRoundedRectangle(topLeadingRadius:26,topTrailingRadius:26)).shadow(color:.black.opacity(0.09),radius:10,y:-3)}
            }
        }.onChange(of:campus){_,_ in if let selected,store.places.contains(where:{$0.id==selected && $0.campus==campus}) { return };query="";category = .all;selected=nil;focused=false;camera.reset(store.data[campus]?.center)}
    }
    private var placePanel:some View {
        VStack(spacing:12){
            Button{focused=false;expanded.toggle()}label:{Capsule().fill(.secondary.opacity(0.3)).frame(width:34,height:4).frame(maxWidth:.infinity).frame(height:24)}.accessibilityLabel("展开或收起地点面板")
            HStack{Image(systemName:"magnifyingglass").foregroundStyle(.secondary);TextField("搜索地点、楼号、简称",text:$query).focused($focused).submitLabel(.search).onSubmit{focused=false};if !query.isEmpty{Button{query=""}label:{Image(systemName:"xmark.circle.fill")}.accessibilityLabel("清空搜索")}}.padding(13).background(ChuannongTheme.green.opacity(0.06),in:RoundedRectangle(cornerRadius:16)).padding(.horizontal,18)
            ScrollView(.horizontal){HStack(spacing:8){ForEach(MapCategory.allCases.filter{item in item == .all || store.places.contains(where:{$0.campus==campus && $0.category==item})}){item in Button(item.title){query="";category=item;focused=false}.font(.system(size:13,weight:.medium)).padding(.horizontal,14).padding(.vertical,10).foregroundStyle(category==item && query.isEmpty ? .white : .secondary).background(category==item && query.isEmpty ? ChuannongTheme.green : .secondary.opacity(0.07),in:RoundedRectangle(cornerRadius:12))}}.padding(.horizontal,18)}.scrollIndicators(.hidden)
            HStack{Text(query.isEmpty ? "探索"+campus.title : "全部校区的搜索结果");Spacer();Text("\(results.count) 个地点")}.font(.caption).foregroundStyle(.secondary).padding(.horizontal,20)
            ScrollView{LazyVStack(spacing:8){
                if let error=store.error ?? camera.error{StatusMessage(text:error);Button("重试"){Task{await store.load(selected:campus,refresh:true)}}}
                if results.isEmpty{if store.loading{ProgressView("正在加载高德校园地点…")}else{Text("没有找到相关地点");Text("试试楼号、简称，或“食堂”").font(.caption).foregroundStyle(.secondary)}}
                ForEach(results){place in Button{select(place)}label:{HStack(spacing:12){Circle().fill(Color(hex:place.category.color)).frame(width:10,height:10);VStack(alignment:.leading,spacing:5){Text(place.poi.name).font(.subheadline.weight(.semibold));Text(place.campus.title+" · "+place.category.title).font(.caption).foregroundStyle(.secondary)};Spacer();if selected==place.id{Image(systemName:"checkmark.circle.fill").foregroundStyle(ChuannongTheme.green)}}.padding(14).background(selected==place.id ? ChuannongTheme.green.opacity(0.09) : .secondary.opacity(0.04),in:RoundedRectangle(cornerRadius:15))}.buttonStyle(.plain)}
                Text("名称与位置来自高德地图").font(.system(size:11)).foregroundStyle(.secondary)
            }.padding(.horizontal,18).padding(.bottom,18)}
        }.onChange(of:focused){_,value in if value{expanded=true}}
    }
    private func control(_ icon:String,_ label:String,action:@escaping()->Void)->some View{Button(action:action){Image(systemName:icon).font(.system(size:20)).frame(width:46,height:46).background(ChuannongTheme.card,in:RoundedRectangle(cornerRadius:15))}.accessibilityLabel(label)}
    private func select(_ place:MapPlace){focused=false;query="";campus=place.campus;category=place.category;selected=place.id;expanded=false;camera.focus(place.poi)}
}

#if canImport(MAMapKit) && !targetEnvironment(simulator)
private final class CampusAnnotation:MAPointAnnotation {var place:MapPlace?}
struct NativeCampusMap:UIViewRepresentable {
    var center:MapPOI?;var places:[MapPlace];var visible:Set<String>;var selected:String?;let camera:CampusCamera;var dark:Bool;var onSelect:(MapPlace)->Void
    func makeCoordinator()->Coordinator{Coordinator(self)}
    func makeUIView(context:Context)->MAMapView{AMapConfiguration.initialize();let map=MAMapView(frame:.zero);map.delegate=context.coordinator;map.showsUserLocation=false;map.isShowsBuildings=true;map.showsCompass=false;map.showsScale=true;map.isRotateEnabled=true;map.isRotateCameraEnabled=true;camera.map=map;return map}
    func updateUIView(_ map:MAMapView,context:Context){
        context.coordinator.parent=self;map.mapType=dark ? .standardNight : .standard
        if context.coordinator.centerID != center?.id{context.coordinator.centerID=center?.id;camera.reset(center)}
        let signature=places.filter{visible.contains($0.id)}.map(\.id).joined(separator:"|")+"#"+(selected ?? "")
        if context.coordinator.signature != signature{context.coordinator.signature=signature;map.removeAnnotations(map.annotations);let annotations=places.filter{visible.contains($0.id)}.map{place->CampusAnnotation in let a=CampusAnnotation();a.place=place;a.coordinate=CLLocationCoordinate2D(latitude:place.poi.lat,longitude:place.poi.lng);a.title=place.poi.name;return a};map.addAnnotations(annotations)}
    }
    static func dismantleUIView(_ map:MAMapView,coordinator:Coordinator){map.delegate=nil;map.showsUserLocation=false;map.removeAnnotations(map.annotations);coordinator.parent.camera.map=nil}
    @MainActor final class Coordinator:NSObject,@preconcurrency MAMapViewDelegate {
        var parent:NativeCampusMap;var signature="";var centerID:String?
        init(_ parent:NativeCampusMap){self.parent=parent}
        func mapView(_ mapView:MAMapView!,viewFor annotation:MAAnnotation!)->MAAnnotationView!{
            guard let a=annotation as? CampusAnnotation,let place=a.place else{return nil}
            guard let view=(mapView.dequeueReusableAnnotationView(withIdentifier:"campus") as? MAPinAnnotationView) ?? MAPinAnnotationView(annotation:a,reuseIdentifier:"campus") else{return nil}
            view.annotation=a;view.canShowCallout=true;view.animatesDrop=false;view.image=UIImage(systemName:place.id==parent.selected ? "mappin.circle.fill" : "circle.fill")?.withTintColor(UIColor(Color(hex:place.category.color)),renderingMode:.alwaysOriginal);return view
        }
        func mapView(_ mapView:MAMapView!,didSelect view:MAAnnotationView!){if let a=view.annotation as? CampusAnnotation,let place=a.place{parent.onSelect(place)}}
        func mapViewDidFailLoadingMap(_ mapView:MAMapView!,withError error:Error!){parent.camera.error="高德地图加载失败，请检查网络与地图授权后重试。"}
    }
}
@MainActor final class AMapPOIReader:NSObject,@preconcurrency AMapSearchDelegate {
    private let api=AMapSearchAPI()!
    private struct FoundPOI:Sendable{let poi:MapPOI;let children:[MapPOI]}
    private var continuation:CheckedContinuation<[FoundPOI],Error>?
    private var active:NSObject?
    private var timeout:Task<Void,Never>?
    private static var nextRequest=Date.distantPast
    override init(){super.init();api.delegate=self}
    func load(_ campus:MapCampus)async throws->CampusMapData{
        let root=AMapPOIKeywordsSearchRequest();root.keywords="四川农业大学(\(campus.title))";root.city=campus == .yaan ? "雅安市" : "成都市";root.cityLimit=true;root.offset=25
        let roots=try await perform(root)
        let names=(campus == .yaan ? [root.keywords!,"四川农业大学(雅安本部)","四川农业大学"] : [root.keywords!]).map{CampusCatalogue.normalize($0).replacingOccurrences(of:"[()（）\\s]",with:"",options:.regularExpression)}
        guard let center=roots.first(where:{names.contains(CampusCatalogue.normalize($0.poi.name).replacingOccurrences(of:"[()（）\\s]",with:"",options:.regularExpression))})?.poi else{throw APIError.server(422,"未找到校区地点")}
        var items:[String:MapPOI]=[:]
        func collect(_ values:[FoundPOI]){for item in values{let p=item.poi;if CampusCatalogue.belongs(p,campus:campus,center:center){items[p.id]=p;for child in item.children where CampusCatalogue.belongs(child,campus:campus,center:center,child:true){items[child.id]=child}}}}
        collect(roots)
        for keyword in ["四川农业大学","教学楼","教学实验楼","公寓","宿舍","食堂","餐厅","图书馆","操场","体育馆","学院","楼","实验","体育","校门"] {
            var seen=Set<String>()
            for page in 1...8 {
                try Task.checkCancellation();let request=AMapPOIAroundSearchRequest();request.keywords=keyword;request.location=AMapGeoPoint.location(withLatitude:CGFloat(center.lat),longitude:CGFloat(center.lng));request.radius=campus == .yaan ? 1800 : 1200;request.offset=25;request.page=page;request.showFieldsType = .children
                let values=try await perform(request);collect(values);let added=values.filter{seen.insert($0.poi.id).inserted}.count;if values.count<25 || added==0{break}
            }
        }
        return CampusMapData(center:center,pois:Array(items.values))
    }
    private func geo(_ p:AMapPOI)->MapPOI?{guard let location=p.location else{return nil};return MapPOI(id:p.uid ?? "",name:p.name ?? "",lat:Double(location.latitude),lng:Double(location.longitude),address:p.address ?? "",typeCode:p.typecode ?? "")}
    private func perform(_ request:AMapPOISearchBaseRequest)async throws->[FoundPOI]{
        let delay=max(0,Self.nextRequest.timeIntervalSinceNow);Self.nextRequest=Date.now.addingTimeInterval(delay+1.1);if delay>0{try await Task.sleep(for:.seconds(delay))}
        return try await withTaskCancellationHandler{try await withCheckedThrowingContinuation{c in continuation=c;active=request;timeout=Task{try? await Task.sleep(for:.seconds(20));guard !Task.isCancelled else{return};finish(.failure(URLError(.timedOut)))};if let request=request as? AMapPOIKeywordsSearchRequest{api.aMapPOIKeywordsSearch(request)}else if let request=request as? AMapPOIAroundSearchRequest{api.aMapPOIAroundSearch(request)}}}onCancel:{Task{@MainActor in self.finish(.failure(CancellationError()))}}
    }
    func onPOISearchDone(_ request:AMapPOISearchBaseRequest!,response:AMapPOISearchResponse!){
        guard request === active else{return}
        let values=(response.pois ?? []).compactMap{item->FoundPOI? in
            guard let poi=geo(item) else{return nil}
            let children=(item.subPOIs ?? []).compactMap{sub->MapPOI? in guard let point=sub.location else{return nil};return MapPOI(id:sub.uid ?? "",name:sub.name ?? "",lat:Double(point.latitude),lng:Double(point.longitude),address:sub.address ?? "")}
            return FoundPOI(poi:poi,children:children)
        }
        finish(.success(values))
    }
    func aMapSearchRequest(_ request:Any!,didFailWithError error:Error!){guard (request as? NSObject) === active else{return};finish(.failure(error ?? URLError(.unknown)))}
    private func finish(_ result:Result<[FoundPOI],Error>){guard let c=continuation else{return};continuation=nil;active=nil;timeout?.cancel();timeout=nil;api.cancelAllRequests();c.resume(with:result)}
}
#endif
