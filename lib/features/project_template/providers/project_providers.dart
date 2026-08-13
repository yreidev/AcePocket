import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/server_store.dart';
import '../models/paged.dart';
import '../models/project.dart';
import '../repo/project_repo.dart';
// PagedState 由本文件转导出 core 的实现。
import 'paged_list_notifier.dart';

/// 项目模块仓库（依赖当前选中服务器的 ApiClient）。
final projectRepoProvider = Provider<ProjectRepo>((ref) {
  return ProjectRepo(ref.watch(apiClientProvider));
});

/// 项目列表的类型筛选（`all` 表示全部）。
final projectTypeFilterProvider = NotifierProvider<ProjectTypeFilter, String>(
  ProjectTypeFilter.new,
);

class ProjectTypeFilter extends Notifier<String> {
  @override
  String build() => 'all';

  void select(String type) {
    if (state == type) return;
    state = type;
  }
}

/// 项目列表（分页，随类型筛选自动重载）。
final projectListProvider =
    AsyncNotifierProvider.autoDispose<
      ProjectListNotifier,
      PagedState<ProjectDetail>
    >(ProjectListNotifier.new);

class ProjectListNotifier extends PagedListNotifier<ProjectDetail> {
  @override
  Future<PagedState<ProjectDetail>> build() {
    // watch 而非 read：切换服务器时 repo 重建，列表需随之重新加载。
    ref.watch(projectRepoProvider);
    // 类型筛选变化时自动重新加载第一页。
    ref.watch(projectTypeFilterProvider);
    return super.build();
  }

  @override
  Future<PageResult<ProjectDetail>> fetch(int page, int limit) {
    return ref
        .read(projectRepoProvider)
        .list(
          page: page,
          limit: limit,
          type: ref.read(projectTypeFilterProvider),
        );
  }
}

/// 单个项目详情（详情页 / 编辑页使用）。
final projectDetailProvider = FutureProvider.autoDispose
    .family<ProjectDetail, int>((ref, id) async {
      return ref.watch(projectRepoProvider).get(id);
    });
