import Foundation
import Testing
import CryptoKit
import CommonCrypto
@testable import ChuannongCore

@Test func schoolLoginNoticesKeepReasonAndRemoveEnteredCredentials() {
    let issue = SchoolLoginIssue(message: "synthetic-user 的密码 synthetic-password 不正确", sensitiveValues: ["synthetic-user", "synthetic-password"])
    #expect(issue.reason == .credentials)
    #expect(!issue.notice.contains("synthetic-user"))
    #expect(!issue.notice.contains("synthetic-password"))
    #expect(SchoolFailure.reason(issue) == .credentials)
    #expect(SchoolLoginIssue(message: "请完成短信验证码", sensitiveValues: []).reason == .verification)
    #expect(SchoolLoginIssue(message: "请通过正常链接登录", sensitiveValues: []).reason == .loginRejected)
    #expect(SchoolLoginIssue(message: "该账号必须采用扫码或统一身份认证方式登录！", sensitiveValues: []).reason == .unifiedAuthentication)
}

@Test func academicTimeoutAlertsEnterRecoveryWithoutRetryingRejectedCredentials() {
    #expect(SchoolFailure.reason(SchoolLoginIssue(message: "系统提示：登录超时，请重新登录！", sensitiveValues: [])) == .expired)
    #expect(SchoolLoginIssue(message: "会话已失效，请重新登录", sensitiveValues: []).reason == .expired)
    #expect(SchoolLoginIssue(message: "登录类别错误，请重新登录！", sensitiveValues: []).reason == .loginRejected)
    #expect(SchoolLoginIssue(message: "密码错误，请重新登录", sensitiveValues: []).reason == .credentials)
    #expect(SchoolLoginIssue(message: "登录超时，请完成短信验证码", sensitiveValues: []).reason == .verification)
}

