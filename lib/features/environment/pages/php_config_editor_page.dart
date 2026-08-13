import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/app_snack.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_view.dart';
import '../../../core/widgets/unsaved_guard.dart';
import '../providers/environment_providers.dart';
import '../widgets/environment_ui.dart';

/// PHP 配置文件编辑页（`/environments/php/:version/config?target=ini|fpm`）。
///
/// - `ini`：`GET/POST /environment/php/{version}/config`（php.ini）
/// - `fpm`：`GET/POST /environment/php/{version}/fpm_config`（php-fpm.conf）
class PhpConfigEditorPage extends ConsumerStatefulWidget {
  const PhpConfigEditorPage({
    super.key,
    required this.version,
    required this.fpm,
  });

  final int version;

  /// true 编辑 php-fpm.conf，false 编辑 php.ini。
  final bool fpm;

  @override
  ConsumerState<PhpConfigEditorPage> createState() =>
      _PhpConfigEditorPageState();
}

class _PhpConfigEditorPageState extends ConsumerState<PhpConfigEditorPage> {
  final TextEditingController _controller = TextEditingController();

  /// 已载入的服务端原文，用于判断是否有未保存修改。
  String? _loaded;
  bool _saving = false;

  String get _fileName => widget.fpm ? 'php-fpm.conf' : 'php.ini';

  AutoDisposeFutureProvider<String> get _provider => widget.fpm
      ? phpFpmConfigProvider(widget.version)
      : phpIniProvider(widget.version);

  @override
  void initState() {
    super.initState();
    // provider 已有缓存值时（页面返回复用）直接填充，避免编辑器空白。
    final cached = ref.read(_provider).valueOrNull;
    if (cached != null) {
      _controller.text = cached;
      _loaded = cached;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _dirty => _loaded != null && _controller.text != _loaded;

  /// [_dirty] 的缓存值，build 只读它。
  bool _dirtyFlag = false;

  /// 重新计算脏标记，只在翻转时重建。
  ///
  /// 原实现每敲一个字符都 `setState`，整页（含承载数千行原文的 TextField）
  /// 跟着重建，大配置文件下输入明显卡顿；而重建只为刷新返回拦截与「保存」
  /// 按钮的可用态，这两者只取决于脏标记本身。
  ///
  /// 任何改动 [_loaded] 的地方都要跟着调一次，否则缓存值会与实际状态脱节
  /// （保存后仍停留在 true，则下一次编辑不会再触发重建，返回拦截失效）。
  void _syncDirty() {
    if (_dirty != _dirtyFlag) setState(() => _dirtyFlag = _dirty);
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final repo = ref.read(environmentRepoProvider);
    final content = _controller.text;
    try {
      if (widget.fpm) {
        await repo.updatePhpFpmConfig(widget.version, content);
      } else {
        await repo.updatePhpConfig(widget.version, content);
      }
      if (!mounted) return;
      setState(() => _loaded = content);
      _syncDirty();
      ref.invalidate(_provider);
      ref.invalidate(phpConfigTuneProvider(widget.version));
      showSuccessSnack(context, '$_fileName 已保存，需重启 PHP-FPM 后生效');
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _reload() async {
    if (_dirty) {
      // 与返回拦截共用同一套文案，避免两条「丢弃草稿」路径措辞不一。
      final ok = await showConfirmDialog(
        context,
        title: '放弃修改',
        content: '重新载入会丢弃 $_fileName 当前未保存的编辑内容。',
        confirmText: '放弃修改',
        cancelText: '继续编辑',
        danger: true,
      );
      if (!ok || !mounted) return;
    }
    setState(() => _loaded = null);
    _syncDirty();
    ref.invalidate(_provider);
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(_provider);
    final theme = Theme.of(context);

    // 数据到达（或重新载入）时填充编辑器。
    ref.listen<AsyncValue<String>>(_provider, (previous, next) {
      next.whenData((value) {
        if (_loaded == null) {
          _controller.text = value;
          setState(() => _loaded = value);
          _syncDirty();
        }
      });
    });

    return UnsavedChangesGuard(
      hasUnsavedChanges: _dirtyFlag,
      message: '$_fileName 的修改尚未保存，确定放弃吗？',
      child: Scaffold(
        appBar: AppBar(
          title: Text('$_fileName · PHP ${phpVersionText(widget.version)}'),
          actions: [
            A11yIconButton(
              tooltip: '重新载入 $_fileName',
              icon: const Icon(Icons.refresh),
              onPressed: _saving ? null : _reload,
            ),
            TextButton(
              // 用 _loaded 而非 config.hasValue 判断：重新载入期间 _loaded 已
              // 置空但旧值仍在 AsyncValue 里，此时编辑器内容是待丢弃的旧文本，
              // 允许保存会把它写回服务端。
              onPressed: _saving || _loaded == null ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('保存'),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: config.when(
          loading: () => LoadingView(message: '读取 $_fileName…'),
          error: (error, _) =>
              ErrorView(error: error, onRetry: () => ref.invalidate(_provider)),
          data: (_) => Column(
            children: [
              HintBanner(
                '直接修改 $_fileName 原文，若不清楚各参数含义请改用「参数调优」页面。'
                '保存后需重启 php-fpm-${widget.version} 服务才会生效。',
                warning: true,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  child: TextField(
                    controller: _controller,
                    maxLines: null,
                    expands: true,
                    keyboardType: TextInputType.multiline,
                    textAlignVertical: TextAlignVertical.top,
                    onChanged: (_) => _syncDirty(),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12.5,
                      height: 1.45,
                    ),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: theme.colorScheme.surfaceContainerLow,
                      contentPadding: const EdgeInsets.all(12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
