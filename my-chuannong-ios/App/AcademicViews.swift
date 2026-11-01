import SwiftUI
import UniformTypeIdentifiers

struct CourseRow: View {
    let course: Course
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            RoundedRectangle(cornerRadius: 3).fill(ChuannongTheme.green).frame(width: 4)
            VStack(alignment: .leading, spacing: 6) {
                Text(course.name).font(.headline)
                Text(course.scheduleLabel).font(.subheadline)
                Text([course.room, course.teacher].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }.fixedSize(horizontal: false, vertical: true)
    }
}

struct TimetableView: View {
    @Environment(SchoolSession.self) private var school
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var week = 1
    @State private var term = ""
    @State private var editor: Course?
    @State private var selection: CourseSelection?
    @State private var deleting: Course?
    @State private var notes = false
    @State private var browser = false
    @State private var error: String?
    private var terms: [String] {
        let published = BundledAcademic.data?.terms.map(\.id) ?? []
        let latest = published.compactMap { Int($0.prefix(4)) }.max() ?? AcademicCalendarRules.calendar.component(.year, from: .now)
        let admission = school.snapshot.admissionYear
        let history = admission.map { (0...8).contains(latest - $0) ? ($0...latest).flatMap { ["\($0)-\($0+1)-1", "\($0)-\($0+1)-2"] } : [] } ?? []
        return Set(published + history + school.snapshot.courses.map(\.term) + [school.snapshot.term]).filter { !$0.isEmpty }.sorted().reversed()
    }
    private var selectedTerm: String { term.isEmpty ? (school.snapshot.term.isEmpty ? BundledAcademic.currentTerm(at: .now)?.id ?? terms.first ?? "" : school.snapshot.term) : term }
    private var totalWeeks: Int { BundledAcademic.data?.terms.first { $0.id == selectedTerm }?.teachingWeeks ?? 20 }
    private var currentWeek: Int { min(totalWeeks, max(1, TimetableRules.week(at: .now, firstMonday: BundledAcademic.firstMonday(selectedTerm, snapshot: school.snapshot)) ?? 1)) }
    private var teaching: Bool { BundledAcademic.data?.terms.first { $0.id == selectedTerm }.map { AcademicCalendarRules.isTeaching($0, at: .now) } ?? false }
    private var allCourses: [Course] { school.snapshot.courses.filter { $0.term == selectedTerm } }
    var body: some View {
        SchoolGate {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Menu { ForEach(terms, id: \.self) { value in Button(termTitle(value) + " · " + value) { term = value; week = 1 } } } label: { Label(termTitle(selectedTerm), systemImage: "calendar").font(.system(size: 14, weight: .semibold)).padding(10).background(ChuannongTheme.card, in: Capsule()) }
                        Spacer(minLength: 0)
                        Menu {
                            Picker("周次", selection: $week) {
                                ForEach(1...totalWeeks, id: \.self) { Text("第 \($0) 周").tag($0) }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text("第 \(week) 周")
                                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
                            }
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                            .frame(minHeight: 44)
                        }.accessibilityLabel("周次，第 \(week) 周")
                        Button { notes = true } label: { Image(systemName: "info.circle").font(.system(size: 20)).frame(width: 34, height: 44) }.accessibilityLabel("课表备注与入学年份")
                        Button(teaching ? "本周" : "非行课期") { if teaching { withAnimation(reduceMotion ? nil : .easeInOut) { week = currentWeek } } else { error = "所选学期当前不在行课期" } }.font(.system(size: 11)).padding(.horizontal, 10).frame(minHeight: 44).background(ChuannongTheme.green.opacity(0.1), in: Capsule())
                    }.padding(.horizontal, 14)
                    SyncStatus(page: .courses).padding(.horizontal, 16)
                    if let error { StatusMessage(text: error).padding(.horizontal, 16) }
                    if BundledAcademic.firstMonday(selectedTerm, snapshot: school.snapshot) == nil { Text("该学期暂无校历日期").font(.system(size: 12)).foregroundStyle(.secondary).padding(.horizontal, 16) }
                    if allCourses.isEmpty { Text("当前学期暂无本机课表，点击刷新读取学校课表；也可点击空白格添加自定义课程。").font(.system(size: 12)).foregroundStyle(.secondary).padding(.horizontal, 16) }
                    if dynamicTypeSize.isAccessibilitySize {
                        ForEach(allCourses.filter { $0.weeks.contains(week) }.sorted { ($0.weekday, $0.start) < ($1.weekday, $1.start) }) { course in Button { open(course) } label: { CourseRow(course: course) }.buttonStyle(.plain).padding(.horizontal, 18) }
                    } else {
                        TabView(selection: $week) {
                            ForEach(1...totalWeeks, id: \.self) { number in
                                TimetableWeekGrid(week: number, firstMonday: BundledAcademic.firstMonday(selectedTerm, snapshot: school.snapshot), courses: allCourses, onCourse: open, onLongPress: longPress, onEmpty: { day, start in editor = Course(name: "", weekday: day, start: start, length: min(2, 11 - start), weeks: [number], term: selectedTerm, source: "MANUAL") }).padding(.horizontal, 12).tag(number)
                            }
                        }.tabViewStyle(.page(indexDisplayMode: .never)).frame(height: 710)
                    }
                }.padding(.vertical, 8)
            }.background(LinearGradient(colors: [ChuannongTheme.green.opacity(0.08), ChuannongTheme.background, ChuannongTheme.background], startPoint: .top, endPoint: .bottom))
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu { Button("打开学校课表同步") { browser = true }; NavigationLink("课程作息时间") { CourseTimeSettingsView() }; Button("添加自定义课程") { editor = Course(name: "", weekday: 1, start: 1, length: 2, weeks: [week], term: selectedTerm, source: "MANUAL") } } label: { Image(systemName: "ellipsis") }.accessibilityLabel("课表选项")
                    SchoolRefresh(page: .courses)
                }
            }
            .sheet(isPresented: Binding(get: { school.pendingImport != nil && !browser }, set: { if !$0 && !browser { school.cancelImport() } })) { if let batch = school.pendingImport { NavigationStack { TimetableImportView(batch: batch) }.environment(school) } }
            .sheet(item: $editor) { course in NavigationStack { CourseEditor(course: course) }.environment(school) }
            .sheet(item: $selection) { selection in NavigationStack { CourseSelectionView(courses: selection.courses) }.environment(school) }
            .sheet(isPresented: $notes) { NavigationStack { TimetableNotesView(term: selectedTerm) }.environment(school) }
            .sheet(isPresented: $browser) { NavigationStack { TimetableSchoolImportView() }.environment(school) }
            .confirmationDialog("删除课程", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) { if let deleting { Button("删除", role: .destructive) { do { try school.removeCourse(deleting) } catch { self.error = error.localizedDescription }; self.deleting = nil } } } message: { Text("确定删除该自定义课程吗？") }
        }.navigationTitle("课程表").navigationBarTitleDisplayMode(.inline)
        .onAppear { week = currentWeek }
        .onChange(of: school.snapshot.term) { _, value in if !value.isEmpty { term = value; week = currentWeek } }
    }
    private func termTitle(_ raw: String) -> String {
        let parts = raw.split(separator: "-"); guard parts.count == 3, let start = Int(parts[0]), let end = Int(parts[1]), end == start + 1 else { return raw }
        if let admission = school.snapshot.admissionYear, (0...3).contains(start - admission) { return ["大一", "大二", "大三", "大四"][start-admission] + (parts[2] == "1" ? "上" : "下") }
        return parts[2] == "1" ? "\(start)秋" : "\(end)春"
    }
    private func open(_ course: Course) { let overlap = allCourses.filter { $0.weeks.contains(week) && $0.weekday == course.weekday && $0.start < course.start + course.length && course.start < $0.start + $0.length }; selection = CourseSelection(courses: [course] + overlap.filter { $0.id != course.id }) }
    private func longPress(_ course: Course) { if course.source != "MANUAL" { error = "仅支持删除自定义课程" } else { deleting = course } }
}
private struct CourseSelection: Identifiable { let id = UUID(); let courses: [Course] }
private struct CourseSelectionView: View {
    let courses: [Course]
    @State private var index = 0
    @Environment(\.dismiss) private var dismiss
    var body: some View { CourseDetail(course: courses[index], onDone: { if index + 1 < courses.count { index += 1 } else { dismiss() } }).id(index).safeAreaInset(edge: .bottom) { if courses.count > 1 { Text("此时段共 \(courses.count) 门课程 · 当前第 \(index + 1) 门，点“完成”继续查看").font(.caption).foregroundStyle(.secondary).padding(14) } } }
}
private struct TimetableWeekGrid: View {
    let week: Int
    let firstMonday: Date?
    let courses: [Course]
    let onCourse: (Course) -> Void
    let onLongPress: (Course) -> Void
    let onEmpty: (Int, Int) -> Void
    private var visible: [Course] { courses.filter { $0.weeks.contains(week) }.sorted { ($0.start, $0.name, $0.id) < ($1.start, $1.name, $1.id) } }
    private var dates: [Date?] { (0..<7).map { offset in firstMonday.map { AcademicCalendarRules.adding((week - 1) * 7 + offset, to: $0) } } }
    var body: some View {
        GeometryReader { geometry in
            let width = max(1, (geometry.size.width - 48 - 8) / 7)
            VStack(spacing: 8) {
                HStack(spacing: 0) {
                    Text(dates[0].map { "\(AcademicCalendarRules.calendar.component(.month, from: $0))月" } ?? "日期").font(.system(size: 13, weight: .bold)).frame(width: 48)
                    ForEach(0..<7) { day in VStack(spacing: 4) { Text("周" + ["一", "二", "三", "四", "五", "六", "日"][day]).font(.system(size: 12, weight: .medium)); Text(dates[day].map { "\(AcademicCalendarRules.calendar.component(.day, from: $0))日" } ?? "—").font(.system(size: 10)) }.foregroundStyle(dates[day].map { AcademicCalendarRules.calendar.isDateInToday($0) } == true ? Color(hex: 0x4F7FED) : .primary).frame(width: width) }
                }.frame(height: 44).background(ChuannongTheme.card.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
                HStack(alignment: .top, spacing: 0) {
                    VStack(spacing: 0) { ForEach(CoursePeriods.current, id: \.section) { period in Text(period.start + "\n" + period.end).font(.system(size: 10, weight: .semibold)).multilineTextAlignment(.center).frame(width: 48, height: 64) } }
                    ForEach(1...7, id: \.self) { day in
                        ZStack(alignment: .top) {
                            VStack(spacing: 0) { ForEach(1...10, id: \.self) { start in Button { onEmpty(day, start) } label: { Color.clear.frame(height: 64).contentShape(Rectangle()).overlay(alignment: .bottom) { Rectangle().fill(.secondary.opacity(0.08)).frame(height: 0.5) } }.accessibilityLabel("周\(day) 第\(start)节，添加课程") } }
                            ForEach(visible.filter { $0.weekday == day }) { course in
                                Button { onCourse(course) } label: { VStack(spacing: 4) { Text(course.name).font(.system(size: 11, weight: .bold)).lineLimit(3); if !course.room.isEmpty { Text(course.room).font(.system(size: 10)).lineLimit(3) }; if !course.teacher.isEmpty { Text(course.teacher).font(.system(size: 9)).lineLimit(3) } }.foregroundStyle(Color(hex: 0x1C2B3A)).multilineTextAlignment(.center).padding(.horizontal, 2).padding(.top, 13).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).background(LinearGradient(colors: colors(course), startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 10)) }.buttonStyle(.plain).frame(width: max(1, width - 3), height: CGFloat(course.length) * 64 - 3).offset(y: CGFloat(course.start - 1) * 64).onLongPressGesture { onLongPress(course) }.accessibilityLabel("\(course.name)，\(course.scheduleLabel)，\(course.room)")
                            }
                        }.frame(width: width, height: 640)
                    }
                }.padding(.vertical, 6).background(ChuannongTheme.card.opacity(0.88), in: RoundedRectangle(cornerRadius: 20))
            }
        }
    }
    private func colors(_ course: Course) -> [Color] {
        let palette: [[UInt32]] = [[0xCDE8FF,0x8EC9F5],[0xB8F0CE,0x6BDAA0],[0xD8D0FF,0xA896F5],[0xFFE7B0,0xFFCA60],[0xFFCDD8,0xFF9AB8],[0xA8EFEC,0x5DD5D0],[0xFFD8B8,0xFFAA72],[0xCEF0A8,0x8ED460]]
        let index = Set(courses.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }).sorted().firstIndex(of: course.name.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        if index < palette.count { return palette[index].map { Color(hex: $0) } }
        return [Color(hue: Double(index * 37 % 360) / 360, saturation: 0.25, brightness: 0.96), Color(hue: Double(index * 37 % 360) / 360, saturation: 0.44, brightness: 0.88)]
    }
}

