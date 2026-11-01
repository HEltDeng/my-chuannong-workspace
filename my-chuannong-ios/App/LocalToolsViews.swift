import SwiftUI
import UserNotifications
import CryptoKit

@MainActor enum BundledAcademic {
    static func currentTerm(at date: Date) -> AcademicCalendarData.Term? {
        data?.terms.first { term in guard let start=AcademicCalendarData.date(term.semesterStart), let end=AcademicCalendarData.date(term.semesterEnd) else{return false}; return date >= start && date < end.addingTimeInterval(86400) }
    }
    static func firstMonday(_ term:String,snapshot:AcademicSnapshot)->Date? {
        snapshot.termStarts[term] ?? data?.terms.first(where:{$0.id==term}).flatMap{AcademicCalendarData.date($0.semesterStart)}
    }
    static var data: AcademicCalendarData? { AcademicDataStore.shared.data }
}

struct SchoolCalendarView: View {
    @State private var store = AcademicDataStore.shared
    @State private var source: URL?
    @AppStorage(PrivacyConsent.storageKey) private var consent = false
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if let data = store.data {
                    VStack(alignment: .leading, spacing: 3) { Text("四川农业大学").font(.system(size: 12)).foregroundStyle(.secondary); Text("校历列表").font(.system(size: 22, weight: .bold)); Text("共 \(data.terms.count) 个学期").font(.system(size: 12)).foregroundStyle(.secondary) }.padding(.vertical, 4)
                    if let message = store.message { Text(message).font(.system(size: 12)).foregroundStyle(.secondary) }
                    ForEach(data.terms) { term in
                        let current = AcademicCalendarRules.isTeaching(term, at: .now)
                        NavigationLink { SemesterCalendarView(termID: term.id) } label: {
                            HStack(spacing: 12) {
                                VStack(spacing: 1) { Text(term.id.hasSuffix("-1") ? "一" : "二").font(.system(size: 16, weight: .bold)); Text(term.id.split(separator: "-").prefix(2).map { String($0.suffix(2)) }.joined(separator: "-")).font(.system(size: 8)) }.foregroundStyle(current ? .white : ChuannongTheme.green).frame(width: 46, height: 46).background(current ? ChuannongTheme.green : ChuannongTheme.green.opacity(0.1), in: Circle())
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 8) { Text(term.title).font(.system(size: 15, weight: .semibold)); if current { Text("本学期").font(.system(size: 10)).foregroundStyle(.white).padding(.horizontal, 6).padding(.vertical, 2).background(ChuannongTheme.green, in: RoundedRectangle(cornerRadius: 4)) } }
                                    Text(term.subtitle).font(.system(size: 12)).foregroundStyle(.secondary); Text(term.semesterStart + " 正式行课").font(.system(size: 11)).foregroundStyle(.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                            }.padding(14).background(current ? ChuannongTheme.green.opacity(0.1) : ChuannongTheme.card, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(ChuannongTheme.green.opacity(current ? 0.5 : 0.1), lineWidth: current ? 1.5 : 1))
                        }.buttonStyle(.plain)
                    }
                } else { EmptyState(title: "暂无校历数据", message: "内置校历暂时无法读取。", icon: "calendar") }
            }.padding(.horizontal, 16).padding(.vertical, 8)
        }.background(ChuannongTheme.background).navigationTitle("学校校历").navigationBarTitleDisplayMode(.inline)
        .refreshable { if consent { await store.refresh(force: true) } }
        .toolbar { ToolbarItemGroup(placement: .topBarTrailing) { Button { Task { if consent { await store.refresh(force: true) } } } label: { if store.refreshing { ProgressView() } else { Image(systemName: "arrow.clockwise") } }.disabled(store.refreshing || !consent).accessibilityLabel("刷新校历"); Menu { Button("查看官方来源") { source = URL(string: AcademicCalendarRules.source) }; Link("在浏览器中打开", destination: URL(string: AcademicCalendarRules.source)!) } label: { Image(systemName: "ellipsis") }.accessibilityLabel("校历选项") } }
        .sheet(isPresented: Binding(get: { source != nil }, set: { if !$0 { source = nil } })) { if let source { ConsentGate { SafariPage(url: source) } } }
    }
}

