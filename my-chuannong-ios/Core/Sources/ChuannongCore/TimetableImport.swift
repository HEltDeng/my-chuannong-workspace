import Foundation

/// Mirrors the Android grid/detail cross-check and preserves ambiguous cells for manual review.
public enum TimetableImportParser {
    private static let days=["星期一","星期二","星期三","星期四","星期五","星期六","星期日"]
    public static func parse(_ document:SchoolDocument)throws->CourseBatch {
        var documents:[SchoolDocument]=[]
        func collect(_ d:SchoolDocument,depth:Int){guard depth<=6,documents.count<60 else{return};documents.append(d);for child in d.frames ?? []{collect(child,depth:depth+1)}}
        collect(document,depth:0)
        let candidates=documents.filter{d in d.tables.contains{table in guard let row=table.first else{return false};return days.allSatisfy{row.contains($0)}}}
        guard candidates.count==1,let d=candidates.first else{throw SchoolFailure.structure}
        try SchoolParser.validate(d)
        let terms=Set(TimetableRules.matches("四川农业大学\\s*(20[0-9]{2}-20[0-9]{2}-[12])\\s*学期",d.text).map{$0[1]})
        guard terms.count==1,let term=terms.first,TimetableRules.validTerm(term) else{throw SchoolFailure.structure}
        let grids=d.tables.filter{table in guard let row=table.first else{return false};return days.allSatisfy{row.contains($0)}}
        guard grids.count==1,let grid=grids.first,grid.count==6 else{throw SchoolFailure.structure}
        var courses:[Course]=[]
        for (index,row) in grid.dropFirst().enumerated() {
            guard (8...9).contains(row.count) else{throw SchoolFailure.structure}
            let first=index*2+1,label=row.dropLast(7).joined().replacingOccurrences(of:"\\s+",with:"",options:.regularExpression)
            guard label.contains("\(first)\(first+1)节") || label.contains("\(first)-\(first+1)节") else{throw SchoolFailure.time}
            for (day,raw) in row.suffix(7).enumerated(){courses += cells(raw,day:day+1,start:first,term:term)}
        }
        guard !courses.isEmpty else{throw SchoolFailure.structure}
        let details=d.tables.filter{table in guard let header=table.first else{return false};return ["课程名称","周次","教室","上课时间","教师"].allSatisfy{header.contains($0)}}
        guard details.count<=1 else{throw SchoolFailure.structure}
        if let detail=details.first {
            var copy=d;copy.tables=[detail]
            let batch=try SchoolParser.courses(copy)
            guard batch.unscheduled.isEmpty,!batch.courses.isEmpty else{throw SchoolFailure.structure}
            for course in courses{try course.validate()}
            func slots(_ values:[Course])->Set<String>{Set(values.flatMap{c in c.weeks.flatMap{week in (c.start..<(c.start+c.length)).map{section in "\(c.name.replacingOccurrences(of:"\\s+",with:"",options:.regularExpression))|\(c.weekday)|\(section)|\(week)"}}})}
            guard slots(courses)==slots(batch.courses) else{throw SchoolFailure.structure}
            return batch
        }
        return CourseBatch(term:term,courses:courses,unscheduled:[])
    }
    private static func cells(_ raw:String,day:Int,start:Int,term:String)->[Course] {
        let lines=raw.components(separatedBy:.newlines).map{$0.trimmingCharacters(in:.whitespacesAndNewlines).trimmingCharacters(in:CharacterSet(charactersIn:"|")).replacingOccurrences(of:"：",with:":")}.filter{!$0.isEmpty}
        var groups:[[String]]=[]
        for line in lines {
            let title=line.contains(":") && !["校区","室","周"].contains(where:line.contains)
            if groups.isEmpty || title && groups.last!.contains(where:{$0.contains("周")}){groups.append([])}
            groups[groups.count-1].append(line)
        }
        return groups.filter{$0.contains(where:{$0.rangeOfCharacter(from:.alphanumerics) != nil})}.map{group in
            let title=group[0],parts=title.split(separator:":",maxSplits:1,omittingEmptySubsequences:false)
            let weekLine=(group.first(where:{$0.contains("周")}) ?? "").replacingOccurrences(of:" ",with:"")
            let token=TimetableRules.matches("^([0-9]+(?:[-－~～][0-9]+)?(?:[,，、][0-9]+(?:-[0-9]+)?)*)周(?:[（(]([单双])周[）)])?",weekLine).first
            let ambiguous = !TimetableRules.matches("[（(][^）)]*周[）)]",weekLine).isEmpty && TimetableRules.matches("[（(][单双]周[）)]",weekLine).isEmpty
            let weeks=token.map{$0[1]+($0[2].isEmpty ? "" : "(\($0[2])周)")} ?? ""
            var course=Course(name:String(parts[0]),teacher:parts.count>1 ? String(parts[1]) : "",room:group.first(where:{$0.contains("校区") || $0.contains("室")}) ?? "",weekday:day,start:start,length:2,weeks:ambiguous ? [] : (try? TimetableRules.weeks(weeks)) ?? [],term:term)
            course.sourceExcerpt=group.joined(separator:"\n");return course
        }
    }
}
