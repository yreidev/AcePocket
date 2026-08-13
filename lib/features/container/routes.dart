import 'package:go_router/go_router.dart';

import 'pages/compose_detail_page.dart';
import 'pages/compose_list_page.dart';
import 'pages/container_detail_page.dart';
import 'pages/container_list_page.dart';
import 'pages/container_logs_page.dart';
import 'pages/image_list_page.dart';
import 'pages/network_list_page.dart';
import 'pages/volume_list_page.dart';

/// 「容器管理」模块路由。
///
/// 子路径与面板后端保持一致（`/api/container` 下的 `/image`、`/network`、
/// `/volume`、`/compose`）：
///
/// - `/containers`                    —— 容器列表（启停 / 重启 / 删除 / 搜索）；
/// - `/containers/image`              —— 镜像管理（拉取 / 删除 / 清理）；
/// - `/containers/network`            —— 网络管理（创建 / 删除 / 清理）；
/// - `/containers/volume`             —— 存储卷管理（创建 / 删除 / 清理）；
/// - `/containers/compose`            —— 编排管理（新建 / 启停 / 删除）；
/// - `/containers/compose/:name`      —— 编排详情（查看 / 编辑 / 启停 / 删除）；
/// - `/containers/:id`                —— 容器详情；
/// - `/containers/:id/logs`           —— 容器实时日志（WebSocket）。
///
/// 注意：静态子路由（image / network / volume / compose）必须声明在
/// 动态段 `:id` **之前**，否则 `/containers/image` 会被 `:id` 抢先匹配。
final List<RouteBase> containerRoutes = [
  GoRoute(
    path: '/containers',
    name: 'containers',
    builder: (context, state) => const ContainerListPage(),
    routes: [
      GoRoute(
        path: 'image',
        name: 'containerImages',
        builder: (context, state) => const ImageListPage(),
      ),
      GoRoute(
        path: 'network',
        name: 'containerNetworks',
        builder: (context, state) => const NetworkListPage(),
      ),
      GoRoute(
        path: 'volume',
        name: 'containerVolumes',
        builder: (context, state) => const VolumeListPage(),
      ),
      GoRoute(
        path: 'compose',
        name: 'containerComposes',
        builder: (context, state) => const ComposeListPage(),
        routes: [
          GoRoute(
            path: ':name',
            name: 'containerComposeDetail',
            builder: (context, state) =>
                ComposeDetailPage(name: state.pathParameters['name'] ?? ''),
          ),
        ],
      ),
      GoRoute(
        path: ':id',
        name: 'containerDetail',
        builder: (context, state) =>
            ContainerDetailPage(id: state.pathParameters['id'] ?? ''),
        routes: [
          GoRoute(
            path: 'logs',
            name: 'containerLogs',
            builder: (context, state) =>
                ContainerLogsPage(id: state.pathParameters['id'] ?? ''),
          ),
        ],
      ),
    ],
  ),
];