struct SemesterCalendarView: View {
    let termID: String
    @State private var store = AcademicDataStore.shared
    @State private var selected: Date?
    @State private var source: URL?
    @AppStorage(PrivacyConsent.storageKey) private var consent = false
    private var term: AcademicCalendarData.Term? { store.data?.terms.first { $0.id == termID } }
    private let accent = Color(hex: 0x4F7FED)
    var body: some View {
        Group {
            if let term { content(term) } else { EmptyState(title: "暂无校历数据", message: "该学期尚无已验证校历。", icon: "calendar") }
        }.background(ChuannongTheme.background).navigationTitle(term?.subtitle ?? "学期校历").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItemGroup(placement: .topBarTrailing) { Button { Task { if consent { await store.refresh(force: true) } } } label: { if store.refreshing { ProgressView() } else { Image(systemName: "arrow.clockwise") } }.disabled(store.refreshing || !consent).accessibilityLabel("刷新校历"); Menu { Button("查看官方来源") { source = URL(string: AcademicCalendarRules.source) }; Button("查看官方原图") { source = URL(string: term?.sourceResource ?? store.data?.sourceResources?.first?.url ?? AcademicCalendarRules.source) }; Link("在浏览器中打开", destination: URL(string: AcademicCalendarRules.source)!) } label: { Image(systemName: "ellipsis") }.accessibilityLabel("校历选项") } }
        .sheet(isPresented: Binding(get: { source != nil }, set: { if !$0 { source = nil } })) { if let source { ConsentGate { SafariPage(url: source) } } }
        .alert(selected.map(AcademicCalendarRules.day) ?? "校历日期", isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } })) { Button("关闭", role: .cancel) { selected = nil } } message: { if let selected, let term { Text(dayDescription(selected, term)) } }
    }
    private func content(_ term: AcademicCalendarData.Term) -> some View {
        let weeks = rows(term), target = targetRow(term)
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 4, pinnedViews: [.sectionHeaders]) {
                    VStack(alignment: .leading, spacing: 8) { Text(term.title + " · " + term.subtitle).font(.headline); Text("\(term.semesterStart) 正式行课 · 共 \(term.teachingWeeks ?? 0) 周").font(.system(size: 12)).foregroundStyle(.secondary); if let message = store.message { Text(message).font(.system(size: 12)).foregroundStyle(.secondary) } }.frame(maxWidth: .infinity, alignment: .leading).padding(14).background(ChuannongTheme.card, in: RoundedRectangle(cornerRadius: 14)).padding(.bottom, 8)
                    Section {
                        ForEach(weeks, id: \.self) { week in weekRow(week, term).id(week) }
                    } header: { HStack(spacing: 0) { Text("周").frame(width: 36); ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { Text($0).frame(maxWidth: .infinity) } }.font(.system(size: 12)).padding(.vertical, 10).background(ChuannongTheme.background) }
                    ForEach(Array(term.events.enumerated()), id: \.offset) { _, event in Text(event.start + (event.end != event.start ? " 至 " + event.end : "") + " " + event.name).font(.system(size: 13)).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4) }
                    Text("来源：四川农业大学 · 核对 " + String((store.data?.checkedAt ?? "").prefix(10))).font(.system(size: 11)).foregroundStyle(.secondary).padding(.vertical, 8)
                }.padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 100)
            }.overlay(alignment: .bottomTrailing) { Button { withAnimation { proxy.scrollTo(target, anchor: .top) } } label: { Text(target <= .now && AcademicCalendarRules.adding(7, to: target) > .now ? "今天 / " + (teachingWeek(.now, term).map { "第\($0)周" } ?? "假期") : "开学周") }.buttonStyle(.borderedProminent).tint(accent).padding(16) }
            .onAppear { if target <= .now && AcademicCalendarRules.adding(7, to: target) > .now { proxy.scrollTo(target, anchor: .top) } }
        }
    }
    private func rows(_ term: AcademicCalendarData.Term) -> [Date] {
        guard let start = AcademicCalendarData.date(term.calendarStart ?? term.semesterStart), let end = AcademicCalendarData.date(term.calendarEnd ?? term.semesterEnd) else { return [] }
        let first = monday(start); return stride(from: 0, through: AcademicCalendarRules.days(first, end), by: 7).map { AcademicCalendarRules.adding($0, to: first) }
    }
    private func monday(_ date: Date) -> Date { let cal = AcademicCalendarRules.calendar; return AcademicCalendarRules.adding(-((cal.component(.weekday, from: date) + 5) % 7), to: cal.startOfDay(for: date)) }
    private func teachingWeek(_ date: Date, _ term: AcademicCalendarData.Term) -> Int? { let week = TimetableRules.week(at: date, firstMonday: AcademicCalendarData.date(term.semesterStart)); return week.flatMap { (1...(term.teachingWeeks ?? 20)).contains($0) ? $0 : nil } }
    private func events(_ date: Date, _ term: AcademicCalendarData.Term) -> [AcademicCalendarData.Event] { let iso = AcademicCalendarRules.day(date); return term.events.filter { iso >= $0.start && ($0.type == "vacation_start" || iso <= $0.end) } }
    private func targetRow(_ term: AcademicCalendarData.Term) -> Date { let today = AcademicCalendarRules.day(.now), start = term.events.first { $0.type == "opening" }?.start ?? term.semesterStart; return today >= start && today <= (term.calendarEnd ?? term.semesterEnd) ? monday(.now) : monday(AcademicCalendarData.date(term.semesterStart) ?? .now) }
    private func weekRow(_ start: Date, _ term: AcademicCalendarData.Term) -> some View {
        HStack(spacing: 0) {
            Text(teachingWeek(start, term).map(String.init) ?? "—").font(.system(size: 12)).foregroundStyle(accent).frame(width: 36)
            ForEach(0..<7) { offset in
                let date = AcademicCalendarRules.adding(offset, to: start), cal = AcademicCalendarRules.calendar
                let current = cal.isDateInToday(date), event = events(date, term)
                let marker = event.contains { $0.type == "practice" } ? "实践" : event.contains { $0.type == "vacation" || $0.type == "vacation_start" } ? "假期" : event.isEmpty ? "" : "事件"
                let iso = AcademicCalendarRules.day(date), visible = iso >= (term.calendarStart ?? term.semesterStart) && iso <= (term.calendarEnd ?? term.semesterEnd)
                Button { selected = date } label: { VStack(spacing: 7) { Text(visible ? (offset == 0 || cal.component(.day, from: date) == 1 ? "\(cal.component(.month, from: date))/\(cal.component(.day, from: date))" : String(cal.component(.day, from: date))) : "").font(.system(size: 13, weight: current ? .bold : .regular)).foregroundStyle(.primary); Text(visible ? marker : "").font(.system(size: 9)).foregroundStyle(marker == "实践" ? accent : .secondary) }.frame(maxWidth: .infinity).frame(height: 62).background(current ? accent.opacity(0.2) : .clear).border(.secondary.opacity(0.15), width: 0.5) }.buttonStyle(.plain).disabled(!visible)
            }
        }.background(start == monday(.now) ? accent.opacity(0.08) : ChuannongTheme.card)
    }
    private func dayDescription(_ date: Date, _ term: AcademicCalendarData.Term) -> String { let events = events(date, term).map { $0.name + ($0.type == "vacation_start" ? "（结束日期未公布）" : "") }; return (teachingWeek(date, term).map { "第\($0)教学周" } ?? "非教学周") + "\n" + (events.isEmpty ? "暂无校历事件" : events.joined(separator: "\n")) }
}

