import SwiftUI
import WidgetKit

@MainActor enum SchoolWidgets {
    static var group:String{Bundle.main.object(forInfoDictionaryKey:"AppGroupIdentifier") as? String ?? "group.com.mychuannong.app.development"}
    static var file:URL?{FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:group)?.appending(path:"courses-v1.json")}
    static func update(_ snapshot:AcademicSnapshot)throws {
        guard let file else{throw APIError.server(422,"小组件共享空间尚未就绪，请检查应用签名配置")}
        let enabled=UserDefaults.standard.object(forKey:"widgets.enabled") as? Bool ?? true
        var calendar=Calendar(identifier:.gregorian);calendar.timeZone=TimeZone(identifier:"Asia/Shanghai")!
        let periods=CoursePeriods.current
        var normalized=snapshot
        if normalized.termStarts[snapshot.term]==nil{normalized.termStarts[snapshot.term]=BundledAcademic.firstMonday(snapshot.term,snapshot:snapshot)}
        let horizon=Date.now.addingTimeInterval(14*86400)
        let values=enabled ? ReminderPlan.occurrences(snapshot:normalized,periods:periods,leadMinutes:0,now:calendar.startOfDay(for:.now).addingTimeInterval(-1)).filter{$0.startsAt<horizon}.compactMap{item->WidgetCourse? in
            guard let period=periods.first(where:{$0.section==item.course.start+item.course.length-1}) else{return nil}
            let parts=period.end.split(separator:":").compactMap{Int($0)};guard parts.count==2,let end=calendar.date(bySettingHour:parts[0],minute:parts[1],second:0,of:item.startsAt) else{return nil}
            return WidgetCourse(id:item.course.id+"-"+String(Int(item.startsAt.timeIntervalSince1970)),name:item.course.name,room:item.course.room,start:item.startsAt,end:end)
        } : []
        let payload=WidgetPayload(generatedAt:.now,enabled:enabled,courses:values,bound:!snapshot.owner.isEmpty)
        try JSONEncoder().encode(payload).write(to:file,options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
        var noBackup=URLResourceValues();noBackup.isExcludedFromBackup=true;var saved=file;try saved.setResourceValues(noBackup)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
struct WidgetSettingsView:View {
    @Environment(SchoolSession.self) private var school
    @AppStorage("widgets.enabled") private var enabled=true
    @State private var message:String?
    var body:some View {
        List {
            Section("下一节课") { Label("课程、地点、开始时间与倒计时",systemImage:"clock");Text("小尺寸小组件").foregroundStyle(.secondary);Button("添加"){message="请返回桌面，长按空白处 → 编辑 → 添加小组件 → 我的川农 → 下一节课。"}.frame(maxWidth:.infinity) }
            Section("今日课表") { Label("今日后续课程并突出下一节",systemImage:"calendar");Text("中尺寸与大尺寸小组件").foregroundStyle(.secondary);Button("添加"){message="请返回桌面，长按空白处 → 编辑 → 添加小组件 → 我的川农 → 今日课表。"}.frame(maxWidth:.infinity) }
            Section {Toggle("在小组件显示课程",isOn:$enabled);Button("更新小组件"){refresh()}.frame(maxWidth:.infinity)}
            if let message{StatusMessage(text:message)}
        }.navigationTitle("桌面小组件").onChange(of:enabled){_,_ in refresh()}
    }
    private func refresh(){do{try SchoolWidgets.update(school.snapshot);message="已请求刷新桌面小组件"}catch{message=error.localizedDescription}}
}
