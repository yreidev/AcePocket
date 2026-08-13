import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/app_settings/repo/app_settings_store.dart';
import '../../features/app_settings/routes.dart';
import '../../features/apps/routes.dart';
import '../../features/cert/routes.dart';
import '../../features/container/routes.dart';
import '../../features/cron_backup/routes.dart';
import '../../features/database/routes.dart';
import '../../features/environment/routes.dart';
import '../../features/files/routes.dart';
import '../../features/home/routes.dart';
import '../../features/migration/routes.dart';
import '../../features/notify_alert/routes.dart';
import '../../features/panel_users/routes.dart';
import '../../features/project_template/routes.dart';
import '../../features/security/routes.dart';
import '../../features/servers/routes.dart';
import '../../features/settings/routes.dart';
import '../../features/ssh_hosts/routes.dart';
import '../../features/terminal/routes.dart';
import '../../features/toolbox_disk/routes.dart';
import '../../features/toolbox_misc/routes.dart';
import '../../features/website/routes.dart';
import '../pages/more_page.dart';
import '../storage/server_store.dart';
import '../theme/motion.dart';
import '../widgets/error_view.dart';

/// 应用路由表。
///
/// 结构：
/// - `StatefulShellRoute.indexedStack` 提供带底部导航的三个 tab
///   （`/` 首页、`/websites` 网站、`/more` 更多），每个 tab 各有独立导航栈；
/// - 其余功能页面均为**顶层普通路由**，`push` 后全屏覆盖底部导航；
/// - 未配置服务器时统一重定向到 `/servers/setup`（`/servers*` 自身豁免，避免死循环）。
///
/// 各 feature 的路由集中在其 `routes.dart` 中导出为 `<camelKey>Routes`，
/// 本文件只做聚合，不重复声明路径。
///
/// ### 完整路由表
///
/// | 路径 | 页面 |
/// | --- | --- |
/// | `/`                            | 首页 / 仪表盘（tab） |
/// | `/websites`                    | 网站列表（tab） |
/// | `/more`                        | 更多（tab） |
/// | `/servers/setup`               | 初次配置引导 |
/// | `/servers/edit`                | 添加 / 编辑服务器 |
/// | `/servers`                     | 服务器管理 |
/// | `/monitor`                     | 历史监控 |
/// | `/panel/update`                | 面板升级（WS 实时日志） |
/// | `/panel/runtime`               | 运行时诊断（runtime / 协程堆栈） |
/// | `/websites/create`             | 创建网站 |
/// | `/websites/settings`           | 网站默认设置 |
/// | `/websites/:id/stats`          | 网站访问统计 |
/// | `/websites/:id`                | 网站详情与配置 |
/// | `/databases`                   | 数据库 |
/// | `/databases/servers`           | 数据库服务器 |
/// | `/databases/users`             | 数据库用户 |
/// | `/databases/redis`             | Redis 管理 |
/// | `/databases/elasticsearch`     | Elasticsearch 管理 |
/// | `/files`                       | 文件管理 |
/// | `/files/edit`                  | 文件编辑器 |
/// | `/files/shares`                | 文件分享 |
/// | `/containers`                  | 容器列表 |
/// | `/containers/image`            | 镜像管理 |
/// | `/containers/network`          | 网络管理 |
/// | `/containers/volume`           | 存储卷管理 |
/// | `/containers/compose`          | 编排管理 |
/// | `/containers/compose/:name`    | 编排详情 |
/// | `/containers/:id`              | 容器详情 |
/// | `/containers/:id/logs`         | 容器实时日志 |
/// | `/certs`                       | SSL 证书 |
/// | `/certs/create`                | 申请证书 |
/// | `/certs/upload`                | 上传证书 |
/// | `/certs/dns`                   | DNS 账号 |
/// | `/certs/dns/create`            | 新建 DNS 账号 |
/// | `/certs/dns/:id/edit`          | 编辑 DNS 账号 |
/// | `/certs/accounts`              | CA 账户 |
/// | `/certs/accounts/create`       | 新建 CA 账户 |
/// | `/certs/accounts/:id/edit`     | 编辑 CA 账户 |
/// | `/certs/:id/edit`              | 编辑证书 |
/// | `/certs/:id/obtain`            | 签发 / 续签证书 |
/// | `/crons`                       | 计划任务 |
/// | `/crons/edit`                  | 新建 / 编辑计划任务 |
/// | `/crons/log`                   | 任务日志 |
/// | `/crons/run`                   | 立即执行任务 |
/// | `/backups`                     | 备份管理 |
/// | `/backups/storages`            | 备份存储 |
/// | `/backups/storages/edit`       | 新建 / 编辑备份存储 |
/// | `/firewall`                    | 防火墙 |
/// | `/firewall/scan`               | 扫描感知 |
/// | `/firewall/export`             | 导出端口规则 |
/// | `/firewall/import`             | 导入端口规则 |
/// | `/security`                    | 面板安全 |
/// | `/security/ssh`                | SSH 服务 |
/// | `/security/tamper`             | 防篡改 |
/// | `/terminal`                    | 终端（`?ssh=` / `?container=` / `?command=`） |
/// | `/ssh-hosts`                   | SSH 主机 |
/// | `/ssh-hosts/new`               | 新建 SSH 主机 |
/// | `/ssh-hosts/:id/edit`          | 编辑 SSH 主机 |
/// | `/ssh-hosts/:id/files`         | SSH 主机文件浏览（id=0 为面板本机） |
/// | `/apps`                        | 应用商店 |
/// | `/systemctl`                   | 系统服务 |
/// | `/processes`                   | 进程管理 |
/// | `/environments`                | 运行环境 |
/// | `/environments/php/:version`   | PHP 管理 |
/// | `/environments/php/:version/tune`    | PHP 参数调优 |
/// | `/environments/php/:version/config`  | PHP 配置文件编辑（`?target=ini\|fpm`） |
/// | `/environments/php/:version/phpinfo` | phpinfo |
/// | `/environments/runtime/:type/:slug`  | Go / Java / Node.js / Python / .NET |
/// | `/projects`                    | 项目（systemd） |
/// | `/projects/create`             | 新建项目 |
/// | `/projects/:id`                | 项目详情 |
/// | `/projects/:id/edit`           | 编辑项目 |
/// | `/templates`                   | 应用模板 |
/// | `/templates/:slug`             | 模板详情 |
/// | `/templates/:slug/deploy`      | 部署模板 |
/// | `/toolbox/disk`                | 磁盘管理（磁盘 / LVM / 自动挂载） |
/// | `/toolbox/disk/smart`          | SMART 健康 |
/// | `/toolbox/disk/raid`           | RAID 阵列 |
/// | `/toolbox/system`              | 系统工具（DNS / SWAP / 时间 / NTP / 主机名） |
/// | `/toolbox/system/hosts`        | hosts 文件编辑 |
/// | `/toolbox/logs`                | 日志清理 |
/// | `/toolbox/network`             | 网络连接 |
/// | `/toolbox/benchmark`           | 服务器跑分 |
/// | `/alerts`                      | 告警（规则 + 记录） |
/// | `/alerts/rules/new`            | 新建告警规则 |
/// | `/alerts/rules/:id/edit`       | 编辑告警规则 |
/// | `/notify`                      | 通知（渠道 + 事件） |
/// | `/notify/channels/new`         | 新建通知渠道 |
/// | `/notify/channels/:id/edit`    | 编辑通知渠道 |
/// | `/webhooks`                    | WebHook |
/// | `/webhooks/new`                | 新建 WebHook |
/// | `/webhooks/:id/edit`           | 编辑 WebHook |
/// | `/migration`                   | 面板迁移向导 |
/// | `/migration/results`           | 迁移结果与日志 |
/// | `/panel-users`                 | 面板用户 |
/// | `/panel-users/passkey`         | 通行密钥 |
/// | `/settings`                    | 面板设置 |
/// | `/settings/tokens`             | API 令牌 |
/// | `/settings/cert`               | 面板证书 |
/// | `/tasks`                       | 任务中心 |
/// | `/tasks/:id`                   | 任务详情与日志 |
/// | `/logs`                        | 面板日志 |
/// | `/about`                       | 关于 |
/// | `/app-settings`                | 应用设置（App 本地偏好） |
final routerProvider = Provider<GoRouter>((ref) {
  // 服务器配置变化时让 GoRouter 重新求值 redirect。
  // 注意：这里刻意不用 ref.watch —— 重建 GoRouter 会丢失整个导航栈。
  final refresh = _RouterRefreshNotifier();
  ref.listen(activeServerProvider, (_, __) => refresh.refresh());
  ref.listen(serverListProvider, (_, __) => refresh.refresh());
  ref.onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    // 启动时默认打开的 tab 由「应用设置」配置；main() 中已 await
    // AppSettingsStore.init()，此处可同步读取。
    initialLocation: AppSettingsStore.instance.startupTab.path,
    refreshListenable: refresh,
    redirect: (context, state) => _redirect(ref, state),
    errorBuilder: (context, state) =>
        _UnknownRoutePage(location: state.uri.toString()),
    routes: <RouteBase>[
      _shellRoute,
      // 服务器接入与管理（含 /servers/setup —— redirect 的目标，必须始终可达）。
      ...serversRoutes,
      // 仪表盘模块只注册 /monitor；首页由 shell 直接使用 HomePage。
      ...homeRoutes,
      // 网站模块的 /websites 由 shell 注册；这里是创建 / 详情 / 统计等子页。
      ...websiteRoutes,
      ...databaseRoutes,
      ...filesRoutes,
      ...containerRoutes,
      ...certRoutes,
      ...cronBackupRoutes,
      ...securityRoutes,
      ...terminalRoutes,
      ...sshHostsRoutes,
      ...appsRoutes,
      ...environmentRoutes,
      ...projectTemplateRoutes,
      ...toolboxDiskRoutes,
      ...toolboxMiscRoutes,
      ...notifyAlertRoutes,
      ...migrationRoutes,
      ...panelUsersRoutes,
      ...settingsRoutes,
      // App 本地设置（本机偏好），不依赖面板。
      ...appSettingsRoutes,
    ],
  );
});

