# AcePanel Mobile — 架构契约（所有功能模块必须遵守）

Flutter 应用，包名 `acepanel_mobile`。UI 语言：简体中文。深浅色主题均支持。

## 技术栈（pubspec 由 core 统一定义，功能模块不得擅自新增依赖）

- `flutter_riverpod` ^2.5 — 状态管理
- `go_router` ^14 — 路由
- `dio` ^5 — HTTP
- `crypto` ^3 — HMAC-SHA256 签名
- `flutter_secure_storage` ^9 — 服务器凭据存储
- `shared_preferences` ^2 — 普通偏好
- `web_socket_channel` ^3 — WebSocket
- `fl_chart` ^0.69 — 图表
- `xterm` ^4 — 终端模拟器
- `intl` ^0.20 — 格式化
- `file_picker` ^11 — 选择本机文件（v11 起是**静态** API `FilePicker.pickFiles()`，
  不再有 `FilePicker.platform`）
- `path_provider` ^2 — 下载保存目录
- `open_filex` ^4 — 用其他应用打开已下载文件

## 目录结构

```
lib/
  main.dart            # ProviderScope + App
  app.dart             # MaterialApp.router，主题
  core/
    api/api_client.dart      # ApiClient（HMAC 签名，见下）
    api/api_exception.dart
    api/ws_client.dart       # wsConnect()（async）+ WsSessionManager
                             #   含 2FA / 图形验证码的全局挑战回调
    models/server.dart       # ServerConfig
    storage/server_store.dart
    router/router.dart       # 聚合各 feature 的 routes + rootNavigatorKey
    pages/more_page.dart     # 「更多」tab：kMoreGroups 全部功能入口
    theme/theme.dart
    widgets/                 # 通用组件（loading_view、error_view、empty_view、
                             #   confirm_dialog、section_card、task_snack）
  features/
    <key>/
      models/    # 该模块的数据模型（fromJson/toJson）
      repo/      # Repository：调用 ApiClient，返回模型
      providers/ # Riverpod providers
      pages/     # 页面 Widget
      widgets/   # 模块内组件
      routes.dart  # 导出 List<RouteBase> <key>Routes
```

## 核心 API（core 提供，功能模块只消费）

```dart
// core/models/server.dart
class ServerConfig {
  final String id;        // uuid
  final String name;
  final String baseUrl;   // e.g. https://1.2.3.4:8888（不含 /api）
  final String tokenId;   // API 令牌 ID
  final String token;     // API 令牌（HMAC 密钥）
}

// core/api/api_client.dart
class ApiClient {
  ApiClient(ServerConfig server);
  // 自动完成 HMAC-SHA256 签名（见 docs/acepanel-api.md 第 3.1 节），
  // 自动拼接 /api 前缀，成功时返回响应 JSON 的 data 字段，
  // 失败（HTTP 非 2xx 或业务错误）抛 ApiException(message)。
  // query 参与 HMAC 签名的规范化，绝不能自行拼进 path。
  // receiveTimeout 用于个别远超默认 60 秒的接口（如 /toolbox_benchmark/test）。
  // cancelToken 用于取消在途请求（如跑分页停止 / 退出），取消后以
  // ApiException(「请求已取消」) 结束。
  Future<dynamic> get(String path,
      {Map<String, dynamic>? query, Duration? receiveTimeout,
      CancelToken? cancelToken});
  Future<dynamic> post(String path,
      {Object? body, Map<String, dynamic>? query, Duration? receiveTimeout,
      CancelToken? cancelToken});
  Future<dynamic> put(String path,
      {Object? body, Map<String, dynamic>? query, Duration? receiveTimeout,
      CancelToken? cancelToken});
  Future<dynamic> delete(String path,
      {Object? body, Map<String, dynamic>? query, CancelToken? cancelToken});
}
// 只收发 JSON。multipart / 二进制流（文件与备份的上传下载、防火墙规则导入导出）
// 用 features/files/repo/transfer_client.dart 的 PanelTransferClient（同一套签名）。

// core/api/ws_client.dart
// 连接 wss://host/api/ws/...。面板禁止用 HMAC 令牌访问 /api/ws（must_login.go 直接 403），
// 只认会话 Cookie，因此内部先用面板用户名/密码登录（WsSessionManager）。
// **是 async 函数，必须 await**；失败抛 WsAuthException。
// 账号开启两步验证或面板要求图形验证码时，由 WsSessionManager.challengeHandler
// 统一弹窗索要（app.dart 启动时注册一次），功能页无需各自处理。
Future<WebSocketChannel> wsConnect(ServerConfig server, String path,
    {Map<String, String>? query});

// 全局 providers（core/api/api_client.dart & storage/server_store.dart）
final serverListProvider   = ...; // AsyncNotifierProvider<..., List<ServerConfig>>
final activeServerProvider = ...; // 当前选中服务器，Notifier<ServerConfig?>
final apiClientProvider    = ...; // Provider<ApiClient>，依赖 activeServerProvider
```

