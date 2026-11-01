import Foundation
import WebKit


/// School-only HTTPS requests. Password submission requires a user-completed school challenge.
@MainActor final class SchoolSSOBroker {
    private let store: WKHTTPCookieStore
    private let current: @MainActor () -> Bool
    private let session: URLSession
    init(store: WKHTTPCookieStore, configuration: URLSessionConfiguration = .ephemeral, current: @escaping @MainActor () -> Bool) {
        self.store = store; self.current = current
        let config = configuration; config.httpCookieStorage = nil; config.httpShouldSetCookies = false; config.urlCache = nil; config.timeoutIntervalForRequest = 15; config.timeoutIntervalForResource = 20
        session = URLSession(configuration: config, delegate: SchoolSSONoRedirect(), delegateQueue: nil)
    }
    private func guardCurrent() throws { try Task.checkCancellation(); guard current() else { throw CancellationError() } }
    private func cookieHeader(_ url: URL) async throws -> String {
        try guardCurrent(); let cookies = await store.allCookies(); try guardCurrent()
        guard let host = url.host else { return "" }; let path = url.path.isEmpty ? "/" : url.path
        return cookies.filter { cookie in
            let domain = cookie.domain.lowercased(), suffix = domain.hasPrefix(".") ? String(domain.dropFirst()) : domain
            let matches = host == suffix || domain.hasPrefix(".") && host.hasSuffix("." + suffix)
            return matches && (cookie.expiresDate.map { $0 > .now } ?? true) && path.hasPrefix(cookie.path) && (path == cookie.path || cookie.path.hasSuffix("/") || path.dropFirst(cookie.path.count).hasPrefix("/"))
        }.sorted { $0.path.count > $1.path.count }.map { $0.name + "=" + $0.value }.joined(separator: "; ")
    }
    private func receive(_ response: HTTPURLResponse, url: URL) async throws {
        try guardCurrent()
        guard let host = url.host else { return }
        for (key, value) in response.allHeaderFields where String(describing: key).lowercased() == "set-cookie" {
            let header = (value as? [String])?.joined(separator: "\n") ?? String(describing: value)
            let separated = header.replacingOccurrences(of: ",(?=\\s*[^;,=\\s]+=)", with: "\n", options: .regularExpression)
            for raw in separated.components(separatedBy: .newlines) where raw.range(of: ";\\s*Partitioned(?:;|$)", options: [.regularExpression, .caseInsensitive]) == nil {
                for cookie in HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": raw], for: url) {
                    let domain = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
                    guard domain == host || domain == "sicau.edu.cn" else { continue }
                    try guardCurrent()
                    if cookie.expiresDate.map({ $0 <= .now }) == true { await store.deleteCookie(cookie) } else { await store.setCookie(cookie) }
                }
            }
        }
    }
    private func get(_ url: URL, cookies: Bool = true, applyCookies: Bool = true, referer: String? = nil) async throws -> (HTTPURLResponse, Data) {
        try guardCurrent(); guard SchoolURLPolicy.allows(url) else { throw SchoolFailure.structure }
        var request = URLRequest(url: url); request.setValue("application/json,text/html", forHTTPHeaderField: "Accept")
        if cookies { let header = try await cookieHeader(url); if !header.isEmpty { request.setValue(header, forHTTPHeaderField: "Cookie") } }
        if let referer { request.setValue(referer, forHTTPHeaderField: "Referer") }
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.url == url else { throw SchoolFailure.structure }
        if cookies && applyCookies { try await receive(http, url: url) }
        var data = Data(); for try await byte in bytes { guard data.count < 2_000_000 else { throw SchoolFailure.structure }; data.append(byte) }
        try guardCurrent(); return (http, data)
    }
    /// Validate a near-expiry TGT using the same official GET as Android. Only the server can renew it.
    func checkNearExpiry(owner:String,proxy:String?) async throws -> Bool {
        for realm in [proxy,"https://auth.sicau.edu.cn"].compactMap({$0}) {
            guard realm == "https://auth.sicau.edu.cn" || SchoolSSORequest.validProxyRealm(realm),let url=URL(string:realm+"/api/v1/cas/login?appid=sicau-cas") else{continue}
            let cookies=await store.allCookies()
            guard cookies.contains(where:{cookie in
                let domain=cookie.domain.trimmingCharacters(in:CharacterSet(charactersIn:"."))
                return cookie.name == "go-admin-tgt" && (domain==url.host || domain=="sicau.edu.cn") && url.path.hasPrefix(cookie.path) && cookie.expiresDate.map{$0.timeIntervalSinceNow>0 && $0.timeIntervalSinceNow<=120} == true
            }) else{continue}
            let before=try SchoolCookieSnapshot.encode(cookies.sorted{[$0.domain,$0.path,$0.name].lexicographicallyPrecedes([$1.domain,$1.path,$1.name])})
            let (response,data)=try await get(url,applyCookies:false,referer:realm+"/wui/")
            guard (200...299).contains(response.statusCode),SchoolSSOEnvelope.confirms(try SchoolSSOEnvelope.decode(data),owner:owner) else{continue}
            let after=try SchoolCookieSnapshot.encode(await store.allCookies().sorted{[$0.domain,$0.path,$0.name].lexicographicallyPrecedes([$1.domain,$1.path,$1.name])})
            try guardCurrent();guard before==after else{return false}
            try await receive(response,url:url);return true
        }
        return false
    }
    func callback(_ request: SchoolSSORequest, owner: String, proxy: String?) async throws -> URL? {
        var tried = Set<String>()
        for base in [request.realm, proxy, "https://auth.sicau.edu.cn"].compactMap({ $0 }) where tried.insert(base).inserted {
            guard let url = request.endpoint(base) else {continue}
            let header=try await cookieHeader(url)
            guard !header.isEmpty else { continue }
            do {
                let (response, data) = try await get(url, applyCookies:false, referer: base + "/wui/")
                let decoded=try SchoolSSOEnvelope.decode(data)
                if (200...299).contains(response.statusCode),let result = request.callback(decoded,owner:owner) {
                    try await receive(response,url:url);return result
                }
            }
            catch is CancellationError { throw CancellationError() } catch {
                continue
            }
        }
        return nil
    }
    func authenticatedOwner(proxy: String?, expected: String?) async throws -> String? {
        for base in [proxy,"https://auth.sicau.edu.cn"].compactMap({$0}) {
            guard base=="https://auth.sicau.edu.cn" || SchoolSSORequest.validProxyRealm(base),
                  let url=URL(string:base+"/api/v1/cas/login?appid=sicau-cas"),!(try await cookieHeader(url)).isEmpty else {continue}
            do {
                let (response,data)=try await get(url,applyCookies:false,referer:base+"/wui/")
                let decoded=try SchoolSSOEnvelope.decode(data)
                guard (200...299).contains(response.statusCode),let owner=SchoolSSOEnvelope.primaryOwner(decoded) else {continue}
                guard expected==nil || expected==owner else {throw SchoolFailure.changed}
                try await receive(response,url:url);return owner
            } catch is CancellationError {throw CancellationError()}
            catch let error as SchoolFailure where error == .changed {throw error}
            catch {continue}
        }
        return nil
    }
    func discoverProxy() async throws -> String? {
        var url = AcademicRoute.portal
        for _ in 0..<5 {
            if let realm = SchoolSSORequest.vpnRealm(url) { return realm }
            guard url.host == "webvpn.sicau.edu.cn", SchoolURLPolicy.allows(url) else { return nil }
            let (response, _) = try await get(url, cookies: false)
            guard [301,302,303,307,308].contains(response.statusCode), let location = response.value(forHTTPHeaderField: "Location"), let next = URL(string: location, relativeTo: url)?.absoluteURL else { return nil }; url = next
        }
        return SchoolSSORequest.vpnRealm(url)
    }
    func restoreVPN(owner: String, proxy: String?) async throws -> Bool {
        var url = AcademicRoute.portal, visited = Set<URL>(), issued = false
        for _ in 0..<8 {
            guard visited.insert(url).inserted, ["webvpn.sicau.edu.cn", "auth.sicau.edu.cn"].contains(url.host), SchoolURLPolicy.allows(url) else { return false }
            if let request = SchoolSSORequest(url) {
                guard !issued, request.service.host == "webvpn.sicau.edu.cn", request.service.path == "/login", URLComponents(url: request.service, resolvingAgainstBaseURL: false)?.queryItems?.contains(URLQueryItem(name: "cas_login", value: "true")) == true,
                      let next = try await callback(request, owner: owner, proxy: proxy) else { return false }
                url = next; issued = true; visited = []; continue
            }
            let (response, _) = try await get(url)
            if [301,302,303,307,308].contains(response.statusCode) {
                guard let raw = response.value(forHTTPHeaderField: "Location"), let next = URL(string: raw, relativeTo: url)?.absoluteURL else { return false }; url = next
            } else { return (200...299).contains(response.statusCode) && url.host == "webvpn.sicau.edu.cn" && ["/", "/portal", "/m/portal"].contains(url.path) }
        }
        return false
    }
    func challenge() async throws -> SchoolChallenge {
        _ = try await get(URL(string: "https://auth.sicau.edu.cn/wui/")!)
        let (response, data) = try await get(URL(string: "https://auth.sicau.edu.cn/api/v1/captcha")!, referer: "https://auth.sicau.edu.cn/wui/")
        guard response.statusCode == 200 else { throw URLError(.badServerResponse) }
        // The school encrypts the image string in the same CAS envelope as login data.
        return try SchoolChallenge(response: SchoolSSOEnvelope.decode(data))
    }
    func login(_ credential: SchoolCredential, code: String, challenge: SchoolChallenge) async throws {
        try guardCurrent()
        let url = URL(string: "https://auth.sicau.edu.cn/api/v1/cas/login")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try SchoolAuthentication.loginBody(credential: credential, code: code, challenge: challenge)
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("https://auth.sicau.edu.cn/wui/", forHTTPHeaderField: "Referer")
        request.setValue(try await cookieHeader(url), forHTTPHeaderField: "Cookie")
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.url == url, http.statusCode == 200 else { throw URLError(.badServerResponse) }
        var data = Data()
        for try await byte in bytes { guard data.count < 2_000_000 else { throw SchoolFailure.structure }; data.append(byte) }
        try guardCurrent()
        let decoded = try SchoolSSOEnvelope.decode(data)
        guard SchoolSSOEnvelope.confirms(decoded, owner: credential.account) else {
            if SchoolSSOEnvelope.primaryOwner(decoded) != nil { throw SchoolFailure.changed }
            throw SchoolLoginIssue(message: decoded["msg"].text, sensitiveValues: [credential.account, credential.password, code])
        }
        // Apply authentication cookies only after the server confirms the expected student.
        try await receive(http, url: url)
    }
}
private final class SchoolSSONoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest) async -> URLRequest? { nil }
}