struct TimetableNotesView: View {
    let term: String
    @Environment(SchoolSession.self) private var school
    @Environment(\.dismiss) private var dismiss
    @State private var year = ""
    @State private var error: String?
    var body: some View {
        Form {
            Section("课表备注") { let notes = Set(school.snapshot.courses.filter { $0.term == term }.compactMap(\.sourceExcerpt) + school.snapshot.unscheduled).sorted(); if notes.isEmpty { Text("暂无课表备注").foregroundStyle(.secondary) }; ForEach(notes, id: \.self) { Text($0).textSelection(.enabled) } }
            Section("入学年份") { TextField("例如 2026", text: $year).keyboardType(.numberPad); Button("保存入学年份") { guard let value = Int(year) else { error = "请填写有效年份"; return }; do { try school.setAdmissionYear(value); error = "已保存" } catch { self.error = error.localizedDescription } }.frame(maxWidth:.infinity) }
            if let error { StatusMessage(text: error) }
        }.navigationTitle("课表备注").onAppear { year = school.snapshot.admissionYear.map(String.init) ?? "" }.toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
    }
}

struct TimetableSchoolImportView: View {
    @Environment(SchoolSession.self) private var school
    @Environment(\.dismiss) private var dismiss
    @State private var state = SchoolBrowserState()
    @State private var reading = false
    @State private var error: String?
    var body: some View {
        VStack(spacing: 0) {
            if let error = error ?? state.error { StatusMessage(text: error).padding(12) }
            if state.loading { ProgressView().padding(8) }
            if let route = school.route { SchoolWebPage(url: route.url(path: SchoolPage.courses.path), school: school, state: state) }
            else { Text("请先完成校园网络认证").padding() }
        }.navigationTitle("学校课表").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("返回") { dismiss() } }; ToolbarItem(placement: .bottomBar) { Button(reading ? "正在读取…" : "同步当前学校课表") { read() }.buttonStyle(.borderedProminent).disabled(reading || state.loading || state.web == nil) } }
        .sheet(isPresented: Binding(get: { school.pendingImport != nil }, set: { if !$0 { school.cancelImport() } })) { if let batch = school.pendingImport { NavigationStack { TimetableImportView(batch: batch) }.environment(school) } }
    }
    private func read() { guard let web = state.web, !reading else { return }; reading = true; Task { defer { reading = false }; do { let document = try await SchoolPageReader.document(web); try await school.stageTimetable(document) } catch { self.error = error.localizedDescription } } }
}

