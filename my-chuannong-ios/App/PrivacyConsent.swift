import SwiftUI
import Darwin

/// Bump this key whenever the scope of processing changes; old consent is not reused.
enum PrivacyConsent {
    static let storageKey = "privacy.ios.v5"
    static let policyVersion = "2026-10-26.1"
    static let receiptVersion = 7
    static var acceptedAt: Int64 { Int64(UserDefaults.standard.double(forKey: "privacy.acceptedAt.v5")) }
    static func accept() {
        UserDefaults.standard.set(Date.now.timeIntervalSince1970 * 1000, forKey: "privacy.acceptedAt.v5")
        UserDefaults.standard.set(true, forKey: storageKey)
    }
    static func declineAndExit() {
        UserDefaults.standard.set(false, forKey: storageKey)
        UserDefaults.standard.removeObject(forKey: "privacy.acceptedAt.v5")
        // Explicit product request for the local review build. iOS has no graceful
        // application-exit API; revisit this behavior before App Store submission.
        UserDefaults.standard.synchronize()
        Darwin.exit(EXIT_SUCCESS)
    }
}

struct WelcomeView: View {
    @State private var document: LegalDocumentKind?
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var bodySize = 15.0
    @ScaledMetric(relativeTo: .headline) private var titleSize = 18.0
    @ScaledMetric(relativeTo: .headline) private var buttonSize = 16.0
    var accept: () -> Void = { PrivacyConsent.accept() }
    var decline: () -> Void = { PrivacyConsent.declineAndExit() }
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(uiColor: .systemBackground).ignoresSafeArea()
                VStack(spacing: 18) {
                    Spacer()
                    Image(systemName: "leaf.fill").font(.system(size: 76)).foregroundStyle(ChuannongTheme.green)
                    Text("欢迎使用我的川农").font(.title2.bold())
                    Spacer()
                    HStack(spacing: 10) {
                        Image(systemName: "leaf.fill").font(.title)
                        Text("我的川农").font(.system(size: 24, weight: .bold)).lineLimit(1)
                    }.foregroundStyle(ChuannongTheme.green).padding(.bottom, 32)
                }.accessibilityHidden(true)
                Color.black.opacity(0.48).ignoresSafeArea()
                VStack(spacing: 0) {
                    Text("用户协议及隐私保护")
                        .font(.system(size: titleSize, weight: .bold)).multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader).padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 18)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("欢迎来到我的川农！\n我们重视您的个人信息与使用权益。请在使用前阅读[《隐私政策》](legal://privacy)、[《用户协议》](legal://agreement)、[《第三方服务与 SDK 清单》](legal://thirdparties)和[《个人信息收集清单》](legal://collection)。")
                            ForEach(LegalContent.consentSummary, id: \.0) { title, text in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(title).fontWeight(.semibold)
                                    Text(text)
                                }
                            }
                            Text("服务范围、使用规则和各功能说明已集中在上述协议及[《服务说明》](legal://services)中。点击“同意”，表示您已阅读并同意用户协议和隐私政策。")
                        }.font(.system(size: bodySize)).foregroundStyle(Color.primary.opacity(0.68)).lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20).padding(.bottom, 8)
                    }.accessibilityIdentifier("welcome-agreement-scroll").scrollIndicators(.visible)
                    VStack(spacing: 4) {
                        Button("同意", action: accept)
                            .font(.system(size: buttonSize, weight: .medium)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(ChuannongTheme.green, in: Capsule())
                            .accessibilityIdentifier("welcome-agree")
                        Button("不同意", action: decline)
                            .font(.system(size: bodySize)).foregroundStyle(Color.primary.opacity(0.68))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .accessibilityIdentifier("welcome-disagree")
                    }.buttonStyle(.plain).padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 12)
                }
                .frame(maxWidth: 420).frame(height: max(260, geometry.size.height * (typeSize.isAccessibilitySize ? 0.86 : 0.70)))
                .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 24))
                .padding(.horizontal, 38)
                .accessibilityAddTraits(.isModal)
            }
        }
        .tint(ChuannongTheme.green)
        .environment(\.openURL, OpenURLAction { url in
            guard url.scheme == "legal", let kind = LegalDocumentKind(rawValue: url.host ?? "") else { return .systemAction }
            document = kind
            return .handled
        })
        .sheet(item: $document) { kind in
            NavigationStack {
                LegalView(kind: kind).toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { document = nil } } }
            }.tint(ChuannongTheme.green)
        }
    }
}
