import 'dart:async';

import 'package:acepocket/core/providers/paged_notifier_base.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 可手动控制完成时机的假 fetch（不发真实网络请求）。
class FakeFetch {
  /// 每次调用的 (page, limit) 记录。
  final List<(int, int)> calls = [];

  final List<Completer<PagedResult<int>>> _pending = [];

  Future<PagedResult<int>> call(int page, int limit) {
    calls.add((page, limit));
    final completer = Completer<PagedResult<int>>();
    _pending.add(completer);
    return completer.future;
  }

  /// 完成第 [index] 次调用（按发起顺序）。
  void complete(int index, PagedResult<int> result) =>
      _pending[index].complete(result);

  void completeError(int index, Object error) =>
      _pending[index].completeError(error);
}

/// 第 [page] 页的整页数据：条目为连续递增的整数，便于断言是否重复 / 弹回。
PagedResult<int> pageOf(int page, {int limit = 20, int total = 60}) =>
    PagedResult(
      items: List.generate(limit, (i) => (page - 1) * limit + i),
      total: total,
    );

void main() {
  group('PagedPager', () {
    late PagedPager<int> pager;
    late AsyncValue<PagedState<int>> state;

    AsyncValue<PagedState<int>> read() => state;
    void write(AsyncValue<PagedState<int>> value) => state = value;

    /// 初始化：第一页 0..19，total 60，hasMore = true。
    Future<void> seed({int total = 60}) async {
      state = AsyncData(
        await pager.buildFirstPage(
            (page, limit) async => pageOf(1, limit: limit, total: total)),
      );
    }

    setUp(() {
      pager = PagedPager<int>();
    });

    test('loadMore 追加下一页并推进页码', () async {
      await seed();
      final fetch = FakeFetch();
      final future =
          pager.loadMore(read: read, write: write, fetch: fetch.call);
      expect(state.requireValue.loadingMore, isTrue);
      fetch.complete(0, pageOf(2));
      await future;

      final value = state.requireValue;
      expect(value.items, List.generate(40, (i) => i));
      expect(value.page, 2);
      expect(value.total, 60);
      expect(value.hasMore, isTrue);
      expect(value.loadingMore, isFalse);
      expect(value.loadMoreError, isNull);
    });

    test('空页收尾：total 修正为已加载条数且 hasMore=false', () async {
      await seed(total: 60);
      final fetch = FakeFetch();
      final future =
          pager.loadMore(read: read, write: write, fetch: fetch.call);
      fetch.complete(0, const PagedResult(items: [], total: 60));
      await future;

      final value = state.requireValue;
      expect(value.items.length, 20);
      expect(value.total, 20, reason: '空页收尾应以已加载条数为准');
      expect(value.hasMore, isFalse);
    });

    test('返回不足一页视为到底', () async {
      await seed(total: 60);
      final fetch = FakeFetch();
      final future =
          pager.loadMore(read: read, write: write, fetch: fetch.call);
      fetch.complete(
          0, PagedResult(items: List.generate(5, (i) => 20 + i), total: 60));
      await future;

      final value = state.requireValue;
      expect(value.items.length, 25);
      expect(value.hasMore, isFalse);
    });

    test('refresh 与 loadMore 交错：慢 loadMore 的过期响应被丢弃', () async {
      await seed();
      final fetch = FakeFetch();
      // loadMore 先发起但响应慢。
      final loadMore =
          pager.loadMore(read: read, write: write, fetch: fetch.call);
      // refresh 后发起先返回（列表已被删掉一条：只剩 19 条）。
      final refresh = pager.reloadFirstPage(
        fetch: fetch.call,
        write: write,
        toErrorState: false,
      );
      fetch.complete(
        1,
        PagedResult(items: List.generate(19, (i) => i), total: 19),
      );
      await refresh;
      // 慢 loadMore 的响应此时才到达，必须被丢弃。
      fetch.complete(0, pageOf(2));
      await loadMore;

      final value = state.requireValue;
      expect(value.items, List.generate(19, (i) => i),
          reason: '过期的 loadMore 响应不得追加（否则条目重复 / 已删条目复活）');
      expect(value.page, 1);
      expect(value.loadingMore, isFalse);
    });

    test('慢 refresh 的过期响应被丢弃（后发先至）', () async {
      await seed();
      final fetch = FakeFetch();
      final slow = pager.reloadFirstPage(
        fetch: fetch.call,
        write: write,
        toErrorState: false,
      );
      final fast = pager.reloadFirstPage(
        fetch: fetch.call,
        write: write,
        toErrorState: false,
      );
      // 后发起的 refresh 先返回（100 起的新数据）。
      fetch.complete(
        1,
        PagedResult(items: List.generate(20, (i) => 100 + i), total: 20),
      );
      await fast;
      // 先发起的 refresh 响应慢，返回旧数据，必须被丢弃。
      fetch.complete(0, pageOf(1));
      await slow;

      expect(state.requireValue.items, List.generate(20, (i) => 100 + i),
          reason: '慢响应后到达时不得把列表弹回旧数据');
    });

    test('loadMore 在途时重复触发不并发发起', () async {
      await seed();
      final fetch = FakeFetch();
      final first = pager.loadMore(read: read, write: write, fetch: fetch.call);
      final second =
          pager.loadMore(read: read, write: write, fetch: fetch.call);
      await second;
      expect(fetch.calls, [(2, 20)], reason: '第二次触发应被在途标志拦截');
      fetch.complete(0, pageOf(2));
      await first;
      expect(state.requireValue.items.length, 40);
    });

    test('refresh 不清掉在途标志：期间不并发、结束后可再加载', () async {
      await seed();
      final fetch = FakeFetch();
      // loadMore A 在途。
      final loadMoreA =
          pager.loadMore(read: read, write: write, fetch: fetch.call);
      // refresh 完成（新一代次的第一页）。
      final refresh = pager.reloadFirstPage(
        fetch: fetch.call,
        write: write,
        toErrorState: false,
      );
      fetch.complete(1, pageOf(1));
      await refresh;
      // A 仍在途：此时再触发 loadMore 不得并发发起第二个请求。
      await pager.loadMore(read: read, write: write, fetch: fetch.call);
      expect(fetch.calls.length, 2, reason: 'refresh 不得清掉在途标志导致并发');
      // A 的过期响应到达后被丢弃。
      fetch.complete(0, pageOf(2));
      await loadMoreA;
      expect(state.requireValue.items.length, 20);
      // A 结束后可以正常加载下一页，且只追加一次。
      final loadMoreC =
          pager.loadMore(read: read, write: write, fetch: fetch.call);
      expect(fetch.calls.length, 3);
      fetch.complete(2, pageOf(2));
      await loadMoreC;
      expect(state.requireValue.items, List.generate(40, (i) => i));
    });

    test('loadMore 失败记录 loadMoreError 并保留数据，重试成功后清除', () async {
      await seed();
      final fetch = FakeFetch();
      final failed =
          pager.loadMore(read: read, write: write, fetch: fetch.call);
      fetch.completeError(0, StateError('网络错误'));
      await failed;

      var value = state.requireValue;
      expect(value.items.length, 20, reason: '失败不得破坏已加载数据');
      expect(value.loadingMore, isFalse);
      expect(value.loadMoreError, isA<StateError>());

      // 重试：发起时清除错误，成功后正常追加。
      final retry = pager.loadMore(read: read, write: write, fetch: fetch.call);
      expect(state.requireValue.loadMoreError, isNull);
      fetch.complete(1, pageOf(2));
      await retry;
      value = state.requireValue;
      expect(value.items.length, 40);
      expect(value.loadMoreError, isNull);
    });

    test('loadMore 失败但响应已过期时不写入 loadMoreError', () async {
      await seed();
      final fetch = FakeFetch();
      final loadMore =
          pager.loadMore(read: read, write: write, fetch: fetch.call);
      final refresh = pager.reloadFirstPage(
        fetch: fetch.call,
        write: write,
        toErrorState: false,
      );
      fetch.complete(1, pageOf(1));
      await refresh;
      // 过期的 loadMore 失败：不得把错误挂到新一代次的列表上。
      fetch.completeError(0, StateError('网络错误'));
      await loadMore;
      expect(state.requireValue.loadMoreError, isNull);
    });

    test('reloadFirstPage(toErrorState: false) 失败保留旧数据并抛出', () async {
      await seed();
      await expectLater(
        pager.reloadFirstPage(
          fetch: (page, limit) async => throw StateError('网络错误'),
          write: write,
          toErrorState: false,
        ),
        throwsA(isA<StateError>()),
      );
      expect(state.hasValue, isTrue);
      expect(state.requireValue.items.length, 20);
    });

    test('reloadFirstPage(toErrorState: true) 失败进入错误态', () async {
      await seed();
      await pager.reloadFirstPage(
        fetch: (page, limit) async => throw StateError('网络错误'),
        write: write,
        toErrorState: true,
      );
      expect(state.hasError, isTrue);
    });

    test('buildFirstPage（依赖变化重建）使在途 loadMore 过期', () async {
      await seed();
      final fetch = FakeFetch();
      final loadMore =
          pager.loadMore(read: read, write: write, fetch: fetch.call);
      // 模拟切换服务器 / 筛选条件变化触发的 build 重跑。
      state = AsyncData(
        await pager.buildFirstPage((page, limit) async =>
            PagedResult(items: List.generate(20, (i) => 200 + i), total: 20)),
      );
      fetch.complete(0, pageOf(2));
      await loadMore;

      expect(state.requireValue.items, List.generate(20, (i) => 200 + i),
          reason: '重建后旧代次的 loadMore 响应不得写入');
    });
  });

  group('PagedAsyncNotifier（Riverpod 集成）', () {
    test('refresh 期间在途 loadMore 的结果被丢弃', () async {
      final fetch = FakeFetch();
      TestPagedNotifier.fetch = fetch;
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final sub = container.listen(testPagedProvider, (_, __) {});
      addTearDown(sub.close);

      // 首屏。
      fetch.complete(0, pageOf(1));
      await container.read(testPagedProvider.future);
      final notifier = container.read(testPagedProvider.notifier);

      // loadMore 在途时下拉刷新，刷新先返回。
      final loadMore = notifier.loadMore();
      final refresh = notifier.reloadFirstPage(toErrorState: false);
      fetch.complete(
        2,
        PagedResult(items: List.generate(19, (i) => i), total: 19),
      );
      await refresh;
      fetch.complete(1, pageOf(2));
      await loadMore;

      final value = container.read(testPagedProvider).requireValue;
      expect(value.items, List.generate(19, (i) => i));
      expect(value.page, 1);
      expect(value.hasMore, isFalse);
      expect(fetch.calls, [(1, 20), (2, 20), (1, 20)]);
    });
  });
}

class TestPagedNotifier extends PagedAsyncNotifier<int> {
  static FakeFetch? fetch;

  @override
  Future<PagedResult<int>> fetchPage(int page, int limit) =>
      fetch!.call(page, limit);
}

final testPagedProvider =
    AsyncNotifierProvider.autoDispose<TestPagedNotifier, PagedState<int>>(
        TestPagedNotifier.new);
