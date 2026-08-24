import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_view.dart';
import '../../../core/widgets/unsaved_guard.dart';
import '../models/container_compose.dart';
import '../models/kv.dart';
import '../providers/container_providers.dart';
import '../widgets/action_runner.dart';
import '../widgets/compose_actions.dart';
import '../widgets/kv_editor.dart';
import '../widgets/status_badge.dart';

/// 编排详情页（`/containers/compose/:name`）。
///
/// 查看 / 编辑 `docker-compose.yml` 与 `.env`，并支持启动、停止、删除。
class ComposeDetailPage extends ConsumerStatefulWidget {
  const ComposeDetailPage({super.key, required this.name});

  final String name;

  @override
  ConsumerState<ComposeDetailPage> createState() => _ComposeDetailPageState();
}

class _ComposeDetailPageState extends ConsumerState<ComposeDetailPage> {
  final TextEditingController _composeController = TextEditingController();

  Key _envEditorKey = UniqueKey();
  List<KV> _envs = const [];
  bool _dirty = false;
  bool _applying = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _composeController.addListener(_onComposeChanged);
    // provider 可能已有缓存值：直接填充（initState 中不可 setState）。
    final cached = ref.read(composeDetailProvider(widget.name)).value;
    if (cached != null) _fill(cached);
    // 之后的数据变化（首次加载完成 / 刷新）通过监听同步到编辑器。
    ref.listenManual<AsyncValue<ComposeDetail>>(
      composeDetailProvider(widget.name),
      (previous, next) => next.whenData(_applyDetail),
    );
  }

  @override
  void dispose() {
    _composeController
      ..removeListener(_onComposeChanged)
      ..dispose();
    super.dispose();
  }

  void _onComposeChanged() {
    if (_applying || _dirty) return;
    setState(() => _dirty = true);
  }

  /// 填充编辑器内容（不触发重建）。
  void _fill(ComposeDetail detail) {
    _applying = true;
    _composeController.text = detail.compose;
    _applying = false;
    _envs = detail.envs;
    _envEditorKey = UniqueKey();
    _dirty = false;
    _loaded = true;
  }

  void _applyDetail(ComposeDetail detail) {
    // 有未保存修改时不覆盖用户输入。
    if (_loaded && _dirty) return;
    if (!mounted) {
      _fill(detail);
      return;
    }
    setState(() => _fill(detail));
  }

  Future<void> _reload({bool force = false}) async {
    if (_dirty && !force) {
      final ok = await showConfirmDialog(
        context,
        title: '放弃修改',
        content: '当前有未保存的修改，重新加载将丢失这些修改。确定继续吗？',
        confirmText: '放弃并重新加载',
        danger: true,
      );
      if (!ok) return;
    }
    setState(() => _dirty = false);
    ref.invalidate(composeDetailProvider(widget.name));
  }

  Future<void> _save() async {
    final ok = await runAction(
      context,
      pending: '正在保存编排…',
      success: '已保存',
      action: () => ref
          .read(containerRepoProvider)
          .updateCompose(
            name: widget.name,
            compose: _composeController.text,
            envs: _envs,
          ),
    );
    if (!ok || !mounted) return;
    setState(() => _dirty = false);
    ref.invalidate(composeDetailProvider(widget.name));
    await ref.read(containerComposesProvider.notifier).reload();
  }

  Future<void> _up() async {
    // 启动用的是服务器上已保存的内容，未保存的编辑不会生效——先说清楚。
    if (_dirty) {
      final go = await showConfirmDialog(
        context,
        title: '有未保存的修改',
        content:
            '当前编辑的内容尚未保存，启动将使用服务器上已保存的编排内容。'
            '建议先保存再启动。',
        confirmText: '仍然启动',
        cancelText: '返回保存',
      );
      if (!go || !mounted) return;
    }
    final ok = await composeUpAction(context, ref, widget.name);
    if (!ok) return;
    ref.invalidate(containersProvider);
    await ref.read(containerComposesProvider.notifier).reload();
  }

  Future<void> _down() async {
    final ok = await composeDownAction(context, ref, widget.name);
    if (!ok) return;
    ref.invalidate(containersProvider);
    await ref.read(containerComposesProvider.notifier).reload();
  }

  Future<void> _remove() async {
    final ok = await composeRemoveAction(context, ref, widget.name);
    if (!ok) return;
    ref.invalidate(containersProvider);
    await ref.read(containerComposesProvider.notifier).reload();
    if (mounted && context.canPop()) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final async = ref.watch(composeDetailProvider(widget.name));

    // 返回箭头（AppBar 默认的 BackButton）走 Navigator.maybePop，
    // 与系统返回手势 / 返回键一样被 UnsavedChangesGuard 拦截，
    // 三条返回路径行为一致。
    return UnsavedChangesGuard(
      hasUnsavedChanges: _dirty,
      message: '编排内容有未保存的修改，离开将丢失这些修改。确定放弃吗？',
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              Flexible(
                child: Text(
                  widget.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_dirty) ...[
                const SizedBox(width: 8),
                const StatusBadge(
                  label: '未保存',
                  tone: BadgeTone.warning,
                  dense: true,
                ),
              ],
            ],
          ),
          actions: [
            A11yIconButton(
              tooltip: '重新加载编排',
              icon: const Icon(Icons.refresh),
              onPressed: _reload,
            ),
            PopupMenuButton<String>(
              tooltip: '更多操作',
              icon: const Icon(Icons.more_vert),
              onSelected: (value) {
                switch (value) {
                  case 'up':
                    _up();
                    break;
                  case 'down':
                    _down();
                    break;
                  case 'remove':
                    _remove();
                    break;
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'up',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.play_arrow_outlined),
                    title: Text('启动编排'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'down',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.stop_outlined),
                    title: Text('停止编排'),
                  ),
                ),
                PopupMenuItem(
                  value: 'remove',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.delete_outline,
                      color: theme.colorScheme.error,
                    ),
                    title: Text(
                      '删除编排',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        body: async.when(
          loading: () => _loaded
              ? _buildEditor(theme)
              : const LoadingView(message: '正在加载编排…'),
          error: (error, _) => _loaded
              ? _buildEditor(theme)
              : ErrorView(
                  error: error,
                  onRetry: () =>
                      ref.invalidate(composeDetailProvider(widget.name)),
                ),
          data: (_) => _buildEditor(theme),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _down,
                    icon: const Icon(Icons.stop_outlined),
                    label: const Text('停止'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _up,
                    icon: const Icon(Icons.play_arrow_outlined),
                    label: const Text('启动'),
                  ),
                ),
              ],
            ),
          ),
        ),
        floatingActionButton: _dirty
            ? FloatingActionButton.extended(
                onPressed: _save,
                icon: const Icon(Icons.save_outlined),
                label: const Text('保存'),
              )
            : null,
      ),
    );
  }

  Widget _buildEditor(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'docker-compose.yml',
                style: theme.textTheme.titleSmall,
              ),
            ),
            TextButton.icon(
              onPressed: _dirty ? _save : null,
              icon: const Icon(Icons.save_outlined, size: 18),
              label: const Text('保存'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _composeController,
          maxLines: null,
          minLines: 12,
          keyboardType: TextInputType.multiline,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontFamilyFallback: ['Courier'],
            fontSize: 13,
            height: 1.5,
          ),
          decoration: const InputDecoration(
            alignLabelWithHint: true,
            hintText: 'services: …',
          ),
        ),
        const SizedBox(height: 20),
        Text('环境变量（.env）', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        KvEditor(
          key: _envEditorKey,
          initialValue: _envs,
          keyHint: '变量名',
          valueHint: '变量值',
          addLabel: '添加变量',
          onChanged: (value) {
            _envs = value;
            if (!_dirty) setState(() => _dirty = true);
          },
        ),
        const SizedBox(height: 8),
        Text(
          '提示：保存后需重新「启动」编排才会生效。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
