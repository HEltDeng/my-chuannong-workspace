import SwiftUI
import Photos

struct GuideView: View {
    let route: FeatureRoute
    @Environment(PlatformSession.self) private var platform
    @State private var store = RemoteContent()
    @State private var web = false
    @State private var message: String?
    @State private var saving = false
    private var repair: Bool { route == .logistics_repair }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: route == .errand ? 16 : 20) {
                if store.loaded { publishedGuide }
                if route == .errand { errand }
                else {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) { Text("微信搜索公众号").font(.system(size: 13)).foregroundStyle(.secondary); Text("「川农后勤」").font(.system(size: 22, weight: .bold)).foregroundStyle(ChuannongTheme.green) }
                        Spacer()
                        Button("复制公众号名称") { UIPasteboard.general.string = "川农后勤"; message = "已复制公众号名称" }.font(.system(size: 12)).buttonStyle(.bordered)
                    }.padding(16).background(ChuannongTheme.green.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                    guideHeading(repair ? "报修路径" : "查询路径")
                    VStack(spacing: 16) {
                        guideStep("1", "搜索公众号", "在微信搜索「川农后勤」并进入公众号"); Divider()
                        guideStep("2", repair ? "打开报修平台" : "打开电精灵", repair ? "底部菜单「智慧后勤」→「后勤报修」" : "底部菜单「智慧后勤」→「电精灵」"); Divider()
                        guideStep("3", repair ? "发起报修" : "进入水电管理", repair ? "在平台首页点击「我要报修」" : "在平台首页点击「水电管理」")
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        guideHeading("入口示意")
                        Text(repair ? "进入「后勤报修」后，点击「我要报修」" : "进入「电精灵」后，点击下方「水电管理」").font(.system(size: 13)).foregroundStyle(.secondary)
                        GuideIllustration(name: repair ? "logistics_repair_reference" : "electric_guide_reference", crop: repair ? CGRect(x: 32, y: 1252, width: 777, height: 470) : CGRect(x: 35, y: 1070, width: 783, height: 485)).accessibilityLabel(repair ? "后勤报修入口示意图，绿色框标出我要报修；此图仅供参考" : "电精灵入口示意图，绿色框标出水电管理；此图仅供参考")
                    }
                    if !repair { Text("复制后请打开微信，公众号完成查询").font(.system(size: 12)).foregroundStyle(.secondary).frame(maxWidth: .infinity) }
                }
                if let message { Text(message).font(.system(size: 12)).foregroundStyle(ChuannongTheme.green).accessibilityAddTraits(.updatesFrequently) }
            }.padding(route == .errand ? 20 : 16)
        }.background(ChuannongTheme.background).navigationTitle(route.title).navigationBarTitleDisplayMode(.inline)
        .task(id: platform.user?.id) { if platform.signedIn { await store.load("services/guides/\(route.rawValue)", session: platform) } }
        .sheet(isPresented: $web) { if let url = CampusContract.externalURL(store.value["url"].text) { SafariPage(url: url) } }
        .serviceAvailability(route)
    }
    private var publishedGuide: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(store.value["title"].text).font(.headline); Text(store.value["body"].text).font(.subheadline).textSelection(.enabled)
            RecordImages(paths: [store.value["image"].text])
            if let url = CampusContract.externalURL(store.value["url"].text) { Button(url.absoluteString) { web = true }.font(.caption).textSelection(.enabled) }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16).background(ChuannongTheme.card, in: RoundedRectangle(cornerRadius: 16))
    }
    private var errand: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let url = Bundle.main.url(forResource: "errand_service_poster", withExtension: "jpg"), let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 24)).accessibilityLabel("哈哈龙跑腿宣传海报与小程序码")
            }
            HStack(spacing: 12) {
                Button(saving ? "正在保存…" : "保存海报") { savePoster() }.buttonStyle(.borderedProminent).frame(maxWidth: .infinity).disabled(saving)
                Button("打开微信") { openWeChat() }.buttonStyle(.bordered).frame(maxWidth: .infinity)
            }
        }
    }
    private func guideHeading(_ title: String) -> some View { HStack(spacing: 10) { RoundedRectangle(cornerRadius: 2).fill(ChuannongTheme.green).frame(width: 4, height: 20); Text(title).font(.system(size: 20, weight: .bold)) } }
    private func guideStep(_ number: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) { Text(number).font(.system(size: 23, weight: .bold)).foregroundStyle(ChuannongTheme.green).frame(width: 38, height: 38).background(ChuannongTheme.green.opacity(0.07), in: Circle()); VStack(alignment: .leading, spacing: 5) { Text(title).font(.system(size: 17, weight: .bold)); Text(detail).font(.system(size: 14)).lineSpacing(7).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading) }
    }
    private func openWeChat() {
        guard let url = URL(string: "weixin://"), UIApplication.shared.canOpenURL(url) else { message = "当前未检测到微信，请先安装微信，或保存海报后使用其他设备扫码。"; return }
        UIApplication.shared.open(url, options: [:]) { opened in Task { @MainActor in message = opened ? nil : "暂时无法打开微信，请重试。" } }
    }
    private func savePoster() {
        guard !saving else { return }; saving = true
        Task {
            defer { saving = false }
            do {
                let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
                guard status == .authorized || status == .limited else { message = "未获得相册保存权限，请在系统设置中允许添加照片后重试。"; return }
                guard let url = Bundle.main.url(forResource: "errand_service_poster", withExtension: "jpg") else { throw APIError.invalidResponse }
                // Preserve the original poster and its code, without re-encoding.
                try await PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url) }
                message = "海报已保存到相册"
            } catch { message = "保存失败，请重试。" }
        }
    }
}

