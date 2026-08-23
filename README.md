# AcePocket

[AcePanel](https://github.com/acepanel/panel)（原「耗子面板」）的 Flutter 手机客户端。

> **非官方项目。** 本项目与 AcePanel 官方团队无关，不隶属于、也未获其背书。
> AcePanel 名称与商标归其各自所有者。本客户端仅通过面板公开的 HTTP API
> 与你自己的服务器通信。

用 **API 令牌 + HMAC-SHA256 签名** 直连你自己的面板，不经过任何第三方服务器；
支持同时接入多台服务器并随时切换。UI 为简体中文、Material 3，跟随系统深浅色（也可手动切换）。

- 目标平台：Android（本地文件选择 / 打开依赖 `file_picker`、`open_filex`）
- Dart SDK：`^3.5.0`（Flutter 3.24+）
- 状态管理：`flutter_riverpod` ^2.5，路由：`go_router` ^14
- 主要依赖：`dio`、`crypto`、`web_socket_channel`、`flutter_secure_storage`、
  `shared_preferences`、`fl_chart`、`xterm`、`intl`、`file_picker`、`path_provider`、`open_filex`

> 仓库已包含用 Flutter 3.44.8 生成并做过必要修补的 `android/` 外壳
> （Android 主 manifest 已声明 `INTERNET` 权限、`android/build.gradle.kts` 有
> file_picker 与 AGP 9 的兼容修补），**不要**再执行 `flutter create .` 覆盖它们。

---

## 功能清单

### 概览 / 监控
- 首页仪表盘：CPU / 内存 / Swap / 负载 / 网络上下行 / 磁盘读写实时数据（3 秒轮询，`fl_chart` 迷你趋势图）
- 磁盘分区用量、网卡流量、系统信息（内核 / 发行版 / 面板版本 / 运行时长）
- 面板健康检查、面板更新提示、网站 / 数据库 / 容器 / 计划任务数量统计
- 占用最高的进程 Top N
- 重启面板、重启服务器（均二次确认）
- 历史监控 `/monitor`：今天 / 昨天 / 近 7 天 / 近 30 天，网卡与磁盘切换，采集间隔与保留天数设置，清空监控数据
- 面板升级 `/panel/update`：逐版本更新日志、WebSocket 实时升级日志、无日志升级兜底
- 运行时诊断 `/panel/runtime`：Go runtime 指标（内存 / 堆 / GC）与协程堆栈（筛选、复制、原始文本）

### 网站
- 列表：按类型（反向代理 / PHP / 纯静态）筛选、下拉刷新、滚动分页、启停开关
- 创建：域名、监听端口、根目录 / 代理地址、PHP 版本、随站创建数据库
- 详情 7 个分页：常规、域名与监听、HTTPS、伪静态、反向代理、重定向、高级配置
- 备注、到期时间、状态、重置配置、删除（可选同时删目录与同名数据库）
- 访问统计：概览 / URI / 慢请求 / IP / 地区 / 蜘蛛 / 客户端 / 错误日志，自定义时间范围，统计设置与清空
- 网站默认设置 `/websites/settings`：默认首页 / 停止页 / 404 页、默认 TLS 版本、默认站点（default_server）
- 仅更新证书文件（`POST /website/cert`，不提交详情页其他改动）

### 数据库
- 数据库列表（创建 / 删除 / 改密），支持 MySQL、PostgreSQL、SQLite、ClickHouse、MongoDB
- 数据库服务器（本地 / 远程）、数据库用户（授权列表、同步用户）
- Redis 键值管理、Elasticsearch 索引与文档管理

### 文件
- 目录浏览、面包屑导航、排序、显示隐藏文件、下拉刷新与分页
- 新建文件 / 目录、重命名、删除、清空、复制 / 移动（目标已存在时预检并二次确认）
- 权限修改、属性查看、压缩 / 解压、远程下载（aria2）
- 文本编辑器（读取 / 保存）
- 从手机选择文件上传：≤5MB 直传，>5MB 走面板分片接口（续传、每片 sha256 校验、失败重试、可取消）
- 下载到手机：流式边收边写、进度与取消、完成后可用其他应用打开
- 文件分享：创建免登录下载链接、复制、删除

### 容器
- 容器列表 / 详情 / 启停 / 重启 / 暂停 / 杀死 / 重命名 / 删除 / 清理
- 容器实时日志（WebSocket）
- 镜像（拉取带逐层进度、删除、清理）、网络、存储卷、Compose 编排（新建 / 启停 / 删除 / 详情）

### 运行环境与项目
- 运行环境 `/environments`：PHP / Go / Java / Node.js / Python / .NET 多版本安装、更新、卸载（异步任务）
- PHP 管理：概览（设为 CLI 版本、清理 Session、错误 / 慢日志入口）、扩展安装卸载、PHP-FPM 负载
- PHP 参数调优（php.ini + php-fpm.conf 逐项，含 Session 存储可视化配置）、配置文件原文编辑、phpinfo（原生渲染，无 WebView）
- 运行时代理 / 镜像源：Go proxy、npm registry、pip mirror（含常用预设）
- 项目 `/projects`：systemd 托管项目列表、启停 / 自启 / 重启 / 重载、完整 unit 配置编辑（启动命令、环境变量、日志输出、依赖顺序、资源限制、安全加固）
- 应用模板 `/templates`：模板市场（分类 + 搜索）、compose 预览、变量表单部署、自动放行端口、部署后一键启动

### SSL 证书
- 证书列表、申请（ACME / DNS / HTTP）、上传自有证书、编辑
- 签发 / 续签实时日志（WebSocket），并提供「无日志执行」兜底
- 部署到网站、查看证书内容、DNS 账号管理、CA 账户管理

### 计划任务与备份
- 计划任务：列表、新建 / 编辑（含 cron 表达式辅助输入与中文预览）、启停、立即执行（WebSocket 回显）、日志查看与清空
- 备份：按类型列出、创建、恢复、删除、下载信息
- 备份下载到手机 / 从手机上传备份包（分块读取 + 分块发送，大文件不占内存，可取消）
- 备份存储：本地 / S3 / OSS / COS / KODO / WebDAV 等

### 安全
- 防火墙：总开关、端口规则、IP 规则、端口转发、端口占用查询
- 扫描感知：设置、统计、趋势、Top IP / 端口、事件记录
- 面板安全：安全入口、端口、HTTPS、登录验证码 / 超时、IP 头、域名 / IP / UA 白名单、Ping 开关
- SSH 服务：服务启停、端口、密码 / 密钥登录开关、root 登录与凭据
- 防篡改：状态与设置、保护规则、拦截日志、路径保护（批量检查 + 逐项开关）
- 端口规则导出 / 导入：面板 xlsx 直传导入、本地 CSV 生成与解析逐条创建

### 终端与 SSH 主机
- 全屏 `xterm` 终端：面板本机 PTY、已保存的 SSH 主机、容器 exec
- 快捷键条（Ctrl 组合 / Esc / Tab / 方向键 / 常用符号）、字号调节、心跳延迟、断线重连、复制粘贴
- SSH 主机 `/ssh-hosts`：主机增删改查，一键打开终端（`/terminal?ssh=<id>`）
- 主机文件浏览 `/ssh-hosts/:id/files`：SFTP 目录浏览与新建目录（`id=0` 为面板本机）

### 工具箱
- 系统工具 `/toolbox/system`：DNS、SWAP、时区、系统时间与 NTP 同步、主机名、hosts 文件编辑
- 磁盘管理 `/toolbox/disk`：磁盘与分区、挂载 / 卸载 / 格式化 / 初始化、fstab 自动挂载、LVM（PV / VG / LV 增删与扩容）
- 磁盘健康 `/toolbox/disk/smart`、RAID 阵列 `/toolbox/disk/raid`
- 日志清理 `/toolbox/logs`：面板 / 网站 / MySQL / Docker / 系统日志扫描与清理
- 网络信息 `/toolbox/network`：连接列表，按状态 / 进程 / PID / 端口筛选与排序，服务端分页
- 服务器跑分 `/toolbox/benchmark`：CPU 9 项 + 内存带宽延迟 + 磁盘 4K/64K/1M 读写
- 面板迁移 `/migration`：连接 → 预检（环境一致性对比）→ 选择迁移项 → WebSocket 实时进度 → 结果与日志

### 告警与通知
- 告警 `/alerts`：规则 CRUD（指标 / 运算符 / 阈值 / 持续时间 / 静默期 / 通知渠道）、告警记录与清空
- 通知渠道 `/notify`：SMTP 渠道 CRUD、发送测试、事件通知开关
- WebHook `/webhooks`：CRUD 与回调地址一键复制

### 应用与系统
- 应用商店：分类、搜索、安装 / 卸载 / 更新、版本通道选择、首页显示与排序、自定义应用源
- 系统服务：启停 / 重启 / 重载 / 开机自启 / 清空日志
- 进程管理：列表、排序、搜索、详情（连接与打开的文件）、发送信号 / 结束进程

### 面板管理
- 面板设置：名称、端口、入口、语言、HTTPS、便签
- API 令牌管理（创建 / 编辑 / 删除，令牌明文仅创建时展示一次）
- 任务中心：任务列表、详情与实时日志（`/file/tail` 反向分页）、取消 / 删除
- 面板日志：操作日志 / 数据库日志 / HTTP 日志 / SSH 登录日志
- 面板证书 `/settings/cert`：证书与私钥热加载（不重启面板），可重新签发 ACME / 自签名证书
- 面板用户 `/panel-users`：用户 CRUD、改用户名 / 邮箱 / 密码、两步验证开启与关闭
- 通行密钥 `/panel-users/passkey`：查看与停用（注册依赖浏览器 WebAuthn，需在网页端完成）
- 关于：App 与面板版本、主题模式（亮 / 暗 / 跟随系统）

### 服务器接入
- 多服务器管理、切换、编辑、删除
- 添加时自动连接测试（可达性 → 令牌有效性），按 401 / 403 / 404 / 418 给出可读中文原因
- 可选填写面板登录账号密码（**仅** WebSocket 功能需要，见下文）

---

## 目录结构

```
lib/
  main.dart                     # ProviderScope + 预加载 ServerStore
  app.dart                      # MaterialApp.router，主题与本地化
  core/
    api/api_client.dart         # ApiClient：HMAC-SHA256 签名、/api 前缀、data 解包
    api/api_exception.dart      # ApiException
    api/ws_client.dart          # wsConnect() + WsSessionManager（Cookie 会话）
                                # 含全局登录挑战回调：2FA / 图形验证码统一在此索要
    models/server.dart          # ServerConfig
    storage/server_store.dart   # 安全存储 + serverListProvider / activeServerProvider / apiClientProvider
    router/router.dart          # 路由聚合、底部导航 Shell、重定向守卫
    pages/more_page.dart        # 「更多」tab：全部功能入口
    theme/theme.dart            # Material 3 深浅色主题
    widgets/                    # loading_view / error_view / empty_view / confirm_dialog
                                # section_card / task_snack
  features/
    <key>/
      models/                   # 数据模型（fromJson，字段以面板 Go 源码为准）
      repo/                     # Repository：调用 ApiClient 返回模型
      providers/                # Riverpod providers
      pages/                    # 页面
      widgets/                  # 模块内组件
      routes.dart               # 导出 final List<RouteBase> <camelKey>Routes
```

功能模块（`lib/features/`，共 20 个）：
`servers`、`home`、`website`、`database`、`files`、`container`、`cert`、
`cron_backup`、`security`、`terminal`、`ssh_hosts`、`apps`、`environment`、
`project_template`、`toolbox_disk`、`toolbox_misc`、`notify_alert`、`migration`、
`panel_users`、`settings`。

### 路由表

| 路径 | 页面 |
| --- | --- |
| `/` | 首页 / 仪表盘（底部导航 tab） |
| `/websites` | 网站列表（底部导航 tab） |
| `/more` | 更多（底部导航 tab） |
| `/servers/setup` | 初次配置引导 |
| `/servers/edit` | 添加 / 编辑服务器（`?id=&advanced=1`） |
| `/servers` | 服务器管理 |
| `/monitor` | 历史监控 |
| `/panel/update` | 面板升级（WebSocket 实时日志） |
| `/panel/runtime` | 运行时诊断（runtime / 协程堆栈） |
| `/websites/create` | 创建网站 |
| `/websites/settings` | 网站默认设置（默认页 / TLS / 默认站点） |
| `/websites/:id` | 网站详情与配置 |
| `/websites/:id/stats` | 网站访问统计 |
| `/databases` | 数据库 |
| `/databases/servers` | 数据库服务器 |
| `/databases/users` | 数据库用户 |
| `/databases/redis` | Redis 管理 |
| `/databases/elasticsearch` | Elasticsearch 管理 |
| `/files` | 文件管理（`?path=`） |
| `/files/edit` | 文件编辑器（`?path=`） |
| `/files/shares` | 文件分享 |
| `/containers` | 容器列表 |
| `/containers/image` | 镜像管理 |
| `/containers/network` | 网络管理 |
| `/containers/volume` | 存储卷管理 |
| `/containers/compose` | 编排管理 |
| `/containers/compose/:name` | 编排详情 |
| `/containers/:id` | 容器详情 |
| `/containers/:id/logs` | 容器实时日志 |
| `/certs` | SSL 证书 |
| `/certs/create` | 申请证书 |
| `/certs/upload` | 上传证书 |
| `/certs/:id/edit` | 编辑证书 |
| `/certs/:id/obtain` | 签发 / 续签（`?mode=obtain\|renew`） |
| `/certs/dns` `/certs/dns/create` `/certs/dns/:id/edit` | DNS 账号 |
| `/certs/accounts` `/certs/accounts/create` `/certs/accounts/:id/edit` | CA 账户 |
| `/crons` | 计划任务 |
| `/crons/edit` | 新建 / 编辑计划任务（`?id=`） |
| `/crons/log` | 任务日志（`?path=&name=`） |
| `/crons/run` | 立即执行任务（`?shell=&name=`） |
| `/backups` | 备份管理 |
| `/backups/storages` `/backups/storages/edit` | 备份存储 |
| `/firewall` | 防火墙 |
| `/firewall/scan` | 扫描感知 |
| `/firewall/export` | 导出端口规则 |
| `/firewall/import` | 导入端口规则 |
| `/security` | 面板安全 |
| `/security/ssh` | SSH 服务 |
| `/security/tamper` | 防篡改 |
| `/terminal` | 终端（`?command=` / `?ssh=` / `?container=` / `?title=`） |
| `/ssh-hosts` | SSH 主机 |
| `/ssh-hosts/new` `/ssh-hosts/:id/edit` | 新建 / 编辑 SSH 主机 |
| `/ssh-hosts/:id/files` | 主机文件浏览（`id=0` 为面板本机，`?path=`） |
| `/apps` | 应用商店 |
| `/systemctl` | 系统服务 |
| `/processes` | 进程管理 |
| `/environments` | 运行环境 |
| `/environments/php/:version` | PHP 管理（概览 / 扩展 / 负载） |
| `/environments/php/:version/tune` | PHP 参数调优 |
| `/environments/php/:version/config` | PHP 配置文件编辑（`?target=ini\|fpm`） |
| `/environments/php/:version/phpinfo` | phpinfo |
| `/environments/runtime/:type/:slug` | Go / Java / Node.js / Python / .NET |
| `/projects` | 项目（systemd） |
| `/projects/create` | 新建项目 |
| `/projects/:id` `/projects/:id/edit` | 项目详情 / 编辑 |
| `/templates` | 应用模板 |
| `/templates/:slug` `/templates/:slug/deploy` | 模板详情 / 部署 |
| `/toolbox/disk` | 磁盘管理（磁盘 / LVM / 自动挂载） |
| `/toolbox/disk/smart` | SMART 健康 |
| `/toolbox/disk/raid` | RAID 阵列 |
| `/toolbox/system` | 系统工具（DNS / SWAP / 时间 / NTP / 主机名） |
| `/toolbox/system/hosts` | hosts 文件编辑 |
| `/toolbox/logs` | 日志清理 |
| `/toolbox/network` | 网络连接信息 |
| `/toolbox/benchmark` | 服务器跑分 |
| `/alerts` | 告警（规则 + 记录） |
| `/alerts/rules/new` `/alerts/rules/:id/edit` | 新建 / 编辑告警规则 |
| `/notify` | 通知（渠道 + 事件） |
| `/notify/channels/new` `/notify/channels/:id/edit` | 新建 / 编辑通知渠道 |
| `/webhooks` | WebHook |
| `/webhooks/new` `/webhooks/:id/edit` | 新建 / 编辑 WebHook |
| `/migration` | 面板迁移向导 |
| `/migration/results` | 迁移结果与日志 |
| `/panel-users` | 面板用户 |
| `/panel-users/passkey` | 通行密钥（`?user_id=`） |
| `/settings` | 面板设置 |
| `/settings/tokens` | API 令牌 |
| `/settings/cert` | 面板证书 |
| `/tasks` | 任务中心 |
| `/tasks/:id` | 任务详情与日志 |
| `/logs` | 面板日志 |
| `/about` | 关于 |

`/`、`/websites`、`/more` 是 `StatefulShellRoute.indexedStack` 的三个分支（各自保留独立导航栈），
其余全部为顶层路由，`push` 时全屏覆盖底部导航。
未配置服务器时全局重定向到 `/servers/setup`（`/servers*` 自身豁免，避免重定向死循环）。

---

## 编译运行

本机需要 Flutter 3.24 或更高版本（`flutter --version` 确认）。已在 **Flutter 3.44.8 stable** 上验证：
`dart analyze lib` **零 issue**（error / warning / info 全清），`flutter test` 通过，
`flutter build apk --debug` 构建成功。

```bash
git clone <this-repo> acepanel-mobile
cd acepanel-mobile

# 1. 拉依赖（android/ 已在仓库中，不需要也不要执行 flutter create .）
flutter pub get

# 2. 静态检查（可选）
flutter analyze

# 3. 连上设备 / 模拟器后运行
flutter run

# 4. 打包
flutter build apk --release        # Android
```

> 若确实需要重新生成平台外壳（换包名等），执行
> `flutter create . --platforms=android --org <你的域名倒写>` 之后**必须**
> 重新补回下面「注意事项」里列出的两处修补：主 manifest 的 `INTERNET` 权限，
> 以及 `android/build.gradle.kts` 末尾的 file_picker × AGP 9 兼容段。

### 注意事项

- **`file_picker` 与 AGP 9**：`file_picker` 11.0.2 的 `android/build.gradle` 在检测到
  AGP 9+ 时会跳过 `org.jetbrains.kotlin.android` 插件（它假定工程启用了 AGP 内建 Kotlin），
  但其他 Flutter 插件仍显式应用 KGP，工程只能保持 `android.builtInKotlin=false`；
  两者叠加会让 file_picker 的 Kotlin 源码不参与编译，构建时报
  `找不到符号: 类 FilePickerPlugin`。仓库已在 `android/build.gradle.kts` 末尾针对该子工程
  补回 Kotlin 插件与 JVM 17 目标，**重新生成 android/ 后需要手动补回这段**。
- **Flutter 内建 Kotlin 迁移警告**：Flutter 3.44 构建时仍会提示 `file_picker` 11.0.2
  与 `package_info_plus` 9.0.1 自行应用 KGP，未来 Flutter 版本会停止兼容。当前
  `file_picker` 已是稳定最新版，而 `package_info_plus` 10.x 依赖 `win32` 6.x，和
  `file_picker` 11.0.2 依赖的 `win32` 5.x 无法同时解析；需等待上游发布可兼容版本后
  一并升级。在此之前当前 Flutter 3.44.8 的 release 构建可正常完成。
- **`flutter create .` 之后如果 `pubspec.yaml` 被改写**（某些 Flutter 版本会追加默认段落），
  请确认 `name: acepanel_mobile`、`environment.sdk: ^3.5.0` 与 dependencies 列表仍与仓库版本一致。
- **`intl` 版本**：`flutter_localizations` 会把 `intl` 钉死在 Flutter SDK 内置的版本上。
  本仓库用的是 `^0.20.2`（Flutter 3.44 内置版本）。若你的 Flutter 较旧导致
  `version solving failed`，按 pub 的提示把约束改成它要求的版本即可，代码本身不受影响。
- **网络权限（重要）**：`flutter create` **只**把 `INTERNET` 权限写进 `debug`/`profile` 的
  manifest，主 manifest（release 用）里没有——release 包会因此完全无法联网，
  且报错表现为「无法连接服务器」而非权限错误，极易误判为网络或地址问题。
  本仓库已在 `android/app/src/main/AndroidManifest.xml` 中显式声明该权限，
  执行 `flutter create .` 后若该文件被覆盖，需要重新加回：
  `<uses-permission android:name="android.permission.INTERNET"/>`。
  验证方法：`adb shell dumpsys package <包名> | grep INTERNET`。
  App 仅接受 **HTTPS** 面板地址；Android 明文流量限制不会为 HTTP 面板放宽。
  请先给面板配置 HTTPS，再添加服务器。
- **自签名证书**：在「添加服务器」的高级选项中打开「允许自签名证书」即可（App 内实现，不需要改平台配置）。

---

## 在面板上创建 API 令牌并接入

1. 浏览器登录你的 AcePanel 面板；
2. 进入 **设置 → API 令牌**，点击「创建令牌」；
   - 填写名称与过期时间（过期时间必须晚于当前、早于 10 年后）；
   - 如果面板启用了「IP 白名单」，把手机出口 IP 加进去，否则会返回 403；
3. 创建成功后会弹出令牌明文，**只显示这一次**，复制保存；同时记下列表里的 **令牌 ID**（数字）；
4. 打开 App，在引导页 / 「更多 → 服务器管理 → 添加」中填写：

   | 字段 | 说明 |
   | --- | --- |
   | 名称 | 本地显示名，随意 |
   | 面板地址 | 形如 `https://1.2.3.4:8888`，**不要**带 `/api`、不要带访问入口 |
   | 令牌 ID | 第 3 步的数字 ID |
   | 令牌 | 第 3 步复制的明文令牌 |
   | 访问入口 | 面板「安全入口」，如 `/my-entrance`；未设置就留空 |
   | 允许自签名证书 | 面板用自签名 HTTPS 时打开 |
   | 面板用户名 / 密码 | **可选**，见下文 |

5. 点「保存并进入」，App 会先做连接测试（可达性 → 令牌有效性）再保存。

### 为什么还要填面板用户名 / 密码？

面板服务端**明确禁止**用 HMAC 令牌访问 WebSocket：
`internal/middleware/must_login.go` 中，只要请求带 `Authorization` 头且路径以 `/api/ws` 开头就直接返回
403 `ws not allowed`。`/api/ws/*` 只认**会话 Cookie**。

所以 App 在需要 WebSocket 的功能上会先用用户名/密码登录面板拿会话
（`GET 入口` → `GET /api/user/key` 取 RSA 公钥 → RSA-OAEP(SHA-512) 加密后
`POST /api/user/login`，全部在 `core/api/ws_client.dart` 内实现），Cookie 只保存在内存里。

**需要账号密码的功能**：终端 / SSH / 容器 exec、容器实时日志、计划任务实时日志与立即执行、
证书签发 / 续签实时日志、镜像拉取进度、面板升级实时日志、面板迁移进度。
**不需要的功能**：其余全部（仪表盘、网站、数据库、文件、备份、安全、应用、进程、运行环境、
项目、工具箱、告警通知、设置、任务、日志……）。

未填写时，相关页面会给出明确引导（而不是静默失败），点击即可跳到
`/servers/edit?id=<当前服务器>&advanced=1` 补填。

**两步验证（2FA）与图形验证码已在 core 层统一处理**：`WsSessionManager` 在登录前会查
`GET /api/user/is_2fa?username=` 与 `GET /api/user/captcha`，需要时通过全局
`challengeHandler` 弹出输入框（`features/panel_users/widgets/two_factor_prompt.dart`，
在 `lib/app.dart` 启动时注册一次），因此**所有**用到 WebSocket 的页面都自动支持，
无需各自实现；输错时会带着面板返回的原因重试，最多 3 次（面板登录接口限流 5 次 / 分钟）。

### 常见接入错误

| 现象 | 原因 |
| --- | --- |
| HTTP 401 / 「令牌无效」 | 令牌 ID 或令牌值填错；或令牌已过期；或手机时间与服务器相差超过 300 秒（签名时间戳窗口） |
| HTTP 403 | 令牌配置了 IP 白名单，当前出口 IP 不在其中 |
| HTTP 404 / 418 | 面板设置了「安全入口」但 App 里没填（或填错） |
| 「服务器证书校验失败」 | 自签名证书，打开高级选项里的「允许自签名证书」 |
| 「无法连接服务器」 | 地址 / 端口不通，或 Android 明文流量被拦（见上文） |

---

## 未覆盖的面板功能

`internal/route/*.go` 共声明 **308 个 `/api/*` 端点**，本客户端已覆盖 **303 个**。
下面是逐条核对后**确实没有实现**的 5 个端点及原因：

| 端点 | 路由文件 | 未实现的原因 |
| --- | --- | --- |
| `POST /api/user/passkey/register`<br>`PUT /api/user/passkey/register` | `user.go` | 通行密钥注册走 WebAuthn（`navigator.credentials.create`），Flutter 内没有等价能力。`/panel-users/passkey` 已实现查看与停用，并引导到网页端注册 |
| `POST /api/user/passkey/login`<br>`PUT /api/user/passkey/login` | `user.go` | 同上，通行密钥登录同样依赖浏览器。App 用 API 令牌 + 面板账号会话认证，不需要它 |
| `GET /api/ws/ssh/transfer` | `ws.go` | 主机之间（面板本机 ⇄ SSH 主机 / SSH 主机 ⇄ SSH 主机）的文件互传。`/ssh-hosts/:id/files` 目前只做目录浏览与新建目录，本机与手机之间的上传下载走 `/files` |
| `GET /api/toolbox_migration/log` | `toolbox_migration.go` | 返回 `text/plain` 附件（`Content-Disposition`），`ApiClient` 只解包 JSON。迁移页改为在日志控制台提供「复制全部日志」，内容来自 `/results` 与 WebSocket 增量，信息完全等价 |
| `POST /api/toolbox_migration/exec` | `toolbox_migration.go` | SSE 流式执行任意 bash，是**被迁移的源面板**暴露给目标面板调用的内部接口，客户端不应也不需要调用 |

其他已知的局部缺口（接口已实现但没有对应界面 / 有行为限制）：

- **容器创建 / 重建表单**：`ContainerRepo.createContainer()` / `updateContainer()`
  （`POST/PUT /api/container/container`）已实现，但没有做参数众多的创建表单；
  容器可通过应用模板或 Compose 编排创建。
- **编译型运行环境的自定义编译参数**：属于 `app` 模块的 `CustomForm`，
  运行环境列表对这类环境会标注「支持自定义编译」并提示先在网页端配置参数。
- **通知渠道类型**：面板 `pkg/notify` 目前只实现了 `smtp`
  （`request` 的校验也是 `in:smtp`），因此渠道表单即 SMTP 配置。
- **进程状态筛选**：面板服务端 `request.ProcessList.Status` 的校验白名单与实际比较值不匹配
  （Web 端同样如此），因此只提供排序与关键词搜索。
- **跑分接口耗时**：面板同步执行跑分后才返回，`ApiClient` 默认 60 秒 `receiveTimeout`
  不够用，跑分接口已单独放宽到 10 分钟（`ApiClient` 支持按请求覆盖 `receiveTimeout`）；
  再超时的项目按单项失败处理并可单独重测。
- **分片上传残留**：大文件上传中断且不再续传时，目标目录会残留
  `.{文件名}.{hash}.chunk.{n}` 隐藏临时文件（面板 Web 端同样行为），
  重新选同一文件上传会自动续传并在合并后清理。

---

## 开发约定

- 接口路径、请求 / 响应字段一律以 AcePanel Go 源码为准（`internal/route/*.go` 的
  `Summary` / `Request` / `Response` 即接口文档），前端行为参考 `web/src/api/`。
- 每个功能模块只写自己 `lib/features/<key>/` 目录内的文件，通过 `routes.dart` 导出
  `final List<RouteBase> <camelKey>Routes`，由 `core/router/router.dart` 聚合。
- 列表页统一：下拉刷新 + 分页 + `ErrorView` 可重试 + `EmptyView` 空态；
  危险操作统一 `showConfirmDialog(danger: true)` 二次确认。
- 颜色一律取自 `Theme.of(context).colorScheme`，不硬编码。
- 时间字段：面板返回带时区偏移的 RFC3339，`DateTime.parse` 得到的是 `isUtc=true` 的实例，
  展示前必须 `.toLocal()`（各模块的 `models/json_utils.dart` 里的 `jsonTime()` 已统一处理，
  并把 Go 零值时间视为 null）。
- WebSocket 一律用 `core/api/ws_client.dart` 的 `wsConnect()`（**async，需 await**），
  两步验证与图形验证码由 `WsSessionManager.challengeHandler` 统一处理，功能页不要各自实现。
- 需要 multipart / 二进制流的接口（文件上传下载、备份上传下载、防火墙规则导入导出）
  不能走 `ApiClient`（它只收发 JSON），复用 `features/files/repo/transfer_client.dart`
  的 `PanelTransferClient`（同一套 HMAC 签名）与 `features/files/widgets/` 里的进度对话框。
- 详见 `docs/architecture.md`（架构契约）与 `docs/acepanel-api.md`（认证细节）。

## 安全说明

- 面板地址、令牌、账号密码保存在 `flutter_secure_storage`
  （Android EncryptedSharedPreferences），不会上传到任何第三方。
- WebSocket 会话 Cookie 只存在内存中，App 退出即失效。
- 主题模式等非敏感偏好存在 `shared_preferences`。

## 许可

与上游 AcePanel 保持一致（AGPL-3.0）。