struct CourseDetail: View {
    let course: Course
    var onDone: (() -> Void)?
    @Environment(SchoolSession.self) private var school
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var deleting = false
    @State private var error: String?
    var body: some View {
        List {
            Section { Text(course.name).font(.title2.bold()); Text(course.scheduleLabel); Text(course.room); Text(course.teacher); Text(course.term); Text("周次：" + course.weeks.map(String.init).joined(separator: "、")) }
            if course.source == "MANUAL" {
                Button("编辑课程") { editing = true }.frame(maxWidth:.infinity)
                Button("删除本机课程", role: .destructive) { deleting = true }.frame(maxWidth:.infinity)
            } else { StatusMessage(text: "学校课程通过课表刷新更新，不在本机直接修改学校记录。") }
            if let error { StatusMessage(text: error) }
        }.navigationTitle("课程详情").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { if let onDone { onDone() } else { dismiss() } } } }
        .sheet(isPresented: $editing, onDismiss: { dismiss() }) { NavigationStack { CourseEditor(course: course) }.environment(school) }
        .confirmationDialog("删除这条本机课程？", isPresented: $deleting, titleVisibility: .visible) {
            Button("删除", role: .destructive) { do { try school.removeCourse(course); dismiss() } catch { self.error = error.localizedDescription } }
        }
    }
}

