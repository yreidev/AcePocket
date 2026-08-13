import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/app_snack.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/section_card.dart';
import '../models/firewall_models.dart';
import '../providers/security_providers.dart';
import '../widgets/firewall_dialogs.dart';
import '../widgets/paged_list_view.dart';
import '../widgets/security_tiles.dart';

/// 防火墙页面：总开关 + 端口规则 / IP 规则 / 端口转发三个分页。
class FirewallPage extends ConsumerStatefulWidget {
  const FirewallPage({super.key});

  @override
  ConsumerState<FirewallPage> createState() => _FirewallPageState();
}

class _FirewallPageState extends ConsumerState<FirewallPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(
    length: 3,
    vsync: this,
  );
  bool _togglingFirewall = false;

  /// 新建规则在途标志：请求返回前禁用 FAB，避免连点建出重复规则。
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _tabController.addListener(_onTabChanged);
  }

  @override
  void dispose() {
    _tabController
      ..removeListener(_onTabChanged)
      ..dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _toggleFirewall(bool value) async {
    if (_togglingFirewall) return;
    if (!value) {
      final confirmed = await showConfirmDialog(
        context,
        title: '关闭防火墙？',
        content: '关闭后服务器所有端口将不再受防火墙保护，确定继续？',
        confirmText: '关闭',
        danger: true,
      );
      if (!confirmed || !mounted) return;
    }
    setState(() => _togglingFirewall = true);
    try {
      await ref.read(securityRepoProvider).updateFirewallStatus(value);
      ref.invalidate(firewallStatusProvider);
      if (!mounted) return;
      showSuccessSnack(context, value ? '防火墙已开启' : '防火墙已关闭');
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _togglingFirewall = false);
    }
  }

  void _refreshCurrentTab() {
    switch (_tabController.index) {
      case 0:
        ref.invalidate(firewallRulesProvider);
      case 1:
        ref.invalidate(firewallIpRulesProvider);
      case 2:
        ref.invalidate(firewallForwardsProvider);
    }
    ref.invalidate(firewallStatusProvider);
  }

  Future<void> _create() async {
    if (_creating) return;
    final repo = ref.read(securityRepoProvider);
    try {
      switch (_tabController.index) {
        case 0:
          final portRule = await showFirewallRuleSheet(context);
          if (portRule == null || !mounted) return;
          setState(() => _creating = true);
          await repo.createFirewallRule(
            family: portRule.family,
            protocol: portRule.protocol,
            portStart: portRule.portStart,
            portEnd: portRule.portEnd,
            address: portRule.address,
            strategy: portRule.strategy,
            direction: portRule.direction,
          );
          ref.invalidate(firewallRulesProvider);
        case 1:
          final ipRule = await showFirewallIpRuleSheet(context);
          if (ipRule == null || !mounted) return;
          setState(() => _creating = true);
          await repo.createFirewallIpRule(ipRule);
          ref.invalidate(firewallIpRulesProvider);
        case 2:
          final forward = await showFirewallForwardSheet(context);
          if (forward == null || !mounted) return;
          setState(() => _creating = true);
          await repo.createFirewallForward(forward);
          ref.invalidate(firewallForwardsProvider);
      }
      if (!mounted) return;
      showSuccessSnack(context, '规则已创建');
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, e);
    } finally {
      if (mounted && _creating) setState(() => _creating = false);
    }
  }

  String get _fabLabel => switch (_tabController.index) {
    0 => '新建端口规则',
    1 => '新建 IP 规则',
    _ => '新建转发',
  };

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(firewallStatusProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('防火墙'),
        actions: [
          A11yIconButton(
            tooltip: '刷新当前分页',
            icon: const Icon(Icons.refresh),
            onPressed: _refreshCurrentTab,
          ),
          PopupMenuButton<String>(
            tooltip: '更多防火墙操作',
            onSelected: (value) async {
              switch (value) {
                case 'scan':
                  unawaited(context.push('/firewall/scan'));
                case 'export':
                  unawaited(context.push('/firewall/export'));
                case 'import':
                  await context.push('/firewall/import');
                  // 导入可能新增了规则，返回后刷新端口规则列表。
                  ref.invalidate(firewallRulesProvider);
                case 'security':
                  unawaited(context.push('/security'));
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'export', child: Text('导出端口规则')),
              PopupMenuItem(value: 'import', child: Text('导入端口规则')),
              PopupMenuDivider(),
              PopupMenuItem(value: 'scan', child: Text('扫描感知')),
              PopupMenuItem(value: 'security', child: Text('面板安全设置')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          SectionCard(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: status.when(
              data: (running) => SettingSwitchTile(
                title: '系统防火墙',
                subtitle: running ? '运行中，规则已生效' : '已停止，所有端口未受保护',
                icon: Icons.security_outlined,
                value: running,
                busy: _togglingFirewall,
                onChanged: _toggleFirewall,
              ),
              loading: () => const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.security_outlined),
                title: Text('系统防火墙'),
                subtitle: Text('状态获取中…'),
                trailing: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              error: (error, _) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.error_outline,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: const Text('系统防火墙'),
                subtitle: Text(
                  describeError(error),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: A11yIconButton(
                  tooltip: '重新获取防火墙状态',
                  icon: const Icon(Icons.refresh),
                  onPressed: () => ref.invalidate(firewallStatusProvider),
                ),
              ),
            ),
          ),
          TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: '端口规则'),
              Tab(text: 'IP 规则'),
              Tab(text: '端口转发'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [_PortRuleTab(), _IpRuleTab(), _ForwardTab()],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _creating ? null : _create,
        icon: _creating
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add),
        label: Text(_creating ? '创建中…' : _fabLabel),
      ),
    );
  }
}

