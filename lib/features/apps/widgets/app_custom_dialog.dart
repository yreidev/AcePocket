import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_view.dart';
import '../../../core/widgets/unsaved_guard.dart';
import '../models/app_custom.dart';
import '../models/app_item.dart';
import '../providers/apps_providers.dart';

/// 自定义编译参数编辑对话框（仅源码编译类应用支持）。
///
/// 读取 `GET /api/app/custom`，保存 `POST /api/app/custom`。
/// 保存成功返回 true。
Future<bool> showAppCustomDialog(
  BuildContext context, {
  required AppItem app,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _AppCustomDialog(app: app),
  );
  return result ?? false;
}

class _AppCustomDialog extends ConsumerStatefulWidget {
  const _AppCustomDialog({required this.app});

  final AppItem app;

  @override
  ConsumerState<_AppCustomDialog> createState() => _AppCustomDialogState();
}

class _AppCustomDialogState extends ConsumerState<_AppCustomDialog> {
  final _preScriptController = TextEditingController();
  final _argsController = TextEditingController();

  /// 首次读取到的参数，用于判断是否有未保存的修改。
  AppCustom? _original;
  bool _initialized = false;
  bool _saving = false;
  bool _dirty = false;

  /// 保存失败的错误：对话框上方有遮罩层，SnackBar 会被挡住，只能画在对话框内。
  Object? _saveError;

  @override
  void initState() {
    super.initState();
    _preScriptController.addListener(_onEdited);
    _argsController.addListener(_onEdited);
  }

  @override
  void dispose() {
    _preScriptController.dispose();
    _argsController.dispose();
    super.dispose();
  }

  void _onEdited() {
    final original = _original;
    if (original == null) return;
    final dirty =
        _preScriptController.text != original.preScript ||
        _argsController.text != original.args;
    if (dirty != _dirty) setState(() => _dirty = dirty);
  }

  Future<void> _save() async {
    final repo = ref.read(appsRepoProvider);
    if (repo == null) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await repo.saveCustom(
        widget.app.slug,
        AppCustom(
          preScript: _preScriptController.text,
          args: _argsController.text,
        ),
      );
      if (!mounted) return;
      ref.invalidate(appCustomProvider(widget.app.slug));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = e;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final async = ref.watch(appCustomProvider(widget.app.slug));

    return UnsavedChangesGuard(
      hasUnsavedChanges: _dirty && !_saving,
      message: '编译参数有未保存的修改，确定放弃吗？',
      child: _buildDialog(context, theme, async),
    );
  }

  Widget _buildDialog(
    BuildContext context,
    ThemeData theme,
    AsyncValue<AppCustom> async,
  ) {
    return AlertDialog(
      title: Text('${widget.app.name} 编译参数'),
      content: SizedBox(
        width: double.maxFinite,
        child: async.when(
          loading: () =>
              const SizedBox(height: 140, child: LoadingView(message: '读取中…')),
          error: (error, _) => SizedBox(
            height: 180,
            child: ErrorView(
              error: error,
              onRetry: () => ref.invalidate(appCustomProvider(widget.app.slug)),
            ),
          ),
          data: (custom) {
            if (!_initialized) {
              _initialized = true;
              // 先记录原始值再写入文本框：控制器监听器会立刻回调，
              // 此时 _original 已就绪，算出的 dirty 为 false，不会在 build 中
              // 触发 setState。
              _original = custom;
              _preScriptController.text = custom.preScript;
              _argsController.text = custom.args;
            }
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_saveError != null) ...[
                    _InlineError(error: _saveError!),
                    const SizedBox(height: 12),
                  ],
                  Text(
                    '前置脚本在 configure 之前执行，编译参数会追加到 configure 末尾。'
                    '修改后需重新安装应用才会生效。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _preScriptController,
                    minLines: 3,
                    maxLines: 6,
                    enabled: !_saving,
                    decoration: const InputDecoration(
                      labelText: '前置脚本',
                      hintText: '#!/bin/bash\n…',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _argsController,
                    minLines: 2,
                    maxLines: 5,
                    enabled: !_saving,
                    decoration: const InputDecoration(
                      labelText: '编译参数',
                      hintText: '--with-http_v2_module …',
                      alignLabelWithHint: true,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          // maybePop 才会走 UnsavedChangesGuard 的确认流程，
          // 保证「取消」与系统返回键的行为一致。
          onPressed: _saving ? null : () => Navigator.maybePop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: (_saving || !async.hasValue) ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('保存'),
        ),
      ],
    );
  }
}

/// 对话框内的错误条。
///
/// 对话框上方有模态遮罩，SnackBar 会被遮罩挡住（且位于屏幕底部），
/// 保存失败必须画在对话框内部才能被看到。
class _InlineError extends StatelessWidget {
  const _InlineError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline,
            size: 20,
            color: theme.colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '保存失败：${describeError(error)}',
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
