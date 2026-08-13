import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/api/api_exception.dart';
import '../models/upload_source.dart';
import '../repo/file_repo.dart';
import '../repo/transfer_client.dart';
import 'transfer_indicator.dart';

/// 一个待上传的文件。
class UploadJob {
  const UploadJob({
    required this.source,
    required this.targetName,
    this.force = false,
  });

  /// 数据源（本地文件或内存字节）。
  final UploadSource source;

  /// 写入服务器的文件名（冲突自动改名时与源文件名不同）。
  final String targetName;

  /// 是否覆盖服务器上的同名文件。
  final bool force;
}

/// 上传结果汇总。
class UploadOutcome {
  const UploadOutcome({
    required this.succeeded,
    required this.failures,
    required this.cancelled,
  });

  /// 成功上传的文件数。
  final int succeeded;

  /// 失败项，元素形如「文件名：原因」。
  final List<String> failures;

  /// 是否被用户取消。
  final bool cancelled;

  bool get allSucceeded => failures.isEmpty && !cancelled;
}

/// 展示上传进度对话框并实际执行上传，全部结束后自动关闭并返回结果。
///
/// 对话框不可点击遮罩关闭，用户可随时点「取消」中断（已完成的文件保留）。
Future<UploadOutcome?> showUploadProgressDialog(
  BuildContext context, {
  required FileRepo repo,
  required String dir,
  required List<UploadJob> jobs,
}) {
  return showDialog<UploadOutcome>(
    context: context,
    barrierDismissible: false,
    builder: (context) =>
        _UploadProgressDialog(repo: repo, dir: dir, jobs: jobs),
  );
}

class _UploadProgressDialog extends StatefulWidget {
  const _UploadProgressDialog({
    required this.repo,
    required this.dir,
    required this.jobs,
  });

  final FileRepo repo;
  final String dir;
  final List<UploadJob> jobs;

  @override
  State<_UploadProgressDialog> createState() => _UploadProgressDialogState();
}

class _UploadProgressDialogState extends State<_UploadProgressDialog> {
  final TransferCancelToken _cancelToken = TransferCancelToken();
  final List<String> _failures = [];

  Timer? _ticker;
  int _index = 0;
  int _succeeded = 0;
  int _currentSent = 0;
  int _currentTotal = 0;
  int _finishedBytes = 0;
  int _totalBytes = 0;
  double _speed = 0;
  bool _cancelled = false;
  bool _finished = false;

  int _lastSampleBytes = 0;
  int _lastSampleAt = 0;

  @override
  void initState() {
    super.initState();
    _totalBytes = widget.jobs.fold(0, (sum, job) => sum + job.source.size);
    _lastSampleAt = DateTime.now().millisecondsSinceEpoch;
    // 进度回调非常频繁，用定时器统一刷新 UI，避免每 64KB 触发一次重建。
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

  int get _transferred => _finishedBytes + _currentSent;

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
    for (var i = 0; i < widget.jobs.length; i++) {
      if (_cancelToken.isCancelled) break;
      final job = widget.jobs[i];
      _index = i;
      _currentSent = 0;
      _currentTotal = job.source.size;
      try {
        await widget.repo.uploadLocal(
          dir: widget.dir,
          source: job.source,
          fileName: job.targetName,
          force: job.force,
          cancelToken: _cancelToken,
          onProgress: (sent, total) {
            _currentSent = sent;
            _currentTotal = total;
          },
        );
        _succeeded++;
        _finishedBytes += job.source.size;
        _currentSent = 0;
      } on TransferCancelledException {
        break;
      } on ApiException catch (e) {
        _failures.add('${job.targetName}：${e.message}');
        _finishedBytes += job.source.size;
        _currentSent = 0;
      } catch (e) {
        // describeError：直接插值会把原始英文异常类型带到用户面前。
        _failures.add('${job.targetName}：${describeError(e)}');
        _finishedBytes += job.source.size;
        _currentSent = 0;
      } finally {
        await job.source.close();
      }
    }

    // 未走到的文件也要释放句柄。
    for (var i = _index + 1; i < widget.jobs.length; i++) {
      await widget.jobs[i].source.close();
    }

    _finished = true;
    _ticker?.cancel();
    if (!mounted) return;
    Navigator.of(context).pop(
      UploadOutcome(
        succeeded: _succeeded,
        failures: List.unmodifiable(_failures),
        cancelled: _cancelToken.isCancelled,
      ),
    );
  }

  void _cancel() {
    if (_cancelled || _finished) return;
    setState(() => _cancelled = true);
    _cancelToken.cancel();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final job = widget.jobs[_index.clamp(0, widget.jobs.length - 1)];
    final multiple = widget.jobs.length > 1;

    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('正在上传'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TransferIndicator(
                title: job.targetName,
                transferred: _currentSent,
                total: _currentTotal,
                speed: formatTransferSpeed(_speed),
                subtitle: multiple
                    ? '第 ${_index + 1} / ${widget.jobs.length} 个文件'
                    : null,
              ),
              if (multiple) ...[
                const SizedBox(height: 16),
                Text(
                  '总进度 ${formatTransferBytes(_transferred)} / '
                  '${formatTransferBytes(_totalBytes)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _totalBytes > 0
                        ? (_transferred / _totalBytes).clamp(0.0, 1.0)
                        : null,
                    minHeight: 4,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                _cancelled
                    ? '正在取消，等待当前请求结束…'
                    : '上传到 ${widget.dir}\n大文件将自动分片上传，中断后可重新上传续传。',
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
