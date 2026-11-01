import Foundation
import Observation
import WebKit
import CryptoKit

enum CampusNetworkPhase: String { case unknown, checking, connected, notConnected }

struct SchoolAuthenticationRequest: Identifiable {
    let id = UUID()
    let page: SchoolPage
    let owner: String
}

@MainActor @Observable
final class SchoolSession {
    private(set) var identity:SchoolIdentity?
    private(set) var ssoOwner: String?
    var sessionOwner: String? { ssoOwner ?? identity?.studentID }
    private(set) var snapshot=AcademicSnapshot(owner:"")
    private(set) var route:AcademicRoute?
    private(set) var busy=false
    private(set) var restoring=true
    private(set) var network: CampusNetworkPhase = .unknown
    private(set) var resourceRoutes: [String: AcademicRoute] = [:]
    private var networkGeneration = 0
    private(set) var pendingImport: CourseBatch?
    private var academicRetryAfter = Date.distantPast
    var message:String?
    var errors:[String:String]=[:]
    var authenticationNeeded = Set<String>()
    var authenticationRequest: SchoolAuthenticationRequest?
    private(set) var dataStore=WKWebsiteDataStore.nonPersistent()
    private var authRealm:String?
    private var expiryCheckedAt=Date.distantPast
    private var checkingExpiry=false
    private var isVisualPreview=false
    var allowsPresenceReporting: Bool { !isVisualPreview }
    private var generation=0
    private var restored=false
    private var restoration:Task<Void,Never>?
    private var cookieObserver:SchoolCookieObserver?
    private var cookieSave:Task<Void,Never>?
    private var clearingCookies=false
    private let folder:URL
    private let transportConfiguration: URLSessionConfiguration
    private let loadPage: @MainActor (WKWebsiteDataStore, URL, (@MainActor (URL) async throws -> URL?)?) async throws -> SchoolDocument
    private let loadPortal: @MainActor (WKWebsiteDataStore) async throws -> SchoolDocument
    var isBound:Bool{identity != nil}
    init(loadSaved: Bool = true, transportConfiguration: URLSessionConfiguration = .ephemeral,
         loadPortal: @escaping @MainActor (WKWebsiteDataStore) async throws -> SchoolDocument = { store in
             try await SchoolPageReader(dataStore: store).readPortal()
         },
         loadPage: @escaping @MainActor (WKWebsiteDataStore, URL, (@MainActor (URL) async throws -> URL?)?) async throws -> SchoolDocument = { store, url, sso in
             try await SchoolPageReader(dataStore: store, ssoDestination: sso).read(url)
         }){
        self.transportConfiguration = transportConfiguration; self.loadPage = loadPage; self.loadPortal = loadPortal
        folder=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appending(path:"Academic",directoryHint:.isDirectory)
        guard loadSaved else { isVisualPreview=true;restoring = false; restored = true; return }
        let observer=SchoolCookieObserver{[weak self] in self?.cookiesChanged()};cookieObserver=observer;dataStore.httpCookieStore.add(observer)
        do{
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            var values=URLResourceValues();values.isExcludedFromBackup=true;var directory=folder;try directory.setResourceValues(values)
            if let data=try SecureStore.read("identity",realm:"school"){identity=try JSONDecoder().decode(SchoolIdentity.self,from:data)}
            if let data=try SecureStore.read("ssoOwner",realm:"school"),let owner=String(data:data,encoding:.utf8),SchoolSSOEnvelope.validOwner(owner){ssoOwner=owner}
            if let data=try SecureStore.read("route",realm:"school"){route=try JSONDecoder().decode(AcademicRoute.self,from:data)}
            if let data=try SecureStore.read("resources",realm:"school"){resourceRoutes=(try? JSONDecoder().decode([String:AcademicRoute].self,from:data)) ?? [:]}
            if let data=try SecureStore.read("authRealm",realm:"school"),let value=String(data:data,encoding:.utf8),SchoolSSORequest.validProxyRealm(value){authRealm=value}
            if let identity{snapshot=load(owner:identity.studentID)}
        }catch{message=error.localizedDescription}
    }
    func restore() async {
        guard !restored else{return}
        if let restoration{await restoration.value;return}
        let epoch=generation
        let task=Task { @MainActor in
            defer {if epoch==generation{restored=true;restoring=false}}
            do {
                if let data=try SecureStore.read("cookies",realm:"school") {
                    let live=await dataStore.httpCookieStore.allCookies()
                    let keys=Set(live.map{[$0.domain,$0.path,$0.name].joined(separator:"\u{001f}")})
                    for cookie in try SchoolCookieSnapshot.decode(data) {
                        guard epoch==generation,!clearingCookies else{return}
                        if !keys.contains([cookie.domain,cookie.path,cookie.name].joined(separator:"\u{001f}")){await dataStore.httpCookieStore.setCookie(cookie)}
                    }
                }
            }catch{if epoch==generation{message=error.localizedDescription}}
        }
        restoration=task;await task.value;restoration=nil
    }
    func persistCookies() async throws {
        guard !isVisualPreview,restored,!clearingCookies else{return};let epoch=generation
        let cookies=await dataStore.httpCookieStore.allCookies()
        guard epoch==generation,!clearingCookies else{return}
        try SecureStore.write(SchoolCookieSnapshot.encode(cookies),key:"cookies",realm:"school")
    }
    private func cookiesChanged() {
        guard restored,!clearingCookies else{return};let epoch=generation
        cookieSave?.cancel();cookieSave=Task { do {try await Task.sleep(for:.milliseconds(250));guard epoch==generation else{return};try await persistCookies()}catch{} }
    }
    func observe(_ document: SchoolDocument) async {
        guard !isVisualPreview,let current=URL(string:document.url),SchoolURLPolicy.allows(current) else{return}
        if let realm=SchoolSSORequest.vpnRealm(current){authRealm=realm;try? SecureStore.write(Data(realm.utf8),key:"authRealm",realm:"school")}
        let hosts:Set<String>=["ehall.sicau.edu.cn","jiaowu.sicau.edu.cn","op.sicau.edu.cn","ywtb.sicau.edu.cn","xsgz.sicau.edu.cn","auth.sicau.edu.cn"]
        if current.host=="webvpn.sicau.edu.cn",["/","/portal","/m/portal"].contains(current.path) {
            for link in document.links {
                let labels=Set(link.label.split(whereSeparator:\.isWhitespace).map(String.init))
                let matches=hosts.intersection(labels)
                guard matches.count==1, let host=matches.first,let url=URL(string:link.href),let discovered=AcademicRoute(resourceURL:url) else {continue}
                resourceRoutes[host]=discovered
                if host=="jiaowu.sicau.edu.cn"{route=discovered}
            }
            try? SecureStore.write(JSONEncoder().encode(resourceRoutes),key:"resources",realm:"school")
        }
        if current.path.hasSuffix(AcademicRoute.loginPath),document.academicLogin == true || document.academicUnifiedLogin == true,let discovered=AcademicRoute(resourceURL:current){route=discovered;resourceRoutes["jiaowu.sicau.edu.cn"]=discovered}
        if let route{try? SecureStore.write(JSONEncoder().encode(route),key:"route",realm:"school")}
    }
    func resolved(_ direct:URL)->URL? {
        guard SchoolURLPolicy.allows(direct),let host=direct.host,let mapped=resourceRoutes[host] else{return nil}
        let c=URLComponents(url:direct,resolvingAgainstBaseURL:false)!
        return URL(string:"https://webvpn.sicau.edu.cn"+mapped.prefix+c.percentEncodedPath+(c.percentEncodedQuery.map{"?"+$0} ?? "")+(c.percentEncodedFragment.map{"#"+$0} ?? ""))
    }
    func canonicalSchoolURL(_ url: URL) -> URL {
        guard url.host=="webvpn.sicau.edu.cn",let components=URLComponents(url:url,resolvingAgainstBaseURL:false) else {return url}
        for (host,route) in resourceRoutes where route.contains(url) {
            var canonical=URLComponents();canonical.scheme="https";canonical.host=host
            canonical.percentEncodedPath=String(components.percentEncodedPath.dropFirst(route.prefix.count))
            canonical.percentEncodedQuery=components.percentEncodedQuery;canonical.percentEncodedFragment=components.percentEncodedFragment
            return canonical.url ?? url
        }
        return url
    }
    func checkNetwork() async {
        guard !isVisualPreview else{return};await restore();networkGeneration+=1;let epoch=networkGeneration;let sessionEpoch=generation;network = .checking
        do {
            var portal = try await loadPortal(dataStore)
            try Task.checkCancellation(); guard epoch == networkGeneration, sessionEpoch == generation else { return }
            if !Self.connectedPortal(portal), let owner = sessionOwner {
                // Reconnect VPN through the same existing 川农 e identity. No password
                // submission and no assumption about the academic page's login state.
                if try await broker(owner: owner).restoreVPN(owner: owner, proxy: authRealm) {
                    portal = try await loadPortal(dataStore)
                }
            }
            try Task.checkCancellation();guard epoch==networkGeneration, sessionEpoch==generation else{return}
            guard Self.connectedPortal(portal) else {
                network = .notConnected; message = nil; return
            }
            await observe(portal)
            try await persistCookies();network = .connected;message=nil
        } catch is CancellationError {if epoch==networkGeneration{network = .unknown}}
        catch {if epoch==networkGeneration{network = .unknown;message="检测未完成，请检查网络后重试"}}
    }
    private static func connectedPortal(_ document: SchoolDocument) -> Bool {
        guard let url = URL(string: document.url), SchoolURLPolicy.allows(url),
              url.host == "webvpn.sicau.edu.cn", ["/", "/portal", "/m/portal"].contains(url.path),
              !document.authenticationRequired, document.challengeRequired != true else { return false }
        return document.links.contains { link in
            link.label.split(whereSeparator: \.isWhitespace).contains("jiaowu.sicau.edu.cn") &&
                URL(string: link.href).flatMap(AcademicRoute.init(resourceURL:)) != nil
        }
    }
    func authenticateAcademicUnified() async throws {
        guard !isVisualPreview, !busy, let route, network == .connected else { throw SchoolFailure.vpn }
        busy = true; defer { busy = false }; let epoch = generation
        guard let owner = try await confirmUnifiedSession() else { throw SchoolFailure.unifiedAuthentication }
        let verified = try await restoreAcademicSession(route: route, owner: owner)
        guard epoch == generation else { throw CancellationError() }
        try await storeBinding(verified, route: route)
    }
    func savedCredential() throws -> SchoolCredential? {
        guard !isVisualPreview, let data = try SecureStore.read("unifiedCredential", realm: "school") else { return nil }
        let credential = try JSONDecoder().decode(SchoolCredential.self, from: data)
        return credential.belongs(to: sessionOwner) ? credential : nil
    }
    func authenticationChallenge() async throws -> SchoolChallenge {
        guard !isVisualPreview else { throw SchoolFailure.cancelled }
        await restore(); let epoch = generation
        return try await SchoolSSOBroker(store: dataStore.httpCookieStore, configuration: transportConfiguration) { [weak self] in
            self?.generation == epoch && self?.clearingCookies == false
        }.challenge()
    }
    func authenticateUnified(_ credential: SchoolCredential, code: String, challenge: SchoolChallenge) async throws {
        guard !isVisualPreview, !busy else { throw SchoolFailure.cancelled }
        guard sessionOwner == nil || sessionOwner == credential.account else { throw SchoolFailure.changed }
        busy = true; defer { busy = false }; let epoch = generation
        await restore()
        let auth = SchoolSSOBroker(store: dataStore.httpCookieStore, configuration: transportConfiguration) { [weak self] in
            self?.generation == epoch && self?.clearingCookies == false
        }
        do { try await auth.login(credential, code: code, challenge: challenge) }
        catch {
            if epoch == generation, SchoolFailure.reason(error) == .credentials {
                try SecureStore.write(nil, key: "unifiedCredential", realm: "school")
            }
            throw error
        }
        try Task.checkCancellation(); guard epoch == generation else { throw CancellationError() }
        try SecureStore.write(JSONEncoder().encode(credential), key: "unifiedCredential", realm: "school")
        try SecureStore.write(Data(credential.account.utf8), key: "ssoOwner", realm: "school")
        ssoOwner = credential.account
        try await persistCookies()
        guard try await auth.restoreVPN(owner: credential.account, proxy: authRealm) else { throw SchoolFailure.vpn }
        let portal = try await loadPortal(dataStore)
        guard epoch == generation else { throw CancellationError() }
        await observe(portal)
        guard let route else { throw SchoolFailure.vpn }
        network = .connected
        let verified = try await restoreAcademicSession(route: route, owner: credential.account)
        guard epoch == generation else { throw CancellationError() }
        try await storeBinding(verified, route: route)
    }
    private func restoreAcademicSession(route: AcademicRoute, owner: String) async throws -> SchoolIdentity {
        let epoch = generation
        _ = try await loadPage(dataStore, route.url(path: AcademicRoute.unifiedLoginPath), { [weak self] url in
            guard let self, self.generation == epoch, self.sessionOwner == owner else { throw CancellationError() }
            return try await self.ssoDestination(url)
        })
        let verified: SchoolIdentity
        do { verified = try SchoolParser.identity(await read(route.url(path: SchoolPage.identity.path))) }
        catch where [.expired, .vpn].contains(SchoolFailure.reason(error) ?? .structure) { throw SchoolFailure.unifiedAuthentication }
        guard epoch == generation else { throw CancellationError() }
        guard verified.studentID == owner, sessionOwner == owner else { throw SchoolFailure.changed }
        try await persistCookies()
        return verified
    }
    private func storeBinding(_ verified: SchoolIdentity, route: AcademicRoute) async throws {
        let epoch = generation
        try await persistCookies()
        try Task.checkCancellation()
        guard epoch == generation, self.route == route, sessionOwner == verified.studentID else { throw SchoolFailure.changed }
        // School no longer accepts a separate academic password. Remove any obsolete saved one.
        try SecureStore.write(nil, key: "academicCredential", realm: "school")
        try SecureStore.write(JSONEncoder().encode(route), key: "route", realm: "school")
        try SecureStore.write(JSONEncoder().encode(verified), key: "identity", realm: "school")
        identity = verified; snapshot = load(owner: verified.studentID); academicRetryAfter = .distantPast
        pendingImport = nil; message = nil; errors = [:]; authenticationNeeded = []; reschedule()
    }
    func academicWebEntry() async throws -> URL {
        guard !isVisualPreview, let identity, let route else { throw SchoolFailure.identity }
        while busy { try await Task.sleep(for: .milliseconds(100)) }
        try Task.checkCancellation()
        guard self.identity?.studentID == identity.studentID, self.route == route else { throw SchoolFailure.changed }
        busy = true; defer { busy = false }; let epoch = generation
        await restore()
        _ = try await verifiedIdentity(route: route, owner: identity.studentID)
        guard epoch == generation, self.identity?.studentID == identity.studentID else { throw CancellationError() }
        try await persistCookies()
        return route.url(path: SchoolPage.identity.path)
    }
    func verifyBinding(expected:String?=nil) async throws{
        guard !isVisualPreview,!busy,let route else{throw SchoolFailure.vpn};busy=true;defer{busy=false};let epoch=generation
        guard let owner = try await confirmUnifiedSession() else { throw SchoolFailure.unifiedAuthentication }
        let document=try await read(route.url(path:SchoolPage.identity.path))
        let verified=try SchoolParser.identity(document)
        if let expected,verified.studentID != expected{throw SchoolFailure.changed}
        guard owner == verified.studentID else {throw SchoolFailure.changed}
        guard epoch==generation else{throw CancellationError()}
        try await storeBinding(verified, route: route)
    }
    func syncAfterBinding() async {
        guard !isVisualPreview,let owner=identity?.studentID else{return}
        for page in [SchoolPage.courses,.grades,.exams] {
            // Initial data belongs to the signed-in foreground session, not the
            // binding screen. Wait for authentication or a manual refresh rather
            // than silently skipping a page while another school request is busy.
            while busy {
                guard !Task.isCancelled,identity?.studentID==owner else{return}
                do { try await Task.sleep(for:.milliseconds(100)) } catch { return }
            }
            guard !Task.isCancelled,identity?.studentID==owner else{return}
            if snapshot.updated[page.rawValue]==nil{await sync(page, interactive: false)}
            if authenticationNeeded.contains(page.rawValue) { return }
        }
    }
    func sync(_ page:SchoolPage, interactive: Bool = true) async{
        guard !isVisualPreview,!busy,let identity,let route else{return};busy=true;defer{busy=false};let epoch=generation
        do{
            let proof=try await verifiedIdentity(route:route,owner:identity.studentID)
            guard proof.studentID==identity.studentID else{throw SchoolFailure.changed}
            let document=try await read(route.url(path:page == .grades ? "/xuesheng/chengji/chengji/bchengjike.asp" : page.path))
            guard epoch==generation else{throw CancellationError()}
            var next=snapshot
            switch page{
            case .courses:
                let batch=try SchoolParser.courses(document)
                next.receive(batch)
                if next.termStarts[batch.term]==nil,let first=BundledAcademic.firstMonday(batch.term,snapshot:next){next.termStarts[batch.term]=first}
            case .grades:
                var transcript=try TranscriptParser.transcript(document,owner:identity.studentID)
                do { transcript.ranking=try TranscriptParser.ranking(await read(route.url(path:"/xuesheng/chengji/chengji/zytongbf.asp")),owner:identity.studentID); errors["ranking"]=nil }
                catch is CancellationError {throw CancellationError()}
                catch {
                    errors["ranking"]=error.localizedDescription
                    if snapshot.transcript != nil { throw APIError.server(422,"排名获取未完成，已保留上次完整成绩数据") }
                }
                next.transcript=transcript;next.grades=transcript.courses;next.updated[page.rawValue] = .now
            case .exams:next.exams=try SchoolParser.exams(document);next.updated[page.rawValue] = .now
            case .identity:break
            }
            guard epoch==generation,identity.studentID==self.identity?.studentID else{throw CancellationError()}
            try save(next);snapshot=next;network = .connected;errors[page.rawValue]=nil;authenticationNeeded.remove(page.rawValue);if page == .courses{reschedule()};try await persistCookies()
        } catch is CancellationError {} catch {
            if epoch == generation {
                errors[page.rawValue] = error.localizedDescription
                if SchoolAuthentication.requiresAuthentication(error) {
                    authenticationNeeded.insert(page.rawValue)
                    if interactive { authenticationRequest = SchoolAuthenticationRequest(page: page, owner: identity.studentID) }
                } else { authenticationNeeded.remove(page.rawValue) }
            }
        }
    }
    func resumeRefresh(_ request: SchoolAuthenticationRequest) async throws {
        while busy { try await Task.sleep(for: .milliseconds(100)) }
        try Task.checkCancellation()
        guard identity?.studentID == request.owner else { throw SchoolFailure.changed }
        await sync(request.page, interactive: false)
    }
    private func verifiedIdentity(route: AcademicRoute, owner: String) async throws -> SchoolIdentity {
        let epoch = generation
        do {
            let proof = try await readIdentity(route: route, owner: owner)
            guard proof.studentID == owner else { throw SchoolFailure.changed }
            guard epoch == generation, let current = identity, current.studentID == owner else { throw CancellationError() }
            var updated = proof; updated.verifiedAt = current.verifiedAt
            if updated != current { try SecureStore.write(JSONEncoder().encode(updated), key: "identity", realm: "school"); identity = updated }
            return proof
        } catch where SchoolAuthentication.canRecover(error) {
            guard Date.now >= academicRetryAfter else { throw SchoolFailure.autoLoginCooldown }
            guard epoch == generation, identity?.studentID == owner else { throw CancellationError() }
            academicRetryAfter = Date.now.addingTimeInterval(60)
            let proof: SchoolIdentity
            do { proof = try await restoreAcademicSession(route: route, owner: owner) }
            catch {
                // An expired VPN/CAS session must continue directly into authentication.
                // The school currently requires a fresh user-completed captcha for password login.
                academicRetryAfter = .distantPast
                throw error
            }
            guard epoch == generation, identity?.studentID == owner else { throw CancellationError() }
            try SecureStore.write(nil, key: "academicCredential", realm: "school")
            guard epoch == generation, let current = identity, current.studentID == owner else { throw CancellationError() }
            var updated = proof; updated.verifiedAt = current.verifiedAt
            if updated != current { try SecureStore.write(JSONEncoder().encode(updated), key: "identity", realm: "school"); identity = updated }
            return proof
        }
    }
    private func broker(owner:String)->SchoolSSOBroker {
        let epoch=generation
        return SchoolSSOBroker(store:dataStore.httpCookieStore, configuration: transportConfiguration){[weak self] in guard let self else{return false};return epoch==self.generation && self.sessionOwner==owner && !self.clearingCookies}
    }
    @discardableResult func confirmUnifiedSession() async throws -> String? {
        guard !isVisualPreview else { return nil }; await restore(); let epoch=generation
        let broker=SchoolSSOBroker(store:dataStore.httpCookieStore, configuration: transportConfiguration){[weak self] in self?.generation==epoch && self?.clearingCookies==false}
        if authRealm==nil,let discovered=try? await broker.discoverProxy(){authRealm=discovered;try SecureStore.write(Data(discovered.utf8),key:"authRealm",realm:"school")}
        guard let owner=try await broker.authenticatedOwner(proxy:authRealm,expected:sessionOwner) else { return nil }
        guard epoch==generation else {throw CancellationError()}
        try SecureStore.write(Data(owner.utf8),key:"ssoOwner",realm:"school");ssoOwner=owner
        try await persistCookies();return owner
    }
    func ssoDestination(_ url:URL) async throws->URL? {
        guard !isVisualPreview,let request=SchoolSSORequest(url) else{return nil}
        await restore()
        if sessionOwner==nil {_ = try await confirmUnifiedSession()}
        guard let owner=sessionOwner else{return nil}
        let broker=broker(owner:owner)
        if authRealm==nil,let discovered=try? await broker.discoverProxy(){authRealm=discovered;try SecureStore.write(Data(discovered.utf8),key:"authRealm",realm:"school")}
        let result=try await broker.callback(request,owner:owner,proxy:authRealm)
        try await persistCookies()
        if let result, request.service.host == "jiaowu.sicau.edu.cn" {
            guard let routed = resolved(result), route?.contains(routed) == true else { throw SchoolFailure.vpn }
            return routed
        }
        return result
    }
    func checkSessionExpiry() async {
        guard !isVisualPreview,!checkingExpiry,!busy,let owner=sessionOwner,Date.now.timeIntervalSince(expiryCheckedAt)>=60 else{return}
        await restore();checkingExpiry=true;expiryCheckedAt = .now;defer{checkingExpiry=false}
        do{if try await broker(owner:owner).checkNearExpiry(owner:owner,proxy:authRealm){try await persistCookies()}}
        catch is CancellationError{}catch{} // A failed check is not proof of logout; retain all current sessions.
    }
    private func readIdentity(route:AcademicRoute,owner:String) async throws->SchoolIdentity {
        do{return try SchoolParser.identity(await read(route.url(path:SchoolPage.identity.path)))}
        catch let error as SchoolFailure where error == .vpn {
            let broker=broker(owner:owner)
            if authRealm==nil,let discovered=try? await broker.discoverProxy(){authRealm=discovered;try SecureStore.write(Data(discovered.utf8),key:"authRealm",realm:"school")}
            guard try await broker.restoreVPN(owner:owner,proxy:authRealm) else{throw error}
            try await persistCookies()
            return try SchoolParser.identity(await read(route.url(path:SchoolPage.identity.path)))
        }
    }
    func cancelImport(){pendingImport=nil}
    func stageTimetable(_ document:SchoolDocument) async throws {
        guard !busy,let identity,let route,let url=URL(string:document.url),route.contains(url) else{throw SchoolFailure.identity}
        busy=true;defer{busy=false};let epoch=generation
        _ = try await verifiedIdentity(route:route,owner:identity.studentID)
        let batch=try TimetableImportParser.parse(document)
        guard epoch==generation else{throw CancellationError()};pendingImport=batch
    }
    func importCourses(_ batch:CourseBatch) throws {
        guard isBound,let pendingImport,pendingImport.term==batch.term || TimetableRules.validTerm(batch.term) else{throw SchoolFailure.identity}
        guard TimetableRules.validTerm(batch.term),batch.courses.allSatisfy({$0.term==batch.term && (try? $0.validate()) != nil}) else{throw SchoolFailure.time}
        var next=snapshot;next.receive(batch,reviewedImport:true)
        if next.termStarts[batch.term]==nil,let first=BundledAcademic.firstMonday(batch.term,snapshot:next){next.termStarts[batch.term]=first}
        try save(next);snapshot=next;self.pendingImport=nil;reschedule()
    }
    func saveCourse(_ course:Course) throws{try course.validate();guard isBound,course.source=="MANUAL",!snapshot.courses.contains(where:{$0.id==course.id && $0.source != "MANUAL"}) else{throw SchoolFailure.identity};var next=snapshot;next.courses.removeAll{$0.id==course.id};next.courses.append(course);if next.term.isEmpty{next.term=course.term};try save(next);snapshot=next;reschedule()}
    func removeCourse(_ course:Course) throws{guard course.source == "MANUAL" else{return};var next=snapshot;next.courses.removeAll{$0.id==course.id};try save(next);snapshot=next;reschedule()}
    func setTermStart(_ date:Date,term:String) throws{guard TimetableRules.validTerm(term) else{throw SchoolFailure.time};var next=snapshot;next.termStarts[term]=date;try save(next);snapshot=next;reschedule()}
    func setAdmissionYear(_ year:Int) throws{guard isBound,(2000...AcademicCalendarRules.calendar.component(.year,from:.now)).contains(year) else{throw SchoolFailure.identity};var next=snapshot;next.admissionYear=year;try save(next);snapshot=next}
    func forget() async throws{
        guard !isVisualPreview else{return}
        generation+=1;clearingCookies=true;academicRetryAfter = .distantPast;cookieSave?.cancel();restoration?.cancel();defer{clearingCookies=false;restored=true;restoring=false}
        networkGeneration+=1;network = .unknown;resourceRoutes=[:]
        authenticationRequest = nil
        for key in ["identity","ssoOwner","route","cookies","resources","academicCredential","unifiedCredential","authRealm"]{try SecureStore.write(nil,key:key,realm:"school")}
        for cookie in await dataStore.httpCookieStore.allCookies(){await dataStore.httpCookieStore.deleteCookie(cookie)}
        await dataStore.removeData(ofTypes:WKWebsiteDataStore.allWebsiteDataTypes(),modifiedSince:.distantPast)
        if let cookieObserver{dataStore.httpCookieStore.remove(cookieObserver)}
        dataStore=WKWebsiteDataStore.nonPersistent();if let cookieObserver{dataStore.httpCookieStore.add(cookieObserver)};authRealm=nil
        identity=nil;ssoOwner=nil;route=nil;snapshot=AcademicSnapshot(owner:"");pendingImport=nil;message=nil;errors=[:];authenticationNeeded=[];reschedule()
    }
    func clearLearningCaches() throws {
        guard !isVisualPreview else{return}
        generation += 1
        let files = (try? FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil)) ?? []
        for url in files where url.pathExtension == "json" {
            guard let data=try? Data(contentsOf:url),let old=try? JSONDecoder().decode(AcademicSnapshot.self,from:data),file(owner:old.owner)==url else{continue}
            var empty=AcademicSnapshot(owner:old.owner);empty.admissionYear=old.admissionYear
            try save(empty)
        }
        var empty=AcademicSnapshot(owner:identity?.studentID ?? "");empty.admissionYear=snapshot.admissionYear
        snapshot=empty;pendingImport=nil;errors=[:];authenticationNeeded=[];reschedule()
    }
    func clearCurrentData() throws{guard let identity else{return};let next=AcademicSnapshot(owner:identity.studentID);try save(next);snapshot=next;reschedule()}
    private func reschedule(){guard !isVisualPreview else{return};let current=snapshot;try? SchoolWidgets.update(current);Task{_ = try? await CourseNotifications.rebuild(current)}}
    private func file(owner:String)->URL{let digest=SHA256.hash(data:Data(owner.utf8)).map{String(format:"%02x",$0)}.joined();return folder.appending(path:digest+".json")}
    private func load(owner:String)->AcademicSnapshot{guard let data=try? Data(contentsOf:file(owner:owner)),let value=try? JSONDecoder().decode(AcademicSnapshot.self,from:data),value.owner==owner else{return AcademicSnapshot(owner:owner)};return value}
    private func save(_ value:AcademicSnapshot)throws{guard !isVisualPreview else{return};guard !value.owner.isEmpty else{throw SchoolFailure.identity};try JSONEncoder().encode(value).write(to:file(owner:value.owner),options:[.atomic,.completeFileProtection])}
    private func read(_ url:URL) async throws->SchoolDocument{
        guard !isVisualPreview else{throw SchoolFailure.cancelled};await restore()
        let document=try await loadPage(dataStore,url,nil)
        guard let final=URL(string:document.url) else{throw SchoolFailure.structure}
        if SchoolSSORequest(final) != nil || final.host=="auth.sicau.edu.cn" || (final.host=="webvpn.sicau.edu.cn" && ["/","/login","/wui","/wui/","/portal","/m/portal"].contains(final.path)) {throw SchoolFailure.vpn}
        if document.authenticationRequired && document.academicLogin == true && !url.path.hasSuffix(AcademicRoute.loginPath){throw SchoolFailure.expired}
        guard final.host==url.host,final.path==url.path else {throw SchoolFailure.structure}
        return document
    }
}