struct CourseEditor: View {
    @State var course: Course
    @State private var weeks = ""
    @State private var error: String?
    @Environment(SchoolSession.self) private var school
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Form {
            Section("课程信息") {
                TextField("课程名称", text: $course.name)
                TextField("教师", text: $course.teacher)
                TextField("教室", text: $course.room)
                TextField("学期，如 2026-2027-1", text: $course.term).textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            Section("上课时间") {
                Picker("星期", selection: $course.weekday) { ForEach(1...7, id: \.self) { Text("周" + ["一", "二", "三", "四", "五", "六", "日"][$0 - 1]).tag($0) } }
                Stepper("第 \(course.start) 节开始", value: $course.start, in: 1...10)
                Stepper("连续 \(course.length) 节", value: $course.length, in: 1...10)
                TextField("周次，如 1-16 或 1-16(单周)", text: $weeks)
            }
            if let error { StatusMessage(text: error) }
        }.navigationTitle("本机课程").navigationBarTitleDisplayMode(.inline)
        .onAppear { weeks = course.weeks.map(String.init).joined(separator: ",") }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("保存") {
                do { course.weeks = try TimetableRules.weeks(weeks); try school.saveCourse(course); dismiss() } catch { self.error = error.localizedDescription }
            } }
        }
    }
}

