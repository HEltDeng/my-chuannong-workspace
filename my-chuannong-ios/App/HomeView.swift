import SwiftUI

struct HomeView: View {
    @Environment(SchoolSession.self) private var school
    @AppStorage("home.scoresVisible") private var scoresVisible = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let model = HomeDay(snapshot: school.snapshot, now: context.date)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(StudentPresentation.greeting(school.identity?.name)).font(.system(size: 34, weight: .black))
                        Text(model.dateText).font(.system(size: 15, weight: .semibold)).foregroundStyle(.secondary)
                    }.padding(.bottom, 8)
                    sectionTitle(model.tomorrow ? "明日课程" : "今日课程", route: .schedule)
                    NavigationLink { TimetableView() } label: {
                        VStack(alignment: .leading, spacing: 14) {
                            if model.courses.isEmpty {
                                HStack(spacing: 12) {
                                    Image(systemName: "calendar").font(.system(size: 22))
                                    Text(!school.isBound ? "先绑定学号 · 点击进入课表" : school.snapshot.courses.isEmpty ? "暂无本学期课表缓存 · 点击进入课表获取数据" : "\(model.tomorrow ? "明日" : "今日")没有课程 · 点击查看完整课表").font(.system(size: 18, weight: .bold))
                                }.frame(maxWidth: .infinity).padding(.vertical, 10)
                            } else {
                                ForEach(Array(model.courses.enumerated()), id: \.element.id) { index, course in
                                    let color=Color(hex: [0x5E87F6,0x45B979,0xF08D3C,0xB974F0][index % 4])
                                    HStack(alignment: .top, spacing: 14) {
                                        RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 6)
                                        VStack(alignment: .leading, spacing: 7) {
                                            Text(course.name).font(.system(size: 18, weight: .black))
                                            Text(model.time(course) + " · " + (course.room.isEmpty ? "教室待定" : course.room)).font(.system(size: 14, weight: .semibold)).foregroundStyle(color)
                                            Text(course.teacher.isEmpty ? "教师待定" : course.teacher).font(.system(size: 13)).foregroundStyle(.secondary)
                                        }
                                        Spacer(minLength: 0)
                                    }.fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(18).background(ChuannongTheme.card, in: RoundedRectangle(cornerRadius: 28))
                    }.buttonStyle(.plain)
                    sectionTitle("成绩汇总", route: .grade)
                    ZStack(alignment: .topTrailing) {
                        if scoresVisible {
                            NavigationLink { FeatureDestination(route: .grade) } label: {
                                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 14) {
                                    score("加权平均成绩", names: ["加权平均成绩"])
                                    score("专业排名", names: ["专业排名","有效必修加权排名","本人排名","排名","名次"], trailing: true)
                                    score("平均成绩绩点", names: ["平均成绩绩点","平均绩点"])
                                    score("有效学分", names: ["有效学分"])
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal,18).padding(.vertical,14)
                                    .contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityIdentifier("home-grades-summary")
                        }
                        Button {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { scoresVisible.toggle() }
                        } label: { Image(systemName: scoresVisible ? "eye" : "eye.slash").frame(width: 48, height: 48) }
                            .foregroundStyle(.secondary).accessibilityLabel(scoresVisible ? "折叠成绩汇总" : "展开成绩汇总").accessibilityIdentifier("home-grades-visibility").padding(.trailing,4)
                    }.frame(maxWidth: .infinity, minHeight: 48).background(ChuannongTheme.card, in: RoundedRectangle(cornerRadius: 28))
                    sectionTitle("考试安排", route: .exam)
                    if school.snapshot.exams.isEmpty {
                        NavigationLink { ExamsView() } label: {
                            Text(!school.isBound ? "先绑定学号" : school.errors["exams"] ?? (school.snapshot.updated["exams"] == nil ? "尚未同步" : "暂无考试安排"))
                                .font(.system(size: 17, weight: .semibold)).frame(maxWidth: .infinity, alignment: .leading).padding(22).background(ChuannongTheme.card, in: RoundedRectangle(cornerRadius: 24))
                        }.buttonStyle(.plain)
                    } else {
                        ForEach(school.snapshot.exams.prefix(3)) { exam in
                            NavigationLink { ExamsView() } label: {
                                VStack(alignment: .leading, spacing: 9) {
                                    Text(exam.name).font(.headline); Text(exam.time).font(.subheadline)
                                    Text([exam.campus, exam.room].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(20).background(ChuannongTheme.card, in: RoundedRectangle(cornerRadius: 24))
                            }.buttonStyle(.plain)
                        }
                    }
                }.padding(.horizontal,20).padding(.top,12).padding(.bottom,28)
            }.background(ChuannongTheme.background).toolbar(.hidden, for: .navigationBar)
        }
    }
    private func sectionTitle(_ title:String,route:FeatureRoute)->some View {
        HStack { Text(title).font(.system(size:26,weight:.black)).accessibilityAddTraits(.isHeader); Spacer(); NavigationLink("查看全部") { FeatureDestination(route:route) }.font(.subheadline.weight(.semibold)).accessibilityIdentifier("home-view-all-" + route.id) }
    }
    private func score(_ title:String,names:[String],trailing:Bool=false)->some View {
        VStack(alignment:.leading,spacing:4) {
            Text(title).font(.system(size:13)).foregroundStyle(.secondary)
            Text(school.snapshot.transcript?.field(names) ?? "--").font(.system(size:28,weight:.bold)).foregroundStyle(title == "平均成绩绩点" ? ChuannongTheme.green : .primary).minimumScaleFactor(0.7)
        }.padding(.trailing,trailing ? 40 : 0)
    }
}

