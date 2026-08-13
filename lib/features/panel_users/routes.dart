import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'pages/panel_users_page.dart';
import 'pages/passkey_page.dart';

/// 面板用户模块路由。
///
/// - `/panel-users`：面板用户列表（新建 / 改用户名、邮箱、密码 / 两步验证 / 删除）
/// - `/panel-users/passkey`：通行密钥管理（查看与停用；注册需在网页端完成）
///   可选 query 参数 `user_id`，从用户列表跳转时带入。
final List<RouteBase> panelUsersRoutes = <RouteBase>[
  GoRoute(
    path: '/panel-users',
    builder: (BuildContext context, GoRouterState state) =>
        const PanelUsersPage(),
    routes: <RouteBase>[
      GoRoute(
        path: 'passkey',
        builder: (BuildContext context, GoRouterState state) => PasskeyPage(
          initialUserId: int.tryParse(
            state.uri.queryParameters['user_id'] ?? '',
          ),
        ),
      ),
    ],
  ),
];
