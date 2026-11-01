import Foundation
import Observation

@MainActor @Observable
final class PlatformSession {
    private struct Saved: Codable { var token: String; var user: AuthUser }
    private(set) var user: AuthUser?
    private(set) var token: String?
    private(set) var offline = false
    private(set) var busy = false
    var error: String?
    let client = APIClient()
    private var generation = 0
    private var restored = false
    private var isVisualPreview=false
    var allowsPresenceReporting: Bool { !isVisualPreview }
    var signedIn: Bool { user?.accountType == "PHONE" && token != nil }
    var installationID: String {
        if let id=UserDefaults.standard.string(forKey:"platform.installationID"){return id}
        let id=UUID().uuidString;UserDefaults.standard.set(id,forKey:"platform.installationID");return id
    }
    init(loadSaved: Bool = true) {
        guard loadSaved else { isVisualPreview=true;return }
        do {
            if let data=try SecureStore.read("session",realm:"platform"),let saved=try? JSONDecoder().decode(Saved.self,from:data){user=saved.user;token=saved.token;offline=true}
        } catch { self.error=error.localizedDescription }
    }
    func restore() async {
        guard !restored else{return};restored=true
        guard let token else{return};let epoch=generation
        do {
            let account:AuthUser=try await client.request("auth/me",token:token)
            guard epoch==generation else{return}
            try persist(token:token,user:account)
        } catch APIError.server(let status,let message) where status==401 || status==403 {
            guard epoch==generation else{return};try? clear();error=message
        } catch { if epoch==generation {offline=true} }
    }
    func authenticate(phone:String,password:String,nickname:String?,consented:Bool,
                      confirmPassword:String? = nil, challengeId:String? = nil, code:String? = nil) async throws {
        guard !isVisualPreview,!busy,CampusContract.validPhone(phone),CampusContract.validPassword(password),nickname == nil || consented else{throw APIError.server(422,"请核对手机号、密码与协议选项")}
        busy=true;defer{busy=false};error=nil;generation+=1;let epoch=generation
        var body:[String:JSONValue]=["phone":.string(phone.trimmingCharacters(in:.whitespacesAndNewlines)),"password":.string(password),"installationId":.string(installationID),"versionName":.string(Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "0.1.0"),"versionCode":.number(Double(Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "1") ?? 1)]
        if let nickname {
            guard PhoneAccountRules.validConfirmation(password: password, confirmation: confirmPassword ?? ""),
                  PhoneAccountRules.validCode(code ?? ""), let challengeId, !challengeId.isEmpty else {
                throw APIError.server(422,"请核对确认密码和短信验证码")
            }
            body["nickname"] = .string(nickname.trimmingCharacters(in:.whitespacesAndNewlines))
            body["confirmPassword"] = .string(confirmPassword ?? "")
            body["challengeId"] = .string(challengeId)
            body["code"] = .string(code ?? "")
            body.merge(try consentReceipt()) { _, new in new }
        }
        let auth:AuthData=try await client.request(nickname==nil ? "auth/login":"auth/register",method:"POST",body:JSONEncoder().encode(body))
        guard epoch==generation else{throw CancellationError()};try persist(token:auth.token,user:auth.user)
    }
    func phoneCapabilities() async throws -> PhoneAuthCapabilities {
        guard !isVisualPreview else { throw APIError.server(503,"短信验证待开通") }
        return try await client.request("auth/capabilities")
    }
    private func consentReceipt() throws -> [String:JSONValue] {
        guard UserDefaults.standard.bool(forKey:PrivacyConsent.storageKey), PrivacyConsent.acceptedAt > 0 else {
            throw APIError.server(422,"请先阅读并同意当前隐私政策与用户协议")
        }
        return ["policyVersion":.string(PrivacyConsent.policyVersion),"consentAcceptedAt":.number(Double(PrivacyConsent.acceptedAt))]
    }
    func requestSMS(phone:String,mode:PhoneAccountMode) async throws -> SMSChallenge {
        guard !isVisualPreview,!busy,mode != .login,CampusContract.validPhone(phone) else { throw APIError.server(422,"请核对手机号") }
        busy=true;defer{busy=false};let epoch=generation
        var body=try consentReceipt();body["phone"] = .string(phone);body["purpose"] = .string(mode.purpose)
        let result:SMSChallenge=try await client.request("auth/sms-code",method:"POST",body:JSONEncoder().encode(body),token:mode == .verify ? token : nil)
        guard epoch==generation else{throw CancellationError()};return result
    }
    func resetPassword(phone:String,password:String,confirmation:String,challengeId:String,code:String) async throws -> PasswordResetResult {
        guard !isVisualPreview,!busy,PhoneAccountRules.validConfirmation(password:password,confirmation:confirmation),PhoneAccountRules.validCode(code) else { throw APIError.server(422,"请核对确认密码和验证码") }
        busy=true;defer{busy=false}
        var body=try consentReceipt()
        body.merge(["phone":.string(phone),"password":.string(password),"confirmPassword":.string(confirmation),"challengeId":.string(challengeId),"code":.string(code)]){_,new in new}
        let result:PasswordResetResult=try await client.request("auth/reset-password",method:"POST",body:JSONEncoder().encode(body))
        // The server revokes sessions after recovery. Clear only this platform session.
        if result.reset, token != nil { try clear() }
        return result
    }
    func verifyPhone(challengeId:String,code:String) async throws {
        guard !isVisualPreview,!busy,let token else{throw APIError.server(401,"请先登录平台账号")}
        busy=true;defer{busy=false};let epoch=generation
        var body=try consentReceipt();body["challengeId"] = .string(challengeId);body["code"] = .string(code)
        let user:AuthUser=try await client.request("auth/verify-phone",method:"POST",body:JSONEncoder().encode(body),token:token)
        guard epoch==generation else{throw CancellationError()};try persist(token:token,user:user)
    }
    func perform(_ path:String,method:String="GET",body:[String:JSONValue]?=nil,query:[String:String]=[:]) async throws -> JSONValue {
        guard signedIn,let token else{throw APIError.server(401,"请先登录我的川农平台账号")}
        let epoch=generation
        do {
            let result:JSONValue=try await client.request(path,method:method,body:try body.map{try JSONEncoder().encode($0)},token:token,query:query)
            guard epoch==generation else{throw CancellationError()};return result
        }catch APIError.server(let status,let message) where status==401{
            if epoch==generation{try? clear()};throw APIError.server(status,message)
        }
    }
    func bindStudentIdentity(studentId:String,realName:String) async throws {
        guard !isVisualPreview,!busy,let token,user?.phoneVerified == true else {
            throw APIError.server(403,"请先验证绑定手机号")
        }
        busy=true;defer{busy=false};let epoch=generation
        var body=try consentReceipt()
        body.merge(["studentId":.string(studentId.trimmingCharacters(in:.whitespacesAndNewlines).uppercased()),
                    "realName":.string(realName.trimmingCharacters(in:.whitespacesAndNewlines)),"schoolCode":.string("SICAU")]){_,new in new}
        let _:StudentIdentityResult=try await client.request("auth/student-identity",method:"PUT",body:JSONEncoder().encode(body),token:token)
        let account:AuthUser=try await client.request("auth/me",token:token)
        guard epoch==generation else{throw CancellationError()};try persist(token:token,user:account)
    }
    func nickname(_ value:String) async throws {
        guard let token else{return};let epoch=generation
        let account:AuthUser=try await client.request("auth/profile",method:"PATCH",body:JSONEncoder().encode(["nickname":value]),token:token)
        guard epoch==generation else{throw CancellationError()};try persist(token:token,user:account)
    }
    func logout() async throws {
        let old=token
        try clear()
        if let old{let _:JSONValue=try await client.request("auth/logout",method:"POST",body:Data("{}".utf8),token:old)}
    }
    func deleteAccount(password:String) async throws {
        _ = try await perform("auth/account",method:"DELETE",body:["password":.string(password)])
        try clear()
    }
    private func persist(token:String,user:AuthUser) throws {
        guard user.accountType=="PHONE",["ACTIVE","LIMITED"].contains(user.accountStatus ?? "ACTIVE") else{try clear();throw APIError.server(403,"账号当前不可用，请联系管理员")}
        try SecureStore.write(JSONEncoder().encode(Saved(token:token,user:user)),key:"session",realm:"platform")
        self.token=token;self.user=user;offline=false
    }
    private func clear() throws {
        try SecureStore.write(nil,key:"session",realm:"platform");generation+=1;token=nil;user=nil;offline=false
    }
}
