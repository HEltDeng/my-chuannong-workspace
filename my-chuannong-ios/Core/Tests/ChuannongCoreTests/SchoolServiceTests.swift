import Foundation
import Testing
@testable import ChuannongCore

@Test func publicSchoolServicesDoNotRequireAnAcademicVPNMapping() throws {
    let gateway=URL(string:"https://webvpn.sicau.edu.cn/https/0123456789abcdef0123456789abcdef/")!
    for host in ["xsgz.sicau.edu.cn","auth.sicau.edu.cn","www.sicau.edu.cn"] {
        let target=URL(string:"https://\(host)/service")!
        #expect(SchoolServiceNavigation.initial(target,gateway:gateway)==target)
        #expect(SchoolServiceNavigation.initial(target,gateway:nil)==target)
    }
    #expect(SchoolServiceNavigation.initial(URL(string:"https://ywtb.sicau.edu.cn/")!,gateway:nil)==SchoolServiceNavigation.unified)
    #expect(SchoolSSORequest(SchoolServiceNavigation.unified)?.appID=="ywtb")
    #expect(SchoolServiceNavigation.initial(URL(string:"https://op.sicau.edu.cn/")!,gateway:gateway)==gateway)
    let target=URL(string:"https://xsgz.sicau.edu.cn/mobile/scoreLocus/list?term=2026")!
    let entry=SchoolServiceNavigation.initial(target,gateway:gateway)
    #expect(entry.host=="xsgz.sicau.edu.cn" && entry.path=="/mobile/sso")
    #expect(URLComponents(url:entry,resolvingAgainstBaseURL:false)?.queryItems==[URLQueryItem(name:"redirect",value:"/scoreLocus/list?term=2026")])
    #expect(SchoolServiceNavigation.authentication(entry))
    #expect(!SchoolServiceNavigation.targetReached(entry,target:target))
    #expect(SchoolServiceNavigation.targetReached(URL(string:"https://op.sicau.edu.cn/index.aspx")!,target:URL(string:"https://op.sicau.edu.cn/CasLogin.aspx")!))
}

@Test func schoolJourneyReturnsToRequestedServiceOnceAfterAuthentication() {
    let target=URL(string:"https://xsgz.sicau.edu.cn/mobile/checkin?kind=weekly")!
    var journey=SchoolServiceJourney(target:target)
    if case .wait=journey.finished(SchoolServiceNavigation.unified) {} else {Issue.record("Authentication is not a completed service")}
    if case .wait=journey.finished(URL(string:"https://xsgz.sicau.edu.cn/cas/login?ticket=synthetic")!) {} else {Issue.record("CAS callback is not a completed service")}
    if case .returnToTarget=journey.finished(SchoolServiceNavigation.studentHall) {} else {Issue.record("Return to the originally requested subservice")}
    #expect(!journey.reached)
    if case .failed=journey.finished(SchoolServiceNavigation.studentHall) {} else {Issue.record("Do not loop through the hall indefinitely")}
    if case .ready=journey.finished(target) {} else {Issue.record("Requested service should be ready")}
    #expect(journey.reached)
}

@Test func serviceDestinationPreservesSubpageAndHistorySkipsAuthentication() {
    let target=URL(string:"https://xsgz.sicau.edu.cn/mobile/holiday?term=2026#/student")!
    #expect(!SchoolServiceNavigation.targetReached(URL(string:"https://xsgz.sicau.edu.cn/mobile/holiday?term=2025#/student")!,target:target))
    #expect(!SchoolServiceNavigation.targetReached(URL(string:"https://xsgz.sicau.edu.cn/mobile/holiday?term=2026#/teacher")!,target:target))
    #expect(!SchoolServiceNavigation.targetReached(URL(string:"https://evil.invalid/mobile/holiday?term=2026#/student")!,target:target))
    #expect(SchoolServiceNavigation.targetReached(target,target:target))
    #expect(SchoolServiceNavigation.previousBusinessIndex([target,SchoolServiceNavigation.unified,URL(string:"https://xsgz.sicau.edu.cn/cas/login")!])==0)
    #expect(SchoolServiceNavigation.previousBusinessIndex([SchoolServiceNavigation.unified])==nil)
}

@Test func unifiedOwnerMustBeTheServerSelectedPrimaryAccount() {
    func response(_ primary:JSONValue,_ users:[JSONValue],ticket:String="synthetic")->JSONValue {
        .object(["code":.number(200),"data":.object(["st":.string(ticket),"user":primary,"users":.array(users)])])
    }
    let primary:JSONValue = .object(["id":.string("primary"),"number":.string("SYNTHETIC1")])
    let delegated:JSONValue = .object(["id":.string("delegate"),"number":.string("SYNTHETIC2")])
    #expect(SchoolSSOEnvelope.primaryOwner(response(primary,[delegated]))=="SYNTHETIC1")
    #expect(SchoolSSOEnvelope.primaryOwner(response(primary,[primary],ticket:""))==nil)
    #expect(SchoolSSOEnvelope.primaryOwner(response(.object(["id":.string("primary")]),[delegated]))==nil)
    #expect(SchoolSSOEnvelope.primaryOwner(response(.object(["id":.string("primary")]),[primary,delegated]))=="SYNTHETIC1")
    #expect(SchoolSSOEnvelope.primaryOwner(response(.object(["id":.string("primary")]),[primary,primary]))==nil)
    #expect(SchoolSSOEnvelope.primaryOwner(response(.object([:]),[primary]))==nil)
}

#if canImport(WebKit)
import WebKit
@MainActor @Test func authenticationPresentationPreventsFocusZoomWithoutChangingFormValues() async throws {
    let config=WKWebViewConfiguration();config.websiteDataStore = .nonPersistent()
    config.userContentController.addUserScript(WKUserScript(source:SchoolWebPresentation.authentication,injectionTime:.atDocumentStart,forMainFrameOnly:true))
    let web=WKWebView(frame:.zero,configuration:config)
    for host in ["auth.sicau.edu.cn","xsgz.sicau.edu.cn"] {
        web.loadHTMLString("<html><head><meta name='viewport' content='width=980'><style>input{font-size:12px}</style></head><body><input id='account' value='SYNTHETIC'><input id='password' type='password' value='synthetic-secret'></body></html>",baseURL:URL(string:"https://\(host)/wui/")!)
        var ready=false
        for _ in 0..<100 {
            try await Task.sleep(for:.milliseconds(50))
            if !web.isLoading,(try? await web.evaluateJavaScript("!!document.getElementById('account')")) as? Bool == true {ready=true;break}
        }
        try #require(ready)
        let size=try await web.evaluateJavaScript("getComputedStyle(document.getElementById('account')).fontSize") as? String
        #expect(size==(host=="auth.sicau.edu.cn" ? "16px" : "12px"))
        #expect(try await web.evaluateJavaScript("document.getElementById('account').value") as? String == "SYNTHETIC")
        #expect(try await web.evaluateJavaScript("document.getElementById('password').value") as? String == "synthetic-secret")
        let viewport=try #require(try await web.evaluateJavaScript("document.querySelector('meta[name=viewport]').content") as? String)
        #expect(viewport==(host=="auth.sicau.edu.cn" ? "width=device-width, initial-scale=1, viewport-fit=cover" : "width=980"))
        #expect(!viewport.contains("user-scalable=no"))
    }
}
#endif