@MainActor final class SchoolPageReader:NSObject,WKNavigationDelegate,WKUIDelegate{
    let web:WKWebView
    private var continuation:CheckedContinuation<SchoolDocument,Error>?
    private var timeout:Task<Void,Never>?
    private let ssoDestination: (@MainActor (URL) async throws -> URL?)?
    private var ssoTask: Task<Void, Never>?
    private var ssoAttempts = Set<String>()
    private var redirectingSSO = false
    init(dataStore:WKWebsiteDataStore, ssoDestination: (@MainActor (URL) async throws -> URL?)? = nil){self.ssoDestination=ssoDestination;let c=WKWebViewConfiguration();c.websiteDataStore=dataStore;web=WKWebView(frame:.zero,configuration:c);super.init();web.navigationDelegate=self;web.uiDelegate=self}
    func webView(_ webView:WKWebView,runJavaScriptAlertPanelWithMessage message:String,initiatedByFrame frame:WKFrameInfo,completionHandler:@escaping @MainActor @Sendable ()->Void){
        completionHandler()
        finish(.failure(SchoolLoginIssue(message: message, sensitiveValues: [])))
    }
    func read(_ url:URL) async throws->SchoolDocument{
        guard SchoolURLPolicy.allows(url) else{throw SchoolFailure.structure}
        return try await withTaskCancellationHandler{
            try await withCheckedThrowingContinuation{continuation in
                self.continuation=continuation
                timeout=Task{try? await Task.sleep(for:.seconds(25));guard !Task.isCancelled else{return};finish(.failure(URLError(.timedOut)))}
                web.load(URLRequest(url:url))
            }
        }onCancel:{Task{@MainActor in self.finish(.failure(CancellationError()))}}
    }
    func webView(_ webView:WKWebView,decidePolicyFor navigationAction:WKNavigationAction,decisionHandler:@escaping @MainActor @Sendable (WKNavigationActionPolicy)->Void){
        guard let url=navigationAction.request.url,SchoolURLPolicy.allows(url) else{decisionHandler(.cancel);finish(.failure(SchoolFailure.structure));return}
        if navigationAction.targetFrame?.isMainFrame != false, navigationAction.request.httpMethod == "GET", let ssoDestination, let request = SchoolSSORequest(url) {
            redirectingSSO = true
            decisionHandler(.cancel)
            guard ssoAttempts.count < 3, ssoAttempts.insert(request.attemptKey).inserted else { finish(.failure(SchoolFailure.unifiedAuthentication)); return }
            ssoTask = Task {
                do {
                    guard let destination = try await ssoDestination(url) else { throw SchoolFailure.unifiedAuthentication }
                    try Task.checkCancellation()
                    guard continuation != nil, SchoolURLPolicy.allows(destination) else { return }
                    webView.load(URLRequest(url: destination))
                } catch { finish(.failure(error)) }
            }
            return
        }
        decisionHandler(.allow)
    }
    func webView(_ webView:WKWebView,didFinish navigation:WKNavigation!){let url=webView.url;Task{do{let page=try await Self.document(webView);guard webView.url==url else{return};finish(.success(page))}catch{if webView.url==url{finish(.failure(error))}}}}
    func webView(_ webView:WKWebView,didFail navigation:WKNavigation!,withError error:Error){navigationFailed(error)}
    func webView(_ webView:WKWebView,didFailProvisionalNavigation navigation:WKNavigation!,withError error:Error){navigationFailed(error)}
    private func navigationFailed(_ error: Error) {
        let ns = error as NSError
        // WebKit reports our deliberate CAS interception as a policy interruption (102).
        // Only suppress that interruption while this reader is completing the same SSO request.
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return }
        if redirectingSSO && ns.domain == "WebKitErrorDomain" && ns.code == 102 { return }
        finish(.failure(error))
    }
    private func finish(_ result:Result<SchoolDocument,Error>){guard let continuation else{return};self.continuation=nil;timeout?.cancel();timeout=nil;ssoTask?.cancel();ssoTask=nil;redirectingSSO=false;web.stopLoading();continuation.resume(with:result)}
    func readPortal() async throws -> SchoolDocument {
        var document=try await read(AcademicRoute.portal)
        for _ in 0..<6 {
            if document.authenticationRequired || document.links.contains(where:{$0.label.contains("jiaowu.sicau.edu.cn")}){return document}
            try await Task.sleep(for:.seconds(1));document=try await Self.document(web)
        }
        return document
    }
    static func document(_ web:WKWebView) async throws->SchoolDocument{
        guard let url=web.url,SchoolURLPolicy.allows(url) else{throw SchoolFailure.structure}
        // Only rendered text/links and boolean field presence; never input values or passwords.
        let script = #"""
        (()=>{
          let seen=0;const base=location.origin,prefix=(location.pathname.match(/^\/(?:https|http)(?:-[0-9]+)?\/[0-9a-f]{32,256}\//)||[])[0];
          function scan(w,depth){
            if(depth>6||++seen>60)return null;
            try{
              if(w.location.origin!==base || (prefix && !w.location.pathname.startsWith(prefix)))return null;
              const d=w.document;
              const tables=Array.from(d.querySelectorAll('table')).map(t=>Array.from(t.querySelectorAll('tr')).filter(r=>r.closest('table')===t).map(r=>Array.from(r.children).filter(c=>['TD','TH'].includes(c.tagName)).flatMap(c=>{
                const value=c.innerText.trim();const span=Number(c.getAttribute('colspan')||1);
                return !value && span>1 && span<40 ? Array(span).fill('') : [value];
              })));
              const rowspans=Array.from(d.querySelectorAll('table')).map(t=>Array.from(t.querySelectorAll('tr')).filter(r=>r.closest('table')===t).map(r=>Array.from(r.children).some(c=>Number(c.getAttribute('rowspan')||1)>1)));
              const blocks=Array.from(d.querySelectorAll('td,th,p,div,span,font')).filter(e=>!Array.from(e.children).some(c=>['TABLE','DIV','P'].includes(c.tagName))).map(e=>(e.innerText||'').trim()).filter(Boolean);
              const frames=[];for(let i=0;i<w.frames.length;i++){const frame=scan(w.frames[i],depth+1);if(frame)frames.push(frame)}
              return {url:w.location.href,text:d.body?.innerText||'',authenticationRequired:!!d.querySelector('input[type=password],input[name=hour_key]'),redirected:!!d.querySelector('meta[http-equiv=refresh]'),academicUnifiedLogin:Array.from(d.querySelectorAll('a,button,input[type=button]')).some(e=>[e.getAttribute('href'),e.getAttribute('onclick')].some(v=>v&&v.includes('/jiaoshi/aspsso/caslogin.asp'))),academicLogin:!!d.querySelector('input[name=sign]')&&!!d.querySelector('input[name=hour_key]')&&!!d.querySelector('input[name=pwd]'),challengeRequired:Array.from(d.querySelectorAll('input:not([type=hidden])')).some(e=>/captcha|verifycode|checkcode|vcode|one-time-code|验证码/i.test([e.name,e.id,e.autocomplete,e.placeholder].join(' '))),tables,rowspans,blocks,links:Array.from(d.querySelectorAll('a[href]')).map(a=>({label:a.innerText,href:a.href})),frames};
            }catch(_){return null}
          }
          return JSON.stringify(scan(window,0));
        })()
        """#
        guard let text=try await web.evaluateJavaScript(script) as? String,let data=text.data(using:.utf8),data.count<4_000_000,web.url==url else{throw SchoolFailure.structure}
        return try JSONDecoder().decode(SchoolDocument.self,from:data)
    }
}

@MainActor private final class SchoolCookieObserver:NSObject,WKHTTPCookieStoreObserver {
    let changed:@MainActor ()->Void
    init(_ changed:@escaping @MainActor ()->Void){self.changed=changed}
    nonisolated func cookiesDidChange(in cookieStore:WKHTTPCookieStore){Task{@MainActor [weak self] in self?.changed()}}
}