## 路由约定

- 每个 feature 的 `routes.dart` 导出 `final List<RouteBase> <camelKey>Routes`。
- 主框架：`/` 为带底部导航的 ShellRoute（首页、网站、更多）；其余页面为普通路由。
- 未配置服务器时重定向到 `/servers/setup`。
- 同一模块内静态段路由必须声明在动态段之前（如 `/projects/create` 排在
  `/projects/:id` 之前），否则会被路径参数吞掉。
- 新增模块后同时在 `core/pages/more_page.dart` 的 `kMoreGroups` 里挂入口。
- 页面转场固定为 `PredictiveBackPageTransitionsBuilder`（`core/theme/theme.dart`），
  依赖 manifest 的 `android:enableOnBackInvokedCallback="true"`；返回拦截一律用
  `PopScope` 的前置 `canPop`，运行时才决定放行会让预测性返回失效。

## 代码规范

- 所有接口路径、请求/响应字段必须以克隆的源码为准：
  路由定义 `/home/akuma/.claude/jobs/069b6afa/tmp/panel/internal/route/*.go`（每条路由的 Summary/Request/Response 注释即文档），
  前端调用参考 `/home/akuma/.claude/jobs/069b6afa/tmp/panel/web/src/api/`。
- 认证细节见 `docs/acepanel-api.md`。
- 列表页统一：下拉刷新、分页（面板接口分页参数以源码为准，常见 `page`/`limit`）、
  错误用 core/widgets/error_view 展示并可重试；危险操作用 confirm_dialog 二次确认。
- 任何要离开安全存储的凭据（目前只有「配置备份」）必须先经
  `core/crypto/secret_box.dart` 用用户口令加密；该文件的 AES / PBKDF2 由
  `test/core/crypto_test.dart` 的官方向量锁定，不要在没有向量验证的情况下改动。
- Material 3，颜色从 Theme 取，不硬编码；动效时长 / 曲线同理，从 `core/theme/motion.dart`
  的 `AppMotion` 取，并用 `AppMotion.resolve` 适配系统「移除动画」设置。
  内容整体替换用 `core/widgets/fade_switch.dart` 的 `FadeSwitch`，
  条件出现与展开 / 收起用 `core/widgets/animated_reveal.dart` 的
  `AnimatedReveal` / `ExpandChevron`。
- 时间：面板返回带时区偏移的 RFC3339，`DateTime.parse` 得到 `isUtc=true` 的实例，
  展示前必须 `.toLocal()`；Go 零值时间（year <= 1）按 null 处理。
- 新 SDK（Flutter 3.44）已废弃的 API 一律不用：`withOpacity`（用 `withValues`）、
  `DropdownButtonFormField.value`（用 `initialValue`）、`Radio` 的
  `groupValue`/`onChanged`（用 `RadioGroup`）、`ReorderableListView.onReorder`
  （用 `onReorderItem`）。`dart analyze lib` 必须零 issue。
- 不要修改 core/ 与其他 feature 的文件；只写自己目录内的文件
  （集成阶段除外）。
