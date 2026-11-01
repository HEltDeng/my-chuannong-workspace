import SwiftUI
import PhotosUI
import ImageIO
import UniformTypeIdentifiers

extension FeatureRoute {
    var communityPath: String { "community/" + (self == .secondhand ? "secondhand" : "lost-found") }
}

enum LostFoundTheme {
    static let green = Color(hex: 0x21654E)
    static let paper = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? .systemGroupedBackground : UIColor(red: 248/255, green: 250/255, blue: 247/255, alpha: 1) })
}

struct CommunityView: View {
    let kind: FeatureRoute
    var initialMine = false
    @Environment(PlatformSession.self) private var platform
    @Environment(\.scenePhase) private var phase
    @State private var store = RemoteContent()
    @State private var mine = false
    @State private var campus = "全部校区"
    @State private var type = "lost"
    @State private var status = "全部"
    @State private var query = ""
    @State private var compose = false
    @State private var active = false
    @State private var revision = 0
    private var items: [CampusRecord] {
        store.records.filter { item in
            if mine {
                return status == "全部" || (status == "进行中" && !item.value["done"].boolean) || (status == "已完成" && item.value["done"].boolean) || ["PENDING":"待审核", "PUBLISHED":"已发布", "VIOLATION":"违规"][item["status"]] == status
            }
            let text = [item.title, item["location"], item["campus"], item["description"]].joined(separator: " ")
            return !item.value["done"].boolean && item["status"] == "PUBLISHED" && item["kind"] == type && (campus == "全部校区" || item["campus"] == campus) && query.split(whereSeparator: \.isWhitespace).allSatisfy { text.localizedCaseInsensitiveContains(String($0)) }
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(store.error == nil ? "审核通过后公开展示" : "连接已中断，请重新连接后同步").font(.system(size: 11))
                Spacer(minLength: 8)
                NavigationLink("处理通知") { CommunityNotices(kind: .lost_found) }
                Button("刷新") { revision += 1 }
            }.font(.system(size: 11)).padding(12).background(LostFoundTheme.green.opacity(0.06))
            if mine {
                ScrollView(.horizontal) { HStack(spacing: 8) { ForEach(["全部", "待审核", "已发布", "违规", "进行中", "已完成"], id: \.self) { item in
                    FilterPill(item, selected: status == item, tint: LostFoundTheme.green) { status = item }
                } }.padding(.horizontal, 20).padding(.vertical, 14) }.scrollIndicators(.hidden)
            } else { discovery }
            ScrollView {
                LazyVStack(spacing: 0) {
                    if store.loading && !store.loaded { ProgressView("正在读取信息…").padding(40) }
                    if let error = store.error { StatusMessage(text: error).padding(.vertical, 20) }
                    if store.loaded && items.isEmpty { empty }
                    ForEach(items) { item in
                        NavigationLink { CommunityDetail(kind: .lost_found, id: item.id, changed: { revision += 1 }) } label: { row(item) }.buttonStyle(.plain)
                        Divider()
                    }
                    if !items.isEmpty { Text("没有更多了").font(.system(size: 12)).foregroundStyle(.secondary).padding(24) }
                }.padding(.horizontal, 20).padding(.bottom, 88)
            }.refreshable { await load() }
        }
        .background(LostFoundTheme.paper).tint(LostFoundTheme.green)
        .navigationTitle(mine ? "我的发布" : "失物招领").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(mine ? "返回广场" : "我的") { mine.toggle() } } }
        .overlay(alignment: .bottomTrailing) { if !mine { Button { compose = true } label: { Label("发布", systemImage: "plus").font(.system(size: 18, weight: .medium)).padding(.horizontal, 23).frame(height: 48) }.foregroundStyle(.white).background(LostFoundTheme.green, in: Capsule()).padding(20) } }
        .onAppear { active = true; if initialMine { mine = true } }.onDisappear { active = false }
        .task(id: "\(phase)-\(active)-\(mine)-\(revision)-\(platform.user?.id ?? "")") {
            guard phase == .active, active else { return }
            while !Task.isCancelled { await load(); do { try await Task.sleep(for: .seconds(30)) } catch { return } }
        }
        .sheet(isPresented: $compose) { NavigationStack { CommunityEditor(kind: .lost_found, initialType: type, onSuccess: { revision += 1; mine = true }) }.environment(platform) }
    }
    private var discovery: some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索物品或地点", text: $query).onChange(of: query) { _, value in if value.count > 60 { query = String(value.prefix(60)) } }
                if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark") }.accessibilityLabel("清空搜索") }
            }.padding(.horizontal, 15).frame(height: 46).background(LostFoundTheme.green.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
            HStack(spacing: 34) {
                typeButton("寻物", "lost"); typeButton("招领", "found"); Spacer(minLength: 0)
                Menu { ForEach(["全部校区", "雅安校区", "成都校区", "都江堰校区"], id: \.self) { value in Button(value) { campus = value } } } label: { HStack(spacing: 5) { Text(campus); Image(systemName: "chevron.down") }.font(.system(size: 13)) }
            }.padding(.top, 19).frame(height: 69)
            Divider()
        }.padding(.horizontal, 20).padding(.top, 10)
    }
    private func typeButton(_ label: String, _ value: String) -> some View {
        Button { type = value } label: { VStack(spacing: 12) { Text(label).font(.system(size: 20, weight: type == value ? .bold : .regular)); Capsule().fill(type == value ? LostFoundTheme.green : .clear).frame(height: 3) } }.foregroundStyle(type == value ? LostFoundTheme.green : .secondary)
    }
    private func row(_ item: CampusRecord) -> some View {
        HStack(spacing: 17) {
            CommunityPhoto(path: item.imagePaths.first).frame(width: 86, height: 90).clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 8) {
                Text(item.title).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                Label(item["campus"] + " · " + item["location"], systemImage: "mappin.and.ellipse").font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing: 6) { Text(item["date"]).font(.system(size: 11)).foregroundStyle(.secondary); if mine { Text(progress(item)).font(.system(size: 11)).foregroundStyle(LostFoundTheme.green); ReviewStatusBadge(status: item["status"]) } }
                if mine, !item["moderationNote"].isEmpty { Text("处理原因：" + item["moderationNote"]).font(.system(size: 11)).foregroundStyle(.red).lineLimit(2) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.vertical, 12).frame(minHeight: 119)
    }
    private var empty: some View {
        VStack(spacing: 14) {
            Image(systemName: mine ? "tray" : "magnifyingglass").font(.system(size: 40)).foregroundStyle(.secondary)
            Text(mine ? (status == "已完成" ? "还没有完成的记录" : "还没有发布信息") : "没有找到相关物品").font(.headline)
            Text(mine ? "寻回遗失物品，也帮好心找到回应" : "试试其他关键词，或切换校区").font(.subheadline).foregroundStyle(.secondary)
            Button(mine ? "发布一条信息" : "清除筛选") { if mine { compose = true } else { query = ""; campus = "全部校区" } }.buttonStyle(.bordered)
        }.frame(maxWidth: .infinity).padding(.vertical, 70)
    }
    private func load() async { await store.load("community/lost-found", session: platform, query: ["mine": mine ? "true" : "false"], allPages: true) }
}

