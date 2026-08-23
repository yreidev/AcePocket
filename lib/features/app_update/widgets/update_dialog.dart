/// 「发现新版本」对话框与 APK 下载安装流程。
///
/// 入口 [showAppUpdateDialog]：展示版本信息与变更日志，
/// 「稍后」记住被跳过的版本，「立即更新」进入下载进度对话框并安装。
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/format.dart';
import '../../../core/widgets/app_snack.dart';
import '../../app_settings/repo/app_settings_store.dart';
import '../models/app_update_models.dart';
import '../repo/apk_installer.dart';

/// 弹出「发现新版本」对话框。调用方自行决定是否弹（跳过版本的判断在调用方）。
Future<void> showAppUpdateDialog(
  BuildContext context,
  AppRelease release,
) async {
  final update = await showDialog<bool>(
    context: context,
    builder: (context) => _UpdateInfoDialog(release: release),
  );
  if (update != true || !context.mounted) return;
  await _startDownload(context, release);
}

/// 新版本信息对话框；pop true 表示用户点了「立即更新」。
class _UpdateInfoDialog extends StatelessWidget {
  const _UpdateInfoDialog({required this.release});

  final AppRelease release;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final publishedAt = release.publishedAt;
    final changelog = _cleanChangelog(release.body);
    return AlertDialog(
      title: Text('发现新版本 v${release.version}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (publishedAt != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                '发布时间：${DateFormat('yyyy-MM-dd HH:mm').format(publishedAt)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 300),
            child: SingleChildScrollView(
              child: Text(
                changelog.isEmpty ? '（无更新说明）' : changelog,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await AppSettingsStore.instance.saveSkippedUpdateVersion(
              release.version,
            );
            if (context.mounted) Navigator.of(context).pop(false);
          },
          child: const Text('稍后'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('立即更新'),
        ),
      ],
    );
  }
}

/// 变更日志纯文本清理：去掉行首的 Markdown 标题 / 列表标记，保留换行。
String _cleanChangelog(String body) {
  final lines = body.replaceAll('\r\n', '\n').split('\n');
  final cleaned = lines.map((line) {
    var s = line.replaceFirst(RegExp(r'^\s*#{1,6}\s+'), '');
    s = s.replaceFirstMapped(RegExp(r'^(\s*)[-*]\s+'), (m) => '${m[1]}• ');
    return s;
  });
  return cleaned.join('\n').trim();
}

/// 下载流程：选资产 → 进度对话框下载 → 安装；失败原因统一走 showErrorSnack。
Future<void> _startDownload(BuildContext context, AppRelease release) async {
  final asset = selectApkAsset(release.assets, preferArm64: isArm64Runtime());
  if (asset == null) {
    showErrorSnack(context, '未找到可用的安装包');
    return;
  }
  final result = await showDialog<_DownloadResult>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _DownloadProgressDialog(asset: asset),
  );
  if (!context.mounted || result == null) return;
  switch (result.kind) {
    case _DownloadResultKind.cancelled:
      // 用户主动取消，静默。
      break;
    case _DownloadResultKind.failed:
      showErrorSnack(context, '下载失败：${result.message}');
    case _DownloadResultKind.success:
      final error = await ApkInstaller().install(result.apkPath!);
      if (error != null && context.mounted) {
        showErrorSnack(context, error);
      }
  }
}

enum _DownloadResultKind { success, cancelled, failed }

/// 下载对话框的结束状态。
class _DownloadResult {
  const _DownloadResult.success(String this.apkPath)
    : kind = _DownloadResultKind.success,
      message = null;

  const _DownloadResult.cancelled()
    : kind = _DownloadResultKind.cancelled,
      apkPath = null,
      message = null;

  const _DownloadResult.failed(String this.message)
    : kind = _DownloadResultKind.failed,
      apkPath = null;

  final _DownloadResultKind kind;
  final String? apkPath;
  final String? message;
}

/// APK 下载进度对话框：进入即开始下载，结束时以 [_DownloadResult] pop。
class _DownloadProgressDialog extends StatefulWidget {
  const _DownloadProgressDialog({required this.asset});

  final ReleaseAsset asset;

  @override
  State<_DownloadProgressDialog> createState() =>
      _DownloadProgressDialogState();
}

class _DownloadProgressDialogState extends State<_DownloadProgressDialog> {
  final CancelToken _cancelToken = CancelToken();
  int _received = 0;
  int _total = -1;

  @override
  void initState() {
    super.initState();
    _startDownload();
  }

  @override
  void dispose() {
    // 对话框被意外销毁时终止下载，避免泄漏。
    if (!_cancelToken.isCancelled) {
      _cancelToken.cancel();
    }
    super.dispose();
  }

  Future<void> _startDownload() async {
    try {
      final path = await ApkInstaller().download(
        widget.asset,
        cancelToken: _cancelToken,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _received = received;
            _total = total;
          });
        },
      );
      if (mounted) {
        Navigator.of(context).pop(_DownloadResult.success(path));
      }
    } on ApkDownloadCancelledException {
      if (mounted) {
        Navigator.of(context).pop(const _DownloadResult.cancelled());
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(_DownloadResult.failed(e.toString()));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasTotal = _total > 0;
    final progress = hasTotal ? (_received / _total).clamp(0.0, 1.0) : null;
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('正在下载更新'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 12),
            Text(
              // 体积 / 百分比统一走 core/utils/format.dart，不再本地换算 MB。
              hasTotal
                  ? '${formatPercent(progress! * 100, fractionDigits: 0)}'
                        '（${formatBytes(_received, fractionDigits: 1)} / '
                        '${formatBytes(_total, fractionDigits: 1)}）'
                  : '正在下载…',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (!_cancelToken.isCancelled) {
                _cancelToken.cancel();
              }
            },
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }
}
