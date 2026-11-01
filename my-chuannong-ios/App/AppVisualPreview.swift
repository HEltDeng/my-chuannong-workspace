import SwiftUI

#if DEBUG
/// Reuses the actual app views. No account restore, school cookies, reporting, or network refresh.
struct AppVisualPreview: View {
    var initialTab = 1
    @State private var tab = 1
    @State private var platform = PlatformSession(loadSaved: false)
    @State private var school = SchoolSession(loadSaved: false)
    @State private var configuration = ProductConfiguration()

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { HomeView() }
                .tabItem { Label("首页", systemImage: "house") }.tag(0)
            NavigationStack { ServicesView(store: .preview(), isPreview: true) }
                .tabItem { Label("服务", systemImage: "square.grid.2x2") }.tag(1)
            NavigationStack { ProfileView() }
                .tabItem { Label("我的", systemImage: "person.crop.circle") }.tag(2)
        }
        .environment(platform).environment(school).environment(configuration)
        .tint(ChuannongTheme.green)
        .onAppear { tab = initialTab }
    }
}

#Preview("当前 Swift 界面 · 可切换三个主页面") {
    AppVisualPreview()
}
#endif
