import SwiftUI

struct QQGroupSettingsRow: View {
    @AppStorage(PrivacyConsent.storageKey) private var consent = false
    @Environment(\.scenePhase) private var phase
    @State private var busy = false
    @State private var message: String?
    @State private var requestTask: Task<Void, Never>?
    var body: some View {
        Button { requestTask?.cancel(); requestTask = Task { await join() } } label: {
            HStack(spacing: 14) {
                QQPenguinIcon().stroke(ChuannongTheme.green, style: StrokeStyle(lineWidth: 2)).frame(width: 24, height: 24).accessibilityHidden(true)
                Text("加入 QQ 聊天群").font(.system(size: 15)).foregroundStyle(.primary)
                Spacer()
                if busy { ProgressView() }
                else { Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(.tertiary) }
            }.padding(.horizontal, 18).frame(minHeight: 58).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(busy).accessibilityIdentifier("join-qq-group")
            .overlay(alignment: .bottom) { Divider().padding(.leading, 56) }
            .alert("加入 QQ 聊天群", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("知道了", role: .cancel) { message = nil }
            } message: { Text(message ?? "") }
            .onDisappear { requestTask?.cancel() }
            .onChange(of: phase) { _, value in if value != .active { requestTask?.cancel() } }
    }
    @MainActor private func join() async {
        guard consent else { message = "请先阅读并同意用户协议与隐私政策。"; return }
        guard !busy else { return }
        busy = true; defer { busy = false }
        do {
            // Read on every tap, so a changed or disabled group is never opened from a stale cache.
            let value: JSONValue = try await APIClient().request("public/qq-group")
            try Task.checkCancellation()
            let group = QQGroupConfiguration(value)
            guard group.enabled else { message = "QQ群筹备中"; return }
            guard let url = group.joinURL else { message = "加群链接暂不可用，请稍后重试。"; return }
            let opened = await UIApplication.shared.open(url, options: url.scheme == "https" ? [.universalLinksOnly: true] : [:])
            if !opened {
                message = UIApplication.shared.canOpenURL(URL(string: "mqqapi://")!)
                    ? "当前加群链接暂时无法唤起 QQ，请稍后重试。"
                    : "未能打开 QQ，请确认已安装并更新 QQ。"
            }
        } catch is CancellationError {} catch { message = "暂时无法获取加群信息，请稍后重试。" }
    }
}

/// Tencent TDesign's official logo-qq outline, with its original 24 x 24 geometry.
/// Source: https://github.com/Tencent/tdesign-icons/blob/develop/svg/logo-qq.svg
/// Copyright (c) 2021-present TDesign. MIT license: Resources/ThirdPartyNotices/TDesign-Icons.txt.
struct QQPenguinIcon: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 20.2145, y: 14.6548))
        p.addCurve(to: CGPoint(x: 19.513, y: 12.675), control1: CGPoint(x: 20.0273, y: 14.0523), control2: CGPoint(x: 19.7714, y: 13.3498))
        p.addLine(to: CGPoint(x: 18.5692, y: 10.3156))
        p.addCurve(to: CGPoint(x: 18.5818, y: 9.58475), control1: CGPoint(x: 18.5692, y: 10.2884), control2: CGPoint(x: 18.5818, y: 9.82435))
        p.addCurve(to: CGPoint(x: 11.9971, y: 1.5), control1: CGPoint(x: 18.5818, y: 5.55233), control2: CGPoint(x: 16.6781, y: 1.50052))
        p.addCurve(to: CGPoint(x: 5.41184, y: 9.58475), control1: CGPoint(x: 7.3161, y: 1.49948), control2: CGPoint(x: 5.41184, y: 5.55233))
        p.addCurve(to: CGPoint(x: 5.42442, y: 10.3156), control1: CGPoint(x: 5.41184, y: 9.82383), control2: CGPoint(x: 5.42389, y: 10.2884))
        p.addLine(to: CGPoint(x: 4.48067, y: 12.675))
        p.addCurve(to: CGPoint(x: 3.77916, y: 14.6548), control1: CGPoint(x: 4.22167, y: 13.3498), control2: CGPoint(x: 3.96633, y: 14.0523))
        p.addCurve(to: CGPoint(x: 3.39589, y: 18.7443), control1: CGPoint(x: 2.88784, y: 17.5279), control2: CGPoint(x: 3.17568, y: 18.717))
        p.addCurve(to: CGPoint(x: 5.23567, y: 16.581), control1: CGPoint(x: 3.86776, y: 18.8015), control2: CGPoint(x: 5.23567, y: 16.581))
        p.addCurve(to: CGPoint(x: 7.32921, y: 20.7561), control1: CGPoint(x: 5.23567, y: 17.8666), control2: CGPoint(x: 5.89734, y: 19.5444))
        p.addCurve(to: CGPoint(x: 5.71541, y: 21.4864), control1: CGPoint(x: 6.7939, y: 20.9212), control2: CGPoint(x: 6.13747, y: 21.1755))
        p.addCurve(to: CGPoint(x: 5.45325, y: 22.168), control1: CGPoint(x: 5.33633, y: 21.7664), control2: CGPoint(x: 5.38352, y: 22.0516))
        p.addCurve(to: CGPoint(x: 12.0002, y: 22.3337), control1: CGPoint(x: 5.75368, y: 22.6745), control2: CGPoint(x: 10.6009, y: 22.4915))
        p.addCurve(to: CGPoint(x: 18.5467, y: 22.168), control1: CGPoint(x: 13.3996, y: 22.491), control2: CGPoint(x: 18.2468, y: 22.6745))
        p.addCurve(to: CGPoint(x: 18.2845, y: 21.4864), control1: CGPoint(x: 18.6148, y: 22.0527), control2: CGPoint(x: 18.662, y: 21.7674))
        p.addCurve(to: CGPoint(x: 16.6697, y: 20.7555), control1: CGPoint(x: 17.8651, y: 21.175), control2: CGPoint(x: 17.2055, y: 20.9207))
        p.addCurve(to: CGPoint(x: 18.7632, y: 16.581), control1: CGPoint(x: 18.1015, y: 19.5444), control2: CGPoint(x: 18.7632, y: 17.8666))
        p.addCurve(to: CGPoint(x: 20.603, y: 18.7443), control1: CGPoint(x: 18.7632, y: 16.581), control2: CGPoint(x: 20.1306, y: 18.8015))
        p.addCurve(to: CGPoint(x: 20.2145, y: 14.6548), control1: CGPoint(x: 20.8195, y: 18.7181), control2: CGPoint(x: 21.1089, y: 17.529))
        p.closeSubpath()
        return p.applying(CGAffineTransform(scaleX: rect.width / 24, y: rect.height / 24).concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY)))
    }
}
