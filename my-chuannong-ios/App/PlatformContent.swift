import SwiftUI
import Observation

@MainActor @Observable final class RemoteContent {
    private(set) var value = JSONValue.null
    private(set) var loading = false
    private(set) var loaded = false
    var error: String?
    private var generation = 0
    private var scope: String?
    var records: [CampusRecord] { value.records }
    func load(_ path: String, session: PlatformSession, query: [String: String] = [:], append: Bool = false, allPages: Bool = false) async {
        let owner = session.user?.id
        let nextScope = (owner ?? "") + "|" + path + "|" + query.filter { $0.key != "offset" && $0.key != "limit" }.sorted { $0.key < $1.key }.map { $0.key + "=" + $0.value }.joined(separator: "&")
        if scope != nextScope { value = .null; loaded = false; error = nil; scope = nextScope }
        generation += 1; let epoch = generation; loading = true
        defer { if epoch == generation { loading = false } }
        do {
            var parameters = query
            if allPages { parameters["limit"] = "100"; parameters["offset"] = "0" }
            var result = try await session.perform(path, query: parameters)
            if !result["accountId"].text.isEmpty,result["accountId"].text != owner {throw APIError.server(403,"账号已变化，请重新读取")}
            if allPages {
                var rows = result.records
                while Double(rows.count) < result["total"].number {
                    try Task.checkCancellation(); guard epoch == generation, owner == session.user?.id else { return }
                    parameters["offset"] = String(rows.count)
                    let page = try await session.perform(path, query: parameters)
                    let known = Set(rows.map(\.id)); let additions = page.records.filter { !known.contains($0.id) }
                    guard !additions.isEmpty else { throw APIError.invalidResponse }
                    rows += additions
                    if case .object(var values) = page { values["items"] = .array(rows.map(\.value)); result = .object(values) }
                }
            }
            try Task.checkCancellation(); guard epoch == generation, owner == session.user?.id else { return }
            if append, case .object(var next) = result {
                let existing = Set(records.map(\.id))
                next["items"] = .array(records.map(\.value) + result.records.filter { !existing.contains($0.id) }.map(\.value))
                value = .object(next)
            } else { value = result }
            loaded = true; error = nil
        } catch is CancellationError {} catch {
            if epoch == generation {
                if case APIError.server(let status, _) = error, [401,403,404,410].contains(status) { value = .null; loaded = false }
                self.error = error.localizedDescription
            }
        }
    }
}

struct RemoteStatus: View {
    let store: RemoteContent
    var empty = "暂无内容"
    var body: some View {
        if store.loading { ProgressView("正在加载…") }
        if let error = store.error { StatusMessage(text: error) }
        if !empty.isEmpty && store.loaded && !store.loading && store.records.isEmpty { Text(empty).foregroundStyle(.secondary) }
    }
}

struct RecordImages: View {
    let paths:[String]
    @State private var selected:Int?
    var body:some View {
        ForEach(Array(paths.enumerated()),id:\.offset){index,path in
            if let url=CampusContract.imageURL(path){
                Button{selected=index}label:{VStack(spacing:8){AsyncImage(url:url){phase in
                    if let image=phase.image{image.resizable().scaledToFit()}
                    else if phase.error != nil{Label("图片暂时无法加载",systemImage:"photo").foregroundStyle(.secondary)}
                    else{ProgressView().frame(maxWidth:.infinity,minHeight:100)}
                };Text("\(index+1) / \(paths.count) · 点击查看大图").font(.caption).foregroundStyle(.secondary)}.clipShape(RoundedRectangle(cornerRadius:16))}.buttonStyle(.plain)
            }
        }.fullScreenCover(isPresented:Binding(get:{selected != nil},set:{if !$0{selected=nil}})){PhotoGallery(paths:paths,index:selected ?? 0)}
    }
}