struct GuideIllustration: View {
    let name: String
    let crop: CGRect
    var body: some View {
        GeometryReader { geometry in
            if let url = Bundle.main.url(forResource: name, withExtension: "png"), let image = UIImage(contentsOfFile: url.path) {
                let scale = geometry.size.width / crop.width
                Image(uiImage: image).resizable().frame(width: image.size.width * scale, height: image.size.height * scale).offset(x: -crop.minX * scale, y: -crop.minY * scale)
            }
        }.aspectRatio(crop.width / crop.height, contentMode: .fit).clipped().clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

enum ProviderTheme {
    static let accent = Color(hex: 0x326B96)
    static let paper = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? .systemGroupedBackground : UIColor(red: 245/255, green: 249/255, blue: 253/255, alpha: 1) })
}
struct ProviderPanel<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View { VStack(alignment: .leading, spacing: 12, content: content).frame(maxWidth: .infinity, alignment: .leading).padding(20).background(ChuannongTheme.card, in: RoundedRectangle(cornerRadius: 20)).overlay(RoundedRectangle(cornerRadius: 20).stroke(ProviderTheme.accent.opacity(0.1), lineWidth: 1)) }
}
struct ProvidersView: View {
    let route: FeatureRoute
    @Environment(PlatformSession.self) private var platform
    @State private var store = RemoteContent()
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                RemoteStatus(store: store, empty: "")
                ForEach(store.records) { item in
                    NavigationLink { ProviderDetail(id: item.id) } label: {
                        ProviderPanel {
                            HStack(alignment: .center, spacing: 14) {
                                if item.imagePaths.isEmpty { Text(route.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(ProviderTheme.accent).frame(width: 76, height: 76).background(ProviderTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 14)) }
                                else { CommunityPhoto(path: item.imagePaths.first).frame(width: 76, height: 76).clipShape(RoundedRectangle(cornerRadius: 14)) }
                                VStack(alignment: .leading, spacing: 7) { Text(item.title).font(.system(size: 18, weight: .bold)); Text(item["campus"]).font(.system(size: 12)).foregroundStyle(.secondary); Text(item["summary"]).font(.system(size: 13)).foregroundStyle(.secondary); if item.value["isDemo"].boolean { Text("演示机构 · 不接受真实预约").font(.system(size: 11)).foregroundStyle(.secondary) } }.frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }.buttonStyle(.plain)
                }
            }.padding(20)
        }.background(ProviderTheme.paper).tint(ProviderTheme.accent).navigationTitle(route.title).navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { NavigationLink("我的预约") { BookingsView() }.font(.subheadline) } }
        .task(id: platform.user?.id) { await load() }.refreshable { await load() }.serviceAvailability(route)
    }
    private func load() async { await store.load("services/providers", session: platform, query: ["category": route.rawValue]) }
}

