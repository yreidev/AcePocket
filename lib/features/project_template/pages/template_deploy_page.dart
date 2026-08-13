import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/widgets/app_snack.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_view.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/unsaved_guard.dart';
import '../models/kv_pair.dart';
import '../models/template.dart';
import '../providers/template_providers.dart';
import '../widgets/kv_list_field.dart';

/// 编排名称合法字符，与 `request.TemplateCreate` 的
/// `regex:"^[a-zA-Z0-9_-]+$"` 一致。
final RegExp _kComposeNamePattern = RegExp(r'^[a-zA-Z0-9_-]+$');

/// 环境变量名的合法字符（写入 `.env` 的 key，shell 变量名规则）。
final RegExp _kEnvNamePattern = RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$');

/// 模板部署页 `/templates/:slug/deploy`。
///
/// 对应面板 `POST /api/template`：用模板生成一个 docker compose 编排目录，
/// 可选自动放行 compose 中声明的端口；创建完成后可立即启动编排
/// （`POST /api/container/compose/{name}/up`）。
class TemplateDeployPage extends ConsumerWidget {
  const TemplateDeployPage({super.key, required this.slug});

  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(templateDetailProvider(slug));
    return detailAsync.when(
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('部署模板')),
        body: const LoadingView(message: '正在加载模板…'),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(title: const Text('部署模板')),
        body: ErrorView(
          error: error,
          onRetry: () => ref.invalidate(templateDetailProvider(slug)),
        ),
      ),
      data: (template) => _DeployForm(template: template),
    );
  }
}

class _DeployForm extends ConsumerStatefulWidget {
  const _DeployForm({required this.template});

  final AppTemplate template;

  @override
  ConsumerState<_DeployForm> createState() => _DeployFormState();
}

