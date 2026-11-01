import Foundation
import Testing
@testable import ChuannongCore

@Test func storedUnifiedPasswordCannotBeReusedForAnotherStudent() throws {
    let original = SchoolCredential(account: "SYNTHETIC1", password: "local-only-test")
    let restored = try JSONDecoder().decode(SchoolCredential.self, from: JSONEncoder().encode(original))
    #expect(restored.belongs(to: "SYNTHETIC1"))
    #expect(!restored.belongs(to: "SYNTHETIC2"))
    #expect(!restored.belongs(to: nil))
    #expect(!SchoolCredential(account: "SYNTHETIC1", password: "").belongs(to: "SYNTHETIC1"))
}

@Test func unifiedLoginRequiresUserCompletedCurrentSchoolChallenge() throws {
    let challenge = try SchoolChallenge(response: .object(["code": .number(200), "id": .string("synthetic-challenge"), "data": .string("data:image/png;base64,dGVzdA==")]))
    let credential = SchoolCredential(account: "SYNTHETIC1", password: "test-secret")
    #expect(throws: SchoolFailure.verification) { try SchoolAuthentication.loginBody(credential: credential, code: " ", challenge: challenge) }
    let body = try #require(JSONSerialization.jsonObject(with: SchoolAuthentication.loginBody(credential: credential, code: "test-code", challenge: challenge)) as? [String: String])
    #expect(body == ["appid": "sicau-cas", "number": "SYNTHETIC1", "password": "test-secret", "code": "test-code", "uuid": "synthetic-challenge"])
    #expect(throws: SchoolFailure.structure) { try SchoolChallenge(response: .object(["code": .number(200), "id": .string("x"), "data": .string("https://foreign.invalid/challenge.png")])) }
}

@Test func expiredVPNAndCASContinueRecoveryButNetworkErrorsNeverTriggerLogin() {
    for failure in [SchoolFailure.vpn, .expired, .unifiedAuthentication] {
        #expect(SchoolAuthentication.canRecover(failure))
        #expect(SchoolAuthentication.requiresAuthentication(failure))
    }
    for error in [URLError(.notConnectedToInternet), URLError(.timedOut), URLError(.cancelled)] {
        #expect(!SchoolAuthentication.canRecover(error))
        #expect(!SchoolAuthentication.requiresAuthentication(error))
    }
    #expect(!SchoolAuthentication.canRecover(SchoolFailure.credentials))
    #expect(!SchoolAuthentication.canRecover(SchoolFailure.verification))
    #expect(!SchoolAuthentication.requiresAuthentication(SchoolFailure.changed))
    #expect(!SchoolAuthentication.requiresAuthentication(CancellationError()))
    #expect(!SchoolAuthentication.requiresAuthentication(SchoolFailure.structure))
    #expect(SchoolAuthentication.requiresAuthentication(SchoolFailure.verification))
}