@MainActor enum CourseNotifications {
    static let prefix = "cn.course."
    private static var generation = 0
    private static var pendingWork: Task<Int, Error>?
    private static var workID = UUID()
    static func ownerKey(_ owner: String) -> String {
        SHA256.hash(data: Data(owner.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static func key(_ course: Course, owner: String) -> String {
        let content = [owner, course.name, course.teacher, course.room, String(course.weekday), String(course.start), String(course.length), course.weeks.map(String.init).joined(separator: ","), course.term, course.source].joined(separator: "|")
        return SHA256.hash(data: Data(content.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static func rebuild(_ snapshot: AcademicSnapshot) async throws -> Int {
        generation += 1; let epoch = generation
        return try await enqueue {
            guard epoch == generation else { throw CancellationError() }
            return try await apply(snapshot, epoch: epoch)
        }
    }
    private static func enqueue(_ action: @escaping @MainActor () async throws -> Int) async throws -> Int {
        let previous = pendingWork, identifier = UUID()
        // An in-flight system add must finish before a newer rebuild clears the queue.
        let operation = Task { @MainActor in
            if let previous { _ = try? await previous.value }
            return try await action()
        }
        pendingWork = operation; workID = identifier
        defer { if workID == identifier { pendingWork = nil } }
        return try await operation.value
    }
    static func snooze(identifier: String, title: String, body: String, starts: Double, expectedOwner: String) async throws {
        let epoch = generation
        _ = try await enqueue {
            guard epoch == generation,
                  UserDefaults.standard.bool(forKey:"reminders.enabled"),
                  UserDefaults.standard.object(forKey:"reminders.snooze") as? Bool ?? true,
                  Date.now.timeIntervalSince1970 + 300 < starts,
                  let data = try SecureStore.read("identity", realm: "school"),
                  let identity = try? JSONDecoder().decode(SchoolIdentity.self, from: data),
                  ownerKey(identity.studentID) == expectedOwner else { return 0 }
            let content = UNMutableNotificationContent()
            let details = UserDefaults.standard.object(forKey: "reminders.details") as? Bool ?? true
            content.title = details ? title : "课程提醒"
            content.body = details ? body : "你有一节课程即将开始"
            content.categoryIdentifier = "COURSE_SNOOZE"
            content.userInfo = ["startsAt": starts, "route": "schedule", "ownerKey": expectedOwner]
            if !UserDefaults.standard.bool(forKey: "reminders.silent") { content.sound = .default }
            try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: identifier + ".snooze", content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 300, repeats: false)))
            return 1
        }
    }
    private static func apply(_ snapshot: AcademicSnapshot, epoch: Int) async throws -> Int {
        let center = UNUserNotificationCenter.current()
        let old = await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix(prefix) }
        guard epoch == generation else { throw CancellationError() }
        center.removePendingNotificationRequests(withIdentifiers: old.map(\.identifier))
        let delivered = await center.deliveredNotifications().filter { $0.request.identifier.hasPrefix(prefix) }
        guard epoch == generation else { throw CancellationError() }
        center.removeDeliveredNotifications(withIdentifiers: delivered.map { $0.request.identifier })
        guard UserDefaults.standard.bool(forKey: "reminders.enabled"), !snapshot.owner.isEmpty else { return 0 }
        let settings = await center.notificationSettings()
        guard epoch == generation else { throw CancellationError() }
        guard [.authorized, .provisional].contains(settings.authorizationStatus) else { throw APIError.server(422, "通知权限未开启，请在系统设置中允许通知") }
        let disabled = Set(UserDefaults.standard.stringArray(forKey: "reminders.disabled") ?? [])
        let ids = Set(snapshot.courses.filter { disabled.contains(key($0, owner: snapshot.owner)) }.map(\.id))
        let lead = UserDefaults.standard.object(forKey: "reminders.lead") as? Int ?? 15
        var calibrated=snapshot
        if calibrated.termStarts[snapshot.term]==nil{calibrated.termStarts[snapshot.term]=BundledAcademic.firstMonday(snapshot.term,snapshot:snapshot)}
        let plan = ReminderPlan.occurrences(snapshot: calibrated, periods: CoursePeriods.current, leadMinutes: lead, now: .now, disabled: ids).prefix(60)
        for occurrence in plan {
            guard epoch == generation else { throw CancellationError() }
            let content = UNMutableNotificationContent()
            let details = UserDefaults.standard.object(forKey: "reminders.details") as? Bool ?? true
            content.title = details ? occurrence.course.name : "课程提醒"
            content.body = details ? "\(occurrence.course.room) · \(occurrence.course.scheduleLabel) · 即将上课" : "你有一节课程即将开始"
            content.categoryIdentifier = (UserDefaults.standard.object(forKey:"reminders.snooze") as? Bool ?? true) ? "COURSE_SNOOZE" : "COURSE"
            content.userInfo=["startsAt":occurrence.startsAt.timeIntervalSince1970,"route":"schedule","ownerKey":ownerKey(snapshot.owner)]
            if !UserDefaults.standard.bool(forKey: "reminders.silent") { content.sound = .default }
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
            var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: occurrence.firesAt); components.timeZone = calendar.timeZone
            let identifier = prefix + key(occurrence.course, owner: snapshot.owner) + "." + String(Int(occurrence.startsAt.timeIntervalSince1970))
            try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
        }
        return plan.count
    }
}

struct ReminderSettingsView: View {
    @Environment(SchoolSession.self) private var school
    @AppStorage("reminders.enabled") private var enabled = false
    @AppStorage("reminders.lead") private var lead = 15
    @AppStorage("reminders.silent") private var silent = false
    @AppStorage("reminders.details") private var details = true
    @AppStorage("reminders.snooze") private var snooze = true
    @State private var disabled = Set<String>()
    @State private var busy = false
    @State private var message: String?
    var body: some View {
        SchoolGate {
            Form {
                Section {
                    Toggle("课程提醒", isOn: Binding(get: { enabled }, set: { value in setEnabled(value) })).disabled(busy)
                    Picker("提前提醒", selection: $lead) { ForEach([5, 10, 15, 20, 30], id: \.self) { Text("\($0) 分钟").tag($0) } }
                    Toggle("静音提醒", isOn: $silent); Toggle("显示课程和教室", isOn: $details)
                    Toggle("允许稍后提醒",isOn:$snooze)
                    NavigationLink("课程作息时间"){CourseTimeSettingsView()}
                }
                Section("提醒课程") {
                    ForEach(school.snapshot.courses.filter { $0.term == school.snapshot.term }) { course in
                        let key = CourseNotifications.key(course, owner: school.snapshot.owner)
                        Toggle(course.name + " · " + course.scheduleLabel, isOn: Binding(get: { !disabled.contains(key) }, set: { value in if value { disabled.remove(key) } else { disabled.insert(key) }; UserDefaults.standard.set(Array(disabled), forKey: "reminders.disabled"); rebuild() }))
                    }
                }
                Section {
                    Button("重新安排提醒") { rebuild() }.frame(maxWidth:.infinity).disabled(busy)
                    if let message { StatusMessage(text: message) }
                }
            }.onAppear { disabled = Set(UserDefaults.standard.stringArray(forKey: "reminders.disabled") ?? []) }
                .onChange(of: lead) { _, _ in rebuild() }.onChange(of: silent) { _, _ in rebuild() }.onChange(of: details) { _, _ in rebuild() }.onChange(of:snooze){_,_ in rebuild()}
        }.navigationTitle("课程提醒")
    }
    private func setEnabled(_ value: Bool) {
        busy = true
        Task {
            defer { busy = false }
            do {
                if value { guard try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) else { message = "通知未获允许，可在系统设置中开启"; return } }
                enabled = value; let count = try await CourseNotifications.rebuild(school.snapshot)
                message = value ? "已安排 \(count) 次提醒；请确认课表周次已校准" : "课程提醒已关闭"
            } catch { message = error.localizedDescription }
        }
    }
    private func rebuild() { Task { do { let count = try await CourseNotifications.rebuild(school.snapshot); message = "已安排 \(count) 次提醒" } catch { message = error.localizedDescription } } }
}

