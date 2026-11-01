import Foundation

/// Preserve server attributes and absolute expiry. Never renew Max-Age when restoring a snapshot.
public enum SchoolCookieSnapshot {
    private static func valid(_ cookie: HTTPCookie, now: Date) -> Bool {
        let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return (domain == "sicau.edu.cn" || domain.hasSuffix(".sicau.edu.cn")) && (cookie.expiresDate.map { $0 > now } ?? true)
    }
    public static func encode(_ cookies: [HTTPCookie], now: Date = .now) throws -> Data {
        let rows = cookies.filter { valid($0, now: now) }.prefix(1024).compactMap { cookie -> [String: Any]? in
            guard var properties = cookie.properties,
                  !properties.keys.contains(where: { $0.rawValue.lowercased().contains("partition") }) else { return nil }
            if properties[.maximumAge] != nil && cookie.expiresDate == nil { return nil }
            properties.removeValue(forKey: .maximumAge)
            if let expiry = cookie.expiresDate { properties[.expires] = expiry }
            if cookie.isHTTPOnly { properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
            if cookie.isSecure { properties[.secure] = "TRUE" }
            if let sameSite = cookie.sameSitePolicy { properties[.sameSitePolicy] = sameSite }
            return Dictionary(uniqueKeysWithValues: properties.map { key, value in (key.rawValue, (value as? URL)?.absoluteString as Any? ?? value) })
        }
        let data = try PropertyListSerialization.data(fromPropertyList: rows, format: .binary, options: 0)
        guard data.count <= 2_000_000 else { throw SchoolFailure.structure }; return data
    }
    public static func decode(_ data: Data, now: Date = .now) throws -> [HTTPCookie] {
        guard data.count <= 2_000_000,
              let rows = try PropertyListSerialization.propertyList(from: data, format: nil) as? [[String: Any]], rows.count <= 1024 else { throw SchoolFailure.structure }
        return rows.compactMap { row in
            var values = Dictionary(uniqueKeysWithValues: row.map { (HTTPCookiePropertyKey($0.key), $0.value) })
            guard !values.keys.contains(where: { $0.rawValue.lowercased().contains("partition") }) else { return nil }
            if values[.maximumAge] != nil && !(values[.expires] is Date) { return nil }
            values.removeValue(forKey: .maximumAge)
            guard let cookie = HTTPCookie(properties: values), valid(cookie, now: now) else { return nil }; return cookie
        }
    }
}
