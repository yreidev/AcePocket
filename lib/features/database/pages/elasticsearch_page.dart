import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/server_store.dart';
import '../../../core/version/panel_feature.dart';
import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/app_snack.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/empty_view.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/feature_gate.dart';
import '../../../core/widgets/loading_view.dart';
import '../models/database_server.dart';
import '../models/es_models.dart';
import '../providers/database_providers.dart';
import '../providers/es_providers.dart';
import '../widgets/database_server_sheet.dart';
import '../widgets/db_feedback.dart';
import '../widgets/es_document_sheet.dart';
import '../widgets/es_tiles.dart';
import '../widgets/no_server_view.dart';
import '../widgets/paged_list.dart';
import '../widgets/server_dropdown.dart';
import '../widgets/text_input_dialog.dart';

/// Elasticsearch 管理页（`/databases/elasticsearch`）。
///
/// 未选择索引时展示索引列表；选择索引后展示该索引的文档列表。
class ElasticsearchPage extends ConsumerStatefulWidget {
  const ElasticsearchPage({super.key});

  @override
  ConsumerState<ElasticsearchPage> createState() => _ElasticsearchPageState();
}

class _ElasticsearchPageState extends ConsumerState<ElasticsearchPage> {
  final TextEditingController _searchController = TextEditingController();

  int? _serverId;
  String? _index;
  String _search = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openIndex(String name) {
    _searchController.clear();
    setState(() {
      _index = name;
      _search = '';
    });
  }

  void _backToIndices() {
    _searchController.clear();
    setState(() {
      _index = null;
      _search = '';
    });
  }

  /// 系统返回（手势 / 返回键）：处在文档列表时先退回索引列表，而不是整页出栈。
  ///
  /// 本页把「索引列表 → 文档列表」做成了同一路由内的两层视图，没有拦截的话
  /// Android 手势返回会直接销毁整页，服务器选择、索引、搜索词一并丢失。
  void _handlePop(bool didPop, Object? result) {
    if (didPop) return;
    _backToIndices();
  }

  /// 重新拉取索引列表并等待结果（供下拉刷新使用）。
  Future<void> _refreshIndices(int serverId) async {
    ref.invalidate(esIndicesProvider(serverId));
    try {
      await ref.read(esIndicesProvider(serverId).future);
    } catch (_) {
      // 错误已由 provider 的 AsyncValue 呈现，这里只需结束刷新动画。
    }
  }

  Future<void> _addServer() async {
    final saved =
        await DatabaseServerSheet.show(context, initialType: 'elasticsearch');
    if (saved == true) ref.invalidate(databaseServerOptionsProvider);
  }

  Future<void> _createIndex(int serverId) async {
    final name = await showTextInputDialog(
      context,
      title: '创建索引',
      label: '索引名',
      hintText: '如 logs-2026',
      confirmText: '创建',
    );
    if (name == null || !mounted) return;
    if (name.isEmpty) {
      showErrorSnack(context, '请填写索引名');
      return;
    }

    final ok = await runGuarded(
      context,
      () => ref
          .read(databaseRepoProvider)
          .esIndexCreate(serverId: serverId, name: name),
      success: '索引创建成功',
    );
    if (ok) ref.invalidate(esIndicesProvider(serverId));
  }

  Future<void> _deleteIndex(int serverId, EsIndex index) async {
    final confirmed = await showConfirmDialog(
      context,
      title: '删除索引',
      content: '确定要删除索引「${index.name}」吗？\n其中的所有文档都会被永久删除。',
      confirmText: '删除',
      danger: true,
    );
    if (!confirmed || !mounted) return;

    final ok = await runGuarded(
      context,
      () => ref
          .read(databaseRepoProvider)
          .esIndexDelete(serverId: serverId, name: index.name),
      success: '索引已删除',
    );
    if (ok) {
      if (_index == index.name) _backToIndices();
      ref.invalidate(esIndicesProvider(serverId));
    }
  }

  Future<void> _createDocument(EsDataQuery query) async {
    final saved = await EsDocumentSheet.show(
      context,
      serverId: query.serverId,
      index: query.index,
    );
    if (saved == true) {
      await ref.read(esDataProvider(query).notifier).refresh();
      ref.invalidate(esIndicesProvider(query.serverId));
    }
  }

  Future<void> _viewDocument(EsDataQuery query, EsDocument document) async {
    final saved = await EsDocumentSheet.show(
      context,
      serverId: query.serverId,
      index: query.index,
      docId: document.id,
    );
    if (saved == true) {
      await ref.read(esDataProvider(query).notifier).refresh();
    }
  }

