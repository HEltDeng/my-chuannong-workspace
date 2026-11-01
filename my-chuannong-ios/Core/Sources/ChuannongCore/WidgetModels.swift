import Foundation

/// Minimal local-only widget payload. It deliberately has no account ID, grades, credentials or cookies.
public struct WidgetCourse:Codable,Identifiable,Sendable {
    public var id:String
    public var name:String
    public var room:String
    public var start:Date
    public var end:Date
    public init(id:String,name:String,room:String,start:Date,end:Date){self.id=id;self.name=name;self.room=room;self.start=start;self.end=end}
}
public struct WidgetPayload:Codable,Sendable {
    public var generatedAt:Date
    public var enabled:Bool
    public var courses:[WidgetCourse]
    public var bound:Bool
    public init(generatedAt:Date,enabled:Bool,courses:[WidgetCourse],bound:Bool){self.generatedAt=generatedAt;self.enabled=enabled;self.courses=courses;self.bound=bound}
    public static var empty:Self{Self(generatedAt:.now,enabled:false,courses:[],bound:false)}
}
