# 我的川农 · Mac 开发与腾讯云部署

2026-10-21：Android 与后台源码已下载到本目录，开发依赖已安装，独立后台已在腾讯云上线。正式 APK 尚未生成：按本次安排，等待确认高德 Android Key 后再打包及真机验收。

## 直接使用

日常使用请打开下面的 HTTPS 公网地址，无需启动本机服务。不要直接双击 `my-chuannong-backend/admin/index.html`：`file://` 打开的是源文件，无法正确加载服务器上的样式、脚本和登录接口。地址中 `%E6%88%91...` 只是中文文件夹的 URL 编码。

| 入口 | 地址 |
| --- | --- |
| 运营后台 | https://chuannong-admin.mychangliapp.cn/admin/ |
| APP API | https://chuannong-api.mychangliapp.cn/api/v1/ |
| 文件服务健康检查 | https://chuannong-files.mychangliapp.cn/health |

三条子域名均已配置到 `81.71.34.186`，HTTPS 证书覆盖全部入口。证书到期日为 2027-01-19，已启用自动续期及 Nginx 重载钩子。

首次交接的临时管理员用户名为 `chuannong-admin`。临时密码保存在本机仓库外文件：

`/Users/heltdeng/.local/share/my-chuannong/production/credentials.json`

此文件同时包含生产密钥，不要粘贴到聊天或提交 Git。2026-10-21 已补充首次超级管理员设置窗口：通过临时凭据登录后，由所有者自行填写正式账号名、新密码（16 至 200 位）和确认密码。保存后全部旧会话和临时凭据失效，再用新凭据登录。新密码不会自动写回本机文件；此文件中的临时密码随后不再可用。

权限保持原有层级：超级管理员管理全部平台账号，并在“运营管理员”中创建、编辑对应板块的管理员；板块管理员只访问所属角色的模块，不能自行扩大权限。首次设置只在已有管理员身份验证后出现，没有公开注册超级管理员的入口。

后台数据库为本产品独立新库：仅有首个超级管理员和必要系统配置；普通用户、公告、资料、二手、失物、商家、预约等业务记录均为空。三项校园指南是空白草稿编辑槽，1.0.0 版本也是草稿，更新与强更默认关闭。管理操作会正常产生审计记录。

平台账号注册和登录由该 API 处理；学校账号、学校认证及教务数据继续由手机端处理。当前没有迁入旧的测试账号，也没有可继续使用的旧测试账号密码。

## 本地开发

- Android：`my-chuannong-android/`
- Python 后台与管理页面：`my-chuannong-backend/`
- 开发和部署辅助脚本：`scripts/`
- 非敏感验收记录与截图：`outputs/`
- 临时过程文件和日志：`.work/`

已安装 JDK 17、Android SDK 36.1、Build Tools 36.0.0、Platform Tools、Gradle 9.4.1 和后台 Python 虚拟环境。

```sh
cd '/Users/heltdeng/Documents/ChatGPT/我的川农'
source scripts/env.sh

# 启动独立本地后台；浏览器访问 http://127.0.0.1:8792/admin/
./scripts/start-local-backend.sh
```

本地管理员与生产管理员分开。本地用户名/密码保存在：

`/Users/heltdeng/.local/share/my-chuannong/development/credentials.json`

本地后台数据库位于 `my-chuannong-backend/data/`；本地运行不会写入腾讯云数据库。Android 正式构建配置已经指向上述公网 API。

```sh
# Android 单元测试
cd my-chuannong-android
./gradlew :app:testReleaseUnitTest --no-configuration-cache --console=plain

# 后台测试
cd ../my-chuannong-backend
.venv/bin/python -m unittest discover -s tests -v
```

## 原签名与正式 APK

包名是 `com.mychuannong.app`。JKS 是签名私钥容器，包名是应用标识；要保持原应用身份，两项都需延续。原 JKS 已恢复到稳定路径，私钥和证书校验通过，未创建替代签名。

- 签名文件：`/Users/heltdeng/.local/share/my-chuannong/signing/my-chuannong-release.jks`
- 私密配置：同目录 `signing.properties`
- 高德所需签名 SHA-1：`D7:FD:1B:9E:95:EC:C9:99:A6:96:11:6C:DC:54:D2:41:14:97:75:32`
- 证书 SHA-256：见 `outputs/signing-public-info.json`

确认现有高德 Android Key 绑定上述包名和 SHA-1 后，将 Key 单独保存为：

`/Users/heltdeng/.local/share/my-chuannong/signing/amap-release.key`

文件权限设为 `600`。随后从开发根目录运行：

```sh
./scripts/build-release.sh
```

