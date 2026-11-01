import Foundation

public struct SchoolDocument: Codable, Sendable {
    public var url: String
    public var text: String
    public var authenticationRequired: Bool
    public var redirected: Bool
    public var tables: [[[String]]]
    public var links: [SchoolLink]
    public var academicLogin: Bool?
    public var academicUnifiedLogin: Bool?
    public var challengeRequired: Bool?
    public var frames: [SchoolDocument]?
    public var blocks: [String]?
    public var rowspans: [[Bool]]?
    public init(url: String, text: String, authenticationRequired: Bool = false, redirected: Bool = false, tables: [[[String]]] = [], links: [SchoolLink] = []) {
        self.url = url; self.text = text; self.authenticationRequired = authenticationRequired; self.redirected = redirected; self.tables = tables; self.links = links
    }
}
public struct SchoolLink: Codable, Sendable { public var label: String; public var href: String }
public struct SchoolIdentity: Codable, Sendable, Equatable { public var studentID: String; public var name: String; public var verifiedAt: Date; public var grade: String? = nil; public var admissionYear: Int? = nil }
public enum SchoolFailure: String, Error, LocalizedError {
    case expired = "学校登录已过期，本机数据已保留"
    case structure = "学校数据结构尚未识别，已保留上次数据"
    case identity = "学校返回的身份无法确认，未完成绑定"
    case changed = "学校账号已变化，请重新绑定，原账号数据仍在本机"
    case vpn = "学校连接已过期，请完成学校验证"
    case time = "课程时间或周次无法确认，请核对学校原始课表"
    case cancelled = "操作已取消"
    case credentials = "学校未接受账号或密码，请核对川农 e 登录信息"
    case loginRejected = "学校未确认此次登录，请打开学校页面检查后重试"
    case unifiedAuthentication = "学校现已改用统一身份认证，请通过川农 e 登录教务系统"
    case autoLoginDisabled = "请补充川农 e 登录密码"
    case autoLoginStopped = "教务自动登录已暂停，请本人重新登录并确认账号密码"
    case autoLoginCooldown = "正在等待学校登录重试，请一分钟后再刷新；原数据已保留"
    case verification = "学校要求验证码、短信或密码安全验证，请打开学校页面继续验证"
    public var errorDescription: String? { rawValue }
    public static func reason(_ error: Error) -> SchoolFailure? {
        (error as? SchoolFailure) ?? (error as? SchoolLoginIssue)?.reason
    }
}