struct ProviderDetail: View {
    let id: String
    @Environment(PlatformSession.self) private var platform
    @State private var store = RemoteContent()
    @State private var booking = false
    @State private var submitted = false
    @State private var bookings = false
    private var item: CampusRecord { CampusRecord(store.value) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if store.loading { ProgressView() }; if let error = store.error { StatusMessage(text: error) }
                if store.loaded {
                    Text(item["campus"]).font(.system(size: 12)).foregroundStyle(.secondary)
                    if !item.imagePaths.isEmpty { CommunityPhoto(path: item.imagePaths.first).frame(height: 190).clipShape(RoundedRectangle(cornerRadius: 20)) }
                    Text(item.title).font(.system(size: 26, weight: .bold)); Text(item["summary"]).font(.system(size: 14)).foregroundStyle(.secondary)
                    ProviderPanel {
                        Text("机构介绍").font(.system(size: 18, weight: .bold))
                        Text(item.value["details"]["description"].text.isEmpty ? "机构暂未填写详细介绍" : item.value["details"]["description"].text)
                        ForEach([item["address"], item["phone"], item.value["details"]["hours"].text, item.value["details"]["pickup"].text].filter { !$0.isEmpty }, id: \.self) { Text($0).font(.system(size: 14)).foregroundStyle(.secondary).textSelection(.enabled) }
                    }
                    ProviderPanel {
                        Text("课程与服务").font(.system(size: 18, weight: .bold))
                        if item.value["details"]["courses"].list.isEmpty { Text("请向机构咨询当前课程。").font(.system(size: 14)).foregroundStyle(.secondary) }
                        ForEach(Array(item.value["details"]["courses"].list.enumerated()), id: \.offset) { index, row in
                            if index > 0 { Divider() }
                            VStack(alignment: .leading, spacing: 8) { Text(courseName(row)).font(.system(size: 15, weight: .semibold)); if !row["description"].text.isEmpty { Text(row["description"].text).font(.system(size: 14)).foregroundStyle(.secondary) }; if row["price"] != .null { Text("参考价格 ¥" + row["price"].text).font(.system(size: 13)).foregroundStyle(ProviderTheme.accent) } }
                        }
                    }
                    if !item.value["details"]["facilities"].list.isEmpty { ProviderPanel { Text("场地设施").font(.system(size: 18, weight: .bold)); ForEach(Array(item.value["details"]["facilities"].list.enumerated()), id: \.offset) { _, value in Text("• " + facility(value)).font(.system(size: 14)).foregroundStyle(.secondary) } } }
                    if item.value["isDemo"].boolean { Text("演示机构").font(.subheadline) } else if !item.value["bookingEnabled"].boolean { Text("暂未开放预约").font(.subheadline) }
                    if !item.value["isDemo"].boolean && item.value["bookingEnabled"].boolean { Button("登记预约意向") { submitted = false; booking = true }.buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth: .infinity) }
                }
            }.padding(20)
        }.background(ProviderTheme.paper).tint(ProviderTheme.accent).navigationTitle("机构详情").navigationBarTitleDisplayMode(.inline)
        .task(id: platform.user?.id) { await store.load("services/providers/\(id)", session: platform) }
        .sheet(isPresented: $booking, onDismiss: { if submitted { bookings = true } }) { NavigationStack { BookingEditor(provider: item, onSuccess: { submitted = true }) }.environment(platform) }
        .navigationDestination(isPresented: $bookings) { BookingsView(message: "已提交，等待运营人员确认") }
    }
    private func facility(_ value: JSONValue) -> String { if case .object = value { return ["name", "title", "description", "note"].map { value[$0].text }.filter { !$0.isEmpty }.joined(separator: " · ") }; return value.text }
}
private func courseName(_ value: JSONValue) -> String { [value["title"].text, value["name"].text].first { !$0.isEmpty } ?? "课程咨询" }

