import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/database_server.dart';
import '../models/db_types.dart';
import '../providers/database_providers.dart';
import 'db_feedback.dart';
import 'db_sheet.dart';

/// 添加 / 编辑数据库服务器
/// （`POST /api/database_server`、`PUT /api/database_server/{id}`）。
///
/// 返回 true 表示保存成功。
class DatabaseServerSheet extends ConsumerStatefulWidget {
  const DatabaseServerSheet({super.key, this.server, this.initialType});

  /// 传入表示编辑已有服务器；为 null 表示新增。
  final DatabaseServer? server;

  /// 新增时的初始类型。
  final String? initialType;

  static Future<bool?> show(
    BuildContext context, {
    DatabaseServer? server,
    String? initialType,
  }) {
    return showDbSheet<bool>(
      context,
      DatabaseServerSheet(server: server, initialType: initialType),
    );
  }

  @override
  ConsumerState<DatabaseServerSheet> createState() =>
      _DatabaseServerSheetState();
}

class _DatabaseServerSheetState extends ConsumerState<DatabaseServerSheet> {
  late final TextEditingController _name;
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _username;
  late final TextEditingController _password;
  late final TextEditingController _remark;

  late String _type;
  bool _submitting = false;
  String? _nameError;
  String? _hostError;
  String? _portError;

  bool get _isEdit => widget.server != null;

  @override
  void initState() {
    super.initState();
    final server = widget.server;
    _type =
        server?.type ??
        (widget.initialType != null && widget.initialType!.isNotEmpty
            ? widget.initialType!
            : 'mysql');
    _name = TextEditingController(text: server?.name ?? '');
    _host = TextEditingController(
      text: server?.host ?? (_type == 'sqlite' ? '' : '127.0.0.1'),
    );
    _port = TextEditingController(
      text: '${server?.port ?? dbTypeDefaultPort(_type)}',
    );
    _username = TextEditingController(text: server?.username ?? '');
    _password = TextEditingController(text: server?.password ?? '');
    _remark = TextEditingController(text: server?.remark ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _host.dispose();
    _port.dispose();
    _username.dispose();
    _password.dispose();
    _remark.dispose();
    super.dispose();
  }

  static final RegExp _namePattern = RegExp(r'^[a-zA-Z0-9_-]+$');

  void _onTypeChanged(String type) {
    setState(() {
      _type = type;
      _port.text = '${dbTypeDefaultPort(type)}';
      _host.text = type == 'sqlite' ? '' : '127.0.0.1';
    });
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final host = _host.text.trim();
    if (!_namePattern.hasMatch(name)) {
      setState(() => _nameError = '名称只能包含字母、数字、下划线和短横线');
      return;
    }
    if (host.isEmpty) {
      setState(() => _hostError = _type == 'sqlite' ? '请填写数据库文件路径' : '请填写主机地址');
      return;
    }
    final port = _type == 'sqlite' ? 0 : (int.tryParse(_port.text.trim()) ?? 0);
    if (_type != 'sqlite' && (port < 1 || port > 65535)) {
      // 错误挂在端口输入框上，而不是弹一条与字段无关的提示。
      setState(() => _portError = '端口需为 1-65535');
      return;
    }

    setState(() {
      _nameError = null;
      _hostError = null;
      _portError = null;
      _submitting = true;
    });

    final repo = ref.read(databaseRepoProvider);
    final username = dbTypeNeedsUsername(_type) ? _username.text.trim() : '';
    final password = dbTypeNeedsPassword(_type) ? _password.text : '';
    final remark = _remark.text.trim();

    final ok = await runGuarded(
      context,
      () => _isEdit
          ? repo.updateServer(
              widget.server!.id,
              name: name,
              host: host,
              port: port,
              username: username,
              password: password,
              remark: remark,
            )
          : repo.createServer(
              name: name,
              type: _type,
              host: host,
              port: port,
              username: username,
              password: password,
              remark: remark,
            ),
      success: _isEdit ? '服务器已更新' : '服务器添加成功',
    );

    if (!mounted) return;
    setState(() => _submitting = false);
    if (ok) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final isSqlite = _type == 'sqlite';
    return DbSheet(
      title: _isEdit ? '编辑数据库服务器' : '添加数据库服务器',
      subtitle: _isEdit ? widget.server!.name : '保存时面板会先测试连接',
      submitting: _submitting,
      onSubmit: _submit,
      children: [
        if (!_isEdit)
          DropdownButtonFormField<String>(
            initialValue: _type,
            isExpanded: true,
            decoration: const InputDecoration(labelText: '类型'),
            items: [
              for (final type in kDatabaseServerTypes)
                DropdownMenuItem(value: type, child: Text(dbTypeLabel(type))),
            ],
            onChanged: (value) => _onTypeChanged(value ?? 'mysql'),
          ),
        TextField(
          controller: _name,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: '名称',
            hintText: '如 local-mysql',
            errorText: _nameError,
          ),
          onChanged: (_) {
            if (_nameError != null) setState(() => _nameError = null);
          },
        ),
        if (isSqlite)
          TextField(
            controller: _host,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: '数据库文件路径',
              hintText: '如 /data/app.db',
              errorText: _hostError,
            ),
            onChanged: (_) {
              if (_hostError != null) setState(() => _hostError = null);
            },
          )
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _host,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: '主机',
                    hintText: '本机填 127.0.0.1',
                    errorText: _hostError,
                  ),
                  onChanged: (_) {
                    if (_hostError != null) setState(() => _hostError = null);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _port,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: '端口',
                    errorText: _portError,
                  ),
                  onChanged: (_) {
                    if (_portError != null) setState(() => _portError = null);
                  },
                ),
              ),
            ],
          ),
        if (dbTypeNeedsUsername(_type))
          TextField(
            controller: _username,
            autocorrect: false,
            decoration: const InputDecoration(labelText: '用户名'),
          ),
        if (dbTypeNeedsPassword(_type)) PasswordField(controller: _password),
        TextField(
          controller: _remark,
          maxLines: 2,
          decoration: const InputDecoration(labelText: '备注（可选）'),
        ),
        if (!_isEdit)
          const SheetHint(
            text:
                '本机数据库请把主机填为 127.0.0.1；远程数据库需确保面板所在机器能访问该地址，'
                '且数据库账号允许远程登录。',
          ),
      ],
    );
  }
}