struct LibraryView: View {
    var initialMode = "全部"
    @Environment(PlatformSession.self) private var platform
    @State private var store = RemoteContent()
    @State private var mode = "全部"
    @State private var query = ""
    @State private var category = "全部分类"
    @State private var categories: [String] = []
    @State private var appeared = false
    @State private var revision = 0
    private var filters: [String: String] {
        var result: [String: String] = ["q": query]
        if mode == "我的收藏" { result["favorites"] = "true" }
        if mode == "最近浏览" { result["recent"] = "true" }
        if category != "全部分类" { result["category"] = category }; return result
    }
    private var empty: String { mode == "我的收藏" ? "还没有收藏资料" : mode == "最近浏览" ? "还没有浏览记录" : "没有找到匹配的资料" }
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) { Image(systemName: "magnifyingglass").foregroundStyle(.secondary); TextField("搜索标题、简介和标签", text: $query).onChange(of: query) { _, text in query = String(text.prefix(100)) } }
                .padding(14).background(ChuannongTheme.card, in: RoundedRectangle(cornerRadius: 14)).padding(.horizontal, 18)
            ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 8) { ForEach(["全部", "最近浏览", "我的收藏"], id: \.self) { value in FilterPill(value == "全部" ? "匹配资料" : value, selected: mode == value) { mode = value } } }.padding(.horizontal, 18) }
            if !categories.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 8) { ForEach(["全部分类"] + categories, id: \.self) { value in FilterPill(value, selected: category == value) { category = value } } }.padding(.horizontal, 18) }
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    RemoteStatus(store: store, empty: empty)
                    ForEach(store.records) { item in
                        NavigationLink { LibraryDetail(id: item.id, onChange: { revision += 1 }) } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack { Text(item["category"]).font(.system(size: 12, weight: .bold)).padding(.horizontal, 10).padding(.vertical, 5).background(ChuannongTheme.green.opacity(0.1), in: Capsule()); Spacer(); if item.value["isFavorite"].boolean { Image(systemName: "bookmark.fill").accessibilityLabel("已收藏") } }.foregroundStyle(ChuannongTheme.green)
                                Text(item.title).font(.system(size: 18, weight: .bold)).foregroundStyle(.primary)
                                Text(item["summary"]).font(.system(size: 13)).lineSpacing(6).lineLimit(3).foregroundStyle(.secondary)
                                Text((item["sourceLabel"].isEmpty ? item["publisherLabel"] : item["sourceLabel"]) + " · " + (item["audienceScope"].isEmpty ? "适用范围见详情" : item["audienceScope"]))
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                            }.padding(17).frame(maxWidth: .infinity, alignment: .leading).background(ChuannongTheme.card, in: RoundedRectangle(cornerRadius: 20))
                        }.buttonStyle(.plain)
                    }
                }.padding(18)
            }.refreshable { await load() }
        }.padding(.top, 8).background(ChuannongTheme.background).navigationTitle("资料库").navigationBarTitleDisplayMode(.inline).serviceAvailability(.document)
        .onAppear { if !appeared { mode = initialMode == "收藏" ? "我的收藏" : initialMode == "最近" ? "最近浏览" : initialMode; appeared = true } }
        .task(id: "\(query)|\(mode)|\(category)|\(revision)|\(platform.user?.id ?? "")") {
            do { try await Task.sleep(for: .milliseconds(220)); try Task.checkCancellation(); await load() } catch {}
        }
    }
    private func load() async {
        await store.load("library", session: platform, query: filters, allPages: true)
        if category == "全部分类" && query.isEmpty && mode == "全部" && store.error == nil {
            var seen = Set<String>(); categories = store.records.map { $0["category"] }.filter { !$0.isEmpty && seen.insert($0).inserted }
        }
    }
}

