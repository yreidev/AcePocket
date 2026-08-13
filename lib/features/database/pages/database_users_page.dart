import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/storage/server_store.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../models/database_user.dart';
import '../models/db_types.dart';
import '../providers/database_providers.dart';
import '../widgets/database_password_sheet.dart';
import '../widgets/database_user_sheet.dart';
import '../widgets/database_user_tile.dart';
import '../widgets/db_feedback.dart';
import '../widgets/db_type_filter.dart';
import '../widgets/no_server_view.dart';
import '../widgets/paged_list.dart';
import '../widgets/text_input_dialog.dart';

/// 数据库用户管理页（`/databases/users`）。
class DatabaseUsersPage extends ConsumerStatefulWidget {
  const DatabaseUsersPage({super.key});

  @override
  ConsumerState<DatabaseUsersPage> createState() => _DatabaseUsersPageState();
}

class _DatabaseUsersPageState extends ConsumerState<DatabaseUsersPage> {
  String _type = '';

  DatabaseUserListNotifier get _notifier =>
      ref.read(databaseUserListProvider(_type).notifier);

  Future<void> _refresh() async {
    ref.invalidate(serverDatabaseUsersProvider);
    await _notifier.refresh();
  }

  Future<void> _create() async {
    final saved = await DatabaseUserSheet.show(context, type: _type);
    if (saved == true) await _refresh();
  }

  Future<void> _edit(DatabaseUser user) async {
    final saved = await DatabaseUserSheet.show(context, user: user);
    if (saved == true) await _refresh();
  }

  Future<void> _changePassword(DatabaseUser user) async {
    final changed = await DatabasePasswordSheet.show(context, user: user);
    if (changed == true) await _refresh();
  }

  Future<void> _editRemark(DatabaseUser user) async {
    final remark = await showTextInputDialog(
      context,
      title: '修改备注',
      label: '备注',
      initialValue: user.remark,
      maxLines: 3,
    );
    if (remark == null || !mounted) return;

    final ok = await runGuarded(
      context,
      () => ref.read(databaseRepoProvider).updateUserRemark(user.id, remark),
      success: '备注已更新',
    );
    if (ok) await _refresh();
  }

  Future<void> _delete(DatabaseUser user) async {
    final name = user.host.isEmpty
        ? user.username
        : '${user.username}@${user.host}';
    final ok = await showConfirmDialog(
      context,
      title: '删除数据库用户',
      content: '确定要删除用户「$name」吗？\n该用户将从数据库中被移除，使用它的应用会立即失去访问权限。',
      confirmText: '删除',
      danger: true,
    );
    if (!ok || !mounted) return;

    final success = await runGuarded(
      context,
      () => ref.read(databaseRepoProvider).deleteUser(user.id),
      success: '用户已删除',
    );
    if (success) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final panelServer = ref.watch(activeServerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('数据库用户'),
        actions: [
          if (panelServer != null)
            DbTypeFilterButton(
              value: _type,
              types: kUserSupportedTypes,
              onChanged: (value) => setState(() => _type = value),
            ),
        ],
      ),
      floatingActionButton: panelServer == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _create,
              icon: const Icon(Icons.person_add_alt),
              label: const Text('创建用户'),
            ),
      body: panelServer == null
          ? const NoServerView()
          : PagedListView<DatabaseUser>(
              state: ref.watch(databaseUserListProvider(_type)),
              onRefresh: _refresh,
              onLoadMore: () => _notifier.loadMore(),
              onRetry: () => ref.invalidate(databaseUserListProvider(_type)),
              emptyMessage: _type.isEmpty
                  ? '还没有数据库用户\n可新建用户，或在「数据库服务器」里对已有服务器执行「同步用户」'
                  : '暂无 ${dbTypeLabel(_type)} 用户\n可在右上角切换筛选查看其他类型',
              emptyIcon: Icons.people_outline,
              emptyAction: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton.icon(
                    onPressed: _create,
                    icon: const Icon(Icons.person_add_alt),
                    label: const Text('创建用户'),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () => context.push('/databases/servers'),
                    icon: const Icon(Icons.dns_outlined),
                    label: const Text('去同步已有用户'),
                  ),
                ],
              ),
              itemBuilder: (context, user, index) => DatabaseUserTile(
                user: user,
                onEdit: () => _edit(user),
                onChangePassword: () => _changePassword(user),
                onEditRemark: () => _editRemark(user),
                onDelete: () => _delete(user),
              ),
            ),
    );
  }
}
