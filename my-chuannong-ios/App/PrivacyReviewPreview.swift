import SwiftUI

#if DEBUG
/// Isolated visual review: no saved accounts, network tasks, or consent persistence.
struct PrivacyReviewPreview: View {
    @State private var accepted = false
    @State private var platform = PlatformSession(loadSaved: false)
    @State private var school = SchoolSession(loadSaved: false)
    @State private var configuration = ProductConfiguration(previewFlags: [
        "resource_library": .object(["enabled": .bool(true), "payload": .object(["status": .string("COMING_SOON")])])
    ])
    var body: some View {
        Group {
            if accepted {
                NavigationStack { ServicesView(store: .preview(), isPreview: true) }
            } else {
                WelcomeView(accept: { accepted = true })
            }
        }.environment(platform).environment(school).environment(configuration).tint(ChuannongTheme.green)
    }
}
#Preview("首次协议 · 独立界面验收") { PrivacyReviewPreview() }
#endif
