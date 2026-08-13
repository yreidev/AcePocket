import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/server_store.dart';
import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_view.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/unsaved_guard.dart';
import '../models/cron.dart';
import '../providers/cron_providers.dart';
import '../providers/options_providers.dart';
import '../providers/storage_providers.dart';
import '../widgets/cron_expression_field.dart';
import '../widgets/feedback.dart';
import '../widgets/kv_editor.dart';
import '../widgets/multi_select_field.dart';
import '../widgets/no_server_view.dart';
import '../widgets/string_list_editor.dart';

/// 计划任务创建 / 编辑页（`/crons/edit`，带 `id` 查询参数时为编辑）。
class CronEditPage extends ConsumerStatefulWidget {
  const CronEditPage({super.key, this.id});

  /// 为 null 表示新建。
  final int? id;

  @override
  ConsumerState<CronEditPage> createState() => _CronEditPageState();
}

class _CronEditPageState extends ConsumerState<CronEditPage> {
  /// backup / cutoff 的默认子类型（两者的子类型表都以「网站」打头）。
  static const _kDefaultSubType = 'website';

  /// 新建脚本任务时预填的模板。
  static const _scriptTemplate = '#!/bin/bash\n'
      'export PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:'
      '/usr/local/sbin:\$PATH\n\n'
      '# 在此填写脚本内容\n';

  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _timeController = TextEditingController(text: '*/30 * * * *');
  final _scriptController = TextEditingController(text: _scriptTemplate);
  final _urlController = TextEditingController();
  final _bodyController = TextEditingController();
  final _keepController = TextEditingController(text: '1');
  final _timeoutController = TextEditingController(text: '10');
  final _retriesController = TextEditingController(text: '0');

  String _type = CronTypes.shell;
  String _subType = 'website';
  bool _flock = false;
  int _storage = 0;
  List<String> _targets = const [];
  String _method = 'GET';
  List<KvEntry> _headers = [];
  bool _insecure = false;

  bool _nameEdited = false;
  bool _loading = false;
  Object? _loadError;
  bool _saving = false;

  /// 服务端脚本文件路径（编辑模式下用于重试读取）。
  String _shellPath = '';

  /// 脚本读取失败的原因；非 null 时禁止保存（见 [_scriptReadFailed]）。
  Object? _scriptError;

  /// 正在重试读取脚本。
  bool _scriptRetrying = false;

  /// 是否有未保存的修改（用于返回拦截）。
  bool _dirty = false;

  /// 由代码（加载 / 自动纠正）而非用户操作引起的变更，不计入 [_dirty]。
  bool _suppressDirty = false;

  bool get _isEdit => widget.id != null;

  /// 编辑脚本任务时脚本内容读取失败。
  ///
  /// 此时输入框里只有默认模板，直接提交会让面板把模板写进脚本文件、
  /// **覆盖服务器上的真实脚本且不可恢复**，因此必须阻断保存。
  bool get _scriptReadFailed =>
      _isEdit && _type == CronTypes.shell && _scriptError != null;

