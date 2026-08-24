import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/version/panel_feature.dart';
import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/app_snack.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/empty_view.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/feature_gate.dart';
import '../../../core/widgets/loading_view.dart';
import '../../../core/widgets/task_snack.dart';
import '../models/environment_models.dart';
import '../providers/environment_providers.dart';
import '../widgets/environment_tile.dart';
import '../widgets/environment_ui.dart';

/// 运行环境列表页（`/environments`）。
///
/// 按类型（`GET /environment/types`）筛选与分组，展示可用版本与已安装版本，
/// 支持安装 / 更新 / 卸载（均为面板后台任务）以及进入各环境的配置管理页。
///
/// 说明：`GET /environment/list` 在面板侧**不分页**（`EnvironmentService.List`
/// 直接返回过滤后的完整数组），因此这里不做上拉加载，只提供下拉刷新；
/// 关键字在客户端按「名称 / 描述包含」过滤，与面板过滤语义一致。
class EnvironmentListPage extends ConsumerStatefulWidget {
  const EnvironmentListPage({super.key});

  @override
  ConsumerState<EnvironmentListPage> createState() =>
      _EnvironmentListPageState();
}

class _EnvironmentListPageState extends ConsumerState<EnvironmentListPage> {
  late final TextEditingController _searchController = TextEditingController(
    text: ref.read(environmentFilterProvider).query,
  );