// ---------------------------------------------------------------------------
// 底部导航（StatefulShellRoute）
// ---------------------------------------------------------------------------

/// 根导航器 Key。
///
/// 除 GoRouter 自身外，还供需要在「任意位置」弹出全局对话框的场景取用
/// （如 WS 会话登录的两步验证弹窗，见
/// `features/panel_users/widgets/two_factor_prompt.dart`）。
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'root',
);
final GlobalKey<NavigatorState> _homeTabKey = GlobalKey<NavigatorState>(
  debugLabel: 'tab-home',
);
final GlobalKey<NavigatorState> _websiteTabKey = GlobalKey<NavigatorState>(
  debugLabel: 'tab-website',
);
final GlobalKey<NavigatorState> _moreTabKey = GlobalKey<NavigatorState>(
  debugLabel: 'tab-more',
);

/// 首页快捷入口：路径与本文件聚合的真实路由一一对应。
///
/// `/websites` 是底部导航 tab 的分支根路由，只能用 `go` 切换（`isTab: true`）。
const List<QuickEntry> _quickEntries = <QuickEntry>[
  QuickEntry(
    label: '网站',
    icon: Icons.language_rounded,
    path: '/websites',
    isTab: true,
  ),
  QuickEntry(label: '数据库', icon: Icons.storage_rounded, path: '/databases'),
  QuickEntry(label: '文件', icon: Icons.folder_outlined, path: '/files'),
  QuickEntry(label: '容器', icon: Icons.widgets_outlined, path: '/containers'),
  QuickEntry(label: '计划任务', icon: Icons.schedule_rounded, path: '/crons'),
  QuickEntry(label: '备份', icon: Icons.backup_outlined, path: '/backups'),
  QuickEntry(label: '证书', icon: Icons.verified_user_outlined, path: '/certs'),
  QuickEntry(label: '应用', icon: Icons.apps_rounded, path: '/apps'),
  QuickEntry(label: '终端', icon: Icons.terminal_rounded, path: '/terminal'),
  QuickEntry(
    label: '防火墙',
    icon: Icons.local_fire_department_outlined,
    path: '/firewall',
  ),
  QuickEntry(label: '监控', icon: Icons.insights_rounded, path: '/monitor'),
  QuickEntry(label: '任务', icon: Icons.task_alt_rounded, path: '/tasks'),
];

