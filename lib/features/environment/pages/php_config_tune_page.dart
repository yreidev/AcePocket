import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/app_snack.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_view.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/unsaved_guard.dart';
import '../models/php_models.dart';
import '../providers/environment_providers.dart';
import '../widgets/environment_ui.dart';

/// PHP 参数调优页（`/environments/php/:version/tune`）。
///
/// 对应 `GET/POST /environment/php/{version}/config_tune`：面板逐项读写
/// `php.ini` 与 `php-fpm.conf`，留空表示注释掉该配置项。
/// 另含 `POST /environment/php/{version}/clean_session`（清理 Session 文件）。
///
/// 本页有 6 张卡片 20 余项输入，误触返回或「重新载入」会清空全部草稿，
/// 因此表单的「是否有未保存修改」上提到页面级（[_dirty]），
/// 同时供 [UnsavedChangesGuard]（侧滑 / 返回键 / 返回箭头）与
/// AppBar 的重新载入按钮消费，两条路径行为一致。
class PhpConfigTunePage extends ConsumerStatefulWidget {
  const PhpConfigTunePage({super.key, required this.version});

  final int version;

  @override
  ConsumerState<PhpConfigTunePage> createState() => _PhpConfigTunePageState();
}

class _PhpConfigTunePageState extends ConsumerState<PhpConfigTunePage> {
  /// 表单是否有未保存修改，由 [_TuneForm] 写入。
  ///
  /// 用 [ValueNotifier] 而非 setState 上抛：避免每次脏标记翻转都重建
  /// `tune.when(...)`，也避免在子组件 build 期间调用父级 setState。
  final ValueNotifier<bool> _dirty = ValueNotifier<bool>(false);

  /// 重新载入代次。并入表单 key，保证「放弃修改并重新载入」一定重建表单，
  /// 即使服务端返回的数据与上一次完全一致（此时 key 的数据部分不变）。
  int _reloadToken = 0;

  @override
  void dispose() {
    _dirty.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    if (_dirty.value) {
      final ok = await showConfirmDialog(
        context,
        title: '放弃修改',
        content: '重新载入会丢弃当前所有未保存的修改。',
        confirmText: '放弃修改',
        cancelText: '继续编辑',
        danger: true,
      );
      if (!ok || !mounted) return;
    }
    _dirty.value = false;
    setState(() => _reloadToken++);
    ref.invalidate(phpConfigTuneProvider(widget.version));
  }

  @override
  Widget build(BuildContext context) {
    final tune = ref.watch(phpConfigTuneProvider(widget.version));
    return ValueListenableBuilder<bool>(
      valueListenable: _dirty,
      builder: (context, dirty, _) => UnsavedChangesGuard(
        hasUnsavedChanges: dirty,
        message: '参数调优表单中有未保存的修改，确定放弃吗？',
        child: Scaffold(
          appBar: AppBar(
            title: Text('参数调优 · PHP ${phpVersionText(widget.version)}'),
            actions: [
              A11yIconButton(
                tooltip: '重新载入配置',
                icon: const Icon(Icons.refresh),
                onPressed: _reload,
              ),
            ],
          ),
          body: tune.when(
            loading: () => const LoadingView(message: '读取 PHP 配置…'),
            error: (error, _) => ErrorView(
              error: error,
              onRetry: () =>
                  ref.invalidate(phpConfigTuneProvider(widget.version)),
            ),
            data: (data) => _TuneForm(
              key: ValueKey('$_reloadToken:${data.toJson()}'),
              version: widget.version,
              initial: data,
              dirty: _dirty,
            ),
          ),
        ),
      ),
    );
  }
}

/// Session 保存方式支持的取值。
const List<String> _sessionHandlers = ['files', 'redis', 'memcached'];

/// php-fpm 进程管理方式（服务端 `validate:"in:static,dynamic,ondemand"`）。
const List<String> _pmModes = ['dynamic', 'static', 'ondemand'];

/// 容量单位；空串表示不带单位（php.ini 中按字节计，也用于 `-1` 这类特殊值）。
const List<String> _sizeUnits = ['', 'K', 'M', 'G'];

/// 单位下拉的展示文案。
String _sizeUnitLabel(String unit) => unit.isEmpty ? '字节' : unit;

