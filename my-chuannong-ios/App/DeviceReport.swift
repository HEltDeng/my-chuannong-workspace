import Foundation
import UIKit

@MainActor enum DeviceReport {
    static var hardwareModel: String {
        #if targetEnvironment(simulator)
        return ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "iOS Simulator"
        #else
        var system = utsname()
        uname(&system)
        return withUnsafeBytes(of: &system.machine) { bytes in
            String(decoding: bytes.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
        #endif
    }
    static func payload(installationID: String) -> [String: JSONValue] {
        ["installationId": .string(installationID),
         "versionName": .string(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"),
         "versionCode": .number(Double(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1") ?? 1),
         "consentVersion": .number(Double(PrivacyConsent.receiptVersion)),
         "policyVersion": .string(PrivacyConsent.policyVersion),
         "consentAcceptedAt": .number(Double(PrivacyConsent.acceptedAt)),
         "platform": .string("ios"), "manufacturer": .string("Apple"),
         "model": .string(hardwareModel), "osVersion": .string(UIDevice.current.systemVersion)]
    }
}