@MainActor @Observable final class LedgerStore {
    private(set) var items: [LedgerEntry] = []
    var error: String?
    private var file: URL?
    func load(owner: String) {
        do {
            let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "Ledger", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var values = URLResourceValues(); values.isExcludedFromBackup = true; var directory = folder; try directory.setResourceValues(values)
            let key = SHA256.hash(data: Data(owner.utf8)).map { String(format: "%02x", $0) }.joined()
            file = folder.appending(path: key + ".json")
            if FileManager.default.fileExists(atPath: file!.path) { items = try JSONDecoder().decode([LedgerEntry].self, from: Data(contentsOf: file!)) } else { items = [] }
        } catch { self.error = "本机账本读取失败，原文件已保留：" + error.localizedDescription; file = nil; items = [] }
    }
    func save(_ entry: LedgerEntry) throws { var next = items; next.removeAll { $0.id == entry.id }; next.append(entry); try write(next) }
    func remove(_ entry: LedgerEntry) throws { try write(items.filter { $0.id != entry.id }) }
    private func write(_ value: [LedgerEntry]) throws {
        guard let file else { throw APIError.server(422, "账本尚未就绪") }
        try JSONEncoder().encode(value).write(to: file, options: [.atomic, .completeFileProtection]); items = value
    }
}

