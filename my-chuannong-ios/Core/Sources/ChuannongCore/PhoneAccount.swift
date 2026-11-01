import Foundation

public enum PhoneAccountMode: String, Sendable {
    case login, register, reset, verify
    public var purpose: String { self == .verify ? "verify_phone" : rawValue }
    public var needsNewPassword: Bool { self == .register || self == .reset }
    public var title: String {
        switch self {
        case .login: "登录我的川农账号"
        case .register: "创建我的川农账号"
        case .reset: "找回密码"
        case .verify: "验证绑定手机号"
        }
    }
}

public struct PhoneAuthCapabilities: Decodable, Sendable {
    public let availablePurposes: [String]
    public let resetLimit: Int
    public let policyVersion: String
}
public struct SMSChallenge: Decodable, Sendable {
    public let challengeId: String
    public let expiresIn: Int
    public let retryAfter: Int
}
public struct PasswordResetResult: Decodable, Sendable {
    public let reset: Bool
    public let loginRequired: Bool
    public let remainingToday: Int
}
public struct StudentIdentityResult: Decodable, Sendable {
    public let studentId: String?
    public let realName: String?
    public let identityStatus: String
    public let phoneVerified: Bool
}
public enum PhoneAccountRules {
    public static let reminder = "请牢记密码并妥善保管绑定手机号。每个账号每天最多找回密码两次，超限后次日恢复，账号和数据不会删除。"
    public static func validCode(_ code: String) -> Bool {
        code.count == 6 && code.utf8.allSatisfy { (48...57).contains($0) }
    }
    public static func validConfirmation(password: String, confirmation: String) -> Bool {
        CampusContract.validPassword(password) && !password.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && password == confirmation
    }
}
