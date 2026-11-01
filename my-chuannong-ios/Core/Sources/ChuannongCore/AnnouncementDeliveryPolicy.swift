import Foundation

/// Matches Android: a foreground sync presents only the newest unseen important notice.
public enum AnnouncementDeliveryPolicy {
    public static func latest(in items: [CampusRecord], knownIDs: Set<String>) -> CampusRecord? {
        items.enumerated().filter {
            !$0.element.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !knownIDs.contains($0.element.id) &&
            ($0.element.value["notificationEnabled"].boolean || $0.element.value["popupEnabled"].boolean)
        }.sorted {
            let lhs = $0.element.value["publishedAt"].number, rhs = $1.element.value["publishedAt"].number
            return lhs == rhs ? $0.offset < $1.offset : lhs > rhs
        }.first?.element
    }
}
