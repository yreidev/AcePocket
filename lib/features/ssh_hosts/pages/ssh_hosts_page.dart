import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/version/panel_feature.dart';
import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/app_snack.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/feature_gate.dart';
import '../models/ssh_host.dart';
import '../providers/ssh_hosts_providers.dart';
import '../widgets/paged_list_view.dart';
import '../widgets/ssh_host_tile.dart';

/// SSH 主机列表页（`/ssh-hosts`）。
///
/// 对应面板 `internal/route/ssh.go`：列表 / 新建 / 编辑 / 删除，
/// 并提供跳转终端（复用 terminal 模块的 `/terminal?ssh=<id>`）与 SFTP 文件浏览。
class SshHostsPage extends ConsumerStatefulWidget {
  const SshHostsPage({super.key});

  @override
  ConsumerState<SshHostsPage> createState() => _SshHostsPageState();
}

class _SshHostsPageState extends ConsumerState<SshHostsPage> {
  /// 正在执行删除的主机 id，用于禁用重复点击。
  int? _deletingId;

  /// 重新拉取列表（下拉刷新 / 刷新按钮 / 增删改之后）。
  ///
  /// 走 Notifier 的 refresh 而非 invalidate：失败时保留现有列表并提示，
  /// 不会把整页打回加载态。
  Future<void> _refresh() async {
    ref.invalidate(sshHostOptionsProvider);
    try {
      await ref.read(sshHostsProvider.notifier).refresh();
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, e);
    }
  }

  /// 首屏加载失败后的重试：整页回到加载态重新请求。
  void _retry() {
    ref.invalidate(sshHostsProvider);
    ref.invalidate(sshHostOptionsProvider);
  }

  Future<void> _create() async {
    final created = await context.push<bool>('/ssh-hosts/new');
    if (created == true) await _refresh();
  }

  Future<void> _edit(SshHost host) async {
    final updated = await context.push<bool>('/ssh-hosts/${host.id}/edit');
    if (updated == true) await _refresh();
  }

  void _openTerminal(SshHost host) {
    // terminal 模块约定：`/terminal?ssh=<主机 id>&title=<标题>`
    // （见 lib/features/terminal/models/terminal_session_spec.dart）。
    final uri = Uri(
      path: '/terminal',
      queryParameters: {'ssh': host.id.toString(), 'title': host.displayName},
    );
    context.push(uri.toString());
  }

  void _openFiles(SshHost host) {
    context.push('/ssh-hosts/${host.id}/files');
  }

  void _openLocalFiles() {
    // 面板源码 `request.SSHFile` 约定：id 为 0 表示面板本机。
    context.push('/ssh-hosts/0/files');
  }

  Future<void> _delete(SshHost host) async {
    // 删除在途时忽略重复触发，避免对同一主机发出多次 DELETE。
    if (_deletingId != null) return;
    final confirmed = await showConfirmDialog(
      context,
      title: '删除主机「${host.displayName}」？',
      content: '删除后该主机的连接信息（含密码 / 私钥）将从面板移除，不可恢复。',
      confirmText: '删除',
      danger: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _deletingId = host.id);
    try {
      await ref.read(sshHostsRepoProvider).delete(host.id);
      if (!mounted) return;
      showSuccessSnack(context, '主机「${host.displayName}」已删除');
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _deletingId = null);
    }
  }

  void _onAction(SshHost host, SshHostAction action) {
    switch (action) {
      case SshHostAction.terminal:
        _openTerminal(host);
      case SshHostAction.files:
        _openFiles(host);
      case SshHostAction.edit:
        _edit(host);
      case SshHostAction.delete:
        _delete(host);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(sshHostsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('SSH 主机'),
        actions: [
          A11yIconButton(
            tooltip: '浏览面板本机文件',
            icon: const Icon(Icons.folder_special_outlined),
            onPressed: _openLocalFiles,
          ),
          A11yIconButton(
            tooltip: '刷新主机列表',
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('新建主机'),
      ),
      body: Column(
        children: [
          const FeatureUnsupportedBanner(feature: PanelFeature.sshHosts),
          if (_deletingId != null) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: PagedListView<SshHost>(
              state: state,
              onRefresh: _refresh,
              onLoadMore: () => ref.read(sshHostsProvider.notifier).loadMore(),
              onRetry: _retry,
              emptyMessage: '还没有保存任何 SSH 主机\n新建后可一键打开终端、浏览远程文件',
              emptyIcon: Icons.dns_outlined,
              emptyAction: FilledButton.icon(
                onPressed: _create,
                icon: const Icon(Icons.add),
                label: const Text('新建主机'),
              ),
              totalLabel: (total) => '共 $total 台主机',
              itemBuilder: (context, host, index) => SshHostTile(
                host: host,
                busy: _deletingId == host.id,
                onAction: (action) => _onAction(host, action),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
