import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'pages/environment_list_page.dart';
import 'pages/php_config_editor_page.dart';
import 'pages/php_config_tune_page.dart';
import 'pages/php_environment_page.dart';
import 'pages/php_info_page.dart';
import 'pages/runtime_environment_page.dart';

/// 运行环境模块路由。
///
/// - `/environments`
///   —— 运行环境列表：按类型分组 / 筛选，安装、更新、卸载；
/// - `/environments/php/:version`
///   —— PHP 管理（概览 / 扩展 / 负载）；
/// - `/environments/php/:version/tune`
///   —— PHP 参数调优（php.ini + php-fpm.conf 逐项）；
/// - `/environments/php/:version/config?target=ini|fpm`
///   —— 直接编辑 php.ini 或 php-fpm.conf 原文；
/// - `/environments/php/:version/phpinfo`
///   —— phpinfo 展示；
/// - `/environments/runtime/:type/:slug`
///   —— Go / Java / Node.js / Python / .NET 管理
///   （设为命令行默认版本、代理 / 镜像源、安装状态与安装 / 更新 / 卸载）。
///
/// PHP 与其他环境走不同前缀（`php/` 与 `runtime/`），避免动态段互相遮蔽。
final List<RouteBase> environmentRoutes = <RouteBase>[
  GoRoute(
    path: '/environments',
    builder: (BuildContext context, GoRouterState state) =>
        const EnvironmentListPage(),
    routes: <RouteBase>[
      GoRoute(
        path: 'php/:version',
        builder: (BuildContext context, GoRouterState state) =>
            PhpEnvironmentPage(version: _phpVersion(state)),
        routes: <RouteBase>[
          GoRoute(
            path: 'tune',
            builder: (BuildContext context, GoRouterState state) =>
                PhpConfigTunePage(version: _phpVersion(state)),
          ),
          GoRoute(
            path: 'config',
            builder: (BuildContext context, GoRouterState state) =>
                PhpConfigEditorPage(
                  version: _phpVersion(state),
                  fpm: state.uri.queryParameters['target'] == 'fpm',
                ),
          ),
          GoRoute(
            path: 'phpinfo',
            builder: (BuildContext context, GoRouterState state) =>
                PhpInfoPage(version: _phpVersion(state)),
          ),
        ],
      ),
      GoRoute(
        path: 'runtime/:type/:slug',
        builder: (BuildContext context, GoRouterState state) =>
            RuntimeEnvironmentPage(
              type: state.pathParameters['type'] ?? '',
              slug: state.pathParameters['slug'] ?? '',
            ),
      ),
    ],
  ),
];

/// 从路径参数解析 PHP 版本号（面板用无点写法，如 `83` 表示 8.3）。
int _phpVersion(GoRouterState state) =>
    int.tryParse(state.pathParameters['version'] ?? '') ?? 0;