脚本会按源码原有发布门禁构建 1.0.0（versionCode 10），验证包名与原证书，并在 `outputs/release-时间/` 写入 APK 和交付清单。Key 尚未提供时会明确停止，不生成缺失服务配置的正式包。完成后仍需安卓真机验收登录、地图及更新流程。

## 已完成的验证

- Android Release 单元测试：362 项通过，0 失败。
- 后台测试：本次首次账号设置更新后共 106 项，本机和服务器隔离测试库均通过；包含新增 9 项设置和凭据失效验证，以及原有管理员模块权限测试。
- 原 JKS 的私钥校验、Release 端点校验及 BuildConfig 生成通过。
- 公网 HTTPS/API：初次部署 11 项检查通过，包含健康、就绪、管理员登录、跨入口会话、空资料/公告列表和退出。本次启用首次设置后 8 项检查通过，覆盖三域名健康、就绪、临时登录、身份、待设置状态和退出；实际新凭据由所有者在页面填写。
- 数据库完整性检查为 `ok`，浏览器已实际登录公网后台。

`outputs/live-verification.json`、`outputs/production-state.json`、`outputs/android-test-summary.json` 保存验收记录。`scripts/verify-live.py` 是临时凭据有效期间的初始部署验收脚本：首次设置待完成时只验证身份与设置状态；设置完成、临时凭据失效后不再适用。开始发布真实内容后也不再适用其“空列表/仅一个管理员”断言。

## 运维与后续迁移

SSH 使用已有别名 `mychangli`，川农服务独立运行：

```sh
ssh mychangli
sudo systemctl status mychuannong-backend --no-pager
sudo journalctl -u mychuannong-backend -n 80 --no-pager
sudo systemctl list-timers mychuannong-backup.timer certbot.timer
```

| 内容 | 服务器路径 |
| --- | --- |
| 当前源码 | `/opt/mychuannong/current`（指向独立版本目录） |
| Python 环境 | `/opt/mychuannong/venv` |
| 运行配置与密钥 | `/etc/mychuannong/production.env` |
| 数据库 | `/var/lib/mychuannong/my-chuannong.db` |
| 上传图片 | `/var/lib/mychuannong/uploads` |
| 下载文件 | `/var/www/mychuannong-files` |
| 日志 | `/var/log/mychuannong` |
| 数据库备份 | `/var/backups/mychuannong` |
| Nginx 配置 | `/etc/nginx/sites-available/mychuannong` |

后台服务监听 `127.0.0.1:8792`，通过 Nginx 的 HTTPS 入口访问。API 域名不提供管理页，管理功能通过管理域名访问。

数据库每日北京时间 04:15 起的五分钟内自动备份，保留 14 天；首份完整性校验备份已完成。**这项定时任务只备份数据库**，后续迁移还需一并转移上传图片、下载文件和生产密钥。数据库应使用现有在线备份工具或在停止服务后迁移，不能只复制正在写入的 SQLite 主文件。不得重新初始化覆盖运营数据。

资料通过后台“资料管理”填写下载链接并发布；公告通过“APP 公告”发布。自有资料文件放在文件目录的 `resources/` 下，对应 `https://chuannong-files.mychangliapp.cn/resources/文件名`。未来 APK 放在 `releases/` 下。文件域名根路径不列出目录，当前尚无文件，因此根路径返回 404 是预期行为。

`scripts/install-backend.sh` 和 `scripts/install-maintenance.sh` 是服务器端安装记录及辅助脚本，不要直接在 Mac 执行。后续源码发布需先归档、校验、备份，再更新版本目录和重启服务；不需要再次创建管理员或初始化数据库。

## Git 来源与历史

源码来自已登录 GitHub 下载的 `codex/release-1.0.0` 归档，并核对了归档提交号及源码清单：

- Android 上游：`6f37598289f2ab92d8bd71f6c32489aaf94a94f2`
- 后台上游：`61db65f7661b0ae9a9cff3e4cb59293ad17b7a73`
- 首次超级管理员设置版本：`4d861c3c48d99dc665eab1ea7c176cdcf7ea5ffa`

两个源码目录均建立了 `codex/macos-deployment` 本地 Git 快照并设置原仓库地址。它们不是携带完整历史的 clone，本次未修改 GitHub。未来需要推送改动时，应在 GitHub Git 凭据可用后获取原历史，基于原分支应用本地变更；不要将独立快照历史强推覆盖远端。

最初部署调整了管理页面的环境文案；随后按所有者要求增加一次性超级管理员账号设置、旧会话撤销及相应测试。角色与板块权限模型保持原样，详见后台 `docs/2026-10-21-initial-admin-setup.md`。本目录另有独立 Git 用于保存开发与部署脚本；嵌套源码、凭据、构建输出和运行数据均不纳入它的提交。
