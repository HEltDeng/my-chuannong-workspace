import XCTest
@testable import ChuannongCore

final class ServiceAvailabilityTests: XCTestCase {
    private func flag(_ status: String, enabled: Bool = true) -> JSONValue {
        .object(["enabled": .bool(enabled), "payload": .object(["status": .string(status), "maintenanceNote": .string("合成维护提示"), "expectedRestoreAt": .number(1_900_000_000_000)])])
    }
    func testStatesAndLegacyDisabledFlags() {
        XCTAssertTrue(ServiceAvailability().isOpen)
        XCTAssertTrue(ServiceAvailability(flag: flag("OPEN")).isOpen)
        XCTAssertEqual(ServiceAvailability(flag: flag("OPEN")).message, "")
        XCTAssertNil(ServiceAvailability(flag: flag("OPEN")).expectedAt)
        let maintenance = ServiceAvailability(flag: flag("MAINTENANCE"))
        XCTAssertFalse(maintenance.isOpen)
        XCTAssertEqual(maintenance.title, "维护中")
        XCTAssertEqual(maintenance.message, "合成维护提示")
        XCTAssertEqual(maintenance.expectedAt?.timeIntervalSince1970, 1_900_000_000)
        for status in ["COMING_SOON", "CLOSED"] {
            XCTAssertFalse(ServiceAvailability(flag: flag(status)).isOpen)
            XCTAssertEqual(ServiceAvailability(flag: flag(status)).title, status == "CLOSED" ? "关闭" : "即将上线")
        }
        XCTAssertFalse(ServiceAvailability(flag: flag("OPEN", enabled: false)).isOpen)
    }
    func testAllOwnedRoutesMapIndependentlyWithoutGatingSchoolServices() {
        let actions = ["document", "lost_found", "secondhand", "errand", "electric", "logistics_repair", "driving_school", "ielts_toefl", "civil_postgrad", "gym"]
        XCTAssertEqual(Set(actions.compactMap(ServiceAvailability.key(for:))).count, 10)
        XCTAssertEqual(ServiceAvailability.key(for: "document"), "resource_library")
        for action in ["schedule", "auth", "academic", "unknown"] { XCTAssertNil(ServiceAvailability.key(for: action)) }
    }
}
