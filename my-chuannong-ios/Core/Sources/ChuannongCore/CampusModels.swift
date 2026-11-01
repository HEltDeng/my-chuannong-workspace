import Foundation

/// Used only for the product API's finite JSON content contracts, never school credentials.
public enum JSONValue: Codable, Sendable, Hashable {
    case object([String: JSONValue]), array([JSONValue]), string(String), number(Double), bool(Bool), null
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([String: JSONValue].self) { self = .object(v) }
        else { self = .array(try c.decode([JSONValue].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    public subscript(_ key: String) -> JSONValue { if case .object(let v) = self { return v[key] ?? .null }; return .null }
    public var text: String { switch self { case .string(let v): v; case .number(let v): v.isFinite && v.rounded() == v && v >= Double(Int64.min) && v < Double(Int64.max) ? String(Int64(v)) : String(v); default: "" } }
    public var boolean: Bool { if case .bool(let v) = self { return v }; return false }
    public var number: Double { if case .number(let v) = self { return v }; return 0 }
    public var list: [JSONValue] { if case .array(let v) = self { return v }; return [] }
    public var records: [CampusRecord] { (self["items"].list.isEmpty ? list : self["items"].list).map(CampusRecord.init) }
}

public struct CampusRecord: Identifiable, Hashable, Sendable {
    public var value: JSONValue
    public var id: String { value["id"].text }
    public init(_ value: JSONValue) { self.value = value }
    public subscript(_ key: String) -> String { value[key].text }
    public var title: String { [self["title"], self["name"], self["provider_name"]].first(where: { !$0.isEmpty }) ?? "" }
    public var imagePaths: [String] { let images = value["images"].list.map(\.text); return images.isEmpty ? [self["image"], self["coverUrl"]].filter { !$0.isEmpty } : images }
    public var statusLabel: String { CampusContract.statusLabel(self["status"]) }
}

public enum CampusContract {
    public static let campuses = ["成都校区", "雅安校区", "都江堰校区"]
    public static let marketplaceCategories = ["自行车", "书籍", "电动车", "高速材料", "四六级耳机", "宿舍用品", "数码产品", "其他"]
    public static func validPhone(_ value: String) -> Bool { value.range(of: "^1[3-9][0-9]{9}$", options: .regularExpression) != nil }
    public static func validPassword(_ value: String) -> Bool { (8...200).contains(value.count) }
    public static func statusLabel(_ value: String) -> String {
        ["PENDING":"待审核 / 待处理", "PUBLISHED":"已发布", "VIOLATION":"未通过审核", "CONFIRMED":"已确认", "COMPLETED":"已完成", "CANCELLED":"已取消", "REJECTED":"已拒绝", "OPEN":"待处理", "RESOLVED":"已解决", "PROCESSING":"处理中"][value] ?? value
    }
    public static func imageURL(_ path: String) -> URL? {
        guard !path.isEmpty, let url = URL(string: path, relativeTo: Product.origin)?.absoluteURL,
              url.scheme == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443,
              [Product.origin.host, Product.fileHost].contains(url.host) else { return nil }
        return url
    }
    public static func externalURL(_ value: String) -> URL? {
        guard let url = URL(string: value), url.scheme == "https", url.host != nil, url.user == nil, url.password == nil else { return nil }; return url
    }
    public static func day(_ date: Date) -> String {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "Asia/Shanghai"); f.dateFormat = "yyyy-MM-dd"; return f.string(from: date)
    }
}

public enum FeatureRoute: String, CaseIterable, Identifiable, Sendable {
    case schedule, grade, exam, document, cet, mandarin, ncre, comprehensive_score
    case electric, lost_found, errand, secondhand, weekly_attendance, holiday_destination, logistics_repair
    case driving_school, ielts_toefl, civil_postgrad, gym
    case school_home, academic, student_affairs, auth, ywtb, payments, calendar, campus_map
    public var id: String { rawValue }
    public var title: String { Self.catalog[self]!.0 }
    public var icon: String { Self.catalog[self]!.1 }
    public var section: String { Self.catalog[self]!.2 }
    public var requiresPlatform: Bool { [.document,.secondhand,.lost_found,.errand,.driving_school,.ielts_toefl,.civil_postgrad,.gym].contains(self) }
    public static let catalog: [Self: (String, String, String)] = [
        .schedule:("课表","calendar","学习"), .grade:("成绩查询","chart.bar","学习"), .exam:("考试安排","list.bullet.clipboard","学习"), .cet:("四六级","abc","学习"), .document:("资料库","folder","学习"), .mandarin:("普通话测试","waveform","学习"), .ncre:("计算机考试","desktopcomputer","学习"), .comprehensive_score:("综测成绩","chart.bar.xaxis","学习"),
        .electric:("电费查询","bolt","生活"), .errand:("跑腿代取","shippingbox","生活"), .secondhand:("二手好物","bag","生活"), .lost_found:("失物招领","doc.text.magnifyingglass","生活"), .weekly_attendance:("周点名","person.badge.clock","生活"), .holiday_destination:("节假日去向","suitcase.rolling","生活"), .logistics_repair:("后勤报修","wrench.and.screwdriver","生活"),
        .driving_school:("驾校","car","校外园地"), .ielts_toefl:("雅思托福","character.book.closed","校外园地"), .civil_postgrad:("考公考研","books.vertical","校外园地"), .gym:("健身房","dumbbell","校外园地"),
        .school_home:("学校官网","globe.asia.australia","学校服务"), .academic:("教务系统","graduationcap","学校服务"), .student_affairs:("学工系统","person.text.rectangle","学校服务"), .auth:("统一认证","lock.shield","学校服务"), .ywtb:("一网通办","square.grid.2x2","学校服务"), .payments:("校园缴费","creditcard","学校服务"), .calendar:("学校校历","calendar.badge.clock","学校服务"), .campus_map:("校园地图","map","学校服务")
    ]
}
