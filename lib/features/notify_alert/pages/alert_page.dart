import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/version/panel_feature.dart';
import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/app_snack.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/feature_gate.dart';
import '../models/alert_rule.dart';
import '../providers/notify_alert_providers.dart';
import '../widgets/alert_tiles.dart';
import '../widgets/form_fields.dart';
import '../widgets/paged_list_view.dart';

/// 告警页 `/alerts`：告警规则与告警记录。
class AlertPage extends ConsumerStatefulWidget {
  const AlertPage({super.key});

  @override
  ConsumerState<AlertPage> createState() => _AlertPageState();
}

class _AlertPageState extends ConsumerState<AlertPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController =
      TabController(length: 2, vsync: this);

  /// 正在清空告警记录（防止重复点击发起多次清空请求）。
  bool _clearing = false;

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

  void _refreshAll() {
    ref.invalidate(alertRulesProvider);
    ref.invalidate(alertRecordsProvider);
    ref.invalidate(allNotifyChannelsProvider);
  }

  Future<void> _createRule() async {
    final saved = await context.push<bool>('/alerts/rules/new');
    if (!mounted || saved != true) return;
    try {
      await ref.read(alertRulesProvider.notifier).reload();
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  Future<void> _clearRecords() async {
    if (_clearing) return;
    final ok = await showConfirmDialog(
      context,
      title: '清空告警记录',
      content: '所有告警记录将被删除，且不可恢复。已配置的告警规则不受影响。确定继续？',
      confirmText: '清空',
      danger: true,
    );
    if (!ok || !mounted) return;
    setState(() => _clearing = true);
    try {
      await ref.read(notifyAlertRepoProvider).clearAlertRecords();
      if (!mounted) return;
      showSuccessSnack(context, '告警记录已清空');
      await ref.read(alertRecordsProvider.notifier).reload();
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final onRecordsTab = _tabController.index == 1;
    return Scaffold(
      appBar: AppBar(
        title: const Text('告警'),
        actions: [
          A11yIconButton(
            tooltip: '刷新告警规则与记录',
            icon: const Icon(Icons.refresh),
            onPressed: _refreshAll,
          ),
          if (onRecordsTab)
            A11yIconButton(
              tooltip: '清空全部告警记录',
              icon: _clearing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete_sweep_outlined),
              onPressed: _clearing ? null : _clearRecords,
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '告警规则'),
            Tab(text: '告警记录'),
          ],
        ),
      ),
      body: Column(
        children: [
          const FeatureUnsupportedBanner(feature: PanelFeature.alert),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [
                _AlertRulesTab(),
                _AlertRecordsTab(),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: _tabController.index == 0
          ? FloatingActionButton.extended(
              onPressed: _createRule,
              icon: const Icon(Icons.add),
              label: const Text('新建规则'),
            )
          : null,
    );
  }
}

// -------------------------------------------------------------------- 告警规则

class _AlertRulesTab extends ConsumerStatefulWidget {
  const _AlertRulesTab();

  @override
  ConsumerState<_AlertRulesTab> createState() => _AlertRulesTabState();
}

class _AlertRulesTabState extends ConsumerState<_AlertRulesTab> {
  int? _busyId;

  Future<void> _reloadQuietly() async {
    try {
      await ref.read(alertRulesProvider.notifier).reload();
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  /// 操作期间禁用其他条目的操作，避免重复提交。
  Future<void> _runBusy(int id, Future<void> Function() action) async {
    if (_busyId != null) return;
    setState(() => _busyId = id);
    try {
      await action();
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _edit(AlertRule rule) async {
    final saved = await context.push<bool>('/alerts/rules/${rule.id}/edit');
    if (!mounted || saved != true) return;
    await _reloadQuietly();
  }

  Future<void> _toggle(AlertRule rule) async {
    await _runBusy(rule.id, () async {
      await ref
          .read(notifyAlertRepoProvider)
          .updateAlertRule(rule.copyWith(enabled: !rule.enabled));
      if (mounted) {
        showSuccessSnack(context, rule.enabled ? '规则已停用' : '规则已启用');
      }
      await _reloadQuietly();
    });
  }

  Future<void> _delete(AlertRule rule) async {
    final ok = await showConfirmDialog(
      context,
      title: '删除告警规则',
      content: '确定要删除「${rule.name.isEmpty ? '未命名规则' : rule.name}」吗？'
          '删除后该规则不再触发告警，已产生的告警记录会保留。',
      confirmText: '删除',
      danger: true,
    );
    if (!ok) return;
    await _runBusy(rule.id, () async {
      await ref.read(notifyAlertRepoProvider).deleteAlertRule(rule.id);
      if (mounted) showSuccessSnack(context, '规则已删除');
      await _reloadQuietly();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(alertRulesProvider);
    return PagedListView<AlertRule>(
      state: state,
      header: const InfoBanner(
        text: '面板每分钟检查一次指标，条件连续满足设定次数后触发告警，'
            '并按静默期去重；未选择通知渠道时只记录不发送。',
      ),
      onRefresh: () => ref.read(alertRulesProvider.notifier).refresh(),
      onLoadMore: () => ref.read(alertRulesProvider.notifier).loadMore(),
      onRetry: () => ref.invalidate(alertRulesProvider),
      emptyMessage: '暂无告警规则',
      emptyIcon: Icons.notifications_active_outlined,
      itemBuilder: (context, rule, index) => AlertRuleTile(
        rule: rule,
        busy: _busyId == rule.id,
        onEdit: () => _edit(rule),
        onToggle: () => _toggle(rule),
        onDelete: () => _delete(rule),
      ),
    );
  }
}

// -------------------------------------------------------------------- 告警记录

class _AlertRecordsTab extends ConsumerWidget {
  const _AlertRecordsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(alertRecordsProvider);
    return PagedListView<AlertRecord>(
      state: state,
      header: const InfoBanner(
        text: '告警记录只保存触发历史，不代表当前状态；清空记录不影响告警规则。',
      ),
      onRefresh: () => ref.read(alertRecordsProvider.notifier).refresh(),
      onLoadMore: () => ref.read(alertRecordsProvider.notifier).loadMore(),
      onRetry: () => ref.invalidate(alertRecordsProvider),
      emptyMessage: '暂无告警记录',
      emptyIcon: Icons.history_toggle_off,
      itemBuilder: (context, record, index) => AlertRecordTile(record: record),
    );
  }
}
