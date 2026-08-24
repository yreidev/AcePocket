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
import '../models/redis_kv.dart';
import '../providers/database_providers.dart';
import '../providers/redis_providers.dart';
import '../widgets/database_server_sheet.dart';
import '../widgets/db_feedback.dart';
import '../widgets/no_server_view.dart';
import '../widgets/paged_list.dart';
import '../widgets/redis_key_sheet.dart';
import '../widgets/redis_key_tile.dart';
import '../widgets/server_dropdown.dart';
import '../widgets/text_input_dialog.dart';

/// Redis 管理页（`/databases/redis`）。
class RedisPage extends ConsumerStatefulWidget {
  const RedisPage({super.key});

  @override
  ConsumerState<RedisPage> createState() => _RedisPageState();
}

class _RedisPageState extends ConsumerState<RedisPage> {
  final TextEditingController _searchController = TextEditingController();

  int? _serverId;
  int _db = 0;
  String _search = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refresh(RedisDataQuery query) =>
      ref.read(redisDataProvider(query).notifier).refresh();

  Future<void> _addServer() async {
    final saved = await DatabaseServerSheet.show(context, initialType: 'redis');
    if (saved == true) ref.invalidate(databaseServerOptionsProvider);
  }

  Future<void> _createKey(RedisDataQuery query) async {
    final saved = await RedisKeySheet.show(
      context,
      serverId: query.serverId,
      db: query.db,
    );
    if (saved == true) await _refresh(query);
  }

  Future<void> _viewKey(RedisDataQuery query, RedisKv kv) async {
    final saved = await RedisKeySheet.show(
      context,
      serverId: query.serverId,
      db: query.db,
      keyName: kv.key,
    );
    if (saved == true) await _refresh(query);
  }

  Future<void> _setTtl(RedisDataQuery query, RedisKv kv) async {
    final input = await showTextInputDialog(
      context,
      title: '设置过期时间',
      label: '过期时间（秒）',
      hintText: '0 或负数表示永不过期',
      initialValue: '${kv.ttl > 0 ? kv.ttl : 0}',
      keyboardType: TextInputType.number,
    );
    if (input == null || !mounted) return;
    final ttl = int.tryParse(input.trim());
    if (ttl == null) {
      showErrorSnack(context, '请输入合法的秒数，0 或负数表示永不过期');
      return;
    }

    final ok = await runGuarded(
      context,
      () => ref
          .read(databaseRepoProvider)
          .redisKeyTtl(
            serverId: query.serverId,
            db: query.db,
            key: kv.key,
            ttl: ttl,
          ),
      success: '过期时间已更新',
    );
    if (ok) await _refresh(query);
  }

  Future<void> _rename(RedisDataQuery query, RedisKv kv) async {
    final newKey = await showTextInputDialog(
      context,
      title: '重命名键',
      label: '新键名',
      initialValue: kv.key,
    );
    if (newKey == null || !mounted) return;
    if (newKey.isEmpty) {
      // 原来静默返回，用户以为改名成功了却什么也没发生。
      showErrorSnack(context, '请填写新键名');
      return;
    }
    if (newKey == kv.key) {
      showInfoSnack(context, '新键名与原键名相同，未做修改');
      return;
    }

    final ok = await runGuarded(
      context,
      () => ref
          .read(databaseRepoProvider)
          .redisKeyRename(
            serverId: query.serverId,
            db: query.db,
            oldKey: kv.key,
            newKey: newKey,
          ),
      success: '重命名成功',
    );
    if (ok) await _refresh(query);
  }

  Future<void> _deleteKey(RedisDataQuery query, RedisKv kv) async {
    final confirmed = await showConfirmDialog(
      context,
      title: '删除键',
      content: '确定要删除键「${kv.key}」吗？该操作不可恢复。',
      confirmText: '删除',
      danger: true,
    );
    if (!confirmed || !mounted) return;

    final ok = await runGuarded(
      context,
      () => ref
          .read(databaseRepoProvider)
          .redisKeyDelete(serverId: query.serverId, db: query.db, key: kv.key),
      success: '键已删除',
    );
    if (ok) await _refresh(query);
  }

