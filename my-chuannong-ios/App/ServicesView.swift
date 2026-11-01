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
    var isActive = true
    var allowsNetwork = true
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var cardHeight = 136.0
    @State private var selection = 1
    @State private var lastInteraction = Date.distantPast
    @State private var detail: Announcement?
    @State private var web: WebDestination?

    private var canRotate: Bool {
        !isPreview && isActive && allowsNetwork && scenePhase == .active && !reduceMotion && detail == nil && web == nil && store.state.items.count > 1
    }
    private var carouselHeight: CGFloat {
        cardHeight + (store.state.items.contains { $0.imageURL != nil } ? 104 : 0)
        + (store.state.items.contains { $0.recoverAt != nil } ? 24 : 0)
        + (dynamicTypeSize.isAccessibilitySize ? 90 : 0)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                dynamics
                FeatureSections()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(ChuannongTheme.background)
        .foregroundStyle(ChuannongTheme.ink)
        .refreshable { if !isPreview && isActive && allowsNetwork { await store.refresh() } }
        .task(id: "\(scenePhase)-\(isActive)-\(allowsNetwork)") {
            guard !isPreview, isActive, allowsNetwork, scenePhase == .active else { return }
            while !Task.isCancelled {
                await store.refresh()
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
            }
        }
        .task(id: canRotate) {
            guard canRotate else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard Date.now.timeIntervalSince(lastInteraction) >= 4, !store.state.items.isEmpty else { continue }
                withAnimation(.easeInOut(duration: 0.35)) {
                    selection += 1
                }
            }
        }
        .onChange(of: store.state.items.map(\.id)) { _, ids in
            selection = ids.count > 1 ? 1 : 0
        }
        .task(id: "\(selection):\(store.state.items.map(\.id))") {
            let count=store.state.items.count;guard count>1,selection==0 || selection==count+1 else{return}
            let observed=selection;do{try await Task.sleep(for:.milliseconds(400))}catch{return};guard selection==observed, store.state.items.count==count else{return}
            var transaction=Transaction();transaction.disablesAnimations=true;withTransaction(transaction){selection=observed==0 ? count : 1}
        }
        .toolbar(.hidden,for:.navigationBar)
        .sheet(item: $detail) { announcement in
            NavigationStack { AnnouncementDetailView(announcement: announcement) }
        }
        .sheet(item: $web) { destination in
            SafariPage(url: destination.url).ignoresSafeArea()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("校园服务").font(.system(size:24,weight:.bold)).accessibilityAddTraits(.isHeader)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal,16).padding(.vertical,12)
        .background(LinearGradient(colors: [ChuannongTheme.card, ChuannongTheme.green.opacity(0.14)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 24))
    }

    private var dynamics: some View {
        // SwiftUI may evaluate retiring ForEach children after the live feed changes.
        // Capture values once so withdrawal cannot change their count to zero mid-render.
        let items = store.state.items
        let pages = Array(items.suffix(1)) + items + Array(items.prefix(1))
        let activeIndex = items.isEmpty ? 0 : ((selection - 1) % items.count + items.count) % items.count
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("服务动态").font(.system(size:18,weight:.bold)).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                if store.refreshing { ProgressView().controlSize(.small).accessibilityLabel("正在刷新服务动态") }
            }
            if items.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: store.state.errorMessage == nil ? "megaphone" : "wifi.exclamationmark")
                        .foregroundStyle(ChuannongTheme.green).accessibilityHidden(true)
                    Text(!allowsNetwork ? "联网后更新服务动态" : !store.state.hasLoaded && store.state.errorMessage == nil
                         ? "正在加载服务动态…"
                         : store.state.errorMessage ?? "暂无服务动态")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .padding(22).frame(maxWidth: .infinity, minHeight: 92)
                .background(ChuannongTheme.card, in: RoundedRectangle(cornerRadius: 22))
            } else {
                if items.count == 1 {
                    announcementButton(items[0])
                } else {
                    TabView(selection: $selection) {
                        ForEach(Array(pages.enumerated()), id: \.offset) { page, item in
                            announcementButton(item).tag(page).padding(.horizontal, 1)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(height: carouselHeight)
                    .simultaneousGesture(DragGesture(minimumDistance: 10).onChanged { _ in lastInteraction = .now })
                    HStack(spacing: 8) {
                        ForEach(items.indices, id: \.self) { index in
                            Circle().fill(ChuannongTheme.green.opacity(index == activeIndex ? 1 : 0.24))
                                .frame(width: index == activeIndex ? 8 : 6, height: index == activeIndex ? 8 : 6)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 20)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("服务动态轮播")
                    .accessibilityValue("第 \(activeIndex+1) 条，共 \(items.count) 条")
                    .accessibilityAdjustableAction { direction in
                        lastInteraction = .now
                        let count = items.count
                        guard count > 0 else { return }
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                            switch direction {
                            case .increment: selection += 1
                            case .decrement: selection -= 1
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
        let accent = item.type == "MAINTENANCE" ? Color(hex:0xB8860B) : item.type == "CLOSED" ? Color.secondary : ChuannongTheme.green
        let label = item.type == "MAINTENANCE" ? "维护中" : item.type == "CLOSED" ? "暂时关闭" : item.category?.isEmpty == false ? item.category! : "公告"
        let icon = item.type == "MAINTENANCE" ? "wrench.and.screwdriver" : item.type == "CLOSED" ? "pause.circle" : "megaphone.fill"
        return Button {
            lastInteraction = .now
            if let url = item.destination { web = WebDestination(url: url) }
            else { detail = item }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Label { Text(label).font(.system(size:12,weight:.bold)) } icon: { Image(systemName:icon).font(.system(size:18)) }.foregroundStyle(accent)
                Text(item.title).font(.system(size:16,weight:.bold)).foregroundStyle(.primary).lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                if let summary=item.summary,!summary.isEmpty { Text(summary).font(.system(size:13)).foregroundStyle(.secondary).lineLimit(2).lineSpacing(6) }
                if let url=item.imageURL {
                    AsyncImage(url:url) { image in image.resizable().scaledToFill() } placeholder: { RoundedRectangle(cornerRadius:12).fill(accent.opacity(0.08)) }
                        .frame(maxWidth:.infinity).frame(height:96).clipShape(RoundedRectangle(cornerRadius:12)).accessibilityHidden(true)
                }
                if let recoverAt=item.recoverAt {
                    Text("预计恢复：" + Date(timeIntervalSince1970:Double(recoverAt)/1000).formatted(.dateTime.month().day().hour().minute())).font(.system(size:12)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal,18).padding(.vertical,14).frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: cardHeight, alignment: .topLeading)
            .background(ChuannongTheme.card, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(accent.opacity(0.3), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("打开公告详情")
        .disabled(!allowsNetwork)
    }


}

private struct WebDestination: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct SafariPage: UIViewControllerRepresentable {
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
    NavigationStack { ServicesView(store: .preview(), isPreview: true) }.environment(ProductConfiguration())
        .tint(ChuannongTheme.green)
}
#endif
