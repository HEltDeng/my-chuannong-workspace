import XCTest
@testable import ChuannongCore

final class PhoneAccountTests: XCTestCase {
    func testPurposeAndPasswordRules() {
        XCTAssertEqual(PhoneAccountMode.verify.purpose,"verify_phone")
        XCTAssertFalse(PhoneAccountRules.validCode("１２３４５６"))
        XCTAssertFalse(PhoneAccountRules.validCode("12345"))
        XCTAssertTrue(PhoneAccountRules.validCode("012345"))
        XCTAssertFalse(PhoneAccountRules.validConfirmation(password:"pass1234",confirmation:"pass1235"))
        XCTAssertTrue(PhoneAccountRules.validConfirmation(password:"pass1234",confirmation:"pass1234"))
    }
    func testLegacyAccountDecodeAndNewCapabilitiesContract() throws {
        let user=try JSONDecoder().decode(AuthUser.self,from:Data(#"{"id":"synthetic","nickname":"测试","accountType":"PHONE"}"#.utf8))
        XCTAssertNil(user.phoneVerified)
        let caps=try JSONDecoder().decode(PhoneAuthCapabilities.self,from:Data(#"{"availablePurposes":[],"resetLimit":2,"policyVersion":"2026-10-23.2"}"#.utf8))
        XCTAssertTrue(caps.availablePurposes.isEmpty)
        let challenge=try JSONDecoder().decode(SMSChallenge.self,from:Data(#"{"challengeId":"synthetic","expiresIn":300,"retryAfter":60}"#.utf8))
        XCTAssertEqual(challenge.expiresIn,300)
        XCTAssertEqual(challenge.retryAfter,60)
    }
}
