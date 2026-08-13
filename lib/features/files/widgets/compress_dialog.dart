import 'dart:math';

import 'package:flutter/material.dart';

import '../models/file_item.dart';

/// 压缩包格式选项（与面板 `pkg/io/compress.go` 支持的格式一致）。
class _ArchiveFormat {
  const _ArchiveFormat(this.ext, {this.singleOnly = false});

  final String ext;

  /// 单文件压缩格式（gzip/bzip2/xz/zstd）只能压缩一个文件。
  final bool singleOnly;
}

const List<_ArchiveFormat> _formats = [
  _ArchiveFormat('.zip'),
  _ArchiveFormat('.tar'),
  _ArchiveFormat('.tar.gz'),
  _ArchiveFormat('.tgz'),
  _ArchiveFormat('.tar.bz2'),
  _ArchiveFormat('.tar.xz'),
  _ArchiveFormat('.tar.zst'),
  _ArchiveFormat('.7z'),
  _ArchiveFormat('.gz', singleOnly: true),
  _ArchiveFormat('.bz2', singleOnly: true),
  _ArchiveFormat('.xz', singleOnly: true),
  _ArchiveFormat('.zst', singleOnly: true),
];

/// 压缩对话框，返回目标压缩包的**绝对路径**；取消时返回 null。
///
/// 面板接口 `POST /api/file/compress` 的 `paths` 是相对 `dir` 的名称，
/// 由调用方按当前目录下的选中项传入。
Future<String?> showCompressDialog(
  BuildContext context, {
  required String dir,
  required List<String> names,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _CompressDialog(dir: dir, names: names),
  );
}

class _CompressDialog extends StatefulWidget {
  const _CompressDialog({required this.dir, required this.names});

  final String dir;
  final List<String> names;

  @override
  State<_CompressDialog> createState() => _CompressDialogState();
}

class _CompressDialogState extends State<_CompressDialog> {
  late String _format;
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _format = '.zip';
    _controller = TextEditingController(text: _defaultName());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _defaultName() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rnd = Random();
    final suffix =
        List.generate(6, (_) => chars[rnd.nextInt(chars.length)]).join();
    final base = widget.names.length == 1
        ? widget.names.first
        : (posixBaseName(widget.dir) == '/'
            ? 'archive'
            : posixBaseName(widget.dir));
    return '$base-$suffix$_format';
  }

  void _applyFormat(String format) {
    setState(() {
      _format = format;
      final current = _controller.text.trim();
      final stripped = _stripKnownExtension(current);
      _controller.text = '$stripped$format';
      _error = null;
    });
  }

  static String _stripKnownExtension(String name) {
    for (final format in _formats) {
      if (name.toLowerCase().endsWith(format.ext)) {
        return name.substring(0, name.length - format.ext.length);
      }
    }
    return name;
  }

  void _submit() {
    var name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '文件名不能为空');
      return;
    }
    if (name.contains('/')) {
      setState(() => _error = '文件名不能包含 /');
      return;
    }
    if (!name.toLowerCase().endsWith(_format)) {
      name = '${_stripKnownExtension(name)}$_format';
    }
    Navigator.of(context).pop(posixJoin(widget.dir, name));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final multiple = widget.names.length > 1;
    return AlertDialog(
      title: const Text('压缩'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              multiple
                  ? '共 ${widget.names.length} 项，压缩包保存到 ${widget.dir}'
                  : '压缩「${widget.names.first}」，压缩包保存到 ${widget.dir}',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final format in _formats)
                  if (!(format.singleOnly && multiple))
                    ChoiceChip(
                      label: Text(format.ext),
                      selected: _format == format.ext,
                      onSelected: (_) => _applyFormat(format.ext),
                    ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              decoration: InputDecoration(
                labelText: '压缩包文件名',
                errorText: _error,
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
            const SizedBox(height: 8),
            Text(
              '压缩以后台任务执行，可在「任务」中查看进度。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('开始压缩')),
      ],
    );
  }
}

/// 解压对话框，返回解压目标目录的绝对路径；取消时返回 null。
Future<String?> showUnCompressDialog(
  BuildContext context, {
  required String archivePath,
  required String currentDir,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _UnCompressDialog(
      archivePath: archivePath,
      currentDir: currentDir,
    ),
  );
}

class _UnCompressDialog extends StatefulWidget {
  const _UnCompressDialog({
    required this.archivePath,
    required this.currentDir,
  });

  final String archivePath;
  final String currentDir;

  @override
  State<_UnCompressDialog> createState() => _UnCompressDialogState();
}

class _UnCompressDialogState extends State<_UnCompressDialog> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentDir);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty || !value.startsWith('/')) {
      setState(() => _error = '请输入绝对路径（以 / 开头）');
      return;
    }
    Navigator.of(context).pop(posixNormalize(value));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      // 路径长 / 键盘弹出时内容会超高，交给对话框自身滚动。
      scrollable: true,
      title: const Text('解压'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '解压「${widget.archivePath}」',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            decoration: InputDecoration(
              labelText: '解压到目录',
              errorText: _error,
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              ActionChip(
                label: const Text('当前目录'),
                onPressed: () => _controller.text = widget.currentDir,
              ),
              ActionChip(
                label: const Text('同名子目录'),
                onPressed: () => _controller.text = posixJoin(
                  widget.currentDir,
                  _stripArchiveExtension(posixBaseName(widget.archivePath)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '解压以后台任务执行，可在「任务」中查看进度。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('开始解压')),
      ],
    );
  }

  static String _stripArchiveExtension(String name) {
    final lower = name.toLowerCase();
    for (final ext in FileItem.archiveExtensions) {
      if (lower.endsWith(ext)) {
        return name.substring(0, name.length - ext.length);
      }
    }
    return name;
  }
}
