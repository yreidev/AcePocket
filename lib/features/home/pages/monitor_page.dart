import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/storage/server_store.dart';
import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/app_snack.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/empty_view.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_view.dart';
import '../models/monitor_models.dart';
import '../providers/monitor_providers.dart';
import '../widgets/formatters.dart';
import '../widgets/monitor_chart_card.dart';
import '../widgets/monitor_setting_dialog.dart';

/// 历史监控图表页（`/monitor`）。
///
/// 数据来自 `GET /monitor/list?start=&end=`，时间范围可切换。
class MonitorPage extends ConsumerWidget {
  const MonitorPage({super.key});

  /// 刷新监控数据。
  ///
  /// 请求失败时错误已由 `monitorDetailProvider` 的 AsyncValue 承载并在页面上
  /// 展示，这里必须吞掉异常：直接把失败的 Future 交给 RefreshIndicator /
  /// 按钮回调会变成一条无人处理的异步异常。
  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(monitorSettingProvider);
    ref.invalidate(monitorDetailProvider);
    try {
      await ref.read(monitorDetailProvider.future);
    } catch (_) {
      // 忽略：错误态由 async.when 的 error 分支渲染。
    }
  }

  Future<void> _openSetting(BuildContext context, WidgetRef ref) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => const MonitorSettingDialog(),
    );
    if (saved != true) return;
    ref.invalidate(monitorSettingProvider);
    ref.invalidate(monitorDetailProvider);
    if (!context.mounted) return;
    showSuccessSnack(context, '监控设置已保存');
  }

  Future<void> _clear(BuildContext context, WidgetRef ref) async {
    final ok = await showConfirmDialog(
      context,
      title: '清空监控数据',
      content:
          '将删除面板上全部历史监控记录，且不可恢复。\n'
          '清空后需要等采集任务重新积累数据，本页会暂时无图。确定继续吗？',
      confirmText: '清空',
      danger: true,
    );
    if (!ok) return;
    try {
      await ref.read(monitorRepoProvider).clear();
      ref.invalidate(monitorDetailProvider);
      if (!context.mounted) return;
      showSuccessSnack(context, '监控数据已清空');
    } catch (e) {
      // 网络层异常（超时 / 证书）不是 ApiException，此前会漏掉、静默失败。
      if (!context.mounted) return;
      showErrorSnack(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final server = ref.watch(activeServerProvider);
    if (server == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('历史监控')),
        body: EmptyView(
          message: '尚未选择服务器',
          icon: Icons.dns_outlined,
          action: FilledButton.icon(
            onPressed: () => context.go('/servers/setup'),
            icon: const Icon(Icons.add),
            label: const Text('添加服务器'),
          ),
        ),
      );
    }

    final range = ref.watch(monitorRangeProvider);
    final async = ref.watch(monitorDetailProvider);
    final setting = ref.watch(monitorSettingProvider).value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('历史监控'),
        actions: [
          A11yIconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新监控数据',
            onPressed: () => _refresh(ref),
          ),
          PopupMenuButton<String>(
            tooltip: '打开更多操作菜单',
            onSelected: (value) {
              switch (value) {
                case 'setting':
                  _openSetting(context, ref);
                  break;
                case 'clear':
                  _clear(context, ref);
                  break;
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'setting',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.tune),
                  title: Text('监控设置'),
                ),
              ),
              PopupMenuItem(
                value: 'clear',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.delete_outline),
                  title: Text('清空监控数据'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          _RangeSelector(
            value: range,
            onChanged: (value) =>
                ref.read(monitorRangeProvider.notifier).state = value,
          ),
          if (setting != null && !setting.enabled)
            _DisabledHint(onOpenSetting: () => _openSetting(context, ref)),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _refresh(ref),
              child: async.when(
                loading: () =>
                    _fill(context, const LoadingView(message: '正在加载监控数据…')),
                error: (error, _) => _fill(
                  context,
                  ErrorView(
                    error: error,
                    onRetry: () => ref.invalidate(monitorDetailProvider),
                  ),
                ),
                data: (detail) {
                  if (detail.isEmpty) {
                    return _fill(
                      context,
                      EmptyView(
                        message: setting != null && !setting.enabled
                            ? '监控采集已关闭，暂无历史数据'
                            : '该时间段暂无监控数据',
                        icon: Icons.show_chart_rounded,
                        action: FilledButton.tonalIcon(
                          onPressed: () => _openSetting(context, ref),
                          icon: const Icon(Icons.tune),
                          label: const Text('监控设置'),
                        ),
                      ),
                    );
                  }
                  return _MonitorCharts(detail: detail);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fill(BuildContext context, Widget child) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.55,
          child: Center(child: child),
        ),
      ],
    );
  }
}

class _RangeSelector extends StatelessWidget {
  const _RangeSelector({required this.value, required this.onChanged});

  final MonitorRange value;
  final ValueChanged<MonitorRange> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<MonitorRange>(
          segments: [
            for (final range in MonitorRange.values)
              ButtonSegment<MonitorRange>(
                value: range,
                label: Text(range.label),
              ),
          ],
          selected: {value},
          showSelectedIcon: false,
          style: const ButtonStyle(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onSelectionChanged: (selection) => onChanged(selection.first),
        ),
      ),
    );
  }
}

class _DisabledHint extends StatelessWidget {
  const _DisabledHint({required this.onOpenSetting});

  final VoidCallback onOpenSetting;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            size: 16,
            color: theme.colorScheme.onTertiaryContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '面板监控采集当前处于关闭状态',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onTertiaryContainer,
              ),
            ),
          ),
          TextButton(onPressed: onOpenSetting, child: const Text('去开启')),
        ],
      ),
    );
  }
}