@Test func persistentSchoolCookiesKeepAttributesAndOriginalDeadline() throws {
    let now=Date.now,deadline=now.addingTimeInterval(3600)
    let cookie=try #require(HTTPCookie(properties:[.name:"synthetic-session",.value:"test-only",.domain:".sicau.edu.cn",.path:"/test/",.secure:"TRUE",HTTPCookiePropertyKey("HttpOnly"):"TRUE",.sameSitePolicy:HTTPCookieStringPolicy.sameSiteLax,.expires:deadline]))
    let restored=try #require(SchoolCookieSnapshot.decode(SchoolCookieSnapshot.encode([cookie],now:now),now:now.addingTimeInterval(90)).first)
    #expect(restored.value==cookie.value)
    #expect(restored.domain==cookie.domain && restored.path==cookie.path)
    #expect(restored.isSecure && restored.isHTTPOnly)
    #expect(restored.sameSitePolicy==cookie.sameSitePolicy)
    #expect(abs(try #require(restored.expiresDate).timeIntervalSince(deadline))<1)
    #expect(try SchoolCookieSnapshot.decode(SchoolCookieSnapshot.encode([cookie],now:now),now:deadline.addingTimeInterval(1)).isEmpty)
}
@Test func maximumAgeIsNotRenewedByRepeatedRestoration() throws {
    let now=Date.now
    let cookie=try #require(HTTPCookie(properties:[.name:"synthetic-maxage",.value:"test-only",.domain:"auth.sicau.edu.cn",.path:"/",.maximumAge:"120",.secure:"TRUE"]))
    let expiry=try #require(cookie.expiresDate)
    let data=try SchoolCookieSnapshot.encode([cookie],now:now)
    let once=try SchoolCookieSnapshot.decode(data,now:now.addingTimeInterval(60))
    #expect(once.count==1)
    #expect(abs(try #require(once.first?.expiresDate).timeIntervalSince(expiry))<1)
    let again=try SchoolCookieSnapshot.encode(once,now:now.addingTimeInterval(60))
    #expect(try SchoolCookieSnapshot.decode(again,now:expiry.addingTimeInterval(1)).isEmpty)
}
@Test func sessionOnlyCookiesSurviveAppRestartWithoutInventedExpiry() throws {
    let cookie=try #require(HTTPCookie(properties:[.name:"ASPSESSIONID_TEST",.value:"test-only",.domain:"webvpn.sicau.edu.cn",.path:"/https/0123456789abcdef0123456789abcdef/",.secure:"TRUE",.discard:"TRUE"]))
    let restored=try #require(SchoolCookieSnapshot.decode(SchoolCookieSnapshot.encode([cookie])).first)
    #expect(restored.expiresDate==nil)
    #expect(restored.path==cookie.path)
}
@Test func cookieRestorationRejectsExpiredForeignAndMalformedRecords() throws {
    let now=Date.now
    let expired=try #require(HTTPCookie(properties:[.name:"old",.value:"test",.domain:"auth.sicau.edu.cn",.path:"/",.expires:now.addingTimeInterval(-1)]))
    let foreign=try #require(HTTPCookie(properties:[.name:"foreign",.value:"test",.domain:"sicau.edu.cn.evil.invalid",.path:"/"]))
    #expect(try SchoolCookieSnapshot.decode(SchoolCookieSnapshot.encode([expired,foreign],now:now),now:now).isEmpty)
    let legacy=try PropertyListSerialization.data(fromPropertyList:[["Name":"old-age","Value":"test","Domain":"auth.sicau.edu.cn","Path":"/","Max-Age":"120"]],format:.binary,options:0)
    #expect(try SchoolCookieSnapshot.decode(legacy).isEmpty)
    #expect(throws:(any Error).self){try SchoolCookieSnapshot.decode(Data("not a plist".utf8))}
}
@Test func refreshProtectsReviewedAndManualRowsWithMatchingSchoolKeys() throws {
    let term="2026-2027-1"
    let manual=Course(name:"自定义",weekday:1,start:1,length:2,weeks:[1],term:term,source:"MANUAL")
    let reviewed=Course(name:"已核对",weekday:2,start:3,length:2,weeks:[3],term:term,source:"IMPORTED")
    var duplicate=manual;duplicate.source="SCHOOL";duplicate.weeks=[1,2,3]
    var duplicateReview=reviewed;duplicateReview.source="SCHOOL";duplicateReview.weeks=[1,2,3]
    let school=Course(name:"新学校课",weekday:3,start:1,length:2,weeks:[1],term:term)
    var nextWeek=school;nextWeek.weeks=[2]
    var snapshot=AcademicSnapshot(owner:"SYNTHETIC");snapshot.courses=[manual,reviewed]
    snapshot.receive(CourseBatch(term:term,courses:[duplicate,duplicateReview,school,nextWeek],unscheduled:[]))
    #expect(snapshot.courses.count==3)
    #expect(snapshot.courses.first{$0.name=="自定义"}?.weeks==[1])
    #expect(snapshot.courses.first{$0.name=="已核对"}?.weeks==[3])
    #expect(snapshot.courses.first{$0.name=="新学校课"}?.weeks==[1,2])
    snapshot.receive(CourseBatch(term:term,courses:[school],unscheduled:[]),reviewedImport:true)
    #expect(snapshot.courses.count==2)
    #expect(Set(snapshot.courses.map(\.source))==["MANUAL","IMPORTED"])
}
private func ssoURL(_ service:String="https://webvpn.sicau.edu.cn/login?cas_login=true")->URL {
    var query=URLComponents();query.queryItems=[URLQueryItem(name:"appid",value:"sicau-cas"),URLQueryItem(name:"service",value:service)]
    var url=URLComponents(string:"https://auth.sicau.edu.cn/wui/")!;url.percentEncodedFragment="/?"+query.percentEncodedQuery!;return url.url!
}
private var ssoResponse:JSONValue { .object(["code":.number(200),"data":.object(["st":.string("synthetic-ticket"),"user":.object(["id":.number(1234567),"number":.string("SYNTHETIC1")]),"users":.array([.object(["id":.number(1234567),"number":.string("SYNTHETIC1")])])])]) }
@Test func ssoCallbackRequiresBoundPrimaryOwnerAndUsesUnformattedIDs() throws {
    let request=try #require(SchoolSSORequest(ssoURL()))
    let callback=try #require(request.callback(ssoResponse,owner:"SYNTHETIC1"))
    let values=URLComponents(url:callback,resolvingAgainstBaseURL:false)!.queryItems!
    #expect(values.contains(URLQueryItem(name:"ticket",value:"synthetic-ticket:1234567")))
    #expect(values.contains(URLQueryItem(name:"userId",value:"1234567")))
    #expect(request.callback(ssoResponse,owner:"SYNTHETIC2")==nil)
    let delegated:JSONValue = .object(["code":.number(200),"data":.object(["st":.string("synthetic-ticket"),"user":.object(["id":.string("primary"),"number":.string("SYNTHETIC2")]),"users":.array([.object(["id":.string("delegated"),"number":.string("SYNTHETIC1")])])])])
    #expect(request.callback(delegated,owner:"SYNTHETIC1")==nil)
}
@Test func ssoRejectsForeignCallbacksAndPreexistingTicketParameters() {
    for service in ["https://evil.invalid/login","https://webvpn.sicau.edu.cn.evil.invalid/login","http://webvpn.sicau.edu.cn/login","https://webvpn.sicau.edu.cn/login?ticket=old","https://user:password@webvpn.sicau.edu.cn/login"]{#expect(SchoolSSORequest(ssoURL(service))==nil)}
    #expect(SchoolSSORequest.validProxyRealm("https://webvpn.sicau.edu.cn/https/0123456789abcdef0123456789abcdef"))
    #expect(!SchoolSSORequest.validProxyRealm("https://webvpn.sicau.edu.cn/http/0123456789abcdef0123456789abcdef"))
}
@Test func encryptedSchoolEnvelopeRoundTripsAndRejectsTamperedCiphertext() throws {
    let requestID="synthetic-request",key=Array(Insecure.MD5.hash(data:Data((requestID+":sicau-cas").utf8))),iv=[UInt8](repeating:7,count:16)
    let plain=Array(try JSONEncoder().encode(ssoResponse["data"]))
    var encrypted=[UInt8](repeating:0,count:plain.count+16),written=0
    let status=key.withUnsafeBytes{k in iv.withUnsafeBytes{v in plain.withUnsafeBytes{p in encrypted.withUnsafeMutableBytes{e in CCCrypt(CCOperation(kCCEncrypt),CCAlgorithm(kCCAlgorithmAES),CCOptions(kCCOptionPKCS7Padding),k.baseAddress,k.count,v.baseAddress,p.baseAddress,p.count,e.baseAddress,e.count,&written)}}}}
    #expect(status==kCCSuccess)
    let envelope:JSONValue = .object(["code":.number(200),"requestId":.string(requestID),"data":.string(Data(iv+encrypted.prefix(written)).base64EncodedString())])
    let decoded=try SchoolSSOEnvelope.decode(JSONEncoder().encode(envelope))
    #expect(SchoolSSOEnvelope.confirms(decoded,owner:"SYNTHETIC1"))
    #expect(throws:(any Error).self){try SchoolSSOEnvelope.decode(Data(#"{"code":200,"requestId":"x","data":"invalid-base64"}"#.utf8))}
}

@Test func academicSSOAcceptsOnlyTheOfficialSecureCallback() throws {
    let service = "https://jiaowu.sicau.edu.cn" + AcademicRoute.unifiedLoginPath
    let request = try #require(SchoolSSORequest(ssoURL(service)))
    #expect(request.service.absoluteString == service)
    let callback = try #require(request.callback(ssoResponse, owner: "SYNTHETIC1"))
    #expect(callback.host == "jiaowu.sicau.edu.cn" && callback.path == AcademicRoute.unifiedLoginPath)
    #expect(request.callback(ssoResponse, owner: "SYNTHETIC2") == nil)
    for invalid in [
        "http://jiaowu.sicau.edu.cn" + AcademicRoute.unifiedLoginPath,
        "https://jiaowu.sicau.edu.cn/other/callback",
        service + "?redirect=https://evil.invalid",
        service + "?ticket=old",
        service + "#unexpected",
        "https://jiaowu.sicau.edu.cn.evil.invalid" + AcademicRoute.unifiedLoginPath
    ] { #expect(SchoolSSORequest(ssoURL(invalid)) == nil) }
}