struct BookingEditor: View {
    let provider: CampusRecord
    var onSuccess: () -> Void
    @Environment(PlatformSession.self) private var platform
    @Environment(\.dismiss) private var dismiss
    @State private var clientID = UUID().uuidString
    @State private var course = ""
    @State private var date = Date.now
    @State private var name = ""
    @State private var phone = ""
    @State private var note = ""
    @State private var consent = false
    @State private var busy = false
    @State private var error: String?
    @FocusState private var focusedField: BookingField?
    private enum BookingField: Hashable { case name, phone, note }
    private var choices: [String] { let rows = provider.value["details"]["courses"].list.map(courseName); var seen = Set<String>(); return rows.isEmpty ? ["课程咨询"] : rows.filter { seen.insert($0).inserted } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 19) {
                Text("登记预约意向").font(.system(size: 26, weight: .bold)); Text(provider.title).font(.system(size: 14)).foregroundStyle(.secondary)
                field("课程 / 服务") { Picker("课程 / 服务", selection: $course) { ForEach(choices, id: \.self) { Text($0).tag($0) } }.labelsHidden() }
                field("称呼") { TextField("称呼", text: $name).textContentType(.name).focused($focusedField, equals: .name).submitLabel(.next).onSubmit { focusedField = .phone }.onChange(of: name) { _, value in name = String(value.prefix(40)) } }
                field("联系电话") { TextField("联系电话", text: $phone).textContentType(.telephoneNumber).keyboardType(.phonePad).focused($focusedField, equals: .phone).onChange(of: phone) { _, value in phone = String(value.prefix(32)) } }
                field("意向日期") { DatePicker("意向日期", selection: $date, displayedComponents: .date).labelsHidden() }
                field("备注") { TextField("补充你的预约需求", text: $note, axis: .vertical).lineLimit(3...6).focused($focusedField, equals: .note).onChange(of: note) { _, value in note = String(value.prefix(500)) } }
                Toggle("同意将以上联系方式用于本次预约联系", isOn: $consent).font(.system(size: 13))
                if let error { StatusMessage(text: error) }
                Button(busy ? "提交中…" : "提交预约意向") { submit() }.buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth: .infinity).disabled(busy || !consent)
            }.padding(20)
        }.scrollDismissesKeyboard(.interactively).background(ProviderTheme.paper).tint(ProviderTheme.accent).navigationTitle("登记预约意向").navigationBarTitleDisplayMode(.inline).interactiveDismissDisabled(busy)
        .onAppear { if course.isEmpty { course = choices[0] } }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("返回机构") { dismiss() }.disabled(busy) }
            ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("完成输入") { focusedField = nil } }
        }
    }
    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View { VStack(alignment: .leading, spacing: 8) { Text(title).font(.system(size: 14)); content().font(.system(size: 14)).frame(maxWidth: .infinity, alignment: .leading).padding(12).background(ChuannongTheme.card, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(ProviderTheme.accent.opacity(0.15), lineWidth: 1)) } }
    private func submit() {
        guard !busy, consent, choices.contains(course), (1...40).contains(name.trimmingCharacters(in: .whitespacesAndNewlines).count), (1...32).contains(phone.trimmingCharacters(in: .whitespacesAndNewlines).count), note.count <= 500 else { error = "请填写课程、称呼与联系电话，并核对字数限制"; return }
        busy = true
        focusedField = nil
        let body: [String: JSONValue] = ["clientId": .string(clientID), "providerId": .string(provider.id), "course": .string(course), "preferredDate": .string(CampusContract.day(date)), "name": .string(name), "phone": .string(phone), "note": .string(note), "consented": .bool(consent)]
        Task { defer { busy = false }; do { _ = try await platform.perform("services/bookings", method: "POST", body: body); onSuccess(); dismiss() } catch { self.error = error.localizedDescription } }
    }
}

struct BookingsView: View {
    var message: String = ""
    @Environment(PlatformSession.self) private var platform
    @State private var store = RemoteContent()
    @State private var busy = false
    @State private var actionMessage: String?
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                Text("我的预约").font(.system(size: 26, weight: .bold))
                if let text = actionMessage ?? (message.isEmpty ? nil : message) { Text(text).font(.system(size: 12)).foregroundStyle(.secondary) }
                RemoteStatus(store: store, empty: "暂时没有预约")
                ForEach(store.records) { item in
                    ProviderPanel {
                        Text(["PENDING":"待确认", "CONFIRMED":"已确认", "COMPLETED":"已完成", "CANCELLED":"已取消", "REJECTED":"未通过"][item["status"]] ?? item["status"]).font(.system(size: 12)).foregroundStyle(ProviderTheme.accent)
                        Text(item["provider_name"].isEmpty ? "预约机构" : item["provider_name"]).font(.system(size: 18, weight: .bold)); Text(item["course"] + " · " + item["preferred_date"]).font(.system(size: 14)).foregroundStyle(.secondary)
                        if !item["reply"].isEmpty { Text(item["reply"]).font(.system(size: 14)) }
                        if ["PENDING", "CONFIRMED"].contains(item["status"]) { Button("取消预约") { cancel(item) }.buttonStyle(.bordered).frame(maxWidth: .infinity).disabled(busy) }
                    }
                }
                if store.value["total"].number > Double(store.records.count) { Button("加载更多") { Task { await load(append: true) } }.frame(maxWidth: .infinity).disabled(store.loading) }
            }.padding(20)
        }.background(ProviderTheme.paper).tint(ProviderTheme.accent).navigationTitle("我的预约").navigationBarTitleDisplayMode(.inline)
        .task(id: platform.user?.id) { await load() }.refreshable { await load() }
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { Task { await load() } } label: { Label("刷新预约", systemImage: "arrow.clockwise") }.disabled(store.loading || busy) } }
    }
    private func cancel(_ item: CampusRecord) { busy = true; Task { defer { busy = false }; do { _ = try await platform.perform("services/bookings/\(item.id)", method: "PATCH", body: ["status": .string("CANCELLED")]); actionMessage = "预约已取消"; await load() } catch { store.error = error.localizedDescription } } }
    private func load(append: Bool = false) async { await store.load("services/bookings", session: platform, query: ["limit":"100", "offset": append ? String(store.records.count) : "0"], append: append) }
}
