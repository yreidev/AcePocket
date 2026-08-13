import 'package:go_router/go_router.dart';

import 'pages/monitor_page.dart';
import 'pages/panel_update_page.dart';
import 'pages/runtime_info_page.dart';

export 'pages/home_page.dart' show HomePage;
export 'widgets/quick_entry_grid.dart' show QuickEntry, kDefaultQuickEntries;

/// 「仪表盘与监控」模块路由。
///
/// - `HomePage` 由外壳的底部导航直接作为「首页」tab 使用，**不注册独立路由**，
///   通过本文件的 `export` 提供给外壳；
/// - `/monitor` —— 历史监控图表页（时间范围切换、监控设置、清空数据）；
/// - `/panel/update` —— 面板升级（更新日志 + WebSocket 实时升级进度）；
/// - `/panel/runtime` —— 运行时诊断（Go 运行时统计 + 协程堆栈）。
final List<RouteBase> homeRoutes = [
  GoRoute(path: '/monitor', builder: (context, state) => const MonitorPage()),
  GoRoute(
    path: '/panel/update',
    name: 'panelUpdate',
    builder: (context, state) => const PanelUpdatePage(),
  ),
  GoRoute(
    path: '/panel/runtime',
    name: 'panelRuntime',
    builder: (context, state) => const RuntimeInfoPage(),
  ),
];
