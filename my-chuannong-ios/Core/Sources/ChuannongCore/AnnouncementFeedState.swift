import Foundation

/// Mirrors Android's successful-empty / cached / failed feed states.
public struct AnnouncementFeedState: Sendable {
    public private(set) var items: [Announcement] = []
    public private(set) var hasLoaded = false
    public private(set) var errorMessage: String?
    public private(set) var lastSuccess: Date?

    public init() {}
    public mutating func restore(_ cached: [Announcement]) {
        items = Announcement.visible(in: cached)
        hasLoaded = true
    }
    public mutating func receive(_ feed: [Announcement], at date: Date = .now) {
        items = Announcement.visible(in: feed)
        hasLoaded = true
        lastSuccess = date
        errorMessage = nil
    }
    public mutating func fail() {
        errorMessage = "暂时无法获取动态，下拉重试"
    }
}
