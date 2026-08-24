import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/empty_view.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_view.dart';
import '../models/cert.dart';
import '../providers/cert_providers.dart';
import '../widgets/cert_content_dialog.dart';
import '../widgets/cert_tile.dart';
import '../widgets/deploy_sheet.dart';
import '../widgets/snack.dart';

/// 证书列表页 `/certs`。
class CertListPage extends ConsumerStatefulWidget {
  const CertListPage({super.key});

  @override
  ConsumerState<CertListPage> createState() => _CertListPageState();
}

class _CertListPageState extends ConsumerState<CertListPage> {
  final ScrollController _scrollController = ScrollController();

  /// 正在执行操作的证书 id（禁用该行按钮）。
  int? _busyId;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 240) {
      _loadMore();
    }
  }

  Future<void> _loadMore() =>
      // 失败会记录到 state.loadMoreError，由列表底部展示并可重试。
      ref.read(certListProvider.notifier).loadMore();

  Future<void> _refreshAll() async {
    ref.invalidate(certOptionsProvider);
    await ref.read(certListProvider.notifier).refresh();
  }

  /// 增删改之后静默刷新列表（保留旧数据，失败仅提示）。
  Future<void> _reloadQuietly() async {
    try {
      await ref.read(certListProvider.notifier).reload();
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  Future<void> _runBusy(int id, Future<void> Function() action) async {
    setState(() => _busyId = id);
    try {
      await action();
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _delete(CertListItem cert) async {
    final domain = cert.domains.isEmpty ? '该证书' : cert.domains.first;
    final ok = await showConfirmDialog(
      context,
      title: '删除证书',
      content: '确定要删除「$domain」吗？删除后无法恢复，已部署到网站的证书文件不会被移除。',
      confirmText: '删除',
      danger: true,
    );
    if (!ok) return;
    await _runBusy(cert.id, () async {
      await ref.read(certRepoProvider).deleteCert(cert.id);
      if (mounted) showSnack(context, '已删除');
      await _reloadQuietly();
    });
  }

  Future<void> _toggleAutoRenewal(CertListItem cert) async {
    await _runBusy(cert.id, () async {
      await ref
          .read(certRepoProvider)
          .updateCert(
            id: cert.id,
            type: cert.type,
            domains: cert.domains,
            alias: cert.alias,
            cert: cert.cert,
            key: cert.key,
            script: cert.script,
            autoRenewal: !cert.autoRenewal,
            accountId: cert.accountId,
            dnsId: cert.dnsId,
            websiteId: cert.websiteId,
          );
      if (mounted) {
        showSnack(context, cert.autoRenewal ? '已关闭自动续签' : '已开启自动续签');
      }
      await _reloadQuietly();
    });
  }

  Future<void> _deploy(CertListItem cert) async {
    final options = ref.read(certOptionsProvider).value;
    if (options == null) {
      showSnack(context, '网站列表尚未加载完成，请稍候重试', error: true);
      return;
    }
    final selection = await showDeployCertSheet(
      context,
      websites: options.websites,
      initialSelected: cert.websiteId == 0 ? const [] : [cert.websiteId],
    );
    if (selection == null) return;

    await _runBusy(cert.id, () async {
      for (final websiteId in selection.websiteIds) {
        await ref
            .read(certRepoProvider)
            .deploy(
              id: cert.id,
              websiteId: websiteId,
              enableHttps: selection.enableHttps,
            );
      }
      if (mounted) showSnack(context, '部署成功');
      await _reloadQuietly();
    });
  }

  // 子页面可能以 pushReplacement 的方式跳转（如创建后直接进入签发页），
  // 返回值不一定可靠，统一在返回时静默刷新列表。
  Future<void> _openObtain(CertListItem cert, {required bool renew}) async {
    await context.push(
      '/certs/${cert.id}/obtain?mode=${renew ? 'renew' : 'obtain'}',
    );
    await _reloadQuietly();
  }

  Future<void> _openEdit(CertListItem cert) async {
    await context.push('/certs/${cert.id}/edit');
    await _reloadQuietly();
  }

  Future<void> _openCreate() async {
    await context.push('/certs/create');
    await _reloadQuietly();
  }

  Future<void> _openUpload() async {
    await context.push('/certs/upload');
    await _reloadQuietly();
  }

  @override
  Widget build(BuildContext context) {
    final listState = ref.watch(certListProvider);
    final options = ref.watch(certOptionsProvider).value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('SSL 证书'),
        actions: [
          PopupMenuButton<String>(
            tooltip: '更多证书操作',
            onSelected: (value) async {
              switch (value) {
                case 'upload':
                  await _openUpload();
                case 'dns':
                  await context.push('/certs/dns');
                  ref.invalidate(certOptionsProvider);
                case 'account':
                  await context.push('/certs/accounts');
                  ref.invalidate(certOptionsProvider);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'upload',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.upload_file_outlined),
                  title: Text('上传证书'),
                ),
              ),
              PopupMenuItem(
                value: 'dns',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.dns_outlined),
                  title: Text('DNS 账号'),
                ),
              ),
              PopupMenuItem(
                value: 'account',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.account_circle_outlined),
                  title: Text('CA 账户'),
                ),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreate,
        icon: const Icon(Icons.add),
        label: const Text('申请证书'),
      ),
      body: listState.when(
        loading: () => const LoadingView(message: '正在加载证书…'),
        error: (error, _) => ErrorView(
          error: error,
          onRetry: () => ref.read(certListProvider.notifier).refresh(),
        ),
        data: (state) {
          if (state.isEmpty) {
            return RefreshIndicator(
              onRefresh: _refreshAll,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(height: MediaQuery.of(context).size.height * 0.2),
                  EmptyView(
                    message: '还没有证书\n可以申请 Let\'s Encrypt 免费证书，或上传已有证书',
                    icon: Icons.lock_outline,
                    action: FilledButton.icon(
                      onPressed: _openCreate,
                      icon: const Icon(Icons.add),
                      label: const Text('申请证书'),
                    ),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _refreshAll,
            child: ListView.builder(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(top: 4, bottom: 96),
              itemCount: state.items.length + 1,
              itemBuilder: (context, index) {
                if (index == state.items.length) {
                  return _ListFooter(
                    loading: state.loadingMore,
                    hasMore: state.hasMore,
                    total: state.total,
                    error: state.loadMoreError,
                    onRetry: _loadMore,
                  );
                }
                final cert = state.items[index];
                return CertTile(
                  cert: cert,
                  busy: _busyId == cert.id,
                  accountName: options == null || cert.accountId == 0
                      ? ''
                      : options.accountName(cert.accountId),
                  websiteName: options == null || cert.websiteId == 0
                      ? ''
                      : options.websiteName(cert.websiteId),
                  dnsName: options == null || cert.dnsId == 0
                      ? ''
                      : options.dnsName(cert.dnsId),
                  onObtain: () => _openObtain(cert, renew: false),
                  onRenew: () => _openObtain(cert, renew: true),
                  onDeploy: () => _deploy(cert),
                  onView: () => showCertContentDialog(
                    context,
                    cert: cert.cert,
                    key: cert.key,
                  ),
                  onEdit: () => _openEdit(cert),
                  onDelete: () => _delete(cert),
                  onToggleAutoRenewal: () => _toggleAutoRenewal(cert),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _ListFooter extends StatelessWidget {
  const _ListFooter({
    required this.loading,
    required this.hasMore,
    required this.total,
    required this.error,
    required this.onRetry,
  });

  final bool loading;
  final bool hasMore;
  final int total;

  /// 加载下一页失败时的错误（展示后可点击重试）。
  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!loading && error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Column(
          children: [
            Text(
              // 直接插值会把 `XxxException: ` 前缀暴露给用户。
              '加载失败：${errorMessage(error!)}',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              )
            : Text(
                hasMore ? '上拉加载更多' : '共 $total 张证书',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
      ),
    );
  }
}
