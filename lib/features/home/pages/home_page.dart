import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/storage/server_store.dart';
import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/app_snack.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/empty_view.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_view.dart';
import '../providers/home_providers.dart';
import '../widgets/count_info_card.dart';
import '../widgets/disk_card.dart';
import '../widgets/home_apps_card.dart';
import '../widgets/home_banners.dart';
import '../widgets/load_card.dart';
import '../widgets/network_card.dart';
import '../widgets/quick_entry_grid.dart';
import '../widgets/resource_overview_card.dart';
import '../widgets/system_info_card.dart';
import '../widgets/top_processes_card.dart';

/// 首页（概览 tab）。
///
/// 由外壳的底部导航直接使用，不注册独立路由（见 `routes.dart`）。
/// 实时数据每 3 秒轮询一次（[homeRealtimeProvider]），下拉可立即刷新全部数据。
class HomePage extends ConsumerWidget {
  const HomePage({super.key, this.quickEntries = kDefaultQuickEntries});

  /// 快捷入口宫格内容；外壳可按实际注册的路由覆盖。
  final List<QuickEntry> quickEntries;

  Future<void> _refreshAll(WidgetRef ref) async {
    ref.invalidate(panelInfoProvider);
    ref.invalidate(systemInfoProvider);
    ref.invalidate(countInfoProvider);
    ref.invalidate(healthProvider);
    ref.invalidate(homeAppsProvider);
    ref.invalidate(panelUpdateProvider);
    ref.invalidate(topProcessesProvider);
    await ref.read(homeRealtimeProvider.notifier).refreshNow();
  }

  Future<void> _restartPanel(BuildContext context, WidgetRef ref) async {
    final ok = await showConfirmDialog(
      context,
      title: '重启面板',
      content: '重启期间面板将短暂无法访问，网站与服务不受影响。确定继续吗？',
      confirmText: '重启面板',
      danger: true,
    );
    if (!ok) return;
    try {
      await ref.read(homeRepoProvider).restartPanel();
      if (!context.mounted) return;
      showSuccessSnack(context, '重启指令已下发，面板重启完成后下拉刷新即可');
    } catch (e) {
      // 网络层异常（超时 / 证书）不是 ApiException，此前会漏掉、静默失败。
      if (!context.mounted) return;
      showErrorSnack(context, e);
    }
  }

  Future<void> _restartServer(BuildContext context, WidgetRef ref) async {
    final ok = await showConfirmDialog(
      context,
      title: '重启服务器',
      content: '将立即重启整台服务器，所有网站、数据库与容器都会中断。确定继续吗？',
      confirmText: '重启服务器',
      danger: true,
    );
    if (!ok) return;
    try {
      await ref.read(homeRepoProvider).restartServer();
      if (!context.mounted) return;
      showSuccessSnack(context, '重启指令已下发，服务器即将重启');
    } catch (e) {
      if (!context.mounted) return;
      showErrorSnack(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final server = ref.watch(activeServerProvider);

    if (server == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('概览')),
        body: EmptyView(
          message: '还没有配置任何服务器\n添加后即可查看面板实时状态',
          icon: Icons.dns_outlined,
          action: FilledButton.icon(
            onPressed: () => context.go('/servers/setup'),
            icon: const Icon(Icons.add),
            label: const Text('添加服务器'),
          ),
        ),
      );
    }

    final panelName = ref.watch(panelInfoProvider).valueOrNull?.name;
    final realtime = ref.watch(homeRealtimeProvider);
    final systemInfo = ref.watch(systemInfoProvider).valueOrNull;
    final state = realtime.valueOrNull;

    Widget body;
    if (state != null) {
      body = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 4, bottom: 24),
        children: [
          const HealthBanner(),
          const PanelUpdateBanner(),
          if (realtime.hasError)
            _StaleHint(error: realtime.error!, theme: theme),
          ResourceOverviewCard(state: state, updatedAt: state.info.time),
          LoadCard(state: state, systemInfo: systemInfo),
          NetworkCard(state: state),
          DiskCard(state: state),
          const CountInfoCard(),
          QuickEntryGrid(entries: quickEntries),
          const HomeAppsCard(),
          const TopProcessesCard(),
          const SystemInfoCard(),
        ],
      );
    } else if (realtime.hasError) {
      body = _fill(
        context,
        ErrorView(
          error: realtime.error!,
          onRetry: () => ref.invalidate(homeRealtimeProvider),
        ),
      );
    } else {
      body = _fill(context, const LoadingView(message: '正在获取实时负载…'));
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              panelName == null || panelName.isEmpty ? 'AcePanel' : panelName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium,
            ),
            Text(
              server.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          A11yIconButton(
            icon: const Icon(Icons.insights_rounded),
            tooltip: '查看历史监控图表',
            onPressed: () => context.push('/monitor'),
          ),
          PopupMenuButton<String>(
            tooltip: '打开更多操作菜单',
            onSelected: (value) {
              switch (value) {
                case 'refresh':
                  _refreshAll(ref);
                  break;
                case 'servers':
                  context.push('/servers');
                  break;
                case 'panel_update':
                  context.push('/panel/update');
                  break;
                case 'panel_runtime':
                  context.push('/panel/runtime');
                  break;
                case 'restart_panel':
                  _restartPanel(context, ref);
                  break;
                case 'restart_server':
                  _restartServer(context, ref);
                  break;
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'refresh',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.refresh),
                  title: Text('刷新'),
                ),
              ),
              PopupMenuItem(
                value: 'servers',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.dns_outlined),
                  title: Text('服务器管理'),
                ),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: 'panel_update',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.system_update_alt_rounded),
                  title: Text('面板升级'),
                ),
              ),
              PopupMenuItem(
                value: 'panel_runtime',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.bug_report_outlined),
                  title: Text('运行时诊断'),
                ),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: 'restart_panel',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.restart_alt),
                  title: Text('重启面板'),
                ),
              ),
              PopupMenuItem(
                value: 'restart_server',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.power_settings_new),
                  title: Text('重启服务器'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(onRefresh: () => _refreshAll(ref), child: body),
    );
  }

  /// 让 loading / error 视图也能被下拉刷新。
  Widget _fill(BuildContext context, Widget child) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.6,
          child: Center(child: child),
        ),
      ],
    );
  }
}

/// 轮询失败但仍有历史数据时的轻提示（不打断页面）。
class _StaleHint extends StatelessWidget {
  const _StaleHint({required this.error, required this.theme});

  final Object error;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final message = describeError(error);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.cloud_off_rounded,
            size: 16,
            color: theme.colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '实时数据刷新失败：$message',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
