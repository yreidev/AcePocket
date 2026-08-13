import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/app_snack.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_view.dart';
import '../../../core/widgets/section_card.dart';
import '../models/website_stat.dart';
import '../providers/website_providers.dart';
import '../providers/website_stat_providers.dart';
import '../widgets/formatters.dart';
import '../widgets/paged_stat_list.dart';
import '../widgets/stat_widgets.dart';
part 'website_stats_tabs.dart';

/// 网站统计页 `/websites/:id/stats`。
///
/// 面板统计接口是全站维度的，按网站名称（`sites` 参数）过滤，
/// 因此进入本页需要网站名称：由列表 / 详情页通过 `extra` 传入，
/// 未传入时回退到 `GET /api/website/{id}` 读取名称。
class WebsiteStatsPage extends ConsumerStatefulWidget {
  const WebsiteStatsPage({
    super.key,
    required this.websiteId,
    this.websiteName,
  });

  final int websiteId;
  final String? websiteName;

  @override
  ConsumerState<WebsiteStatsPage> createState() => _WebsiteStatsPageState();
}

class _WebsiteStatsPageState extends ConsumerState<WebsiteStatsPage> {
  StatDateRange _range = StatDateRange.today();
  int _status = 0;
  int _threshold = 0;
  String _geoGroupBy = 'country';
  String _geoCountry = '';

  static const _tabs = ['概览', 'URI', '慢请求', 'IP', '地区', '蜘蛛', '客户端', '错误'];