@MainActor private struct HomeDay {
    let snapshot:AcademicSnapshot
    let now:Date
    private var calendar:Calendar { var c=Calendar(identifier:.gregorian);c.timeZone=TimeZone(identifier:"Asia/Shanghai")!;return c }
    var tomorrow:Bool {
        let parts=(CoursePeriods.current.last?.end ?? "21:10").split(separator:":").compactMap{Int($0)}
        return calendar.component(.hour,from:now)*60+calendar.component(.minute,from:now) >= (parts.first ?? 21)*60+(parts.last ?? 10)
    }
    var target:Date{calendar.date(byAdding:.day,value:tomorrow ? 1 : 0,to:now)!}
    var term:String { snapshot.term.isEmpty ? BundledAcademic.currentTerm(at:now)?.id ?? "" : snapshot.term }
    var week:Int?{if let known=BundledAcademic.data?.terms.first(where:{$0.id==term}),!AcademicCalendarRules.isTeaching(known,at:target){return nil};return TimetableRules.week(at:target,firstMonday:BundledAcademic.firstMonday(term,snapshot:snapshot))}
    var courses:[Course] {
        guard let week else{return []};let day=(calendar.component(.weekday,from:target)+5)%7+1
        return snapshot.courses.filter{$0.term==term && $0.weekday==day && $0.weeks.contains(week)}.sorted{$0.start<$1.start}
    }
    var dateText:String {
        let f=DateFormatter();f.locale=Locale(identifier:"zh_CN");f.timeZone=calendar.timeZone;f.dateFormat="M月d日 EEE"
        return (tomorrow ? "明日" : "")+f.string(from:target)+(term.isEmpty ? "" : " · "+term)+" · "+(week.map{"第\($0)周"} ?? "非行课期")
    }
    func time(_ course:Course)->String {
        let periods=CoursePeriods.current
        guard let start=periods.first(where:{$0.section==course.start})?.start,let end=periods.first(where:{$0.section==course.start+course.length-1})?.end else{return course.scheduleLabel}
        return start+"–"+end
    }
}

