import Foundation

public struct SchoolField: Codable, Hashable, Sendable, Identifiable {
    public var name: String
    public var value: String
    public var id: String { name }
    public init(name: String, value: String) { self.name = name; self.value = value }
}
public struct SchoolTranscript: Codable, Sendable {
    public var owner: String
    public var summary: [SchoolField]
    public var ranking: [SchoolField]
    public var courses: [GradeRecord]
    public var updatedAt: Date
    public func field(_ names: [String]) -> String { names.lazy.compactMap { name in (summary + ranking).first(where: { $0.name == name })?.value }.first ?? "--" }
}

/// Uses the school's explicit fields. Never derives GPA, rank, or another student's information.
public enum TranscriptParser {
    private static let summaryLabels: Set<String> = ["有效学分", "算术平均成绩", "加权平均成绩", "平均绩点", "平均成绩绩点"]
    private static let rankNames: Set<String> = ["专业排名", "排名", "本人排名", "名次", "有效必修加权排名"]
    private static let rankLabels: Set<String> = ["本人排名", "有效必修加权排名","专业排名", "排名", "名次", "排名总人数", "总人数", "参评人数", "排名比例", "排名百分比", "统计范围", "排名范围", "学年学期", "学年", "学期", "有效必修加权成绩", "校区", "系列", "专业", "年级"]
    private static let ids: Set<String> = ["学号", "学生学号"]
    private static func normalize(_ s: String) -> String { SchoolParser.label(s) }
    private static func validate(_ d: SchoolDocument, owner: String, allowCohort: Bool = false) throws {
        try SchoolParser.validate(d)
        guard d.challengeRequired != true else { throw SchoolFailure.verification }
        if !allowCohort {
            let shown = TimetableRules.matches("(?:学生)?学号\\s*[:：]\\s*([0-9A-Za-z_-]{4,32})", d.text).map { $0[1] }
            guard shown.allSatisfy({ $0 == owner }) else { throw SchoolFailure.changed }
            for table in d.tables {
                for (i,row) in table.enumerated() {
                    for column in row.indices where ids.contains(normalize(row[column])) {
                        let headers = row.map(normalize)
                        let isHeader = headers.contains("姓名") || headers.contains("学生姓名")
                        let value = isHeader && i + 1 < table.count && table[i+1].count == row.count ? table[i+1][column] : (column + 1 < row.count ? row[column+1] : "")
                        if value.range(of: "^[0-9A-Za-z_-]{4,32}$", options: .regularExpression) != nil, value != owner { throw SchoolFailure.changed }
                    }
                }
            }
        }
    }
    private static func fields(_ d: SchoolDocument, labels: Set<String>) throws -> [SchoolField] {
        var values: [String: String] = [:], order: [String] = []
        func add(_ name: String, _ raw: String) throws {
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard labels.contains(name), !value.isEmpty, !labels.contains(normalize(value)) else { return }
            if let old = values[name], old != value { throw SchoolFailure.structure }
            if values[name] == nil { order.append(name) }; values[name] = value
        }
        for table in d.tables {
            if let index = table.firstIndex(where: { !$0.isEmpty && $0.allSatisfy { labels.contains(normalize($0)) } }) {
                let header = table[index].map(normalize), data = table.dropFirst(index + 1).filter { !$0.joined().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                guard data.count == 1, data[0].count == header.count else { throw SchoolFailure.structure }
                for column in header.indices { try add(header[column], data[0][column]) }
            }
            for row in table { for column in row.indices where labels.contains(normalize(row[column])) && column + 1 < row.count { try add(normalize(row[column]), row[column+1]) } }
        }
        let alternatives = labels.sorted { $0.count > $1.count }.map(NSRegularExpression.escapedPattern).joined(separator: "|")
        let pattern = "(" + alternatives + ")\\s*[:：]\\s*(.*?)(?=\\s*(?:" + alternatives + ")\\s*[:：]|$)"
        for block in d.blocks ?? d.text.components(separatedBy: .newlines) {
            for match in TimetableRules.matches(pattern, block) { try add(match[1], match[2].trimmingCharacters(in: CharacterSet(charactersIn: "；; \t\n"))) }
        }
        return order.map { SchoolField(name: $0, value: values[$0]!) }
    }
    public static func transcript(_ d: SchoolDocument, owner: String) throws -> SchoolTranscript {
        try validate(d, owner: owner)
        guard d.text.contains("个人成绩单") || d.text.contains("四川农业大学学生成绩单") else { throw SchoolFailure.structure }
        var courses: [GradeRecord] = []; var recognized = false
        let names: Set<String> = ["课程名称", "课程名", "课程"], grades: Set<String> = ["成绩", "总评成绩", "最终成绩", "课程成绩"]
        let numbers: Set<String> = ["课程序号", "课程编号", "课程号", "序号"]
        for (tableIndex, table) in d.tables.enumerated() {
            guard let index = table.firstIndex(where: { row in let h = Set(row.map(normalize)); return !h.isDisjoint(with: names) && !h.isDisjoint(with: grades) && !h.isDisjoint(with: ["学分", "课程学分"]) }) else { continue }
            recognized = true
            let header = table[index].map(normalize), starts = header.indices.filter { names.contains(header[$0]) }
            let boundaries = [0] + starts.dropFirst().map { numbers.contains(header[$0-1]) ? $0-1 : $0 } + [header.count]
            for (rowIndex, raw) in table.enumerated() where rowIndex > index {
                let joined = raw.joined(separator: " ")
                if joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !TimetableRules.matches("暂无成绩|没有成绩|无成绩记录", joined).isEmpty || raw.map(normalize) == header || summaryLabels.contains(where: { joined.contains($0) }) { continue }
                guard raw.count == header.count, !(d.rowspans?.indices.contains(tableIndex) == true && d.rowspans![tableIndex].indices.contains(rowIndex) && d.rowspans![tableIndex][rowIndex]) else { throw SchoolFailure.structure }
                for group in 0..<(boundaries.count-1) {
                    let range = boundaries[group]..<boundaries[group+1]
                    func cell(_ labels: Set<String>) -> String { guard let column = range.first(where: { labels.contains(header[$0]) }) else { return "" }; return raw[column] }
                    if ["否", "无效"].contains(cell(["有效", "是否有效"])) || raw[range].allSatisfy({ $0.isEmpty }) { continue }
                    let name = cell(names), grade = cell(grades); guard !name.isEmpty, !grade.isEmpty else { throw SchoolFailure.structure }
                    courses.append(GradeRecord(name: name, grade: grade, credit: cell(["学分", "课程学分"]), term: cell(["学期", "学年学期"]), nature: cell(["课程性质", "性质"]), remarks: cell(["备注信息", "备注", "成绩说明"]), number: cell(numbers)))
                }
            }
        }
        guard recognized, !courses.isEmpty || !TimetableRules.matches("暂无成绩|没有成绩|无成绩记录", d.text).isEmpty else { throw SchoolFailure.structure }
        var seen = Set<GradeRecord>()
        let summary = try fields(d, labels: summaryLabels), ordered = ["有效学分", "算术平均成绩", "加权平均成绩", "平均绩点", "平均成绩绩点"].compactMap { name in summary.first { $0.name == name } }
        return SchoolTranscript(owner: owner, summary: ordered, ranking: [], courses: courses.filter { seen.insert($0).inserted }, updatedAt: .now)
    }
    public static func ranking(_ d: SchoolDocument, owner: String) throws -> [SchoolField] {
        try validate(d, owner: owner, allowCohort: true)
        guard d.text.contains("有效必修加权排名") || d.text.contains("有效必修课加权平均成绩及专业排名") else { throw SchoolFailure.structure }
        var matches: [[SchoolField]] = []; var cohort = false
        for table in d.tables {
            guard let i=table.firstIndex(where: { r in let h=Set(r.map(normalize));return !h.isDisjoint(with: ids) && !h.isDisjoint(with: rankNames) }) else{continue}
            cohort = true
            let h=table[i].map(normalize);guard let idColumn=h.firstIndex(where:{ids.contains($0)}) else{continue}
            for row in table.dropFirst(i+1) where row.indices.contains(idColumn) && row[idColumn].trimmingCharacters(in: .whitespacesAndNewlines) == owner {
                guard row.count == h.count else { throw SchoolFailure.structure }
                matches.append(h.indices.filter{rankLabels.contains(h[$0]) && !row[$0].isEmpty}.map{SchoolField(name:h[$0],value:row[$0])})
            }
        }
        if cohort { guard matches.count == 1, matches[0].contains(where: { rankNames.contains($0.name) }) else{throw SchoolFailure.structure};return matches[0] }
        try validate(d, owner: owner)
        let result=try fields(d,labels:rankLabels)
        guard result.contains(where:{rankNames.contains($0.name)}) else{throw SchoolFailure.structure};return result
    }
}

public enum StudentPresentation {
    public static func greeting(_ name: String?) -> String {
        guard let value=name?.trimmingCharacters(in:.whitespacesAndNewlines), !value.isEmpty else{return "川农同学"}
        let compound:Set<String>=["欧阳","司马","上官","诸葛","夏侯","司徒","司空","皇甫","尉迟","公孙","慕容","令狐","长孙","宇文","东方","南宫","独孤","端木","轩辕","钟离","闾丘","闻人","澹台","公羊","申屠","太史","仲孙","万俟"]
        return String(value.prefix(compound.contains(String(value.prefix(2))) ? 2 : 1))+"同学"
    }
    public static func maskedStudent(_ raw: String?) -> String {
        guard let value=raw, !value.isEmpty else{return "未绑定"}
        return value.count <= 6 ? String(repeating:"*",count:value.count) : value.prefix(4)+String(repeating:"*",count:value.count-6)+value.suffix(2)
    }
    public static func maskedPhone(_ raw: String?) -> String {
        guard let raw,raw.count==11 else{return "未绑定"};return raw.prefix(3)+"****"+raw.suffix(4)
    }
}