struct FilterPill: View {
    let title: String
    let selected: Bool
    var tint: Color
    var action: () -> Void
    init(_ title: String, selected: Bool, tint: Color = ChuannongTheme.green, action: @escaping () -> Void) { self.title = title; self.selected = selected; self.tint = tint; self.action = action }
    var body: some View { Button(action: action) { Text(title).font(.system(size: 13, weight: selected ? .semibold : .regular)).padding(.horizontal, 13).padding(.vertical, 8).foregroundStyle(selected ? tint : .secondary).background(selected ? tint.opacity(0.12) : ChuannongTheme.card, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(tint.opacity(selected ? 0.25 : 0.1), lineWidth: 0.5)) } }
}
private func progress(_ item: CampusRecord) -> String { item.value["done"].boolean ? (item["kind"] == "lost" ? "已找回" : "已归还") : "进行中" }

struct CommunityDetail: View {
    let kind: FeatureRoute
    let id: String
    var changed: () -> Void
    @Environment(PlatformSession.self) private var platform
    @Environment(\.dismiss) private var dismiss
    @State private var store = RemoteContent()
    @State private var editing = false
    @State private var deleting = false
    @State private var contact = false
    @State private var busy = false
    @State private var revision = 0
    @State private var copied: String?
    private var item: CampusRecord { CampusRecord(store.value) }
    private var market: Bool { kind == .secondhand }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if store.loading { ProgressView() }
                if let error = store.error { StatusMessage(text: error) }
                if store.loaded {
                    if item.value["mine"].boolean { review }
                    RecordImages(paths: item.imagePaths)
                    VStack(alignment: .leading, spacing: 13) {
                        Text(market ? (item["type"] == "want" ? "求购" : "出售") : (item["kind"] == "found" ? "招领" : "寻物") + " · " + progress(item)).font(.system(size: 12, weight: .medium)).foregroundStyle(ChuannongTheme.green)
                        Text(item.title).font(.system(size: 24, weight: .bold))
                        Label(item["campus"] + " · " + item[market ? "category" : "location"], systemImage: "mappin.and.ellipse").font(.system(size: 13)).foregroundStyle(.secondary)
                        Text(market ? communityDate(item.value["createdAt"].number) : item["date"] + " · " + (item["kind"] == "found" ? "拾获" : "遗失")).font(.system(size: 12)).foregroundStyle(.secondary)
                        if market { Divider(); Text(item["description"]).font(.system(size: 14)).lineSpacing(9).textSelection(.enabled) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(market ? 22 : 0).background(market ? ChuannongTheme.card : .clear, in: RoundedRectangle(cornerRadius: 20))
                    if market { marketContact } else {
                        Divider()
                        VStack(alignment: .leading, spacing: 12) { Text("物品描述").font(.system(size: 16, weight: .semibold)); Text(item["description"].isEmpty ? "发布人暂未补充描述，可联系了解物品特征。" : item["description"]).font(.system(size: 14)).lineSpacing(8).textSelection(.enabled) }
                        Text(item["kind"] == "found" ? "领取时请核对物品特征，确认后当面交还。" : "如有相关线索，可以通过联系方式联系发布人。").font(.system(size: 12)).foregroundStyle(.secondary).padding(.vertical, 16)
                    }
                }
            }.padding(20)
        }.background(LostFoundTheme.paper)
        .navigationTitle(market ? "好物详情" : item["kind"] == "found" ? "招领详情" : "寻物详情").navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { if store.loaded { management } }
        .task(id: "\(revision)-\(platform.user?.id ?? "")") { await store.load(kind.communityPath + "/" + id, session: platform) }
        .sheet(isPresented: $editing) { NavigationStack { CommunityEditor(kind: kind, existing: item, onSuccess: { revision += 1; changed() }) }.environment(platform) }
        .sheet(isPresented: $contact) { NavigationStack { VStack(alignment: .leading, spacing: 22) { Text("联系方式").font(.title2.bold()); Text(item["contact"]).textSelection(.enabled); Button(copied ?? "复制联系方式") { UIPasteboard.general.string = item["contact"]; copied = "已复制" }.buttonStyle(.borderedProminent).frame(maxWidth:.infinity); Text("仅用于本次物品联系，请勿用于其他用途。").font(.footnote).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading).padding(24).toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { contact = false } } } }.presentationDetents([.medium]) }
        .confirmationDialog("永久删除这条发布？", isPresented: $deleting, titleVisibility: .visible) { Button("删除", role: .destructive) { perform { _ = try await platform.perform(kind.communityPath + "/" + id, method: "DELETE"); changed(); dismiss() } } } message: { Text("删除后无法恢复。") }
    }
    private var review: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack { ReviewStatusBadge(status: item["status"]); if !market { Text(item["status"] == "PUBLISHED" && !item.value["done"].boolean ? "公开列表展示中" : "公开列表不展示").font(.system(size: 12)).foregroundStyle(.secondary) } }
            if !item["moderationNote"].isEmpty { Text("处理原因：" + item["moderationNote"]).font(.system(size: 13)).foregroundStyle(.red) }
        }.padding(15).frame(maxWidth: .infinity, alignment: .leading).background(ChuannongTheme.card, in: RoundedRectangle(cornerRadius: 14))
    }
    private var marketContact: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) { Text(String(item["ownerName"].prefix(1))).font(.headline).frame(width: 40, height: 40).background(ChuannongTheme.green.opacity(0.1), in: Circle()); VStack(alignment: .leading, spacing: 4) { Text(item["ownerName"]).font(.system(size: 15, weight: .semibold)); Text(item["campus"]).font(.system(size: 12)).foregroundStyle(.secondary) } }
            ForEach([("微信", "wechat"), ("电话", "phone")], id: \.1) { name, key in if !item[key].isEmpty { HStack { VStack(alignment: .leading, spacing: 5) { Text(name).font(.caption).foregroundStyle(.secondary); Text(item[key]).textSelection(.enabled) }; Spacer(); Button("复制" + name) { UIPasteboard.general.string = item[key]; copied = "已复制" + name }.font(.system(size: 12)).buttonStyle(.bordered) } } }
            if let copied { Text(copied).font(.caption).foregroundStyle(ChuannongTheme.green) }
        }.padding(20).background(ChuannongTheme.card, in: RoundedRectangle(cornerRadius: 20))
    }
    @ViewBuilder private var management: some View {
        if item.value["mine"].boolean {
            HStack(spacing: 14) {
                Button("编辑") { editing = true }; Button("删除", role: .destructive) { deleting = true }
                if !market { Spacer(); Button(item.value["done"].boolean ? "重新开放" : item["kind"] == "lost" ? "标记已找回" : "标记已归还") { perform { _ = try await platform.perform(kind.communityPath + "/" + id, method: "PATCH", body: ["done": .bool(!item.value["done"].boolean)]); revision += 1; changed() } }.buttonStyle(.borderedProminent).disabled(item["status"] != "PUBLISHED") }
            }.font(.system(size: 14)).disabled(busy).padding(.horizontal, 20).padding(.vertical, 12).frame(maxWidth: .infinity).background(LostFoundTheme.paper)
        } else if !market { Button("联系发布人") { contact = true }.buttonStyle(.borderedProminent).frame(maxWidth: .infinity).padding(16).background(LostFoundTheme.paper) }
    }
    private func perform(_ operation: @escaping @MainActor () async throws -> Void) { busy = true; Task { defer { busy = false }; do { try await operation() } catch { store.error = error.localizedDescription } } }
}
func communityDate(_ milliseconds: Double) -> String { guard milliseconds > 0 else { return "" }; return Date(timeIntervalSince1970: milliseconds / 1000).formatted(.dateTime.year().month().day().hour().minute()) }