struct TermCalibration: View {
    let term: String
    @Environment(SchoolSession.self) private var school
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date.now
    @State private var error: String?
    var body: some View {
        Form {
            Section("\(term) 第一周") {
                DatePicker("第一周周一", selection: $date, displayedComponents: .date)
                Text("以学校公布的校历为准，校准后用于首页今日课程与当前周次。").font(.footnote).foregroundStyle(.secondary)
            }
            if let error { StatusMessage(text: error) }
        }.navigationTitle("校准周次").navigationBarTitleDisplayMode(.inline)
        .onAppear { date = school.snapshot.termStarts[term] ?? .now }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("保存") {
                var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
                guard calendar.component(.weekday, from: date) == 2 else { error = "请选择第一周的周一"; return }
                do { try school.setTermStart(date, term: term); dismiss() } catch { self.error = error.localizedDescription }
            } }
        }
    }
}

struct GradesView: View {
    @Environment(SchoolSession.self) private var school
    @State private var collapsed = Set<String>()
    @State private var selected: GradeRecord?
    @State private var web = false
    private var terms: [String] { var seen = Set<String>(); return school.snapshot.grades.map { $0.term.isEmpty ? "个人成绩单" : $0.term }.filter { seen.insert($0).inserted } }
    var body: some View {
        SchoolGate {
            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) { metric("加权平均成绩", names: ["加权平均成绩"], size: 32); metric("平均成绩绩点", names: ["平均成绩绩点", "平均绩点"], size: 24, green: true) }
                    Spacer(minLength: 16)
                    VStack(alignment: .trailing, spacing: 8) { metric("专业排名", names: ["专业排名", "有效必修加权排名", "本人排名", "排名", "名次"], size: 32, alignment: .trailing); metric("有效学分", names: ["有效学分"], size: 24, alignment: .trailing) }
                }.padding(16).background(ChuannongTheme.card, in: RoundedRectangle(cornerRadius: 20)).padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 12)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 12) {
                            SyncStatus(page: .grades)
                            if !school.authenticationNeeded.contains("grades") { Button("打开教务成绩网页") { web = true }.frame(maxWidth:.infinity).disabled(school.busy) }
                            Text("有效必修加权排名").font(.system(size: 16, weight: .bold))
                            if let report = school.snapshot.transcript { ForEach(report.ranking) { Text($0.name + "：" + $0.value).font(.system(size: 14)) } }
                            else { Text("尚未获取本人排名").font(.system(size: 14)).foregroundStyle(.secondary) }
                            if let error = school.errors["ranking"] { StatusMessage(text: error) }
                        }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(ChuannongTheme.card, in: RoundedRectangle(cornerRadius: 10))
                        if school.snapshot.grades.isEmpty { Text(school.snapshot.updated["grades"] == nil ? "请刷新获取本人已公布成绩" : "个人成绩单暂无成绩数据").foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 40) }
                        ForEach(terms, id: \.self) { term in
                            VStack(spacing: 0) {
                                Button { if !collapsed.insert(term).inserted { collapsed.remove(term) } } label: {
                                    HStack { VStack(alignment: .leading, spacing: 4) { Text(term).font(.system(size: 16, weight: .bold)) }; Spacer(); Image(systemName: collapsed.contains(term) ? "chevron.down" : "chevron.up").foregroundStyle(.secondary) }.padding(.horizontal, 10).padding(.vertical, 14)
                                }.buttonStyle(.plain).accessibilityLabel(term + (collapsed.contains(term) ? "，展开" : "，折叠"))
                                if !collapsed.contains(term) {
                                    ForEach(school.snapshot.grades.filter { ($0.term.isEmpty ? "个人成绩单" : $0.term) == term }) { grade in
                                        Divider()
                                        Button { selected = grade } label: {
                                            HStack(alignment: .top, spacing: 12) {
                                                VStack(alignment: .leading, spacing: 6) {
                                                    Text(grade.name).font(.system(size: 16, weight: .bold))
                                                    if !grade.nature.isEmpty { Text(grade.nature).font(.system(size: 12)).padding(.horizontal, 8).padding(.vertical, 3).foregroundStyle(ChuannongTheme.green).background(ChuannongTheme.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 4)) }
                                                    Text("学分：" + (grade.credit.isEmpty ? "未提供" : grade.credit)).font(.system(size: 14)).foregroundStyle(.secondary)
                                                    if let number = grade.number, !number.isEmpty { Text("课程序号：" + number).font(.system(size: 14)).foregroundStyle(.secondary) }
                                                    if !grade.remarks.isEmpty { Text("备注：" + grade.remarks).font(.system(size: 14)).foregroundStyle(.secondary) }
                                                }; Spacer(minLength: 0); Text(grade.grade).font(.system(size: 24, weight: .bold)).foregroundStyle(ChuannongTheme.green).fixedSize(horizontal: true, vertical: false)
                                            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                                        }.buttonStyle(.plain)
                                    }
                                }
                            }.background(ChuannongTheme.card, in: RoundedRectangle(cornerRadius: 10))
                        }
                    }.padding(.horizontal, 15).padding(.vertical, 10)
                }.refreshable { await school.sync(.grades) }
            }.background(ChuannongTheme.background).toolbar { SchoolRefresh(page: .grades) }
        }.navigationTitle("成绩查询").navigationBarTitleDisplayMode(.inline)
        .alert(item: $selected) { grade in Alert(title: Text(grade.name), message: Text("课程成绩：\(grade.grade)\n课程学分：\(grade.credit)\n课程性质：\(grade.nature)\n课程序号：\(grade.number ?? "")\n备注：\(grade.remarks)"), dismissButton: .default(Text("确定"))) }
        .sheet(isPresented: $web) { if let route = school.route { NavigationStack { SchoolBrowserView(url: route.url(path: "/xuesheng/chengji/chengji/bchengjike.asp"), title: "教务成绩查询") }.environment(school) } }
    }
    private func metric(_ label: String, names: [String], size: CGFloat, green: Bool = false, alignment: HorizontalAlignment = .leading) -> some View {
        VStack(alignment: alignment, spacing: 4) { Text(label).font(.system(size: 14)).foregroundStyle(.secondary); Text(school.snapshot.transcript?.field(names) ?? "--").font(.system(size: size, weight: .bold)).foregroundStyle(green ? ChuannongTheme.green : .primary).minimumScaleFactor(0.7) }
    }
}

