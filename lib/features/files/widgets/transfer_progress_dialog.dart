import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/api/api_exception.dart';
import '../repo/transfer_client.dart';
import 'transfer_indicator.dart';

/// 单次传输的执行体：把 [onProgress] 与 [cancelToken] 透传给底层传输客户端。
typedef TransferRunner =
    Future<void> Function({
      required TransferProgress onProgress,
      required TransferCancelToken cancelToken,
    });

/// 传输结果。
class TransferResult {
  const TransferResult({this.error, this.cancelled = false});

  /// 失败原因（可直接展示），成功时为 null。
  final String? error;

  /// 是否被用户取消。
  final bool cancelled;

  bool get succeeded => error == null && !cancelled;
}

/// 通用的单文件传输进度对话框（上传 / 下载均可用）。
///
/// 文件模块的多文件上传有自己的对话框；本对话框面向「一次传一个文件」的场景，
/// 例如备份文件的上传与下载，调用方只需提供 [runner]。
Future<TransferResult?> showTransferProgressDialog(
  BuildContext context, {
  required String title,
  required String fileName,
  required TransferRunner runner,
  int totalBytes = -1,
  String? hint,
}) {
  return showDialog<TransferResult>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _TransferProgressDialog(
      title: title,
      fileName: fileName,
      runner: runner,
      totalBytes: totalBytes,
      hint: hint,
    ),
  );
}

class _TransferProgressDialog extends StatefulWidget {
  const _TransferProgressDialog({
    required this.title,
    required this.fileName,
    required this.runner,
    required this.totalBytes,
    this.hint,
  });

  final String title;
  final String fileName;
  final TransferRunner runner;
  final int totalBytes;
  final String? hint;

  @override
  State<_TransferProgressDialog> createState() =>
      _TransferProgressDialogState();
}

class _TransferProgressDialogState extends State<_TransferProgressDialog> {
  final TransferCancelToken _cancelToken = TransferCancelToken();

  Timer? _ticker;
  int _transferred = 0;
  late int _total = widget.totalBytes;
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
    final delta = _transferred - _lastSampleBytes;
    _speed = delta <= 0 ? 0 : delta / elapsed;
    _lastSampleBytes = _transferred;
    _lastSampleAt = now;
  }

  Future<void> _run() async {
    TransferResult result;
    try {
      await widget.runner(
        onProgress: (transferred, total) {
          _transferred = transferred;
          if (total > 0) _total = total;
        },
        cancelToken: _cancelToken,
      );
      result = const TransferResult();
    } on TransferCancelledException {
      result = const TransferResult(cancelled: true);
    } catch (e) {
      // describeError：非 ApiException 时避免露出原始英文异常。
      result = TransferResult(error: describeError(e));
    }
    _finished = true;
    _ticker?.cancel();
    if (!mounted) return;
    Navigator.of(context).pop(result);
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
        title: Text(widget.title),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TransferIndicator(
                title: widget.fileName,
                transferred: _transferred,
                total: _total,
                speed: formatTransferSpeed(_speed),
              ),
              if (_cancelled || widget.hint != null) ...[
                const SizedBox(height: 12),
                Text(
                  _cancelled ? '正在取消，等待当前请求结束…' : widget.hint!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
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