  @override
  void initState() {
    super.initState();
    _nameController.addListener(() {
      if (_nameController.text.isNotEmpty) _nameEdited = true;
    });
    for (final controller in <TextEditingController>[
      _nameController,
      _timeController,
      _scriptController,
      _urlController,
      _bodyController,
      _keepController,
      _timeoutController,
      _retriesController,
    ]) {
      controller.addListener(_markDirty);
    }
    if (_isEdit) {
      _load();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _timeController.dispose();
    _scriptController.dispose();
    _urlController.dispose();
    _bodyController.dispose();
    _keepController.dispose();
    _timeoutController.dispose();
    _retriesController.dispose();
    super.dispose();
  }

  /// 标记「有未保存的修改」；已标记或处于抑制期时为空操作。
  void _markDirty() {
    if (_suppressDirty || _dirty || !mounted) return;
    setState(() => _dirty = true);
  }

  /// 表单字段变更的统一入口：改状态 + 标脏。
  void _updateField(VoidCallback change) {
    setState(change);
    _markDirty();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final repo = ref.read(cronRepoProvider);
      final cron = await repo.get(widget.id!);
      final needScript = cron.type == CronTypes.shell && cron.shell.isNotEmpty;
      String script = '';
      Object? scriptError;
      if (needScript) {
        try {
          script = await repo.readFile(cron.shell);
        } catch (e) {
          scriptError = e;
        }
      }
      if (!mounted) return;
      _suppressDirty = true;
      setState(() {
        _nameController.text = cron.name;
        _timeController.text = cron.time;
        _type = cron.type;
        _flock = cron.config.flock;
        _storage = cron.config.storage;
        _targets = List.of(cron.config.targets);
        _subType = cron.config.subType.isEmpty
            ? _kDefaultSubType
            : cron.config.subType;
        _keepController.text =
            '${cron.config.keep <= 0 ? 1 : cron.config.keep}';
        _urlController.text = cron.config.url;
        _method = cron.config.method.isEmpty ? 'GET' : cron.config.method;
        _headers = cron.config.headers.entries
            .map((e) => KvEntry(key: e.key, value: e.value))
            .toList();
        _bodyController.text = cron.config.body;
        _timeoutController.text = '${cron.config.timeout}';
        _retriesController.text = '${cron.config.retries}';
        _insecure = cron.config.insecure;
        _shellPath = cron.shell;
        _scriptError = scriptError;
        // 读取成功才写入输入框——哪怕内容为空串也照写，否则空脚本会被
        // 默认模板顶替，保存时同样会覆盖服务器上的文件。
        if (needScript && scriptError == null) {
          _scriptController.text = script;
        }
        _nameEdited = true;
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

  /// 单独重试读取脚本内容（整页数据已经加载好，不必重来一遍）。
  Future<void> _retryReadScript() async {
    if (_scriptRetrying || _shellPath.isEmpty) return;
    setState(() => _scriptRetrying = true);
    try {
      final script = await ref.read(cronRepoProvider).readFile(_shellPath);
      if (!mounted) return;
      _suppressDirty = true;
      setState(() {
        _scriptController.text = script;
        _scriptError = null;
        _scriptRetrying = false;
      });
      _suppressDirty = false;
      showSuccessSnack(context, '脚本内容已读取');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _scriptError = e;
        _scriptRetrying = false;
      });
      showErrorSnack(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final server = ref.watch(activeServerProvider);
    final blocked = _scriptReadFailed;
    return UnsavedChangesGuard(
      hasUnsavedChanges: _dirty && !_saving,
      message: _isEdit ? '任务的修改还没有保存，确定放弃吗？' : '新建的任务还没有创建，确定放弃吗？',
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isEdit ? '编辑计划任务' : '新建计划任务'),
        ),
        body: server == null
            ? const NoServerView()
            : _loading
                ? const LoadingView(message: '正在加载任务详情…')
                : _loadError != null
                    ? ErrorView(error: _loadError!, onRetry: _load)
                    : _buildForm(context),
        bottomNavigationBar: server == null || _loading || _loadError != null
            ? null
            : SafeArea(
                minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (blocked)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          '脚本内容未能读取，保存会覆盖服务器上的现有脚本，'
                          '请先在上方重试读取。',
                          textAlign: TextAlign.center,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                        ),
                      ),
                    FilledButton(
                      onPressed: _saving || blocked ? null : _submit,
                      child: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_isEdit ? '保存' : '创建'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    final theme = Theme.of(context);
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
                if (!_isEdit) ...[
                  DropdownButtonFormField<String>(
                    initialValue: _type,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '任务类型'),
                    items: [
                      for (final type in CronTypes.all)
                        DropdownMenuItem(
                          value: type,
                          child: Text(CronTypes.label(type)),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      _updateField(() {
                        _type = value;
                        _subType = _kDefaultSubType;
                        _targets = const [];
                      });
                      _autoName();
                    },
                  ),
                  const SizedBox(height: 16),
                ] else ...[
                  InputDecorator(
                    decoration: const InputDecoration(labelText: '任务类型'),
                    child: Text(CronTypes.label(_type)),
                  ),
                  const SizedBox(height: 16),
                ],
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: '任务名称'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? '请填写任务名称' : null,
                ),
                const SizedBox(height: 16),
                CronExpressionField(controller: _timeController),
                const SizedBox(height: 8),
                a11ySwitch(
                  label: '进程锁',
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _flock,
                    onChanged: (v) => _updateField(() => _flock = v),
                    title: const Text('进程锁'),
                    subtitle: Text(
                      '上一次执行尚未结束时跳过本次执行',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_type == CronTypes.shell) _buildShellSection(theme),
          if (_type == CronTypes.url) _buildUrlSection(),
          if (_type == CronTypes.backup || _type == CronTypes.cutoff)
            _buildBackupSection(theme),
          if (_type == CronTypes.synctime)
            SectionCard(
              title: '说明',
              child: Text(
                '同步时间任务会按设定周期与 NTP 服务器校准系统时间，无需额外配置。',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildShellSection(ThemeData theme) {
    return SectionCard(
      title: '脚本内容',
      child: _scriptReadFailed
          ? _buildScriptErrorPanel(theme)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _scriptController,
                  maxLines: 16,
                  minLines: 8,
                  autocorrect: false,
                  enableSuggestions: false,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                  ),
                  decoration: const InputDecoration(
                    alignLabelWithHint: true,
                    hintText: '#!/bin/bash',
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? '请填写脚本内容' : null,
                ),
                const SizedBox(height: 8),
                Text(
                  '保存后脚本会写入服务器上的任务脚本文件并覆盖原内容。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
    );
  }

  /// 脚本读取失败时替代编辑框展示：说明后果 + 重试读取。
  ///
  /// 这里刻意**不展示输入框**——框里只有默认模板，让用户误以为那就是服务器上
  /// 的脚本，是数据丢失的直接来源。
  Widget _buildScriptErrorPanel(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline,
                  size: 20, color: colorScheme.onErrorContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '脚本内容读取失败',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            describeError(_scriptError!),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onErrorContainer,
            ),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Text(
            '为避免把默认模板写进服务器上的脚本文件、覆盖掉原有内容，'
            '读取成功前无法保存本任务。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onErrorContainer,
            ),
          ),
          if (_shellPath.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _shellPath,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onErrorContainer,
                fontFamily: 'monospace',
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              onPressed: _scriptRetrying ? null : _retryReadScript,
              icon: _scriptRetrying
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh, size: 18),
              label: Text(_scriptRetrying ? '正在读取…' : '重试读取脚本'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUrlSection() {
    return SectionCard(
      title: '请求配置',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _method,
            isExpanded: true,
            decoration: const InputDecoration(labelText: '请求方法'),
            items: [
              for (final m in CronTypes.httpMethods)
                DropdownMenuItem(value: m, child: Text(m)),
            ],
            onChanged: (v) {
              if (v == null) return;
              _updateField(() => _method = v);
              _autoName();
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _urlController,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'URL',
              hintText: 'https://example.com',
            ),
            onChanged: (_) => _autoName(),
            validator: (v) {
              if (_type != CronTypes.url) return null;
              final text = (v ?? '').trim();
              if (text.isEmpty) return '请填写 URL';
              final uri = Uri.tryParse(text);
              if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
                return 'URL 格式不正确，需包含 http(s)://';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          KvEditor(
            label: '自定义请求头',
            entries: _headers,
            keyHint: '名称',
            onChanged: (v) => _updateField(() => _headers = v),
          ),
          if (_method == 'POST' || _method == 'PUT' || _method == 'PATCH') ...[
            const SizedBox(height: 8),
            TextFormField(
              controller: _bodyController,
              maxLines: 6,
              minLines: 3,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: '请求体',
                alignLabelWithHint: true,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _timeoutController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '超时（秒）'),
                  validator: (v) => _validateNonNegativeInt(v, '超时时间'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _retriesController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '失败重试次数'),
                  validator: (v) => _validateNonNegativeInt(v, '重试次数'),
                ),
              ),
            ],
          ),
          a11ySwitch(
            label: '忽略证书校验',
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _insecure,
              onChanged: (v) => _updateField(() => _insecure = v),
              title: const Text('忽略证书校验'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackupSection(ThemeData theme) {
    final isBackup = _type == CronTypes.backup;
    final subTypes =
        isBackup ? CronTypes.backupSubTypes : CronTypes.cutoffSubTypes;
    return SectionCard(
      title: isBackup ? '备份配置' : '日志切割配置',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            initialValue: subTypes.containsKey(_subType) ? _subType : null,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: isBackup ? '备份类型' : '切割类型',
            ),
            items: [
              for (final entry in subTypes.entries)
                DropdownMenuItem(
                  value: entry.key,
                  child: Text(entry.value, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (value) {
              if (value == null) return;
              _updateField(() {
                _subType = value;
                // Redis / Valkey 为整实例备份，目标固定为实例类型本身。
                _targets = (value == 'redis' || value == 'valkey')
                    ? [value]
                    : const [];
              });
              _autoName();
            },
            validator: (v) => (v == null || v.isEmpty)
                ? '请选择${isBackup ? '备份' : '切割'}类型'
                : null,
          ),
          const SizedBox(height: 16),
          _buildTargetField(theme),
          const SizedBox(height: 16),
          TextFormField(
            controller: _keepController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '保留份数',
              helperText: '超出份数的旧备份会被自动清理',
            ),
            validator: (v) {
              final n = int.tryParse((v ?? '').trim());
              if (n == null || n < 1) return '保留份数需为大于 0 的整数';
              return null;
            },
          ),
          const SizedBox(height: 16),
          _buildStorageField(),
        ],
      ),
    );
  }

  Widget _buildTargetField(ThemeData theme) {
    final isBackup = _type == CronTypes.backup;

    if (isBackup && (_subType == 'redis' || _subType == 'valkey')) {
      return InputDecorator(
        decoration: const InputDecoration(labelText: '备份目标'),
        child: Text(
          '${_subType == 'redis' ? 'Redis' : 'Valkey'} 整实例备份，无需选择具体库',
          style: theme.textTheme.bodyMedium,
        ),
      );
    }

    if (isBackup && _subType == 'path') {
      return StringListEditor(
        label: '备份目录',
        values: _targets,
        hintText: '/www/wwwroot/example',
        addLabel: '添加目录',
        onChanged: (v) {
          _updateField(() => _targets = v);
          _autoName();
        },
      );
    }

    if (_subType == 'container') {
      return MultiSelectField(
        label: '选择容器',
        selected: _targets,
        options: ref.watch(containerOptionsProvider),
        onReload: () => ref.invalidate(containerOptionsProvider),
        onChanged: (v) {
          _updateField(() => _targets = v);
          _autoName();
        },
      );
    }

    if (isBackup &&
        CronTypes.backupSubTypes.containsKey(_subType) &&
        _subType != 'website') {
      // mysql / postgresql / clickhouse
      final provider = databaseOptionsProvider(_subType);
      return MultiSelectField(
        label: '选择数据库',
        selected: _targets,
        options: ref.watch(provider),
        onReload: () => ref.invalidate(provider),
        onChanged: (v) {
          _updateField(() => _targets = v);
          _autoName();
        },
      );
    }

    return MultiSelectField(
      label: '选择网站',
      selected: _targets,
      options: ref.watch(websiteOptionsProvider),
      onReload: () => ref.invalidate(websiteOptionsProvider),
      onChanged: (v) {
        _updateField(() => _targets = v);
        _autoName();
      },
    );
  }

  Widget _buildStorageField() {
    final storages = ref.watch(storageOptionsProvider);
    return storages.when(
      loading: () => const InputDecorator(
        decoration: InputDecoration(labelText: '备份存储'),
        child: Text('加载中…'),
      ),
      error: (error, _) => InputDecorator(
        decoration: InputDecoration(
          labelText: '备份存储',
          errorText: describeError(error),
          suffixIcon: A11yIconButton(
            tooltip: '重新加载备份存储列表',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(storageOptionsProvider),
          ),
        ),
        child: const Text('加载失败，默认使用本地存储'),
      ),
      data: (list) {
        final ids = list.map((e) => e.id).toList();
        final value = ids.contains(_storage)
            ? _storage
            : (ids.isEmpty ? null : ids.first);
        // 原先选中的存储已被删除时，下拉框回退到第一项，但 _storage 仍是失效的
        // ID，提交出去会落到一个不存在的存储上——这里把状态一并纠正过来。
        if (value != null && value != _storage) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || _storage == value) return;
            // 属于自动纠正而非用户编辑，不标记为「未保存的修改」。
            setState(() => _storage = value);
          });
        }
        return DropdownButtonFormField<int>(
          initialValue: value,
          isExpanded: true,
          decoration: const InputDecoration(labelText: '备份存储'),
          items: [
            for (final option in list)
              DropdownMenuItem(
                value: option.id,
                child: Text(
                  option.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (v) => _updateField(() => _storage = v ?? 0),
        );
      },
    );
  }

  String? _validateNonNegativeInt(String? value, String label) {
    final n = int.tryParse((value ?? '').trim());
    if (n == null || n < 0) return '$label需为不小于 0 的整数';
    return null;
  }

  /// 新建模式下根据类型与目标自动生成任务名（用户手动改过则不再覆盖）。
  void _autoName() {
    if (_isEdit || _nameEdited) return;
    String name;
    switch (_type) {
      case CronTypes.backup:
        final prefix = '备份${CronTypes.backupSubTypes[_subType] ?? ''}';
        name = _targets.isEmpty ? prefix : '$prefix - ${_targets.join('、')}';
        break;
      case CronTypes.cutoff:
        final prefix = '日志切割 - ${CronTypes.cutoffSubTypes[_subType] ?? ''}';
        name = _targets.isEmpty ? prefix : '$prefix - ${_targets.join('、')}';
        break;
      case CronTypes.url:
        final url = _urlController.text.trim();
        name = url.isEmpty ? '访问 URL' : '$_method - $url';
        break;
      case CronTypes.synctime:
        name = '同步时间';
        break;
      default:
        return;
    }
    // 直接改 text 会触发监听把 _nameEdited 置 true，这里手动还原。
    _nameController.text = name;
    _nameEdited = false;
  }

  Future<void> _submit() async {
    if (_saving) return;

    // 兜底：保存按钮此时应已禁用，仍再挡一次，绝不让默认模板覆盖真实脚本。
    if (_scriptReadFailed) {
      showErrorSnack(context, '脚本内容未能读取，保存会覆盖服务器上的现有脚本，请先重试读取');
      return;
    }

    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    final needTargets = _type == CronTypes.backup || _type == CronTypes.cutoff;
    final targets =
        _targets.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (needTargets && targets.isEmpty) {
      showErrorSnack(context, '请至少选择一个目标');
      return;
    }

    final headers = <String, String>{};
    for (final entry in _headers) {
      final key = entry.key.trim();
      if (key.isNotEmpty) headers[key] = entry.value;
    }

    final keep = int.tryParse(_keepController.text.trim()) ?? 1;
    final timeout = int.tryParse(_timeoutController.text.trim()) ?? 10;
    final retries = int.tryParse(_retriesController.text.trim()) ?? 0;

    setState(() => _saving = true);
    try {
      final repo = ref.read(cronRepoProvider);
      if (_isEdit) {
        await repo.update(
          id: widget.id!,
          name: _nameController.text.trim(),
          type: _type,
          time: _timeController.text.trim(),
          script: _type == CronTypes.shell ? _scriptController.text : '',
          subType: needTargets ? _subType : '',
          flock: _flock,
          storage: _storage,
          targets: targets,
          keep: keep < 1 ? 1 : keep,
          url: _urlController.text.trim(),
          method: _method,
          headers: headers,
          body: _bodyController.text,
          timeout: timeout,
          insecure: _insecure,
          retries: retries,
        );
      } else {
        await repo.create(
          name: _nameController.text.trim(),
          type: _type,
          time: _timeController.text.trim(),
          script: _type == CronTypes.shell ? _scriptController.text : '',
          subType: needTargets ? _subType : '',
          flock: _flock,
          storage: _storage,
          targets: targets,
          keep: keep < 1 ? 1 : keep,
          url: _urlController.text.trim(),
          method: _method,
          headers: headers,
          body: _bodyController.text,
          timeout: timeout,
          insecure: _insecure,
          retries: retries,
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
