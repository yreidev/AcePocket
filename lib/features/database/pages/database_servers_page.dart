import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/server_store.dart';
import '../../../core/widgets/app_snack.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../models/database_server.dart';
import '../models/db_types.dart';
import '../providers/database_providers.dart';
import '../widgets/database_server_sheet.dart';
import '../widgets/database_server_tile.dart';
import '../widgets/db_feedback.dart';
import '../widgets/db_type_filter.dart';
import '../widgets/no_server_view.dart';
import '../widgets/paged_list.dart';
import '../widgets/text_input_dialog.dart';

/// 数据库服务器管理页（`/databases/servers`）。
class DatabaseServersPage extends ConsumerStatefulWidget {
  const DatabaseServersPage({super.key});

  @override
  ConsumerState<DatabaseServersPage> createState() =>
      _DatabaseServersPageState();
}

class _DatabaseServersPageState extends ConsumerState<DatabaseServersPage> {
  String _type = '';

  /// 正在同步用户的服务器 id：同步是耗时操作且无进度反馈，
  /// 不拦住重复点击会向面板发多份同样的导入请求。
  final Set<int> _syncing = <int>{};

  DatabaseServerListNotifier get _notifier =>
      ref.read(databaseServerListProvider(_type).notifier);

  Future<void> _refresh() async {
    // 服务器变化会影响所有依赖服务器下拉的表单。
    ref.invalidate(databaseServerOptionsProvider);
    await _notifier.refresh();
  }

  Future<void> _create() async {
    final saved = await DatabaseServerSheet.show(
      context,
      initialType: _type.isEmpty ? null : _type,
    );
    if (saved == true) await _refresh();
  }

  Future<void> _edit(DatabaseServer server) async {
    final saved = await DatabaseServerSheet.show(context, server: server);
    if (saved == true) await _refresh();
  }

  Future<void> _editRemark(DatabaseServer server) async {
    final remark = await showTextInputDialog(
      context,
      title: '修改备注',
      label: '备注',
      initialValue: server.remark,
      maxLines: 3,
    );
    if (remark == null || !mounted) return;

    final ok = await runGuarded(
      context,
      () =>
          ref.read(databaseRepoProvider).updateServerRemark(server.id, remark),
      success: '备注已更新',
    );
    if (ok) await _refresh();
  }

  Future<void> _sync(DatabaseServer server) async {
    if (_syncing.contains(server.id)) {
      showInfoSnack(context, '「${server.name}」正在同步用户，请稍候');
      return;
    }
    final ok = await showConfirmDialog(
      context,
      title: '同步服务器用户',
      content: '将把「${server.name}」上已存在但未被面板记录的数据库用户导入面板。',
      confirmText: '同步',
    );
    if (!ok || !mounted) return;

    showInfoSnack(context, '正在同步用户，请稍候…');
    setState(() => _syncing.add(server.id));
    final success = await runGuarded(
      context,
      () => ref.read(databaseRepoProvider).syncServer(server.id),
      success: '用户同步完成',
    );
    if (!mounted) return;
    setState(() => _syncing.remove(server.id));
    if (success) {
      ref.invalidate(databaseUserListProvider);
      await _refresh();
    }
  }

  Future<void> _delete(DatabaseServer server) async {
    final ok = await showConfirmDialog(
      context,
      title: '删除数据库服务器',
      content: '确定要从面板中移除「${server.name}」吗？\n'
          '仅删除面板中的记录，不会删除数据库本身的数据。',
      confirmText: '删除',
      danger: true,
    );
    if (!ok || !mounted) return;

    final success = await runGuarded(
      context,
      () => ref.read(databaseRepoProvider).deleteServer(server.id),
      success: '服务器已删除',
    );
    if (success) {
      ref.invalidate(databaseUserListProvider);
      ref.invalidate(databaseListProvider);
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final panelServer = ref.watch(activeServerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('数据库服务器'),
        actions: [
          if (panelServer != null)
            DbTypeFilterButton(
              value: _type,
              types: kDatabaseServerTypes,
              onChanged: (value) => setState(() => _type = value),
            ),
        ],
      ),
      floatingActionButton: panelServer == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _create,
              icon: const Icon(Icons.add),
              label: const Text('添加服务器'),
            ),
      body: panelServer == null
          ? const NoServerView()
          : PagedListView<DatabaseServer>(
              state: ref.watch(databaseServerListProvider(_type)),
              onRefresh: _refresh,
              onLoadMore: () => _notifier.loadMore(),
              onRetry: () => ref.invalidate(databaseServerListProvider(_type)),
              emptyMessage: _type.isEmpty
                  ? '还没有数据库服务器\n添加本机或远程数据库后即可管理'
                  : '暂无 ${dbTypeLabel(_type)} 服务器',
              emptyIcon: Icons.dns_outlined,
              emptyAction: FilledButton.icon(
                onPressed: _create,
                icon: const Icon(Icons.add),
                label: const Text('添加服务器'),
              ),
              itemBuilder: (context, server, index) => DatabaseServerTile(
                server: server,
                syncing: _syncing.contains(server.id),
                onEdit: () => _edit(server),
                onEditRemark: () => _editRemark(server),
                onSync: () => _sync(server),
                onDelete: () => _delete(server),
              ),
            ),
    );
  }
}
