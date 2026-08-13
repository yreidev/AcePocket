import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'models/ssh_file_info.dart';
import 'pages/ssh_host_form_page.dart';
import 'pages/ssh_hosts_page.dart';
import 'pages/ssh_sftp_page.dart';

/// SSH 主机模块路由。
///
/// - `/ssh-hosts`             主机列表（增删改 + 打开终端 / 文件浏览）
/// - `/ssh-hosts/new`         新建主机
/// - `/ssh-hosts/:id/edit`    编辑主机
/// - `/ssh-hosts/:id/files`   主机 SFTP 文件浏览，`id` 为 0 表示面板本机；
///   可带 `?path=/opt` 指定初始目录。
///
/// 打开终端复用 terminal 模块的 `/terminal?ssh=<主机 id>&title=<名称>`。
final List<RouteBase> sshHostsRoutes = <RouteBase>[
  GoRoute(
    path: '/ssh-hosts',
    builder: (BuildContext context, GoRouterState state) =>
        const SshHostsPage(),
    routes: <RouteBase>[
      // 静态段必须声明在 `:id` 之前，避免 `new` 被当作主机 id。
      GoRoute(
        path: 'new',
        builder: (BuildContext context, GoRouterState state) =>
            const SshHostFormPage(),
      ),
      GoRoute(
        path: ':id/edit',
        builder: (BuildContext context, GoRouterState state) => SshHostFormPage(
          hostId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
        ),
      ),
      GoRoute(
        path: ':id/files',
        builder: (BuildContext context, GoRouterState state) => SshSftpPage(
          hostId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
          initialPath: normalizePath(state.uri.queryParameters['path'] ?? '/'),
        ),
      ),
    ],
  ),
];
