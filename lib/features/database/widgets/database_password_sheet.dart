import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_snack.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_view.dart';
import '../models/database_user.dart';
import '../models/db_types.dart';
import '../providers/database_providers.dart';
import 'db_feedback.dart';
import 'db_sheet.dart';

/// 修改数据库用户密码（`PUT /api/database_user/{id}`）。
///
/// 两种用法：
/// - 传 [user]：直接为该用户改密；
/// - 传 [serverId]：先在该服务器的用户中挑选一个再改密（数据库列表页用）。
///
/// 返回 true 表示修改成功。
class DatabasePasswordSheet extends ConsumerStatefulWidget {
  const DatabasePasswordSheet({
    super.key,
    this.user,
    this.serverId,
    this.subtitle,
  }) : assert(user != null || serverId != null, '必须提供 user 或 serverId');

  final DatabaseUser? user;
  final int? serverId;
  final String? subtitle;

  static Future<bool?> show(
    BuildContext context, {
    DatabaseUser? user,
    int? serverId,
    String? subtitle,
  }) {
    return showDbSheet<bool>(
      context,
      DatabasePasswordSheet(
        user: user,
        serverId: serverId,
        subtitle: subtitle,
      ),
    );
  }

  @override
  ConsumerState<DatabasePasswordSheet> createState() =>
      _DatabasePasswordSheetState();
}

class _DatabasePasswordSheetState extends ConsumerState<DatabasePasswordSheet> {
  final TextEditingController _password = TextEditingController();
  DatabaseUser? _selected;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _selected = widget.user;
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  String _userLabel(DatabaseUser user) =>
      user.host.isEmpty ? user.username : '${user.username}@${user.host}';

  Future<void> _submit() async {
    final user = _selected;
    if (user == null) {
      showErrorSnack(context, '请先选择要改密的用户');
      return;
    }
    if (_password.text.isEmpty) {
      showErrorSnack(context, '请填写新密码');
      return;
    }

    setState(() => _submitting = true);
    final ok = await runGuarded(
      context,
      () => ref.read(databaseRepoProvider).updateUser(
            user.id,
            password: _password.text,
            // 保持原有授权与备注不变（接口会按传入列表回收多余权限）。
            privileges: user.privileges,
            remark: user.remark,
          ),
      success: '密码修改成功',
    );

    if (!mounted) return;
    setState(() => _submitting = false);
    if (ok) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.user != null) {
      return _buildSheet(context, users: [widget.user!], showPicker: false);
    }

    final usersAsync = ref.watch(serverDatabaseUsersProvider(widget.serverId!));
    return usersAsync.when(
      loading: () => const SizedBox(
        height: 240,
        child: LoadingView(message: '正在加载数据库用户'),
      ),
      error: (error, _) => SizedBox(
        height: 300,
        child: ErrorView(
          error: error,
          onRetry: () =>
              ref.invalidate(serverDatabaseUsersProvider(widget.serverId!)),
        ),
      ),
      data: (users) => _buildSheet(context, users: users, showPicker: true),
    );
  }

  Widget _buildSheet(
    BuildContext context, {
    required List<DatabaseUser> users,
    required bool showPicker,
  }) {
    final selected =
        _selected != null && users.any((u) => u.id == _selected!.id)
            ? _selected
            : null;

    return DbSheet(
      title: '修改数据库密码',
      subtitle: widget.subtitle ??
          (showPicker ? '为该服务器上的数据库用户设置新密码' : _userLabel(users.first)),
      submitting: _submitting,
      onSubmit: users.isEmpty ? null : _submit,
      children: [
        if (users.isEmpty)
          const SheetHint(
            text: '该服务器下还没有面板托管的数据库用户，可先在「数据库用户」中创建或同步。',
            icon: Icons.warning_amber_outlined,
          ),
        if (showPicker && users.isNotEmpty)
          DropdownButtonFormField<int>(
            initialValue: selected?.id,
            isExpanded: true,
            decoration: const InputDecoration(labelText: '数据库用户'),
            hint: const Text('请选择用户'),
            items: [
              for (final user in users)
                DropdownMenuItem(
                  value: user.id,
                  child: Text(
                    _userLabel(user),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            // firstWhere 在 id 为 null 时会抛 StateError，先挡掉。
            onChanged: (id) {
              if (id == null) return;
              setState(() => _selected = users.firstWhere((u) => u.id == id));
            },
          ),
        if (users.isNotEmpty)
          PasswordField(
            controller: _password,
            label: '新密码',
            onGenerate: generatePassword,
          ),
        if (users.isNotEmpty)
          const SheetHint(
            text: '修改后请同步更新使用该账号的应用配置，否则应用将无法连接数据库。',
          ),
      ],
    );
  }
}
