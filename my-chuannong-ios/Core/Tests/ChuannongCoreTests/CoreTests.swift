import Foundation
import Testing
@testable import ChuannongCore

@Test func transportRejectsCrossOriginAndTraversal() throws {
    for path in ["https://evil.invalid", "//evil.invalid", "../admin", "public/%2e%2e/admin", "auth/login#x"] {
        #expect(throws: APIError.self) { try APIClient.url(for: path) }
    }
    #expect(try APIClient.url(for: "public/service-updates").absoluteString == "https://chuannong-api.mychangliapp.cn/api/v1/public/service-updates")
}

@Test func redirectsRemainInsideTheProductAPI() {
    #expect(APIClient.isProductURL(URL(string: "https://chuannong-api.mychangliapp.cn/api/v1/public/service-updates")))
    for raw in ["https://www.sicau.edu.cn/", "https://chuannong-api.mychangliapp.cn:8443/api/v1/", "https://chuannong-api.mychangliapp.cn/admin/", "http://chuannong-api.mychangliapp.cn/api/v1/"] {
        #expect(!APIClient.isProductURL(URL(string: raw)))
    }
}
@Test func iosNeverDisplaysAndroidAPKUpdateAsAnnouncement() throws {
    let json = Data(#"[{"id":"u","type":"UPDATE","title":"APK更新"},{"id":"a","type":"ANNOUNCEMENT","title":"公告","summary":"正文","imageUrl":"/uploads/test.png"}]"#.utf8)
    let feed = try JSONDecoder().decode([Announcement].self, from: json)
    #expect(Announcement.visible(in: feed).map(\.id) == ["a"])
    #expect(feed[1].imageURL?.host == Product.origin.host)
    #expect(Announcement.visible(in: []).isEmpty)
}
@Test func schoolOriginsRemainSeparate() {
    #expect(SchoolURLPolicy.allows(URL(string: "https://jiaowu.sicau.edu.cn/")!))
    for raw in ["https://sicau.edu.cn.evil.invalid/", "http://jiaowu.sicau.edu.cn/", "https://chuannong-api.mychangliapp.cn/"] {
        #expect(!SchoolURLPolicy.allows(URL(string: raw)!))
    }
}
@Test func actualEmptyServiceFeedDecodes() throws {
    let envelope = try JSONDecoder().decode(APIEnvelope<[Announcement]>.self, from: Data(#"{"ok":true,"data":[]}"#.utf8))
    #expect(envelope.ok)
    #expect(envelope.data?.isEmpty == true)
}

@Test func feedFailureKeepsCardsAndSuccessfulWithdrawalClearsThem() throws {
    let items = try JSONDecoder().decode([Announcement].self, from: Data(#"[{"id":"a","type":"ANNOUNCEMENT","title":"合成公告"}]"#.utf8))
    var state = AnnouncementFeedState()
    #expect(!state.hasLoaded)
    state.receive(items, at: Date(timeIntervalSince1970: 1))
    state.fail()
    #expect(state.items.map(\.id) == ["a"])
    #expect(state.errorMessage != nil)
    #expect(state.lastSuccess == Date(timeIntervalSince1970: 1))
    state.receive([])
    #expect(state.hasLoaded && state.items.isEmpty)
    #expect(state.errorMessage == nil)
}

@Test func restoredCacheDoesNotClaimASuccessfulNetworkRequest() {
    var state = AnnouncementFeedState()
    state.restore([])
    #expect(state.hasLoaded)
    #expect(state.lastSuccess == nil)
    state.fail()
    #expect(state.items.isEmpty && state.errorMessage != nil)
}
