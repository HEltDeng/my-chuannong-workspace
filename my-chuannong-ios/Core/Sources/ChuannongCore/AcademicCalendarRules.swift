import Foundation
import CryptoKit

public enum AcademicCalendarRules {
    public static let source = "https://www.sicau.edu.cn/ggfw/rlxl.htm"
    public static var calendar: Calendar { var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(identifier: "Asia/Shanghai")!; value.firstWeekday = 2; return value }
    public static func sha256(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
    public static func day(_ value: Date) -> String { CampusContract.day(value) }
    public static func days(_ start: Date, _ end: Date) -> Int { calendar.dateComponents([.day], from: start, to: end).day ?? 0 }
    public static func adding(_ days: Int, to value: Date) -> Date { calendar.date(byAdding: .day, value: days, to: value)! }
    public static func validSource(_ value: String) -> Bool { guard let url = URL(string: value) else { return false }; return url.scheme == "https" && url.host == "www.sicau.edu.cn" && url.user == nil && url.password == nil && (url.port == nil || url.port == 443) }
    public static func validate(_ value: AcademicCalendarData) throws {
        guard value.schemaVersion == 1, value.school == "sicau", value.validationStatus == "verified", value.sourcePage == source, !value.version.isEmpty,
              let fingerprint = value.contentFingerprint, fingerprint.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
              let resources = value.sourceResources, !resources.isEmpty, resources.allSatisfy({ validSource($0.url) && $0.sha256.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil }),
              sha256(Data(resources.map(\.sha256).sorted().joined().utf8)) == fingerprint,
              let year = value.academicYear, year.range(of: "^20[0-9]{2}-20[0-9]{2}$", options: .regularExpression) != nil,
              (1...40).contains(value.terms.count), Set(value.terms.map(\.id)).count == value.terms.count, value.terms.contains(where: { $0.id.hasPrefix(year) }) else { throw SchoolFailure.structure }
        for term in value.terms {
            guard TimetableRules.validTerm(term.id), let start = AcademicCalendarData.date(term.semesterStart), let end = AcademicCalendarData.date(term.semesterEnd),
                  calendar.component(.weekday, from: start) == 2, (70...210).contains(days(start, end)),
                  let weeks = term.teachingWeeks, (10...30).contains(weeks), days(start, end) / 7 + 1 == weeks, term.weekRule == "MONDAY_CONTINUOUS",
                  let calendarStart = term.calendarStart.flatMap(AcademicCalendarData.date), let calendarEnd = term.calendarEnd.flatMap(AcademicCalendarData.date), calendarStart <= start, calendarEnd >= end,
                  let year = Int(term.id.prefix(4)), calendar.component(.year, from: start) == (term.id.hasSuffix("-1") ? year : year + 1) else { throw SchoolFailure.structure }
            for event in term.events {
                guard !event.name.isEmpty, event.source == source, let start = AcademicCalendarData.date(event.start), let end = AcademicCalendarData.date(event.end), end >= start else { throw SchoolFailure.structure }
            }
        }
        guard value.periods.count == 10 else { throw SchoolFailure.structure }
        var previousEnd = -1
        for (index, period) in value.periods.enumerated() {
            guard period.section == index + 1, period.lecture == index / 2 + 1, let start = minutes(period.start), let end = minutes(period.end), start < end, start > previousEnd else { throw SchoolFailure.structure }; previousEnd = end
        }
    }
    private static func minutes(_ raw: String) -> Int? { guard let match = TimetableRules.matches("^([01][0-9]|2[0-3]):([0-5][0-9])$", raw).first else { return nil }; return Int(match[1])! * 60 + Int(match[2])! }
    public static func isTeaching(_ term: AcademicCalendarData.Term, at date: Date) -> Bool {
        let day = day(date)
        return day >= term.semesterStart && day <= term.semesterEnd && !term.events.contains { ($0.type == "vacation" && day >= $0.start && day <= $0.end) || ($0.type == "vacation_start" && day >= $0.start) }
    }
    public struct Notes: Equatable, Sendable {
        public var opening: Date; public var registrationStart: Date; public var registrationEnd: Date; public var teaching: Date
        public var practiceStart: Date; public var practiceEnd: Date; public var vacationStart: Date; public var vacationEnd: Date?
    }
    /// Ports the Android adapter's exact labels, chronology checks, and ambiguous-reading rejection.
    public static func notes(_ raw: String, year: Int, semester: Int) throws -> Notes {
        func dates(_ label: String) throws -> [Date] {
            let marker = ["报到注册":"注册", "实践周":"实践", "正式行课":"正式行", "寒假":"寒", "暑假":"六"][label] ?? label
            let rows = raw.components(separatedBy: .newlines).map { $0.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression) }.filter { label == "暑假" ? $0.hasPrefix("六") : $0.contains(marker) }
            guard rows.count == 1 else { throw SchoolFailure.structure }
            let matches = TimetableRules.matches("([0-9]{1,2})月([0-9]{1,2})日?(?:至(?:([0-9]{1,2})月)?([0-9]{1,2})日?)?", rows[0])
            guard matches.count == 1 else { throw SchoolFailure.structure }; let m = matches[0]
            func date(_ month: Int, _ day: Int) throws -> Date { guard let result = AcademicCalendarData.date(String(format: "%04d-%02d-%02d", semester == 1 && month >= 7 ? year : year + 1, month, day)) else { throw SchoolFailure.structure }; return result }
            let start = try date(Int(m[1])!, Int(m[2])!), end = try m[4].isEmpty ? start : date(Int(m[3]) ?? Int(m[1])!, Int(m[4])!)
            guard end >= start else { throw SchoolFailure.structure }; return [start, end]
        }
        let opening = try dates("开学上班"), registration = try dates("报到注册"), teaching = try dates("正式行课"), practice = try dates("实践周"), vacation = try dates(semester == 1 ? "寒假" : "暑假")
        let n = Notes(opening: opening[0], registrationStart: registration[0], registrationEnd: registration[1], teaching: teaching[0], practiceStart: practice[0], practiceEnd: practice[1], vacationStart: vacation[0], vacationEnd: semester == 1 ? vacation[1] : nil)
        guard calendar.component(.weekday, from: n.teaching) == 2, calendar.component(.weekday, from: n.practiceStart) == 2, calendar.component(.weekday, from: n.practiceEnd) == 1,
              n.opening <= n.registrationStart, (1...7).contains(days(n.registrationEnd, n.teaching)), (98...175).contains(days(n.teaching, n.practiceStart)), days(n.practiceStart, n.practiceEnd) == 6,
              n.vacationStart >= n.practiceStart, n.vacationStart <= adding(1, to: n.practiceEnd) else { throw SchoolFailure.structure }
        if let end = n.vacationEnd, !(7...70).contains(days(n.vacationStart, end)) { throw SchoolFailure.structure }
        return n
    }
    public static func periods(_ raw: String) throws -> [AcademicCalendarData.Period] {
        let labels = ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]
        let rows = raw.components(separatedBy: .newlines).map { $0.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression).replacingOccurrences(of: "：", with: ":").replacingOccurrences(of: "第丸节", with: "第九节") }
        return try labels.enumerated().map { index, label in
            let matches = rows.filter { $0.contains("第" + label + "节") }; guard matches.count == 1, let line = matches[0].components(separatedBy: "第" + label + "节").last else { throw SchoolFailure.structure }
            let times = TimetableRules.matches("[0-9]{1,2}:[0-9]{2}", line).map { $0[0].count == 4 ? "0" + $0[0] : $0[0] }; guard times.count == 2 else { throw SchoolFailure.structure }
            return AcademicCalendarData.Period(section: index + 1, start: times[0], end: times[1], lecture: index / 2 + 1)
        }
    }
}
