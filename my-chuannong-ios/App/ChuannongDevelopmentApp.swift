import SwiftUI

/// A separate simulator workbench while school binding and other modules migrate.
/// Its bundle identifier is deliberately distinct from the eventual production app.
@main
struct ChuannongDevelopmentApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ServicesView()
                    .navigationTitle("服务")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Text("开发验收").font(.caption).foregroundStyle(.secondary)
                        }
                    }
            }
            .tint(ChuannongTheme.green)
        }
    }
}