class _TuneForm extends ConsumerStatefulWidget {
  const _TuneForm({
    super.key,
    required this.version,
    required this.initial,
    required this.dirty,
  });

  final int version;
  final PhpConfigTune initial;

  /// 页面级的「有未保存修改」标记，见 [_PhpConfigTunePageState._dirty]。
  final ValueNotifier<bool> dirty;

  @override
  ConsumerState<_TuneForm> createState() => _TuneFormState();
}

class _TuneFormState extends ConsumerState<_TuneForm> {
  // 常规
  late String _shortOpenTag = _normalizeOnOff(widget.initial.shortOpenTag);
  late String _displayErrors = _normalizeOnOff(widget.initial.displayErrors);
  late final TextEditingController _dateTimezone =
      TextEditingController(text: widget.initial.dateTimezone);
  late final TextEditingController _errorReporting =
      TextEditingController(text: widget.initial.errorReporting);

  // 禁用函数
  late final TextEditingController _disableFunctions =
      TextEditingController(text: widget.initial.disableFunctions);

  // 上传限制
  late final PhpSizeValue _uploadInit =
      PhpSizeValue.parse(widget.initial.uploadMaxFilesize);
  late final PhpSizeValue _postInit =
      PhpSizeValue.parse(widget.initial.postMaxSize);
  late final PhpSizeValue _memoryInit =
      PhpSizeValue.parse(widget.initial.memoryLimit);
  late final TextEditingController _uploadMaxFilesize =
      TextEditingController(text: _uploadInit.number);
  late String _uploadUnit = _uploadInit.unit;
  late final TextEditingController _postMaxSize =
      TextEditingController(text: _postInit.number);
  late String _postUnit = _postInit.unit;
  late final TextEditingController _memoryLimit =
      TextEditingController(text: _memoryInit.number);
  late String _memoryUnit = _memoryInit.unit;
  late final TextEditingController _maxFileUploads =
      TextEditingController(text: widget.initial.maxFileUploads);

  // 超时限制
  late final TextEditingController _maxExecutionTime =
      TextEditingController(text: widget.initial.maxExecutionTime);
  late final TextEditingController _maxInputTime =
      TextEditingController(text: widget.initial.maxInputTime);
  late final TextEditingController _maxInputVars =
      TextEditingController(text: widget.initial.maxInputVars);

  // Session
  late String _sessionHandler = _sessionHandlers.contains(
    widget.initial.sessionSaveHandler.trim(),
  )
      ? widget.initial.sessionSaveHandler.trim()
      : 'files';
  late final TextEditingController _sessionSavePath = TextEditingController(
    text: _sessionHandler == 'files' ? widget.initial.sessionSavePath : '',
  );
  late final _RedisSavePath _redisInit =
      _RedisSavePath.parse(widget.initial.sessionSavePath);
  late final _MemcachedSavePath _memcachedInit =
      _MemcachedSavePath.parse(widget.initial.sessionSavePath);
  late final TextEditingController _redisHost =
      TextEditingController(text: _redisInit.host);
  late final TextEditingController _redisPort =
      TextEditingController(text: _redisInit.port);
  late final TextEditingController _redisPassword =
      TextEditingController(text: _redisInit.password);
  late final TextEditingController _memcachedHost =
      TextEditingController(text: _memcachedInit.host);
  late final TextEditingController _memcachedPort =
      TextEditingController(text: _memcachedInit.port);
  late final TextEditingController _sessionGcMaxlifetime =
      TextEditingController(text: widget.initial.sessionGcMaxlifetime);
  late final TextEditingController _sessionCookieLifetime =
      TextEditingController(text: widget.initial.sessionCookieLifetime);

  // FPM 进程管理
  late String _pm = _pmModes.contains(widget.initial.pm.trim())
      ? widget.initial.pm.trim()
      : 'dynamic';
  late final TextEditingController _pmMaxChildren =
      TextEditingController(text: widget.initial.pmMaxChildren);
  late final TextEditingController _pmStartServers =
      TextEditingController(text: widget.initial.pmStartServers);
  late final TextEditingController _pmMinSpareServers =
      TextEditingController(text: widget.initial.pmMinSpareServers);
  late final TextEditingController _pmMaxSpareServers =
      TextEditingController(text: widget.initial.pmMaxSpareServers);

