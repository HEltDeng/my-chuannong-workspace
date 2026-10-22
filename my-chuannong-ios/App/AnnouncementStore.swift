import Foundation
import Observation

@MainActor @Observable
final class AnnouncementStore {
    private(set) var state = AnnouncementFeedState()
    private(set) var refreshing = false
    private let client: APIClient
    private let cacheURL: URL?

    init(client: APIClient = APIClient(), useCache: Bool = true) {
        self.client = client
        cacheURL = useCache ? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appending(path: "public-service-announcements.json") : nil
        if let cacheURL, let data = try? Data(contentsOf: cacheURL),
           let items = try? JSONDecoder().decode([Announcement].self, from: data) {
            state.restore(items)
        }
    }

    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        do {
            let feed: [Announcement] = try await client.request("public/service-updates")
            try Task.checkCancellation()
            state.receive(feed)
            if let cacheURL, let data = try? JSONEncoder().encode(state.items) {
                try? data.write(to: cacheURL, options: .atomic)
            }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            state.fail()
        }
    }

    #if DEBUG
    static func preview() -> AnnouncementStore {
        let store = AnnouncementStore(useCache: false)
        let json = #"[{"id":"preview-a","type":"ANNOUNCEMENT","title":"服务动态卡片预览","summary":"此内容仅用于 Xcode 预览，不会发布到后台。","category":"公告"},{"id":"preview-b","type":"ANNOUNCEMENT","title":"左右滑动查看下一条","summary":"迁移自己的安卓卡片交互，保持川农绿色主题。","category":"公告"}]"#
        if let items = try? JSONDecoder().decode([Announcement].self, from: Data(json.utf8)) {
            store.state.receive(items)
        }
        return store
    }
    #endif
}
