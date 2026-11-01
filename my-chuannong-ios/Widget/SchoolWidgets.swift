import WidgetKit
import SwiftUI

struct SchoolEntry:TimelineEntry {
    var date:Date
    var payload:WidgetPayload
    var isPreview=false
    var remaining:[WidgetCourse]{payload.courses.filter{$0.end>date}.sorted{$0.start<$1.start}}
    var today:[WidgetCourse]{var c=Calendar(identifier:.gregorian);c.timeZone=TimeZone(identifier:"Asia/Shanghai")!;return remaining.filter{c.isDate($0.start,inSameDayAs:date)}}
    var message:String{!payload.bound ? "打开应用绑定学号" : !payload.enabled ? "课程展示已关闭" : Date.now.timeIntervalSince(payload.generatedAt)>14*86400 ? "打开应用更新课表" : "今日暂无后续课程"}
}
struct SchoolProvider:TimelineProvider {
    func placeholder(in context:Context)->SchoolEntry{SchoolEntry(date:.now,payload:.empty,isPreview:true)}
    func getSnapshot(in context:Context,completion:@escaping(SchoolEntry)->Void){completion(SchoolEntry(date:.now,payload:context.isPreview ? .empty : read(),isPreview:context.isPreview))}
    func getTimeline(in context:Context,completion:@escaping(Timeline<SchoolEntry>)->Void){
        let payload=read(),now=Date.now
        var calendar=Calendar(identifier:.gregorian);calendar.timeZone=TimeZone(identifier:"Asia/Shanghai")!
        let nextDay=calendar.date(byAdding:.day,value:1,to:calendar.startOfDay(for:now))!
        let horizon=now.addingTimeInterval(2*86400)
        let moments=Set([now,nextDay]+payload.courses.flatMap{[$0.start,$0.end]}.filter{$0>now && $0<horizon}).sorted().prefix(80)
        completion(Timeline(entries:moments.map{SchoolEntry(date:$0,payload:payload)},policy:.after(now.addingTimeInterval(3600))))
    }
    private func read()->WidgetPayload {
        let group=Bundle.main.object(forInfoDictionaryKey:"AppGroupIdentifier") as? String ?? "group.com.mychuannong.app.development"
        guard let root=FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:group),let data=try? Data(contentsOf:root.appending(path:"courses-v1.json")),let value=try? JSONDecoder().decode(WidgetPayload.self,from:data) else{return .empty};return value
    }
}
struct NextCourseView:View {
    let entry:SchoolEntry
    private let green=Color(red:35/255,green:123/255,blue:98/255)
    var body:some View {
        VStack(alignment:.leading,spacing:9) {
            Label("下一节课",systemImage:"clock").font(.caption.weight(.semibold)).foregroundStyle(green)
            if let course=entry.remaining.first,entry.payload.enabled {
                Text(course.name).font(.headline).lineLimit(2).privacySensitive()
                Text(course.room.isEmpty ? "教室待定" : course.room).font(.caption).lineLimit(1).privacySensitive()
                Spacer(minLength:0)
                if course.start>entry.date{Text(course.start,style:.timer).font(.title3.monospacedDigit()).foregroundStyle(green)}else{Text("正在上课").font(.subheadline).foregroundStyle(green)}
                Text(course.start,style:.time).font(.caption).foregroundStyle(.secondary)
            }else{Text(entry.isPreview ? "课程与教室将在这里显示" : entry.message).font(.subheadline);Spacer(minLength:0)}
        }.frame(maxWidth:.infinity,alignment:.leading).containerBackground(for:.widget){Color(.systemBackground)}.widgetURL(URL(string:"mychuannong://schedule"))
    }
}
struct TodayCoursesView:View {
    let entry:SchoolEntry
    @Environment(\.widgetFamily) private var family
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack{Label("今日课表",systemImage:"calendar").font(.headline).foregroundStyle(Color(red:35/255,green:123/255,blue:98/255));Spacer();Text(entry.date,format:.dateTime.month().day()).font(.caption).foregroundStyle(.secondary)}
            if entry.today.isEmpty || !entry.payload.enabled{Text(entry.isPreview ? "显示今日后续课程，并突出下一节" : entry.message).font(.subheadline).foregroundStyle(.secondary);Spacer(minLength:0)}
            else{ForEach(Array(entry.today.prefix(family == .systemLarge ? 6 : 2).enumerated()),id:\.element.id){index,course in
                HStack(spacing:10){RoundedRectangle(cornerRadius:2).fill(index==0 ? Color(red:35/255,green:123/255,blue:98/255) : .secondary.opacity(0.3)).frame(width:4);VStack(alignment:.leading,spacing:4){Text(course.name).font(.subheadline.bold()).lineLimit(1);Text(course.room).font(.caption).foregroundStyle(.secondary).lineLimit(1)}.privacySensitive();Spacer();Text(course.start,style:.time).font(.caption.monospacedDigit())}.fixedSize(horizontal:false,vertical:true)
            };Spacer(minLength:0)}
        }.containerBackground(for:.widget){Color(.systemBackground)}.widgetURL(URL(string:"mychuannong://schedule"))
    }
}
struct NextCourseWidget:Widget {
    var body:some WidgetConfiguration{StaticConfiguration(kind:"NextCourse",provider:SchoolProvider()){NextCourseView(entry:$0)}.configurationDisplayName("下一节课").description("课程、地点、开始时间与倒计时").supportedFamilies([.systemSmall])}
}
struct TodayCoursesWidget:Widget {
    var body:some WidgetConfiguration{StaticConfiguration(kind:"TodayCourses",provider:SchoolProvider()){TodayCoursesView(entry:$0)}.configurationDisplayName("今日课表").description("今日后续课程并突出下一节").supportedFamilies([.systemMedium,.systemLarge])}
}
@main struct SchoolWidgetBundle:WidgetBundle{var body:some Widget{NextCourseWidget();TodayCoursesWidget()}}
