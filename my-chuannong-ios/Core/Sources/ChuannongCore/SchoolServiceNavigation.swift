import Foundation

/// School service routing from this product's Android SchoolWebPolicy/SchoolServiceJourney.
public enum SchoolServiceNavigation {
    public static let unified = URL(string: "https://auth.sicau.edu.cn/wui/#/?appid=ywtb&service=https%3A%2F%2Fywtb.sicau.edu.cn%2Fcas%2Flogin%2Fuser&cascallback=choose")!
    public static let studentHall = URL(string: "https://xsgz.sicau.edu.cn/mobile/stuhall/studentindex")!
    public static func initial(_ target: URL, gateway: URL?) -> URL {
        if target.host=="ywtb.sicau.edu.cn",target.path=="/" {return unified}
        // The school's business pages send a missing local token through /sso/logout.
        // Start at its official mobile SSO entry to obtain a fresh service token first.
        if target.host=="xsgz.sicau.edu.cn",target.path.hasPrefix("/mobile/"),!authentication(target) {
            var destination=URLComponents(string:"https://xsgz.sicau.edu.cn/mobile/sso")!
            let redirect=String(target.path.dropFirst("/mobile".count))+(target.query.map{"?"+$0} ?? "")+(target.fragment.map{"#"+$0} ?? "")
            destination.queryItems=[URLQueryItem(name:"redirect",value:redirect)]
            return destination.url!
        }
        if ["xsgz.sicau.edu.cn","auth.sicau.edu.cn","ywtb.sicau.edu.cn","www.sicau.edu.cn"].contains(target.host) {return target}
        return gateway ?? target
    }
    public static func authentication(_ url: URL) -> Bool {
        guard SchoolURLPolicy.allows(url) else {return true}
        return url.host=="auth.sicau.edu.cn" || SchoolSSORequest(url) != nil || url.path.hasSuffix(AcademicRoute.loginPath) ||
            url.path.range(of:"(?i)/(login|cas|caslogin|sso|oauth|callback|wui)(/|\\.|$)",options:.regularExpression) != nil
    }
    public static func targetReached(_ current: URL, target: URL) -> Bool {
        guard SchoolURLPolicy.allows(current),!authentication(current) else {return false}
        if authentication(target) {return current.host==(SchoolSSORequest(target)?.service.host ?? target.host)}
        guard current.host==target.host else {return false}
        if target.path=="/" || target.path.isEmpty {return true}
        return current.path.trimmingCharacters(in:CharacterSet(charactersIn:"/"))==target.path.trimmingCharacters(in:CharacterSet(charactersIn:"/")) &&
            (target.query==nil || current.query==target.query) && (target.fragment==nil || current.fragment==target.fragment)
    }
    public static func neutralLanding(_ current: URL, target: URL) -> Bool {
        guard SchoolURLPolicy.allows(current),!authentication(current),current.host==target.host else {return false}
        return ["","/","/index.html"].contains(current.path) || current.host=="xsgz.sicau.edu.cn" && current.path==studentHall.path
    }
    public static func previousBusinessIndex(_ urls: [URL]) -> Int? {
        urls.indices.reversed().first { SchoolURLPolicy.allows(urls[$0]) && !authentication(urls[$0]) }
    }
}

public struct SchoolServiceJourney {
    public let target: URL
    public private(set) var reached = false
    private var returned = false
    public enum Step { case ready, returnToTarget, wait, failed }
    public init(target: URL) {self.target=target}
    public mutating func finished(_ current: URL) -> Step {
        if SchoolServiceNavigation.targetReached(current,target:target) {reached=true;return .ready}
        if reached || SchoolServiceNavigation.authentication(current) {return .wait}
        if SchoolServiceNavigation.neutralLanding(current,target:target) {
            guard !returned else {return .failed};returned=true;return .returnToTarget
        }
        return .wait
    }
}

public enum SchoolWebPresentation {
    // Only presentation metadata. No input values, credentials, event interception or form submission.
    // At least 16 CSS px prevents WebKit's focus zoom while preserving user pinch-to-zoom.
    public static let authentication = #"""
    (() => {
      const auth = () => location.hostname === 'auth.sicau.edu.cn' ||
        location.hostname === 'webvpn.sicau.edu.cn' && /^\/https\/[0-9a-f]{32,256}\/wui\/?$/.test(location.pathname);
      const apply = () => {
        if (!auth() || !document.head) return;
        let viewport = document.querySelector('meta[name="viewport"]');
        if (!viewport) { viewport = document.createElement('meta'); viewport.name = 'viewport'; document.head.appendChild(viewport); }
        const content = 'width=device-width, initial-scale=1, viewport-fit=cover';
        if (viewport.content !== content) viewport.content = content;
        if (!document.getElementById('chuannong-auth-layout')) {
          const style = document.createElement('style'); style.id = 'chuannong-auth-layout';
          style.textContent = 'html{-webkit-text-size-adjust:100%} input:not([type=checkbox]):not([type=radio]),select,textarea{font-size:16px!important;max-width:100%;box-sizing:border-box}';
          document.head.appendChild(style);
        }
      };
      apply(); document.addEventListener('DOMContentLoaded', apply, {once:true});
      new MutationObserver(apply).observe(document, {childList:true, subtree:true});
    })();
    """#
}
