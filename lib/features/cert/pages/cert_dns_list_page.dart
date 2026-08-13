import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/empty_view.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_view.dart';
import '../models/cert_dns.dart';
import '../providers/cert_providers.dart';
import '../widgets/snack.dart';

/// DNS 账号列表页 `/certs/dns`。
///
/// 对应 GET /api/cert/dns（DNS 验证签发证书时使用的解析商 API 凭据）。
class CertDnsListPage extends ConsumerStatefulWidget {
  const CertDnsListPage({super.key});

  @override
  ConsumerState<CertDnsListPage> createState() => _CertDnsListPageState();
}

class _CertDnsListPageState extends ConsumerState<CertDnsListPage> {
  final ScrollController _scrollController = ScrollController();
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
    if (position.pixels >= position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    try {
      await ref.read(certDnsListProvider.notifier).loadMore();
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  Future<void> _reloadQuietly() async {
    ref.invalidate(certOptionsProvider);
    try {
      await ref.read(certDnsListProvider.notifier).reload();
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  Future<void> _delete(CertDns dns) async {
    final ok = await showConfirmDialog(
      context,
      title: '删除 DNS 账号',
      content: '确定要删除「${dns.name}」吗？使用该账号签发的证书将无法自动续签。',
      confirmText: '删除',
      danger: true,
    );
    if (!ok) return;
    setState(() => _busyId = dns.id);
    try {
      await ref.read(certRepoProvider).deleteDns(dns.id);
      if (mounted) showSnack(context, '已删除');
      await _reloadQuietly();
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _openForm({int? id}) async {
    await context
        .push(id == null ? '/certs/dns/create' : '/certs/dns/$id/edit');
    await _reloadQuietly();
  }

  @override
  Widget build(BuildContext context) {
    final listState = ref.watch(certDnsListProvider);
    final options = ref.watch(certOptionsProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('DNS 账号')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('新建'),
      ),
      body: listState.when(
        loading: () => const LoadingView(message: '正在加载 DNS 账号…'),
        error: (error, _) => ErrorView(
          error: error,
          onRetry: () => ref.read(certDnsListProvider.notifier).refresh(),
        ),
        data: (state) {
          if (state.isEmpty) {
            return RefreshIndicator(
              onRefresh: () => ref.read(certDnsListProvider.notifier).refresh(),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(height: MediaQuery.of(context).size.height * 0.2),
                  EmptyView(
                    message: '还没有 DNS 账号\n添加后即可通过 DNS 验证签发泛域名证书',
                    icon: Icons.dns_outlined,
                    action: FilledButton.icon(
                      onPressed: () => _openForm(),
                      icon: const Icon(Icons.add),
                      label: const Text('新建 DNS 账号'),
                    ),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () => ref.read(certDnsListProvider.notifier).refresh(),
            child: ListView.separated(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 96),
              itemCount: state.items.length + (state.hasMore ? 1 : 0),
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                if (index >= state.items.length) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    ),
                  );
                }
                final dns = state.items[index];
                final provider =
                    options?.dnsProviderLabel(dns.type) ?? dns.typeLabel;
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor:
                        Theme.of(context).colorScheme.primaryContainer,
                    child: Icon(
                      Icons.dns_outlined,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                  title: Text(
                    dns.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '$provider · 验证服务器 ${dns.data.dnsServer}'
                    '${dns.data.skipVerify ? ' · 跳过验证' : ''}',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: _busyId == dns.id
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : PopupMenuButton<String>(
                          tooltip: '「${dns.name}」的更多操作',
                          onSelected: (value) {
                            if (value == 'edit') {
                              _openForm(id: dns.id);
                            } else if (value == 'delete') {
                              _delete(dns);
                            }
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(value: 'edit', child: Text('编辑')),
                            PopupMenuItem(value: 'delete', child: Text('删除')),
                          ],
                        ),
                  onTap: () => _openForm(id: dns.id),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
