import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/api/api_exception.dart';
import '../repo/transfer_client.dart';
import 'transfer_indicator.dart';

/// 下载结果。
class DownloadOutcome {
  const DownloadOutcome({this.file, this.error, this.cancelled = false});

  /// 成功时保存到本地的文件。
  final File? file;

  /// 失败原因（可直接展示）。
  final String? error;

  /// 是否被用户取消。
  final bool cancelled;
}

/// 下载执行器：由调用方提供实际的下载动作（文件模块 / 备份模块通用）。
///
/// [savePath] 为本对话框算好的本地保存路径，[onProgress] 与 [cancelToken]
/// 需要透传给底层传输客户端。
typedef DownloadRunner =
    Future<File> Function({
      required String savePath,
      required TransferProgress onProgress,
      required TransferCancelToken cancelToken,
    });

/// 展示下载进度对话框并实际执行下载，结束后返回结果。
///
/// 保存目录由 [resolveDownloadDirectory] 决定，重名时自动追加 `-1`、`-2`…
Future<DownloadOutcome?> showDownloadProgressDialog(
  BuildContext context, {
  required String fileName,
  required DownloadRunner runner,
}) {
  return showDialog<DownloadOutcome>(
    context: context,
    barrierDismissible: false,
    builder: (context) =>
        _DownloadProgressDialog(fileName: fileName, runner: runner),
  );
}

class _DownloadProgressDialog extends StatefulWidget {
  const _DownloadProgressDialog({required this.fileName, required this.runner});

  final String fileName;
  final DownloadRunner runner;

  @override
  State<_DownloadProgressDialog> createState() =>
      _DownloadProgressDialogState();
}

class _DownloadProgressDialogState extends State<_DownloadProgressDialog> {
  final TransferCancelToken _cancelToken = TransferCancelToken();

  Timer? _ticker;
  int _received = 0;
  int _total = -1;
  double _speed = 0;
  bool _cancelled = false;
  bool _finished = false;

  int _lastSampleBytes = 0;
  int _lastSampleAt = 0;

  @override
  void initState() {
    super.initState();
    _lastSampleAt = DateTime.now().millisecondsSinceEpoch;
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted || _finished) return;
      _sampleSpeed();
      setState(() {});
    });
    unawaited(_run());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _sampleSpeed() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final elapsed = (now - _lastSampleAt) / 1000;
    if (elapsed < 0.25) return;
    final delta = _received - _lastSampleBytes;
    _speed = delta <= 0 ? 0 : delta / elapsed;
    _lastSampleBytes = _received;
    _lastSampleAt = now;
  }

  Future<void> _run() async {
    DownloadOutcome outcome;
    try {
      final dir = await resolveDownloadDirectory();
      final savePath = await uniqueLocalPath(dir, widget.fileName);
      final file = await widget.runner(
        savePath: savePath,
        onProgress: (received, total) {
          _received = received;
          _total = total;
        },
        cancelToken: _cancelToken,
      );
      outcome = DownloadOutcome(file: file);
    } on TransferCancelledException {
      outcome = const DownloadOutcome(cancelled: true);
    } catch (e) {
      // describeError：非 ApiException 时避免露出原始英文异常。
      outcome = DownloadOutcome(error: describeError(e));
    }
    _finished = true;
    _ticker?.cancel();
    if (!mounted) return;
    Navigator.of(context).pop(outcome);
  }

  void _cancel() {
    if (_cancelled || _finished) return;
    setState(() => _cancelled = true);
    _cancelToken.cancel();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('正在下载'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TransferIndicator(
                title: widget.fileName,
                transferred: _received,
                total: _total,
                speed: formatTransferSpeed(_speed),
              ),
              const SizedBox(height: 12),
              Text(
                _cancelled ? '正在取消…' : '文件将保存到手机的应用目录中，完成后可用其他应用打开。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _cancelled ? null : _cancel,
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }
}

/// 下载完成提示：展示本地保存路径，并提供「用其他应用打开」与复制路径。
Future<void> showDownloadResultDialog(
  BuildContext context, {
  required File file,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _DownloadResultDialog(file: file),
  );
}

class _DownloadResultDialog extends StatefulWidget {
  const _DownloadResultDialog({required this.file});

  final File file;

  @override
  State<_DownloadResultDialog> createState() => _DownloadResultDialogState();
}

class _DownloadResultDialogState extends State<_DownloadResultDialog> {
  String? _hint;
  bool _hintIsError = false;
  bool _opening = false;

  Future<void> _open() async {
    setState(() {
      _opening = true;
      _hint = null;
    });
    final error = await openLocalFile(widget.file.path);
    if (!mounted) return;
    setState(() {
      _opening = false;
      _hint = error;
      _hintIsError = error != null;
    });
  }

  Future<void> _copyPath() async {
    await Clipboard.setData(ClipboardData(text: widget.file.path));
    if (!mounted) return;
    setState(() {
      _hint = '路径已复制到剪贴板';
      _hintIsError = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      // 保存路径较长时内容可能超出屏幕高度。
      scrollable: true,
      title: const Text('下载完成'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('已保存到：', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 6),
            SelectableText(
              widget.file.path,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (_hint != null) ...[
              const SizedBox(height: 12),
              Text(
                _hint!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: _hintIsError
                      ? theme.colorScheme.error
                      : theme.colorScheme.primary,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _copyPath, child: const Text('复制路径')),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
        FilledButton(
          onPressed: _opening ? null : _open,
          child: Text(_opening ? '打开中…' : '用其他应用打开'),
        ),
      ],
    );
  }
}