// --------------------------------------------------------------------- 端口规则

class _PortRuleTab extends ConsumerStatefulWidget {
  const _PortRuleTab();

  @override
  ConsumerState<_PortRuleTab> createState() => _PortRuleTabState();
}

class _PortRuleTabState extends ConsumerState<_PortRuleTab> {
  /// 正在删除的规则标识（网站列表 `_busyId` 模式）：
  /// 该行按钮禁用并显示进度，防止在途时二次点出确认框重复提交。
  String? _busyKey;

  /// 规则无服务端 id，用全部业务字段拼出行标识。
  String _keyOf(FirewallRule rule) =>
      '${rule.family}/${rule.protocol}/${rule.portStart}-${rule.portEnd}/'
      '${rule.address}/${rule.strategy}/${rule.direction}';

  Future<void> _delete(FirewallRule rule) async {
    if (_busyKey != null) return;
    final confirmed = await showConfirmDialog(
      context,
      title: '删除端口规则？',
      content:
          '${FirewallLabels.protocol(rule.protocol)} ${rule.portLabel} '
          '（${FirewallLabels.direction(rule.direction)}·'
          '${FirewallLabels.strategy(rule.strategy)}）将被移除。',
      confirmText: '删除',
      danger: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _busyKey = _keyOf(rule));
    try {
      await ref.read(securityRepoProvider).deleteFirewallRule(rule);
      ref.invalidate(firewallRulesProvider);
      if (!mounted) return;
      showSuccessSnack(context, '端口规则已删除');
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busyKey = null);
    }
  }

  void _showUsage(FirewallRule rule) {
    showPortUsageDialog(
      context,
      port: rule.portStart,
      protocol: rule.protocol == 'udp' ? 'udp' : 'tcp',
      future: ref
          .read(securityRepoProvider)
          .portUsage(rule.portStart, rule.protocol == 'udp' ? 'udp' : 'tcp'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(firewallRulesProvider);
    final notifier = ref.read(firewallRulesProvider.notifier);
    final theme = Theme.of(context);

    return PagedListView<FirewallRule>(
      state: state,
      emptyMessage: '暂无端口规则',
      emptyIcon: Icons.shield_outlined,
      onRetry: () => ref.invalidate(firewallRulesProvider),
      onLoadMore: notifier.loadMore,
      onRefresh: () async {
        try {
          await notifier.refresh();
        } catch (e) {
          if (!context.mounted) return;
          showErrorSnack(context, e);
        }
      },
      itemBuilder: (context, rule, index) {
        final accept = rule.strategy == 'accept';
        final busy = _busyKey == _keyOf(rule);
        return ListTile(
          enabled: !busy,
          leading: Icon(
            rule.direction == 'in' ? Icons.login : Icons.logout,
            color: accept ? theme.colorScheme.primary : theme.colorScheme.error,
          ),
          title: Row(
            children: [
              Flexible(
                child: Text(
                  '${FirewallLabels.protocol(rule.protocol)} ${rule.portLabel}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              TagChip(
                label: FirewallLabels.strategy(rule.strategy),
                color: accept
                    ? theme.colorScheme.primary
                    : theme.colorScheme.error,
              ),
              if (rule.inUse) ...[
                const SizedBox(width: 6),
                TagChip(label: '占用中', color: theme.colorScheme.tertiary),
              ],
            ],
          ),
          subtitle: Text(
            '${FirewallLabels.direction(rule.direction)} · '
            '${FirewallLabels.family(rule.family)} · '
            '来源 ${rule.address.isEmpty ? '不限' : rule.address}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : PopupMenuButton<String>(
                  tooltip: '端口规则操作',
                  onSelected: (value) {
                    switch (value) {
                      case 'usage':
                        _showUsage(rule);
                      case 'delete':
                        _delete(rule);
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'usage', child: Text('查看端口占用')),
                    PopupMenuItem(value: 'delete', child: Text('删除')),
                  ],
                ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------- IP 规则

class _IpRuleTab extends ConsumerStatefulWidget {
  const _IpRuleTab();

  @override
  ConsumerState<_IpRuleTab> createState() => _IpRuleTabState();
}

class _IpRuleTabState extends ConsumerState<_IpRuleTab> {
  /// 正在删除的规则标识：在途时该行按钮禁用，防止二次点出确认框。
  String? _busyKey;

  String _keyOf(FirewallIpRule rule) =>
      '${rule.family}/${rule.protocol}/${rule.address}/'
      '${rule.strategy}/${rule.direction}';

  Future<void> _delete(FirewallIpRule rule) async {
    if (_busyKey != null) return;
    final confirmed = await showConfirmDialog(
      context,
      title: '删除 IP 规则？',
      content:
          '${rule.address} 的'
          '${FirewallLabels.direction(rule.direction)}'
          '${FirewallLabels.strategy(rule.strategy)}规则将被移除。',
      confirmText: '删除',
      danger: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _busyKey = _keyOf(rule));
    try {
      await ref.read(securityRepoProvider).deleteFirewallIpRule(rule);
      ref.invalidate(firewallIpRulesProvider);
      if (!mounted) return;
      showSuccessSnack(context, 'IP 规则已删除');
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busyKey = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(firewallIpRulesProvider);
    final notifier = ref.read(firewallIpRulesProvider.notifier);
    final theme = Theme.of(context);

    return PagedListView<FirewallIpRule>(
      state: state,
      emptyMessage: '暂无 IP 规则',
      emptyIcon: Icons.block_outlined,
      onRetry: () => ref.invalidate(firewallIpRulesProvider),
      onLoadMore: notifier.loadMore,
      onRefresh: () async {
        try {
          await notifier.refresh();
        } catch (e) {
          if (!context.mounted) return;
          showErrorSnack(context, e);
        }
      },
      itemBuilder: (context, rule, index) {
        final accept = rule.strategy == 'accept';
        final busy = _busyKey == _keyOf(rule);
        return ListTile(
          enabled: !busy,
          leading: Icon(
            accept ? Icons.verified_user_outlined : Icons.block,
            color: accept ? theme.colorScheme.primary : theme.colorScheme.error,
          ),
          title: Text(
            rule.address.isEmpty ? '(未指定地址)' : rule.address,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${FirewallLabels.direction(rule.direction)} · '
            '${FirewallLabels.protocol(rule.protocol)} · '
            '${FirewallLabels.family(rule.family)} · '
            '${FirewallLabels.strategy(rule.strategy)}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : A11yIconButton(
                  tooltip: '删除 ${rule.address} 的 IP 规则',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _delete(rule),
                ),
        );
      },
    );
  }
}

// --------------------------------------------------------------------- 端口转发

class _ForwardTab extends ConsumerStatefulWidget {
  const _ForwardTab();

  @override
  ConsumerState<_ForwardTab> createState() => _ForwardTabState();
}

class _ForwardTabState extends ConsumerState<_ForwardTab> {
  /// 正在删除的转发标识：在途时该行按钮禁用，防止二次点出确认框。
  String? _busyKey;

  String _keyOf(FirewallForward forward) =>
      '${forward.protocol}/${forward.port}/'
      '${forward.targetIp}:${forward.targetPort}';

  Future<void> _delete(FirewallForward forward) async {
    if (_busyKey != null) return;
    final confirmed = await showConfirmDialog(
      context,
      title: '删除端口转发？',
      content:
          '${forward.port} → ${forward.targetIp}:${forward.targetPort} '
          '的转发规则将被移除。',
      confirmText: '删除',
      danger: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _busyKey = _keyOf(forward));
    try {
      await ref.read(securityRepoProvider).deleteFirewallForward(forward);
      ref.invalidate(firewallForwardsProvider);
      if (!mounted) return;
      showSuccessSnack(context, '端口转发已删除');
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busyKey = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(firewallForwardsProvider);
    final notifier = ref.read(firewallForwardsProvider.notifier);
    final theme = Theme.of(context);

    return PagedListView<FirewallForward>(
      state: state,
      emptyMessage: '暂无端口转发规则',
      emptyIcon: Icons.alt_route_outlined,
      onRetry: () => ref.invalidate(firewallForwardsProvider),
      onLoadMore: notifier.loadMore,
      onRefresh: () async {
        try {
          await notifier.refresh();
        } catch (e) {
          if (!context.mounted) return;
          showErrorSnack(context, e);
        }
      },
      itemBuilder: (context, forward, index) {
        final busy = _busyKey == _keyOf(forward);
        return ListTile(
          enabled: !busy,
          leading: Icon(Icons.alt_route, color: theme.colorScheme.primary),
          title: Text(
            '${forward.port} → ${forward.targetIp}:${forward.targetPort}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text('协议 ${FirewallLabels.protocol(forward.protocol)}'),
          trailing: busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : A11yIconButton(
                  tooltip: '删除 ${forward.port} 的端口转发',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _delete(forward),
                ),
        );
      },
    );
  }
}
