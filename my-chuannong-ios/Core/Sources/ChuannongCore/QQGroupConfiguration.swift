import Foundation

public struct QQGroupConfiguration: Sendable {
    public let enabled: Bool
    public let joinURL: URL?

    public init(_ value: JSONValue) {
        enabled = value["enabled"].boolean
        let group = value["groupNumber"].text
        let raw = value["joinUrl"].text
        guard enabled, group.range(of: #"^[1-9][0-9]{4,11}$"#, options: .regularExpression) != nil,
              !raw.isEmpty, raw.count <= 2048,
              !raw.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0) }),
              let url = URLComponents(string: raw), url.user == nil, url.password == nil,
              url.fragment == nil, url.port == nil || url.port == 443 else { joinURL = nil; return }
        if url.scheme == "https", ["qun.qq.com", "qm.qq.com"].contains(url.host), !url.path.isEmpty, url.path != "/" {
            joinURL = url.url; return
        }
        if url.scheme == "mqqapi", url.host == "card", url.port == nil, url.path == "/show_pslcard" {
            let items = url.queryItems ?? []
            let keys = Set(items.map(\.name))
            if keys.count == items.count, keys.isSubset(of: ["src_type", "version", "uin", "card_type", "source", "auth", "key"]),
               items.first(where: { $0.name == "uin" })?.value == group,
               items.first(where: { $0.name == "card_type" })?.value == "group" {
                joinURL = url.url; return
            }
        }
        joinURL = nil
    }
}