final StatefulShellRoute _shellRoute = StatefulShellRoute.indexedStack(
  builder: (context, state, navigationShell) =>
      _MainShell(navigationShell: navigationShell),
  branches: [
    StatefulShellBranch(
      navigatorKey: _homeTabKey,
      routes: [
        GoRoute(
          path: '/',
          name: 'home',
          builder: (context, state) =>
              const HomePage(quickEntries: _quickEntries),
        ),
      ],
    ),
    StatefulShellBranch(
      navigatorKey: _websiteTabKey,
      routes: [
        GoRoute(
          path: '/websites',
          name: 'websites',
          builder: (context, state) => const WebsiteListPage(),
        ),
      ],
    ),
    StatefulShellBranch(
      navigatorKey: _moreTabKey,
      routes: [
        GoRoute(
          path: '/more',
          name: 'more',
          builder: (context, state) => const MorePage(),
        ),
      ],
    ),
  ],
);

/// 底部导航外壳：三个 tab 各自保留独立导航栈（IndexedStack）。
///
/// 切换 tab 不会产生可回退的路由（goBranch 是切换分支而非压栈），因此系统返回
/// 手势/返回键在非首个 tab 上会直接退出应用。这里维护一份 tab 访问历史，
/// 返回时先逐个回到上一个访问过的 tab，只有回到栈底 tab 时才交给系统退出。
class _MainShell extends StatefulWidget {
  const _MainShell({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  State<_MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<_MainShell> {
  /// tab 访问历史，末位为当前 tab，栈底为进入应用时所在的 tab。
  final List<int> _history = <int>[];

  @override
  void initState() {
    super.initState();
    _history.add(widget.navigationShell.currentIndex);
  }

  @override
  void didUpdateWidget(covariant _MainShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncHistory();
  }

  /// 以 navigationShell 的实际分支下标为准同步历史。
  ///
  /// 分支可能由底部导航之外的方式切换——「更多」页里指向 tab 的入口用的是
  /// `context.go`，重定向守卫也会改变分支——所以不能只在点击回调里记录。
  /// 已访问过的 tab 会被移到末位，避免历史无限增长。
  void _syncHistory() {
    final index = widget.navigationShell.currentIndex;
    if (_history.isEmpty) {
      _history.add(index);
      return;
    }
    if (_history.last == index) return;
    setState(() {
      _history
        ..remove(index)
        ..add(index);
    });
  }

  void _onDestinationSelected(int index) {
    // 再次点击当前 tab 时回到该 tab 的栈底。
    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }

  void _handlePop(bool didPop, Object? result) {
    if (didPop || _history.length <= 1) return;
    setState(() => _history.removeLast());
    widget.navigationShell.goBranch(_history.last);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // 仅当已回到栈底 tab 时才放行系统返回（退出应用）。
      canPop: _history.length <= 1,
      onPopInvokedWithResult: _handlePop,
      child: _buildScaffold(),
    );
  }

  Widget _buildScaffold() {
    final navigationShell = widget.navigationShell;
    return Scaffold(
      body: _BranchFadeThrough(
        index: navigationShell.currentIndex,
        child: navigationShell,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: _onDestinationSelected,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: '首页',
          ),
          NavigationDestination(
            icon: Icon(Icons.language_outlined),
            selectedIcon: Icon(Icons.language_rounded),
            label: '网站',
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view_rounded),
            label: '更多',
          ),
        ],
      ),
    );
  }
}

