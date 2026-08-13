import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/app_snack.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_view.dart';
import '../models/file_item.dart';
import '../providers/files_providers.dart';

/// 展示文件 / 目录属性的底部面板（`GET /api/file/info` + `GET /api/file/size`）。
Future<void> showFilePropertySheet(BuildContext context, String path) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => FilePropertySheet(path: path),
  );
}

class FilePropertySheet extends ConsumerStatefulWidget {
  const FilePropertySheet({super.key, required this.path});

  final String path;

  @override
  ConsumerState<FilePropertySheet> createState() => _FilePropertySheetState();
}

class _FilePropertySheetState extends ConsumerState<FilePropertySheet> {
  String? _calculatedSize;
  bool _calculating = false;
  String? _sizeError;

  Future<void> _calculateSize() async {
    setState(() {
      _calculating = true;
      _sizeError = null;
    });
    try {
      final size = await ref.read(fileRepoProvider).size(widget.path);
      if (!mounted) return;
      setState(() {
        _calculatedSize = size;
        _calculating = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        // describeError：非 ApiException 时避免露出原始英文异常。
        _sizeError = describeError(e);
        _calculating = false;
      });
    }
  }

  Widget _row(String label, String value, {bool copyable = false}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value.isEmpty ? '-' : value,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          if (copyable)
            A11yIconButton(
              iconSize: 18,
              visualDensity: VisualDensity.compact,
              tooltip: '复制$label',
              icon: const Icon(Icons.copy_all_outlined),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: value));
                if (!mounted) return;
                showSuccessSnack(context, '$label已复制到剪贴板');
              },
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final infoAsync = ref.watch(fileInfoProvider(widget.path));

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: infoAsync.when(
            loading: () => const SizedBox(
              height: 200,
              child: LoadingView(message: '正在读取属性…'),
            ),
            error: (error, _) => SizedBox(
              height: 240,
              child: ErrorView(
                error: error,
                onRetry: () => ref.invalidate(fileInfoProvider(widget.path)),
              ),
            ),
            data: (FileItem info) => SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        info.dir
                            ? Icons.folder_outlined
                            : Icons.description_outlined,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          info.name,
                          style: theme.textTheme.titleMedium,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _row('路径', info.full, copyable: true),
                  _row('类型', info.dir ? '目录' : (info.symlink ? '符号链接' : '文件')),
                  if (info.symlink) _row('链接指向', info.link),
                  _row(
                    '大小',
                    _calculatedSize ?? (info.size.isEmpty ? '未计算' : info.size),
                  ),
                  _row('权限', '${info.mode}（${info.modeStr}）'),
                  _row('属主', '${info.owner}:${info.group}'),
                  _row('UID/GID', '${info.uid} / ${info.gid}'),
                  _row('修改时间', info.modify),
                  _row('隐藏文件', info.hidden ? '是' : '否'),
                  _row('防篡改锁定', info.immutable ? '是（chattr +i）' : '否'),
                  if (_sizeError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _sizeError!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _calculating ? null : _calculateSize,
                          icon: _calculating
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.straighten),
                          label: Text(_calculating ? '计算中…' : '计算大小'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: () =>
                              ref.invalidate(fileInfoProvider(widget.path)),
                          icon: const Icon(Icons.refresh),
                          label: const Text('刷新'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
