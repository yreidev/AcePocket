import 'package:go_router/go_router.dart';

import 'pages/about_page.dart';
import 'pages/logs_page.dart';
import 'pages/panel_cert_page.dart';
import 'pages/settings_page.dart';
import 'pages/task_detail_page.dart';
import 'pages/tasks_page.dart';
import 'pages/tokens_page.dart';

/// 「设置与令牌」模块路由。
///
/// - `/settings`        —— 面板设置（名称 / 端口 / 入口 / 语言 / 安全 / HTTPS / 便签）；
/// - `/settings/tokens` —— API 令牌管理（列表 / 创建 / 编辑 / 删除）；
/// - `/settings/cert`   —— 面板 HTTPS 证书（查看 / 更新证书与私钥、重新签发）；
/// - `/tasks`           —— 任务中心（异步任务列表）；
/// - `/tasks/:id`       —— 任务详情与日志；
/// - `/logs`            —— 面板日志（操作 / 数据库 / HTTP / SSH 登录）；
/// - `/about`           —— 关于（App 与面板版本信息、开源地址）。
final List<RouteBase> settingsRoutes = [
  GoRoute(
    path: '/settings',
    builder: (context, state) => const SettingsPage(),
    routes: [
      GoRoute(path: 'tokens', builder: (context, state) => const TokensPage()),
      GoRoute(path: 'cert', builder: (context, state) => const PanelCertPage()),
    ],
  ),
  GoRoute(
    path: '/tasks',
    builder: (context, state) => const TasksPage(),
    routes: [
      GoRoute(
        path: ':id',
        builder: (context, state) => TaskDetailPage(
          taskId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
        ),
      ),
    ],
  ),
  GoRoute(path: '/logs', builder: (context, state) => const LogsPage()),
  GoRoute(path: '/about', builder: (context, state) => const AboutPage()),
];