/// 底部导航切换 tab 时的入场动效（Material 3 fade-through 的入场段）。
///
/// `StatefulShellRoute.indexedStack` 换分支是瞬时的——[IndexedStack] 只改显示
/// 下标——三个 tab 之间会硬闪。这里**不替换子树**（分支导航栈必须保活，换掉
/// 就等于清空三个 tab 的历史），只在下标变化时对整个 body 跑一次淡入 + 轻微放大。
///
/// [FadeTransition] / [ScaleTransition] 常驻在树上而不是「动画时才包一层」：
/// 结构一旦变化，[StatefulNavigationShell] 会被重新挂载，三个分支的状态全丢。
class _BranchFadeThrough extends StatefulWidget {
  const _BranchFadeThrough({required this.index, required this.child});

  /// 当前分支下标；变化即触发一次入场。
  final int index;

  final Widget child;

  @override
  State<_BranchFadeThrough> createState() => _BranchFadeThroughState();
}

class _BranchFadeThroughState extends State<_BranchFadeThrough>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.tabSwitch,
    // 初始为 1：首帧就是稳定态，启动时不该有淡入。
    value: 1,
  );

  /// 前 40% 是「旧内容已消失」的空档，之后才淡入，符合 fade-through 的时序。
  late final CurvedAnimation _fade = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.4, 1, curve: AppMotion.standard),
  );

  late final CurvedAnimation _scaleCurve = CurvedAnimation(
    parent: _controller,
    curve: AppMotion.enter,
  );

  late final Animation<double> _scale = Tween<double>(
    begin: 0.97,
    end: 1,
  ).animate(_scaleCurve);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 系统开启「移除动画」时时长归零，切换保持瞬时。
    _controller.duration = AppMotion.resolve(context, AppMotion.tabSwitch);
  }

  @override
  void didUpdateWidget(covariant _BranchFadeThrough oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _fade.dispose();
    _scaleCurve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: ScaleTransition(scale: _scale, child: widget.child),
    );
  }
}