struct CommunityEditor: View {
    let kind: FeatureRoute
    var existing: CampusRecord?
    var initialType:String?
    var onSuccess: () -> Void
    @Environment(PlatformSession.self) private var platform
    @Environment(\.dismiss) private var dismiss
    @State private var clientID = UUID().uuidString
    @State private var title = ""
    @State private var description = ""
    @State private var campus = CampusContract.campuses[0]
    @State private var type = "sell"
    @State private var category = CampusContract.marketplaceCategories[0]
    @State private var location = ""
    @State private var date = Date.now
    @State private var time = ""
    @State private var contact = ""
    @State private var wechat = ""
    @State private var phone = ""
    @State private var images: [String] = []
    @State private var selection: [PhotosPickerItem] = []
    @State private var populated=false
    @State private var originalDraft:[String]=[]
    @State private var discard=false
    private var draft:[String] { [title,description,campus,type,category,location,CampusContract.day(date),time,contact,wechat,phone]+images }
    private var dirty:Bool { populated && draft != originalDraft }
    @State private var loadingImages = false
    @State private var busy = false
    @State private var error: String?
    private var maxImages: Int { kind == .secondhand ? 4 : 1 }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 19) {
                Text(existing == nil ? (kind == .secondhand ? "分享好物，传递需要" : type == "found" ? "帮物品找到主人" : "让遗失物品早一点回家") : "编辑信息").font(.system(size: 24, weight: .bold))
                Picker("信息类型", selection: $type) {
                    if kind == .secondhand { Text("出售").tag("sell"); Text("求购").tag("want") }
                    else { Text("寻物").tag("lost"); Text("招领").tag("found") }
                }.pickerStyle(.segmented).disabled(busy || loadingImages || (kind == .secondhand && existing != nil))
                if kind == .lost_found { photoSection }
                editorField(kind == .secondhand ? "标题 *" : "物品名称 *") {
                    TextField(kind == .secondhand ? "给好物起个名字" : type == "found" ? "例如：捡到一张校园卡" : "例如：寻找一串钥匙", text: $title).onChange(of: title) { _, value in title = String(value.prefix(kind == .secondhand ? 50 : 30)) }
                }
                editorField("所在校区 *") { Picker("所在校区", selection: $campus) { ForEach(["雅安校区", "成都校区", "都江堰校区"], id: \.self) { Text($0).tag($0) } }.labelsHidden() }
                if kind == .secondhand {
                    editorField("分类 *") { Picker("分类", selection: $category) { ForEach(CampusContract.marketplaceCategories, id: \.self) { Text($0).tag($0) } }.labelsHidden() }
                } else {
                    editorField(type == "found" ? "拾获地点 *" : "遗失地点 *") { TextField("例如：图书馆一楼", text: $location).onChange(of: location) { _, value in location = String(value.prefix(40)) } }
                    editorField(type == "found" ? "拾获日期 *" : "遗失日期 *") { DatePicker("日期", selection: $date, displayedComponents: .date).labelsHidden() }
                }
                editorField(kind == .secondhand ? "描述 *" : "补充描述 · 选填") {
                    TextField(kind == .secondhand ? "介绍一下物品的情况和你的需求…" : "物品特征、颜色，或其他有用的线索…", text: $description, axis: .vertical).lineLimit(4...8).onChange(of: description) { _, value in description = String(value.prefix(kind == .secondhand ? 1000 : 300)) }
                }
                if kind == .secondhand {
                    editorField("微信号") { TextField("微信号与电话至少填写一项", text: $wechat).textInputAutocapitalization(.never).autocorrectionDisabled().onChange(of: wechat) { _, value in wechat = String(value.prefix(64)) } }
                    editorField("联系电话") { TextField("方便同学联系你", text: $phone).keyboardType(.phonePad).onChange(of: phone) { _, value in phone = String(value.prefix(32)) } }
                    photoSection
                } else {
                    editorField("联系方式 *") { TextField("微信 / 手机号等", text: $contact).onChange(of: contact) { _, value in contact = String(value.prefix(60)) } }
                }
                if let error { StatusMessage(text: error) }
                Button { submit() } label: { HStack { Spacer(); if busy { ProgressView().tint(.white) }; Text(busy ? "正在提交…" : existing == nil ? "提交发布" : "保存并提交审核"); Spacer() }.frame(minHeight: 46) }.buttonStyle(.borderedProminent).disabled(busy || loadingImages)
            }.padding(20)
        }.background(LostFoundTheme.paper).navigationTitle(existing == nil ? "发布信息" : "编辑信息").navigationBarTitleDisplayMode(.inline).interactiveDismissDisabled(busy || dirty)
        .onAppear { populate() }.task(id: selection) { await prepareImages() }
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { if dirty { discard=true } else { dismiss() } }.disabled(busy) } }
        .confirmationDialog("放弃这次编辑？",isPresented:$discard,titleVisibility:.visible){Button("放弃编辑",role:.destructive){dismiss()};Button("继续编辑",role:.cancel){}}message:{Text("尚未保存的内容将不会保留。 ")}
    }
    private func editorField<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) { Text(title).font(.system(size: 13, weight: .medium)); content().font(.system(size: 14)).frame(maxWidth: .infinity, alignment: .leading).padding(13).background(ChuannongTheme.card, in: RoundedRectangle(cornerRadius: 11)).overlay(RoundedRectangle(cornerRadius: 11).stroke(.secondary.opacity(0.12), lineWidth: 1)) }
    }
    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                if images.isEmpty { PhotosPicker(selection: $selection, maxSelectionCount: maxImages, matching: .images) { VStack(spacing: 7) { Image(systemName: "plus").font(.title2); Text("添加照片").font(.system(size: 12)) }.frame(width: 84, height: 84).background(ChuannongTheme.green.opacity(0.06), in: RoundedRectangle(cornerRadius: 13)) }.disabled(busy || loadingImages) }
                VStack(alignment: .leading, spacing: 7) {
                    Text("物品照片 · 选填").font(.system(size: 14, weight: .medium))
                    Text(kind == .secondhand ? "最多 4 张照片，让同学更了解你的物品。" : "清晰的照片，更容易找到失主\n请遮住证件上的个人信息").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            if !images.isEmpty {
                ScrollView(.horizontal) { HStack(spacing: 12) { ForEach(Array(images.enumerated()), id: \.offset) { index, path in VStack(spacing: 8) { CommunityPhoto(path: path).frame(width: 84, height: 84).clipShape(RoundedRectangle(cornerRadius: 12)); Button("移除照片", role: .destructive) { images.remove(at: index) }.font(.system(size: 11)).disabled(busy || loadingImages) } } } }
                if images.count < maxImages { PhotosPicker("继续添加", selection: $selection, maxSelectionCount: maxImages - images.count, matching: .images).disabled(busy || loadingImages) }
            }
            if loadingImages { ProgressView("正在处理照片…") }
        }
    }
    private func populate() {
        guard !populated else{return};populated=true;defer{originalDraft=draft}
        guard let item = existing else { type = initialType ?? (kind == .secondhand ? "sell" : "lost");campus=kind == .lost_found ? "成都校区" : "雅安校区";category="书籍";return }
        title = item.title; description = item["description"]; campus = item["campus"]; type = item[kind == .secondhand ? "type" : "kind"]
        category = item["category"]; location = item["location"]; time = item["time"]; contact = item["contact"]; wechat = item["wechat"]; phone = item["phone"]; images = item.imagePaths
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "Asia/Shanghai"); f.dateFormat = "yyyy-MM-dd"; date = f.date(from: item["date"]) ?? .now
    }
    private func prepareImages() async {
        guard !selection.isEmpty else { return }; loadingImages = true; defer { loadingImages = false }
        do {
            var additions: [String] = []
            for item in selection {
                guard let data = try await item.loadTransferable(type: Data.self), data.count <= 10 * 1024 * 1024 else { throw APIError.server(422, "请选择 10 MB 以内、格式可读取的图片") }
                let encoded = try await Task.detached(priority: .userInitiated) { try UploadImage.encode(data) }.value
                try Task.checkCancellation(); additions.append(encoded)
            }
            guard images.count + additions.count <= maxImages else { throw APIError.server(422, "照片数量超出限制") }
            images += additions; selection = []
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
    private func submit() {
        let isMarket = kind == .secondhand
        title=title.trimmingCharacters(in:.whitespacesAndNewlines);description=description.trimmingCharacters(in:.whitespacesAndNewlines);location=location.trimmingCharacters(in:.whitespacesAndNewlines);contact=contact.trimmingCharacters(in:.whitespacesAndNewlines);wechat=wechat.trimmingCharacters(in:.whitespacesAndNewlines);phone=phone.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= (isMarket ? 50 : 30), description.count <= (isMarket ? 1000 : 300), !isMarket || !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { error = "请核对标题与描述：标题最多 \(isMarket ? 50 : 30) 字，描述最多 \(isMarket ? 1000 : 300) 字"; return }
        guard isMarket ? ((!wechat.isEmpty || !phone.isEmpty) && wechat.count <= 64 && phone.count <= 32) : (!location.isEmpty && location.count <= 40 && !contact.isEmpty && contact.count <= 60 && time.count <= 30) else { error = "请完整填写地点和联系方式，并核对长度"; return }
        var body: [String: JSONValue] = ["clientId": .string(clientID), "title": .string(title), "description": .string(description), "campus": .string(campus)]
        if isMarket { body.merge(["type": .string(type), "category": .string(category), "wechat": .string(wechat), "phone": .string(phone), "images": .array(images.map(JSONValue.string))]) { _, new in new } }
        else { body.merge(["kind": .string(type), "location": .string(location), "date": .string(CampusContract.day(date)), "time": .string(time), "contact": .string(contact), "image": .string(images.first ?? "")]) { _, new in new } }
        if existing != nil { body.removeValue(forKey: "clientId") }
        busy = true
        Task { defer { busy = false }; do { _ = try await platform.perform(kind.communityPath + (existing.map { "/" + $0.id } ?? ""), method: existing == nil ? "POST" : "PATCH", body: body); onSuccess(); dismiss() } catch { self.error = error.localizedDescription } }
    }
}

nonisolated enum UploadImage {
    static func encode(_ data: Data) throws -> String {
        guard data.count <= 40_000_000, let source = CGImageSourceCreateWithData(data as CFData, nil), let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 1600] as CFDictionary) else { throw APIError.server(422, "照片过大或格式无法识别") }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { throw APIError.server(422, "照片处理失败") }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destination), output.length <= 3_000_000 else { throw APIError.server(422, "照片压缩后仍超过 3MB，请选择较小的图片") }
        return "data:image/jpeg;base64," + (output as Data).base64EncodedString()
    }
}

