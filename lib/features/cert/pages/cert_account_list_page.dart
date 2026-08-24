import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/empty_view.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_view.dart';
import '../models/cert_account.dart';
import '../providers/cert_providers.dart';
import '../widgets/snack.dart';

/// CA 账户列表页 `/certs/accounts`。
///
/// 对应 GET /api/cert/account（ACME 账户，签发证书时必须关联）。
class CertAccountListPage extends ConsumerStatefulWidget {
  const CertAccountListPage({super.key});

  @override
  ConsumerState<CertAccountListPage> createState() =>
      _CertAccountListPageState();
}

class _CertAccountListPageState extends ConsumerState<CertAccountListPage> {
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
      await ref.read(certAccountListProvider.notifier).loadMore();
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  Future<void> _reloadQuietly() async {
    ref.invalidate(certOptionsProvider);
    try {
      await ref.read(certAccountListProvider.notifier).reload();
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  Future<void> _delete(CertAccount account) async {
    final ok = await showConfirmDialog(
      context,
      title: '删除 CA 账户',
      content: '确定要删除「${account.email}」吗？关联该账户的证书将无法继续签发与续签。',
      confirmText: '删除',
      danger: true,
    );
    if (!ok) return;
    setState(() => _busyId = account.id);
    try {
      await ref.read(certRepoProvider).deleteAccount(account.id);
      if (mounted) showSnack(context, '已删除');
      await _reloadQuietly();
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _openForm({int? id}) async {
    await context.push(
      id == null ? '/certs/accounts/create' : '/certs/accounts/$id/edit',
    );
    await _reloadQuietly();
  }

  @override
  Widget build(BuildContext context) {
    final listState = ref.watch(certAccountListProvider);
    final options = ref.watch(certOptionsProvider).value;

    return Scaffold(
      appBar: AppBar(title: const Text('CA 账户')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('新建'),
      ),
      body: listState.when(
        loading: () => const LoadingView(message: '正在加载账户…'),
        error: (error, _) => ErrorView(
          error: error,
          onRetry: () => ref.read(certAccountListProvider.notifier).refresh(),
        ),
        data: (state) {
          if (state.isEmpty) {
            return RefreshIndicator(
              onRefresh: () =>
                  ref.read(certAccountListProvider.notifier).refresh(),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(height: MediaQuery.of(context).size.height * 0.2),
                  EmptyView(
                    message: '还没有 CA 账户\n注册一个 Let\'s Encrypt 账户即可免费签发证书',
                    icon: Icons.account_circle_outlined,
                    action: FilledButton.icon(
                      onPressed: () => _openForm(),
                      icon: const Icon(Icons.add),
                      label: const Text('新建账户'),
                    ),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () =>
                ref.read(certAccountListProvider.notifier).refresh(),
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
                final account = state.items[index];
                final ca = options?.caLabel(account.ca) ?? account.caLabel;
                final created = account.createdAt == null
                    ? ''
                    : ' · ${DateFormat('yyyy-MM-dd').format(account.createdAt!)}';
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.secondaryContainer,
                    child: Icon(
                      Icons.verified_user_outlined,
                      color: Theme.of(context).colorScheme.onSecondaryContainer,
                    ),
                  ),
                  title: Text(
                    account.email,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '$ca · ${_keyTypeLabel(account.keyType)}$created',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: _busyId == account.id
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : PopupMenuButton<String>(
                          tooltip: '「${account.email}」的更多操作',
                          onSelected: (value) {
                            if (value == 'edit') {
                              _openForm(id: account.id);
                            } else if (value == 'delete') {
                              _delete(account);
                            }
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(value: 'edit', child: Text('编辑')),
                            PopupMenuItem(value: 'delete', child: Text('删除')),
                          ],
                        ),
                  onTap: () => _openForm(id: account.id),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

String _keyTypeLabel(String keyType) {
  switch (keyType) {
    case 'P256':
      return 'EC256';
    case 'P384':
      return 'EC384';
    case '2048':
      return 'RSA2048';
    case '3072':
      return 'RSA3072';
    case '4096':
      return 'RSA4096';
    default:
      return keyType;
  }
}
