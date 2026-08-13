import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_snack.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_view.dart';
import '../models/database_server.dart';
import '../models/database_user.dart';
import '../models/db_types.dart';
import '../utils/database_validation.dart';
import '../providers/database_providers.dart';
import 'db_feedback.dart';
import 'db_sheet.dart';
import 'privileges_editor.dart';
import 'server_dropdown.dart';

/// 创建 / 编辑数据库用户
/// （`POST /api/database_user`、`PUT /api/database_user/{id}`）。
///
/// 返回 true 表示保存成功。
class DatabaseUserSheet extends ConsumerStatefulWidget {
  const DatabaseUserSheet({super.key, this.user, this.type = ''});

  /// 传入表示编辑已有用户；为 null 表示新增。
  final DatabaseUser? user;

  /// 新增时的类型过滤（空串表示不限）。
  final String type;

  static Future<bool?> show(
    BuildContext context, {
    DatabaseUser? user,
    String type = '',
  }) {
    return showDbSheet<bool>(
      context,
      DatabaseUserSheet(user: user, type: type),
    );
  }

  @override
  ConsumerState<DatabaseUserSheet> createState() => _DatabaseUserSheetState();
}

class _DatabaseUserSheetState extends ConsumerState<DatabaseUserSheet> {
  late final TextEditingController _username;
  late final TextEditingController _password;
  late final TextEditingController _remark;
  final TextEditingController _specificHost = TextEditingController();

  DatabaseServer? _server;
  late List<String> _privileges;
  String _hostOption = 'localhost';
  bool _submitting = false;
  String? _usernameError;
  String? _hostError;

  bool get _isEdit => widget.user != null;

  @override
  void initState() {
    super.initState();
    final user = widget.user;
    _username = TextEditingController(text: user?.username ?? '');
    _password = TextEditingController();
    _remark = TextEditingController(text: user?.remark ?? '');
    _privileges = List<String>.of(user?.privileges ?? const []);
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _remark.dispose();
    _specificHost.dispose();
    super.dispose();
  }

  static final RegExp _usernamePattern = RegExp(r'^[a-zA-Z_-][a-zA-Z0-9_-]*$');

  String get _host =>
      _hostOption == 'specific' ? _specificHost.text.trim() : _hostOption;

  Future<void> _submitCreate() async {
    final server = _server;
    final username = _username.text.trim();
    if (server == null) {
      showErrorSnack(context, '请先选择数据库服务器');
      return;
    }
    if (!_usernamePattern.hasMatch(username)) {
      setState(() => _usernameError = '用户名只能包含字母、数字、下划线和短横线，且不能以数字开头');
      return;
    }
    if (username == 'root' || username == 'admin') {
      setState(() => _usernameError = '不允许使用 root / admin 作为用户名');
      return;
    }
    if (_password.text.isEmpty) {
      showErrorSnack(context, '请填写密码');
      return;
    }
    if (dbTypeUsesHost(server.type) && _hostOption == 'specific') {
      final hostError = validateDbUserHost(_specificHost.text);
      if (hostError != null) {
        setState(() => _hostError = hostError);
        return;
      }
    }

    setState(() {
      _usernameError = null;
      _hostError = null;
      _submitting = true;
    });

    final ok = await runGuarded(
      context,
      () => ref
          .read(databaseRepoProvider)
          .createUser(
            serverId: server.id,
            username: username,
            password: _password.text,
            host: dbTypeUsesHost(server.type) ? _host : '',
            privileges: _privileges,
            remark: _remark.text.trim(),
          ),
      success: '用户创建成功',
    );

    if (!mounted) return;
    setState(() => _submitting = false);
    if (ok) Navigator.of(context).pop(true);
  }

