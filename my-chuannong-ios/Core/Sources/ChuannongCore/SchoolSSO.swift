import Foundation
import CryptoKit
import CommonCrypto

/// Port of the product's SicauAuthProtocol. Decrypts the school's documented response envelope locally.
public enum SchoolSSOEnvelope {
    public static func validOwner(_ value: String) -> Bool { value.range(of: "^[0-9A-Za-z_-]{4,32}$", options: .regularExpression) != nil }
    public static func primaryOwner(_ response: JSONValue) -> String? {
        guard response["code"].number==200,!response["data"]["st"].text.isEmpty else { return nil }
        let primary=response["data"]["user"],id=primary["id"].text,number=primary["number"].text
        guard !id.isEmpty else { return nil }
        if validOwner(number) { return number }
        let matches=response["data"]["users"].list.filter { $0["id"].text==id && validOwner($0["number"].text) }
        return matches.count==1 ? matches[0]["number"].text : nil
    }
    public static func decode(_ data: Data) throws -> JSONValue {
        guard data.count <= 2_000_000, case .object(var envelope) = try JSONDecoder().decode(JSONValue.self, from: data) else { throw SchoolFailure.structure }
        if case .string(let encoded) = envelope["data"] {
            guard let bytes = Data(base64Encoded: encoded), bytes.count > 16, bytes.count <= 2_000_000,
                  case .string(let requestID) = envelope["requestId"], !requestID.isEmpty else { throw SchoolFailure.structure }
            let key = Array(Insecure.MD5.hash(data: Data((requestID + ":sicau-cas").utf8))), iv = Array(bytes.prefix(16)), payload = Array(bytes.dropFirst(16))
            var output = [UInt8](repeating: 0, count: payload.count + kCCBlockSizeAES128), written = 0
            let status = key.withUnsafeBytes { key in iv.withUnsafeBytes { iv in payload.withUnsafeBytes { input in output.withUnsafeMutableBytes { destination in
                CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding), key.baseAddress, key.count, iv.baseAddress, input.baseAddress, input.count, destination.baseAddress, destination.count, &written)
            } } } }
            guard status == kCCSuccess else { throw SchoolFailure.structure }
            envelope["data"] = try JSONDecoder().decode(JSONValue.self, from: Data(output.prefix(written)))
        }
        return .object(envelope)
    }
    public static func confirms(_ response: JSONValue, owner: String) -> Bool {
        guard response["code"].number == 200, !response["data"]["st"].text.isEmpty else { return false }
        let body = response["data"], primary = body["user"], primaryID = primary["id"].text, number = primary["number"].text
        if !number.isEmpty { return number == owner && !primaryID.isEmpty }
        let users = body["users"].list
        return users.filter { $0["number"].text == owner && (!primaryID.isEmpty ? $0["id"].text == primaryID : users.count == 1) }.count == 1
    }
}

