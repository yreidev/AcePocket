import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/server_store.dart';
import '../models/paged.dart';
import '../models/process_info.dart';
import '../repo/process_repo.dart';

/// 每页条数。
const int kProcessPageSize = 20;

/// 进程仓库；未选择服务器时为 null。
final processRepoProvider = Provider<ProcessRepo?>((ref) {
  final server = ref.watch(activeServerProvider);
  if (server == null) return null;
  return ProcessRepo(ref.watch(apiClientProvider));
});

/// 进程列表查询条件（排序字段 / 升降序 / 关键词）。
final processQueryProvider =
    NotifierProvider<ProcessQueryNotifier, ProcessQuery>(
      ProcessQueryNotifier.new,
    );

class ProcessQueryNotifier extends Notifier<ProcessQuery> {
  @override
  ProcessQuery build() => const ProcessQuery();

  void setSort(String sort) {
    if (state.sort == sort) return;
    state = state.copyWith(sort: sort);
  }

  void setDesc(bool desc) {
    if (state.desc == desc) return;
    state = state.copyWith(desc: desc);
  }

  void toggleOrder() => state = state.copyWith(desc: !state.desc);

  void setKeyword(String keyword) {
    if (state.keyword == keyword) return;
    state = state.copyWith(keyword: keyword);
  }
}

typedef ProcessListState = PagedListState<ProcessInfo>;

/// 进程列表（查询条件或当前服务器变化时自动重新加载）。
final processListProvider =
    NotifierProvider.autoDispose<ProcessListNotifier, ProcessListState>(
      ProcessListNotifier.new,
    );

class ProcessListNotifier extends Notifier<ProcessListState> {
  ProcessRepo? _repo;
  ProcessQuery _query = const ProcessQuery();
  bool _alive = true;
  int _generation = 0;

  @override
  ProcessListState build() {
    _alive = true;
    ref.onDispose(() => _alive = false);

    _repo = ref.watch(processRepoProvider);
    _query = ref.watch(processQueryProvider);

    if (_repo == null) {
      return ProcessListState(
        isLoading: false,
        error: '尚未选择服务器，请先在服务器列表中选择一台面板',
      );
    }

    final generation = ++_generation;
    Future.microtask(() => _loadFirstPage(generation));
    return ProcessListState(isLoading: true);
  }

  /// 下拉刷新 / 操作后刷新（不清空当前列表）；
  /// 失败时返回错误对象供页面提示（成功返回 null）。
  ///
  /// 刷新失败时保留已加载的进程，避免一次网络抖动就把整页换成错误页、
  /// 连带丢失滚动位置；仅在列表本来就为空时才写入 `state.error`。
  Future<Object?> refresh() async {
    if (_repo == null) return null;
    return _loadFirstPage(++_generation, silent: true);
  }

  /// 错误页「重试」：先展示首屏加载态再重新拉取，让点击有即时反馈。
  Future<Object?> reload() async {
    if (_repo == null) return null;
    return _loadFirstPage(++_generation);
  }

  Future<Object?> _loadFirstPage(int generation, {bool silent = false}) async {
    final repo = _repo;
    if (repo == null || _stale(generation)) return null;
    if (!silent) {
      _set(generation, state.copyWith(isLoading: true, clearError: true));
    }
    try {
      final paged = await repo.list(
        page: 1,
        limit: kProcessPageSize,
        sort: _query.sort,
        order: _query.order,
        keyword: _query.keyword,
      );
      _set(
        generation,
        ProcessListState(
          items: paged.items,
          total: paged.total,
          page: 1,
          isLoading: false,
        ),
      );
      return null;
    } catch (e) {
      if (_stale(generation)) return null;
      if (state.items.isNotEmpty) {
        _set(
          generation,
          state.copyWith(
            isLoading: false,
            isLoadingMore: false,
            clearError: true,
          ),
        );
      } else {
        _set(generation, ProcessListState(isLoading: false, error: e));
      }
      return e;
    }
  }

  /// 加载下一页；失败时返回错误对象（成功返回 null）。
  Future<Object?> loadMore() async {
    final repo = _repo;
    if (repo == null) return null;
    final current = state;
    if (current.isLoading || current.isLoadingMore || !current.hasMore) {
      return null;
    }
    final generation = _generation;
    _set(generation, current.copyWith(isLoadingMore: true));
    try {
      final next = current.page + 1;
      final paged = await repo.list(
        page: next,
        limit: kProcessPageSize,
        sort: _query.sort,
        order: _query.order,
        keyword: _query.keyword,
      );
      if (_stale(generation)) return null;
      _set(
        generation,
        state.copyWith(
          items: [...state.items, ...paged.items],
          total: paged.total,
          page: next,
          isLoadingMore: false,
        ),
      );
      return null;
    } catch (e) {
      _set(generation, state.copyWith(isLoadingMore: false));
      return e;
    }
  }

  /// 从列表中移除指定 PID（结束进程成功后即时反馈）。
  void removePid(int pid) {
    final items = state.items.where((p) => p.pid != pid).toList();
    final removed = state.items.length - items.length;
    if (removed == 0) return;
    _set(
      _generation,
      state.copyWith(
        items: items,
        total: state.total - removed < 0 ? 0 : state.total - removed,
      ),
    );
  }

  bool _stale(int generation) => !_alive || generation != _generation;

  void _set(int generation, ProcessListState next) {
    if (_stale(generation)) return;
    state = next;
  }
}

/// 进程详情。
final processDetailProvider = FutureProvider.autoDispose
    .family<ProcessInfo, int>((ref, pid) async {
      final repo = ref.watch(processRepoProvider);
      if (repo == null) {
        throw StateError('尚未选择服务器');
      }
      return repo.detail(pid);
    });
