# 我的川农 iOS

原生 SwiftUI 迁移自本工作区自己的川农 Android。当前覆盖三主页、学校绑定与会话、课表/成绩/考试/校历、学校服务、资料库、校园社区、校外园地、设置、提醒和 WidgetKit。主体代码已移植，正在统一验收与修复，**尚未最终交付**。完整范围、待测项与历史证据见 [迁移与验收记录](../docs/IOS_MIGRATION.md)。

## Xcode 可视化

打开 `MyChuannong.xcodeproj`，Scheme `MyChuannongDevelopment`。`App/AppVisualPreview.swift` 的 Canvas 使用真实页面组件；可切换首页、服务、我的。固定 Canvas 后可在左侧阅读/修改其他 Swift 文件，右侧继续显示界面。预览不读取真实登录缓存、不上报设备，服务动态明确标注样例。

开发 Bundle ID：`com.mychuannong.app.development`；Widget：`com.mychuannong.app.development.widgets`。本机模拟器已安装的版本可能落后于正在编辑的代码，编译成功并不等于已经安装或通过业务测试。

2026-10-23 增加独立 `MyChuannongRelease` Scheme，运行使用 `Release` 优化构建，显示名为「我的川农」，Bundle ID 为 `com.mychuannong.app`，Widget 为 `com.mychuannong.app.widgets`，App Group 为 `group.com.mychuannong.app`。Debug 仍使用开发标识与 Canvas；Release 不包含调试预览入口。用户要求重新体验首次安装时，已重置原 iPhone 17 Pro 测试模拟器并安装此 Release 包，首次协议未代为同意。

Release 本机预览命令：

```sh
xcodebuild -project my-chuannong-ios/MyChuannong.xcodeproj \
  -scheme MyChuannongRelease -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .work/ios-release-build CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- build
```

企业注册通过后的签名团队与正式高德 iOS Key 使用 `Config/Release.local.xcconfig.example` 对应的忽略文件单独配置。Release 不读取开发版 Local.xcconfig，不复用绑定开发 Bundle ID 的高德 Key。模拟器 Release 包不等于可上传 App Store 的签名归档；正式上传条件及已知图标、退出行为限制见迁移记录。

## 构建与依赖

从总工作区根目录执行：

```sh
python3 my-chuannong-ios/Scripts/update-project.py
xcodebuild -project my-chuannong-ios/MyChuannong.xcodeproj \
  -scheme MyChuannongDevelopment -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .work/ios-build CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- build
```

从 iOS 目录执行 `swift Scripts/generate-assets.swift` 可从自有原图重新生成标准 AppIcon。高德官方 SDK 放在被忽略的 `Vendor/AMap`。首次设置可用 `python3 Scripts/install-amap.py /本机官方SDK压缩包目录` 校验并安装固定版本，再运行 `update-project.py`。地图 11.3.100 / Foundation NO-IDFA 1.9.4 / Search 9.8.1 无 arm64 模拟器切片，地图须在真机验收。

复制 `Config/Local.xcconfig.example` 为 `Config/Local.xcconfig` 填本机签名、App Group 与独立高德 iOS Key；不要将其加入 Git。iOS Key 绑定实际 Bundle ID，不能复用 Android Key。

核心规则验收命令：`swift test --package-path my-chuannong-ios/Core`。本轮 34 项核心测试已通过；模拟器与 unsigned 真机目标构建通过。真实学校绑定、课表主动刷新、App 重开与模拟器完整重启后的免重输密码刷新、真实教务超时响应后的自动恢复已通过，2026-10-23 已完成本轮自有服务内容、预约回传、关注通知等测试，完整范围与限制见迁移记录。模拟器必须启用本机 ad-hoc 签名以生成 Keychain/App Group 权限；`CODE_SIGNING_ALLOWED=NO` 只用于编译检查，不能用于安装后登录测试。真实账号与验证码不放在命令行、源码或日志中。

最新学校链路回归：川农 e 会话独立于教务绑定，统一认证、一网通办、学工、综测、周点名、节假日去向及缴费共享学校认证；学工先经官方 mobile SSO 入口取得业务会话再回到所选子页。教务已去掉保存勾选，验证成功默认写入本机 Keychain；隐私正文按用户要求暂不修改。认证页聚焦维持设备宽度与缩放比例，键盘遮挡时允许必要滚动。最终构建完整重启模拟器后的课表刷新与学工会话恢复已实测。详细证据与尚未验收的产品功能见 `../docs/IOS_MIGRATION.md`。

## 代码入口

- `App/SchoolSession.swift`、`SchoolViews.swift`、`SchoolSSOBroker.swift`：先 VPN 后教务、身份验证、非同步 Keychain 会话及有限恢复。
- `App/HomeView.swift`、`AcademicViews.swift`、`TimetableImportView.swift`：学习数据和课表刷新/核对导入。
- `App/ServicesView.swift`、`PlatformContent.swift`、`CommunityViews.swift`、`MarketplaceView.swift`、`CampusServiceViews.swift`：原服务分类和平台业务。
- `App/ProfileViews.swift`、`AccountSettings.swift`、`LegalDocuments.swift`：我的、账号与隐私设置。
- `App/AcademicDataStore.swift`、`LocalToolsViews.swift`、`CampusMapView.swift`：校历、提醒、本机工具与校园地图。
- `Widget/SchoolWidgets.swift`、`App/Widgets.swift`：最小共享课表数据与桌面小组件。
- `Core/Sources/ChuannongCore/`：接口、解析、URL/身份/会话规则，禁止上传学校学习数据。

公告保留服务头条下方的原“服务动态”，不在首页新增栏目。云岭星球只做局部参考，未导入其源码。后端与业务域名继续复用；新增 iOS 设备和版本策略已部署到现有后台并通过双端上报验收。用户本机文档实际包含同一学号的川农 e 与教务两套凭据；最终交付必须通过这两段真实登录、主动刷新与登录保存/恢复测试，并明确实际观察时长和未通过项，不能宣称已完成两位学生实测。

2026-10-23：独立高德 iOS 开发 Key 已创建并配置；课表周次单行、预约收键盘/机构名/刷新、通知最新一条去重已修复。后端 135 项、iOS 核心 34 项通过。完整验收状态及生产测试清理见 `../docs/IOS_MIGRATION.md`。


2026-10-23 学校更新教务登录方式后，iOS 已改为一次川农 e 认证：通过校园 VPN 自动完成教务 SSO 与学号绑定，去掉第二步学号/教务密码输入；成功后清除旧教务密码，仅保留本机学校会话。当前 Release 已通过真实学校认证与课表/成绩/考试同步、持久化恢复，以及 App 冷启动后绑定和完整成绩详情的 UI 回归。37 项核心测试、模拟器 Release 与 unsigned 真机编译通过；长期会话时效仍由学校决定。详细范围见 `../docs/IOS_MIGRATION.md` 最新记录。

2026-10-26 学校刷新修复：刷新统一处理 VPN/教务/CAS 过期，先复用学校会话，确需本人验证时直接进入全屏原生学校认证页；验证后继续同一页面刷新，失败保留缓存。新登录在学校确认本人后将川农 e 学号及密码存入不可同步的本机 Keychain；旧安装没有该密码时需补存一次。学校当前密码登录要求本人完成验证码，不能宣称所有过期情况均可无交互登录。协议更新为 `2026-10-26.1` / 第 7 版，重新同意后才恢复上报；生产仅增加新版协议记录兼容，学校凭据不上报。