struct LibraryDetail: View {
    let id: String
    var onChange: () -> Void = {}
    @Environment(PlatformSession.self) private var platform
    @State private var store = RemoteContent()
    @State private var favorite: Bool?
    @State private var busy = false
    @State private var complaint = false
    @State private var destination: URL?
    @State private var recorded = false
    @State private var message: String?
    private var item: CampusRecord { CampusRecord(store.value) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if store.loading { ProgressView() }
                if let error = store.error { StatusMessage(text: error) }
                if store.loaded {
                    if let cover = CampusContract.imageURL(item["coverUrl"]) {
                        AsyncImage(url: cover) { image in image.resizable().scaledToFill() } placeholder: { Color.secondary.opacity(0.1) }
                            .frame(height: 190).frame(maxWidth: .infinity).clipped().clipShape(RoundedRectangle(cornerRadius: 20)).accessibilityLabel(item.title + "封面")
                    }
                    VStack(alignment: .leading, spacing: 7) { Text(item["category"]).font(.system(size: 13, weight: .bold)).foregroundStyle(ChuannongTheme.green); Text(item.title).font(.system(size: 25, weight: .bold)) }
                    VStack(alignment: .leading, spacing: 10) {
                        line("简介", item["summary"], fallback: "暂无简介")
                        line("标签", item.value["tags"].list.map(\.text).joined(separator: " · "), fallback: "暂无标签")
                        line("适用范围", item["audienceScope"], fallback: "未特别限定")
                        line("发布者", item["publisherLabel"])
                        line("资料来源", item["sourceLabel"], fallback: "请查看外部页面")
                        line("发布时间", item.value["publishedAt"].number > 0 ? Date(timeIntervalSince1970: item.value["publishedAt"].number / 1000).formatted(date: .abbreviated, time: .shortened) : "未记录")
                        line("资源类型", item["resourceType"] == "EXTERNAL_LINK" ? "外部链接" : item["resourceType"])
                        line("费用", item.value["isFree"].boolean ? "免费" : "后续开放")
                    }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(ChuannongTheme.card, in: RoundedRectangle(cornerRadius: 20))
                    Text(item["usageNote"].isEmpty ? "请确认资料来源合法并遵守版权与使用规则。" : item["usageNote"]).font(.system(size: 12)).lineSpacing(6).foregroundStyle(.secondary)
                    if let message { StatusMessage(text: message) }
                    Button { if let url = CampusContract.externalURL(item["externalUrl"]) { destination = url } else { message = "资料链接不可用，请稍后重试或反馈。" } } label: {
                        Label(item.value["isFree"].boolean ? "打开资料" : "付费能力后续开放", systemImage: "arrow.up.right.square").frame(maxWidth: .infinity)
                    }.buttonStyle(.borderedProminent).disabled(!item.value["isFree"].boolean)
                    Button { complaint = true } label: { Text("侵权投诉 / 要求下架").frame(maxWidth: .infinity) }.buttonStyle(.bordered)
                }
            }.padding(18).textSelection(.enabled)
        }.background(ChuannongTheme.background).navigationTitle("资料详情").navigationBarTitleDisplayMode(.inline)
        .toolbar { if store.loaded { Button { act { let result = try await platform.perform("library/\(id)/favorite", method: "POST", body: [:]); favorite = result["isFavorite"].boolean; onChange() } } label: { Image(systemName: (favorite ?? item.value["isFavorite"].boolean) ? "bookmark.fill" : "bookmark") }.accessibilityLabel((favorite ?? item.value["isFavorite"].boolean) ? "取消收藏" : "收藏").disabled(busy) } }
        .task(id: platform.user?.id) {
            await store.load("library/\(id)", session: platform)
            if store.loaded && store.error == nil && !recorded {
                do { _ = try await platform.perform("library/\(id)/view", method: "POST", body: [:]); recorded = true; onChange() } catch { message = "浏览记录暂未保存，可继续查看资料。" }
            }
        }
        .sheet(isPresented: Binding(get: { destination != nil }, set: { if !$0 { destination = nil } })) { if let destination { SafariPage(url: destination) } }
        .sheet(isPresented: $complaint) { NavigationStack { LibraryComplaintView(id: id) { message = "投诉已提交，管理员将在后台处理" } }.environment(platform) }
    }
    private func line(_ label: String, _ value: String, fallback: String = "未提供") -> some View { VStack(alignment: .leading, spacing: 2) { Text(label).font(.system(size: 11)).foregroundStyle(.secondary); Text(value.isEmpty ? fallback : value).font(.system(size: 14)) } }
    private func act(_ operation: @escaping @MainActor () async throws -> Void) { busy = true; Task { defer { busy = false }; do { try await operation(); message = nil } catch { message = error.localizedDescription } } }
}

private struct LibraryComplaintView: View {
    let id: String; var onSuccess: () -> Void
    @Environment(PlatformSession.self) private var platform
    @Environment(\.dismiss) private var dismiss
    @State private var reason = "版权或授权问题"
    @State private var detail = ""
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        Form {
            TextField("投诉原因", text: $reason).onChange(of: reason) { _, text in reason = String(text.prefix(80)) }
            TextField("补充说明（可选）", text: $detail, axis: .vertical).lineLimit(4...8).onChange(of: detail) { _, text in detail = String(text.prefix(1000)) }
            if let error { StatusMessage(text: error) }
        }.navigationTitle("提交资料投诉").navigationBarTitleDisplayMode(.inline).interactiveDismissDisabled(busy)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(busy) }
            ToolbarItem(placement: .confirmationAction) { Button(busy ? "提交中…" : "提交") { busy = true; Task { defer { busy = false }; do { _ = try await platform.perform("library/\(id)/complaints", method: "POST", body: ["reason": .string(reason), "detail": .string(detail)]); onSuccess(); dismiss() } catch { self.error = error.localizedDescription } } }.disabled(busy || reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        }
    }
}

struct SubmissionField: Identifiable {
    let key: String; let title: String; let limit: Int; var required = false
    var id: String { key }
}

