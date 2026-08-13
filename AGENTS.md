# Repository Guidelines

AcePocket 是 AcePanel 服务器面板的非官方 Flutter 手机客户端。当前开发、CI 与发布以 Android 为主；除非用户明确要求，不要新增 iOS CI 或发布工作。UI、代码注释和提交说明使用中文。

## 项目结构与模块组织

应用入口为 `lib/main.dart` 和 `lib/app.dart`。共享 API、路由、存储、主题、生命周期、版本门控、工具及组件位于 `lib/core/`。业务代码按 `lib/features/<feature>/` 组织，通常包含 `models/`、`repo/`、`providers/`、`pages/`、`widgets/` 和 `routes.dart`。测试在 `test/core/` 与 `test/features/` 中镜像源码结构；平台工程位于 `android/` 和 `ios/`，资源和文档分别位于 `assets/` 与 `docs/`。

新增模块时，在 `routes.dart` 导出 `<camelKey>Routes`，由 `lib/core/router/router.dart` 聚合，并在 `lib/core/pages/more_page.dart` 的 `kMoreGroups` 添加入口。同一模块内静态路由必须放在动态路由之前。底部导航使用 `StatefulShellRoute.indexedStack`，其余页面使用顶层路由全屏覆盖。

## 构建、测试与开发命令

```bash
flutter pub get
flutter analyze
flutter test
flutter test test/core/downsample_test.dart
flutter test --plain-name '端口写成斜杠时提示改用冒号'
flutter run
flutter build apk --release --target-platform android-arm64
```

使用 Flutter 3.44.8 stable 与 CI 对齐。静态检查必须达到 0 error、0 warning、0 info。真机更新安装使用 `adb install -r <apk>`，不要使用会先卸载应用、清除私有数据的 `flutter install`。发布签名读取不入库的 `android/key.properties`，模板见 `android/key.properties.example`；缺失时仅生成不可分发的 debug 签名包。

## 编码风格与命名约定

遵循 `analysis_options.yaml` 和 `flutter_lints`：两个空格缩进、单引号字符串、多行结构保留末尾逗号，并使用 `dart format`。文件使用 `snake_case.dart`，类型使用 `UpperCamelCase`，成员和 provider 使用 `lowerCamelCase`。功能专属代码留在对应 feature，只有真正跨模块复用的逻辑才进入 `core/`。

## 架构与数据约定

HTTP 面板请求使用 API 令牌和 HMAC-SHA256。路径、Go 风格 query 编码、摘要与签名统一由 `lib/core/api/panel_request_signer.dart` 生成；query 必须通过 `ApiClient` 的 `query` 参数传入，不能拼进 path。配置访问入口时，实际 URL 带入口前缀，但签名路径仍为 `/api/...`。

WebSocket 不接受 HMAC，必须通过 `lib/core/api/ws_client.dart` 的 RSA-OAEP(SHA-512) 登录流程换取 Cookie。统一调用异步的 `wsConnect`；2FA 与图形验证码由全局 `WsSessionManager.challengeHandler` 处理，不要在功能页重复实现。

所有面板网络通道必须使用 `lib/core/api/panel_http_client.dart` 的 HTTPS 与证书策略。面板仅允许 HTTPS；自签名证书采用 TOFU：首次拒绝并要求用户确认，之后固定 SHA-256 指纹。`badCertificateCallback` 是同步回调且可能不在 UI 语境中运行，只能记录并拒绝证书，禁止直接弹窗。GitHub 更新检查等非面板公网请求使用独立客户端，不套用面板证书固定逻辑。

Notifier 的 `build()` 必须 `ref.watch(xxxRepoProvider)`，确保切换服务器后重建。分页统一使用 `lib/core/providers/paged_notifier_base.dart`，不要自行复制分页状态机；基类通过请求代次 `generation` 丢弃过期响应，并将进行中标志保存在 pager 字段中，避免 refresh 重建 state 后误清标志并触发并发请求。面板时间在解析处调用 `.toLocal()`，Go 零值时间（`year <= 1`）按 null 处理。新增面板功能需登记 `PanelFeature` 并展示 `FeatureUnsupportedBanner`；纯本地功能不做版本门控。轮询和心跳通过 `ref.listen` 消费前台状态，避免因 `ref.watch` 重建 Notifier。

接口路径、方法和字段以 AcePanel Go 源码为准：路由查 `internal/route/*.go`，请求查 `internal/request/*.go`，响应查 `internal/service/*.go`。补充资料见 `docs/acepanel-api.md` 和 `docs/architecture.md`。

## 动效与返回手势

自定义动画的时长与曲线一律取 `lib/core/theme/motion.dart` 的 `AppMotion`（转发 Material 3 的 `Durations` / `Easing`），不要自己发明数值；写入组件前用 `AppMotion.resolve` 包一层，系统开启「移除动画」时退化为瞬时。内容整体替换用 `lib/core/widgets/fade_switch.dart` 的 `FadeSwitch`（子节点必须带 `Key`，整页占位传 `expand: true`）；条件出现的通栏内容与展开 / 收起面板用 `lib/core/widgets/animated_reveal.dart` 的 `AnimatedReveal`，折叠箭头用同文件的 `ExpandChevron`。

交叉淡入期间新旧内容会同时挂在树上，同一个 `ScrollController` 不能被两个可滚动组件持有，两侧至少有一侧不挂控制器。

页面转场在 `lib/core/theme/theme.dart` 固定为 `PredictiveBackPageTransitionsBuilder`，配合 manifest 的 `enableOnBackInvokedCallback` 提供 Android 14+ 的预测性返回，不要依赖 Flutter 默认值。返回拦截只能用 `PopScope` 的前置 `canPop`，不要等返回发生时再决定放行，否则系统拿不到确定的返回意图，预测动画不会出现。底部导航的分支切换动效包在 `_BranchFadeThrough` 里，它必须常驻组件树——结构一变 `StatefulNavigationShell` 会重挂载，三个 tab 的导航栈全部清空。

## 测试规范

测试使用 `flutter_test`，文件名以 `_test.dart` 结尾。解析、校验、仓库层和签名构造编写单元测试，可见状态与交互编写 widget test。每个缺陷修复应包含回归测试；提交前运行 `flutter analyze` 和 `flutter test`。测试只能使用 `example.com`、`192.0.2.1`、`2001:db8::` 等保留示例值，禁止出现真实地址、域名、令牌或密码。

## Android 配置约束

不要运行 `flutter create .`，它会覆盖平台定制。主 manifest 必须保留 release 的 `INTERNET` 权限、对 `open_filex` 存储权限的移除规则、收窄后的 FileProvider 路径，以及 `android:enableOnBackInvokedCallback="true"`（预测性返回的开关，去掉后返回手势会退化成普通淡入淡出）。修改 manifest 后运行 `cd android && ./gradlew :app:processReleaseManifest` 检查合并结果。保留 `android/build.gradle.kts` 中的 `file_picker` AGP 9 兼容段。

## 提交与 Pull Request 规范

提交遵循 Conventional Commits，type/scope 使用英文，说明使用中文，例如 `fix: 修复网络安全问题`、`feat: 添加服务器筛选`、`ci: 调整构建校验`。每个提交只处理一个逻辑变更。PR 应说明行为变化、关联 issue、列出验证命令，并为 UI 变更提供截图；迁移、安全影响和平台差异必须明确说明。

## 安全提示

禁止提交 API 令牌、密码、密钥库或 `android/key.properties`。使用示例配置与仓库 Secrets。不要放宽 HTTPS、TOFU、签名校验、Android 权限或 FileProvider 路径来绕过问题。
