import Foundation
import Testing
@testable import ChuannongCore

private let syntheticURL = "https://jiaowu.sicau.edu.cn/test"
@Test func schoolIdentityRequiresOneUnambiguousStudent() throws {
    let valid = SchoolDocument(url: syntheticURL, text: "个人资料", tables: [[["学号", "TEST20260001", "姓名", "测试同学"]]])
    #expect(try SchoolParser.identity(valid).studentID == "TEST20260001")
    let conflicting = SchoolDocument(url: syntheticURL, text: "个人资料", tables: [[["学号", "TEST0001"]], [["学号", "TEST0002"]]])
    #expect(throws: SchoolFailure.self) { try SchoolParser.identity(conflicting) }
    var expired = valid; expired.authenticationRequired = true
    #expect(throws: SchoolFailure.expired) { try SchoolParser.identity(expired) }
}
@Test func routesAreLearnedOnlyFromSchoolVPNPaths() {
    let route = AcademicRoute(resourceURL: URL(string: "https://webvpn.sicau.edu.cn/https/0123456789abcdef0123456789abcdef/web/web/web/index.asp")!)
    #expect(route?.url(path: SchoolPage.identity.path).path == "/https/0123456789abcdef0123456789abcdef/xuesheng/dangan/banji/bjiben.asp")
    for text in ["https://webvpn.sicau.edu.cn.evil.invalid/https/0123456789abcdef0123456789abcdef/", "http://webvpn.sicau.edu.cn/https/0123456789abcdef0123456789abcdef/", "https://webvpn.sicau.edu.cn/https/random/"] { #expect(AcademicRoute(resourceURL: URL(string: text)!) == nil) }
}
@Test func weeksValidateBoundsParityAndMalformedRanges() throws {
    #expect(try TimetableRules.weeks("1-8（单周）") == [1,3,5,7])
    #expect(try TimetableRules.weeks("2,4,6-8") == [2,4,6,7,8])
    for value in ["0-2", "2-31", "5-2", "1,,3", "1-2-3", "一到四", "1(双周)"] { #expect(throws: SchoolFailure.self) { try TimetableRules.weeks(value) } }
    #expect(!TimetableRules.validTerm("2026-2028-1"))
}
@Test func schoolCoursesSplitNonContiguousSectionsWithoutInventingTimes() throws {
    let doc = SchoolDocument(url: syntheticURL, text: "2026-2027-1", tables: [[
        ["课程名称", "周次", "上课时间", "教室", "教师"],
        ["合成课程", "1-8", "1-1,1-2,1-4(单周)", "合成教室", "合成教师"]
    ]])
    let batch = try SchoolParser.courses(doc)
    #expect(batch.courses.count == 2)
    #expect(Set(batch.courses.map(\.start)) == [1,4])
    #expect(batch.courses.allSatisfy { $0.weeks == [1,3,5,7] })
    var bad = doc; bad.tables[0][1][2] = "周一上午"
    #expect(throws: SchoolFailure.self) { try SchoolParser.courses(bad) }
}
@Test func malformedEmptyCoursePageDoesNotClearCache() throws {
    let doc = SchoolDocument(url: syntheticURL, text: "2026-2027-1", tables: [[["课程名称", "周次", "上课时间", "教室"]]])
    #expect(throws: SchoolFailure.self) { try SchoolParser.courses(doc) }
    var legitimate = doc; legitimate.text += " 暂无课程"
    #expect(try SchoolParser.courses(legitimate).courses.isEmpty)
}
@Test func refreshPreservesManualCoursesAndOtherTerms() {
    let manual = Course(name: "手动课程", weekday: 2, start: 1, length: 2, weeks: [1], term: "2026-2027-1", source: "MANUAL")
    let previous = Course(name: "旧学期", weekday: 2, start: 1, length: 2, weeks: [1], term: "2025-2026-2")
    let stale = Course(name: "应移除", weekday: 3, start: 1, length: 2, weeks: [1], term: "2026-2027-1")
    var snapshot = AcademicSnapshot(owner: "SYNTHETIC"); snapshot.courses = [manual,previous,stale]
    snapshot.receive(CourseBatch(term: "2026-2027-1", courses: [], unscheduled: []), at: Date(timeIntervalSince1970: 12))
    #expect(Set(snapshot.courses.map(\.name)) == ["手动课程", "旧学期"])
    #expect(snapshot.updated["courses"] == Date(timeIntervalSince1970: 12))
}
@Test func gradeAndExamPagesRejectLoginInsteadOfEmptySuccess() {
    let doc = SchoolDocument(url: syntheticURL, text: "登录超时，请重新登录", tables: [])
    #expect(throws: SchoolFailure.expired) { try SchoolParser.grades(doc) }
    #expect(throws: SchoolFailure.expired) { try SchoolParser.exams(doc) }
}
@Test func reminderDatesUseShanghaiCalendarAndSelectedWeeks() throws {
    let monday = try #require(AcademicCalendarData.date("2026-09-07"))
    var snapshot = AcademicSnapshot(owner: "SYNTHETIC"); snapshot.term = "2026-2027-1"; snapshot.termStarts[snapshot.term] = monday
    let course = Course(name: "合成课程", weekday: 1, start: 1, length: 2, weeks: [1,3], term: snapshot.term)
    snapshot.courses = [course]
    let periods = [AcademicCalendarData.Period(section: 1, start: "08:10", end: "08:55")]
    let plan = ReminderPlan.occurrences(snapshot: snapshot, periods: periods, leadMinutes: 15, now: monday)
    #expect(plan.count == 2)
    #expect(plan[0].startsAt.timeIntervalSince(monday) == 8 * 3600 + 10 * 60)
    #expect(plan[1].startsAt.timeIntervalSince(plan[0].startsAt) == 14 * 86400)
    #expect(plan[0].startsAt.timeIntervalSince(plan[0].firesAt) == 900)
    #expect(ReminderPlan.occurrences(snapshot: snapshot, periods: periods, leadMinutes: 15, now: monday, disabled: [course.id]).isEmpty)
    snapshot.termStarts[snapshot.term] = nil
    #expect(ReminderPlan.occurrences(snapshot: snapshot, periods: periods, leadMinutes: 15, now: monday).isEmpty)
}
@Test func ledgerUsesDecimalAmountsAndAvoidsDivisionByZero() {
    #expect(LedgerEntry.amount("12.34") == Decimal(string: "12.34"))
    for invalid in ["NaN", "1e5", "-1", "12.345", "0", "1,000"] { #expect(LedgerEntry.amount(invalid) == nil) }
    let entry = LedgerEntry(name: "测试", amount: 100, purchasedAt: Date(timeIntervalSince1970: 0), category: "其他")
    #expect(entry.dailyCost(at: Date(timeIntervalSince1970: 0)) == 100)
    #expect(entry.dailyCost(at: Date(timeIntervalSince1970: 10 * 86400)) == 10)
}
@Test func productImagesNeverLoadSchoolOrCredentialURLs() {
    #expect(CampusContract.imageURL("/uploads/example.jpg")?.host == Product.origin.host)
    for value in ["https://jiaowu.sicau.edu.cn/a.jpg", "https://user:secret@chuannong-api.mychangliapp.cn/a.jpg", "https://chuannong-api.mychangliapp.cn:8443/a.jpg", "http://chuannong-files.mychangliapp.cn/a.jpg"] { #expect(CampusContract.imageURL(value) == nil) }
}

@Test func schoolProfileExtractsOnlyLabeledGradeAndKeepsOldCacheCompatible() throws {
    let document = SchoolDocument(url: syntheticURL, text: "个人资料", tables: [[["学号","姓名","年级","入学年份"],["TEST20260001","测试学生","大二","2025"]]])
    let identity = try SchoolParser.identity(document)
    #expect(identity.name == "测试学生")
    #expect(identity.grade == "大二")
    #expect(identity.admissionYear == 2025)
    let old = Data(#"{"studentID":"TEST20260001","name":"测试学生","verifiedAt":0}"#.utf8)
    #expect(try JSONDecoder().decode(SchoolIdentity.self, from: old).grade == nil)
    let missing = SchoolDocument(url: syntheticURL, text: "大四 2022级", tables: [[["学号","TEST20260001"]]])
    #expect(try SchoolParser.identity(missing).grade == nil)
    #expect(try SchoolParser.identity(missing).admissionYear == nil)
}
