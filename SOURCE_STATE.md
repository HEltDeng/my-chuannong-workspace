# 源码接手说明 · 2026-11-01

本仓库同步截至本次整理的本机现有源码。源码同步不等于重新发布生产服务、App Store 或 APK。

## 获取完整源码

```sh
git clone --recurse-submodules https://github.com/HEltDeng/my-chuannong-workspace.git
cd my-chuannong-workspace
git submodule update --init --recursive
```

Android、iOS、后台分别由子仓库构建，部署与开发脚本留在 scripts。所有源代码子仓库固定到具体提交。

## 保留与排除

保留源码、构建脚本、工程配置、依赖锁定文件、必要应用资源和合成测试。运行数据库、用户上传文件、登录会话、密钥、签名私钥、个人资料、缓存与可重新生成的输出不随仓库分发。

正式签名、地图/短信/外部服务密钥必须在本机配置。源码、依赖和资源可恢复，生产数据和签名身份需用用户自己的独立备份恢复；不能把缺少真实账号或服务配置当成代码缺失。二进制字节还会受工具链、签名和构建时间影响。

## 官网源码 · 2026-11-04

`my-chuannong-website` 为独立私有子仓库，包含静态官网源码；本地预览及未来发布配置见子仓库 README。源码同步不代表官网或客户端已发布。

## 客户端源码同步 · 2026-11-18

当前固定的客户端源码为 iOS **0.1.0（7）** 与 Android **1.0.1（11）**。iOS 沿用 `main`，Android 沿用 `codex/module-operations`；Android 内嵌的失物招领网页源码由 `web/lost-found` 子模块固定。后台配套同步密码注册及协议收据10兼容源码，沿用 `codex/module-operations`。执行上方递归克隆命令即可取得彼此对应的源码提交。

两端已移除校园地图、高德 SDK 与平台短信入口，采用协议版本 `2026-11-17.1`。构建所需的核准协议 `MyChuannongLegal.json` 仍由仓库外目录提供；可用 `scripts/package-app-legal.py` 从所有者本机核准的 Word 文档生成。原始协议、私密配置、签名和运行数据不进入 Git，具体构建变量见各客户端 README。

本次操作仅同步 Git 源码及版本引用，不部署生产服务，不发布安装包或提交应用审核。网站的本地在途改动不属于本次客户端源码同步。