class _DeployFormState extends ConsumerState<_DeployForm> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  /// 校验失败时用于滚动定位到第一个出错的输入框。
  final GlobalKey _nameFieldKey = GlobalKey();
  final GlobalKey _composeFieldKey = GlobalKey();
  final Map<String, GlobalKey> _envFieldKeys = {};

  late final String _initialName = _sanitizeName(widget.template.slug);
  late final TextEditingController _nameController =
      TextEditingController(text: _initialName);
  late final TextEditingController _composeController =
      TextEditingController(text: widget.template.compose);

  /// 模板定义的环境变量当前值（key 为变量名）。
  final Map<String, String> _envValues = {};

  /// 模板变量的初始值（用于判断是否有未提交的修改）。
  final Map<String, String> _initialEnvValues = {};

  /// 文本类环境变量的输入控制器。
  final Map<String, TextEditingController> _envControllers = {};

  /// 用户额外添加的变量（同名时覆盖模板变量）。
  List<KvPair> _extraEnvs = const <KvPair>[];

  bool _autoFirewall = false;
  bool _autoStart = true;

  /// 当前部署阶段的文案；为 null 表示未在部署中。
  String? _step;

  /// 已经部署过（此时离开页面无需再确认）。
  bool _deployed = false;

  /// 表单是否被改动过（供返回拦截使用）。
  bool _dirty = false;

  bool get _submitting => _step != null;

  @override
  void initState() {
    super.initState();
    for (final env in widget.template.environments) {
      var initial = env.defaultValue ?? '';
      if (env.type == 'select') {
        // 默认值必须落在候选项内，否则取第一个候选项。
        final options = _selectOptions(env);
        if (!options.any((e) => e.$1 == initial)) {
          initial = options.isEmpty ? '' : options.first.$1;
        }
      } else {
        // 值的变化经 onChanged 写入 _envValues 后再重算 dirty，
        // 因此这里不额外挂 controller 监听。
        _envControllers[env.name] = TextEditingController(text: initial);
      }
      _envFieldKeys[env.name] = GlobalKey();
      _envValues[env.name] = initial;
      _initialEnvValues[env.name] = initial;
    }
    _nameController.addListener(_onFormChanged);
    _composeController.addListener(_onFormChanged);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _composeController.dispose();
    for (final controller in _envControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  /// 编排名称只允许字母、数字、下划线与短横线，模板 slug 里的点号等一律转下划线。
  static String _sanitizeName(String slug) {
    final cleaned = slug.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return cleaned.isEmpty ? 'app' : cleaned;
  }

  /// select 类型的候选项（面板返回 `label -> value`）。
  List<(String, String)> _selectOptions(TemplateEnvironment env) {
    final options = <(String, String)>[];
    env.options.forEach((label, value) => options.add((value, label)));
    return options;
  }

  /// 合并模板变量与用户自定义变量，后者同名覆盖。
  List<KvPair> _finalEnvs() {
    final merged = <String, String>{};
    for (final env in widget.template.environments) {
      merged[env.name] = _envValues[env.name] ?? '';
    }
    for (final extra in _extraEnvs) {
      merged[extra.key] = extra.value;
    }
    return [
      for (final entry in merged.entries)
        KvPair(key: entry.key, value: entry.value),
    ];
  }

  /// 表单内容变化：重算「是否有未提交的修改」，变化时才 setState。
  void _onFormChanged() {
    final dirty = !_deployed &&
        (_nameController.text != _initialName ||
            _composeController.text != widget.template.compose ||
            _extraEnvs.isNotEmpty ||
            _envValues.entries.any((e) => _initialEnvValues[e.key] != e.value));
    if (dirty != _dirty && mounted) setState(() => _dirty = dirty);
  }

  // ---------------------------------------------------------------------
  // 校验（错误就地展示在对应输入框下方，而不是一条 SnackBar）
  // ---------------------------------------------------------------------

  String? _validateName(String? value) {
    final name = (value ?? '').trim();
    if (name.isEmpty) return '请填写编排名称';
    if (!_kComposeNamePattern.hasMatch(name)) {
      return '只能包含字母、数字、下划线与短横线';
    }
    return null;
  }

  String? _validateCompose(String? value) {
    if ((value ?? '').trim().isEmpty) return '编排内容不能为空';
    return null;
  }

  String? _validateEnv(TemplateEnvironment env, String? value) {
    final text = (value ?? '').trim();
    if (env.required && text.isEmpty) return '该项为必填';
    if (text.isEmpty) return null;
    switch (env.type) {
      case 'port':
        final port = int.tryParse(text);
        if (port == null || port < 1 || port > 65535) {
          return '应为 1-65535 之间的端口号';
        }
      case 'number':
        if (double.tryParse(text) == null) return '应为数字';
      case 'url':
        final uri = Uri.tryParse(text);
        if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
          return '应为完整链接，如 https://example.com';
        }
    }
    return null;
  }

  /// 自定义变量（KvListField 不在 Form 内，单独校验后用 SnackBar 提示）。
  String? _validateExtraEnvs() {
    final seen = <String>{};
    for (final extra in _extraEnvs) {
      if (!_kEnvNamePattern.hasMatch(extra.key)) {
        return '自定义变量名「${extra.key}」不合法：只能以字母或下划线开头，'
            '且仅含字母、数字与下划线';
      }
      if (!seen.add(extra.key)) {
        return '自定义变量「${extra.key}」重复，请合并为一条';
      }
    }
    return null;
  }

  /// 滚动到第一个校验失败的输入框，避免用户在长表单里找不到红色提示。
  void _scrollToFirstError() {
    final candidates = <(GlobalKey, String?)>[
      (_nameFieldKey, _validateName(_nameController.text)),
      for (final env in widget.template.environments)
        (
          _envFieldKeys[env.name]!,
          _validateEnv(env, _envValues[env.name]),
        ),
      (_composeFieldKey, _validateCompose(_composeController.text)),
    ];
    for (final (key, error) in candidates) {
      final fieldContext = key.currentContext;
      if (error != null && fieldContext != null) {
        Scrollable.ensureVisible(
          fieldContext,
          duration: const Duration(milliseconds: 250),
          alignment: 0.2,
        );
        return;
      }
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    FocusScope.of(context).unfocus();

    if (!(_formKey.currentState?.validate() ?? false)) {
      _scrollToFirstError();
      showErrorSnack(context, '请先修正标红的输入项');
      return;
    }
    final extraError = _validateExtraEnvs();
    if (extraError != null) {
      showErrorSnack(context, extraError);
      return;
    }

    final name = _nameController.text.trim();
    final ok = await showConfirmDialog(
      context,
      title: '部署模板',
      content: '将使用模板「${widget.template.name}」创建编排「$name」。'
          '${_autoFirewall ? '\n面板会自动放行编排中声明的端口。' : ''}'
          '${_autoStart ? '\n创建完成后立即启动编排（docker compose up -d）。' : ''}',
      confirmText: '开始部署',
    );
    if (!ok || !mounted) return;

    setState(() => _step = '正在创建编排…');
    try {
      final repo = ref.read(templateRepoProvider);
      final dir = await repo.createCompose(
        slug: widget.template.slug,
        name: name,
        compose: _composeController.text,
        envs: _finalEnvs(),
        autoFirewall: _autoFirewall,
      );
      var startError = '';
      if (_autoStart) {
        if (mounted) setState(() => _step = '正在启动编排…');
        try {
          await repo.composeUp(name);
        } catch (e) {
          startError = describeError(e);
        }
      }
      if (!mounted) return;
      // 部署已经发生，此后离开页面不再询问「放弃修改」。
      setState(() {
        _deployed = true;
        _dirty = false;
      });
      await _showResultDialog(name: name, dir: dir, startError: startError);
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _step = null);
    }
  }

  Future<void> _showResultDialog({
    required String name,
    required String dir,
    required String startError,
  }) async {
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(startError.isEmpty ? '部署完成' : '编排已创建，但启动失败'),
        // 编排目录与启动失败信息都可能很长，内容区可滚动，避免溢出。
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('编排名称：$name'),
              if (dir.isNotEmpty) ...[
                const SizedBox(height: 6),
                SelectableText('编排目录：$dir'),
              ],
              if (startError.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  startError,
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                const SizedBox(height: 6),
                Text(
                  '可在编排详情页查看日志后手动启动。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop('stay'),
            child: const Text('留在本页'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop('compose'),
            child: const Text('查看编排'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (action == 'compose') {
      context
          .pushReplacement('/containers/compose/${Uri.encodeComponent(name)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final template = widget.template;
    final title = template.name.isEmpty ? template.slug : template.name;

    return UnsavedChangesGuard(
      hasUnsavedChanges: _dirty,
      message: '部署配置尚未提交，返回会丢失已填写的内容，确定放弃吗？',
      child: Scaffold(
        appBar: AppBar(
          // 模板名可能很长，单行省略而不是把标题挤没。
          title:
              Text('部署 · $title', maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: FilledButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : const Icon(Icons.rocket_launch_outlined),
              label: Text(_step ?? '开始部署'),
            ),
          ),
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.only(top: 8, bottom: 24),
            children: [
              // 部署分两步（创建编排 → 启动编排），进行中给出明确的阶段提示。
              if (_submitting)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      LinearProgressIndicator(
                        borderRadius: BorderRadius.circular(4),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${_step ?? ''}部署完成前请勿离开本页',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              SectionCard(
                title: '编排设置',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      key: _nameFieldKey,
                      controller: _nameController,
                      enabled: !_submitting,
                      autocorrect: false,
                      enableSuggestions: false,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      validator: _validateName,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'[a-zA-Z0-9_-]'),
                        ),
                      ],
                      decoration: const InputDecoration(
                        labelText: '编排名称',
                        helperText: '仅字母、数字、下划线与短横线；同名编排已存在时会创建失败',
                        helperMaxLines: 2,
                        errorMaxLines: 2,
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('自动放行端口'),
                      subtitle: const Text('由面板放行编排中声明的端口'),
                      value: _autoFirewall,
                      onChanged: _submitting
                          ? null
                          : (value) => setState(() => _autoFirewall = value),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('创建后立即启动'),
                      subtitle: const Text('等价于 docker compose up -d'),
                      value: _autoStart,
                      onChanged: _submitting
                          ? null
                          : (value) => setState(() => _autoStart = value),
                    ),
                  ],
                ),
              ),
              if (template.environments.isNotEmpty)
                SectionCard(
                  title: '环境变量',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final env in template.environments)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: _buildEnvField(env),
                        ),
                    ],
                  ),
                ),
              SectionCard(
                child: KvListField(
                  label: '自定义变量',
                  helper: '追加写入编排的 .env；与模板变量同名时覆盖模板值',
                  initialValues: _extraEnvs,
                  onChanged: (value) {
                    _extraEnvs = value;
                    _onFormChanged();
                  },
                ),
              ),
              SectionCard(
                title: 'docker-compose.yml',
                trailing: TextButton.icon(
                  onPressed: _submitting
                      ? null
                      : () => setState(
                            () => _composeController.text = template.compose,
                          ),
                  icon: const Icon(Icons.restore, size: 18),
                  label: const Text('恢复默认'),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '可直接编辑，留空则无法提交。变量以 ${r'${VAR}'} 形式引用上方环境变量。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      key: _composeFieldKey,
                      controller: _composeController,
                      enabled: !_submitting,
                      autocorrect: false,
                      enableSuggestions: false,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      validator: _validateCompose,
                      minLines: 10,
                      maxLines: 30,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        height: 1.4,
                      ),
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEnvField(TemplateEnvironment env) {
    final label = env.required ? '${env.label} *' : env.label;
    final helper = env.name;

    if (env.type == 'select') {
      final options = _selectOptions(env);
      final current = _envValues[env.name] ?? '';
      return DropdownButtonFormField<String>(
        key: _envFieldKeys[env.name],
        initialValue: options.any((e) => e.$1 == current) ? current : null,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        validator: (value) => _validateEnv(env, value),
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          errorMaxLines: 2,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        items: [
          for (final option in options)
            DropdownMenuItem(value: option.$1, child: Text(option.$2)),
        ],
        onChanged: _submitting
            ? null
            : (newValue) {
                if (newValue == null) return;
                setState(() => _envValues[env.name] = newValue);
                _onFormChanged();
              },
      );
    }

    final controller = _envControllers[env.name]!;
    final isNumber = env.type == 'number' || env.type == 'port';
    return TextFormField(
      key: _envFieldKeys[env.name],
      controller: controller,
      enabled: !_submitting,
      autocorrect: false,
      enableSuggestions: false,
      obscureText: env.type == 'password',
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: (value) => _validateEnv(env, value),
      keyboardType: isNumber
          ? TextInputType.number
          : (env.type == 'url' ? TextInputType.url : TextInputType.text),
      inputFormatters: switch (env.type) {
        'port' => [FilteringTextInputFormatter.digitsOnly],
        'number' => [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
        _ => null,
      },
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        hintText: env.defaultValue,
        errorMaxLines: 2,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      onChanged: (value) {
        _envValues[env.name] = value;
        _onFormChanged();
      },
    );
  }
}