  /// 正在提交操作的环境（`type/slug`）。
  String? _busyKey;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    ref.invalidate(environmentTypesProvider);
    ref.invalidate(environmentListProvider);
    await ref.read(environmentListProvider.future);
  }

  Future<void> _run(
    EnvironmentDetail env,
    Future<void> Function() action,
    String successMessage,
  ) async {
    setState(() => _busyKey = env.key);
    try {
      await action();
      ref.invalidate(environmentListProvider);
      if (!mounted) return;
      showTaskSubmittedSnack(context, successMessage);
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busyKey = null);
    }
  }

  Future<void> _onAction(
    EnvironmentDetail env,
    EnvironmentAction action,
  ) async {
    final repo = ref.read(environmentRepoProvider);
    switch (action) {
      case EnvironmentAction.manage:
        _openManagePage(env);
      case EnvironmentAction.install:
        final ok = await showConfirmDialog(
          context,
          title: '安装 ${env.name}？',
          content: env.customSupported
              ? '面板将在后台编译安装该环境，耗时较长，可在任务中心查看进度。'
                    '如需自定义编译参数，请先在面板 Web 端配置。'
              : '面板将在后台下载并安装该环境，可在任务中心查看进度。',
          confirmText: '安装',
        );
        if (!ok) return;
        await _run(
          env,
          () => repo.install(env.type, env.slug),
          '已提交安装任务：${env.name}',
        );
      case EnvironmentAction.update:
        final ok = await showConfirmDialog(
          context,
          title: '更新 ${env.name}？',
          content:
              '将从 ${env.installedVersion.isEmpty ? '当前版本' : env.installedVersion}'
              ' 更新到 ${env.version}，更新期间该环境可能短暂不可用。',
          confirmText: '更新',
        );
        if (!ok) return;
        await _run(
          env,
          () => repo.update(env.type, env.slug),
          '已提交更新任务：${env.name}',
        );
      case EnvironmentAction.uninstall:
        final ok = await showConfirmDialog(
          context,
          title: '卸载 ${env.name}？',
          content:
              '卸载后依赖该环境的网站 / 应用将无法运行，配置文件也会一并删除，'
              '此操作不可恢复。',
          confirmText: '卸载',
          danger: true,
        );
        if (!ok) return;
        await _run(
          env,
          () => repo.uninstall(env.type, env.slug),
          '已提交卸载任务：${env.name}',
        );
    }
  }

  void _openManagePage(EnvironmentDetail env) {
    final phpVersion = env.phpVersion;
    if (env.type == 'php' && phpVersion != null) {
      context.push('/environments/php/$phpVersion');
      return;
    }
    context.push('/environments/runtime/${env.type}/${env.slug}');
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(environmentFilterProvider);
    final environments = ref.watch(visibleEnvironmentsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('运行环境'),
        actions: [
          A11yIconButton(
            tooltip: '刷新运行环境列表',
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
        ],
      ),
      body: Column(
        children: [
          const FeatureUnsupportedBanner(feature: PanelFeature.environment),
          _header(filter),
          const Divider(height: 1),
          Expanded(
            child: environments.when(
              loading: () => const LoadingView(message: '读取运行环境列表…'),
              error: (error, _) => ErrorView(
                error: error,
                onRetry: () => ref.invalidate(environmentListProvider),
              ),
              data: (items) => RefreshIndicator(
                onRefresh: _refresh,
                child: items.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          SizedBox(
                            height: MediaQuery.sizeOf(context).height * 0.5,
                            child: EmptyView(
                              message: filter.query.isNotEmpty
                                  ? '没有匹配「${filter.query}」的运行环境'
                                  : filter.onlyInstalled
                                  ? '当前筛选下没有已安装的运行环境'
                                  : '暂无可用运行环境',
                              icon: Icons.dns_outlined,
                            ),
                          ),
                        ],
                      )
                    : _buildList(items, filter),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------- 头部

  Widget _header(EnvironmentFilter filter) {
    final theme = Theme.of(context);
    final types = ref.watch(environmentTypesProvider);
    final typeItems = types.value ?? const <EnvironmentType>[];

    return Material(
      color: theme.colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                isDense: true,
                hintText: '搜索环境名称或描述',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: filter.query.isEmpty
                    ? null
                    : A11yIconButton(
                        tooltip: '清空搜索关键字',
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          ref
                              .read(environmentFilterProvider.notifier)
                              .setQuery('');
                        },
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onChanged: (value) =>
                  ref.read(environmentFilterProvider.notifier).setQuery(value),
            ),
          ),
          SizedBox(
            height: 46,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _typeChip(label: '全部', value: '', current: filter.type),
                for (final type in typeItems)
                  _typeChip(
                    label: type.label,
                    value: type.value,
                    current: filter.type,
                  ),
                const SizedBox(width: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: FilterChip(
                    label: const Text('仅已安装'),
                    selected: filter.onlyInstalled,
                    onSelected: (value) => ref
                        .read(environmentFilterProvider.notifier)
                        .setOnlyInstalled(value),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _typeChip({
    required String label,
    required String value,
    required String current,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8, top: 6, bottom: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: current == value,
        onSelected: (_) =>
            ref.read(environmentFilterProvider.notifier).setType(value),
      ),
    );
  }

  // ------------------------------------------------------------------- 列表

  Widget _buildList(List<EnvironmentDetail> items, EnvironmentFilter filter) {
    // 指定了类型时不再分组，直接平铺。
    if (filter.type.isNotEmpty) {
      return ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 6, bottom: 28),
        itemCount: items.length,
        itemBuilder: (context, index) => _tile(items[index]),
      );
    }

    final grouped = _groupByType(items);
    final rows = <Widget>[];
    for (final entry in grouped) {
      rows.add(SubHeader('${entry.$1}（${entry.$2.length}）'));
      rows.addAll(entry.$2.map(_tile));
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 28),
      children: rows,
    );
  }

  Widget _tile(EnvironmentDetail env) => EnvironmentTile(
    key: ValueKey(env.key),
    environment: env,
    busy: _busyKey == env.key,
    onAction: (action) => _onAction(env, action),
  );

  /// 按类型分组，顺序遵循 `/environment/types` 的返回顺序。
  List<(String, List<EnvironmentDetail>)> _groupByType(
    List<EnvironmentDetail> items,
  ) {
    final types =
        ref.read(environmentTypesProvider).value ?? const <EnvironmentType>[];
    final order = <String>[for (final type in types) type.value];
    final buckets = <String, List<EnvironmentDetail>>{};
    for (final item in items) {
      buckets.putIfAbsent(item.type, () => <EnvironmentDetail>[]).add(item);
    }
    final keys = buckets.keys.toList()
      ..sort((a, b) {
        final ia = order.indexOf(a);
        final ib = order.indexOf(b);
        if (ia == ib) return a.compareTo(b);
        if (ia < 0) return 1;
        if (ib < 0) return -1;
        return ia.compareTo(ib);
      });
    String labelOf(String type) {
      for (final item in types) {
        if (item.value == type) return item.label;
      }
      return environmentTypeLabel(type);
    }

    return [for (final key in keys) (labelOf(key), buckets[key]!)];
  }
}