/// Preserve the school's actionable notice without exposing entered credentials.
public struct SchoolLoginIssue: Error, LocalizedError, Sendable {
    public let reason: SchoolFailure
    public let notice: String
    public init(message: String, sensitiveValues: [String]) {
        if !TimetableRules.matches("必须.{0,24}(?:扫码|统一身份认证)|(?:取消|关闭).{0,24}(?:账号|密码).{0,8}登录", message).isEmpty { reason = .unifiedAuthentication }
        else if !TimetableRules.matches("短信|验证码|弱密码|修改密码|密码安全", message).isEmpty { reason = .verification }
        else if !TimetableRules.matches("登录超时|会话.{0,12}(?:过期|失效)|登录(?:已)?失效|账号验证失败", message).isEmpty { reason = .expired }
        else if !TimetableRules.matches("(?:密码|口令).{0,24}(?:错误|不正确|有误)|用户名或密码|账号不存在|学号不存在", message).isEmpty { reason = .credentials }
        else { reason = .loginRejected }
        var safe = message
        for value in sensitiveValues where !value.isEmpty { safe = safe.replacingOccurrences(of: value, with: "[已隐藏]") }
        notice = String(safe.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
    }
    public var errorDescription: String? { reason.rawValue + (notice.isEmpty ? "" : "\n学校提示：" + notice) }
}

public enum SchoolPage: String, CaseIterable, Sendable {
    case identity, courses, grades, exams
    public var path: String { switch self {
    case .identity: "/xuesheng/dangan/banji/bjiben.asp"
    case .courses: "/xuesheng/gongxuan/gongxuan/kbbanji.asp?title_id1=4"
    case .grades: "/xuesheng/chengji/chengji/sear_ch_all.asp"
    case .exams: "/xuesheng/kao/kao/xuesheng.asp?title_id1=01"
    } }
}

public struct AcademicRoute: Codable, Sendable, Equatable {
    public let prefix: String
    public static let portal = URL(string: "https://webvpn.sicau.edu.cn/")!
    public static let loginPath = "/web/web/web/index.asp"
    // Official entry observed on the academic homepage after the 2026-10-23 login change.
    public static let unifiedLoginPath = "/jiaoshi/aspsso/caslogin.asp"
    public init?(resourceURL: URL) {
        guard SchoolURLPolicy.allows(resourceURL), resourceURL.host == "webvpn.sicau.edu.cn",
              let path=URLComponents(url:resourceURL,resolvingAgainstBaseURL:false)?.path,
              let range = path.range(of: "^/(?:https|http)(?:-[0-9]+)?/[0-9a-f]{32,256}/", options: .regularExpression) else { return nil }
        prefix = String(path[range].dropLast())
    }
    public func url(path: String) -> URL { URL(string: "https://webvpn.sicau.edu.cn" + prefix + path)! }
    public func contains(_ url: URL) -> Bool { SchoolURLPolicy.allows(url) && url.host == "webvpn.sicau.edu.cn" && URLComponents(url:url,resolvingAgainstBaseURL:false)?.path.hasPrefix(prefix + "/") == true }
}

public struct Course: Codable, Identifiable, Hashable, Sendable {
    public var id: String = UUID().uuidString
    public var name: String
    public var teacher: String
    public var room: String
    public var weekday: Int
    public var start: Int
    public var length: Int
    public var weeks: [Int]
    public var term: String
    public var source: String = "SCHOOL"
    public var sourceExcerpt: String?
    public init(name: String, teacher: String = "", room: String = "", weekday: Int, start: Int, length: Int, weeks: [Int], term: String, source: String = "SCHOOL") {
        self.name = name; self.teacher = teacher; self.room = room; self.weekday = weekday; self.start = start; self.length = length; self.weeks = weeks; self.term = term; self.source = source
    }
    public var scheduleLabel: String { "周\(["一","二","三","四","五","六","日"][max(0,min(6,weekday-1))]) · 第 \(start)–\(start+length-1) 节" }
    public func validate() throws { guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 160, (1...7).contains(weekday), (1...10).contains(start), length > 0, start + length <= 11, !weeks.isEmpty, weeks.allSatisfy({ (1...30).contains($0) }), TimetableRules.validTerm(term) else { throw SchoolFailure.time } }
}
public struct GradeRecord: Codable, Identifiable, Hashable, Sendable {
    public var name: String; public var grade: String; public var credit: String; public var term: String; public var nature: String; public var remarks: String
    public var number: String?
    public var id: String { [name,term,grade,nature,remarks,number ?? ""].joined(separator: "|") }
}
public struct ExamRecord: Codable, Identifiable, Hashable, Sendable {
    public var name: String; public var time: String; public var room: String; public var seat: String; public var campus: String; public var notes: String
    public var id: String { [name,time,room,seat].joined(separator: "|") }
}
public struct CourseBatch: Codable, Sendable { public var term: String; public var courses: [Course]; public var unscheduled: [String] }
public struct AcademicSnapshot: Codable, Sendable {
    public var owner: String
    public var courses: [Course] = []
    public var grades: [GradeRecord] = []
    public var exams: [ExamRecord] = []
    public var unscheduled: [String] = []
    public var term: String = ""
    public var updated: [String: Date] = [:]
    public var termStarts: [String: Date] = [:]
    public var transcript: SchoolTranscript?
    public var admissionYear: Int?
    public init(owner: String) { self.owner = owner }
    public mutating func receive(_ batch: CourseBatch, reviewedImport: Bool = false, at date: Date = .now) {
        func key(_ course: Course) -> String { [course.name, course.teacher, course.room, String(course.weekday), String(course.start), String(course.length), course.term].joined(separator: "\u{001f}") }
        // Explicit import replaces network/imported rows; ordinary refresh protects reviewed and manual rows.
        let protected = Set(courses.filter { $0.term == batch.term && (reviewedImport ? $0.source == "MANUAL" : $0.source != "SCHOOL") }.map(key))
        courses.removeAll { $0.term == batch.term && (reviewedImport ? $0.source != "MANUAL" : $0.source == "SCHOOL") }
        var imported: [String: Course] = [:]
        for var course in batch.courses where !protected.contains(key(course)) {
            course.source = reviewedImport ? "IMPORTED" : "SCHOOL"
            let courseKey = key(course)
            if var existing = imported[courseKey] { existing.weeks = Set(existing.weeks + course.weeks).sorted(); imported[courseKey] = existing }
            else { imported[courseKey] = course }
        }
        courses += imported.values.sorted { ($0.weekday, $0.start, $0.name) < ($1.weekday, $1.start, $1.name) }
        term = batch.term; unscheduled = batch.unscheduled; updated["courses"] = date
    }
}

public enum TimetableRules {
    public static func matches(_ pattern: String, _ text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { m in (0..<m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? "" : ns.substring(with: m.range(at: $0)) } }
    }
    public static func validTerm(_ value: String) -> Bool {
        guard let m = matches("^(20[0-9]{2})-(20[0-9]{2})-([12])$", value).first else { return false }
        return Int(m[2]) == (Int(m[1]) ?? 0) + 1
    }
    public static func weeks(_ raw: String) throws -> [Int] {
        var s = raw.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        for (a,b) in [("，",","),("、",","),("－","-"),("—","-"),("～","-"),("~","-"),("（","("),("）",")")] { s = s.replacingOccurrences(of: a, with: b) }
        guard let m = matches("^([0-9,\\-]+)(?:周)?(?:\\((单|双)(?:周)?\\))?$",s).first else { throw SchoolFailure.time }
        var values = Set<Int>()
        for part in m[1].split(separator: ",", omittingEmptySubsequences: false) {
            let pieces = part.split(separator: "-", omittingEmptySubsequences: false)
            let n = pieces.compactMap { Int($0) }
            guard n.count == pieces.count, (1...2).contains(n.count), let first=n.first, let last=n.last, first<=last, first>=1, last<=30 else { throw SchoolFailure.time }
            values.formUnion(first...last)
        }
        let result = values.sorted().filter { m[2] == "单" ? $0 % 2 == 1 : m[2] == "双" ? $0 % 2 == 0 : true }
        guard !result.isEmpty else { throw SchoolFailure.time }; return result
    }
    public static func week(at date: Date, firstMonday: Date?) -> Int? {
        guard let firstMonday else { return nil }
        var calendar=Calendar(identifier:.gregorian); calendar.timeZone=TimeZone(identifier:"Asia/Shanghai")!
        let days=calendar.dateComponents([.day],from:calendar.startOfDay(for:firstMonday),to:calendar.startOfDay(for:date)).day ?? 0
        return days >= 0 && days < 210 ? days / 7 + 1 : nil
    }
}

/// Port of the observed Android field contracts. Missing/malformed structure never becomes empty success.
public enum SchoolParser {
    static func label(_ s: String) -> String { s.replacingOccurrences(of: "[\\s\u{00a0}：:]", with: "", options: .regularExpression) }
    static func validate(_ d: SchoolDocument) throws {
        let text=d.text.replacingOccurrences(of:"提交后重新登录便可正常访问教务系统",with:"")
        if d.authenticationRequired || !TimetableRules.matches("登录超时|账号验证失败|请重新登录|请先登录|登录已失效",text).isEmpty { throw SchoolFailure.expired }
        if d.redirected { throw SchoolFailure.structure }
    }
    public static func identity(_ d: SchoolDocument) throws -> SchoolIdentity {
        try validate(d)
        guard TimetableRules.matches("短信验证|手机验证码|弱密码|必须.{0,16}修改.{0,8}密码",d.text).isEmpty else { throw SchoolFailure.identity }
        var ids=Set<String>(); var names=Set<String>(); var grades=Set<String>(); var years=Set<Int>()
        for table in d.tables {
            for (i,row) in table.enumerated() {
                for j in row.indices where ["学号","学生学号","姓名","学生姓名","年级","所在年级","入学年份","入学年级"].contains(label(row[j])) {
                    let vertical = table.count == 2 && i == 0 && table[1].count == row.count
                    let value = vertical ? table[1][j] : (j+1 < row.count ? row[j+1] : "")
                    if ["学号","学生学号"].contains(label(row[j])) { if value.range(of:"^[0-9A-Za-z_-]{4,32}$",options:.regularExpression) != nil { ids.insert(value) } }
                    else if ["姓名","学生姓名"].contains(label(row[j])) { if (2...40).contains(value.count) { names.insert(value) } }
                    else if ["大一","大二","大三","大四","大五","大六","研一","研二","研三","研四"].contains(value) { grades.insert(value) }
                    else if let match = TimetableRules.matches("^(20[0-9]{2})(?:级|年)?$",value).first, let year = Int(match[1]) { years.insert(year) }
                }
            }
        }
        guard ids.count == 1 else { throw SchoolFailure.identity }
        return SchoolIdentity(studentID: ids.first!,name:names.count == 1 ? names.first! : "川农同学",verifiedAt:.now,grade:grades.count == 1 ? grades.first : nil,admissionYear:years.count == 1 ? years.first : nil)
    }
    static func table(_ d: SchoolDocument, required: [Set<String>]) throws -> ([String],[[String]]) {
        try validate(d); var candidates:[([String],[[String]])]=[]
        for t in d.tables {
            guard let index=t.firstIndex(where: { row in let h=Set(row.map(label)); return required.allSatisfy { !h.isDisjoint(with:$0) } }) else { continue }
            let headers=t[index].map(label)
            guard Set(headers).count == headers.count else { throw SchoolFailure.structure }
            let rows=t.dropFirst(index+1).filter { $0.contains(where: { !$0.isEmpty }) && $0.map(label) != headers && !["合计","总计"].contains($0.first ?? "") }
            guard rows.allSatisfy({ $0.count == headers.count }) else { throw SchoolFailure.structure }
            candidates.append((headers,Array(rows)))
        }
        guard candidates.count == 1 else { throw SchoolFailure.structure }; return candidates[0]
    }
    static func value(_ row:[String],_ headers:[String],_ names:String...) -> String { guard let i=headers.firstIndex(where:{ names.contains($0) }) else{return ""};return row[i] }
    public static func courses(_ d:SchoolDocument) throws -> CourseBatch {
        let terms=Set(TimetableRules.matches("(20[0-9]{2})\\s*[-—－]\\s*(20[0-9]{2})\\s*(?:-\\s*([12])|学年\\s*(上|下|第一|第二)学期)",d.text).map { "\($0[1])-\($0[2])-\($0[3].isEmpty ? (["上","第一"].contains($0[4]) ? "1" : "2") : $0[3])" })
        guard terms.count==1, let term=terms.first,TimetableRules.validTerm(term) else{throw SchoolFailure.structure}
        let(h,rows)=try table(d,required:[["课程名称","课程名","课程"],["周次","上课周次"],["上课时间"],["教室","上课教室"]])
        if rows.isEmpty && TimetableRules.matches("暂无课程|没有课程|无选课记录|未选课程",d.text).isEmpty{throw SchoolFailure.structure}
        var courses:[Course]=[];var unscheduled:[String]=[]
        for r in rows {
            let name=value(r,h,"课程名称","课程名","课程"), raw=value(r,h,"上课时间")
            guard !name.isEmpty else{throw SchoolFailure.structure}
            if ["自行在线学习","在线学习","网络学习","不定时","时间待定"].contains(raw){unscheduled.append(name+" · "+raw);continue}
            let times=raw.split(separator:"\n").map(String.init), rooms=value(r,h,"教室","上课教室").split(separator:"\n").map(String.init), weeks=value(r,h,"周次","上课周次").split(separator:"\n").map(String.init)
            guard !times.isEmpty,[0,1,times.count].contains(rooms.count),[1,times.count].contains(weeks.count) else{throw SchoolFailure.time}
            for (i,time) in times.enumerated(){
                let normalized=time.replacingOccurrences(of:"\\s+",with:"",options:.regularExpression).replacingOccurrences(of:"（",with:"(").replacingOccurrences(of:"）",with:")")
                let parity=TimetableRules.matches("\\((单|双)(?:周)?\\)$",normalized).first
                let stripped=parity.map{normalized.replacingOccurrences(of:$0[0],with:"")} ?? normalized
                let selected=try TimetableRules.weeks(weeks.count==1 ? weeks[0]:weeks[i]).filter{parity?[1]=="单" ? $0%2==1 : parity?[1]=="双" ? $0%2==0:true}
                var points:[Int:[Int]]=[:]
                for token in stripped.replacingOccurrences(of:"，",with:",").split(separator:","){
                    guard let m=TimetableRules.matches("^([1-7])-(10|[1-9])$",String(token)).first else{throw SchoolFailure.time}
                    points[Int(m[1])!,default:[]].append(Int(m[2])!)
                }
                for (day,sections) in points{
                    var groups:[[Int]]=[]
                    for n in Set(sections).sorted(){if groups.last?.last.map({$0+1==n})==true{groups[groups.count-1].append(n)}else{groups.append([n])}}
                    for group in groups{let course=Course(name:name,teacher:value(r,h,"教师","任课教师"),room:rooms.count<=1 ? rooms.first ?? "":rooms[i],weekday:day,start:group[0],length:group.count,weeks:selected,term:term);try course.validate();courses.append(course)}
                }
            }
        }
        return CourseBatch(term:term,courses:courses,unscheduled:unscheduled)
    }
    public static func grades(_ d:SchoolDocument) throws -> [GradeRecord]{
        let(h,rows)=try table(d,required:[["课程名称","课程名","课程"],["成绩","总评成绩","最终成绩"],["学期","学年学期"]])
        return try rows.map{r in let name=value(r,h,"课程名称","课程名","课程"), grade=value(r,h,"成绩","总评成绩","最终成绩");guard !name.isEmpty,!grade.isEmpty else{throw SchoolFailure.structure};return GradeRecord(name:name,grade:grade,credit:value(r,h,"学分"),term:value(r,h,"学年学期","学期"),nature:value(r,h,"课程性质"),remarks:value(r,h,"成绩说明"))}
    }
    public static func exams(_ d:SchoolDocument) throws -> [ExamRecord]{
        let(h,rows)=try table(d,required:[["课程名称","课程名","课程"],["考试时间"],["考试教室","考试地点","考场"]])
        return try rows.map{r in let name=value(r,h,"课程名称","课程名","课程"), time=value(r,h,"考试时间");guard !name.isEmpty,!time.isEmpty else{throw SchoolFailure.structure};return ExamRecord(name:name,time:time,room:value(r,h,"考试教室","考试地点","考场"),seat:value(r,h,"座位号","座号"),campus:value(r,h,"校区"),notes:value(r,h,"备注"))}
    }
}
