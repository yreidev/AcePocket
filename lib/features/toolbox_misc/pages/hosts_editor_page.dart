import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/app_snack.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_view.dart';
import '../../../core/widgets/unsaved_guard.dart';
import '../providers/toolbox_misc_providers.dart';
import '../widgets/toolbox_tiles.dart';

/// /etc/hosts 编辑页（GET/POST `/toolbox_system/hosts`）。
///
/// 面板保存时直接以 0644 覆盖写入 /etc/hosts，因此保存前需二次确认。
class HostsEditorPage extends ConsumerStatefulWidget {
  const HostsEditorPage({super.key});

  @override
  ConsumerState<HostsEditorPage> createState() => _HostsEditorPageState();
}

class _HostsEditorPageState extends ConsumerState<HostsEditorPage> {
  final TextEditingController _controller = TextEditingController();

  /// 已加载到编辑器的原始内容，用于判断是否有未保存修改。
  String _original = '';
  bool _loaded = false;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _dirty => _loaded && _controller.text != _original;

  void _apply(String content) {
    if (_loaded) return;
    _controller.text = content;
    _original = content;
    _loaded = true;
  }

  Future<void> _reload() async {
    if (_dirty) {
      final confirmed = await showConfirmDialog(
        context,
        title: '放弃当前修改？',
        content: '重新读取会丢弃尚未保存的编辑内容。',
        confirmText: '重新读取',
        danger: true,
      );
      if (!confirmed) return;
    }
    setState(() {
      _loaded = false;
      _original = '';
    });
    ref.invalidate(hostsContentProvider);
  }

  Future<void> _save() async {
    final content = _controller.text;
    final confirmed = await showConfirmDialog(
      context,
      title: '保存 hosts 文件？',
      content:
          '将以当前内容覆盖服务器上的 /etc/hosts，'
          '错误的解析记录可能导致域名解析异常。',
      confirmText: '保存',
      danger: true,
    );
    if (!confirmed) return;
    setState(() => _saving = true);
    try {
      await ref.read(toolboxMiscRepoProvider).updateHosts(content);
      if (!mounted) return;
      setState(() => _original = content);
      ref.invalidate(systemToolsProvider);
      showSuccessSnack(context, 'hosts 已保存');
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = ref.watch(hostsContentProvider);

    // 未保存拦截统一交给 core 的 UnsavedChangesGuard：
    // AppBar 返回箭头（走 maybePop）与系统返回手势 / 返回键行为一致。
    return UnsavedChangesGuard(
      hasUnsavedChanges: _dirty,
      message: 'hosts 内容已修改但尚未保存，放弃后无法恢复。',
      child: Scaffold(
        appBar: AppBar(
          title: const Text('hosts 文件'),
          actions: [
            A11yIconButton(
              tooltip: '重新读取 hosts 文件',
              icon: const Icon(Icons.refresh),
              onPressed: _saving ? null : _reload,
            ),
          ],
        ),
        body: content.when(
          loading: () => const LoadingView(message: '读取 /etc/hosts…'),
          error: (error, _) => ErrorView(
            error: error,
            onRetry: () => ref.invalidate(hostsContentProvider),
          ),
          data: (data) {
            _apply(data);
            return Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: Text(
                    '每行一条记录，格式为「IP  域名 [别名…]」，'
                    '以 # 开头的行为注释。保存后立即生效。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: TextField(
                      controller: _controller,
                      onChanged: (_) => setState(() {}),
                      maxLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      keyboardType: TextInputType.multiline,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontFamily: 'monospace',
                      ),
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                        hintText: '127.0.0.1  localhost',
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _dirty ? '有未保存的修改' : '内容与服务器一致',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: _dirty
                          ? theme.colorScheme.tertiary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                FilledButton.icon(
                  onPressed: (!_loaded || _saving || !_dirty) ? null : _save,
                  icon: _saving
                      ? const BusyIndicator(size: 16)
                      : const Icon(Icons.save_outlined),
                  label: const Text('保存'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
