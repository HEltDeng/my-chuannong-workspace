#if canImport(WebKit)
import Foundation
import Testing
import WebKit
@testable import ChuannongCore

@MainActor @Test func academicFormAlwaysSubmitsOneStudentCategory() async throws {
    // Exercise real WebKit form serialization, including the unchecked radio
    // that caused "登录类别错误" in the native iOS login flow.
    let categories = [
        "<input type='radio' name='lb' value='T' checked><input type='radio' name='lb' value='S'>",
        "<select name='lb'><option value='T'>教师</option><option value='S'>学生</option></select>",
        "<input type='checkbox' name='lb' value='S'>",
        ""
    ]
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    let web = WKWebView(frame: .zero, configuration: configuration)
    let base = URL(string: "https://webvpn.sicau.edu.cn/https/0123456789abcdef0123456789abcdef/web/web/web/index.asp")!
    let destination = "https://webvpn.sicau.edu.cn/https/0123456789abcdef0123456789abcdef/jiaoshi/bangong/check.asp"
    for category in categories {
        web.loadHTMLString("<html><body><form action='http://jiaowu.sicau.edu.cn/jiaoshi/bangong/check.asp' accept-charset='GBK'><input name='user'><input name='pwd' type='password'><input name='hour_key' value='fixture-hour'><input name='sign' value='fixture-sign'>\(category)<input type='submit' name='submit'></form></body></html>", baseURL: base)
        var ready = false
        for _ in 0..<100 {
            try await Task.sleep(for: .milliseconds(50))
            if !web.isLoading, (try? await web.evaluateJavaScript("!!document.querySelector('[name=hour_key]')")) as? Bool == true { ready = true; break }
        }
        try #require(ready)
        _ = try await web.evaluateJavaScript("HTMLFormElement.prototype.submit = function() { window.submitted = Array.from(new FormData(this).entries()); window.charset = this.acceptCharset; window.targetAction = this.action; }; true;")
        let accepted = try await web.callAsyncJavaScript(SchoolLoginForm.submission, arguments: ["account": "TEST20260001", "secret": "synthetic+&密码", "destination": destination], in: nil, contentWorld: .page)
        #expect(accepted as? Bool == true)
        let entries = try #require(try await web.evaluateJavaScript("window.submitted") as? [[String]])
        #expect(entries.count == 6)
        #expect(entries.filter { $0.first == "lb" } == [["lb", "S"]])
        #expect(entries.contains(["pwd", "synthetic+&密码"]))
        #expect(entries.contains(["submit", ""]))
        #expect(entries.contains(["sign", "fixture-sign"]))
        #expect(entries.contains(["hour_key", "fixture-hour"]))
        #expect(try await web.evaluateJavaScript("window.charset") as? String == "GBK")
        #expect(try await web.evaluateJavaScript("window.targetAction") as? String == destination)
        let rejected = try await web.callAsyncJavaScript(SchoolLoginForm.submission, arguments: ["account": "TEST20260001", "secret": "synthetic", "destination": "https://example.invalid/jiaoshi/bangong/check.asp"], in: nil, contentWorld: .page)
        #expect(rejected as? Bool == false)
    }
}
#endif
