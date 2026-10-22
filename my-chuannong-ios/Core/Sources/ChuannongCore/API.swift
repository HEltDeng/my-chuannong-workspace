import Foundation

public enum Product {
    public static let api = URL(string: "https://chuannong-api.mychangliapp.cn/api/v1/")!
    public static let origin = URL(string: "https://chuannong-api.mychangliapp.cn")!
    public static let fileHost = "chuannong-files.mychangliapp.cn"
    public static let bundleID = "com.mychuannong.app"
    public static let version = "1.0.0"
}

public struct APIEnvelope<T: Decodable & Sendable>: Decodable, Sendable {
    public let ok: Bool
    public let data: T?
    public let error: APIErrorBody?
}
public struct APIErrorBody: Decodable, Sendable { public let code: String; public let message: String }
public enum APIError: Error, LocalizedError {
    case invalidRoute, server(Int, String), invalidResponse
    public var errorDescription: String? {
        switch self {
        case .invalidRoute: "请求地址无效"
        case let .server(_, message): message
        case .invalidResponse: "服务器响应无效，请稍后重试"
        }
    }
}

/// A product-only transport. School cookies and credentials never enter this session.
public actor APIClient {
    private let session: URLSession
    public init(session: URLSession? = nil) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        self.session = session ?? URLSession(configuration: configuration, delegate: ProductRedirectPolicy(), delegateQueue: nil)
    }
    public static func isProductURL(_ url: URL?) -> Bool {
        guard let url else { return false }
        return url.scheme == "https" && url.host == Product.api.host &&
            (url.port == nil || url.port == 443) && url.user == nil && url.password == nil &&
            url.path.hasPrefix("/api/v1/")
    }
    public static func url(for path: String) throws -> URL {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("://"),
              !path.contains(".."), !path.contains("\\"), !path.contains("#"),
              !path.contains("%"),
              let url = URL(string: path, relativeTo: Product.api)?.absoluteURL,
              isProductURL(url) else { throw APIError.invalidRoute }
        return url
    }
    public func request<T: Decodable & Sendable>(_ path: String, method: String = "GET", body: Data? = nil, token: String? = nil) async throws -> T {
        var request = URLRequest(url: try Self.url(for: path))
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        let envelope = try JSONDecoder().decode(APIEnvelope<T>.self, from: data)
        guard (200...299).contains(http.statusCode), envelope.ok, let value = envelope.data else {
            throw APIError.server(http.statusCode, envelope.error?.message ?? "服务暂不可用")
        }
        return value
    }
}

private final class ProductRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        APIClient.isProductURL(request.url) ? request : nil
    }
}

public struct Announcement: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let type: String
    public let title: String
    public let summary: String?
    public let imageUrl: String?
    public let targetUrl: String?
    public let publishedAt: Int64?
    public let category: String?
    public static func visible(in feed: [Self]) -> [Self] { feed.filter { $0.type == "ANNOUNCEMENT" } }
    public var imageURL: URL? {
        guard let imageUrl else { return nil }
        let url = URL(string: imageUrl, relativeTo: Product.origin)?.absoluteURL
        guard let url, url.scheme == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443,
              [Product.origin.host, Product.fileHost].contains(url.host) else { return nil }
        return url
    }
    public var destination: URL? {
        guard let targetUrl, let url = URL(string: targetUrl), url.scheme == "https", url.host != nil, url.user == nil, url.password == nil else { return nil }
        return url
    }
}

public struct AuthUser: Codable, Sendable {
    public let id: String
    public let nickname: String
    public let accountType: String
    public let phoneMasked: String?
}
public struct AuthData: Codable, Sendable { public let token: String; public let user: AuthUser }
public struct ResourceItem: Decodable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let description: String?
    public let category: String?
}

public enum SchoolURLPolicy {
    public static func allows(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased(), url.user == nil, url.password == nil else { return false }
        return host == "sicau.edu.cn" || host.hasSuffix(".sicau.edu.cn")
    }
}
