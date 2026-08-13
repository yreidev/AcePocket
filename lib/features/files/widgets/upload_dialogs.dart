import 'package:flutter/material.dart';

import '../../../core/utils/input_validation.dart';

/// 「上传 / 获取文件」入口的可选方式。
enum UploadMethod {
  /// 用系统文件选择器挑选手机本地文件上传
  /// （小文件 `POST /api/file/upload`，大文件走 `/api/file/chunk/*` 分片）。
  local,

  /// 粘贴文本内容，直接以 multipart 形式上传为文件（`POST /api/file/upload`）。
  text,

  /// 由面板通过 aria2 远程下载到服务器（`POST /api/file/remote_download`）。
  remote,
}

/// 展示「上传方式」选择面板。
Future<UploadMethod?> showUploadMethodSheet(BuildContext context) {
  return showModalBottomSheet<UploadMethod>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      final theme = Theme.of(context);
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.drive_folder_upload_outlined),
              title: const Text('从手机中选择文件上传'),
              subtitle: const Text('可多选，大文件自动分片上传，支持进度与取消'),
              onTap: () => Navigator.of(context).pop(UploadMethod.local),
            ),
            ListTile(
              leading: const Icon(Icons.text_snippet_outlined),
              title: const Text('粘贴文本内容上传'),
              subtitle: const Text('输入文件名与文本内容，直接上传为服务器文件'),
              onTap: () => Navigator.of(context).pop(UploadMethod.text),
            ),
            ListTile(
              leading: const Icon(Icons.cloud_download_outlined),
              title: const Text('远程下载到服务器'),
              subtitle: const Text('由面板用 aria2 从 URL 下载，后台任务执行'),
              onTap: () => Navigator.of(context).pop(UploadMethod.remote),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Text(
                '提示：上传大文件时请保持应用在前台，系统回收后台进程会中断传输；'
                '分片上传中断后重新选择同一文件会自动续传。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// 文本上传结果。
typedef TextUploadResult = ({String name, String content});

/// 「粘贴文本内容上传」对话框。
Future<TextUploadResult?> showTextUploadDialog(
  BuildContext context, {
  required String dir,
}) {
  return showDialog<TextUploadResult>(
    context: context,
    builder: (context) => _TextUploadDialog(dir: dir),
  );
}

class _TextUploadDialog extends StatefulWidget {
  const _TextUploadDialog({required this.dir});

  final String dir;

  @override
  State<_TextUploadDialog> createState() => _TextUploadDialogState();
}

class _TextUploadDialogState extends State<_TextUploadDialog> {
  final _nameController = TextEditingController();
  final _contentController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    final error = validateFileName(name);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop((name: name, content: _contentController.text));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      // 键盘弹出时内容区高度受限，允许滚动避免溢出。
      scrollable: true,
      title: const Text('上传文本文件'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '上传到 ${widget.dir}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              autofocus: true,
              decoration: InputDecoration(labelText: '文件名', errorText: _error),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _contentController,
              minLines: 5,
              maxLines: 12,
              keyboardType: TextInputType.multiline,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              decoration: const InputDecoration(
                labelText: '文件内容',
                alignLabelWithHint: true,
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
        FilledButton(onPressed: _submit, child: const Text('上传')),
      ],
    );
  }
}

/// 远程下载结果。
typedef RemoteDownloadResult = ({String name, String url});

/// 「远程下载到服务器」对话框。
Future<RemoteDownloadResult?> showRemoteDownloadDialog(
  BuildContext context, {
  required String dir,
}) {
  return showDialog<RemoteDownloadResult>(
    context: context,
    builder: (context) => _RemoteDownloadDialog(dir: dir),
  );
}

class _RemoteDownloadDialog extends StatefulWidget {
  const _RemoteDownloadDialog({required this.dir});

  final String dir;

  @override
  State<_RemoteDownloadDialog> createState() => _RemoteDownloadDialogState();
}

class _RemoteDownloadDialogState extends State<_RemoteDownloadDialog> {
  final _urlController = TextEditingController();
  final _nameController = TextEditingController();
  String? _urlError;
  String? _nameError;

  @override
  void dispose() {
    _urlController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  /// 从 URL 猜测文件名，方便用户直接使用。
  void _guessName(String url) {
    if (_nameController.text.trim().isNotEmpty) return;
    final uri = Uri.tryParse(url.trim());
    if (uri == null || uri.pathSegments.isEmpty) return;
    final last = uri.pathSegments.last;
    if (last.isNotEmpty) _nameController.text = last;
  }

  void _submit() {
    final url = _urlController.text.trim();
    final uri = Uri.tryParse(url);
    if (url.isEmpty || uri == null || !uri.hasScheme || !uri.hasAuthority) {
      setState(() => _urlError = '请输入合法的下载地址（http/https）');
      return;
    }
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = '请输入保存的文件名');
      return;
    }
    if (name.contains('/')) {
      setState(() => _nameError = '文件名不能包含 /');
      return;
    }
    Navigator.of(context).pop((name: name, url: url));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      scrollable: true,
      title: const Text('远程下载'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '保存到 ${widget.dir}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _urlController,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: '下载地址',
                hintText: 'https://example.com/file.tar.gz',
                errorText: _urlError,
              ),
              onChanged: (value) {
                _guessName(value);
                if (_urlError != null) setState(() => _urlError = null);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: '保存文件名',
                errorText: _nameError,
              ),
              onChanged: (_) {
                if (_nameError != null) setState(() => _nameError = null);
              },
            ),
            const SizedBox(height: 8),
            Text(
              '下载以后台任务执行，可在「任务」中查看进度。',
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
        FilledButton(onPressed: _submit, child: const Text('开始下载')),
      ],
    );
  }
}
