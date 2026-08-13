import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/version/panel_feature.dart';
import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/empty_view.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/feature_gate.dart';
import '../../../core/widgets/loading_view.dart';
import '../models/lv_option.dart';
import '../models/template.dart';
import '../providers/template_providers.dart';
import '../widgets/list_footer.dart';
import '../widgets/template_tile.dart';

/// 应用模板市场页 `/templates`。
///
/// 模板来自面板同步的应用商店数据与本地模板目录，可按分类筛选、
/// 按名称 / 描述 / 官网搜索，选中后用模板创建 docker compose 编排。
class TemplateListPage extends ConsumerStatefulWidget {
  const TemplateListPage({super.key});

  @override
  ConsumerState<TemplateListPage> createState() => _TemplateListPageState();
}

class _TemplateListPageState extends ConsumerState<TemplateListPage> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _searchController.text = ref.read(templateFilterProvider).query;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 240) {
      _loadMore();
    }
  }

  /// 加载下一页；失败会记录到 `state.loadMoreError`，由列表底部展示并可重试。
  Future<void> _loadMore() =>
      ref.read(templateListProvider.notifier).loadMore();

  Future<void> _refresh() async {
    ref.invalidate(templateCategoriesProvider);
    await ref.read(templateListProvider.notifier).refresh();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      ref.read(templateFilterProvider.notifier).search(value.trim());
    });
  }

  void _openDetail(AppTemplate template) {
    context.push('/templates/${Uri.encodeComponent(template.slug)}');
  }

  void _openDeploy(AppTemplate template) {
    context.push('/templates/${Uri.encodeComponent(template.slug)}/deploy');
  }

  @override
  Widget build(BuildContext context) {
    final listState = ref.watch(templateListProvider);
    final filter = ref.watch(templateFilterProvider);
    final categoriesAsync = ref.watch(templateCategoriesProvider);
    final categoryLabel = ref.watch(templateCategoryLabelProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('应用模板')),
      body: Column(
        children: [
          const FeatureUnsupportedBanner(feature: PanelFeature.template),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: '搜索模板名称、描述或官网',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : A11yIconButton(
                        tooltip: '清空搜索关键词',
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _searchController.clear();
                          _debounce?.cancel();
                          ref.read(templateFilterProvider.notifier).search('');
                          setState(() {});
                        },
                      ),
              ),
              onChanged: (value) {
                setState(() {});
                _onSearchChanged(value);
              },
              onSubmitted: (value) {
                _debounce?.cancel();
                ref.read(templateFilterProvider.notifier).search(value.trim());
              },
            ),
          ),
          _CategoryBar(
            categories: categoriesAsync.valueOrNull ?? const [],
            selected: filter.category,
            onSelected: (value) =>
                ref.read(templateFilterProvider.notifier).selectCategory(value),
          ),
          const Divider(height: 1),
          Expanded(
            child: listState.when(
              loading: () => const LoadingView(message: '正在加载模板…'),
              error: (error, _) => ErrorView(error: error, onRetry: _refresh),
              data: (state) {
                if (state.isEmpty) {
                  return RefreshIndicator(
                    onRefresh: _refresh,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.15,
                        ),
                        EmptyView(
                          message:
                              filter.query.isNotEmpty ||
                                  filter.category.isNotEmpty
                              ? '没有匹配的模板\n换个关键词或分类再试试'
                              : '暂无模板\n请先在面板「应用商店」同步应用数据',
                          icon: Icons.widgets_outlined,
                        ),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.builder(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(top: 4, bottom: 32),
                    itemCount: state.items.length + 1,
                    itemBuilder: (context, index) {
                      if (index == state.items.length) {
                        return ListFooter(
                          loading: state.loadingMore,
                          hasMore: state.hasMore,
                          total: state.total,
                          unit: '个模板',
                          error: state.loadMoreError,
                          onRetry: _loadMore,
                        );
                      }
                      final template = state.items[index];
                      return TemplateTile(
                        template: template,
                        categoryLabel: categoryLabel,
                        onTap: () => _openDetail(template),
                        onDeploy: () => _openDeploy(template),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 分类筛选栏（分类接口不可用时只展示「全部」）。
class _CategoryBar extends StatelessWidget {
  const _CategoryBar({
    required this.categories,
    required this.selected,
    required this.onSelected,
  });

  final List<LvOption> categories;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final options = <(String, String)>[
      ('', '全部'),
      for (final item in categories) (item.value, item.label),
    ];
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: options.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final option = options[index];
          return ChoiceChip(
            label: Text(option.$2),
            selected: selected == option.$1,
            onSelected: (_) => onSelected(option.$1),
          );
        },
      ),
    );
  }
}