  void _setRange(StatDateRange range) {
    if (_range == range) return;
    setState(() => _range = range);
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year, now.month, now.day),
      initialDateRange: DateTimeRange(
        start: DateTime(
          now.year,
          now.month,
          now.day,
        ).subtract(const Duration(days: 6)),
        end: DateTime(now.year, now.month, now.day),
      ),
    );
    if (picked == null || !mounted) return;
    String fmt(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
    _setRange(
      StatDateRange(
        start: fmt(picked.start),
        end: fmt(picked.end),
        label: '自定义',
      ),
    );
  }

  void _refreshAll(
    StatQuery base,
    StatQuery slow,
    StatQuery errors,
    StatQuery geo,
  ) {
    ref.invalidate(statOverviewProvider(base));
    ref.invalidate(statRealtimeProvider);
    ref.invalidate(statUrisProvider(base));
    ref.invalidate(statIpsProvider(base));
    ref.invalidate(statSpidersProvider(base));
    ref.invalidate(statClientsProvider(base));
    ref.invalidate(statSlowUrisProvider(slow));
    ref.invalidate(statErrorsProvider(errors));
    ref.invalidate(statGeosProvider(geo));
  }

  Future<void> _openSetting() async {
    final StatSetting current;
    try {
      current = await ref.read(statSettingProvider.future);
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
      return;
    }
    if (!mounted) return;

    final daysController = TextEditingController(text: '${current.days}');
    var bodyEnabled = current.bodyEnabled;
    String? daysError;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('统计设置'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: daysController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: '数据保留天数',
                  helperText: '1 - 365',
                  errorText: daysError,
                ),
                onChanged: (_) {
                  if (daysError != null) {
                    setDialogState(() => daysError = null);
                  }
                },
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('记录请求体'),
                subtitle: const Text('错误日志中保存请求体内容'),
                value: bodyEnabled,
                onChanged: (v) => setDialogState(() => bodyEnabled = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              // 就地校验：原先关掉对话框才提示越界，用户得重开重填。
              onPressed: () {
                final parsed = int.tryParse(daysController.text.trim());
                if (parsed == null || parsed < 1 || parsed > 365) {
                  setDialogState(() => daysError = '请输入 1 - 365 之间的整数');
                  return;
                }
                Navigator.of(context).pop(true);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    final days = int.tryParse(daysController.text.trim()) ?? current.days;
    daysController.dispose();
    if (saved != true || !mounted) return;

    try {
      await ref
          .read(websiteStatRepoProvider)
          .saveSetting(current.copyWith(days: days, bodyEnabled: bodyEnabled));
      if (!mounted) return;
      ref.invalidate(statSettingProvider);
      showSuccessSnack(context, '统计设置已保存');
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  Future<void> _clearStats(
    StatQuery base,
    StatQuery slow,
    StatQuery errors,
    StatQuery geo,
  ) async {
    final ok = await showConfirmDialog(
      context,
      title: '清空统计数据',
      content: '将清空面板中所有网站的统计数据（不仅是当前网站），且不可恢复。确定继续吗？',
      confirmText: '清空',
      danger: true,
    );
    if (!ok) return;
    try {
      await ref.read(websiteStatRepoProvider).clear();
      if (!mounted) return;
      showSuccessSnack(context, '统计数据已清空');
      _refreshAll(base, slow, errors, geo);
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 解析网站名称：优先使用路由传入，其次读取网站配置。
    final passedName = widget.websiteName?.trim() ?? '';
    if (passedName.isEmpty) {
      final settingAsync = ref.watch(websiteSettingProvider(widget.websiteId));
      return settingAsync.when(
        loading: () => Scaffold(
          appBar: AppBar(title: const Text('网站统计')),
          body: const LoadingView(message: '正在加载网站信息…'),
        ),
        error: (error, _) => Scaffold(
          appBar: AppBar(title: const Text('网站统计')),
          body: ErrorView(
            error: error,
            onRetry: () =>
                ref.invalidate(websiteSettingProvider(widget.websiteId)),
          ),
        ),
        data: (setting) => _buildScaffold(setting.name),
      );
    }
    return _buildScaffold(passedName);
  }

  Widget _buildScaffold(String siteName) {
    final theme = Theme.of(context);
    final base = StatQuery(range: _range, sites: siteName);
    final slow = base.copyWith(threshold: _threshold);
    final errors = base.copyWith(status: _status);
    final geo = base.copyWith(groupBy: _geoGroupBy, country: _geoCountry);

    return DefaultTabController(
      length: _tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(siteName, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(
                '${_range.label} · ${_range.start}'
                '${_range.isSingleDay ? '' : ' ~ ${_range.end}'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          actions: [
            PopupMenuButton<String>(
              tooltip: '时间范围',
              icon: const Icon(Icons.date_range),
              onSelected: (value) {
                switch (value) {
                  case 'today':
                    _setRange(StatDateRange.today());
                  case 'yesterday':
                    _setRange(StatDateRange.yesterday());
                  case '7d':
                    _setRange(StatDateRange.lastDays(7));
                  case '30d':
                    _setRange(StatDateRange.lastDays(30));
                  case 'custom':
                    _pickCustomRange();
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'today', child: Text('今天')),
                PopupMenuItem(value: 'yesterday', child: Text('昨天')),
                PopupMenuItem(value: '7d', child: Text('近 7 天')),
                PopupMenuItem(value: '30d', child: Text('近 30 天')),
                PopupMenuItem(value: 'custom', child: Text('自定义范围…')),
              ],
            ),
            A11yIconButton(
              tooltip: '刷新全部统计数据',
              icon: const Icon(Icons.refresh),
              onPressed: () => _refreshAll(base, slow, errors, geo),
            ),
            PopupMenuButton<String>(
              tooltip: '统计页的更多操作',
              onSelected: (value) {
                switch (value) {
                  case 'setting':
                    _openSetting();
                  case 'clear':
                    _clearStats(base, slow, errors, geo);
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'setting',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.settings_outlined),
                    title: Text('统计设置'),
                  ),
                ),
                PopupMenuItem(
                  value: 'clear',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.delete_sweep_outlined,
                      color: theme.colorScheme.error,
                    ),
                    title: Text(
                      '清空统计',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                ),
              ],
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [for (final tab in _tabs) Tab(text: tab)],
          ),
        ),
        body: TabBarView(
          children: [
            _OverviewTab(query: base),
            _UriTab(query: base),
            _SlowUriTab(
              query: slow,
              threshold: _threshold,
              onThresholdChanged: (v) => setState(() => _threshold = v),
            ),
            _IpTab(query: base),
            _GeoTab(
              query: geo,
              groupBy: _geoGroupBy,
              country: _geoCountry,
              onDrillDown: (groupBy, country) => setState(() {
                _geoGroupBy = groupBy;
                _geoCountry = country;
              }),
            ),
            _SpiderTab(query: base),
            _ClientTab(query: base),
            _ErrorTab(
              query: errors,
              status: _status,
              onStatusChanged: (v) => setState(() => _status = v),
            ),
          ],
        ),
      ),
    );
  }
}
