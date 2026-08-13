import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/app_snack.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_view.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/unsaved_guard.dart';
import '../models/firewall_scan_models.dart';
import '../providers/security_providers.dart';
import '../widgets/paged_list_view.dart';
import '../widgets/security_dialogs.dart';
import '../widgets/security_tiles.dart';

/// 防火墙「扫描感知」页面：设置、统计概览与扫描事件列表。
class FirewallScanPage extends ConsumerStatefulWidget {
  const FirewallScanPage({super.key});

  @override
  ConsumerState<FirewallScanPage> createState() => _FirewallScanPageState();
}

class _FirewallScanPageState extends ConsumerState<FirewallScanPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController =
      TabController(length: 2, vsync: this);

  /// 清空在途标志：不可恢复的操作，请求返回前禁用按钮防连点。
  bool _clearing = false;

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _refreshAll() {
    ref.invalidate(scanSettingProvider);
    ref.invalidate(scanInterfacesProvider);
    ref.invalidate(scanOverviewProvider);
    ref.invalidate(scanEventsProvider);
  }

  Future<void> _clear() async {
    if (_clearing) return;
    final confirmed = await showConfirmDialog(
      context,
      title: '清空扫描数据？',
      content: '所有扫描事件与统计记录将被删除，且不可恢复。',
      confirmText: '清空',
      danger: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _clearing = true);
    try {
      await ref.read(securityRepoProvider).clearScanData();
      _refreshAll();
      if (!mounted) return;
      showSuccessSnack(context, '扫描数据已清空');
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final days = ref.watch(scanRangeDaysProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('扫描感知'),
        actions: [
          A11yIconButton(
            tooltip: '刷新扫描数据',
            icon: const Icon(Icons.refresh),
            onPressed: _refreshAll,
          ),
          A11yIconButton(
            tooltip: '清空全部扫描数据',
            icon: _clearing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.delete_sweep_outlined),
            onPressed: _clearing ? null : _clear,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '概览'),
            Tab(text: '扫描事件'),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 7, label: Text('近 7 天')),
                  ButtonSegment(value: 30, label: Text('近 30 天')),
                  ButtonSegment(value: 90, label: Text('近 90 天')),
                ],
                selected: {days},
                showSelectedIcon: false,
                onSelectionChanged: (selection) => ref
                    .read(scanRangeDaysProvider.notifier)
                    .state = selection.first,
              ),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [
                _ScanOverviewTab(),
                _ScanEventsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------------ 概览

class _ScanOverviewTab extends ConsumerWidget {
  const _ScanOverviewTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(scanOverviewProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(scanSettingProvider);
        ref.invalidate(scanOverviewProvider);
        await ref.read(scanOverviewProvider.future);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          const _ScanSettingCard(),
          overview.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: LoadingView(message: '统计数据加载中…'),
            ),
            error: (error, _) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: ErrorView(
                error: error,
                onRetry: () => ref.invalidate(scanOverviewProvider),
              ),
            ),
            data: (data) => Column(
              children: [
                SectionCard(
                  title: '扫描汇总',
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Expanded(
                        child: StatTile(
                          label: '扫描次数',
                          value: '${data.summary.totalCount}',
                          icon: Icons.radar,
                        ),
                      ),
                      Expanded(
                        child: StatTile(
                          label: '独立来源 IP',
                          value: '${data.summary.uniqueIps}',
                          icon: Icons.public,
                        ),
                      ),
                      Expanded(
                        child: StatTile(
                          label: '被扫端口',
                          value: '${data.summary.uniquePorts}',
                          icon: Icons.numbers,
                        ),
                      ),
                    ],
                  ),
                ),
                if (data.trend.isNotEmpty)
                  SectionCard(
                    title: '每日趋势',
                    child: _TrendBars(trend: data.trend),
                  ),
                SectionCard(
                  title: 'Top 扫描源 IP',
                  child: data.topIps.isEmpty
                      ? const _CardEmpty(message: '暂无数据')
                      : Column(
                          children: [
                            for (final item in data.topIps)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                                title: Text(
                                  item.sourceIp,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  [
                                    if (item.location.isNotEmpty) item.location,
                                    '扫描 ${item.totalCount} 次 · '
                                        '${item.portCount} 个端口',
                                    if (item.lastSeen.isNotEmpty)
                                      '最近 ${item.lastSeen}',
                                  ].join(' · '),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                        ),
                ),
                SectionCard(
                  title: 'Top 被扫描端口',
                  child: data.topPorts.isEmpty
                      ? const _CardEmpty(message: '暂无数据')
                      : Column(
                          children: [
                            for (final item in data.topPorts)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                                title: Text(
                                  '${item.port} / ${item.protocol.toUpperCase()}',
                                ),
                                subtitle: Text(
                                  '被扫 ${item.totalCount} 次 · '
                                  '来自 ${item.ipCount} 个 IP',
                                ),
                              ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CardEmpty extends StatelessWidget {
  const _CardEmpty({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        message,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// 每日趋势条形图（不引入图表库，按最大值等比绘制）。
class _TrendBars extends StatelessWidget {
  const _TrendBars({required this.trend});

  final List<ScanDayTrend> trend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final max = trend.fold<int>(
      1,
      (value, item) => item.totalCount > value ? item.totalCount : value,
    );
    return Column(
      children: [
        for (final item in trend)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                SizedBox(
                  width: 78,
                  child: Text(
                    item.date,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: item.totalCount / max,
                      minHeight: 10,
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
                    ),
                  ),
                ),
                SizedBox(
                  width: 64,
                  child: Text(
                    '${item.totalCount}',
                    textAlign: TextAlign.right,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// -------------------------------------------------------------------- 设置卡片

class _ScanSettingCard extends ConsumerStatefulWidget {
  const _ScanSettingCard();

  @override
  ConsumerState<_ScanSettingCard> createState() => _ScanSettingCardState();
}

/// 扫描感知设置同样是「草稿 + 显式保存」：改动只落在 [_draft]，
/// 因此每项都要标「未保存」，并在返回时拦一道（[UnsavedChangesGuard]）。
class _ScanSettingCardState extends ConsumerState<_ScanSettingCard> {
  ScanSetting? _draft;

  /// 服务端当前生效的设置，用于比对是否有未保存修改。
  ScanSetting? _origin;
  bool _saving = false;

  bool _dirtyOf(Object? Function(ScanSetting setting) pick) {
    final draft = _draft;
    final origin = _origin;
    if (draft == null || origin == null) return false;
    final a = pick(draft);
    final b = pick(origin);
    if (a is List && b is List) return !listEquals(a, b);
    return a != b;
  }

  bool get _enabledDirty => _dirtyOf((s) => s.enabled);
  bool get _daysDirty => _dirtyOf((s) => s.days);
  bool get _interfacesDirty => _dirtyOf((s) => s.interfaces);
  bool get _autoBlockDirty => _dirtyOf((s) => s.autoBlock);
  bool get _thresholdDirty => _dirtyOf((s) => s.blockThreshold);
  bool get _windowDirty => _dirtyOf((s) => s.blockWindow);
  bool get _durationDirty => _dirtyOf((s) => s.blockDuration);
  bool get _whitelistDirty => _dirtyOf((s) => s.whitelist);

  bool get _dirty =>
      _enabledDirty ||
      _daysDirty ||
      _interfacesDirty ||
      _autoBlockDirty ||
      _thresholdDirty ||
      _windowDirty ||
      _durationDirty ||
      _whitelistDirty;

  void _reset() {
    setState(() {
      _draft = null;
      _origin = null;
    });
  }

  Future<void> _save() async {
    final draft = _draft;
    if (draft == null || _saving) return;
    setState(() => _saving = true);
    try {
      await ref.read(securityRepoProvider).updateScanSetting(draft);
      if (!mounted) return;
      setState(() {
        _draft = null;
        _origin = null;
      });
      ref.invalidate(scanSettingProvider);
      ref.invalidate(scanOverviewProvider);
      showSuccessSnack(context, '扫描感知设置已保存');
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(scanSettingProvider);

    return SectionCard(
      title: '扫描感知设置',
      child: async.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: LoadingView(),
        ),
        error: (error, _) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: ErrorView(
            error: error,
            onRetry: () => ref.invalidate(scanSettingProvider),
          ),
        ),
        data: (setting) {
          _origin ??= setting;
          final draft = _draft ??= setting;
          final interfaces = ref.watch(scanInterfacesProvider);
          return UnsavedChangesGuard(
            hasUnsavedChanges: _dirty && !_saving,
            message: '扫描感知设置改了但没保存，'
                '这些改动还没有下发到面板，返回后将丢失。',
            onDiscard: _reset,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SettingSwitchTile(
                  title: '开启扫描感知',
                  subtitle: '监听网卡流量，记录端口扫描行为',
                  value: draft.enabled,
                  dirty: _enabledDirty,
                  onChanged: (value) =>
                      setState(() => _draft = draft.copyWith(enabled: value)),
                ),
                if (draft.enabled) ...[
                  SettingValueTile(
                    title: '数据保留天数',
                    value: '${draft.days} 天',
                    dirty: _daysDirty,
                    onTap: () async {
                      final days = await showIntInputDialog(
                        context,
                        title: '数据保留天数',
                        initialValue: draft.days,
                        min: 1,
                        max: 365,
                        label: '天数',
                      );
                      if (days == null || !mounted) return;
                      setState(() => _draft = draft.copyWith(days: days));
                    },
                  ),
                  SettingValueTile(
                    title: '监听网卡',
                    value: draft.interfaces.isEmpty
                        ? '自动检测'
                        : draft.interfaces.join('、'),
                    dirty: _interfacesDirty,
                    onTap: () async {
                      final options = interfaces.valueOrNull ?? const [];
                      final selected = await showMultiSelectDialog(
                        context,
                        title: '选择监听网卡',
                        options: options.map((e) => e.name).toList(),
                        selected: draft.interfaces,
                        labelBuilder: (name) => options
                            .firstWhere(
                              (e) => e.name == name,
                              orElse: () => NetInterface(
                                  name: name, ips: const [], status: ''),
                            )
                            .label,
                        emptyHint: '未获取到可用网卡，留空即为自动检测',
                      );
                      if (selected == null || !mounted) return;
                      setState(
                          () => _draft = draft.copyWith(interfaces: selected));
                    },
                  ),
                  SettingSwitchTile(
                    title: '自动封锁扫描源',
                    subtitle: '达到阈值后自动写入防火墙 IP 规则',
                    value: draft.autoBlock,
                    dirty: _autoBlockDirty,
                    onChanged: (value) => setState(
                        () => _draft = draft.copyWith(autoBlock: value)),
                  ),
                  if (draft.autoBlock) ...[
                    SettingValueTile(
                      title: '封锁阈值',
                      value: '${draft.blockThreshold} 次',
                      dirty: _thresholdDirty,
                      onTap: () async {
                        final value = await showIntInputDialog(
                          context,
                          title: '封锁阈值',
                          initialValue: draft.blockThreshold,
                          min: 1,
                          max: 100000,
                          label: '扫描次数',
                          helperText: '检测窗口内扫描次数达到该值即触发封锁',
                        );
                        if (value == null || !mounted) return;
                        setState(() =>
                            _draft = draft.copyWith(blockThreshold: value));
                      },
                    ),
                    SettingValueTile(
                      title: '检测窗口',
                      value: '${draft.blockWindow} 分钟',
                      dirty: _windowDirty,
                      onTap: () async {
                        final value = await showIntInputDialog(
                          context,
                          title: '检测窗口',
                          initialValue: draft.blockWindow,
                          min: 1,
                          max: 1440,
                          label: '分钟',
                        );
                        if (value == null || !mounted) return;
                        setState(
                            () => _draft = draft.copyWith(blockWindow: value));
                      },
                    ),
                    SettingValueTile(
                      title: '封锁时长',
                      value: draft.blockDuration == 0
                          ? '永久'
                          : '${draft.blockDuration} 小时',
                      dirty: _durationDirty,
                      onTap: () async {
                        final value = await showIntInputDialog(
                          context,
                          title: '封锁时长',
                          initialValue: draft.blockDuration,
                          min: 0,
                          max: 87600,
                          label: '小时',
                          helperText: '填 0 表示永久封锁',
                        );
                        if (value == null || !mounted) return;
                        setState(() =>
                            _draft = draft.copyWith(blockDuration: value));
                      },
                    ),
                    SettingValueTile(
                      title: 'IP 白名单',
                      value: draft.whitelist.isEmpty
                          ? '未设置'
                          : draft.whitelist.join('、'),
                      helper: '白名单内的 IP 不会被自动封锁',
                      dirty: _whitelistDirty,
                      onTap: () async {
                        final values = await showStringListEditor(
                          context,
                          title: 'IP 白名单',
                          values: draft.whitelist,
                          hintText: '172.16.0.1 或 172.16.0.0/16',
                        );
                        if (values == null || !mounted) return;
                        setState(
                            () => _draft = draft.copyWith(whitelist: values));
                      },
                    ),
                  ],
                ],
                const SizedBox(height: 12),
                // 未改动时禁用并写明「设置未变更」，避免与「已生效」混淆。
                FilledButton.icon(
                  onPressed: (_saving || !_dirty) ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(_dirty ? '保存设置' : '设置未变更'),
                ),
                if (_dirty && !_saving)
                  TextButton(
                    onPressed: () {
                      _reset();
                      ref.invalidate(scanSettingProvider);
                    },
                    child: const Text('放弃修改'),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// -------------------------------------------------------------------- 扫描事件

class _ScanEventsTab extends ConsumerWidget {
  const _ScanEventsTab();

  Future<void> _editFilter(BuildContext context, WidgetRef ref) async {
    final current = ref.read(scanEventFilterProvider);
    final ip = await showTextInputDialog(
      context,
      title: '筛选来源 IP',
      initialValue: current.sourceIp,
      label: '来源 IP',
      helperText: '留空表示不限制；确定后可继续筛选端口',
      confirmText: '下一步',
    );
    if (ip == null || !context.mounted) return;
    final portText = await showTextInputDialog(
      context,
      title: '筛选端口',
      initialValue: current.port == null ? '' : '${current.port}',
      label: '端口',
      helperText: '留空表示不限制',
      keyboardType: TextInputType.number,
      confirmText: '应用',
      validator: (value) {
        if (value.isEmpty) return null;
        final port = int.tryParse(value);
        if (port == null || port < 1 || port > 65535) {
          return '端口需在 1-65535 之间';
        }
        return null;
      },
    );
    if (portText == null || !context.mounted) return;
    ref.read(scanEventFilterProvider.notifier).state = ScanEventFilter(
      sourceIp: ip.trim(),
      port: portText.isEmpty ? null : int.tryParse(portText),
      location: current.location,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(scanEventsProvider);
    final notifier = ref.read(scanEventsProvider.notifier);
    final filter = ref.watch(scanEventFilterProvider);
    final theme = Theme.of(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  filter.isEmpty
                      ? '全部扫描事件'
                      : '筛选：'
                          '${filter.sourceIp.isEmpty ? '' : 'IP ${filter.sourceIp} '}'
                          '${filter.port == null ? '' : '端口 ${filter.port}'}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (!filter.isEmpty)
                TextButton(
                  onPressed: () => ref
                      .read(scanEventFilterProvider.notifier)
                      .state = const ScanEventFilter(),
                  child: const Text('清除'),
                ),
              A11yIconButton(
                tooltip: '筛选扫描事件',
                icon: const Icon(Icons.filter_alt_outlined),
                onPressed: () => _editFilter(context, ref),
              ),
            ],
          ),
        ),
        Expanded(
          child: PagedListView<ScanEvent>(
            state: state,
            emptyMessage: '所选时间范围内暂无扫描事件',
            emptyIcon: Icons.radar,
            onRetry: () => ref.invalidate(scanEventsProvider),
            onLoadMore: notifier.loadMore,
            onRefresh: () async {
              try {
                await notifier.refresh();
              } catch (e) {
                if (!context.mounted) return;
                showErrorSnack(context, e);
              }
            },
            itemBuilder: (context, event, index) => ListTile(
              leading: Icon(
                Icons.travel_explore_outlined,
                color: theme.colorScheme.tertiary,
              ),
              title: Row(
                children: [
                  Flexible(
                    child: Text(
                      event.sourceIp,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  TagChip(label: '${event.count} 次'),
                ],
              ),
              subtitle: Text(
                [
                  '端口 ${event.port}/${event.protocol.toUpperCase()}',
                  event.date,
                  if (event.location.isNotEmpty) event.location,
                ].join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
