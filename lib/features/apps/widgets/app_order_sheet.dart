import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/widgets/empty_view.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_view.dart';
import '../models/app_item.dart';
import '../providers/apps_providers.dart';

/// 首页显示应用的排序（对应 `POST /api/app/update_order`）。
///
/// 保存成功返回 true。
Future<bool> showAppOrderSheet(BuildContext context) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => const _AppOrderSheet(),
  );
  return result ?? false;
}

class _AppOrderSheet extends ConsumerStatefulWidget {
  const _AppOrderSheet();

  @override
  ConsumerState<_AppOrderSheet> createState() => _AppOrderSheetState();
}

class _AppOrderSheetState extends ConsumerState<_AppOrderSheet> {
  List<AppItem>? _apps;
  Object? _error;

  /// 保存失败的错误：只能在弹层内部展示（见 [_save] 注释）。
  Object? _saveError;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // 首帧之后再加载，避免在 initState 内直接 setState。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    final repo = ref.read(appsRepoProvider);
    if (repo == null) {
      setState(() {
        _loading = false;
        _error = '尚未选择服务器';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final paged = await repo.list(page: 1, limit: 200, installedOnly: true);
      if (!mounted) return;
      setState(() {
        _apps = paged.items.where((app) => app.show).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    final repo = ref.read(appsRepoProvider);
    final apps = _apps;
    if (repo == null || apps == null) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await repo.updateOrder(apps.map((app) => app.slug).toList());
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      // 弹层内不能用 SnackBar：这里没有自己的 Scaffold，ScaffoldMessenger 解析到
      // 应用级实例，SnackBar 会显示在模态弹层**下方**被完全遮挡，
      // 用户得不到任何失败反馈。改为在弹层内部用错误条展示。
      setState(() {
        _saving = false;
        _saveError = e;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxHeight = MediaQuery.of(context).size.height * 0.8;
    final apps = _apps;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('首页显示排序', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(
                    '长按拖动调整应用在面板首页的展示顺序',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: Builder(
                builder: (context) {
                  if (_loading) {
                    return const SizedBox(
                      height: 200,
                      child: LoadingView(message: '加载中…'),
                    );
                  }
                  if (_error != null) {
                    return SizedBox(
                      height: 220,
                      child: ErrorView(error: _error!, onRetry: _load),
                    );
                  }
                  if (apps == null || apps.isEmpty) {
                    return const SizedBox(
                      height: 220,
                      child: EmptyView(
                        message: '暂无在首页显示的应用\n可在应用列表中打开「首页显示」开关',
                        icon: Icons.dashboard_customize_outlined,
                      ),
                    );
                  }
                  return ReorderableListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: apps.length,
                    // onReorderItem 的 newIndex 已按「移除 oldIndex 后」修正，
                    // 无需再自行 -1（onReorder 在 Flutter 3.41+ 已废弃）。
                    onReorderItem: (oldIndex, newIndex) {
                      setState(() {
                        final item = apps.removeAt(oldIndex);
                        apps.insert(newIndex, item);
                      });
                    },
                    itemBuilder: (context, index) {
                      final app = apps[index];
                      return ListTile(
                        key: ValueKey(app.slug),
                        leading: Text(
                          '${index + 1}',
                          style: theme.textTheme.titleMedium,
                        ),
                        title: Text(app.name.isEmpty ? app.slug : app.name),
                        subtitle: Text(app.slug),
                        trailing: const Icon(Icons.drag_handle),
                      );
                    },
                  );
                },
              ),
            ),
            const Divider(height: 1),
            if (_saveError != null)
              Container(
                width: double.infinity,
                color: theme.colorScheme.errorContainer,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 20,
                      color: theme.colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '保存排序失败：${describeError(_saveError!)}',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(false),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: (_saving || apps == null || apps.isEmpty)
                        ? null
                        : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('保存'),
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
