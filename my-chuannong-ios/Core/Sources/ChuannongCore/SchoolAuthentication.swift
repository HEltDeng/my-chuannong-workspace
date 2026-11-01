import Foundation

/// Passwords are encoded only for the device-only school Keychain and school HTTPS request.
public struct SchoolCredential: Codable, Sendable {
    public let account: String
    public let password: String
    public init(account: String, password: String) { self.account = account; self.password = password }
    public func belongs(to owner: String?) -> Bool { owner == account && SchoolSSOEnvelope.validOwner(account) && !password.isEmpty }
}

public struct SchoolChallenge: Sendable {
    public let id: String
    public let image: Data
    public init(response: JSONValue) throws {
        let encoded = response["data"].text
        guard response["code"].number == 200, !response["id"].text.isEmpty,
              let comma = encoded.firstIndex(of: ","),
              ["data:image/png;base64", "data:image/jpeg;base64", "data:image/gif;base64"].contains(String(encoded[..<comma])),
              let bytes = Data(base64Encoded: String(encoded[encoded.index(after: comma)...])),
              !bytes.isEmpty, bytes.count < 1_000_000 else { throw SchoolFailure.structure }
        id = response["id"].text; image = bytes
    }
}

public enum SchoolAuthentication {
    public static func loginBody(credential: SchoolCredential, code: String, challenge: SchoolChallenge) throws -> Data {
        guard SchoolSSOEnvelope.validOwner(credential.account), !credential.password.isEmpty,
              !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw SchoolFailure.verification }
        return try JSONSerialization.data(withJSONObject: ["appid": "sicau-cas", "number": credential.account,
            "password": credential.password, "code": code, "uuid": challenge.id])
    }
    public static func requiresAuthentication(_ error: Error) -> Bool {
        guard let reason = SchoolFailure.reason(error) else { return false }
        return [.expired, .vpn, .unifiedAuthentication, .verification, .credentials, .autoLoginDisabled, .autoLoginStopped].contains(reason)
    }
    public static func canRecover(_ error: Error) -> Bool {
        guard let reason = SchoolFailure.reason(error) else { return false }
        return [.expired, .vpn, .unifiedAuthentication].contains(reason)
    }
}
