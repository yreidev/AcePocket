part of 'project_form_page.dart';

// ---------------------------------------------------------------------------
// 新建
// ---------------------------------------------------------------------------

class _CreateForm extends ConsumerStatefulWidget {
  const _CreateForm();

  @override
  ConsumerState<_CreateForm> createState() => _CreateFormState();
}

class _CreateFormState extends ConsumerState<_CreateForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _rootDirController = TextEditingController();
  final _workingDirController = TextEditingController();
  final _execStartController = TextEditingController();
  final _userController = TextEditingController(text: 'www');

  static const String _kDefaultUser = 'www';
  static const String _kDefaultType = 'general';
  static const String _kDefaultRestart = 'on-failure';

  String _type = _kDefaultType;
  String _restart = _kDefaultRestart;
  bool _submitting = false;

  /// 已创建成功（离开页面无需再确认）。
  bool _created = false;

  /// 表单是否被改动过（供返回拦截使用）。
  bool _dirty = false;

  late final List<TextEditingController> _controllers = [
    _nameController,
    _descriptionController,
    _rootDirController,
    _workingDirController,
    _execStartController,
    _userController,
  ];

  @override
  void initState() {
    super.initState();
    for (final controller in _controllers) {
      controller.addListener(_onFormChanged);
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller
        ..removeListener(_onFormChanged)
        ..dispose();
    }
    super.dispose();
  }

  /// 重算「是否有未保存的草稿」，仅在结果变化时 setState。
  void _onFormChanged() {
    final dirty =
        !_created &&
        (_nameController.text.isNotEmpty ||
            _descriptionController.text.isNotEmpty ||
            _rootDirController.text.isNotEmpty ||
            _workingDirController.text.isNotEmpty ||
            _execStartController.text.isNotEmpty ||
            _userController.text != _kDefaultUser ||
            _type != _kDefaultType ||
            _restart != _kDefaultRestart);
    if (dirty != _dirty && mounted) setState(() => _dirty = dirty);
  }

  Future<void> _submit() async {
    if (_submitting) return;
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) {
      showErrorSnack(context, _kFormInvalidHint);
      return;
    }
    final name = _nameController.text.trim();

    setState(() => _submitting = true);
    try {
      final project = await ref
          .read(projectRepoProvider)
          .create(
            ProjectCreatePayload(
              name: name,
              type: _type,
              description: _descriptionController.text.trim(),
              rootDir: _rootDirController.text.trim(),
              workingDir: _workingDirController.text.trim(),
              execStart: _execStartController.text.trim(),
              user: _userController.text.trim(),
              restart: _restart,
            ),
          );
      if (!mounted) return;
      // 创建成功后不再拦截返回。
      _created = true;
      _dirty = false;
      showSuccessSnack(context, '已创建项目「$name」');
      // 创建后直接进入详情，方便继续补全 systemd 配置。
      context.pushReplacement('/projects/${project.id}');
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 有草稿时拦截系统返回手势与返回键，避免误触丢失已填写的内容。
    return UnsavedChangesGuard(
      hasUnsavedChanges: _dirty,
      message: '新建项目的内容尚未提交，返回会丢失已填写的内容，确定放弃吗？',
      child: _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('新建项目')),
      bottomNavigationBar: _SubmitBar(
        submitting: _submitting,
        label: '创建项目',
        onSubmit: _submit,
      ),
      body: Form(
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
                    enabled: !_submitting,
                    autocorrect: false,
                    enableSuggestions: false,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    validator: _validateProjectName,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'[a-zA-Z0-9_-]'),
                      ),
                    ],
                    decoration: const InputDecoration(
                      labelText: '项目名称',
                      hintText: '仅字母、数字、下划线与短横线，同时作为服务名',
                      errorMaxLines: 2,
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: _type,
                    decoration: const InputDecoration(
                      labelText: '项目类型',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      for (final item in kProjectTypeOptions)
                        DropdownMenuItem(value: item.$1, child: Text(item.$2)),
                    ],
                    onChanged: _submitting
                        ? null
                        : (value) {
                            if (value == null) return;
                            setState(() => _type = value);
                            _onFormChanged();
                          },
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _descriptionController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: '项目描述',
                      hintText: '写入 systemd 的 Description，可留空',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ],
              ),
            ),
            SectionCard(
              title: '目录与运行',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _rootDirController,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      labelText: '项目目录',
                      hintText: '留空时由面板取「项目默认目录 / 项目名」',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _workingDirController,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      labelText: '运行目录',
                      hintText: '留空则与项目目录相同',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _execStartController,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      labelText: '启动命令',
                      hintText: '如 /usr/bin/node /www/app/main.js',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _userController,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      labelText: '运行用户',
                      hintText: '留空则以 root 运行',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: _restart,
                    decoration: const InputDecoration(
                      labelText: '重启策略',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      for (final item in kProjectRestartOptions)
                        DropdownMenuItem(value: item.$1, child: Text(item.$2)),
                    ],
                    onChanged: _submitting
                        ? null
                        : (value) {
                            if (value == null) return;
                            setState(() => _restart = value);
                            _onFormChanged();
                          },
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Text(
                '创建后可在编辑页配置环境变量、日志输出、依赖顺序、资源限制与安全加固。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 编辑
// ---------------------------------------------------------------------------

class _EditForm extends ConsumerStatefulWidget {
  const _EditForm({required this.project});

  final ProjectDetail project;

  @override
  ConsumerState<_EditForm> createState() => _EditFormState();
}

class _EditFormState extends ConsumerState<_EditForm> {
  late final TextEditingController _nameController = TextEditingController(
    text: widget.project.name,
  );
  late final TextEditingController _descriptionController =
      TextEditingController(text: widget.project.description);
  late final TextEditingController _rootDirController = TextEditingController(
    text: widget.project.rootDir,
  );
  late final TextEditingController _workingDirController =
      TextEditingController(text: widget.project.workingDir);
  late final TextEditingController _execStartPreController =
      TextEditingController(text: widget.project.execStartPre);
  late final TextEditingController _execStartController = TextEditingController(
    text: widget.project.execStart,
  );
  late final TextEditingController _execStartPostController =
      TextEditingController(text: widget.project.execStartPost);
  late final TextEditingController _execStopController = TextEditingController(
    text: widget.project.execStop,
  );
  late final TextEditingController _execReloadController =
      TextEditingController(text: widget.project.execReload);
  late final TextEditingController _userController = TextEditingController(
    text: widget.project.user,
  );
  late final TextEditingController _restartSecController =
      TextEditingController(text: widget.project.restartSec);
  late final TextEditingController _restartMaxController =
      TextEditingController(text: '${widget.project.restartMax}');
  late final TextEditingController _timeoutStartController =
      TextEditingController(text: '${widget.project.timeoutStartSec}');
  late final TextEditingController _timeoutStopController =
      TextEditingController(text: '${widget.project.timeoutStopSec}');

  /// 内存限制初始文本（MB）；与当前输入比较即可判断是否被改动。
  late final String _initialMemoryText = widget.project.memoryLimit > 0
      ? trimDouble(widget.project.memoryLimit / (1024 * 1024))
      : '0';
  late final String _initialCpuQuotaText = widget.project.cpuQuota > 0
      ? '${trimDouble(widget.project.cpuQuota)}%'
      : '';
  late final TextEditingController _memoryLimitController =
      TextEditingController(text: _initialMemoryText);
  late final TextEditingController _cpuQuotaController = TextEditingController(
    text: _initialCpuQuotaText,
  );
  late final TextEditingController _standardOutputFileController =
      TextEditingController(
        text: _initialOutputFile(widget.project.standardOutput),
      );
  late final TextEditingController _standardErrorFileController =
      TextEditingController(
        text: _initialOutputFile(widget.project.standardError),
      );

  late String _restart = _optionOrFirst(
    kProjectRestartOptions,
    widget.project.restart,
    'on-failure',
  );
  late String _standardOutput = _initialOutputKind(
    widget.project.standardOutput,
  );
  late String _standardError = _initialOutputKind(widget.project.standardError);
  late String _protectSystem = _optionOrFirst(
    kProtectSystemOptions,
    widget.project.protectSystem,
    '',
  );

  late List<KvPair> _environments = List<KvPair>.from(
    widget.project.environments,
  );
  late List<String> _requires = List<String>.from(widget.project.requires);
  late List<String> _wants = List<String>.from(widget.project.wants);
  late List<String> _after = List<String>.from(widget.project.after);
  late List<String> _before = List<String>.from(widget.project.before);
  late List<String> _readWritePaths = List<String>.from(
    widget.project.readWritePaths,
  );
  late List<String> _readOnlyPaths = List<String>.from(
    widget.project.readOnlyPaths,
  );

  late bool _noNewPrivileges = widget.project.noNewPrivileges;
  late bool _protectTmp = widget.project.protectTmp;
  late bool _protectHome = widget.project.protectHome;

  final _formKey = GlobalKey<FormState>();

  bool _submitting = false;

  /// 已保存成功（离开页面无需再确认）。
  bool _saved = false;

  /// 表单是否被改动过（供返回拦截使用）。
  bool _dirty = false;

  late final List<TextEditingController> _controllers = [
    _nameController,
    _descriptionController,
    _rootDirController,
    _workingDirController,
    _execStartPreController,
    _execStartController,
    _execStartPostController,
    _execStopController,
    _execReloadController,
    _userController,
    _restartSecController,
    _restartMaxController,
    _timeoutStartController,
    _timeoutStopController,
    _memoryLimitController,
    _cpuQuotaController,
    _standardOutputFileController,
    _standardErrorFileController,
  ];

  @override
  void initState() {
    super.initState();
    for (final controller in _controllers) {
      controller.addListener(_onFormChanged);
    }
  }

  /// 重算「是否有未保存的修改」（与加载到的项目逐项比较），
  /// 仅在结果变化时 setState，避免每次按键都重建整页表单。
  void _onFormChanged() {
    final dirty = !_saved && _computeDirty();
    if (dirty != _dirty && mounted) setState(() => _dirty = dirty);
  }

  bool _computeDirty() {
    final p = widget.project;
    return _nameController.text != p.name ||
        _descriptionController.text != p.description ||
        _rootDirController.text != p.rootDir ||
        _workingDirController.text != p.workingDir ||
        _execStartPreController.text != p.execStartPre ||
        _execStartController.text != p.execStart ||
        _execStartPostController.text != p.execStartPost ||
        _execStopController.text != p.execStop ||
        _execReloadController.text != p.execReload ||
        _userController.text != p.user ||
        _restartSecController.text != p.restartSec ||
        _restartMaxController.text != '${p.restartMax}' ||
        _timeoutStartController.text != '${p.timeoutStartSec}' ||
        _timeoutStopController.text != '${p.timeoutStopSec}' ||
        _memoryLimitController.text != _initialMemoryText ||
        _cpuQuotaController.text != _initialCpuQuotaText ||
        _standardOutputFileController.text !=
            _initialOutputFile(p.standardOutput) ||
        _standardErrorFileController.text !=
            _initialOutputFile(p.standardError) ||
        _restart !=
            _optionOrFirst(kProjectRestartOptions, p.restart, 'on-failure') ||
        _standardOutput != _initialOutputKind(p.standardOutput) ||
        _standardError != _initialOutputKind(p.standardError) ||
        _protectSystem !=
            _optionOrFirst(kProtectSystemOptions, p.protectSystem, '') ||
        _noNewPrivileges != p.noNewPrivileges ||
        _protectTmp != p.protectTmp ||
        _protectHome != p.protectHome ||
        !listEquals(_environments, p.environments) ||
        !listEquals(_requires, p.requires) ||
        !listEquals(_wants, p.wants) ||
        !listEquals(_after, p.after) ||
        !listEquals(_before, p.before) ||
        !listEquals(_readWritePaths, p.readWritePaths) ||
        !listEquals(_readOnlyPaths, p.readOnlyPaths);
  }

  /// 面板返回的 `standard_output` 形如 `journal` 或 `append:/var/log/app.log`，
  /// 这里拆成「类型」与「文件路径」两个输入。
  static String _initialOutputKind(String raw) {
    if (raw.isEmpty) return 'journal';
    for (final item in kProjectOutputOptions) {
      if (item.$1 == raw) return raw;
    }
    if (raw.startsWith('append:')) return 'append:/var/log/';
    if (raw.startsWith('truncate:')) return 'truncate:/var/log/';
    return 'journal';
  }

  static String _initialOutputFile(String raw) {
    if (raw.startsWith('append:')) return raw.substring('append:'.length);
    if (raw.startsWith('truncate:')) return raw.substring('truncate:'.length);
    return '';
  }

  static String _optionOrFirst(
    List<(String, String)> options,
    String value,
    String fallback,
  ) {
    for (final item in options) {
      if (item.$1 == value) return value;
    }
    return fallback;
  }

  bool _isFileOutput(String kind) =>
      kind.startsWith('append:') || kind.startsWith('truncate:');

  /// 把「类型 + 文件路径」拼回面板需要的 `standard_output` 值。
  String _composeOutput(String kind, TextEditingController fileController) {
    if (!_isFileOutput(kind)) return kind;
    final prefix = kind.startsWith('append:') ? 'append:' : 'truncate:';
    final path = fileController.text.trim();
    if (path.isEmpty) return 'journal';
    return '$prefix$path';
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller
        ..removeListener(_onFormChanged)
        ..dispose();
    }
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // 校验（错误就地展示在对应输入框下方，而不是一条 SnackBar）
  // ---------------------------------------------------------------------

  String? _validateRootDir(String? value) {
    if ((value ?? '').trim().isEmpty) return '请填写项目目录';
    return null;
  }

  /// 内存限制（MB）。原先非数字输入会被静默当作 0（= 取消限制），
  /// 这里直接拒绝，避免用户以为限制生效。
  String? _validateMemoryLimit(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return null;
    final mb = double.tryParse(text);
    if (mb == null) return '请填写数字，0 表示不限制';
    if (mb < 0) return '内存限制不能为负数';
    return null;
  }

  String? _validateCpuQuota(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return null;
    if (!_kCpuQuotaPattern.hasMatch(text)) {
      return '应为百分比，如 50%、200%';
    }
    return null;
  }

  /// 日志文件路径：选了「文件」输出就必须填绝对路径，
  /// 原先留空会被静默改回 journal。
  String? _validateOutputFile(String kind, String? value) {
    if (!_isFileOutput(kind)) return null;
    final path = (value ?? '').trim();
    if (path.isEmpty) return '选择文件输出时必须填写文件路径';
    if (!path.startsWith('/')) return '请填写绝对路径，如 /var/log/app.log';
    return null;
  }

  Future<void> _submit() async {
    if (_submitting) return;
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) {
      showErrorSnack(context, _kFormInvalidHint);
      return;
    }

    final name = _nameController.text.trim();
    final rootDir = _rootDirController.text.trim();
    final memoryMb = double.tryParse(_memoryLimitController.text.trim()) ?? 0;
    final cpuQuota = _cpuQuotaController.text.trim();

    final payload = ProjectUpdatePayload(
      id: widget.project.id,
      name: name,
      description: _descriptionController.text.trim(),
      rootDir: rootDir,
      workingDir: _workingDirController.text.trim(),
      execStartPre: _execStartPreController.text.trim(),
      execStart: _execStartController.text.trim(),
      execStartPost: _execStartPostController.text.trim(),
      execStop: _execStopController.text.trim(),
      execReload: _execReloadController.text.trim(),
      user: _userController.text.trim(),
      restart: _restart,
      restartSec: _restartSecController.text.trim(),
      restartMax: int.tryParse(_restartMaxController.text.trim()) ?? 0,
      timeoutStartSec: int.tryParse(_timeoutStartController.text.trim()) ?? 0,
      timeoutStopSec: int.tryParse(_timeoutStopController.text.trim()) ?? 0,
      environments: _environments,
      standardOutput: _composeOutput(
        _standardOutput,
        _standardOutputFileController,
      ),
      standardError: _composeOutput(
        _standardError,
        _standardErrorFileController,
      ),
      requires: _requires,
      wants: _wants,
      after: _after,
      before: _before,
      // 面板以字节写入 systemd 的 MemoryLimit=，界面按 MB 输入。
      memoryLimit: memoryMb * 1024 * 1024,
      cpuQuota: cpuQuota,
      noNewPrivileges: _noNewPrivileges,
      protectTmp: _protectTmp,
      protectHome: _protectHome,
      protectSystem: _protectSystem,
      readWritePaths: _readWritePaths,
      readOnlyPaths: _readOnlyPaths,
    );

    setState(() => _submitting = true);
    try {
      await ref.read(projectRepoProvider).update(payload);
      ref.invalidate(projectDetailProvider(widget.project.id));
      if (!mounted) return;
      // 保存成功后不再拦截返回。
      _saved = true;
      _dirty = false;
      showSuccessSnack(context, '已保存，重启项目后生效');
      context.pop(true);
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 有未保存修改时拦截系统返回手势与返回键（整页表单，误触代价高）。
    return UnsavedChangesGuard(
      hasUnsavedChanges: _dirty,
      message: '项目配置有未保存的修改，返回会丢失这些修改，确定放弃吗？',
      child: _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '编辑项目 · ${widget.project.name}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      bottomNavigationBar: _SubmitBar(
        submitting: _submitting,
        label: '保存',
        onSubmit: _submit,
      ),
      body: Form(
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
                    enabled: !_submitting,
                    autocorrect: false,
                    enableSuggestions: false,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    validator: _validateProjectName,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'[a-zA-Z0-9_-]'),
                      ),
                    ],
                    decoration: const InputDecoration(
                      labelText: '项目名称',
                      helperText: '改名会同时重命名 systemd 服务文件',
                      helperMaxLines: 2,
                      errorMaxLines: 2,
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _descriptionController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: '项目描述',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _rootDirController,
                    enabled: !_submitting,
                    autocorrect: false,
                    enableSuggestions: false,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    validator: _validateRootDir,
                    decoration: const InputDecoration(
                      labelText: '项目目录',
                      errorMaxLines: 2,
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _workingDirController,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      labelText: '运行目录',
                      hintText: '留空则与项目目录相同',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _userController,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      labelText: '运行用户',
                      hintText: '留空则以 root 运行',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ],
              ),
            ),
            SectionCard(
              title: '启动命令',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _CommandField(
                    controller: _execStartPreController,
                    label: '启动前命令 ExecStartPre',
                  ),
                  const SizedBox(height: 14),
                  _CommandField(
                    controller: _execStartController,
                    label: '启动命令 ExecStart',
                  ),
                  const SizedBox(height: 14),
                  _CommandField(
                    controller: _execStartPostController,
                    label: '启动后命令 ExecStartPost',
                  ),
                  const SizedBox(height: 14),
                  _CommandField(
                    controller: _execStopController,
                    label: '停止命令 ExecStop',
                  ),
                  const SizedBox(height: 14),
                  _CommandField(
                    controller: _execReloadController,
                    label: '重载命令 ExecReload',
                  ),
                ],
              ),
            ),
            SectionCard(
              title: '重启策略',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _restart,
                    decoration: const InputDecoration(
                      labelText: '重启策略 Restart',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      for (final item in kProjectRestartOptions)
                        DropdownMenuItem(value: item.$1, child: Text(item.$2)),
                    ],
                    onChanged: _submitting
                        ? null
                        : (value) {
                            if (value == null) return;
                            setState(() => _restart = value);
                            _onFormChanged();
                          },
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _restartSecController,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: '重启间隔 RestartSec',
                      hintText: '如 5s、1min',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _IntField(
                    controller: _restartMaxController,
                    label: '最大重启次数 StartLimitBurst',
                    helper: '0 表示不限制',
                  ),
                  const SizedBox(height: 14),
                  _IntField(
                    controller: _timeoutStartController,
                    label: '启动超时（秒）',
                    helper: '0 表示使用 systemd 默认值',
                  ),
                  const SizedBox(height: 14),
                  _IntField(
                    controller: _timeoutStopController,
                    label: '停止超时（秒）',
                    helper: '0 表示使用 systemd 默认值',
                  ),
                ],
              ),
            ),
            SectionCard(
              child: KvListField(
                label: '环境变量',
                initialValues: _environments,
                helper: '写入 systemd 的 Environment=，值可包含空格',
                keyHint: 'KEY',
                valueHint: 'VALUE',
                onChanged: (value) {
                  _environments = value;
                  _onFormChanged();
                },
              ),
            ),
            SectionCard(
              title: '日志输出',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _standardOutput,
                    decoration: const InputDecoration(
                      labelText: '标准输出 StandardOutput',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      for (final item in kProjectOutputOptions)
                        DropdownMenuItem(value: item.$1, child: Text(item.$2)),
                    ],
                    onChanged: _submitting
                        ? null
                        : (value) {
                            if (value == null) return;
                            setState(() => _standardOutput = value);
                            _onFormChanged();
                          },
                  ),
                  if (_isFileOutput(_standardOutput)) ...[
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _standardOutputFileController,
                      enabled: !_submitting,
                      autocorrect: false,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      validator: (value) =>
                          _validateOutputFile(_standardOutput, value),
                      decoration: const InputDecoration(
                        labelText: '标准输出文件路径',
                        hintText: '/var/log/app.log',
                        errorMaxLines: 2,
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: _standardError,
                    decoration: const InputDecoration(
                      labelText: '标准错误 StandardError',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      for (final item in kProjectOutputOptions)
                        DropdownMenuItem(value: item.$1, child: Text(item.$2)),
                    ],
                    onChanged: _submitting
                        ? null
                        : (value) {
                            if (value == null) return;
                            setState(() => _standardError = value);
                            _onFormChanged();
                          },
                  ),
                  if (_isFileOutput(_standardError)) ...[
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _standardErrorFileController,
                      enabled: !_submitting,
                      autocorrect: false,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      validator: (value) =>
                          _validateOutputFile(_standardError, value),
                      decoration: const InputDecoration(
                        labelText: '标准错误文件路径',
                        hintText: '/var/log/app-error.log',
                        errorMaxLines: 2,
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            SectionCard(
              title: '依赖与启动顺序',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  StringListField(
                    label: '强依赖 Requires',
                    initialValues: _requires,
                    hint: 'mysqld.service',
                    onChanged: (value) {
                      _requires = value;
                      _onFormChanged();
                    },
                  ),
                  const SizedBox(height: 6),
                  StringListField(
                    label: '弱依赖 Wants',
                    initialValues: _wants,
                    hint: 'redis.service',
                    onChanged: (value) {
                      _wants = value;
                      _onFormChanged();
                    },
                  ),
                  const SizedBox(height: 6),
                  StringListField(
                    label: '在其之后启动 After',
                    initialValues: _after,
                    hint: 'network.target',
                    helper: '留空时面板默认写入 network.target',
                    onChanged: (value) {
                      _after = value;
                      _onFormChanged();
                    },
                  ),
                  const SizedBox(height: 6),
                  StringListField(
                    label: '在其之前启动 Before',
                    initialValues: _before,
                    hint: 'nginx.service',
                    onChanged: (value) {
                      _before = value;
                      _onFormChanged();
                    },
                  ),
                ],
              ),
            ),
            SectionCard(
              title: '资源限制',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _memoryLimitController,
                    enabled: !_submitting,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    validator: _validateMemoryLimit,
                    decoration: const InputDecoration(
                      labelText: '内存限制（MB）',
                      helperText: '0 表示不限制',
                      errorMaxLines: 2,
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _cpuQuotaController,
                    enabled: !_submitting,
                    autocorrect: false,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    validator: _validateCpuQuota,
                    decoration: const InputDecoration(
                      labelText: 'CPU 限制 CPUQuota',
                      hintText: '如 50%、200%',
                      helperText: '100% = 1 个 CPU 核心，留空表示不限制',
                      helperMaxLines: 2,
                      errorMaxLines: 2,
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ],
              ),
            ),
            SectionCard(
              title: '安全加固',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('禁止提权'),
                    subtitle: const Text('NoNewPrivileges=true'),
                    value: _noNewPrivileges,
                    onChanged: (value) {
                      setState(() => _noNewPrivileges = value);
                      _onFormChanged();
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('保护临时目录'),
                    subtitle: const Text('ProtectTmp=true'),
                    value: _protectTmp,
                    onChanged: (value) {
                      setState(() => _protectTmp = value);
                      _onFormChanged();
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('保护主目录'),
                    subtitle: const Text('ProtectHome=true'),
                    value: _protectHome,
                    onChanged: (value) {
                      setState(() => _protectHome = value);
                      _onFormChanged();
                    },
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _protectSystem,
                    decoration: const InputDecoration(
                      labelText: '保护系统 ProtectSystem',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      for (final item in kProtectSystemOptions)
                        DropdownMenuItem(value: item.$1, child: Text(item.$2)),
                    ],
                    onChanged: _submitting
                        ? null
                        : (value) {
                            if (value == null) return;
                            setState(() => _protectSystem = value);
                            _onFormChanged();
                          },
                  ),
                  const SizedBox(height: 8),
                  StringListField(
                    label: '可读写路径 ReadWritePaths',
                    initialValues: _readWritePaths,
                    hint: '/www/app/storage',
                    onChanged: (value) {
                      _readWritePaths = value;
                      _onFormChanged();
                    },
                  ),
                  const SizedBox(height: 6),
                  StringListField(
                    label: '只读路径 ReadOnlyPaths',
                    initialValues: _readOnlyPaths,
                    hint: '/etc',
                    onChanged: (value) {
                      _readOnlyPaths = value;
                      _onFormChanged();
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 公共小组件
// ---------------------------------------------------------------------------

class _CommandField extends StatelessWidget {
  const _CommandField({required this.controller, required this.label});

  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autocorrect: false,
      enableSuggestions: false,
      maxLines: 2,
      minLines: 1,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }
}

class _IntField extends StatelessWidget {
  const _IntField({required this.controller, required this.label, this.helper});

  final TextEditingController controller;
  final String label;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }
}

class _SubmitBar extends StatelessWidget {
  const _SubmitBar({
    required this.submitting,
    required this.label,
    required this.onSubmit,
  });

  final bool submitting;
  final String label;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton(
          onPressed: submitting ? null : onSubmit,
          child: submitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              : Text(label),
        ),
      ),
    );
  }
}
