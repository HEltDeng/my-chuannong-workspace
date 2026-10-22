import SwiftUI
import SafariServices

enum ChuannongTheme {
    // Same light-mode brand token as Android DesignColors: #237B62.
    static let green = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.45, green: 0.76, blue: 0.64, alpha: 1)
            : UIColor(red: 35 / 255, green: 123 / 255, blue: 98 / 255, alpha: 1)
    })
    static let background = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let ink = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? .label : UIColor(red: 72 / 255, green: 69 / 255, blue: 80 / 255, alpha: 1)
    })
}

struct ServicesView: View {
    @State var store = AnnouncementStore()
    var isPreview = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var cardHeight = 184.0
    @State private var selection = 0
    @State private var lastInteraction = Date.distantPast
    @State private var detail: Announcement?
    @State private var web: WebDestination?

    private var canRotate: Bool {
        !isPreview && scenePhase == .active && !reduceMotion && detail == nil && web == nil && store.state.items.count > 1
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                dynamics
                publicSchoolLinks
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(ChuannongTheme.background)
        .foregroundStyle(ChuannongTheme.ink)
        .refreshable { if !isPreview { await store.refresh() } }
        .task(id: scenePhase) {
            guard !isPreview, scenePhase == .active else { return }
            while !Task.isCancelled {
                await store.refresh()
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
            }
        }
        .task(id: canRotate) {
            guard canRotate else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(6)) } catch { return }
                guard Date.now.timeIntervalSince(lastInteraction) >= 12, !store.state.items.isEmpty else { continue }
                withAnimation(.easeInOut(duration: 0.35)) {
                    selection = (selection + 1) % store.state.items.count
                }
            }
        }
        .onChange(of: store.state.items.map(\.id)) { _, ids in
            if selection >= ids.count { selection = 0 }
        }
        .sheet(item: $detail) { announcement in
            NavigationStack { AnnouncementDetailView(announcement: announcement) }
        }
        .sheet(item: $web) { destination in
            SafariPage(url: destination.url).ignoresSafeArea()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("校园服务").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
            Text("常用查询与校园工具，清晰归类，一步直达")
                .font(.subheadline).foregroundStyle(.secondary).lineSpacing(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(LinearGradient(colors: [ChuannongTheme.card, ChuannongTheme.green.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 26))
    }

    private var dynamics: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("服务动态").font(.title2.bold()).accessibilityAddTraits(.isHeader)
                Text("（下拉刷新）").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if store.refreshing { ProgressView().controlSize(.small).accessibilityLabel("正在刷新服务动态") }
            }
            if store.state.items.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: store.state.errorMessage == nil ? "megaphone" : "wifi.exclamationmark")
                        .foregroundStyle(ChuannongTheme.green).accessibilityHidden(true)
                    Text(!store.state.hasLoaded && store.state.errorMessage == nil
                         ? "正在加载服务动态…"
                         : store.state.errorMessage ?? "暂无服务动态，下拉可刷新")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .padding(22).frame(maxWidth: .infinity, minHeight: 92)
                .background(ChuannongTheme.card, in: RoundedRectangle(cornerRadius: 22))
            } else {
                if store.state.items.count == 1 {
                    announcementButton(store.state.items[0])
                } else {
                    TabView(selection: $selection) {
                        ForEach(Array(store.state.items.enumerated()), id: \.element.id) { index, item in
                            announcementButton(item).tag(index).padding(.horizontal, 1)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(height: cardHeight + (dynamicTypeSize.isAccessibilitySize ? 60 : 0))
                    .simultaneousGesture(DragGesture(minimumDistance: 10).onChanged { _ in lastInteraction = .now })
                    HStack(spacing: 8) {
                        ForEach(store.state.items.indices, id: \.self) { index in
                            Circle().fill(ChuannongTheme.green.opacity(index == selection ? 1 : 0.24))
                                .frame(width: index == selection ? 8 : 6, height: index == selection ? 8 : 6)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 20)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("服务动态轮播")
                    .accessibilityValue("第 \(selection + 1) 条，共 \(store.state.items.count) 条")
                    .accessibilityAdjustableAction { direction in
                        lastInteraction = .now
                        let count = store.state.items.count
                        guard count > 0 else { return }
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                            switch direction {
                            case .increment: selection = (selection + 1) % count
                            case .decrement: selection = (selection + count - 1) % count
                            @unknown default: break
                            }
                        }
                    }
                }
                if store.state.errorMessage != nil {
                    Label("刷新失败，已保留上次动态", systemImage: "wifi.exclamationmark")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityIdentifier("service-dynamics")
    }

    private func announcementButton(_ item: Announcement) -> some View {
        Button {
            lastInteraction = .now
            if let url = item.destination { web = WebDestination(url: url) }
            else { detail = item }
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                Label(item.category?.isEmpty == false ? item.category! : "公告", systemImage: "megaphone.fill")
                    .font(.caption.bold()).foregroundStyle(ChuannongTheme.green)
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.title).font(.headline).foregroundStyle(.primary).lineLimit(2)
                        if let summary = item.summary, !summary.isEmpty {
                            Text(summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(3).lineSpacing(3)
                        }
                    }
                    Spacer(minLength: 0)
                    if let url = item.imageURL {
                        AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: {
                            RoundedRectangle(cornerRadius: 12).fill(ChuannongTheme.green.opacity(0.08))
                        }
                        .frame(width: 72, height: 72).clipShape(RoundedRectangle(cornerRadius: 12)).accessibilityHidden(true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: cardHeight - 6, alignment: .topLeading)
            .background(ChuannongTheme.card, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(ChuannongTheme.green.opacity(0.28), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("打开公告详情")
    }

    // These are the public destinations from our Android SchoolServiceCatalog.
    // Authenticated school services are added only after the native binding flow is ported.
    private var publicSchoolLinks: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("学校公开信息").font(.title2.bold()).accessibilityAddTraits(.isHeader)
            publicLink("学校官网", subtitle: "四川农业大学", icon: "building.2", url: "https://www.sicau.edu.cn/")
            Divider()
            publicLink("学校校历", subtitle: "查看官方校历与日程", icon: "calendar", url: "https://www.sicau.edu.cn/ggfw/rlxl.htm")
        }
        .padding(22).background(ChuannongTheme.card, in: RoundedRectangle(cornerRadius: 26))
    }

    private func publicLink(_ title: String, subtitle: String, icon: String, url: String) -> some View {
        Button {
            if let destination = URL(string: url), SchoolURLPolicy.allows(destination) { web = WebDestination(url: destination) }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.title3).foregroundStyle(ChuannongTheme.green)
                    .frame(width: 46, height: 46).background(ChuannongTheme.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.headline).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
            }
        }.buttonStyle(.plain)
    }
}

private struct WebDestination: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

private struct SafariPage: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

private struct AnnouncementDetailView: View {
    let announcement: Announcement
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(announcement.title).font(.title2.bold()).accessibilityAddTraits(.isHeader)
                Text(announcement.category ?? "公告").font(.subheadline.bold()).foregroundStyle(ChuannongTheme.green)
                if let milliseconds = announcement.publishedAt {
                    Text(Date(timeIntervalSince1970: Double(milliseconds) / 1000), format: .dateTime.year().month().day().hour().minute())
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let url = announcement.imageURL {
                    AsyncImage(url: url) { image in image.resizable().scaledToFit() } placeholder: { ProgressView() }
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                Text(announcement.summary ?? "").font(.body).lineSpacing(7).textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(24)
            .background(ChuannongTheme.card, in: RoundedRectangle(cornerRadius: 24)).padding(20)
        }
        .background(ChuannongTheme.background)
        .foregroundStyle(ChuannongTheme.ink)
        .navigationTitle("服务公告").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
    }
}

#if DEBUG
#Preview("服务动态 · 卡片与位置") {
    NavigationStack { ServicesView(store: .preview(), isPreview: true) }
        .tint(ChuannongTheme.green)
}
#endif
