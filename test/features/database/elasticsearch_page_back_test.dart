import 'package:acepocket/core/models/server.dart';
import 'package:acepocket/core/providers/paged_notifier_base.dart';
import 'package:acepocket/core/storage/server_store.dart';
import 'package:acepocket/core/version/panel_version_provider.dart';
import 'package:acepocket/features/database/models/database_server.dart';
import 'package:acepocket/features/database/models/es_models.dart';
import 'package:acepocket/features/database/pages/elasticsearch_page.dart';
import 'package:acepocket/features/database/providers/database_providers.dart';
import 'package:acepocket/features/database/providers/es_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Elasticsearch 页把「索引列表 → 文档列表」做成了同一路由内的两层视图。
/// 历史实现只在 AppBar 的返回箭头里 setState 回退内层，没有 [PopScope]：
/// Android 手势返回会直接销毁整页，服务器选择 / 索引 / 搜索词全部丢失。
/// 本用例模拟系统返回，断言第一次返回只退回索引列表、页面仍在栈上。
void main() {
  // 占位服务器信息，均为 RFC 5737 保留地址。
  const esServer = DatabaseServer(
    id: 7,
    name: 'es-local',
    type: 'elasticsearch',
    host: '192.0.2.1',
    port: 9200,
    username: '',
    password: '',
    status: 'valid',
    remark: '',
  );

  const index = EsIndex(
    name: 'logs-2026',
    health: 'green',
    status: 'open',
    docsCount: '12',
    storeSize: '1.2mb',
  );

  Widget buildPage() {
    return ProviderScope(
      overrides: [
        activeServerProvider.overrideWith(_FakeActiveServer.new),
        // 版本探测不参与本用例：给 null 即按功能可用处理。
        panelVersionProvider.overrideWith((ref) async => null),
        databaseServerOptionsProvider(
          'elasticsearch',
        ).overrideWith((ref) async => const [esServer]),
        esIndicesProvider(7).overrideWith((ref) async => const [index]),
        esDataProvider.overrideWith(_FakeEsData.new),
      ],
      child: const MaterialApp(home: ElasticsearchPage()),
    );
  }

  /// 模拟系统返回手势 / 实体返回键。
  Future<void> systemBack(WidgetTester tester) async {
    final message = const JSONMethodCodec().encodeMethodCall(
      const MethodCall('popRoute'),
    );
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/navigation',
      message,
      (_) {},
    );
    await tester.pumpAndSettle();
  }

  testWidgets('文档列表下系统返回先退回索引列表而不是退出整页', (tester) async {
    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    // 进入索引的文档列表。
    await tester.tap(find.text('logs-2026'));
    await tester.pumpAndSettle();
    expect(find.text('索引：logs-2026'), findsOneWidget);

    // 第一次系统返回：只回到索引列表，页面本身还在。
    await systemBack(tester);
    expect(find.text('Elasticsearch 管理'), findsOneWidget);
    expect(find.text('索引：logs-2026'), findsNothing);
    expect(find.byType(ElasticsearchPage), findsOneWidget);
    // 服务器选择没有被重置。
    expect(find.textContaining('es-local'), findsWidgets);
  });

  testWidgets('索引列表下 AppBar 无返回箭头，系统返回交回给路由', (tester) async {
    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.arrow_back), findsNothing);
    // 栈底路由无法再 pop，页面保持原样即可（不应抛异常）。
    await systemBack(tester);
    expect(find.text('Elasticsearch 管理'), findsOneWidget);
  });
}

class _FakeActiveServer extends ActiveServerNotifier {
  @override
  ServerConfig? build() => const ServerConfig(
    id: 'test-server',
    name: '测试面板',
    baseUrl: 'https://192.0.2.1:8888',
    tokenId: '1',
    token: 'placeholder-token',
  );
}

/// 文档分页 Notifier 的替身：直接给一页固定数据，不触碰网络。
class _FakeEsData extends EsDataNotifier {
  @override
  Future<PagedState<EsDocument>> build(EsDataQuery arg) async {
    return const PagedState<EsDocument>(
      items: [EsDocument(id: 'doc-1', index: 'logs-2026', source: '{"a":1}')],
      total: 1,
      page: 1,
      hasMore: false,
    );
  }
}
