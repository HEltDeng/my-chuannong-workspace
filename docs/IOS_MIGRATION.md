# 我的川农 iOS 迁移记录

用户确认日期：2026-10-22。先完成安卓与生产后台联通及公告修复，再逐项迁移 iOS。

## 不得偏离的方向

迁移主体是用户自己的“我的川农”Android 工程：业务流程、学校适配、API、数据模型、功能与绿色主题全部以现有 Android 为准。iOS 使用原生交互，并做性能、可访问性和精细 UI 适配。

云岭星球仅是局部设计研究对象，可研究动画、校园相关页面及交互逻辑。不整套复制源代码、页面、导航壳，不将第三方应用当作川农工程的基础。当前只读取过官方公开的概览与公告 SwiftUI 文件进行研究，没有将任何云岭星球源码导入本产品。若后续确需少量复用代码，须单独记录来源、许可和改动。

2026-10-22 追加位置确认：公告必须复用“服务”页原有“服务动态”卡片区，位于顶部介绍卡（头条）下面、学习工具上面；不另建“校园公告”板块，首页不新增公告卡。安卓和 iOS 一致。已安装用户的“我的长理”v1.0.7 正式参考包，在用户明确同意该模拟器接受协议后实际进入服务页，核对了以上位置。

## 共用与独立配置

- 共享业务 API：`https://chuannong-api.mychangliapp.cn/api/v1/`；共享现有账号、公告、资料、二手、失物、机构和预约，不另建用户数据库。
- 现有后台与文件域名继续复用，iOS 无需单独业务域名。
- 后端现有设备统计字段 `androidVersion/sdkInt` 以及版本下载策略是 Android 专属，接入 iOS 前必须增加明确的平台与系统字段；不能把 iPhone 伪装为 Android，也不能下发 APK 更新。
- 高德企业账号可沿用，iOS SDK Key 必须单独申请并绑定 Bundle ID；Android Key 不通用。
- Apple 签名、Provisioning、APNs、WidgetKit、权限文案、隐私清单和 App Store 发布独立配置。模拟器构建可先不依赖分发签名。
- 学校认证、教务会话及平台账号三者隔离。学校凭据、Cookie、课表和成绩始终留在设备，不进入自有后端或源码仓库。

## 功能迁移验收表

以下条目全部是目标，不能将入口存在或显示占位文字视为完成。

| 功能 | Android 迁移依据 | iOS 完成条件 |
| --- | --- | --- |
| 首次学校绑定 | SchoolAccessGate、SicauWebVpn、SicauJiaowuSession | 先川农 e/VPN，再教务；验证码由用户完成；真实成功证明绑定 |
| 会话与安全存储 | AcademicCredentialVault、SchoolWebSessions | 非同步 Keychain、按域隔离、会话恢复与撤销、账号切换隔离 |
| 首页 | OverviewRepository、OverviewScreen | 今日课程、成绩汇总/隐藏、考试；不下拉刷新 |
| 课表 | Timetable、SchoolSyncEngine | 查询/导入、周次、课程详情、显式刷新、失败保留缓存 |
| 成绩与考试 | SicauTranscriptParser、SicauBusinessParser | 使用真实结构解析，学期、统计、排名与空数据区分 |
| 校历 | SemesterCalendarRepository | 官方数据与校区、学期、教学周一致 |
| 学校服务 | SchoolServices、SchoolServiceJourney | 综测、周点名、节假日去向、学工、一网通办、缴费、统一认证、官网跳转与返回 |
| 公共考试 | 现有快捷入口与学校适配 | 四六级、普通话、计算机考试保持同等入口和行为 |
| 校园地图 | CampusAmapCatalogue、CampusAmapView | 三校区、搜索、地点与路线；独立 iOS 高德 Key；真机定位验收 |
| 平台账号 | CampusToolsSession | 注册/登录、恢复、退出、昵称、注销；不与学校凭据混用 |
| 公告与通知 | FeatureScreen、RemoteConfigurationStore、notification_follows | 公告位于服务页顶部介绍卡下方、学习工具上方；排序、图片、链接、详情、撤回；按账号关注投递；APNs 单列验收 |
| 资料库 | Resource API | 搜索/分类、详情、下载、收藏、历史与投诉 |
| 二手好物 | secondhand 本产品页面和 marketplace API | 出售/求购、图片、发布/编辑/删除、审核、处理通知与筛选 |
| 失物招领 | lost-found 本产品页面和 API | 寻物/招领、图片、发布、收藏、认领、举报、审核与通知 |
| 校外园地 | services、bookings API | 驾校、雅思托福、考公考研、健身房；机构详情与预约状态 |
| 校园指南 | services/guides | 跑腿代取、后勤报修、电费指南，后台内容与图片同步 |
| 设置与反馈 | ProfileSettings、feedback API | 隐私、数据管理、通知关注、反馈和更新 |
| 小组件与上课提醒 | WidgetUpdateCoordinator | WidgetKit、App Group 安全共享、UNUserNotificationCenter |
| 活跃统计 | activity/foreground | 同意后、已登录、前台才上报；平台字段真实；限频与退出停止 |
| 性能与视觉 | 自有 Android 绿色主题 | 原生手势、动态字体、VoiceOver、暗色、减少动态效果、后台取消任务 |