struct ExamsView: View {
    @Environment(SchoolSession.self) private var school
    var body: some View {
        SchoolGate {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 30) {
                    SyncStatus(page: .exams)
                    if school.snapshot.exams.isEmpty {
                        Text(school.errors["exams"] ?? (school.snapshot.updated["exams"] == nil ? "请刷新获取本人考试安排" : "查询成功，暂无数据")).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 60)
                    }
                    ForEach(school.snapshot.exams) { exam in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(exam.name).font(.system(size: 19, weight: .bold)).padding(.top, 10)
                            Label(exam.time, systemImage: "clock").font(.system(size: 17, weight: .bold))
                            Label(exam.room, systemImage: "mappin.and.ellipse").font(.system(size: 17, weight: .bold))
                            if !exam.seat.isEmpty { Label("座位：" + exam.seat, systemImage: "chair").font(.system(size: 17, weight: .bold)) }
                            if !exam.campus.isEmpty { Text(exam.campus).font(.subheadline) }
                            if !exam.notes.isEmpty { Text(exam.notes).foregroundStyle(.secondary) }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(10).background(ChuannongTheme.card, in: RoundedRectangle(cornerRadius: 8)).shadow(color: .black.opacity(0.06), radius: 5, y: 2).textSelection(.enabled)
                    }
                }.padding(16)
            }.background(ChuannongTheme.background).refreshable { await school.sync(.exams) }.toolbar { SchoolRefresh(page: .exams) }
        }.navigationTitle("考试安排").navigationBarTitleDisplayMode(.inline)
    }
}