/// 各项监控图表。
class _MonitorCharts extends ConsumerWidget {
  const _MonitorCharts({required this.detail});

  final MonitorDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final netNames = detail.net.map((e) => e.name).toList();
    final diskNames = detail.diskIo.map((e) => e.name).toList();

    final selectedNet = _pick(ref.watch(monitorNetDeviceProvider), netNames);
    final selectedDisk = _pick(ref.watch(monitorDiskDeviceProvider), diskNames);

    final net = selectedNet == null
        ? null
        : detail.net.firstWhere((e) => e.name == selectedNet);
    final disk = selectedDisk == null
        ? null
        : detail.diskIo.firstWhere((e) => e.name == selectedDisk);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 4, bottom: 24),
      children: [
        MonitorChartCard(
          title: 'CPU 使用率',
          times: detail.times,
          minY: 0,
          maxY: 100,
          valueFormatter: (v) => '${v.toStringAsFixed(0)}%',
          series: [
            ChartSeries(
              name: 'CPU',
              values: detail.cpu.percent,
              color: colors.primary,
            ),
          ],
        ),
        MonitorChartCard(
          title: '系统负载',
          times: detail.times,
          minY: 0,
          valueFormatter: formatAxisNumber,
          series: [
            ChartSeries(
              name: '1 分钟',
              values: detail.load.load1,
              color: colors.primary,
            ),
            ChartSeries(
              name: '5 分钟',
              values: detail.load.load5,
              color: colors.secondary,
            ),
            ChartSeries(
              name: '15 分钟',
              values: detail.load.load15,
              color: colors.tertiary,
            ),
          ],
        ),
        MonitorChartCard(
          title: '内存使用',
          subtitle: '总量 ${formatMegabytes(detail.mem.total)}',
          times: detail.times,
          minY: 0,
          valueFormatter: (v) => formatMegabytes(v, fractionDigits: 1),
          series: [
            ChartSeries(
              name: '已用',
              values: detail.mem.used,
              color: colors.primary,
            ),
            ChartSeries(
              name: '可用',
              values: detail.mem.available,
              color: colors.tertiary,
            ),
          ],
        ),
        if (detail.swap.total > 0)
          MonitorChartCard(
            title: 'SWAP 使用',
            subtitle: '总量 ${formatMegabytes(detail.swap.total)}',
            times: detail.times,
            minY: 0,
            valueFormatter: (v) => formatMegabytes(v, fractionDigits: 1),
            series: [
              ChartSeries(
                name: '已用',
                values: detail.swap.used,
                color: colors.primary,
              ),
              ChartSeries(
                name: '空闲',
                values: detail.swap.free,
                color: colors.tertiary,
              ),
            ],
          ),
        if (net != null)
          MonitorChartCard(
            title: '网络速率',
            times: detail.times,
            minY: 0,
            valueFormatter: (v) => formatMegabytesRate(v),
            trailing: _DeviceSelector(
              names: netNames,
              value: net.name,
              onChanged: (value) =>
                  ref.read(monitorNetDeviceProvider.notifier).state = value,
            ),
            series: [
              ChartSeries(name: '上行', values: net.tx, color: colors.primary),
              ChartSeries(name: '下行', values: net.rx, color: colors.tertiary),
            ],
          ),
        if (net != null)
          MonitorChartCard(
            title: '网络累计流量',
            times: detail.times,
            minY: 0,
            valueFormatter: (v) => formatMegabytes(v, fractionDigits: 1),
            trailing: _DeviceSelector(
              names: netNames,
              value: net.name,
              onChanged: (value) =>
                  ref.read(monitorNetDeviceProvider.notifier).state = value,
            ),
            series: [
              ChartSeries(name: '发送', values: net.sent, color: colors.primary),
              ChartSeries(name: '接收', values: net.recv, color: colors.tertiary),
            ],
          ),
        if (disk != null)
          MonitorChartCard(
            title: '磁盘 IO 速率',
            times: detail.times,
            minY: 0,
            valueFormatter: (v) => formatKilobytesRate(v),
            trailing: _DeviceSelector(
              names: diskNames,
              value: disk.name,
              onChanged: (value) =>
                  ref.read(monitorDiskDeviceProvider.notifier).state = value,
            ),
            series: [
              ChartSeries(
                name: '读取',
                values: disk.readSpeed,
                color: colors.primary,
              ),
              ChartSeries(
                name: '写入',
                values: disk.writeSpeed,
                color: colors.tertiary,
              ),
            ],
          ),
      ],
    );
  }

  /// 选中项不在列表中（如切换了时间范围）时回退到第一项。
  String? _pick(String? selected, List<String> names) {
    if (names.isEmpty) return null;
    if (selected != null && names.contains(selected)) return selected;
    return names.first;
  }
}

class _DeviceSelector extends StatelessWidget {
  const _DeviceSelector({
    required this.names,
    required this.value,
    required this.onChanged,
  });

  final List<String> names;
  final String value;
  final ValueChanged<String> onChanged;

  /// 设备名可能很长（如 `br-1a2b3c4d5e6f`），而这里位于卡片标题行的尾部，
  /// 不限宽会把标题挤没甚至溢出，因此统一限制最大宽度并省略号收尾。
  static const double _maxWidth = 140;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (names.length <= 1) {
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _maxWidth),
        child: Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.end,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _maxWidth),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isDense: true,
          isExpanded: true,
          borderRadius: BorderRadius.circular(12),
          alignment: Alignment.centerRight,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurface,
          ),
          items: [
            for (final name in names)
              DropdownMenuItem<String>(
                value: name,
                child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (selected) {
            if (selected != null) onChanged(selected);
          },
        ),
      ),
    );
  }
}