  bool _saving = false;
  bool _cleaning = false;

  /// 载入时的表单快照。
  ///
  /// 不能直接和 `widget.initial` 比较：控件对原始值做了归一化
  /// （`1` → `On`、`50m` → `50` + `M`、未知 handler 回落 `files` 等），
  /// 那样一进页面就会被判为「已修改」。这里以归一化后的首帧值为基准。
  late String _baseline;

  /// 与 [_baseline] 的比较结果，用于底部的未保存提示。
  bool _localDirty = false;

  /// 全部文本控制器，initState 挂监听、dispose 时释放，避免两处列表不同步。
  late final List<TextEditingController> _controllers = [
    _dateTimezone,
    _errorReporting,
    _disableFunctions,
    _uploadMaxFilesize,
    _postMaxSize,
    _memoryLimit,
    _maxFileUploads,
    _maxExecutionTime,
    _maxInputTime,
    _maxInputVars,
    _sessionSavePath,
    _redisHost,
    _redisPort,
    _redisPassword,
    _memcachedHost,
    _memcachedPort,
    _sessionGcMaxlifetime,
    _sessionCookieLifetime,
    _pmMaxChildren,
    _pmStartServers,
    _pmMinSpareServers,
    _pmMaxSpareServers,
  ];

  @override
  void initState() {
    super.initState();
    _baseline = _snapshot();
    for (final controller in _controllers) {
      controller.addListener(_syncDirty);
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller
        ..removeListener(_syncDirty)
        ..dispose();
    }
    super.dispose();
  }

  /// 当前表单的可比较快照。
  String _snapshot() => _collect().toJson().toString();

  /// 重新计算脏标记并同步给页面（只在翻转时通知，避免无谓重建）。
  void _syncDirty() {
    final dirty = _snapshot() != _baseline;
    if (dirty == _localDirty) return;
    setState(() => _localDirty = dirty);
    widget.dirty.value = dirty;
  }

  /// 下拉框等非文本控件改值后统一走这里，保证脏标记同步。
  void _update(VoidCallback change) {
    setState(change);
    _syncDirty();
  }

  static String _normalizeOnOff(String raw) {
    final value = raw.trim();
    if (value.toLowerCase() == 'on' || value == '1') return 'On';
    if (value.toLowerCase() == 'off' || value == '0') return 'Off';
    return '';
  }

  String get _composedSavePath {
    switch (_sessionHandler) {
      case 'redis':
        return _RedisSavePath(
          host: _redisHost.text.trim().isEmpty
              ? '127.0.0.1'
              : _redisHost.text.trim(),
          port:
              _redisPort.text.trim().isEmpty ? '6379' : _redisPort.text.trim(),
          password: _redisPassword.text,
        ).compose();
      case 'memcached':
        return _MemcachedSavePath(
          host: _memcachedHost.text.trim().isEmpty
              ? '127.0.0.1'
              : _memcachedHost.text.trim(),
          port: _memcachedPort.text.trim().isEmpty
              ? '11211'
              : _memcachedPort.text.trim(),
        ).compose();
      default:
        return _sessionSavePath.text.trim();
    }
  }