  Future<void> _deleteDocument(EsDataQuery query, EsDocument document) async {
    final confirmed = await showConfirmDialog(
      context,
      title: '删除文档',
      content: '确定要删除文档「${document.id}」吗？该操作不可恢复。',
      confirmText: '删除',
      danger: true,
    );
    if (!confirmed || !mounted) return;

    final ok = await runGuarded(
      context,
      () => ref.read(databaseRepoProvider).esDocumentDelete(
            serverId: query.serverId,
            index: query.index,
            id: document.id,
          ),
      success: '文档已删除',
    );
    if (ok) {
      await ref.read(esDataProvider(query).notifier).refresh();
      ref.invalidate(esIndicesProvider(query.serverId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final panelServer = ref.watch(activeServerProvider);
    if (panelServer == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Elasticsearch 管理')),
        body: const NoServerView(),
      );
    }

    final serversAsync =
        ref.watch(databaseServerOptionsProvider('elasticsearch'));
    final servers = serversAsync.valueOrNull ?? const <DatabaseServer>[];
    final serverId = servers.any((s) => s.id == _serverId)
        ? _serverId
        : (servers.isEmpty ? null : servers.first.id);
    final index = _index;

    final query = (serverId != null && index != null)
        ? EsDataQuery(serverId: serverId, index: index, search: _search)
        : null;

    // 处在文档列表（index != null）时禁止直接出栈，交给 _handlePop 回退内层视图。
    return PopScope<Object?>(
      canPop: index == null,
      onPopInvokedWithResult: _handlePop,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            index == null ? 'Elasticsearch 管理' : '索引：$index',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          leading: index == null
              ? null
              : A11yIconButton(
                  tooltip: '返回索引列表',
                  // 走 maybePop 以复用上面的 PopScope，保证箭头与系统手势行为一致。
                  onPressed: () => Navigator.maybePop(context),
                  icon: const Icon(Icons.arrow_back),
                ),
        ),
        floatingActionButton: serverId == null
            ? null
            : (query == null
                ? FloatingActionButton.extended(
                    onPressed: () => _createIndex(serverId),
                    icon: const Icon(Icons.add),
                    label: const Text('创建索引'),
                  )
                : FloatingActionButton.extended(
                    onPressed: () => _createDocument(query),
                    icon: const Icon(Icons.note_add_outlined),
                    label: const Text('新建文档'),
                  )),
        body: Column(
          children: [
            const FeatureUnsupportedBanner(feature: PanelFeature.elasticsearch),
            Expanded(
              child:
                  _buildBody(context, serversAsync, servers, serverId, query),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    AsyncValue<List<DatabaseServer>> serversAsync,
    List<DatabaseServer> servers,
    int? serverId,
    EsDataQuery? query,
  ) {
    if (servers.isEmpty) {
      if (serversAsync.isLoading) {
        return const LoadingView(message: '正在加载 Elasticsearch 服务器');
      }
      if (serversAsync.hasError) {
        return ErrorView(
          error: serversAsync.error!,
          onRetry: () =>
              ref.invalidate(databaseServerOptionsProvider('elasticsearch')),
        );
      }
      return EmptyView(
        message: '还没有 Elasticsearch 服务器\n添加后即可管理索引与文档',
        icon: Icons.search_outlined,
        action: FilledButton.icon(
          onPressed: _addServer,
          icon: const Icon(Icons.add),
          label: const Text('添加 Elasticsearch 服务器'),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            children: [
              ServerDropdown(
                servers: servers,
                value: serverId,
                showType: false,
                label: 'Elasticsearch 服务器',
                onChanged: (server) {
                  _searchController.clear();
                  setState(() {
                    _serverId = server.id;
                    _index = null;
                    _search = '';
                  });
                },
              ),
              if (query != null) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _searchController,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    labelText: '搜索文档',
                    hintText: '输入关键字后回车全文检索',
                    prefixIcon: const Icon(Icons.search),
                    // 监听输入框本身：只看已提交的 _search 会导致用户刚输入
                    // 还没回车时看不到清除按钮。
                    suffixIcon: ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _searchController,
                      builder: (context, value, _) => value.text.isEmpty
                          ? const SizedBox.shrink()
                          : A11yIconButton(
                              tooltip: '清除搜索词',
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _search = '');
                              },
                            ),
                    ),
                  ),
                  onSubmitted: (value) =>
                      setState(() => _search = value.trim()),
                ),
              ],
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: query == null
              ? _buildIndices(context, serverId!)
              : _buildDocuments(context, query),
        ),
      ],
    );
  }

  Widget _buildIndices(BuildContext context, int serverId) {
    final indicesAsync = ref.watch(esIndicesProvider(serverId));
    return indicesAsync.when(
      loading: () => const LoadingView(message: '正在加载索引'),
      error: (error, _) => ErrorView(
        error: error,
        onRetry: () => ref.invalidate(esIndicesProvider(serverId)),
      ),
      data: (indices) => RefreshIndicator(
        onRefresh: () => _refreshIndices(serverId),
        child: indices.isEmpty
            ? LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: ConstrainedBox(
                    constraints:
                        BoxConstraints(minHeight: constraints.maxHeight),
                    child: EmptyView(
                      message: '该服务器上还没有索引',
                      icon: Icons.folder_outlined,
                      action: FilledButton.icon(
                        onPressed: () => _createIndex(serverId),
                        icon: const Icon(Icons.add),
                        label: const Text('创建索引'),
                      ),
                    ),
                  ),
                ),
              )
            : ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(top: 8, bottom: 96),
                itemCount: indices.length,
                itemBuilder: (context, i) => EsIndexTile(
                  index: indices[i],
                  onBrowse: () => _openIndex(indices[i].name),
                  onDelete: () => _deleteIndex(serverId, indices[i]),
                ),
              ),
      ),
    );
  }

  Widget _buildDocuments(BuildContext context, EsDataQuery query) {
    return PagedListView<EsDocument>(
      state: ref.watch(esDataProvider(query)),
      onRefresh: () => ref.read(esDataProvider(query).notifier).refresh(),
      onLoadMore: () => ref.read(esDataProvider(query).notifier).loadMore(),
      onRetry: () => ref.invalidate(esDataProvider(query)),
      emptyMessage: _search.isEmpty ? '该索引下暂无文档' : '没有匹配「$_search」的文档',
      emptyIcon: Icons.description_outlined,
      itemBuilder: (context, document, index) => EsDocumentTile(
        document: document,
        onView: () => _viewDocument(query, document),
        onDelete: () => _deleteDocument(query, document),
      ),
    );
  }
}
