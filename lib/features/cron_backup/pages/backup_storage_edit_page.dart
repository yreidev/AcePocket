import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/server_store.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_view.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/unsaved_guard.dart';
import '../models/backup_storage.dart';
import '../providers/storage_providers.dart';
import '../widgets/feedback.dart';
import '../widgets/no_server_view.dart';

/// 备份存储创建 / 编辑页（`/backups/storages/edit`，带 `id` 时为编辑）。
class BackupStorageEditPage extends ConsumerStatefulWidget {
  const BackupStorageEditPage({super.key, this.id});

  /// 为 null 表示新建。
  final int? id;

  @override
  ConsumerState<BackupStorageEditPage> createState() =>
      _BackupStorageEditPageState();
}

class _BackupStorageEditPageState extends ConsumerState<BackupStorageEditPage> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();

  // S3
  final _accessKeyController = TextEditingController();
  final _secretKeyController = TextEditingController();
  final _regionController = TextEditingController(text: 'us-east-1');
  final _endpointController = TextEditingController();
  final _bucketController = TextEditingController();

  // SFTP / WebDAV
  final _urlController = TextEditingController();
  final _hostController = TextEditingController();
  final _portController = TextEditingController(text: '22');
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _privateKeyController = TextEditingController();

  final _pathController = TextEditingController();

  String _type = BackupStorageTypes.s3;
  String _style = 'virtual-hosted';
  String _scheme = 'https';

  /// SFTP 认证方式：password / private_key（仅前端用于切换输入项）。
  String _sftpAuth = 'password';

  bool _loading = false;
  Object? _loadError;
  bool _saving = false;

  /// 是否有未保存的修改（用于返回拦截）。
  bool _dirty = false;

  /// 由代码（加载已有配置）而非用户输入引起的变更，不计入 [_dirty]。
  bool _suppressDirty = false;

  bool get _isEdit => widget.id != null;

  /// 全部输入控制器，便于统一挂 / 摘监听与释放。
  List<TextEditingController> get _controllers => [
        _nameController,
        _accessKeyController,
        _secretKeyController,
        _regionController,
        _endpointController,
        _bucketController,
        _urlController,
        _hostController,
        _portController,
        _usernameController,
        _passwordController,
        _privateKeyController,
        _pathController,
      ];

  @override
  void initState() {
    super.initState();
    for (final controller in _controllers) {
      controller.addListener(_markDirty);
    }
    if (_isEdit) _load();
  }

  /// 标记「有未保存的修改」；已标记或处于抑制期时为空操作。
  void _markDirty() {
    if (_suppressDirty || _dirty || !mounted) return;
    setState(() => _dirty = true);
  }

  /// 下拉框等非文本字段变更的统一入口：改状态 + 标脏。
  void _updateField(VoidCallback change) {
    setState(change);
    _markDirty();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _accessKeyController.dispose();
    _secretKeyController.dispose();
    _regionController.dispose();
    _endpointController.dispose();
    _bucketController.dispose();
    _urlController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _privateKeyController.dispose();
    _pathController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final storage = await ref.read(backupStorageRepoProvider).get(widget.id!);
      if (!mounted) return;
      final info = storage.info;
      _suppressDirty = true;
      setState(() {
        _nameController.text = storage.name;
        _type = BackupStorageTypes.creatable.contains(storage.type)
            ? storage.type
            : BackupStorageTypes.s3;
        _accessKeyController.text = info.accessKey;
        _secretKeyController.text = info.secretKey;
        _style = info.style.isEmpty ? 'virtual-hosted' : info.style;
        _regionController.text = info.region;
        _endpointController.text = info.endpoint;
        _scheme = info.scheme.isEmpty ? 'https' : info.scheme;
        _bucketController.text = info.bucket;
        _urlController.text = info.url;
        _hostController.text = info.host;
        _portController.text = '${info.port}';
        _usernameController.text = info.username;
        _passwordController.text = info.password;
        _privateKeyController.text = info.privateKey;
        _pathController.text = info.path;
        _sftpAuth = info.privateKey.isNotEmpty ? 'private_key' : 'password';
        _loading = false;
        _dirty = false;
      });
      _suppressDirty = false;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = e;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final server = ref.watch(activeServerProvider);
    return UnsavedChangesGuard(
      hasUnsavedChanges: _dirty && !_saving,
      message: _isEdit ? '存储配置的修改还没有保存，确定放弃吗？' : '新建的存储还没有创建，确定放弃吗？',
      child: Scaffold(
        appBar: AppBar(title: Text(_isEdit ? '编辑备份存储' : '添加备份存储')),
        body: server == null
            ? const NoServerView()
            : _loading
                ? const LoadingView(message: '正在加载存储配置…')
                : _loadError != null
                    ? ErrorView(error: _loadError!, onRetry: _load)
                    : _buildForm(),
        bottomNavigationBar: server == null || _loading || _loadError != null
            ? null
            : SafeArea(
                minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton(
                  onPressed: _saving ? null : _submit,
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_isEdit ? '保存' : '创建'),
                ),
              ),
      ),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        children: [
          SectionCard(
            title: '基本信息',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: '名称'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? '请填写名称' : null,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _type,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '类型'),
                  items: [
                    for (final type in BackupStorageTypes.creatable)
                      DropdownMenuItem(
                        value: type,
                        child: Text(BackupStorageTypes.label(type)),
                      ),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    _updateField(() {
                      _type = v;
                      if (v == BackupStorageTypes.sftp &&
                          _portController.text.trim().isEmpty) {
                        _portController.text = '22';
                      }
                    });
                  },
                ),
              ],
            ),
          ),
          if (_type == BackupStorageTypes.s3) _buildS3Section(),
          if (_type == BackupStorageTypes.sftp) _buildSftpSection(),
          if (_type == BackupStorageTypes.webdav) _buildWebdavSection(),
        ],
      ),
    );
  }

  Widget _buildS3Section() {
    return SectionCard(
      title: 'S3 配置',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _accessKeyController,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Access Key'),
            validator: _requiredValidator('Access Key'),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _secretKeyController,
            autocorrect: false,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Secret Key'),
            validator: _requiredValidator('Secret Key'),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _style,
            isExpanded: true,
            decoration: const InputDecoration(labelText: '寻址风格'),
            items: const [
              DropdownMenuItem(
                value: 'virtual-hosted',
                child: Text('Virtual Hosted'),
              ),
              DropdownMenuItem(value: 'path', child: Text('Path')),
            ],
            onChanged: (v) =>
                _updateField(() => _style = v ?? 'virtual-hosted'),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _regionController,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: '地区（Region）',
              hintText: 'us-east-1',
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _endpointController,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: '端点（Endpoint）',
              hintText: 's3.amazonaws.com',
            ),
            validator: _requiredValidator('端点'),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _scheme,
            isExpanded: true,
            decoration: const InputDecoration(labelText: '协议'),
            items: const [
              DropdownMenuItem(value: 'https', child: Text('HTTPS')),
              DropdownMenuItem(value: 'http', child: Text('HTTP')),
            ],
            onChanged: (v) => _updateField(() => _scheme = v ?? 'https'),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _bucketController,
            autocorrect: false,
            decoration: const InputDecoration(labelText: '存储桶（Bucket）'),
            validator: _requiredValidator('存储桶'),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _pathController,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: '路径（可选）',
              hintText: 'backup/',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSftpSection() {
    return SectionCard(
      title: 'SFTP 配置',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _hostController,
            autocorrect: false,
            decoration: const InputDecoration(labelText: '主机'),
            validator: _requiredValidator('主机'),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _portController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '端口'),
            validator: (v) {
              final n = int.tryParse((v ?? '').trim());
              if (n == null || n < 1 || n > 65535) return '端口需为 1-65535';
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _usernameController,
            autocorrect: false,
            decoration: const InputDecoration(labelText: '用户名'),
            validator: _requiredValidator('用户名'),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _sftpAuth,
            isExpanded: true,
            decoration: const InputDecoration(labelText: '认证方式'),
            items: const [
              DropdownMenuItem(value: 'password', child: Text('密码')),
              DropdownMenuItem(value: 'private_key', child: Text('私钥')),
            ],
            onChanged: (v) => _updateField(() => _sftpAuth = v ?? 'password'),
          ),
          const SizedBox(height: 16),
          if (_sftpAuth == 'password')
            TextFormField(
              controller: _passwordController,
              autocorrect: false,
              obscureText: true,
              decoration: const InputDecoration(labelText: '密码'),
              validator: _requiredValidator('密码'),
            )
          else
            TextFormField(
              controller: _privateKeyController,
              autocorrect: false,
              maxLines: 6,
              minLines: 4,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              decoration: const InputDecoration(
                labelText: '私钥',
                alignLabelWithHint: true,
                hintText: '-----BEGIN OPENSSH PRIVATE KEY-----',
              ),
              validator: _requiredValidator('私钥'),
            ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _pathController,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: '远程路径',
              hintText: '/backup',
            ),
            validator: _requiredValidator('远程路径'),
          ),
        ],
      ),
    );
  }

  Widget _buildWebdavSection() {
    return SectionCard(
      title: 'WebDAV 配置',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _urlController,
            autocorrect: false,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'URL',
              hintText: 'https://dav.example.com/dav',
            ),
            validator: _requiredValidator('URL'),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _usernameController,
            autocorrect: false,
            decoration: const InputDecoration(labelText: '用户名'),
            validator: _requiredValidator('用户名'),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _passwordController,
            autocorrect: false,
            obscureText: true,
            decoration: const InputDecoration(labelText: '密码'),
            validator: _requiredValidator('密码'),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _pathController,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: '路径（可选）',
              hintText: '/backup',
            ),
          ),
        ],
      ),
    );
  }

  String? Function(String?) _requiredValidator(String label) {
    return (value) =>
        (value == null || value.trim().isEmpty) ? '请填写$label' : null;
  }

  BackupStorageInfo _buildInfo() {
    final port = int.tryParse(_portController.text.trim()) ?? 22;
    return BackupStorageInfo(
      accessKey: _accessKeyController.text.trim(),
      secretKey: _secretKeyController.text.trim(),
      style: _style,
      region: _regionController.text.trim(),
      endpoint: _endpointController.text.trim(),
      scheme: _scheme,
      bucket: _bucketController.text.trim(),
      url: _urlController.text.trim(),
      host: _hostController.text.trim(),
      port: port,
      username: _usernameController.text.trim(),
      // SFTP 选择私钥认证时不提交密码，反之不提交私钥。
      password: _type == BackupStorageTypes.sftp && _sftpAuth == 'private_key'
          ? ''
          : _passwordController.text,
      privateKey: _type == BackupStorageTypes.sftp && _sftpAuth == 'password'
          ? ''
          : _privateKeyController.text,
      path: _pathController.text.trim(),
    );
  }

  Future<void> _submit() async {
    if (_saving) return;
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    setState(() => _saving = true);
    try {
      final repo = ref.read(backupStorageRepoProvider);
      if (_isEdit) {
        await repo.update(
          id: widget.id!,
          type: _type,
          name: _nameController.text.trim(),
          info: _buildInfo(),
        );
      } else {
        await repo.create(
          type: _type,
          name: _nameController.text.trim(),
          info: _buildInfo(),
        );
      }
      if (!mounted) return;
      _dirty = false;
      showSuccessSnack(context, _isEdit ? '已保存' : '创建成功');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
