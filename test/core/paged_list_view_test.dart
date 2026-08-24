import 'package:acepocket/core/providers/paged_notifier_base.dart';
import 'package:acepocket/core/widgets/paged_list_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('空列表展示空态文案', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PagedListView<String>(
            state: const AsyncData(
              PagedState(items: [], total: 0, page: 1, hasMore: false),
            ),
            onRefresh: () async {},
            onLoadMore: () {},
            onRetry: () {},
            itemBuilder: (_, item, _) => Text(item),
            emptyMessage: '还没有任何镜像',
          ),
        ),
      ),
    );
    expect(find.text('还没有任何镜像'), findsOneWidget);
  });

  testWidgets('加载下一页失败时展示错误与重试，不再自动触发', (tester) async {
    var loadMore = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PagedListView<String>(
            state: AsyncData(
              PagedState(
                items: const ['a', 'b'],
                total: 10,
                page: 1,
                hasMore: true,
                loadMoreError: Exception('网络中断'),
              ),
            ),
            onRefresh: () async {},
            onLoadMore: () => loadMore++,
            onRetry: () {},
            itemBuilder: (_, item, _) => ListTile(title: Text(item)),
          ),
        ),
      ),
    );
    expect(find.textContaining('加载下一页失败'), findsOneWidget);
    expect(loadMore, 0);
    await tester.tap(find.text('重试'));
    await tester.pump();
    expect(loadMore, 1);
  });

  testWidgets('依赖变化导致 isReloading 时盖住上一台服务器的条目', (tester) async {
    const previous = AsyncData(
      PagedState(
        items: ['old-server.example.com'],
        total: 1,
        page: 1,
        hasMore: false,
      ),
    );
    // ignore: invalid_use_of_internal_member
    final reloading = const AsyncLoading<PagedState<String>>().copyWithPrevious(
      previous,
      isRefresh: false,
    );
    expect(reloading.isReloading, isTrue);
    expect(reloading.hasValue, isTrue);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PagedListView<String>(
            state: reloading,
            onRefresh: () async {},
            onLoadMore: () {},
            onRetry: () {},
            itemBuilder: (_, item, _) => Text(item),
            loadingMessage: '正在加载列表…',
          ),
        ),
      ),
    );
    expect(find.text('old-server.example.com'), findsNothing);
    expect(find.text('正在加载列表…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('下拉刷新 isRefreshing 时继续展示当前条目', (tester) async {
    const previous = AsyncData(
      PagedState(
        items: ['panel.example.com'],
        total: 1,
        page: 1,
        hasMore: false,
      ),
    );
    final refreshing = const AsyncLoading<PagedState<String>>()
        // ignore: invalid_use_of_internal_member
        .copyWithPrevious(previous);
    expect(refreshing.isRefreshing, isTrue);
    expect(refreshing.isReloading, isFalse);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PagedListView<String>(
            state: refreshing,
            onRefresh: () async {},
            onLoadMore: () {},
            onRetry: () {},
            itemBuilder: (_, item, _) => Text(item),
          ),
        ),
      ),
    );
    expect(find.text('panel.example.com'), findsOneWidget);
  });

  group('占位态交叉淡入', () {
    Widget build(AsyncValue<PagedState<String>> state) => MaterialApp(
      home: Scaffold(
        body: PagedListView<String>(
          state: state,
          onRefresh: () async {},
          onLoadMore: () {},
          onRetry: () {},
          itemBuilder: (_, item, _) => ListTile(title: Text(item)),
        ),
      ),
    );

    const withItems = AsyncData(
      PagedState<String>(
        items: <String>['a'],
        total: 1,
        page: 1,
        hasMore: false,
      ),
    );
    const withoutItems = AsyncData(
      PagedState<String>(items: <String>[], total: 0, page: 1, hasMore: false),
    );

    // 过渡期间新旧内容同时挂在树上，若两个可滚动组件共用同一个
    // ScrollController 会直接抛断言，这里逐个方向锁死。
    testWidgets('列表切空态期间不会重复挂载同一个 ScrollController', (tester) async {
      await tester.pumpWidget(build(withItems));
      await tester.pumpWidget(build(withoutItems));
      await tester.pump(const Duration(milliseconds: 60));
      expect(tester.takeException(), isNull);

      await tester.pumpAndSettle();
      expect(find.text('暂无数据'), findsOneWidget);
      expect(find.text('a'), findsNothing);
    });

    testWidgets('空态切列表期间不会重复挂载同一个 ScrollController', (tester) async {
      await tester.pumpWidget(build(withoutItems));
      await tester.pumpWidget(build(withItems));
      await tester.pump(const Duration(milliseconds: 60));
      expect(tester.takeException(), isNull);

      await tester.pumpAndSettle();
      expect(find.text('a'), findsOneWidget);
    });

    testWidgets('加载态切列表期间不会重复挂载同一个 ScrollController', (tester) async {
      await tester.pumpWidget(build(const AsyncLoading<PagedState<String>>()));
      await tester.pumpWidget(build(withItems));
      await tester.pump(const Duration(milliseconds: 60));
      expect(tester.takeException(), isNull);

      await tester.pumpAndSettle();
      expect(find.text('a'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });
}
