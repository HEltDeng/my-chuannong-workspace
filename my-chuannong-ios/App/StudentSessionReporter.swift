import Foundation

/// Sends only a projection of the verified school profile, never school sessions.
@MainActor final class StudentSessionReporter {
    private var lastSignature: String?
    private var lastSuccess = Date.distantPast
    private var hasReported: Bool { UserDefaults.standard.bool(forKey: "studentPresence.reported") }

    private func reportToken() throws -> String {
        if let saved = try SecureStore.read("reportToken", realm: "presence"), let token = String(data: saved, encoding: .utf8) { return token }
        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "") + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        try SecureStore.write(Data(token.utf8), key: "reportToken", realm: "presence")
        return token
    }
    func run(platform: PlatformSession, school: SchoolSession) async {
        guard platform.allowsPresenceReporting, school.allowsPresenceReporting else { return }
        while !Task.isCancelled {
            guard UserDefaults.standard.bool(forKey: PrivacyConsent.storageKey), PrivacyConsent.acceptedAt > 0 else { return }
            let identity = school.identity
            let owner = platform.signedIn ? platform.user?.id : nil
            let signature = [owner ?? "", platform.token ?? "", identity?.studentID ?? "", identity?.name ?? "", identity?.grade ?? "", String(identity?.admissionYear ?? 0)].joined(separator: "|")
            guard owner != nil || identity != nil || hasReported else { return }
            if signature != lastSignature || Date.now.timeIntervalSince(lastSuccess) >= 300 {
                do {
                    var body = DeviceReport.payload(installationID: platform.installationID)
                    body["reportToken"] = .string(try reportToken())
                    let sequence = UserDefaults.standard.integer(forKey: "studentPresence.sequence") + 1
                    UserDefaults.standard.set(sequence, forKey: "studentPresence.sequence")
                    body["reportSequence"] = .number(Double(sequence))
                    body["schoolIdentity"] = identity.map { identity in
                        var fields: [String: JSONValue] = ["studentId": .string(identity.studentID), "realName": .string(identity.name == "川农同学" ? "" : identity.name), "grade": .string(identity.grade ?? "")]
                        if let year = identity.admissionYear { fields["admissionYear"] = .number(Double(year)) }
                        return .object(fields)
                    } ?? .null
                    if platform.signedIn {
                        // Reuse the platform session guard so a revoked token is
                        // cleared before the next school-only report.
                        _ = try await platform.perform("activity/student-session", method: "POST", body: body)
                    } else {
                        let _: JSONValue = try await platform.client.request("activity/student-session", method: "POST", body: JSONEncoder().encode(body))
                    }
                    try Task.checkCancellation()
                    lastSignature = signature; lastSuccess = .now
                    UserDefaults.standard.set(owner != nil || identity != nil, forKey: "studentPresence.reported")
                } catch is CancellationError { return }
                catch { /* Retry after 30 seconds; never log a profile or mark a failed report as sent. */ }
            }
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
        }
    }
}