struct SubmissionForm: View {
    let title: String
    let path: String
    let fields: [SubmissionField]
    var fixed: [String: JSONValue]
    var onSuccess: () -> Void = {}
    @Environment(PlatformSession.self) private var platform
    @Environment(\.dismiss) private var dismiss
    @State private var values: [String: String] = [:]
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        Form {
            ForEach(fields) { field in
                Section(field.title + (field.required ? "（必填）" : "")) {
                    TextField(field.title, text: Binding(get: { values[field.key] ?? "" }, set: { values[field.key] = String($0.prefix(field.limit)) }), axis: .vertical).lineLimit(2...8)
                    Text("\(values[field.key]?.count ?? 0)/\(field.limit)").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let error { StatusMessage(text: error) }
        }.navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(busy)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(busy) }
            ToolbarItem(placement: .confirmationAction) { Button(busy ? "提交中…" : "提交") { submit() }.disabled(busy || fields.contains { $0.required && (values[$0.key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) }
        }
    }
    private func submit() {
        var body = fixed; for field in fields { body[field.key] = .string(values[field.key] ?? "") }
        busy = true
        Task { defer { busy = false }; do { _ = try await platform.perform(path, method: "POST", body: body); onSuccess(); dismiss() } catch { self.error = error.localizedDescription } }
    }
}

struct FeedbackView: View {
    @Environment(PlatformSession.self) private var platform
    @State private var store=RemoteContent()
    @State private var mine=false
    @State private var category="FEATURE_SUGGESTION"
    @State private var title=""
    @State private var content=""
    @State private var busy=false
    @State private var success=false
    @State private var error:String?
    @FocusState private var focused:Bool
    private let categories=[("功能建议","FEATURE_SUGGESTION"),("预约问题","RESERVATION"),("失物招领","LOST_FOUND"),("资料库","RESOURCE_LIBRARY"),("账号与安全","ACCOUNT_SECURITY"),("内容投诉","CONTENT_REPORT"),("其他","OTHER")]
    var body:some View {
        ScrollView {
            if mine { history }
            else {
                VStack(alignment:.leading,spacing:14) {
                    Text("反馈类型").font(.headline)
                    LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:7),count:3),spacing:6){ForEach(categories,id:\.1){item in Button(item.0){category=item.1}.font(.system(size:13)).frame(maxWidth:.infinity,minHeight:38).background(category==item.1 ? ChuannongTheme.green.opacity(0.13) : ChuannongTheme.card,in:RoundedRectangle(cornerRadius:10)).overlay(RoundedRectangle(cornerRadius:10).stroke(.secondary.opacity(0.18))).foregroundStyle(.primary).accessibilityAddTraits(category==item.1 ? .isSelected : [])}}
                    VStack(alignment:.leading,spacing:8){Text("反馈标题").font(.subheadline);TextField("请简要概括问题或建议",text:$title).focused($focused).padding(14).overlay(RoundedRectangle(cornerRadius:12).stroke(.secondary.opacity(0.3)));Text("\(title.count)/80").font(.caption).foregroundStyle(.secondary).frame(maxWidth:.infinity,alignment:.trailing)}
                    VStack(alignment:.leading,spacing:8){Text("反馈内容").font(.subheadline);TextField("请描述问题现象、操作步骤或建议",text:$content,axis:.vertical).lineLimit(7...12).focused($focused).padding(14).overlay(RoundedRectangle(cornerRadius:12).stroke(.secondary.opacity(0.3)));Text("\(content.count)/2000").font(.caption).foregroundStyle(.secondary).frame(maxWidth:.infinity,alignment:.trailing)}
                    if let error{Text(error).font(.system(size:13)).foregroundStyle(.red)}
                    Button(action:submit){HStack{if busy{ProgressView()};Text(busy ? "提交中…" : "提交反馈")}.frame(maxWidth:.infinity).padding(.vertical,8)}.buttonStyle(.borderedProminent).disabled(busy || title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || content.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty).padding(.vertical,18)
                }.padding(.horizontal,18).disabled(busy)
            }
        }.background(ChuannongTheme.background).navigationTitle("意见反馈").navigationBarTitleDisplayMode(.inline).scrollDismissesKeyboard(.interactively)
        .toolbar{ToolbarItem(placement:.primaryAction){Button(mine ? "提交反馈" : "我的反馈"){mine.toggle();error=nil;focused=false}.disabled(busy)}}
        .onChange(of:title){_,value in title=String(value.prefix(80));error=nil}.onChange(of:content){_,value in content=String(value.prefix(2000));error=nil}
        .task(id:"\(mine)-\(platform.user?.id ?? "")"){if mine{await reload()}}
        .alert("反馈已提交",isPresented:$success){Button("查看我的反馈"){mine=true};Button("继续",role:.cancel){}}message:{Text("管理员会跟进你的反馈，处理结果可在“我的反馈”中查看。")}
    }
    private var history:some View {
        LazyVStack(alignment:.leading,spacing:10){
            HStack{Button(store.loading ? "刷新中…" : "刷新"){Task{await reload()}}.buttonStyle(.bordered).disabled(store.loading)}.frame(maxWidth:.infinity).padding(.vertical,10)
            RemoteStatus(store:store,empty:"还没有反馈记录")
            ForEach(store.records){item in NavigationLink{FeedbackDetail(id:item.id)}label:{VStack(alignment:.leading,spacing:8){
                HStack{Text(categories.first{$0.1==item["category"]}?.0 ?? "其他");Text(item.statusLabel).fontWeight(.bold)}.font(.system(size:12)).foregroundStyle(ChuannongTheme.green)
                Text(item.title).font(.system(size:17,weight:.bold));Text(item["content"]).foregroundStyle(.secondary).lineLimit(4)
                if !item["publicReply"].isEmpty{VStack(alignment:.leading,spacing:5){Text("处理说明").font(.system(size:13,weight:.bold));Text(item["publicReply"])}.padding(12).frame(maxWidth:.infinity,alignment:.leading).background(ChuannongTheme.green.opacity(0.07),in:RoundedRectangle(cornerRadius:12))}
                else if ["RESOLVED","CLOSED"].contains(item["status"]){Text("处理说明正在同步，请稍后刷新").font(.system(size:12)).foregroundStyle(.secondary)}
                Text("提交 \(stamp(item["createdAt"])) · 更新 \(stamp(item["updatedAt"]))").font(.system(size:11)).foregroundStyle(.secondary)
            }.padding(16).frame(maxWidth:.infinity,alignment:.leading).background(ChuannongTheme.card,in:RoundedRectangle(cornerRadius:18))}.buttonStyle(.plain)}
        }.padding(.horizontal,18).padding(.bottom,28)
    }
    private func stamp(_ raw:String)->String{guard let n=Double(raw),n>0 else{return "—"};return Date(timeIntervalSince1970:n/1000).formatted(date:.abbreviated,time:.shortened)}
    private func reload() async {await store.load("feedback",session:platform)}
    private func submit(){guard !busy else{return};busy=true;error=nil;focused=false;Task{defer{busy=false};do{_ = try await platform.perform("feedback",method:"POST",body:["category":.string(category),"title":.string(title.trimmingCharacters(in:.whitespacesAndNewlines)),"content":.string(content.trimmingCharacters(in:.whitespacesAndNewlines)),"appVersion":.string(Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "0.1.0")]);title="";content="";success=true}catch{self.error=error.localizedDescription}}}
}

