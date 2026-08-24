import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/app_snack.dart';
import '../../../core/widgets/empty_view.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_view.dart';
import '../models/ssh_file_info.dart';
import '../models/ssh_host.dart';
import '../providers/ssh_hosts_providers.dart';
import '../widgets/sftp_file_tile.dart';
import '../widgets/sftp_path_bar.dart';
import '../widgets/ssh_feedback.dart';

/// 主机文件浏览（`/ssh-hosts/:id/files`）。
///
/// 对应面板接口 `GET /ssh/{id}/file`（浏览目录）与 `POST /ssh/{id}/mkdir`
/// （创建目录）；`id` 为 0 表示面板本机（`request.SSHFile` 的约定）。
/// 面板的 SFTP 接口只提供目录浏览与建目录，不含上传 / 下载 / 删除。
class SshSftpPage extends ConsumerStatefulWidget {
  const SshSftpPage({super.key, required this.hostId, this.initialPath = '/'});

  final int hostId;
  final String initialPath;

  @override
  ConsumerState<SshSftpPage> createState() => _SshSftpPageState();
}

class _SshSftpPageState extends ConsumerState<SshSftpPage> {
  late int _hostId = widget.hostId;
  late String _path = normalizePath(widget.initialPath);
  bool _busy = false;

  SftpQuery get _query => (hostId: _hostId, path: _path);

  String _hostLabel(List<SshHost> hosts) {
    if (_hostId == 0) return '面板本机';
    for (final host in hosts) {
      if (host.id == _hostId) return host.displayName;
    }
    return 'SSH 主机 #$_hostId';
  }

  void _navigateTo(String path) {
    final next = normalizePath(path);
    if (next == _path) return;
    setState(() => _path = next);
  }

  void _goUp() {
    if (_path == '/') return;
    _navigateTo(parentPath(_path));
  }

  void _switchHost(int hostId) {
    if (hostId == _hostId) return;
    setState(() {
      _hostId = hostId;
      _path = '/';
    });
  }

  /// 重新读取当前目录。
  ///
  /// invalidate 后 Riverpod 会保留上一份数据（AsyncLoading 携带旧值），
  /// 因此刷新期间列表不会闪回加载态，只在路径栏下方显示细进度条。
  Future<void> _refresh() async {
    final query = _query;
    ref.invalidate(sftpListingProvider(query));
    try {
      await ref.read(sftpListingProvider(query).future);
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, e);
    }
  }

  Future<void> _promptPath() async {
    final input = await showTextInputDialog(
      context,
      title: '跳转到目录',
      initialValue: _path,
      label: '绝对路径',
      hintText: '/opt',
      helperText: '以 / 开头的完整路径',
      confirmText: '前往',
      emptyError: '请输入目录路径',
    );
    if (input == null) return;
    _navigateTo(input);
  }

  Future<void> _mkdir() async {
    if (_busy) return;
    final currentPath = _path;
    final name = await showTextInputDialog(
      context,
      title: '新建目录',
      label: '目录名称',
      hintText: 'backup',
      helperText: '将创建在 $currentPath 下，支持多级（如 a/b）',
      confirmText: '创建',
      emptyError: '请输入目录名称',
    );
    if (name == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(sshHostsRepoProvider)
          .mkdir(hostId: _hostId, path: joinPath(currentPath, name));
      if (!mounted) return;
      showSuccessSnack(context, '目录「$name」已创建');
      // 刷新后再解除忙碌态，避免进度条先消失、列表却还是旧的。
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _onTapFile(SshFileInfo file) {
    if (file.navigable) {
      _navigateTo(joinPath(_path, file.name));
      return;
    }
    showSftpFileInfoDialog(context, file: file, directory: _path);
  }

  @override
  Widget build(BuildContext context) {
    final hosts = ref.watch(sshHostOptionsProvider).value ?? const [];
    final listing = ref.watch(sftpListingProvider(_query));
    final isRoot = _path == '/';
    // 已有数据时（下拉刷新 / 建目录后重载）保留列表，只用细进度条表示在加载。
    final reloading = listing.isLoading && listing.hasValue;

    return PopScope(
      canPop: isRoot,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _goUp();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_hostLabel(hosts)),
              Text(
                '文件浏览',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          actions: [
            A11yIconButton(
              tooltip: '返回上级目录',
              icon: const Icon(Icons.arrow_upward),
              onPressed: isRoot ? null : _goUp,
            ),
            A11yIconButton(
              tooltip: '在当前目录新建目录',
              icon: const Icon(Icons.create_new_folder_outlined),
              onPressed: _busy ? null : _mkdir,
            ),
            A11yIconButton(
              tooltip: '刷新当前目录',
              icon: const Icon(Icons.refresh),
              onPressed: _busy || reloading ? null : _refresh,
            ),
            PopupMenuButton<int>(
              tooltip: '切换主机',
              icon: const Icon(Icons.swap_horiz),
              onSelected: _switchHost,
              itemBuilder: (context) => [
                CheckedPopupMenuItem<int>(
                  value: 0,
                  checked: _hostId == 0,
                  child: const Text('面板本机'),
                ),
                for (final host in hosts)
                  CheckedPopupMenuItem<int>(
                    value: host.id,
                    checked: _hostId == host.id,
                    child: Text(
                      host.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ],
        ),
        body: Column(
          children: [
            SftpPathBar(
              path: _path,
              onNavigate: _navigateTo,
              onEditPath: _promptPath,
            ),
            // 建目录 / 刷新期间的细进度条，位置固定在路径栏下方，
            // 不占用列表高度突变（minHeight 2 的空白占位保持布局稳定）。
            SizedBox(
              height: 2,
              child: _busy || reloading
                  ? const LinearProgressIndicator(minHeight: 2)
                  : null,
            ),
            Expanded(child: _buildBody(listing)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(AsyncValue<List<SshFileInfo>> listing) {
    // 有数据就优先展示数据：刷新失败时列表不会被错误页顶掉，
    // 错误本身已由 _refresh 以 SnackBar 提示。
    if (listing.hasValue) return _buildList(listing.requireValue);
    if (listing.hasError) {
      return ErrorView(
        error: listing.error!,
        onRetry: () => ref.invalidate(sftpListingProvider(_query)),
      );
    }
    return const LoadingView(message: '正在读取目录…');
  }

  Widget _buildList(List<SshFileInfo> files) {
    if (files.isEmpty) {
      final isRoot = _path == '/';
      return RefreshIndicator(
        onRefresh: _refresh,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: EmptyView(
                message:
                    '$_path 下没有任何文件或目录\n'
                    '下拉可重新读取；也可以在这里新建目录',
                icon: Icons.folder_open_outlined,
                action: Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    if (!isRoot)
                      OutlinedButton.icon(
                        onPressed: _goUp,
                        icon: const Icon(Icons.arrow_upward),
                        label: const Text('返回上级'),
                      ),
                    FilledButton.tonalIcon(
                      onPressed: _busy ? null : _mkdir,
                      icon: const Icon(Icons.create_new_folder_outlined),
                      label: const Text('新建目录'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: files.length + 1,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) {
          if (index == files.length) {
            final theme = Theme.of(context);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  '共 ${files.length} 项',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            );
          }
          final file = files[index];
          return SftpFileTile(
            file: file,
            onTap: () => _onTapFile(file),
            onShowInfo: () =>
                showSftpFileInfoDialog(context, file: file, directory: _path),
          );
        },
      ),
    );
  }
}
