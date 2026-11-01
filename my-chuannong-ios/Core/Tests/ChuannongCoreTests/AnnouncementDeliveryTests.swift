import Testing
@testable import ChuannongCore

private func notice(_ id: String, _ date: Double, important: Bool = true) -> CampusRecord {
    CampusRecord(.object(["id": .string(id), "publishedAt": .number(date), "notificationEnabled": .bool(important), "popupEnabled": .bool(false)]))
}

@Test func foregroundNoticesMatchAndroidLatestOnlyAndStableDeduplication() {
    let items = [notice("old", 100), notice("latest", 300), notice("middle", 200)]
    #expect(AnnouncementDeliveryPolicy.latest(in: items, knownIDs: [])?.id == "latest")
    #expect(AnnouncementDeliveryPolicy.latest(in: items, knownIDs: Set(items.map(\.id))) == nil)
    #expect(AnnouncementDeliveryPolicy.latest(in: [notice("edited", 500)], knownIDs: ["edited"]) == nil)
    #expect(AnnouncementDeliveryPolicy.latest(in: [notice("ordinary", 800, important: false), notice("", 900)], knownIDs: []) == nil)
    #expect(AnnouncementDeliveryPolicy.latest(in: [notice("first", 100), notice("second", 100)], knownIDs: [])?.id == "first")
}
