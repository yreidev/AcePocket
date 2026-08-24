import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;

import '../../../core/api/api_exception.dart';
import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/app_snack.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_view.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/task_snack.dart';
import '../../../core/widgets/unsaved_guard.dart';
import '../models/environment_models.dart';
import '../providers/environment_providers.dart';
import '../widgets/environment_ui.dart';

/// Go / Java / Node.js / Python / .NET 的环境管理页
/// （`/environments/runtime/:type/:slug`）。
///
/// 覆盖接口：
/// - `POST /environment/{type}/{slug}/set_cli` —— 设为命令行默认版本；
/// - `GET|POST /environment/go/{slug}/proxy` —— Go 代理；
/// - `GET|POST /environment/nodejs/{slug}/registry` —— npm 镜像源；
/// - `GET|POST /environment/python/{slug}/mirror` —— pip 镜像源；
/// - `GET /environment/is_installed`、`POST /environment/{install,update,uninstall}`。
class RuntimeEnvironmentPage extends ConsumerStatefulWidget {
  const RuntimeEnvironmentPage({
    super.key,
    required this.type,
    required this.slug,
  });

  final String type;
  final String slug;

  @override
  ConsumerState<RuntimeEnvironmentPage> createState() =>
      _RuntimeEnvironmentPageState();
}

