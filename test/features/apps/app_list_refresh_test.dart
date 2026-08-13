import 'package:acepocket/core/api/api_client.dart';
import 'package:acepocket/core/api/api_exception.dart';
import 'package:acepocket/core/models/server.dart';
import 'package:acepocket/features/apps/models/app_item.dart';
import 'package:acepocket/features/apps/models/paged.dart';
import 'package:acepocket/features/apps/providers/apps_providers.dart';
import 'package:acepocket/features/apps/repo/apps_repo.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 占位服务器：RFC 5737 文档地址 + 假令牌，不指向任何真实主机。
const _server = ServerConfig(
  id: 'test-server',
  name: '测试面板',
  baseUrl: 'https://192.0.2.1:8888',
  tokenId: '1',
  token: 'unit-test-token',
);

/// 可控成败的应用仓库替身；不发起任何真实请求。
class _FakeAppsRepo extends AppsRepo {
  _FakeAppsRepo() : super(ApiClient(_server));

  bool fail = false;

  @override
  Future<Paged<AppItem>> list({
    required int page,
    required int limit,
    String category = '',
    String query = '',
    bool installedOnly = false,
  }) async {
    if (fail) throw const ApiException('网络连接失败');
    return Paged<AppItem>(
      items: [
        AppItem.fromJson(const <String, dynamic>{
          'slug': 'nginx',
          'name': 'Nginx',
          'installed': true,
        }),
      ],
      total: 1,
    );
  }
}

void main() {
  test('下拉刷新失败保留已加载的应用，仅返回错误供页面提示', () async {
    final repo = _FakeAppsRepo();
    final container = ProviderContainer(
      overrides: [appsRepoProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);

    final sub = container.listen(
      appListProvider(true),
      (_, __) {},
      fireImmediately: true,
    );
    await Future<void>.delayed(Duration.zero);
    expect(sub.read().items, hasLength(1));

    repo.fail = true;
    final error = await container
        .read(appListProvider(true).notifier)
        .refresh();

    expect(error, isA<ApiException>());
    final state = sub.read();
    expect(state.items, hasLength(1), reason: '刷新失败不应清空已加载数据');
    expect(state.error, isNull, reason: '有数据时不应切换到整页错误态');
    expect(state.isLoading, isFalse);
  });

  test('首屏没有任何数据时，加载失败仍写入错误态（展示错误页）', () async {
    final repo = _FakeAppsRepo()..fail = true;
    final container = ProviderContainer(
      overrides: [appsRepoProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);

    final sub = container.listen(
      appListProvider(false),
      (_, __) {},
      fireImmediately: true,
    );
    await Future<void>.delayed(Duration.zero);

    final state = sub.read();
    expect(state.items, isEmpty);
    expect(state.error, isA<ApiException>());
    expect(state.isLoading, isFalse);
  });
}
