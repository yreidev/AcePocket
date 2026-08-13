import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_snack.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_view.dart';
import '../models/database_server.dart';
import '../models/db_types.dart';
import '../providers/database_providers.dart';
import '../utils/database_validation.dart';
import 'db_feedback.dart';
import 'db_sheet.dart';
import 'server_dropdown.dart';

/// 创建数据库（对应 `POST /api/database`）。
///
/// 返回 true 表示创建成功。
class CreateDatabaseSheet extends ConsumerStatefulWidget {
  const CreateDatabaseSheet({super.key, this.type = ''});

  /// 类型过滤（空串表示不限）。
  final String type;

  static Future<bool?> show(BuildContext context, {String type = ''}) {
    return showDbSheet<bool>(context, CreateDatabaseSheet(type: type));
  }

  @override
  ConsumerState<CreateDatabaseSheet> createState() =>
      _CreateDatabaseSheetState();
}

class _CreateDatabaseSheetState extends ConsumerState<CreateDatabaseSheet> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _username = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _specificHost = TextEditingController();
  final TextEditingController _comment = TextEditingController();

  DatabaseServer? _server;
  bool _createUser = false;
  String _hostOption = 'localhost';
  bool _submitting = false;
  String? _nameError;
  String? _usernameError;
  String? _hostError;

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _password.dispose();
    _specificHost.dispose();
    _comment.dispose();
    super.dispose();
  }

  static final RegExp _namePattern = RegExp(r'^[a-zA-Z_-][a-zA-Z0-9_-]*$');

  String get _host =>
      _hostOption == 'specific' ? _specificHost.text.trim() : _hostOption;

  Future<void> _submit() async {
    final server = _server;
    final name = _name.text.trim();
    if (server == null) {
      showErrorSnack(context, '请先选择数据库服务器');
      return;
    }
    if (!_namePattern.hasMatch(name)) {
      setState(() => _nameError = '数据库名只能包含字母、数字、下划线和短横线，且不能以数字开头');
      return;
    }
    // 勾选了「同时创建数据库用户」时，用户名与密码是必填的：
    // 原来直接提交，由面板返回英文校验错误，用户不知道该补哪个字段。
    if (_createUser && dbTypeSupportsUser(server.type)) {
      if (_username.text.trim().isEmpty) {
        setState(() => _usernameError = '请填写要创建的数据库用户名');
        return;
      }
      if (_password.text.isEmpty) {
        showErrorSnack(context, '请填写数据库用户的密码');
        return;
      }
      if (dbTypeUsesHost(server.type) && _hostOption == 'specific') {
        final hostError = validateDbUserHost(_specificHost.text);
        if (hostError != null) {
          setState(() => _hostError = hostError);
          return;
        }
      }
    }
    setState(() {
      _nameError = null;
      _usernameError = null;
      _hostError = null;
      _submitting = true;
    });

    final ok = await runGuarded(
      context,
      () => ref.read(databaseRepoProvider).createDatabase(
            serverId: server.id,
            name: name,
            createUser: _createUser,
            username: _username.text.trim(),
            password: _password.text,
            host: dbTypeUsesHost(server.type) ? _host : '',
            comment: _comment.text.trim(),
          ),
      success: '数据库创建成功',
    );

    if (!mounted) return;
    setState(() => _submitting = false);
    if (ok) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
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
        final available =
            servers.where((s) => kDatabaseListTypes.contains(s.type)).toList();
        final server =
            _server != null && available.any((s) => s.id == _server!.id)
                ? _server
                : null;
        final serverType = server?.type ?? '';

        return DbSheet(
          title: '创建数据库',
          submitting: _submitting,
          onSubmit: available.isEmpty ? null : _submit,
          children: [
            if (available.isEmpty)
              const SheetHint(
                text: '还没有可用的数据库服务器，请先在「数据库服务器」中添加 MySQL / PostgreSQL 等服务器。',
                icon: Icons.warning_amber_outlined,
              ),
            ServerDropdown(
              servers: available,
              value: server?.id,
              onChanged: (value) => setState(() {
                _server = value;
                _hostOption = 'localhost';
              }),
            ),
            TextField(
              controller: _name,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: '数据库名',
                hintText: '如 my_app',
                errorText: _nameError,
              ),
              onChanged: (_) {
                if (_nameError != null) setState(() => _nameError = null);
              },
            ),
            if (dbTypeSupportsComment(serverType))
              TextField(
                controller: _comment,
                maxLines: 2,
                decoration: const InputDecoration(labelText: '注释（可选）'),
              ),
            if (dbTypeSupportsUser(serverType)) ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('同时创建数据库用户'),
                subtitle: const Text('关闭时可选择授权给一个已存在的用户'),
                value: _createUser,
                onChanged: (value) => setState(() => _createUser = value),
              ),
              TextField(
                controller: _username,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: _createUser ? '用户名' : '授权用户（可留空）',
                  hintText: _createUser ? '如 my_app' : '留空则不授权任何用户',
                  errorText: _usernameError,
                ),
                onChanged: (_) {
                  if (_usernameError != null) {
                    setState(() => _usernameError = null);
                  }
                },
              ),
              if (_createUser)
                PasswordField(
                  controller: _password,
                  onGenerate: generatePassword,
                ),
              if (_createUser && dbTypeUsesHost(serverType)) ...[
                DropdownButtonFormField<String>(
                  initialValue: _hostOption,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '允许访问的主机'),
                  items: [
                    for (final option in kMysqlHostOptions)
                      DropdownMenuItem(
                        value: option.$1,
                        child: Text(option.$2),
                      ),
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
                      if (_hostError != null) setState(() => _hostError = null);
                    },
                  ),
              ],
            ],
          ],
        );
      },
    );
  }
}
