import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/app_snack.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/empty_view.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_view.dart';
import '../models/file_share.dart';
import '../providers/files_providers.dart';
import '../widgets/share_dialogs.dart';

/// 文件分享管理：列表、创建、复制链接、取消分享。
///
/// 对应面板 `internal/route/file_share.go`：
/// `GET /api/file_share`、`POST /api/file_share`、`DELETE /api/file_share/{id}`。
class FileSharesPage extends ConsumerStatefulWidget {
  const FileSharesPage({super.key, this.initialPath});

  /// 创建分享时预填的文件路径（从文件列表进入时携带）。
  final String? initialPath;

  @override
  ConsumerState<FileSharesPage> createState() => _FileSharesPageState();
}

class _FileSharesPageState extends ConsumerState<FileSharesPage> {
  bool _busy = false;

  /// 错误提示统一走 core 的 [showErrorSnack]（成对配色，深浅主题下都能看清）。
  void _error(Object error) {
    if (!mounted) return;
    showErrorSnack(context, error);
  }

  void _success(String message) {
    if (!mounted) return;
    showSuccessSnack(context, message);
  }

  Future<void> _refresh() async {
    ref.invalidate(fileSharesProvider);
    try {
      await ref.read(fileSharesProvider.future);
    } catch (_) {
      // 错误交由 ErrorView 展示。
    }
  }

  Future<void> _create() async {
    final form = await showShareCreateDialog(
      context,
      initialPath: widget.initialPath ?? '',
      pathEditable: true,
    );
    if (form == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final share = await ref
          .read(fileSharesProvider.notifier)
          .create(
            path: form.path,
            expireHours: form.expireHours,
            maxDownloads: form.maxDownloads,
          );
      if (!mounted) return;
      final url = ref.read(fileRepoProvider).shareDownloadUrl(share);
      await showShareLinkDialog(context, url: url);
    } catch (e) {
      _error(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(FileShare share) async {
    final ok = await showConfirmDialog(
      context,
      title: '取消分享',
      content: '确定要取消「${share.path}」的分享吗？\n该链接会立即失效，且无法恢复。',
      // 两个按钮都写「取消」会让人分不清哪个是执行、哪个是退出。
      confirmText: '确认取消分享',
      cancelText: '保留分享',
      danger: true,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(fileSharesProvider.notifier).remove(share.id);
      _success('分享已取消，链接已失效');
    } catch (e) {
      _error(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyLink(FileShare share) async {
    final url = ref.read(fileRepoProvider).shareDownloadUrl(share);
    await Clipboard.setData(ClipboardData(text: url));
    _success('下载链接已复制到剪贴板');
  }

  Widget _buildTile(FileShare share) {
    final theme = Theme.of(context);
    final url = ref.read(fileRepoProvider).shareDownloadUrl(share);
    final expiredAt = share.expiredAt;
    final formatter = DateFormat('yyyy-MM-dd HH:mm');
    final invalid = share.expired || share.exhausted;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    share.path,
                    style: theme.textTheme.titleSmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Chip(
                  label: Text(
                    share.expired ? '已过期' : (share.exhausted ? '次数已用尽' : '有效'),
                    style: theme.textTheme.labelSmall,
                  ),
                  visualDensity: VisualDensity.compact,
                  side: BorderSide.none,
                  backgroundColor: invalid
                      ? theme.colorScheme.errorContainer
                      : theme.colorScheme.secondaryContainer,
                ),
              ],
            ),
            const SizedBox(height: 6),
            SelectableText(
              url,
              // 分享链接可能很长（含访问入口），限制为 3 行避免单条卡片撑满整屏。
              maxLines: 3,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '已下载 ${share.downloads}'
              '${share.maxDownloads > 0 ? ' / ${share.maxDownloads} 次' : ' 次（不限次数）'}'
              ' · 到期时间 ${expiredAt == null ? '未设置' : formatter.format(expiredAt)}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: _busy ? null : () => _copyLink(share),
                  icon: const Icon(Icons.copy_all_outlined, size: 18),
                  label: const Text('复制链接'),
                ),
                TextButton.icon(
                  onPressed: _busy ? null : () => _delete(share),
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                  ),
                  icon: const Icon(Icons.link_off, size: 18),
                  label: const Text('取消分享'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sharesAsync = ref.watch(fileSharesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('文件分享'),
        actions: [
          A11yIconButton(
            tooltip: '刷新分享列表',
            icon: const Icon(Icons.refresh),
            onPressed: _busy ? null : _refresh,
          ),
        ],
        bottom: _busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _create,
        icon: const Icon(Icons.add_link),
        label: const Text('新建分享'),
      ),
      body: sharesAsync.when(
        loading: () => const LoadingView(message: '正在加载分享列表…'),
        error: (error, _) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(fileSharesProvider),
        ),
        data: (shares) {
          if (shares.isEmpty) {
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: 360,
                    child: EmptyView(
                      message:
                          '还没有创建任何分享链接\n'
                          '分享链接无需登录即可下载指定文件，可设置有效期与下载次数',
                      icon: Icons.link_off,
                      action: FilledButton.icon(
                        onPressed: _busy ? null : _create,
                        icon: const Icon(Icons.add_link),
                        label: const Text('新建分享'),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(top: 8, bottom: 88),
              itemCount: shares.length,
              itemBuilder: (context, index) => _buildTile(shares[index]),
            ),
          );
        },
      ),
    );
  }
}
