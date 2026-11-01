import XCTest
@testable import ChuannongCore

final class QQGroupTests: XCTestCase {
    private func group(_ link: String, enabled: Bool = true, number: String = "123456789") -> QQGroupConfiguration {
        QQGroupConfiguration(.object(["enabled": .bool(enabled), "groupNumber": .string(number), "joinUrl": .string(link)]))
    }
    func testOfficialGroupLinksAndUnconfiguredState() {
        XCTAssertFalse(QQGroupConfiguration(.object(["enabled": .bool(false)])).enabled)
        for link in ["https://qm.qq.com/q/synthetic", "https://qun.qq.com/universal-share/share?key=synthetic", "mqqapi://card/show_pslcard?src_type=internal&version=1&uin=123456789&card_type=group&source=qrcode"] {
            XCTAssertEqual(group(link).joinURL?.absoluteString, link)
            XCTAssertNil(group(link, enabled: false).joinURL)
        }
    }
    func testInvalidGroupLinksNeverOpen() {
        for link in ["", "javascript:alert(1)", "https://example.invalid/q/a", "https://qm.qq.com.evil.invalid/q/a", "http://qm.qq.com/q/a", "https://qm.qq.com/q/a\nb", "https://qm.qq.com/", "https://user:pass@qm.qq.com/q/a", "https://qm.qq.com:444/q/a", "https://qm.qq.com/q/a#fragment", "mqqapi://card/show_pslcard?uin=987654321&card_type=group", "mqqapi://card/show_pslcard?uin=123456789&card_type=friend", "mqqapi://card/show_pslcard?uin=123456789&uin=987654321&card_type=group", "mqqapi://card/show_pslcard?uin=123456789&card_type=group&redirect=evil"] {
            XCTAssertNil(group(link).joinURL, link)
        }
        for number in ["", "１２３４５６", "012345", "123"] {
            XCTAssertNil(group("https://qm.qq.com/q/synthetic", number: number).joinURL)
        }
    }
}
