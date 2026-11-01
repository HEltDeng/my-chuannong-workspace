import SwiftUI
import UserNotifications
import CryptoKit
import UIKit

@MainActor @Observable final class ForegroundServices {
    private(set) var popup: CampusRecord?
    private var currentOwner: String?
    private func namespace(_ owner: String) -> String { SHA256.hash(data: Data(owner.utf8)).map { String(format: "%02x", $0) }.joined() }
    private func version(_ item: CampusRecord) -> String { item.id + ":" + item["publishedAt"] }
    private func readSeen(_ key: String) -> Set<String> { Set(UserDefaults.standard.stringArray(forKey: key) ?? []) }
    private func remember(_ id: String, key: String) {
        var values = UserDefaults.standard.stringArray(forKey: key) ?? []
        values.removeAll { $0 == id }; values.append(id)
        UserDefaults.standard.set(Array(values.suffix(500)), forKey: key)
    }
    func run(platform: PlatformSession) async {
        guard let owner = platform.user?.id, platform.signedIn else { return }
        if currentOwner != owner { popup = nil }; currentOwner = owner
        let scope = namespace(owner), popupKey = "notice.popup." + scope, notificationKey = "notice.notification." + scope, knownKey = "notice.known." + scope
        while !Task.isCancelled && owner == platform.user?.id {
            do {
                let feed = try await platform.perform("notifications/feed")
                try Task.checkCancellation(); guard platform.user?.id == owner, currentOwner == owner, feed["accountId"].text == owner else { return }
                let items = feed.records
                let legacySeen = readSeen(popupKey).union(readSeen(notificationKey))
                let knownIDs = readSeen(knownKey).union(items.filter { legacySeen.contains(version($0)) }.map(\.id))
                let selected = AnnouncementDeliveryPolicy.latest(in: items, knownIDs: knownIDs)
                if let shown = popup, !items.contains(where: { version($0) == version(shown) && $0.value["popupEnabled"].boolean }) { popup = nil }
                if let selected {
                    for item in items { remember(item.id, key: knownKey) }
                    if selected.value["popupEnabled"].boolean { popup = selected }
                }
                let center = UNUserNotificationCenter.current(), settings = await center.notificationSettings()
                try Task.checkCancellation(); guard platform.user?.id == owner, currentOwner == owner else { return }
                let active = Set(items.filter { $0.value["notificationEnabled"].boolean }.map { "cn.service." + scope + "." + $0.id })
                let delivered = await center.deliveredNotifications()
                center.removeDeliveredNotifications(withIdentifiers: delivered.map { $0.request.identifier }.filter { $0.hasPrefix("cn.service." + scope + ".") && !active.contains($0) })
                if [.authorized, .provisional].contains(settings.authorizationStatus) {
                    if let item = selected, item.value["notificationEnabled"].boolean {
                        try Task.checkCancellation(); guard platform.user?.id == owner, currentOwner == owner else { return }
                        let content = UNMutableNotificationContent(); content.title = item.title; content.body = item["content"]; content.categoryIdentifier = "SERVICE_NOTICE"; content.userInfo = ["route": "notifications", "module": item["module"], "owner": owner]
                        try await center.add(UNNotificationRequest(identifier: "cn.service." + scope + "." + item.id, content: content, trigger: nil))
                        remember(version(item), key: notificationKey)
                    }
                }
            } catch is CancellationError { return } catch {}
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
        }
    }
    func dismissPopup() {
        guard let shown = popup, let owner = currentOwner else { return }
        remember(version(shown), key: "notice.popup." + namespace(owner)); popup = nil
    }
    func followsChanged() {popup=nil}
    func clear() {
        let oldOwner = currentOwner; popup = nil; currentOwner = nil
        guard let oldOwner else { return }; let prefix = "cn.service." + namespace(oldOwner) + "."
        let center = UNUserNotificationCenter.current()
        Task { let delivered = await center.deliveredNotifications(); center.removeDeliveredNotifications(withIdentifiers: delivered.filter { $0.request.identifier.hasPrefix(prefix) }.map { $0.request.identifier }) }
    }
}
@MainActor final class NotificationDelegate:NSObject,UIApplicationDelegate,UNUserNotificationCenterDelegate {
    func application(_ application:UIApplication,didFinishLaunchingWithOptions launchOptions:[UIApplication.LaunchOptionsKey:Any]?=nil)->Bool {
        let center=UNUserNotificationCenter.current();center.delegate=self
        let snooze=UNNotificationAction(identifier:"SNOOZE_5",title:"5 分钟后提醒",options:[])
        center.setNotificationCategories([UNNotificationCategory(identifier:"COURSE_SNOOZE",actions:[snooze],intentIdentifiers:[],options:[]),UNNotificationCategory(identifier:"COURSE",actions:[],intentIdentifiers:[],options:[]),UNNotificationCategory(identifier:"SERVICE_NOTICE",actions:[],intentIdentifiers:[],options:[])])
        return true
    }
    nonisolated func userNotificationCenter(_ center:UNUserNotificationCenter,willPresent notification:UNNotification) async->UNNotificationPresentationOptions{[.banner,.list,.sound]}
    nonisolated func userNotificationCenter(_ center:UNUserNotificationCenter,didReceive response:UNNotificationResponse) async {
        if response.actionIdentifier=="SNOOZE_5" {
            let request = response.notification.request
            guard let starts = request.content.userInfo["startsAt"] as? Double,
                  let owner = request.content.userInfo["ownerKey"] as? String else { return }
            try? await CourseNotifications.snooze(identifier: request.identifier, title: request.content.title, body: request.content.body, starts: starts, expectedOwner: owner)
        }else if response.actionIdentifier==UNNotificationDefaultActionIdentifier {
            let route=response.notification.request.content.userInfo["route"] as? String
            if let route,["schedule","notifications"].contains(route),let url=URL(string:"mychuannong://"+route){await MainActor.run { UIApplication.shared.open(url, options: [:], completionHandler: nil) }}
        }
    }
}