// ---------------------------------------------------------------------------
// 重定向守卫
// ---------------------------------------------------------------------------

/// 「服务器接入与管理」相关路径：无论是否已配置服务器都必须可达，
/// 否则重定向会自我循环。
bool _isServerRoute(String location) =>
    location == '/servers' || location.startsWith('/servers/');

/// 未配置服务器时的全局重定向。
///
/// - 一台服务器都没有 → `/servers/setup`（初次配置引导）；
/// - 有服务器但未选中当前服务器 → `/servers`（去列表里选一台）。
String? _redirect(Ref ref, GoRouterState state) {
  final location = state.matchedLocation;
  if (_isServerRoute(location)) return null;

  // ServerStore 在 main() 中已 await init()，此处可同步读取。
  final hasAnyServer = ServerStore.instance.servers.isNotEmpty;
  final hasActiveServer = ref.read(activeServerProvider) != null;
  if (hasAnyServer && hasActiveServer) return null;

  return hasAnyServer ? '/servers' : '/servers/setup';
}

/// 桥接 Riverpod 与 GoRouter 的 `refreshListenable`。
class _RouterRefreshNotifier extends ChangeNotifier {
  bool _disposed = false;

  void refresh() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

// ---------------------------------------------------------------------------
// 未知路由
// ---------------------------------------------------------------------------

class _UnknownRoutePage extends StatelessWidget {
  const _UnknownRoutePage({required this.location});

  final String location;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('页面不存在'),
        actions: [
          TextButton(
            onPressed: () => context.go('/'),
            child: const Text('回到首页'),
          ),
        ],
      ),
      body: ErrorView(error: '找不到页面：$location'),
    );
  }
}