class _RuntimeEnvironmentPageState
    extends ConsumerState<RuntimeEnvironmentPage> {
  String? _busy;

  EnvironmentRef get _ref => EnvironmentRef(widget.type, widget.slug);

  bool _isBusy(String key) => _busy == key;

  /// 综合判断是否已安装。
  ///
  /// 以列表接口返回的 `installed` 为主（服务端同样由 `IsInstalled` 计算），
  /// `GET /environment/is_installed` 的探测结果作为补充，任一为真即视为已安装，
  /// 避免探测失败时误禁用操作按钮。
  bool _installed(EnvironmentDetail? env) {
    final probe = ref.watch(environmentInstalledProvider(_ref)).value;
    return env?.installed == true || probe == true;
  }

  Future<void> _run(
    String key,
    Future<void> Function() action, {
    required String successMessage,
    bool asTask = false,
    List<ProviderOrFamily> invalidate = const [],
  }) async {
    setState(() => _busy = key);
    try {
      await action();
      for (final provider in invalidate) {
        ref.invalidate(provider);
      }
      if (!mounted) return;
      if (asTask) {
        showTaskSubmittedSnack(context, successMessage);
      } else {
        showSuccessSnack(context, successMessage);
      }
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  void _refreshAll() {
    ref.invalidate(environmentDetailProvider(_ref));
    ref.invalidate(environmentInstalledProvider(_ref));
    switch (widget.type) {
      case 'go':
        ref.invalidate(goProxyProvider(widget.slug));
      case 'nodejs':
        ref.invalidate(nodejsRegistryProvider(widget.slug));
      case 'python':
        ref.invalidate(pythonMirrorProvider(widget.slug));
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(environmentDetailProvider(_ref));
    final typeLabel = environmentTypeLabel(widget.type);

    return Scaffold(
      appBar: AppBar(
        title: Text('$typeLabel ${widget.slug}'),
        actions: [
          A11yIconButton(
            tooltip: '刷新环境信息',
            icon: const Icon(Icons.refresh),
            onPressed: _refreshAll,
          ),
          _menu(detail.value),
        ],
      ),
      body: detail.when(
        loading: () => const LoadingView(message: '读取环境信息…'),
        error: (error, _) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(environmentDetailProvider(_ref)),
        ),
        data: (env) => RefreshIndicator(
          onRefresh: () async {
            _refreshAll();
            await ref.read(environmentDetailProvider(_ref).future);
          },
          // 用 SingleChildScrollView 而不是 ListView：全页只有三四张卡片，
          // 而 ListView 会把滚出视口的卡片连同 State 一起销毁——代理 / 镜像源
          // 编辑器的草稿和它内部的返回拦截都会随之丢失。
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(top: 8, bottom: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (env == null)
                  const HintBanner('面板环境列表中未找到该版本，可能是环境源数据已更新。', warning: true),
                _infoCard(env),
                _cliCard(env),
                ..._extraCards(env),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _menu(EnvironmentDetail? env) {
    return PopupMenuButton<String>(
      tooltip: '更多操作',
      onSelected: (value) => _onMenu(value, env),
      itemBuilder: (context) => [
        if (env != null && !env.installed)
          const PopupMenuItem(value: 'install', child: Text('安装此版本')),
        if (env != null && env.installed && env.hasUpdate)
          const PopupMenuItem(value: 'update', child: Text('更新到最新版本')),
        if (env != null && env.installed)
          const PopupMenuItem(value: 'uninstall', child: Text('卸载此版本')),
        const PopupMenuItem(value: 'check', child: Text('重新检测安装状态')),
      ],
    );
  }

  Future<void> _onMenu(String value, EnvironmentDetail? env) async {
    // 安装 / 更新 / 卸载在途时不再受理新的菜单操作：菜单项本身不会置灰，
    // 连点会给面板连发多条同类后台任务。
    if (_busy != null) return;
    final repo = ref.read(environmentRepoProvider);
    final name =
        env?.name ?? '${environmentTypeLabel(widget.type)} ${widget.slug}';
    switch (value) {
      case 'check':
        ref.invalidate(environmentInstalledProvider(_ref));
        showInfoSnack(context, '正在重新检测安装状态…');
      case 'install':
        final ok = await showConfirmDialog(
          context,
          title: '安装 $name？',
          content: '面板将在后台执行安装，可在任务中心查看进度。',
          confirmText: '安装',
        );
        if (!ok) return;
        await _run(
          'install',
          () => repo.install(widget.type, widget.slug),
          successMessage: '已提交安装任务：$name',
          asTask: true,
          invalidate: [
            environmentDetailProvider(_ref),
            environmentInstalledProvider(_ref),
            environmentListProvider,
          ],
        );
      case 'update':
        final ok = await showConfirmDialog(
          context,
          title: '更新 $name？',
          content: '更新期间该环境可能短暂不可用。',
          confirmText: '更新',
        );
        if (!ok) return;
        await _run(
          'update',
          () => repo.update(widget.type, widget.slug),
          successMessage: '已提交更新任务：$name',
          asTask: true,
          invalidate: [
            environmentDetailProvider(_ref),
            environmentListProvider,
          ],
        );
      case 'uninstall':
        final ok = await showConfirmDialog(
          context,
          title: '卸载 $name？',
          content: '卸载后依赖该环境的网站 / 应用将无法运行，此操作不可恢复。',
          confirmText: '卸载',
          danger: true,
        );
        if (!ok) return;
        await _run(
          'uninstall',
          () => repo.uninstall(widget.type, widget.slug),
          successMessage: '已提交卸载任务：$name',
          asTask: true,
          invalidate: [
            environmentDetailProvider(_ref),
            environmentInstalledProvider(_ref),
            environmentListProvider,
          ],
        );
    }
  }

  // ------------------------------------------------------------------- 卡片

  Widget _infoCard(EnvironmentDetail? env) {
    final theme = Theme.of(context);
    final installed = _installed(env);
    return SectionCard(
      title: '环境信息',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KeyValueRow(
            label: '名称',
            value:
                env?.name ??
                '${environmentTypeLabel(widget.type)} ${widget.slug}',
          ),
          KeyValueRow(label: '类型', value: environmentTypeLabel(widget.type)),
          KeyValueRow(label: '版本标识', value: widget.slug, monospace: true),
          KeyValueRow(label: '最新版本', value: env?.version ?? ''),
          KeyValueRow(label: '已安装版本', value: env?.installedVersion ?? ''),
          KeyValueRow(
            label: '实时检测',
            value: probeText(ref.watch(environmentInstalledProvider(_ref))),
          ),
          if (env != null && env.description.isNotEmpty)
            KeyValueRow(label: '描述', value: env.description),
          const SizedBox(height: 8),
          Row(
            children: [
              StatusChip(
                label: installed ? '已安装' : '未安装',
                color: installed
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline,
                icon: installed
                    ? Icons.check_circle_outline
                    : Icons.radio_button_unchecked,
              ),
              const SizedBox(width: 8),
              if (env?.hasUpdate == true)
                StatusChip(
                  label: '可更新',
                  color: theme.colorScheme.tertiary,
                  icon: Icons.upgrade_rounded,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _cliCard(EnvironmentDetail? env) {
    final enabled = _installed(env);
    return SectionCard(
      title: '命令行',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _cliDescription,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: !enabled || _isBusy('cli') ? null : _setCli,
            icon: _isBusy('cli')
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.terminal_rounded, size: 18),
            label: const Text('设为命令行默认版本'),
          ),
          if (!enabled)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '该版本尚未安装，安装后才能设置命令行默认版本。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String get _cliDescription {
    switch (widget.type) {
      case 'go':
        return '将 go、gofmt 链接到系统命令目录，使 `go` 命令指向该版本。';
      case 'java':
        return '将 java、javac、jar、jshell 链接到系统命令目录，使 `java` 命令指向该版本。';
      case 'nodejs':
        return '将 node、npm、npx、corepack 链接到系统命令目录，使 `node` 命令指向该版本。';
      case 'python':
        return '将 python3、pip3 链接到系统命令目录，使 `python3` 命令指向该版本。';
      case 'dotnet':
        return '将 dotnet 链接到系统命令目录，使 `dotnet` 命令指向该版本。';
      default:
        return '将该版本的可执行文件链接到系统命令目录。';
    }
  }

  Future<void> _setCli() async {
    final repo = ref.read(environmentRepoProvider);
    Future<void> action() {
      switch (widget.type) {
        case 'go':
          return repo.goSetCli(widget.slug);
        case 'java':
          return repo.javaSetCli(widget.slug);
        case 'nodejs':
          return repo.nodejsSetCli(widget.slug);
        case 'python':
          return repo.pythonSetCli(widget.slug);
        case 'dotnet':
          return repo.dotnetSetCli(widget.slug);
        default:
          // 面板 /environment/types 只会返回 go/java/nodejs/python/dotnet/php，
          // 走到这里说明面板新增了本端未适配的类型，给出可读提示而非 StateError
          // （StateError 的 toString 会带上英文的 "Bad state: " 前缀）。
          throw ApiException('暂不支持为 ${widget.type} 类型设置命令行默认版本');
      }
    }

    await _run('cli', action, successMessage: '已设为命令行默认版本');
  }

  List<Widget> _extraCards(EnvironmentDetail? env) {
    final enabled = _installed(env);

    switch (widget.type) {
      case 'go':
        return [
          _sourceCard(
            title: 'Go 代理（GOPROXY）',
            helper: '执行 `go env -w GOPROXY=…` 写入该版本的 Go 环境变量。',
            value: ref.watch(goProxyProvider(widget.slug)),
            presets: const [
              'https://proxy.golang.org,direct',
              'https://goproxy.cn,direct',
              'https://goproxy.io,direct',
              'https://mirrors.aliyun.com/goproxy/,direct',
            ],
            enabled: enabled,
            onRetry: () => ref.invalidate(goProxyProvider(widget.slug)),
            onSave: (value) => _run(
              'source',
              () => ref
                  .read(environmentRepoProvider)
                  .setGoProxy(widget.slug, value),
              successMessage: 'Go 代理已保存',
              invalidate: [goProxyProvider(widget.slug)],
            ),
          ),
        ];
      case 'nodejs':
        return [
          _sourceCard(
            title: 'npm 镜像源（registry）',
            helper: '执行 `npm config set --global registry …`，对该版本全局生效。',
            value: ref.watch(nodejsRegistryProvider(widget.slug)),
            presets: const [
              'https://registry.npmjs.org/',
              'https://registry.npmmirror.com/',
              'https://mirrors.cloud.tencent.com/npm/',
            ],
            enabled: enabled,
            onRetry: () => ref.invalidate(nodejsRegistryProvider(widget.slug)),
            onSave: (value) => _run(
              'source',
              () => ref
                  .read(environmentRepoProvider)
                  .setNodejsRegistry(widget.slug, value),
              successMessage: 'npm 镜像源已保存',
              invalidate: [nodejsRegistryProvider(widget.slug)],
            ),
          ),
        ];
      case 'python':
        return [
          _sourceCard(
            title: 'pip 镜像源（index-url）',
            helper: '执行 `pip3 config --global set global.index-url …`。',
            value: ref.watch(pythonMirrorProvider(widget.slug)),
            presets: const [
              'https://pypi.org/simple',
              'https://pypi.tuna.tsinghua.edu.cn/simple',
              'https://mirrors.aliyun.com/pypi/simple/',
              'https://mirrors.cloud.tencent.com/pypi/simple',
            ],
            enabled: enabled,
            onRetry: () => ref.invalidate(pythonMirrorProvider(widget.slug)),
            onSave: (value) => _run(
              'source',
              () => ref
                  .read(environmentRepoProvider)
                  .setPythonMirror(widget.slug, value),
              successMessage: 'pip 镜像源已保存',
              invalidate: [pythonMirrorProvider(widget.slug)],
            ),
          ),
        ];
      default:
        return const [HintBanner('该环境类型除「设为命令行默认版本」外没有其他可配置项。')];
    }
  }

  Widget _sourceCard({
    required String title,
    required String helper,
    required AsyncValue<String> value,
    required List<String> presets,
    required bool enabled,
    required VoidCallback onRetry,
    required Future<void> Function(String value) onSave,
  }) {
    if (!enabled) {
      return SectionCard(
        title: title,
        child: Text(
          '该版本尚未安装，安装后才能读取和修改。',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return SectionCard(
      title: title,
      child: value.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ),
        ),
        error: (error, _) => ErrorView(error: error, onRetry: onRetry),
        data: (current) => _SourceEditor(
          key: ValueKey('$title:$current'),
          title: title,
          initialValue: current,
          helper: helper,
          presets: presets,
          saving: _isBusy('source'),
          onSave: onSave,
        ),
      ),
    );
  }
}

/// 代理 / 镜像源编辑器：输入框 + 常用预设 + 保存。
class _SourceEditor extends StatefulWidget {
  const _SourceEditor({
    super.key,
    required this.title,
    required this.initialValue,
    required this.helper,
    required this.presets,
    required this.saving,
    required this.onSave,
  });

  /// 所属卡片标题，用于返回确认的文案。
  final String title;

  final String initialValue;
  final String helper;
  final List<String> presets;
  final bool saving;
  final Future<void> Function(String value) onSave;

  @override
  State<_SourceEditor> createState() => _SourceEditorState();
}

class _SourceEditorState extends State<_SourceEditor> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );

  /// 输入框内容是否偏离服务端当前值。
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_syncDirty);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_syncDirty)
      ..dispose();
    super.dispose();
  }

  void _syncDirty() {
    final dirty = _controller.text.trim() != widget.initialValue.trim();
    if (dirty != _dirty) setState(() => _dirty = dirty);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 拦截返回：改了代理 / 镜像源却没点保存时先确认。
    // UnsavedChangesGuard 内部的 PopScope 按最近的 ModalRoute 注册，不必包住
    // 整个 Scaffold；就近包裹编辑器可以让脏状态完全留在组件内，无需上抛页面级。
    return UnsavedChangesGuard(
      hasUnsavedChanges: _dirty,
      message: '${widget.title}有未保存的修改，确定放弃吗？',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.helper,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            maxLines: 2,
            minLines: 1,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final preset in widget.presets)
                ActionChip(
                  label: Text(
                    preset,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11),
                  ),
                  onPressed: widget.saving
                      ? null
                      : () => _controller.text = preset,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (_dirty)
                Expanded(
                  child: Text(
                    '有未保存的修改',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.tertiary,
                    ),
                  ),
                )
              else
                const Spacer(),
              TextButton(
                onPressed: widget.saving
                    ? null
                    : () => copyToClipboard(context, _controller.text),
                child: const Text('复制'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: widget.saving
                    ? null
                    : () {
                        final value = _controller.text.trim();
                        if (value.isEmpty) {
                          showErrorSnack(context, const ApiException('内容不能为空'));
                          return;
                        }
                        widget.onSave(value);
                      },
                child: widget.saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('保存'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