struct CommunityNotices: View {
    let kind: FeatureRoute
    @Environment(PlatformSession.self) private var platform
    @State private var store = RemoteContent()
    @State private var marking = Set<String>()
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                RemoteStatus(store: store, empty: "暂时没有处理通知")
                ForEach(store.records) { item in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack { ReviewStatusBadge(status: item["status"]); Spacer(); Text((kind == .secondhand ? (item["post_type"] == "sell" ? "出售" : "求购") : (item["post_type"] == "lost" ? "寻物" : "招领")) + " · " + (item.value["read_at"] == .null ? "未读" : "已读")).font(.system(size: 12)).foregroundStyle(.secondary) }
                        Text(item.title).font(.system(size: 17, weight: .semibold))
                        Text("处理结果：" + (["approve":"审核通过", "reject":"审核驳回", "take_down":"已下架"][item["action"]] ?? item["action"])).font(.system(size: 13))
                        if !item["reason"].isEmpty { VStack(alignment: .leading, spacing: 6) { Text("具体原因").bold(); Text(item["reason"]) }.font(.system(size: 13)).padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 10)) }
                        else { Text("本次审核已通过，当前状态和完成进度可在“我的发布”查看。").font(.system(size: 12)).foregroundStyle(.secondary) }
                        Text(communityDate(item.value["created_at"].number)).font(.system(size: 11)).foregroundStyle(.secondary)
                        HStack { NavigationLink("查看信息") { CommunityDetail(kind: kind, id: item["post_id"], changed: {}) }; Spacer(); if item.value["read_at"] == .null { Button(marking.contains(item.id) ? "处理中…" : "标记已读") { mark(item) }.disabled(marking.contains(item.id)) } }.font(.system(size: 13)).buttonStyle(.bordered)
                    }.padding(18).background(ChuannongTheme.card, in: RoundedRectangle(cornerRadius: 18))
                }
                if store.value["total"].number > Double(store.records.count) { Button("加载更多") { Task { await load(append: true) } }.frame(maxWidth:.infinity).disabled(store.loading) }
            }.padding(20)
        }.background(LostFoundTheme.paper).navigationTitle("处理通知").navigationBarTitleDisplayMode(.inline)
        .task(id: platform.user?.id) { await load() }.refreshable { await load() }
    }
    private func load(append: Bool = false) async { await store.load(kind.communityPath + "/notifications", session: platform, query: ["limit":"50", "offset": append ? String(store.records.count) : "0"], append: append) }
    private func mark(_ item: CampusRecord) { marking.insert(item.id); Task { defer { marking.remove(item.id) }; do { _ = try await platform.perform(kind.communityPath + "/notifications", method: "PATCH", body: ["ids": .array([.string(item.id)])]); await load() } catch { store.error = error.localizedDescription } } }
}