  Future<void> _clearDb(RedisDataQuery query) async {
    final confirmed = await showConfirmDialog(
      context,
      title: '清空数据库',
      content: '确定要清空 DB${query.db} 中的全部键值吗？该操作不可恢复。',
      confirmText: '清空',
      danger: true,
    );
    if (!confirmed || !mounted) return;

    final ok = await runGuarded(
      context,
      () => ref
          .read(databaseRepoProvider)
          .redisClear(serverId: query.serverId, db: query.db),
      success: '数据库已清空',
    );
    if (ok) await _refresh(query);
  }

  @override
  Widget build(BuildContext context) {
    final panelServer = ref.watch(activeServerProvider);
    if (panelServer == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Redis 管理')),
        body: const NoServerView(),
      );
    }

    final serversAsync = ref.watch(databaseServerOptionsProvider('redis'));
    final servers = serversAsync.value ?? const <DatabaseServer>[];
    final serverId = servers.any((s) => s.id == _serverId)
        ? _serverId
        : (servers.isEmpty ? null : servers.first.id);

    final dbCount = serverId == null
        ? 16
        : (ref.watch(redisDatabaseCountProvider(serverId)).value ?? 16);
    final db = _db < dbCount ? _db : 0;

    final query = serverId == null
        ? null
        : RedisDataQuery(serverId: serverId, db: db, search: _search);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Redis 管理'),
        actions: [
          if (query != null)
            A11yIconButton(
              tooltip: '清空当前数据库的全部键值',
              onPressed: () => _clearDb(query),
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
        ],
      ),
      floatingActionButton: query == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _createKey(query),
              icon: const Icon(Icons.add),
              label: const Text('新建键'),
            ),
      body: Column(
        children: [
          const FeatureUnsupportedBanner(feature: PanelFeature.redis),
          Expanded(
            child: _buildBody(
              context,
              serversAsync,
              servers,
              serverId,
              dbCount,
              db,
              query,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    AsyncValue<List<DatabaseServer>> serversAsync,
    List<DatabaseServer> servers,
    int? serverId,
    int dbCount,
    int db,
    RedisDataQuery? query,
  ) {
    if (servers.isEmpty) {
      if (serversAsync.isLoading) {
        return const LoadingView(message: '正在加载 Redis 服务器');
      }
      if (serversAsync.hasError) {
        return ErrorView(
          error: serversAsync.error!,
          onRetry: () => ref.invalidate(databaseServerOptionsProvider('redis')),
        );
      }
      return EmptyView(
        message: '还没有 Redis 服务器\n添加后即可管理键值',
        icon: Icons.memory_outlined,
        action: FilledButton.icon(
          onPressed: _addServer,
          icon: const Icon(Icons.add),
          label: const Text('添加 Redis 服务器'),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: ServerDropdown(
                      servers: servers,
                      value: serverId,
                      showType: false,
                      label: 'Redis 服务器',
                      onChanged: (server) => setState(() {
                        _serverId = server.id;
                        _db = 0;
                      }),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<int>(
                      initialValue: db,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: '数据库'),
                      items: [
                        for (var i = 0; i < dbCount; i++)
                          DropdownMenuItem(value: i, child: Text('DB$i')),
                      ],
                      onChanged: (value) => setState(() => _db = value ?? 0),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  labelText: '搜索键名',
                  hintText: '支持 * 通配，如 user:*，回车搜索',
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
                onSubmitted: (value) => setState(() => _search = value.trim()),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: query == null
              ? const LoadingView()
              : _buildKeyList(context, query, db),
        ),
      ],
    );
  }

  Widget _buildKeyList(BuildContext context, RedisDataQuery query, int db) {
    return PagedListView<RedisKv>(
      state: ref.watch(redisDataProvider(query)),
      onRefresh: () => _refresh(query),
      onLoadMore: () => ref.read(redisDataProvider(query).notifier).loadMore(),
      onRetry: () => ref.invalidate(redisDataProvider(query)),
      emptyMessage: _search.isEmpty ? 'DB$db 中暂无键值' : '没有匹配「$_search」的键',
      emptyIcon: Icons.vpn_key_outlined,
      itemBuilder: (context, kv, index) => RedisKeyTile(
        kv: kv,
        onView: () => _viewKey(query, kv),
        onTtl: () => _setTtl(query, kv),
        onRename: () => _rename(query, kv),
        onDelete: () => _deleteKey(query, kv),
      ),
    );
  }
}
