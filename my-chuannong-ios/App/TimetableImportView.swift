import SwiftUI

struct TimetableImportView:View {
    let batch:CourseBatch
    @Environment(SchoolSession.self) private var school
    @Environment(\.dismiss) private var dismiss
    @State private var term=""
    @State private var drafts:[ImportDraft]=[]
    @State private var confirmed=false
    @State private var error:String?
    @State private var populated=false
    private var valid:Bool{TimetableRules.validTerm(term) && !drafts.isEmpty && drafts.allSatisfy{$0.reviewed && $0.valid(term:term)} && confirmed}
    var body:some View {
        Form {
            Section("学期") {
                TextField("如 2026-2027-1",text:$term).autocorrectionDisabled().textInputAutocapitalization(.never)
                DisclosureGroup("导入说明") { Text("请对照学校原始课表，逐条检查课程、教室、周次和调课备注。修改内容后需要重新确认。") }
            }
            ForEach($drafts){$draft in
                Section {
                    TextField("课程名称",text:$draft.course.name)
                    TextField("教师",text:$draft.course.teacher)
                    TextField("教室",text:$draft.course.room)
                    Picker("星期",selection:$draft.course.weekday){ForEach(1...7,id:\.self){Text("周"+["一","二","三","四","五","六","日"][$0-1]).tag($0)}}
                    Stepper("开始：第 \(draft.course.start) 节",value:$draft.course.start,in:1...10)
                    Stepper("结束：第 \(draft.end) 节",value:$draft.end,in:1...10)
                    TextField("周次，如 1-16(单周)",text:$draft.weeks)
                    if let source=draft.course.sourceExcerpt,!source.isEmpty{DisclosureGroup("学校原文"){Text(source).font(.footnote).textSelection(.enabled)}}
                    Toggle("已核对本条课程",isOn:$draft.reviewed).disabled(!draft.valid(term:term))
                    Button("移除此安排",role:.destructive){drafts.removeAll{$0.id==draft.id};confirmed=false}.frame(maxWidth:.infinity)
                }.onChange(of:draft.fingerprint){_,_ in draft.reviewed=false;confirmed=false}
            }
            Button("补充上课安排"){var course=Course(name:"",weekday:1,start:1,length:2,weeks:[],term:term);course.sourceExcerpt="手动补充";drafts.append(ImportDraft(course));confirmed=false}.frame(maxWidth:.infinity)
            if !batch.unscheduled.isEmpty {Section("未排定时间的课程"){ForEach(batch.unscheduled,id:\.self){Text($0)}}}
            Section {Toggle("这是本人的课表，已核对学期、全部课程和调课备注。保存将替换此学期之前导入的课程，保留手动添加的课程。",isOn:$confirmed)}
            if let error{StatusMessage(text:error)}
        }.navigationTitle("核对学校课表").navigationBarTitleDisplayMode(.inline)
        .onAppear{guard !populated else{return};populated=true;term=batch.term;drafts=batch.courses.map(ImportDraft.init)}
        .onChange(of:term){_,_ in confirmed=false;for index in drafts.indices{drafts[index].reviewed=false}}
        .interactiveDismissDisabled()
        .toolbar {
            ToolbarItem(placement:.cancellationAction){Button("取消"){school.cancelImport();dismiss()}}
            ToolbarItem(placement:.confirmationAction){Button("保存"){do{let values=try drafts.map{try $0.course(term:term)};try school.importCourses(CourseBatch(term:term,courses:values,unscheduled:batch.unscheduled));dismiss()}catch{self.error=error.localizedDescription}}.disabled(!valid)}
        }
    }
}
private struct ImportDraft:Identifiable {
    var course:Course
    var weeks:String
    var end:Int
    var reviewed=false
    var id:String{course.id}
    init(_ course:Course){self.course=course;weeks=course.weeks.map(String.init).joined(separator:",");end=course.start+course.length-1}
    var fingerprint:String{[course.name,course.teacher,course.room,String(course.weekday),String(course.start),String(end),weeks].joined(separator:"|")}
    func valid(term:String)->Bool{(try? course(term:term)) != nil}
    func course(term:String)throws->Course{var c=course;c.term=term;c.length=end-c.start+1;c.weeks=try TimetableRules.weeks(weeks);try c.validate();return c}
}
