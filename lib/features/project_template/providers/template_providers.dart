import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/server_store.dart';
import '../models/lv_option.dart';
import '../models/paged.dart';
import '../models/template.dart';
import '../repo/template_repo.dart';
import 'paged_list_notifier.dart';

/// 模板模块仓库（依赖当前选中服务器的 ApiClient）。
final templateRepoProvider = Provider<TemplateRepo>((ref) {
  return TemplateRepo(ref.watch(apiClientProvider));
});

/// 模板市场的筛选条件（分类 slug + 关键词）。
class TemplateFilter {
  const TemplateFilter({this.category = '', this.query = ''});

  /// 分类 slug，空串表示全部。
  final String category;

  /// 搜索关键词，空串表示不过滤。
  final String query;

  TemplateFilter copyWith({String? category, String? query}) => TemplateFilter(
    category: category ?? this.category,
    query: query ?? this.query,
  );

  @override
  bool operator ==(Object other) =>
      other is TemplateFilter &&
      other.category == category &&
      other.query == query;

  @override
  int get hashCode => Object.hash(category, query);
}

final templateFilterProvider =
    NotifierProvider<TemplateFilterNotifier, TemplateFilter>(
      TemplateFilterNotifier.new,
    );

class TemplateFilterNotifier extends Notifier<TemplateFilter> {
  @override
  TemplateFilter build() => const TemplateFilter();

  void selectCategory(String category) {
    if (state.category == category) return;
    state = state.copyWith(category: category);
  }

  void search(String query) {
    if (state.query == query) return;
    state = state.copyWith(query: query);
  }

  void reset() => state = const TemplateFilter();
}

/// 模板列表（分页，随分类 / 关键词自动重载）。
final templateListProvider =
    AsyncNotifierProvider.autoDispose<
      TemplateListNotifier,
      PagedState<AppTemplate>
    >(TemplateListNotifier.new);

class TemplateListNotifier extends PagedListNotifier<AppTemplate> {
  @override
  Future<PagedState<AppTemplate>> build() {
    // watch 而非 read：切换服务器时 repo 重建，列表需随之重新加载。
    ref.watch(templateRepoProvider);
    ref.watch(templateFilterProvider);
    return super.build();
  }

  @override
  Future<PageResult<AppTemplate>> fetch(int page, int limit) {
    final filter = ref.read(templateFilterProvider);
    return ref
        .read(templateRepoProvider)
        .list(
          page: page,
          limit: limit,
          category: filter.category,
          query: filter.query,
        );
  }
}

/// 应用分类（模板分类标签用），面板未同步应用列表时可能为空。
final templateCategoriesProvider = FutureProvider.autoDispose<List<LvOption>>((
  ref,
) async {
  return ref.watch(templateRepoProvider).categories();
});

/// 分类 slug → 中文名（分类接口不可用时原样返回 slug）。
final templateCategoryLabelProvider =
    Provider.autoDispose<String Function(String)>((ref) {
      final categories = ref.watch(templateCategoriesProvider).valueOrNull;
      return (String slug) {
        if (categories == null) return slug;
        for (final item in categories) {
          if (item.value == slug) return item.label;
        }
        return slug;
      };
    });

/// 单个模板详情（详情页 / 部署页使用）。
final templateDetailProvider = FutureProvider.autoDispose
    .family<AppTemplate, String>((ref, slug) async {
      return ref.watch(templateRepoProvider).get(slug);
    });
