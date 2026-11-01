import Foundation

public struct ServiceAvailability: Equatable, Sendable {
    public enum State: String, Sendable { case closed = "CLOSED", open = "OPEN", maintenance = "MAINTENANCE", comingSoon = "COMING_SOON" }
    public let state: State
    public let message: String
    public let expectedAt: Date?
    public var isOpen: Bool { state == .open }
    public var title: String { state == .maintenance ? "维护中" : state == .comingSoon ? "即将上线" : state == .closed ? "关闭" : "" }
    public var symbol: String { state == .maintenance ? "wrench.and.screwdriver" : "clock" }
    public var timeLabel: String { state == .maintenance ? "预计恢复" : "预计上线" }
    public init(flag: JSONValue = .null) {
        let status = flag["payload"]["status"].text.uppercased()
        if flag != .null && flag["enabled"] == .bool(false) { state = .closed }
        else { state = State(rawValue: status) ?? .open }
        message = state == .open ? "" : String(flag["payload"]["maintenanceNote"].text.prefix(300))
        let stamp = flag["payload"]["expectedRestoreAt"].number
        expectedAt = state != .open && stamp.isFinite && stamp > 0 && stamp <= 253_402_300_799_999 ? Date(timeIntervalSince1970: stamp / 1000) : nil
    }
    public static func key(for action: String) -> String? {
        switch action {
        case "document": "resource_library"
        case "lost_found": "lost_found"
        case "secondhand", "errand", "electric", "logistics_repair", "driving_school", "ielts_toefl", "civil_postgrad", "gym": action
        default: nil
        }
    }
}
