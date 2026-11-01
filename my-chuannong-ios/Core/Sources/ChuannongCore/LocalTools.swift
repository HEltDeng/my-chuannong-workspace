import Foundation

public struct AcademicCalendarData: Codable, Sendable {
    public var schemaVersion: Int?
    public var school: String?
    public var academicYear: String?
    public var validationStatus: String?
    public var version: String
    public var checkedAt: String
    public var sourcePage: String
    public var sourceResources: [Source]?
    public var contentFingerprint: String?
    public var checkIntervalHours: Int?
    public var periodsVersion: String?
    public var revisions: [Revision]?
    public var terms: [Term]
    public var periods: [Period]
    public struct Term: Codable, Identifiable, Sendable {
        public var semesterCode: String
        public var title: String
        public var subtitle: String
        public var calendarStart: String?
        public var calendarEnd: String?
        public var semesterStart: String
        public var semesterEnd: String
        public var teachingWeeks: Int?
        public var weekRule: String?
        public var sourceResource: String?
        public var sourceFingerprint: String?
        public var dataVersion: String?
        public var events: [Event]
        public var id: String { semesterCode }
    }
    public struct Source: Codable, Sendable, Hashable { public var url: String; public var sha256: String }
    public struct Revision: Codable, Sendable { public var version: String; public var fingerprint: String; public var sources: [Source]; public var replacedAt: String }
    public struct Event: Codable, Sendable { public var name: String; public var start: String; public var end: String; public var type: String?; public var source: String? }
    public struct Period: Codable, Sendable, Equatable { public var section: Int; public var start: String; public var end: String; public var lecture: Int? }
    public static func date(_ value: String) -> Date? {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "Asia/Shanghai"); f.dateFormat = "yyyy-MM-dd"; f.isLenient = false
        guard let date = f.date(from: value), f.string(from: date) == value else { return nil }; return date
    }
}

public struct ReminderOccurrence: Sendable {
    public var course: Course
    public var startsAt: Date
    public var firesAt: Date
}
public enum ReminderPlan {
    public static func occurrences(snapshot: AcademicSnapshot, periods: [AcademicCalendarData.Period], leadMinutes: Int, now: Date, disabled: Set<String> = []) -> [ReminderOccurrence] {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        var result: [ReminderOccurrence] = []
        for course in snapshot.courses where course.term == snapshot.term && !disabled.contains(course.id) {
            guard (try? course.validate()) != nil, let first = snapshot.termStarts[course.term], calendar.component(.weekday, from: first) == 2,
                  let period = periods.first(where: { $0.section == course.start }) else { continue }
            let time = period.start.split(separator: ":").compactMap { Int($0) }
            guard time.count == 2, (0...23).contains(time[0]), (0...59).contains(time[1]) else { continue }
            for week in Set(course.weeks).sorted() {
                guard let day = calendar.date(byAdding: .day, value: (week - 1) * 7 + course.weekday - 1, to: calendar.startOfDay(for: first)),
                      let start = calendar.date(bySettingHour: time[0], minute: time[1], second: 0, of: day) else { continue }
                let fire = start.addingTimeInterval(-Double(max(0, leadMinutes)) * 60)
                if fire > now { result.append(ReminderOccurrence(course: course, startsAt: start, firesAt: fire)) }
            }
        }
        return result.sorted { $0.firesAt < $1.firesAt }
    }
}

public struct LedgerEntry: Codable, Identifiable, Sendable {
    public var id = UUID().uuidString
    public var name: String
    public var amount: Decimal
    public var purchasedAt: Date
    public var category: String
    public init(name: String, amount: Decimal, purchasedAt: Date, category: String) { self.name = name; self.amount = amount; self.purchasedAt = purchasedAt; self.category = category }
    public func dailyCost(at date: Date) -> Decimal {
        let days = max(1, Int(date.timeIntervalSince(purchasedAt) / 86400))
        return amount / Decimal(days)
    }
    public static func amount(_ text: String) -> Decimal? {
        guard text.range(of: "^[0-9]{1,9}(?:\\.[0-9]{1,2})?$", options: .regularExpression) != nil,
              let number = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")), number > 0 else { return nil }; return number
    }
}
