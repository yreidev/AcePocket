part of 'website_stats_page.dart';

// ------------------------------------------------------------------ 概览

class _OverviewTab extends ConsumerStatefulWidget {
  const _OverviewTab({required this.query});

  final StatQuery query;

  @override
  ConsumerState<_OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends ConsumerState<_OverviewTab> {
  StatMetric _metric = StatMetric.pv;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final overviewAsync = ref.watch(statOverviewProvider(widget.query));
    final realtimeAsync = ref.watch(statRealtimeProvider);

    return overviewAsync.when(
      loading: () => const LoadingView(message: '正在加载统计概览…'),
      error: (error, _) => ErrorView(
        error: error,
        onRetry: () => ref.invalidate(statOverviewProvider(widget.query)),
      ),
      data: (overview) {
        final current = overview.current;
        final previous = overview.previous;
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(statOverviewProvider(widget.query));
            ref.invalidate(statRealtimeProvider);
            // 失败时 provider 进入错误态由 ErrorView 展示，这里吞掉异常，
            // 避免 RefreshIndicator 抛出未处理的 Future 错误。
            try {
              await ref.read(statOverviewProvider(widget.query).future);
            } catch (_) {}
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(top: 8, bottom: 32),
            children: [
              SectionCard(
                title: '全站实时',
                trailing: A11yIconButton(
                  tooltip: '刷新全站实时数据',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.refresh, size: 18),
                  onPressed: () => ref.invalidate(statRealtimeProvider),
                ),
                child: realtimeAsync.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => Text(
                    '实时数据获取失败：${describeError(e)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                  data: (realtime) => StatMetricGrid(
                    tiles: [
                      StatMetricTile(
                        label: '出站速率',
                        value: formatBytesRate(realtime.bandwidth),
                        icon: Icons.upload_outlined,
                      ),
                      StatMetricTile(
                        label: '入站速率',
                        value: formatBytesRate(realtime.bandwidthIn),
                        icon: Icons.download_outlined,
                      ),
                      StatMetricTile(
                        label: '请求速率',
                        value: '${realtime.rps.toStringAsFixed(2)} req/s',
                        icon: Icons.speed_outlined,
                      ),
                    ],
                  ),
                ),
              ),
              SectionCard(
                title: '核心指标（与上一周期对比）',
                child: StatMetricGrid(
                  tiles: [
                    StatMetricTile(
                      label: '浏览量 PV',
                      value: formatCount(current.pv),
                      delta: formatDelta(current.pv, previous.pv),
                      deltaPositive: isDeltaPositive(current.pv, previous.pv),
                    ),
                    StatMetricTile(
                      label: '访客数 UV',
                      value: formatCount(current.uv),
                      delta: formatDelta(current.uv, previous.uv),
                      deltaPositive: isDeltaPositive(current.uv, previous.uv),
                    ),
                    StatMetricTile(
                      label: '独立 IP',
                      value: formatCount(current.ip),
                      delta: formatDelta(current.ip, previous.ip),
                      deltaPositive: isDeltaPositive(current.ip, previous.ip),
                    ),
                    StatMetricTile(
                      label: '请求数',
                      value: formatCount(current.requests),
                      delta: formatDelta(current.requests, previous.requests),
                      deltaPositive: isDeltaPositive(
                        current.requests,
                        previous.requests,
                      ),
                    ),
                    StatMetricTile(
                      label: '出站流量',
                      value: formatBytes(current.bandwidth),
                      delta: formatDelta(current.bandwidth, previous.bandwidth),
                      deltaPositive: isDeltaPositive(
                        current.bandwidth,
                        previous.bandwidth,
                      ),
                    ),
                    StatMetricTile(
                      label: '入站流量',
                      value: formatBytes(current.bandwidthIn),
                      delta: formatDelta(
                        current.bandwidthIn,
                        previous.bandwidthIn,
                      ),
                      deltaPositive: isDeltaPositive(
                        current.bandwidthIn,
                        previous.bandwidthIn,
                      ),
                    ),
                    StatMetricTile(
                      label: '错误数',
                      value: formatCount(current.errors),
                      delta: formatDelta(current.errors, previous.errors),
                      deltaPositive: !isDeltaPositive(
                        current.errors,
                        previous.errors,
                      ),
                    ),
                    StatMetricTile(
                      label: '蜘蛛请求',
                      value: formatCount(current.spiders),
                      delta: formatDelta(current.spiders, previous.spiders),
                      deltaPositive: isDeltaPositive(
                        current.spiders,
                        previous.spiders,
                      ),
                    ),
                    StatMetricTile(
                      label: '平均响应',
                      value: formatMilliseconds(current.avgRequestTimeMs),
                    ),
                    StatMetricTile(
                      label: '错误率',
                      value: formatPercent(current.errorRate),
                    ),
                  ],
                ),
              ),
              SectionCard(
                title: '趋势',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final metric in StatMetric.values)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(metric.label),
                                selected: _metric == metric,
                                onSelected: (_) =>
                                    setState(() => _metric = metric),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    StatSeriesChart(
                      series: overview.series,
                      previousSeries: overview.previousSeries,
                      metric: _metric,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '实线为当前周期，虚线为上一周期',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              SectionCard(
                title: '状态码分布',
                child: StatusCodeBars(totals: current),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ------------------------------------------------------------------- URI

class _UriTab extends ConsumerWidget {
  const _UriTab({required this.query});

  final StatQuery query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(statUrisProvider(query));
    final maxRequests =
        state.value?.items.fold<int>(
          0,
          (max, e) => e.requests > max ? e.requests : max,
        ) ??
        0;

    return PagedStatList<UriRank>(
      state: state,
      onRefresh: () => ref.read(statUrisProvider(query).notifier).refresh(),
      onLoadMore: () => ref.read(statUrisProvider(query).notifier).loadMore(),
      itemBuilder: (context, item, index) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: StatRankBar(
          label: item.uri,
          value: '${formatCount(item.requests)} 次',
          ratio: maxRequests == 0 ? 0 : item.requests / maxRequests,
          subtitle:
              '流量 ${formatBytes(item.bandwidth)}'
              ' · 平均 ${formatMilliseconds(item.avgRequestTimeMs)}',
          trailing: item.errors > 0 ? '错误 ${formatCount(item.errors)}' : null,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- 慢请求

class _SlowUriTab extends ConsumerWidget {
  const _SlowUriTab({
    required this.query,
    required this.threshold,
    required this.onThresholdChanged,
  });

  final StatQuery query;
  final int threshold;
  final ValueChanged<int> onThresholdChanged;

  static const _options = <({int value, String label})>[
    (value: 0, label: '不限'),
    (value: 100, label: '≥100ms'),
    (value: 500, label: '≥500ms'),
    (value: 1000, label: '≥1s'),
    (value: 3000, label: '≥3s'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(statSlowUrisProvider(query));
    final maxTime =
        state.value?.items.fold<double>(
          0,
          (max, e) => e.avgRequestTimeMs > max ? e.avgRequestTimeMs : max,
        ) ??
        0;

    return PagedStatList<UriRank>(
      state: state,
      header: _FilterHeader(
        title: '响应时间阈值',
        children: [
          for (final option in _options)
            ChoiceChip(
              label: Text(option.label),
              selected: threshold == option.value,
              onSelected: (_) => onThresholdChanged(option.value),
            ),
        ],
      ),
      onRefresh: () => ref.read(statSlowUrisProvider(query).notifier).refresh(),
      onLoadMore: () =>
          ref.read(statSlowUrisProvider(query).notifier).loadMore(),
      itemBuilder: (context, item, index) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: StatRankBar(
          label: item.uri,
          value: formatMilliseconds(item.avgRequestTimeMs),
          ratio: maxTime == 0 ? 0 : item.avgRequestTimeMs / maxTime,
          subtitle:
              '请求 ${formatCount(item.requests)} 次'
              ' · 流量 ${formatBytes(item.bandwidth)}',
          trailing: item.errors > 0 ? '错误 ${formatCount(item.errors)}' : null,
        ),
      ),
    );
  }
}

// -------------------------------------------------------------------- IP

class _IpTab extends ConsumerWidget {
  const _IpTab({required this.query});

  final StatQuery query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(statIpsProvider(query));
    final maxRequests =
        state.value?.items.fold<int>(
          0,
          (max, e) => e.requests > max ? e.requests : max,
        ) ??
        0;

    return PagedStatList<IpRank>(
      state: state,
      onRefresh: () => ref.read(statIpsProvider(query).notifier).refresh(),
      onLoadMore: () => ref.read(statIpsProvider(query).notifier).loadMore(),
      itemBuilder: (context, item, index) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: StatRankBar(
          label: item.ip,
          value: '${formatCount(item.requests)} 次',
          ratio: maxRequests == 0 ? 0 : item.requests / maxRequests,
          subtitle: [
            if (item.location.isNotEmpty) item.location,
            if (item.isp.isNotEmpty) item.isp,
          ].join(' · '),
          trailing: formatBytes(item.bandwidth),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ 地区

class _GeoTab extends ConsumerWidget {
  const _GeoTab({
    required this.query,
    required this.groupBy,
    required this.country,
    required this.onDrillDown,
  });

  final StatQuery query;
  final String groupBy;
  final String country;
  final void Function(String groupBy, String country) onDrillDown;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(statGeosProvider(query));

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(statGeosProvider(query));
        try {
          await ref.read(statGeosProvider(query).future);
        } catch (_) {}
      },
      child: async.when(
        loading: () => const LoadingView(message: '正在加载地区统计…'),
        error: (error, _) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(statGeosProvider(query)),
        ),
        data: (items) {
          final maxRequests = items.fold<int>(
            0,
            (max, e) => e.requests > max ? e.requests : max,
          );
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              _FilterHeader(
                title: '统计维度',
                children: [
                  ChoiceChip(
                    label: const Text('国家'),
                    selected: groupBy == 'country',
                    onSelected: (_) => onDrillDown('country', ''),
                  ),
                  ChoiceChip(
                    label: Text(country.isEmpty ? '省份' : '省份（$country）'),
                    selected: groupBy == 'region',
                    onSelected: (_) => onDrillDown('region', country),
                  ),
                  ChoiceChip(
                    label: const Text('城市'),
                    selected: groupBy == 'city',
                    onSelected: (_) => onDrillDown('city', country),
                  ),
                ],
              ),
              if (items.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(
                    child: Text(
                      '所选时间范围内暂无数据',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              for (final item in items)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: StatRankBar(
                    label: item.label,
                    value: '${formatCount(item.requests)} 次',
                    ratio: maxRequests == 0 ? 0 : item.requests / maxRequests,
                    trailing: formatBytes(item.bandwidth),
                    onTap: groupBy == 'country' && item.country.isNotEmpty
                        ? () => onDrillDown('region', item.country)
                        : null,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

// ------------------------------------------------------------------ 蜘蛛

class _SpiderTab extends ConsumerWidget {
  const _SpiderTab({required this.query});

  final StatQuery query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(statSpidersProvider(query));

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(statSpidersProvider(query));
        try {
          await ref.read(statSpidersProvider(query).future);
        } catch (_) {}
      },
      child: async.when(
        loading: () => const LoadingView(message: '正在加载蜘蛛统计…'),
        error: (error, _) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(statSpidersProvider(query)),
        ),
        data: (stats) {
          if (stats.items.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 120),
                Center(
                  child: Text(
                    '所选时间范围内没有蜘蛛访问',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            );
          }
          final maxRequests = stats.items.fold<int>(
            0,
            (max, e) => e.requests > max ? e.requests : max,
          );
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(top: 8, bottom: 32),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  '蜘蛛请求合计 ${formatCount(stats.total)} 次',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              for (final item in stats.items)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: StatRankBar(
                    label: item.spider,
                    value: '${formatCount(item.requests)} 次',
                    ratio: maxRequests == 0 ? 0 : item.requests / maxRequests,
                    trailing: formatPercent(item.percent),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------- 客户端

class _ClientTab extends ConsumerWidget {
  const _ClientTab({required this.query});

  final StatQuery query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(statClientsProvider(query));

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(statClientsProvider(query));
        try {
          await ref.read(statClientsProvider(query).future);
        } catch (_) {}
      },
      child: async.when(
        loading: () => const LoadingView(message: '正在加载客户端统计…'),
        error: (error, _) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(statClientsProvider(query)),
        ),
        data: (stats) {
          final maxBrowser = stats.browsers.fold<int>(
            0,
            (max, e) => e.requests > max ? e.requests : max,
          );
          final maxOs = stats.os.fold<int>(
            0,
            (max, e) => e.requests > max ? e.requests : max,
          );
          final maxItem = stats.items.fold<int>(
            0,
            (max, e) => e.requests > max ? e.requests : max,
          );

          if (stats.items.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 120),
                Center(
                  child: Text(
                    '所选时间范围内暂无数据',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            );
          }

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(top: 8, bottom: 32),
            children: [
              SectionCard(
                title: '浏览器',
                child: Column(
                  children: [
                    for (final item in stats.browsers.take(10))
                      StatRankBar(
                        label: item.name.isEmpty ? '未知' : item.name,
                        value: '${formatCount(item.requests)} 次',
                        ratio: maxBrowser == 0 ? 0 : item.requests / maxBrowser,
                      ),
                  ],
                ),
              ),
              SectionCard(
                title: '操作系统',
                child: Column(
                  children: [
                    for (final item in stats.os.take(10))
                      StatRankBar(
                        label: item.name.isEmpty ? '未知' : item.name,
                        value: '${formatCount(item.requests)} 次',
                        ratio: maxOs == 0 ? 0 : item.requests / maxOs,
                      ),
                  ],
                ),
              ),
              SectionCard(
                title: '组合明细',
                child: Column(
                  children: [
                    for (final item in stats.items.take(50))
                      StatRankBar(
                        label:
                            '${item.browser.isEmpty ? '未知' : item.browser}'
                            ' / ${item.os.isEmpty ? '未知' : item.os}',
                        value: '${formatCount(item.requests)} 次',
                        ratio: maxItem == 0 ? 0 : item.requests / maxItem,
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  '客户端明细最多展示 100 条（面板接口限制）',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ------------------------------------------------------------------ 错误

class _ErrorTab extends ConsumerWidget {
  const _ErrorTab({
    required this.query,
    required this.status,
    required this.onStatusChanged,
  });

  final StatQuery query;
  final int status;
  final ValueChanged<int> onStatusChanged;

  static const _statuses = [0, 400, 401, 403, 404, 429, 500, 502, 503, 504];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(statErrorsProvider(query));

    return PagedStatList<ErrorLogItem>(
      state: state,
      header: _FilterHeader(
        title: '状态码',
        children: [
          for (final code in _statuses)
            ChoiceChip(
              label: Text(code == 0 ? '全部' : '$code'),
              selected: status == code,
              onSelected: (_) => onStatusChanged(code),
            ),
        ],
      ),
      onRefresh: () => ref.read(statErrorsProvider(query).notifier).refresh(),
      onLoadMore: () => ref.read(statErrorsProvider(query).notifier).loadMore(),
      emptyMessage: '所选条件下没有错误请求',
      itemBuilder: (context, item, index) => ListTile(
        isThreeLine: true,
        leading: CircleAvatar(
          backgroundColor: item.status >= 500
              ? theme.colorScheme.errorContainer
              : theme.colorScheme.secondaryContainer,
          child: Text(
            '${item.status}',
            style: theme.textTheme.labelMedium?.copyWith(
              color: item.status >= 500
                  ? theme.colorScheme.onErrorContainer
                  : theme.colorScheme.onSecondaryContainer,
            ),
          ),
        ),
        title: Text(
          '${item.method} ${item.uri}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium,
        ),
        subtitle: Text(
          '${formatDateTime(item.createdAt)} · ${item.ip}\n${item.ua}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        onTap: () => showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('${item.status} ${item.method}'),
            content: SingleChildScrollView(
              child: SelectableText(
                [
                  'URI：${item.uri}',
                  '时间：${formatDateTime(item.createdAt)}',
                  'IP：${item.ip}',
                  'User-Agent：${item.ua}',
                  if (item.body.isNotEmpty) '请求体：\n${item.body}',
                ].join('\n\n'),
                style: theme.textTheme.bodySmall,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('关闭'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 列表顶部筛选条。
class _FilterHeader extends StatelessWidget {
  const _FilterHeader({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 4, children: children),
        ],
      ),
    );
  }
}
