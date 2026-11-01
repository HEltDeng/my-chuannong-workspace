import SwiftUI

private enum MarketTheme {
    static let paper=Color(uiColor:UIColor{ $0.userInterfaceStyle == .dark ? .systemGroupedBackground : UIColor(red:247/255,green:248/255,blue:244/255,alpha:1) })
    static let green=Color(hex:0x246C50)
    static let ink=Color.primary
    static let muted=Color.secondary
}
struct MarketplaceView:View {
    var initialMine=false
    @Environment(PlatformSession.self) private var platform
    @Environment(\.scenePhase) private var phase
    @Environment(\.dynamicTypeSize) private var size
    @State private var store=RemoteContent()
    @State private var mode="sell"
    @State private var campus="全部校区"
    @State private var category="全部"
    @State private var query=""
    @State private var mine=false
    @State private var mineFilter="all"
    @State private var compose=false
    @State private var campusPicker=false
    @State private var editing:CampusRecord?
    @State private var deleting:CampusRecord?
    @State private var revision=0
    @State private var active=false
    private var items:[CampusRecord] {
        store.records.filter{item in
            if mine{return mineFilter=="all" || item["type"]==mineFilter}
            let text=[item.title,item["description"],item["category"],item["campus"]].joined(separator:" ")
            return item["type"]==mode && (campus=="全部校区" || item["campus"]==campus) && (category=="全部" || item["category"]==category) && (query.isEmpty || text.localizedCaseInsensitiveContains(query))
        }
    }
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:16) {
                HStack{Text(store.error == nil ? "审核通过后公开展示" : "连接已中断，重新连接后同步状态").font(.system(size:11));Spacer();NavigationLink("处理通知"){CommunityNotices(kind:.secondhand)}.font(.system(size:11));Button("刷新"){revision+=1}.font(.system(size:11))}.padding(10).background(MarketTheme.green.opacity(0.07),in:RoundedRectangle(cornerRadius:10))
                if mine {
                    HStack{VStack(alignment:.leading,spacing:5){Text("我的发布").font(.system(size:25,weight:.bold))};Spacer();publishButton}
                    Picker("我的发布类型",selection:$mineFilter){Text("全部").tag("all");Text("出售").tag("sell");Text("求购").tag("want")}.pickerStyle(.segmented)
                }else{
                    VStack(alignment:.leading,spacing:7){Text("闲置好物，校园新趣。").font(.system(size:27,weight:.bold))}.frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,20).padding(.vertical,18).background(Color(hex:0xE3ECDC).opacity(0.75),in:RoundedRectangle(cornerRadius:22))
                    HStack(spacing:12){tab("出售","sell");tab("求购","want");Button("我的"){mine=true}.font(.system(size:20)).foregroundStyle(.secondary);Spacer(minLength:0);Button{campusPicker=true}label:{HStack(spacing:3){Image(systemName:"mappin.and.ellipse");Text(campus);Image(systemName:"chevron.down")}.font(.system(size:12))};publishButton}
                    Divider()
                    HStack(spacing:9){Image(systemName:"magnifyingglass");TextField("搜一搜，发现需要的好物",text:$query).font(.system(size:13));if !query.isEmpty{Button{query=""}label:{Image(systemName:"xmark")}.accessibilityLabel("清空搜索")}}.padding(13).background(MarketTheme.green.opacity(0.05),in:RoundedRectangle(cornerRadius:13))
                    ScrollView(.horizontal){HStack(spacing:8){ForEach(["全部"]+CampusContract.marketplaceCategories,id:\.self){value in Button(value){category=value}.font(.system(size:12)).padding(.horizontal,12).padding(.vertical,7).foregroundStyle(category==value ? .white : .primary).background(category==value ? MarketTheme.green : ChuannongTheme.card,in:Capsule())}}}.scrollIndicators(.hidden)
                }
                HStack{Text(mine ? "全部提交" : mode=="sell" ? "好物推荐" : "同学的心愿清单");Spacer();Text("\(items.count) 条信息")}.font(.system(size:12)).foregroundStyle(.secondary)
                if store.loading && !store.loaded{ProgressView("正在加载…").frame(maxWidth:.infinity)}
                if let error=store.error{StatusMessage(text:error)}
                if store.loaded && items.isEmpty{VStack(spacing:14){Image(systemName:"leaf").font(.title);Text(mine ? "还没有发布信息" : "暂无相关信息");if mine{Button("去发布"){compose=true}.buttonStyle(.borderedProminent)}}.foregroundStyle(.secondary).frame(maxWidth:.infinity).padding(.vertical,48)}
                if mine {ForEach(items){item in mineCard(item)}}
                else if mode=="sell" {
                    LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:12),count:size.isAccessibilitySize ? 1 : 2),spacing:12){ForEach(items){item in NavigationLink{CommunityDetail(kind:.secondhand,id:item.id,changed:{revision+=1})}label:{marketCard(item)}.buttonStyle(.plain)}}
                }else{LazyVStack(spacing:12){ForEach(items){item in NavigationLink{CommunityDetail(kind:.secondhand,id:item.id,changed:{revision+=1})}label:{wantedCard(item)}.buttonStyle(.plain)}}}
            }.padding(.horizontal,20).padding(.vertical,16)
        }.background(MarketTheme.paper).tint(MarketTheme.green).navigationTitle(mine ? "我的发布" : "二手好物").navigationBarTitleDisplayMode(.inline)
        .toolbar{if mine{ToolbarItem(placement:.topBarLeading){Button("返回广场"){mine=false}}}}
        .onAppear{active=true;if initialMine{mine=true}}
        .onDisappear{active=false}
        .task(id:"\(phase)-\(active)-\(mine)-\(revision)-\(platform.user?.id ?? "")"){
            guard phase == .active,active else{return};while !Task.isCancelled{await loadAll();do{try await Task.sleep(for:.seconds(30))}catch{return}}
        }
        .refreshable{await loadAll()}
        .sheet(isPresented:$campusPicker){NavigationStack{List{ForEach(["全部校区","雅安校区","成都校区","都江堰校区"],id:\.self){value in Button{campus=value;campusPicker=false}label:{HStack{Text(value);Spacer();if campus==value{Image(systemName:"checkmark")}}}}}.navigationTitle("选择校区")}.presentationDetents([.medium])}
        .sheet(isPresented:$compose){NavigationStack{CommunityEditor(kind:.secondhand,initialType:mode,onSuccess:{revision+=1;mine=true})}.environment(platform)}
        .sheet(item:$editing){item in NavigationStack{CommunityEditor(kind:.secondhand,existing:item,onSuccess:{revision+=1})}.environment(platform)}
        .confirmationDialog("删除发布",isPresented:Binding(get:{deleting != nil},set:{if !$0{deleting=nil}}),titleVisibility:.visible){if let deleting{Button("确认删除",role:.destructive){Task{do{_ = try await platform.perform("community/secondhand/"+deleting.id,method:"DELETE");self.deleting=nil;revision+=1}catch{store.error=error.localizedDescription}}}}}message:{Text("确定删除“\(deleting?.title ?? "")”？删除后无法恢复。")}
    }
    private var publishButton:some View{Button{compose=true}label:{Image(systemName:"plus").font(.system(size:23)).frame(width:38,height:38).overlay(Circle().stroke(MarketTheme.green,lineWidth:1.4))}.accessibilityLabel("发布好物")}
    private func tab(_ title:String,_ value:String)->some View{Button{mode=value;category="全部"}label:{VStack(spacing:8){Text(title).font(.system(size:20,weight:mode==value ? .bold : .regular));Capsule().fill(mode==value ? MarketTheme.green : .clear).frame(height:4)}}.fixedSize().foregroundStyle(mode==value ? MarketTheme.green : .secondary)}
    private func marketCard(_ item:CampusRecord)->some View{VStack(alignment:.leading,spacing:0){CommunityPhoto(path:item.imagePaths.first).aspectRatio(1.05,contentMode:.fit).clipped();VStack(alignment:.leading,spacing:7){Text(item.title).font(.system(size:14,weight:.semibold)).lineLimit(1);Text(item["description"]).font(.system(size:11)).foregroundStyle(.secondary).lineLimit(1);person(item).padding(.top,7);Text(item["campus"]).font(.system(size:10)).foregroundStyle(.secondary)}.padding(12)}.background(ChuannongTheme.card,in:RoundedRectangle(cornerRadius:16)).clipShape(RoundedRectangle(cornerRadius:16))}
    private func wantedCard(_ item:CampusRecord)->some View{VStack(alignment:.leading,spacing:13){person(item);Text(item.title).font(.system(size:17,weight:.semibold));Text(item["description"]).font(.system(size:13)).foregroundStyle(.secondary);Divider();HStack{Text(item["campus"]).font(.system(size:11)).foregroundStyle(.secondary);Spacer();Text("查看联系方式").font(.system(size:12,weight:.semibold)).foregroundStyle(MarketTheme.green)}}.padding(18).background(ChuannongTheme.card,in:RoundedRectangle(cornerRadius:18))}
    private func person(_ item:CampusRecord)->some View{HStack(spacing:6){Text(String(item["ownerName"].prefix(1))).font(.system(size:11)).frame(width:24,height:24).background(MarketTheme.green.opacity(0.08),in:Circle());Text(item["ownerName"]).lineLimit(1);Spacer(minLength:0);Text(relativeTime(item.value["createdAt"].number)).font(.system(size:10))}.font(.system(size:11)).foregroundStyle(.secondary)}
    private func mineCard(_ item:CampusRecord)->some View{VStack(alignment:.leading,spacing:13){NavigationLink{CommunityDetail(kind:.secondhand,id:item.id,changed:{revision+=1})}label:{HStack(alignment:.top,spacing:13){if item["type"]=="sell"{CommunityPhoto(path:item.imagePaths.first).frame(width:75,height:75).clipShape(RoundedRectangle(cornerRadius:12))};VStack(alignment:.leading,spacing:5){HStack{Text(item["type"]=="sell" ? "出售" : "求购");ReviewStatusBadge(status:item["status"])}.font(.system(size:11));Text(item.title).font(.system(size:15,weight:.semibold));Text(item["description"]).font(.system(size:12)).foregroundStyle(.secondary).lineLimit(2)}}}.buttonStyle(.plain);Text(item["campus"]+" · "+item["category"]).font(.system(size:10)).foregroundStyle(.secondary);if !item["moderationNote"].isEmpty{Text("处理原因："+item["moderationNote"]).font(.system(size:12)).foregroundStyle(.red)};Divider();HStack{Spacer();Button(item["status"]=="VIOLATION" ? "修改并重新提交" : "编辑"){editing=item};Button("删除",role:.destructive){deleting=item}}.font(.system(size:12)).buttonStyle(.bordered)}.padding(15).background(ChuannongTheme.card,in:RoundedRectangle(cornerRadius:17))}
    private func loadAll()async{await store.load("community/secondhand",session:platform,query:["mine":mine ? "true" : "false"],allPages:true)}
    private func relativeTime(_ milliseconds:Double)->String{guard milliseconds>0 else{return ""};let minutes=max(0,Int((Date.now.timeIntervalSince1970-milliseconds/1000)/60));if minutes<1{return "刚刚"};if minutes<60{return "\(minutes)分钟前"};if minutes<1440{return "\(minutes/60)小时前"};return Date(timeIntervalSince1970:milliseconds/1000).formatted(.dateTime.month().day())}
}
struct ReviewStatusBadge:View{
    let status:String
    var body:some View{Text(["PENDING":"待审核","PUBLISHED":"已发布","VIOLATION":"违规"][status] ?? status).font(.system(size:11)).padding(.horizontal,8).padding(.vertical,3).foregroundStyle(status=="VIOLATION" ? .red : status=="PENDING" ? .orange : ChuannongTheme.green).background((status=="VIOLATION" ? Color.red : status=="PENDING" ? .orange : ChuannongTheme.green).opacity(0.09),in:RoundedRectangle(cornerRadius:7))}
}
struct CommunityPhoto:View {
    var path:String?
    var body:some View{GeometryReader{geometry in Group{if let path,path.hasPrefix("data:image/"),let data=Data(base64Encoded:String(path.split(separator:",",maxSplits:1).last ?? "")),let image=UIImage(data:data){Image(uiImage:image).resizable().scaledToFill()}else if let path,let url=CampusContract.imageURL(path){AsyncImage(url:url){phase in if let image=phase.image{image.resizable().scaledToFill()}else{placeholder}}}else{placeholder}}.frame(width:geometry.size.width,height:geometry.size.height).clipped()}}
    private var placeholder:some View{VStack(spacing:9){Image(systemName:"photo").font(.system(size:34));Text("暂无图片").font(.system(size:11))}.foregroundStyle(.secondary).frame(maxWidth:.infinity,maxHeight:.infinity).background(ChuannongTheme.green.opacity(0.07))}
}