  Future<void> _submitUpdate() async {
    setState(() => _submitting = true);
    final ok = await runGuarded(
      context,
      () => ref
          .read(databaseRepoProvider)
          .updateUser(
            widget.user!.id,
            password: _password.text,
            privileges: _privileges,
            remark: _remark.text.trim(),
          ),
      success: '用户已更新',
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (ok) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return _isEdit ? _buildEdit(context) : _buildCreate(context);
  }

  Widget _buildEdit(BuildContext context) {
    final user = widget.user!;
    final title = user.host.isEmpty
        ? user.username
        : '${user.username}@${user.host}';
    return DbSheet(
      title: '编辑数据库用户',
      subtitle: title,
      submitting: _submitting,
      onSubmit: _submitUpdate,
      children: [
        const SheetHint(text: '授权的数据库若不存在，面板会自动创建；移除的授权会被回收。'),
        PasswordField(
          controller: _password,
          label: '新密码',
          hint: '留空则不修改密码',
          onGenerate: generatePassword,
        ),
        PrivilegesEditor(
          values: _privileges,
          onChanged: (values) => setState(() => _privileges = values),
        ),
        TextField(
          controller: _remark,
          maxLines: 2,
          decoration: const InputDecoration(labelText: '备注（可选）'),
        ),
      ],
    );
  }

  Widget _buildCreate(BuildContext context) {
    final optionsAsync = ref.watch(databaseServerOptionsProvider(widget.type));

    return optionsAsync.when(
      loading: () => const SizedBox(
        height: 260,
        child: LoadingView(message: '正在加载数据库服务器'),
      ),
      error: (error, _) => SizedBox(
        height: 300,
        child: ErrorView(
          error: error,
          onRetry: () =>
              ref.invalidate(databaseServerOptionsProvider(widget.type)),
        ),
      ),
      data: (servers) {
        // 仅 MySQL / PostgreSQL / ClickHouse 支持用户管理。
        final available = servers
            .where((s) => dbTypeSupportsUser(s.type))
            .toList();
        final server =
            _server != null && available.any((s) => s.id == _server!.id)
            ? _server
            : null;
        final serverType = server?.type ?? '';

        return DbSheet(
          title: '创建数据库用户',
          submitting: _submitting,
          onSubmit: available.isEmpty ? null : _submitCreate,
          children: [
            if (available.isEmpty)
              const SheetHint(
                text:
                    '没有支持用户管理的数据库服务器，请先添加 MySQL / PostgreSQL / ClickHouse 服务器。',
                icon: Icons.warning_amber_outlined,
              )
            else
              const SheetHint(text: '授权的数据库若不存在，面板会自动创建。'),
            ServerDropdown(
              servers: available,
              value: server?.id,
              onChanged: (value) => setState(() {
                _server = value;
                _hostOption = 'localhost';
              }),
            ),
            TextField(
              controller: _username,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: '用户名',
                errorText: _usernameError,
              ),
              onChanged: (_) {
                if (_usernameError != null) {
                  setState(() => _usernameError = null);
                }
              },
            ),
            PasswordField(controller: _password, onGenerate: generatePassword),
            if (dbTypeUsesHost(serverType)) ...[
              DropdownButtonFormField<String>(
                initialValue: _hostOption,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '允许访问的主机'),
                items: [
                  for (final option in kMysqlHostOptions)
                    DropdownMenuItem(value: option.$1, child: Text(option.$2)),
                ],
                onChanged: (value) => setState(() {
                  _hostOption = value ?? 'localhost';
                  _hostError = null;
                }),
              ),
              if (_hostOption == 'specific')
                TextField(
                  controller: _specificHost,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: '指定主机',
                    hintText: '如 192.0.2.10 或 192.0.2.%',
                    errorText: _hostError,
                  ),
                  onChanged: (_) {
                    if (_hostError != null) {
                      setState(() => _hostError = null);
                    }
                  },
                ),
            ],
            PrivilegesEditor(
              values: _privileges,
              onChanged: (values) => setState(() => _privileges = values),
            ),
            TextField(
              controller: _remark,
              maxLines: 2,
              decoration: const InputDecoration(labelText: '备注（可选）'),
            ),
          ],
        );
      },
    );
  }
}