struct LedgerView: View {
    @Environment(SchoolSession.self) private var school
    @State private var store = LedgerStore()
    @State private var editing: LedgerEntry?
    @State private var deleting: LedgerEntry?
    var body: some View {
        SchoolGate {
            List {
                Section("物品账本") {
                    LabeledContent("总价值", value: money(store.items.reduce(0) { $0 + $1.amount }))
                    LabeledContent("日均使用成本", value: money(store.items.reduce(0) { $0 + $1.dailyCost(at: .now) }))
                }
                if let error = store.error { StatusMessage(text: error) }
                if store.items.isEmpty { Text("还没有物品，点击加号开始记录").foregroundStyle(.secondary) }
                ForEach(store.items.sorted { $0.purchasedAt > $1.purchasedAt }) { item in
                    Button { editing = item } label: {
                        VStack(alignment: .leading, spacing: 8) { Text(item.name).font(.headline); Text("\(item.category) · \(money(item.amount)) · 日均 \(money(item.dailyCost(at: .now)))").font(.subheadline).foregroundStyle(.secondary) }
                    }.buttonStyle(.plain).swipeActions { Button("删除", role: .destructive) { deleting = item } }
                }
            }.toolbar { Button { editing = LedgerEntry(name: "", amount: 0, purchasedAt: .now, category: "其他") } label: { Image(systemName: "plus") }.accessibilityLabel("添加物品") }
            .sheet(item: $editing) { item in NavigationStack { LedgerEditor(item: item, store: store) } }
            .confirmationDialog("删除这条物品记录？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) { if let item = deleting { Button("删除", role: .destructive) { do { try store.remove(item) } catch { store.error = error.localizedDescription }; deleting = nil } } }
        }.navigationTitle("本机记账").task(id: school.snapshot.owner) { if school.isBound { store.load(owner: school.snapshot.owner) } }
    }
    private func money(_ value: Decimal) -> String { value.formatted(.currency(code: "CNY")) }
}

struct LedgerEditor: View {
    @State var item: LedgerEntry
    let store: LedgerStore
    @State private var amount = ""
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Form {
            TextField("物品名称", text: $item.name)
            TextField("购买价格", text: $amount).keyboardType(.decimalPad)
            DatePicker("购买日期", selection: $item.purchasedAt, in: ...Date.now, displayedComponents: .date)
            Picker("分类", selection: $item.category) { ForEach(["手机", "电脑", "笔记本电脑", "平板电脑", "耳机", "自行车", "游戏", "游戏设备", "电子手表", "手表", "其他"], id: \.self) { Text($0).tag($0) } }
            if let error { StatusMessage(text: error) }
        }.navigationTitle("物品记录").onAppear { amount = item.amount > 0 ? NSDecimalNumber(decimal: item.amount).stringValue : "" }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("保存") {
                guard !item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, item.name.count <= 80, let number = LedgerEntry.amount(amount) else { error = "请填写物品名称与有效金额（最多两位小数）"; return }
                item.amount = number; do { try store.save(item); dismiss() } catch { self.error = error.localizedDescription }
            } }
        }
    }
}