struct FeedbackDetail: View {
    let id: String
    @Environment(PlatformSession.self) private var platform
    @State private var store = RemoteContent()
    var body: some View {
        List {
            if store.loading { ProgressView() }; if let error = store.error { StatusMessage(text: error) }
            if store.loaded {
                Section { Text(store.value["title"].text).font(.title2.bold()); Text(store.value["content"].text).textSelection(.enabled); Text(CampusContract.statusLabel(store.value["status"].text)).foregroundStyle(ChuannongTheme.green) }
                if !store.value["publicReply"].text.isEmpty { Section("回复") { Text(store.value["publicReply"].text).textSelection(.enabled) } }
                Section("处理进度") { ForEach(Array(store.value["events"].list.enumerated()), id: \.offset) { _, event in VStack(alignment: .leading, spacing: 6) { Text(CampusContract.statusLabel(event["newStatus"].text)); Text(event["message"].text).foregroundStyle(.secondary) } } }
            }
        }.navigationTitle("反馈详情").task { await store.load("feedback/\(id)", session: platform) }
    }
}

struct NotificationsView: View {
    @Environment(PlatformSession.self) private var platform
    @State private var feed=RemoteContent()
    var body:some View {
        List {
            RemoteStatus(store:feed,empty:"暂无关注板块的新消息")
            ForEach(feed.records){item in VStack(alignment:.leading,spacing:10){Text(item.title).font(.headline);Text(item["content"]).textSelection(.enabled).font(.subheadline)}.padding(.vertical,6)}
        }.navigationTitle("服务消息").navigationBarTitleDisplayMode(.inline)
        .toolbar{ToolbarItem(placement:.primaryAction){NavigationLink{NotificationSettingsView()}label:{Image(systemName:"gearshape")}.accessibilityLabel("通知设置")}}
        .task(id:platform.user?.id){await reload()}.refreshable{await reload()}
    }
    private func reload()async{await feed.load("notifications/feed",session:platform)}
}