  PhpConfigTune _collect() => widget.initial.copyWith(
        shortOpenTag: _shortOpenTag,
        dateTimezone: _dateTimezone.text.trim(),
        displayErrors: _displayErrors,
        errorReporting: _errorReporting.text.trim(),
        disableFunctions: _disableFunctions.text.trim(),
        uploadMaxFilesize:
            PhpSizeValue(_uploadMaxFilesize.text.trim(), _uploadUnit).raw,
        postMaxSize: PhpSizeValue(_postMaxSize.text.trim(), _postUnit).raw,
        maxFileUploads: _maxFileUploads.text.trim(),
        memoryLimit: PhpSizeValue(_memoryLimit.text.trim(), _memoryUnit).raw,
        maxExecutionTime: _maxExecutionTime.text.trim(),
        maxInputTime: _maxInputTime.text.trim(),
        maxInputVars: _maxInputVars.text.trim(),
        sessionSaveHandler: _sessionHandler,
        sessionSavePath: _composedSavePath,
        sessionGcMaxlifetime: _sessionGcMaxlifetime.text.trim(),
        sessionCookieLifetime: _sessionCookieLifetime.text.trim(),
        pm: _pm,
        pmMaxChildren: _pmMaxChildren.text.trim(),
        pmStartServers: _pmStartServers.text.trim(),
        pmMinSpareServers: _pmMinSpareServers.text.trim(),
        pmMaxSpareServers: _pmMaxSpareServers.text.trim(),
      );

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    // 先取快照：保存过程中用户可能继续编辑，成功后只能把「已提交的内容」
    // 当作新基准，否则会把在途修改误判为已保存。
    final payload = _collect();
    try {
      await ref
          .read(environmentRepoProvider)
          .updatePhpConfigTune(widget.version, payload);
      if (!mounted) return;
      _baseline = payload.toJson().toString();
      _syncDirty();
      ref.invalidate(phpConfigTuneProvider(widget.version));
      ref.invalidate(phpIniProvider(widget.version));
      ref.invalidate(phpFpmConfigProvider(widget.version));
      showSuccessSnack(context, '配置已保存，需重启 PHP-FPM 后生效');
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _cleanSession() async {
    if (_cleaning) return;
    final ok = await showConfirmDialog(
      context,
      title: '清理 Session 文件？',
      content: '将删除 session.save_path 下所有 sess_* 文件，'
          '所有已登录用户的会话都会失效（仅 save_handler 为 files 时可用）。',
      confirmText: '清理',
      danger: true,
    );
    if (!ok || !mounted) return;
    setState(() => _cleaning = true);
    try {
      await ref.read(environmentRepoProvider).cleanPhpSession(widget.version);
      if (!mounted) return;
      showSuccessSnack(context, 'Session 文件已清理');
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _cleaning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(top: 8, bottom: 24),
            children: [
              const HintBanner(
                '留空的配置项会被面板注释掉（恢复 PHP 默认值）；'
                '保存后需重启对应的 php-fpm 服务才会生效。',
              ),
              _generalCard(),
              _disableFunctionsCard(),
              _uploadCard(),
              _timeoutCard(),
              _sessionCard(),
              _performanceCard(),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_localDirty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Icon(
                          Icons.edit_note_rounded,
                          size: 16,
                          color: Theme.of(context).colorScheme.tertiary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '有未保存的修改',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.tertiary,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined, size: 18),
                  label: Text(_saving ? '正在保存…' : '保存全部配置'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------ 分区

  Widget _generalCard() => SectionCard(
        title: '常规设置（php.ini）',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FormFieldRow(
              label: '短标签 short_open_tag',
              child: _onOffDropdown(
                value: _shortOpenTag,
                onChanged: (v) => _update(() => _shortOpenTag = v),
              ),
            ),
            FormFieldRow(
              label: '时区 date.timezone',
              helper: '如 Asia/Shanghai',
              child: _textField(_dateTimezone, hint: 'Asia/Shanghai'),
            ),
            FormFieldRow(
              label: '显示错误 display_errors',
              helper: '生产环境建议 Off',
              child: _onOffDropdown(
                value: _displayErrors,
                onChanged: (v) => _update(() => _displayErrors = v),
              ),
            ),
            FormFieldRow(
              label: '错误级别 error_reporting',
              helper: '如 E_ALL & ~E_DEPRECATED & ~E_STRICT',
              child: _textField(_errorReporting, hint: 'E_ALL'),
            ),
          ],
        ),
      );

  Widget _disableFunctionsCard() => SectionCard(
        title: '禁用函数（php.ini）',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '以英文逗号分隔。常见危险函数：exec、shell_exec、system、'
              'passthru、proc_open、popen 等。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _disableFunctions,
              maxLines: 6,
              minLines: 3,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                hintText: 'exec,shell_exec,system,passthru',
              ),
            ),
          ],
        ),
      );

  Widget _uploadCard() => SectionCard(
        title: '上传与内存限制（php.ini）',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FormFieldRow(
              label: '最大上传文件 upload_max_filesize',
              child: _sizeField(
                controller: _uploadMaxFilesize,
                unit: _uploadUnit,
                onUnitChanged: (v) => _update(() => _uploadUnit = v),
                hint: '50',
              ),
            ),
            FormFieldRow(
              label: '最大 POST 大小 post_max_size',
              helper: '应不小于 upload_max_filesize',
              child: _sizeField(
                controller: _postMaxSize,
                unit: _postUnit,
                onUnitChanged: (v) => _update(() => _postUnit = v),
                hint: '50',
              ),
            ),
            FormFieldRow(
              label: '最大上传文件数 max_file_uploads',
              child: _numberField(_maxFileUploads, hint: '20'),
            ),
            FormFieldRow(
              label: '内存限制 memory_limit',
              helper: '单位选「字节」并填 -1 表示不限制',
              child: _sizeField(
                controller: _memoryLimit,
                unit: _memoryUnit,
                onUnitChanged: (v) => _update(() => _memoryUnit = v),
                hint: '256',
                allowNegative: true,
              ),
            ),
          ],
        ),
      );

  Widget _timeoutCard() => SectionCard(
        title: '超时限制（php.ini）',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FormFieldRow(
              label: '脚本最大执行时间 max_execution_time',
              helper: '单位秒，-1 表示不限制',
              child: _numberField(_maxExecutionTime,
                  hint: '30', allowNegative: true),
            ),
            FormFieldRow(
              label: '输入解析最大时间 max_input_time',
              helper: '单位秒，-1 表示不限制',
              child:
                  _numberField(_maxInputTime, hint: '60', allowNegative: true),
            ),
            FormFieldRow(
              label: '最大输入变量数 max_input_vars',
              child: _numberField(_maxInputVars, hint: '1000'),
            ),
          ],
        ),
      );

  Widget _sessionCard() => SectionCard(
        title: 'Session（php.ini）',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FormFieldRow(
              label: '保存方式 session.save_handler',
              helper: '使用 redis / memcached 需先安装对应扩展并确保服务可用',
              child: DropdownButtonFormField<String>(
                initialValue: _sessionHandler,
                isDense: true,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final handler in _sessionHandlers)
                    DropdownMenuItem(value: handler, child: Text(handler)),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  _update(() => _sessionHandler = value);
                },
              ),
            ),
            if (_sessionHandler == 'files')
              FormFieldRow(
                label: '保存路径 session.save_path',
                child: _textField(_sessionSavePath, hint: '/tmp'),
              ),
            if (_sessionHandler == 'redis') ...[
              FormFieldRow(
                label: 'Redis 主机',
                child: _textField(_redisHost, hint: '127.0.0.1'),
              ),
              FormFieldRow(
                label: 'Redis 端口',
                child: _numberField(_redisPort, hint: '6379'),
              ),
              FormFieldRow(
                label: 'Redis 密码',
                helper: '无密码留空',
                child: _textField(_redisPassword, obscure: true),
              ),
            ],
            if (_sessionHandler == 'memcached') ...[
              FormFieldRow(
                label: 'Memcached 主机',
                child: _textField(_memcachedHost, hint: '127.0.0.1'),
              ),
              FormFieldRow(
                label: 'Memcached 端口',
                child: _numberField(_memcachedPort, hint: '11211'),
              ),
            ],
            FormFieldRow(
              label: '回收时间 session.gc_maxlifetime',
              helper: '单位秒',
              child: _numberField(_sessionGcMaxlifetime, hint: '1440'),
            ),
            FormFieldRow(
              label: 'Cookie 有效期 session.cookie_lifetime',
              helper: '单位秒，0 表示浏览器关闭即失效',
              child: _numberField(_sessionCookieLifetime, hint: '0'),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _cleaning ? null : _cleanSession,
                icon: _cleaning
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cleaning_services_outlined, size: 18),
                label: const Text('清理 Session 文件'),
              ),
            ),
          ],
        ),
      );

  Widget _performanceCard() => SectionCard(
        title: '进程管理（php-fpm.conf）',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FormFieldRow(
              label: '进程管理方式 pm',
              helper: 'dynamic 动态、static 固定、ondemand 按需',
              child: DropdownButtonFormField<String>(
                initialValue: _pm,
                isDense: true,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final mode in _pmModes)
                    DropdownMenuItem(value: mode, child: Text(mode)),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  _update(() => _pm = value);
                },
              ),
            ),
            FormFieldRow(
              label: '最大子进程数 pm.max_children',
              child: _numberField(_pmMaxChildren, hint: '30'),
            ),
            if (_pm == 'dynamic') ...[
              FormFieldRow(
                label: '启动进程数 pm.start_servers',
                child: _numberField(_pmStartServers, hint: '5'),
              ),
              FormFieldRow(
                label: '最少空闲进程 pm.min_spare_servers',
                child: _numberField(_pmMinSpareServers, hint: '3'),
              ),
              FormFieldRow(
                label: '最多空闲进程 pm.max_spare_servers',
                child: _numberField(_pmMaxSpareServers, hint: '10'),
              ),
            ],
          ],
        ),
      );

  // ------------------------------------------------------------------ 控件

  Widget _onOffDropdown({
    required String value,
    required ValueChanged<String> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isDense: true,
      decoration: const InputDecoration(
        isDense: true,
        border: OutlineInputBorder(),
      ),
      items: const [
        DropdownMenuItem(value: '', child: Text('不设置')),
        DropdownMenuItem(value: 'On', child: Text('On')),
        DropdownMenuItem(value: 'Off', child: Text('Off')),
      ],
      onChanged: (v) => onChanged(v ?? ''),
    );
  }

  Widget _textField(
    TextEditingController controller, {
    String? hint,
    bool obscure = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _numberField(
    TextEditingController controller, {
    String? hint,
    bool allowNegative = false,
  }) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.numberWithOptions(signed: allowNegative),
      inputFormatters: [
        FilteringTextInputFormatter.allow(
          allowNegative ? RegExp(r'^-?\d*') : RegExp(r'\d*'),
        ),
      ],
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _sizeField({
    required TextEditingController controller,
    required String unit,
    required ValueChanged<String> onUnitChanged,
    String? hint,
    bool allowNegative = false,
  }) {
    return Row(
      children: [
        Expanded(
          child: _numberField(
            controller,
            hint: hint,
            allowNegative: allowNegative,
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 96,
          child: DropdownButtonFormField<String>(
            initialValue: unit,
            isDense: true,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
            ),
            items: [
              for (final item in _sizeUnits)
                DropdownMenuItem(
                  value: item,
                  child: Text(
                    _sizeUnitLabel(item),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (value) {
              if (value == null) return;
              onUnitChanged(value);
            },
          ),
        ),
      ],
    );
  }
}

/// Redis 形式的 `session.save_path`：`tcp://host:port?auth=password`。
class _RedisSavePath {
  const _RedisSavePath({
    required this.host,
    required this.port,
    required this.password,
  });

  factory _RedisSavePath.parse(String raw) {
    final value = raw.trim();
    if (value.isEmpty) {
      return const _RedisSavePath(
        host: '127.0.0.1',
        port: '6379',
        password: '',
      );
    }
    final uri = Uri.tryParse(value);
    if (uri == null || uri.host.isEmpty) {
      return const _RedisSavePath(
        host: '127.0.0.1',
        port: '6379',
        password: '',
      );
    }
    return _RedisSavePath(
      host: uri.host,
      port: uri.hasPort ? '${uri.port}' : '6379',
      password: uri.queryParameters['auth'] ?? '',
    );
  }

  final String host;
  final String port;
  final String password;

  String compose() => password.isEmpty
      ? 'tcp://$host:$port'
      : 'tcp://$host:$port?auth=$password';
}

/// Memcached 形式的 `session.save_path`：`host:port`。
class _MemcachedSavePath {
  const _MemcachedSavePath({required this.host, required this.port});

  factory _MemcachedSavePath.parse(String raw) {
    final parts = raw.trim().split(':');
    if (parts.length < 2 || parts.first.isEmpty) {
      return const _MemcachedSavePath(host: '127.0.0.1', port: '11211');
    }
    return _MemcachedSavePath(host: parts[0], port: parts[1]);
  }

  final String host;
  final String port;

  String compose() => '$host:$port';
}
