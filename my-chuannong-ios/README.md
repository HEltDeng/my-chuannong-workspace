# 我的川农 iOS

本目录迁移自有 Android 产品的业务与接口，使用原生 SwiftUI 实现。当前是第一个可运行的开发验收阶段，尚非 Android 全功能版本。完整范围和验收状态见 [迁移记录](../docs/IOS_MIGRATION.md)。

## 打开与运行

在 Xcode 打开 `MyChuannong.xcodeproj`，选择 `MyChuannongDevelopment` Scheme 和 iPhone 模拟器，按 ⌘R 编译运行。页面代码在 `App/ServicesView.swift`；数据获取在 `App/AnnouncementStore.swift`；公共 API 与状态模型在 `Core/Sources/ChuannongCore/`。

模拟器安装名为“我的川农开发”，开发 Bundle ID 为 `com.mychuannong.app.development`。现阶段只开放服务动态和两个学校公开网页入口，不能用于替代正式应用的学校绑定与平台账号门禁。

```sh
swift test --package-path my-chuannong-ios/Core
xcodebuild -project my-chuannong-ios/MyChuannong.xcodeproj \
  -scheme MyChuannongDevelopment -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath my-chuannong-ios/DerivedData CODE_SIGNING_ALLOWED=NO build
```

以上命令从总工作区根目录执行。模拟器名称按本机安装环境调整。真机签名、正式 Bundle ID 和高德 iOS SDK 接入尚未配置；`Config/Local.xcconfig.example` 只是后续本地配置示例，目前不含密钥，也未接入地图 SDK。

## 已实现与验证

- 复用生产公共接口 `https://chuannong-api.mychangliapp.cn/api/v1/public/service-updates`，仅展示公告，不展示 Android APK 更新。
- 公告在服务页原有“服务动态”位置，位于校园服务介绍卡下方。沿用自有绿色主题，原生分页、自动轮播与详情页；前台同步、下拉刷新、缓存回退与撤回同步。
- API 请求限定本产品 HTTPS 来源，禁止跨来源重定向；学校公开链接使用独立域名规则，学校凭据尚未接入。
- 真实后台 A/B 公告读取、自动轮播、点击详情及撤回同步已在模拟器验证。测试公告已撤回；无卡片时正常显示“暂无服务动态”，不等于断网。
- 7 项 Swift 核心测试及 Xcode 模拟器构建通过。带图公告、跳转公告、VoiceOver 真正操作、大字体/暗色视觉回归与手动无限循环仍待专门验收。

`#Preview` 使用明确标为预览的本地示例，不发请求或写入后台。Xcode Canvas 已实际渲染页面，可在编辑器右侧查看；若暂停，使用画布的 Refresh Canvas 按钮恢复。查看真实后端运行效果使用 ⌘R 和 Simulator。核心 Swift 包位于 `Core/`，与 App 目录分开，避免预览构建目标识别冲突。构建与运行成功不能替代全部功能验收。

## 方向与边界

产品 UI、颜色和业务以自有“我的川农”Android 为准。云岭星球只作局部动画和交互研究，当前未导入任何第三方项目源码。后端、内容与业务域名复用；iOS 高德 Key、Apple 签名、APNs、WidgetKit 和平台设备字段分别适配。

学校凭据、Cookie、课表、成绩将只保存在设备；平台身份与学校认证隔离。缓存与构建目录、私钥和本地配置不进入 Git。下一阶段先实现学校绑定与设备端安全存储，再迁移首页、课表与成绩。