## 已核实环境与阶段

- 本机 Xcode 26.6；iPhone 17 Pro / iOS 26.5 模拟器已经启动。
- iOS 模拟器不提供 App Store 下载安装第三方应用的路径；研究参考使用官方公开页面和源文件，不需要复制整个工程。
- 已创建并编译运行 `my-chuannong-ios/MyChuannong.xcodeproj`，Scheme 为 `MyChuannongDevelopment`。iPhone 17 Pro 模拟器已安装“我的川农开发”，Bundle ID 为 `com.mychuannong.app.development`。Xcode 打开 `App/ServicesView.swift`，可以直接查看真实代码并运行；这是独立开发验收入口，不是已完成学校绑定门禁的发行应用。
- 第一模块实现了原生“服务动态”：复用安卓绿色主题与位置、自动轮播、详情、下拉刷新、前台 30 秒同步、失败保留缓存、成功空数据清除旧卡片。支持动态字体、暗色、减少动态效果；图片和链接支持已实现，尚需带图片/链接的实际发布验收。手动分页采用原生 TabView，尚未完成安卓式无限手动循环的一致性验收。
- 真实生产验收：后台临时发布的 A/B 公告在 iOS 显示并自动轮播，点击可打开完整详情；撤回后公共接口返回成功空列表，iOS 自动显示“暂无服务动态”。两条验收记录均已关闭，未启用通知或弹窗。安卓也已完成发布、滑动、详情、撤回与后台设备可见性核对。
- `swift test --package-path my-chuannong-ios/Core`：7 项核心测试通过，覆盖 API 固定来源、路径/重定向限制、学校域隔离、成功空列表、过滤 Android APK 更新以及缓存/失败/撤回状态转换。Xcode 模拟器 Debug 构建通过。
- SwiftUI Canvas 的构建目标识别问题已解决：将独立核心 Swift 包放入 `Core/`，更新工程引用并重新加载 Xcode 后，原生页面已在代码右侧实际渲染。画布使用明确标注的本地预览示例，不连接生产接口；模拟器用于真实后端验收。
- 完整 iOS 功能迁移尚未完成：学校绑定与本地安全存储、平台账号、课表、成绩、校历数据、地图、资料/交易/失物、预约、关注通知、小组件及真实 iOS 设备统计均待逐项迁移。当前两个学校公开网页入口不代表对应学校业务已迁移。

## 当前交付记录

- 安卓修复提交：`5a14c7c`（保持原有服务动态位置，修复刷新与状态区分）；370 项 JVM 测试与 3 项定向模拟器 UI 测试通过。发布 APK 已校验原签名，并覆盖安装到模拟器。
- 安卓交付目录：`outputs/service-dynamics-corrected-20261022/`，包含 APK 与 `delivery-manifest.json`。本轮未改动或部署后端。
- 证据保存在被 Git 忽略的 `outputs/`：`changli-service-dynamics-reference.png`、`android-service-dynamics-live.png`、`ios-service-dynamics-live.png`、`ios-service-dynamics-detail.png`、`ios-service-dynamics-withdrawn.png`、`admin-service-dynamics-test-withdrawn.png`、`xcode-ios-live-code.png`。不将截图中的真实用户信息提交仓库。
- 后续按依赖顺序推进：先移植学校绑定、会话隔离和设备端安全存储，再接首页/课表/成绩；平台账号与业务模块按上述验收表逐项对齐，平台统计与更新策略单独改造后端。

参考：
- [云岭星球官方项目](https://github.com/zHElEARN/CSUSTPlanet)，仅局部交互研究。
- [高德 iOS SDK Key 配置](https://lbs.amap.com/api/ios-location-sdk/guide/create-project/get-key)。
