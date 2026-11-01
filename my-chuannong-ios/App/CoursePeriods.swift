import SwiftUI

@MainActor enum CoursePeriods {
    static var current:[AcademicCalendarData.Period] {
        guard let raw=UserDefaults.standard.data(forKey:"courses.periods"),let values=try? JSONDecoder().decode([AcademicCalendarData.Period].self,from:raw),valid(values) else{return BundledAcademic.data?.periods ?? []};return values
    }
    static func valid(_ values:[AcademicCalendarData.Period])->Bool {
        guard values.count==10 else{return false}
        return values.enumerated().allSatisfy{index,p in p.section==index+1 && minutes(p.start) != nil && minutes(p.end) != nil && minutes(p.start)!<minutes(p.end)! && (index==0 || (minutes(values[index-1].end) ?? 1440)<=minutes(p.start)!)}
    }
    static func minutes(_ value:String)->Int? {
        guard let m=TimetableRules.matches("^([01][0-9]|2[0-3]):([0-5][0-9])$",value).first else{return nil};return Int(m[1])!*60+Int(m[2])!
    }
    static func save(_ values:[AcademicCalendarData.Period])throws{guard valid(values) else{throw APIError.server(422,"请填写十节课的有效时间，开始时间须早于结束时间，课程时间不得重叠")};UserDefaults.standard.set(try JSONEncoder().encode(values),forKey:"courses.periods")}
}
struct CourseTimeSettingsView:View {
    @Environment(SchoolSession.self) private var school
    @Environment(\.dismiss) private var dismiss
    @State private var periods=CoursePeriods.current
    @State private var message:String?
    var body:some View {
        Form {
            ForEach(periods.indices,id:\.self){i in Section("第 \(i+1) 节"){TextField("开始，如 08:10",text:$periods[i].start).keyboardType(.numbersAndPunctuation);TextField("结束，如 08:55",text:$periods[i].end).keyboardType(.numbersAndPunctuation)}}
            Button("恢复学校默认作息"){periods=BundledAcademic.data?.periods ?? []}.frame(maxWidth:.infinity)
            if let message{StatusMessage(text:message)}
        }.navigationTitle("课程作息时间").toolbar{ToolbarItem(placement:.confirmationAction){Button("保存"){do{try CoursePeriods.save(periods);try? SchoolWidgets.update(school.snapshot);Task{_ = try? await CourseNotifications.rebuild(school.snapshot)};dismiss()}catch{message=error.localizedDescription}}}}
    }
}
