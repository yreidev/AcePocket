import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'pages/alert_page.dart';
import 'pages/alert_rule_form_page.dart';
import 'pages/notify_channel_form_page.dart';
import 'pages/notify_page.dart';
import 'pages/webhook_form_page.dart';
import 'pages/webhook_page.dart';

/// 告警与通知模块路由。
///
/// - `/alerts`                      告警（规则 + 记录）
/// - `/alerts/rules/new`            新建告警规则
/// - `/alerts/rules/:id/edit`       编辑告警规则
/// - `/notify`                      通知（渠道管理 + 事件通知设置）
/// - `/notify/channels/new`         新建通知渠道
/// - `/notify/channels/:id/edit`    编辑通知渠道
/// - `/webhooks`                    WebHook 列表
/// - `/webhooks/new`                新建 WebHook
/// - `/webhooks/:id/edit`           编辑 WebHook
///
/// 字面量子路由（`new`）都声明在参数子路由（`:id`）之前，避免被误匹配。
final List<RouteBase> notifyAlertRoutes = <RouteBase>[
  GoRoute(
    path: '/alerts',
    builder: (BuildContext context, GoRouterState state) => const AlertPage(),
    routes: <RouteBase>[
      GoRoute(
        path: 'rules/new',
        builder: (BuildContext context, GoRouterState state) =>
            const AlertRuleFormPage(),
      ),
      GoRoute(
        path: 'rules/:id/edit',
        builder: (BuildContext context, GoRouterState state) =>
            AlertRuleFormPage(
          ruleId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
        ),
      ),
    ],
  ),
  GoRoute(
    path: '/notify',
    builder: (BuildContext context, GoRouterState state) => const NotifyPage(),
    routes: <RouteBase>[
      GoRoute(
        path: 'channels/new',
        builder: (BuildContext context, GoRouterState state) =>
            const NotifyChannelFormPage(),
      ),
      GoRoute(
        path: 'channels/:id/edit',
        builder: (BuildContext context, GoRouterState state) =>
            NotifyChannelFormPage(
          channelId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
        ),
      ),
    ],
  ),
  GoRoute(
    path: '/webhooks',
    builder: (BuildContext context, GoRouterState state) => const WebhookPage(),
    routes: <RouteBase>[
      GoRoute(
        path: 'new',
        builder: (BuildContext context, GoRouterState state) =>
            const WebhookFormPage(),
      ),
      GoRoute(
        path: ':id/edit',
        builder: (BuildContext context, GoRouterState state) => WebhookFormPage(
          webhookId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
        ),
      ),
    ],
  ),
];
