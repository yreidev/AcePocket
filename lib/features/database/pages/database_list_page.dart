import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/storage/server_store.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/not_installed_view.dart';
import '../models/database.dart';
import '../models/db_types.dart';
import '../providers/database_providers.dart';
import '../widgets/create_database_sheet.dart';
import '../widgets/database_password_sheet.dart';
import '../widgets/database_tile.dart';
import '../widgets/db_feedback.dart';
import '../widgets/db_type_filter.dart';
import '../widgets/no_server_view.dart';
import '../widgets/paged_list.dart';
import '../widgets/text_input_dialog.dart';

/// 数据库列表页（`/databases`）。
class DatabaseListPage extends ConsumerStatefulWidget {
  const DatabaseListPage({super.key});

  @override
  ConsumerState<DatabaseListPage> createState() => _DatabaseListPageState();
}

class _DatabaseListPageState extends ConsumerState<DatabaseListPage> {
  String _type = '';

  DatabaseListNotifier get _notifier =>
      ref.read(databaseListProvider(_type).notifier);

  Future<void> _refresh() => _notifier.refresh();

  Future<void> _create() async {
    final created = await CreateDatabaseSheet.show(context, type: _type);
    if (created == true) await _refresh();
  }

  Future<void> _delete(Database database) async {
    final ok = await showConfirmDialog(
      context,
      title: '删除数据库',
      content:
          '确定要删除数据库「${database.name}」吗？\n'
          '该操作会永久删除其中的所有数据，且不可恢复。',
      confirmText: '删除',
      danger: true,
    );
    if (!ok || !mounted) return;

    final success = await runGuarded(
      context,
      () => ref
          .read(databaseRepoProvider)
          .deleteDatabase(serverId: database.serverId, name: database.name),
      success: '数据库已删除',
    );
    if (success) await _refresh();
  }

  Future<void> _editComment(Database database) async {
    final comment = await showTextInputDialog(
      context,
      title: '设置注释',
      label: '注释',
      initialValue: database.comment,
      maxLines: 3,
    );
    if (comment == null || !mounted) return;

    final success = await runGuarded(
      context,
      () => ref
          .read(databaseRepoProvider)
          .setDatabaseComment(
            serverId: database.serverId,
            name: database.name,
            comment: comment,
          ),
      success: '注释已更新',
    );
    if (success) await _refresh();
  }

  Future<void> _changePassword(Database database) async {
    await DatabasePasswordSheet.show(
      context,
      serverId: database.serverId,
      subtitle: '数据库：${database.name}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final server = ref.watch(activeServerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('数据库'),
        actions: [
          if (server != null)
            DbTypeFilterButton(
              value: _type,
              types: kDatabaseListTypes,
              onChanged: (value) => setState(() => _type = value),
            ),
          PopupMenuButton<String>(
            tooltip: '打开更多数据库管理入口',
            onSelected: (value) => context.push(value),
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: '/databases/servers',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.dns_outlined),
                  title: Text('数据库服务器'),
                ),
              ),
              PopupMenuItem(
                value: '/databases/users',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.people_outline),
                  title: Text('数据库用户'),
                ),
              ),
              PopupMenuItem(
                value: '/databases/redis',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.memory_outlined),
                  title: Text('Redis 管理'),
                ),
              ),
              PopupMenuItem(
                value: '/databases/elasticsearch',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.search_outlined),
                  title: Text('Elasticsearch 管理'),
                ),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: server == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _create,
              icon: const Icon(Icons.add),
              label: const Text('创建数据库'),
            ),
      body: server == null ? const NoServerView() : _buildBody(),
    );
  }

  Widget _buildBody() {
    final state = ref.watch(databaseListProvider(_type));
    // 列表加载失败时探测是否已安装数据库应用：未安装展示专门空态
    // （而不是把面板的原始报错丢给用户）；探测失败则回退到通用错误视图。
    if (state.hasError && !state.isLoading) {
      final installed = ref.watch(databaseAppInstalledProvider);
      if (installed.value == false) {
        return NotInstalledView(
          title: '未安装数据库服务',
          message:
              '数据库管理需要面板已安装 MySQL、PostgreSQL 或 ClickHouse '
              '等数据库应用，请先到应用商店安装后再使用本功能。',
          icon: Icons.storage_outlined,
          onRecheck: () {
            ref.invalidate(databaseAppInstalledProvider);
            ref.invalidate(databaseListProvider(_type));
          },
        );
      }
    }
    return PagedListView<Database>(
      state: state,
      onRefresh: _refresh,
      onLoadMore: () => _notifier.loadMore(),
      onRetry: () => ref.invalidate(databaseListProvider(_type)),
      emptyMessage: _type.isEmpty
          ? '还没有数据库\n创建数据库前，需要先添加一台数据库服务器（MySQL / PostgreSQL 等）'
          : '暂无 ${dbTypeLabel(_type)} 数据库\n可在右上角切换筛选查看其他类型',
      emptyIcon: Icons.storage_outlined,
      // 空态给两步指引：没有服务器时点「创建数据库」只会看到「无可用服务器」，
      // 因此把「添加数据库服务器」也放进空态。
      emptyAction: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton.icon(
            onPressed: _create,
            icon: const Icon(Icons.add),
            label: const Text('创建数据库'),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => context.push('/databases/servers'),
            icon: const Icon(Icons.dns_outlined),
            label: const Text('管理数据库服务器'),
          ),
        ],
      ),
      itemBuilder: (context, database, index) => DatabaseTile(
        database: database,
        onDelete: () => _delete(database),
        onChangePassword: () => _changePassword(database),
        onEditComment: dbTypeSupportsComment(database.type)
            ? () => _editComment(database)
            : null,
      ),
    );
  }
}