struct FeatureSections: View {
    @Environment(ProductConfiguration.self) private var configuration
    private struct Entry:Identifiable{var route:FeatureRoute;var title:String;var id:String{route.id}}
    private func items(_ section:String)->[Entry]{section=="学校服务" ? FeatureRoute.allCases.filter{$0.section==section}.map{Entry(route:$0,title:$0.title)} : configuration.entries(section).compactMap{item in item.route.map{Entry(route:$0,title:item.title)}}}
    @Environment(\.dynamicTypeSize) private var size
    var body: some View {
        ForEach(["学习", "生活", "校外园地", "学校服务"], id: \.self) { section in
            VStack(alignment: .leading, spacing: 6) {
                Text(section).font(.system(size:18,weight:.semibold)).accessibilityAddTraits(.isHeader)
                LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:4),count:size.isAccessibilitySize ? 2 : 4),spacing:2) {
                    ForEach(items(section)) { entry in
                        let route=entry.route
                        NavigationLink { FeatureDestination(route: route) } label: {
                            VStack(spacing: 6) {
                                Image(systemName:route.icon).font(.system(size:25)).frame(width:46,height:46).background(route.color.opacity(0.11),in:RoundedRectangle(cornerRadius:14))
                                Text(entry.title).font(.system(size:12,weight:.medium)).foregroundStyle(.primary).multilineTextAlignment(.center).lineLimit(2)
                            }.frame(maxWidth:.infinity,minHeight:88)
                        }.buttonStyle(FeaturePressStyle()).foregroundStyle(route.color).accessibilityIdentifier("service-entry-" + route.id)
                    }
                }
            }.padding(.horizontal,14).padding(.vertical,12).background(ChuannongTheme.card,in:RoundedRectangle(cornerRadius:20)).overlay(RoundedRectangle(cornerRadius:20).stroke(.secondary.opacity(0.12),lineWidth:0.5))
        }
    }
}
private struct FeaturePressStyle:ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration:Configuration)->some View{configuration.label.scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1).animation(reduceMotion ? nil : .easeOut(duration:0.09),value:configuration.isPressed)}
}
extension Color { init(hex:UInt32) { self.init(red:Double((hex>>16)&255)/255,green:Double((hex>>8)&255)/255,blue:Double(hex&255)/255) } }
extension FeatureRoute {
    var color:Color {
        let colors:[FeatureRoute:UInt32]=[.schedule:0x2878C7,.grade:0x2D8F85,.exam:0xB86669,.document:0x527D62,.cet:0x6574A8,.mandarin:0x8A6680,.ncre:0x6574C8,.comprehensive_score:0x2D8F85,.electric:0xB0792E,.lost_found:0x826F61,.secondhand:0x357F8A,.errand:0x4A70B0,.weekly_attendance:0x5E788A,.holiday_destination:0x6574C8,.logistics_repair:0xB0792E,.academic:0x477DB3,.student_affairs:0x477DB3,.auth:0x6D6DB0,.ywtb:0xAB8145,.payments:0x439D8C,.calendar:0xB86F7A,.campus_map:0x3B8D68]
        return Color(hex:colors[self] ?? 0x237B62)
    }
}

struct FeatureDestination: View {
    let route: FeatureRoute
    @Environment(ProductConfiguration.self) private var configuration
    @Environment(SchoolSession.self) private var school
    var body: some View {
        Group {
            if !configuration.availability(route).isOpen { ServiceUnavailableView(title:route.title, availability:configuration.availability(route)) }
            else if route.requiresPlatform { PlatformGate { nativeContent } }
            else { nativeContent }
        }.navigationTitle(route.title).navigationBarTitleDisplayMode(.inline)
    }
    @ViewBuilder private var nativeContent: some View {
        switch route {
        case .schedule: TimetableView()
        case .grade: GradesView()
        case .exam: ExamsView()
        case .document: LibraryView()
        case .secondhand: MarketplaceView()
        case .lost_found: CommunityView(kind:route)
        case .electric, .errand, .logistics_repair: GuideView(route: route)
        case .driving_school, .ielts_toefl, .civil_postgrad, .gym: ProvidersView(route: route)
        case .academic:
            ConsentGate { AcademicServiceView().id(school.identity?.studentID) }
        case .campus_map: CampusMapView()
        case .calendar: SchoolCalendarView()
        case .cet, .mandarin, .ncre:
            ConsentGate { SafariPage(url: URL(string: Self.external[route]!)!) }
        default:
            ConsentGate { SchoolServiceView(url: URL(string: Self.official[route]!)!, title: route.title) }
        }
    }
    private static let external: [FeatureRoute: String] = [
        .cet: "https://cjcx.neea.edu.cn/html1/folder/21033/653-1.htm", .mandarin: "https://zwfw.moe.gov.cn/mandarin/", .ncre: "https://ncre.neea.edu.cn"
    ]
    private static let official: [FeatureRoute: String] = [
        .school_home: "https://www.sicau.edu.cn/", .student_affairs: "https://xsgz.sicau.edu.cn/mobile/stuhall/studentindex",
        .auth: "https://auth.sicau.edu.cn/wui/#/?appid=ywtb&service=https%3A%2F%2Fywtb.sicau.edu.cn%2Fcas%2Flogin%2Fuser&cascallback=choose",
        .ywtb: "https://ywtb.sicau.edu.cn/", .payments: "https://op.sicau.edu.cn/CasLogin.aspx", .calendar: "https://www.sicau.edu.cn/ggfw/rlxl.htm",
        .comprehensive_score: "https://xsgz.sicau.edu.cn/mobile/scoreLocus/list", .weekly_attendance: "https://xsgz.sicau.edu.cn/mobile/signTask", .holiday_destination: "https://xsgz.sicau.edu.cn/mobile/leaveSchoolRegister"
    ]
}