public struct SchoolSSORequest: Sendable {
    public let realm: String
    public let appID: String
    public let service: URL
    public var attemptKey: String { realm + "|" + appID + "|" + service.absoluteString }
    public init?(_ url: URL) {
        guard SchoolURLPolicy.allows(url), url.query == nil, let c = URLComponents(url: url, resolvingAgainstBaseURL: false), let fragment = c.percentEncodedFragment,
              ["", "/"].contains(String(fragment.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)[0])),
              let separator = fragment.firstIndex(of: "?") else { return nil }
        let base: String
        if url.host == "auth.sicau.edu.cn", c.path == "/wui/" { base = "https://auth.sicau.edu.cn" }
        else if let route = AcademicRoute(resourceURL: url), route.prefix.hasPrefix("/https/"), c.path == route.prefix + "/wui/" { base = "https://webvpn.sicau.edu.cn" + route.prefix }
        else { return nil }
        let raw = String(fragment[fragment.index(after: separator)...]), pairs = URLComponents(string: "https://local.invalid/?" + raw)?.queryItems ?? []
        guard !pairs.isEmpty, Set(pairs.map(\.name)).count == pairs.count, pairs.allSatisfy({ ["appid", "service", "cascallback"].contains($0.name) }) else { return nil }
        let values = Dictionary(uniqueKeysWithValues: pairs.map { ($0.name, $0.value ?? "") })
        guard values["cascallback"] == nil || ["", "choose"].contains(values["cascallback"]!), let app = values["appid"], app.range(of: "^[A-Za-z0-9_-]{1,128}$", options: .regularExpression) != nil,
              let rawService = values["service"], let destination = URL(string: rawService), SchoolURLPolicy.allows(destination),
              Self.allowsService(destination),
              destination.fragment == nil || (destination.host == "ywtb.sicau.edu.cn" && destination.fragment!.hasPrefix("/")),
              !(URLComponents(url: destination, resolvingAgainstBaseURL: false)?.queryItems ?? []).contains(where: { ["ticket", "userId"].contains($0.name) }) else { return nil }
        realm = base; appID = app; service = destination
    }
    private static func allowsService(_ url: URL) -> Bool {
        if url.host == "jiaowu.sicau.edu.cn" { return url.path == AcademicRoute.unifiedLoginPath && url.query == nil }
        return ["webvpn.sicau.edu.cn", "ywtb.sicau.edu.cn", "xsgz.sicau.edu.cn", "ehall.sicau.edu.cn", "op.sicau.edu.cn", "ecology.sicau.edu.cn"].contains(url.host)
    }
    public func endpoint(_ base: String) -> URL? {
        guard base == "https://auth.sicau.edu.cn" || Self.validProxyRealm(base) else { return nil }
        var c = URLComponents(string: base + "/api/v1/cas/login")!; c.queryItems = [URLQueryItem(name: "appid", value: appID)]; return c.url
    }
    public func callback(_ response: JSONValue, owner: String) -> URL? {
        guard !owner.isEmpty, SchoolSSOEnvelope.confirms(response, owner: owner) else { return nil }
        let body = response["data"], primary = body["user"], primaryID = primary["id"].text, users = body["users"].list
        guard case .array = body["users"] else { return nil }
        let candidates = users.filter { user in let id = user["id"].text, number = user["number"].text; return !id.isEmpty && (primaryID.isEmpty || id == primaryID) && (number == owner || number.isEmpty && id == primaryID) }
        let user: JSONValue
        if users.isEmpty { user = primary } else if candidates.count == 1 { user = candidates[0] } else { return nil }
        let id = user["id"].text, ticket = body["st"].text
        guard !id.isEmpty, id.count <= 128, !ticket.isEmpty, ticket.count <= 4096,
              user["number"].text == owner || id == primaryID,
              !(id + ticket).unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) else { return nil }
        var c = URLComponents(url: service, resolvingAgainstBaseURL: false)!
        c.queryItems = (c.queryItems ?? []) + [URLQueryItem(name: "ticket", value: ticket + ":" + id), URLQueryItem(name: "userId", value: id)]
        return c.url
    }
    public static func validProxyRealm(_ base: String) -> Bool {
        guard let url = URL(string: base + "/wui/"), let route = AcademicRoute(resourceURL: url) else { return false }
        return route.prefix.hasPrefix("/https/") && base == "https://webvpn.sicau.edu.cn" + route.prefix
    }
    public static func vpnRealm(_ url: URL) -> String? {
        guard let request = Self(url), request.service.host == "webvpn.sicau.edu.cn", request.service.path == "/login",
              URLComponents(url: request.service, resolvingAgainstBaseURL: false)?.queryItems?.contains(URLQueryItem(name: "cas_login", value: "true")) == true,
              validProxyRealm(request.realm) else { return nil }; return request.realm
    }
    public static func reuseURL(_ url: URL) -> URL? {
        guard Self(url) != nil, var components = URLComponents(url: url, resolvingAgainstBaseURL: false), let fragment = components.percentEncodedFragment,
              !fragment.components(separatedBy: "&").contains(where: { $0.hasPrefix("cascallback=") }) else { return nil }
        components.percentEncodedFragment = fragment + "&cascallback=choose"; return components.url
    }
}
