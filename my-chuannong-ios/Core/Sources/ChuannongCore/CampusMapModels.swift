import Foundation

public enum MapCampus:String,CaseIterable,Codable,Identifiable,Sendable {
    case yaan,chengdu,dujiangyan
    public var id:String{rawValue}
    public var title:String{switch self{case .yaan:"雅安校区";case .chengdu:"成都校区";case .dujiangyan:"都江堰校区"}}
}
public enum MapCategory:String,CaseIterable,Identifiable,Sendable {
    case all,teaching,dorm,dining,library,sports,service,gate
    public var id:String{rawValue}
    public var title:String{switch self{case .all:"全部";case .teaching:"教学楼";case .dorm:"宿舍";case .dining:"食堂";case .library:"图书馆";case .sports:"体育场馆";case .service:"生活服务";case .gate:"校门"}}
    public var keywords:String{switch self{case .all:"全部";case .teaching:"教学 教室 上课 自习";case .dorm:"宿舍 公寓 寝室 住宿";case .dining:"食堂 餐厅 吃饭 餐饮";case .library:"图书馆 借书 阅读 自习";case .sports:"体育 运动 球场 健身";case .service:"生活 服务";case .gate:"校门 出入口 大门"}}
    public var color:UInt32{switch self{case .all:0x237B62;case .teaching:0xE4AE62;case .dorm:0x70AD98;case .dining:0xDA8C7E;case .library:0x7AA9CE;case .sports:0x8DA9B0;case .service:0xAC9AC2;case .gate:0x9BADA3}}
}
public struct MapPOI:Codable,Identifiable,Hashable,Sendable {
    public var id:String;public var name:String;public var lat:Double;public var lng:Double;public var address:String;public var typeCode:String
    public init(id:String,name:String,lat:Double,lng:Double,address:String="",typeCode:String=""){self.id=id;self.name=name;self.lat=lat;self.lng=lng;self.address=address;self.typeCode=typeCode}
    public var valid:Bool{!id.isEmpty && !name.isEmpty && lat.isFinite && lng.isFinite && (18...54).contains(lat) && (73...135).contains(lng)}
    public func distance(to other:Self)->Double{let y=(lat-other.lat)*Double.pi/180,x=(lng-other.lng)*Double.pi/180*cos((lat+other.lat)/2*Double.pi/180);return sqrt(x*x+y*y)*6371000}
}
public struct CampusMapData:Codable,Sendable{public var center:MapPOI;public var pois:[MapPOI];public init(center:MapPOI,pois:[MapPOI]){self.center=center;self.pois=pois}}
public struct MapPlace:Identifiable,Sendable {
    public var campus:MapCampus;public var poi:MapPOI;public var category:MapCategory
    public var id:String{campus.id+":"+poi.id}
    public var aliases:[String]{
        let name=CampusCatalogue.normalize(poi.name)
        let pattern=category == .teaching ? "(?:第)?([0-9]+)(?:号)?(?:综合)?教(?!学区)" : "(?:第)?([0-9]+)(?:号)?(?:公寓|宿舍|舍|栋)|(?:公寓|宿舍)(?:第)?([0-9]+)(?:号)?"
        guard category == .teaching || category == .dorm else{return []}
        return TimetableRules.matches(pattern,name).flatMap{m->[String] in let n=m[1].isEmpty && m.count>2 ? m[2] : m[1];return category == .teaching ? [n+"号",n+"教",n+"号教学楼"] : [n+"号",n+"舍",n+"栋",n+"号宿舍"]}
    }
}
public enum CampusCatalogue {
    private static func contains(_ pattern:String,_ text:String)->Bool{!TimetableRules.matches(pattern,text).isEmpty}
    public static func category(_ poi:MapPOI)->MapCategory? {
        let n=poi.name
        guard !poi.typeCode.split(separator:"|").contains(where:{$0.hasPrefix("10")}),!contains("(?i)停车|充电|公交|车站|外卖|便利店|超市|咖啡|奶茶|香肠|快餐|酒店|宾馆|旅馆|民宿|营业厅|自动售|快递柜|取餐柜|ATM|自助银行",n) else{return nil}
        if n.contains("图书馆"){return .library}
        if contains("食堂|餐厅|膳食",n){return .dining}
        if contains("体育馆|体育场|运动场|操场|球场|球馆|游泳|健身房|训练室",n){return .sports}
        if contains("管理中心|办公楼",n){return .service}
        if contains("公寓|宿舍|学生.*舍|博士生楼|教职工住宅",n){return .dorm}
        if contains("医院|医务|卫生所",n){return .service}
        if contains("校门|[东西南北正侧]门|出入口",n){return .gate}
        if contains("教学楼|教学实验|[0-9一二三四五六七八九十]教(?!学区)|学院|实验|科研|科学楼|理学楼|机电楼|院士楼|林园楼|报告厅|文法楼|作物楼|学术|教学部|体育系|试验站",n){return .teaching}
        if contains("中心|后勤|快递站|驿站|展览馆|麦立方|学生会|团委|广场|荷花池|杨柳湖|楼([A-Za-z区座栋0-9()（）-]*)$",n){return .service}
        return nil
    }
    public static func belongs(_ poi:MapPOI,campus:MapCampus,center:MapPOI,child:Bool=false)->Bool {
        let text=poi.name+poi.address
        guard poi.valid,poi.distance(to:center)<(campus == .yaan ? 1800 : 1200),!MapCampus.allCases.contains(where:{$0 != campus && text.contains($0.title)}) else{return false}
        if !poi.name.contains("四川农业大学") && contains("近四川农业大学|四川农业大学.*(附近|对面|旁边)",poi.address){return false}
        return child || !center.address.isEmpty && poi.address.contains(center.address) || ["四川农业大学","四川农大","川农学生"].contains(where:text.contains)
    }
    public static func places(_ data:CampusMapData,campus:MapCampus)->[MapPlace] {
        var seen=Set<String>()
        return data.pois.compactMap{poi in guard poi.id != data.center.id,poi.valid,seen.insert(poi.id).inserted,let category=category(poi) else{return nil};return MapPlace(campus:campus,poi:poi,category:category)}.sorted{a,b in let x=MapCategory.allCases.firstIndex(of:a.category)!,y=MapCategory.allCases.firstIndex(of:b.category)!;return x==y ? a.poi.name<b.poi.name : x<y}
    }
    public static func normalize(_ raw:String)->String {
        var text=raw.precomposedStringWithCompatibilityMapping.lowercased().trimmingCharacters(in:.whitespacesAndNewlines).replacingOccurrences(of:"\\s+",with:" ",options:.regularExpression)
        let digits=Array("零一二三四五六七八九")
        let pattern="[一二三四五六七八九]?十[一二三四五六七八九]?|[一二三四五六七八九](?=[号栋舍教公综宿])"
        if let regex=try? NSRegularExpression(pattern:pattern) {
            for match in regex.matches(in:text,range:NSRange(text.startIndex...,in:text)).reversed() {
                guard let range=Range(match.range,in:text) else{continue};let token=String(text[range]),parts=token.components(separatedBy:"十")
                let value=parts.count==2 ? (parts[0].first.flatMap{digits.firstIndex(of:$0)} ?? 1)*10+(parts[1].first.flatMap{digits.firstIndex(of:$0)} ?? 0) : digits.firstIndex(of:token.first!) ?? 0
                text.replaceSubrange(range,with:String(value))
            }
        }
        return text
    }
    public static func visible(_ values:[MapPlace],campus:MapCampus,category:MapCategory,query:String)->[MapPlace] {
        let needle=normalize(query);guard !needle.isEmpty else{return values.filter{$0.campus==campus && (category == .all || $0.category==category)}}
        return values.filter{place in let haystack=normalize(([place.poi.name,place.campus.title,place.category.keywords]+place.aliases).joined(separator:" "));return needle.split(separator:" ").allSatisfy{token in contains((token.first?.isNumber == true ? "(?<![0-9])" : "")+NSRegularExpression.escapedPattern(for:String(token))+(token.last?.isNumber == true ? "(?![0-9])" : ""),haystack)}}.sorted{a,b in a.campus==campus && b.campus != campus}
    }
}
