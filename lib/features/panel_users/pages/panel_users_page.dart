import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/version/panel_feature.dart';
import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/app_snack.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/feature_gate.dart';
import '../../../core/widgets/section_card.dart';
import '../models/panel_user.dart';
import '../providers/panel_user_providers.dart';
import '../widgets/paged_list_view.dart';
import '../widgets/panel_user_dialogs.dart';
import '../widgets/two_fa_dialog.dart';

final DateFormat _dateTimeFormat = DateFormat('yyyy-MM-dd HH:mm:ss');

/// 格式化面板返回的时间（模型里已 `toLocal()`）。
String formatDateTime(DateTime? time) =>
    time == null ? '-' : _dateTimeFormat.format(time);

/// 面板用户管理页（`/api/users` 系列接口）。
///
/// 功能：列表（分页 + 下拉刷新）、新建、改用户名 / 邮箱 / 密码、
/// 两步验证开关、删除，以及跳转通行密钥管理。
class PanelUsersPage extends ConsumerStatefulWidget {
  const PanelUsersPage({super.key});

  @override
  ConsumerState<PanelUsersPage> createState() => _PanelUsersPageState();
}

class _PanelUsersPageState extends ConsumerState<PanelUsersPage> {
  /// 正在执行操作的用户 ID（用于禁用控件并展示进度）。
  int? _busyUserId;

  bool _isBusy(int id) => _busyUserId == id;

  Future<void> _run(int userId, Future<void> Function() action) async {
    setState(() => _busyUserId = userId);
    try {
      await action();
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busyUserId = null);
    }
  }

  // ------------------------------------------------------------------ 操作

  Future<void> _create() async {
    final form = await showCreateUserDialog(context);
    if (form == null) return;
    await _run(-1, () async {
      await ref
          .read(panelUserRepoProvider)
          .create(
            username: form.username,
            password: form.password,
            email: form.email,
          );
      await ref.read(panelUsersProvider.notifier).refresh();
      if (mounted) showSuccessSnack(context, '用户 ${form.username} 已创建');
    });
  }

  Future<void> _renameUser(PanelUser user) async {
    final username = await showTextInputDialog(
      context,
      title: '修改用户名',
      initialValue: user.username,
      label: '用户名',
      helperText: '字母、数字、下划线与连字符，且不能与已有用户重复',
      validator: validateUsername,
    );
    if (username == null || username == user.username) return;
    await _run(user.id, () async {
      await ref.read(panelUserRepoProvider).updateUsername(user.id, username);
      ref
          .read(panelUsersProvider.notifier)
          .replace(user.copyWith(username: username));
      if (mounted) showSuccessSnack(context, '用户名已修改');
    });
  }

  Future<void> _changeEmail(PanelUser user) async {
    final email = await showTextInputDialog(
      context,
      title: '修改邮箱',
      initialValue: user.email,
      label: '邮箱',
      keyboardType: TextInputType.emailAddress,
      validator: validateEmail,
    );
    if (email == null || email == user.email) return;
    await _run(user.id, () async {
      await ref.read(panelUserRepoProvider).updateEmail(user.id, email);
      ref
          .read(panelUsersProvider.notifier)
          .replace(user.copyWith(email: email));
      if (mounted) showSuccessSnack(context, '邮箱已修改');
    });
  }

  Future<void> _changePassword(PanelUser user) async {
    final password = await showPasswordDialog(
      context,
      title: '修改 ${user.displayName} 的密码',
      helperText: '至少 8 位；修改后该用户的网页端会话需要重新登录',
    );
    if (password == null) return;
    await _run(user.id, () async {
      await ref.read(panelUserRepoProvider).updatePassword(user.id, password);
      if (mounted) {
        showSuccessSnack(context, '密码已修改，若该账号用于 App 的实时功能请同步更新服务器配置');
      }
    });
  }

  Future<void> _deleteUser(PanelUser user, {required bool isCurrent}) async {
    final confirmed = await showConfirmDialog(
      context,
      title: '删除用户 ${user.displayName}？',
      content:
          '删除后该用户的 API 令牌与通行密钥一并失效，且无法恢复。'
          '面板不允许删除最后一个用户。'
          // 删掉令牌归属用户 = 当场把自己踢下线，必须说明白。
          '${isCurrent ? '\n\n注意：这是本 App 当前 API 令牌的归属用户，删除后 App 将立即无法访问该面板，'
                    '需要用其他用户重新签发令牌。' : ''}',
      confirmText: '删除',
      danger: true,
    );
    if (!confirmed) return;
    await _run(user.id, () async {
      await ref.read(panelUserRepoProvider).delete(user.id);
      await ref.read(panelUsersProvider.notifier).refresh();
      if (mounted) showSuccessSnack(context, '用户已删除');
    });
  }

  Future<void> _toggleTwoFa(PanelUser user, bool enable) async {
    if (enable) {
      final secret = await showEnableTwoFaDialog(
        context,
        userId: user.id,
        username: user.displayName,
      );
      if (secret == null) return;
      ref
          .read(panelUsersProvider.notifier)
          .replace(user.copyWith(twoFaSecret: secret));
      if (mounted) showSuccessSnack(context, '两步验证已开启');
      return;
    }

    final confirmed = await showConfirmDialog(
      context,
      title: '关闭两步验证？',
      content: '关闭后 ${user.displayName} 登录面板将不再需要动态验证码，账号安全性降低。',
      confirmText: '关闭',
      danger: true,
    );
    if (!confirmed) return;
    await _run(user.id, () async {
      await ref.read(panelUserRepoProvider).updateTwoFa(user.id);
      ref
          .read(panelUsersProvider.notifier)
          .replace(user.copyWith(twoFaSecret: ''));
      if (mounted) showSuccessSnack(context, '两步验证已关闭');
    });
  }

  void _openPasskeys(PanelUser user) {
    context.push('/panel-users/passkey?user_id=${user.id}');
  }

  // ------------------------------------------------------------------ 构建

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(panelUsersProvider);
    final currentUser = ref.watch(currentPanelUserProvider).value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('面板用户'),
        actions: [
          A11yIconButton(
            tooltip: '管理通行密钥',
            icon: const Icon(Icons.fingerprint_rounded),
            onPressed: () => context.push('/panel-users/passkey'),
          ),
          A11yIconButton(
            tooltip: '刷新用户列表',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(panelUsersProvider);
              ref.invalidate(currentPanelUserProvider);
              ref.invalidate(wsAccountStatusProvider);
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busyUserId == -1 ? null : _create,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('新建用户'),
      ),
      body: Column(
        children: [
          const FeatureUnsupportedBanner(feature: PanelFeature.panelUsers),
          Expanded(
            child: PagedListView<PanelUser>(
              state: state,
              header: const _HeaderNotice(),
              onRefresh: () async {
                ref.invalidate(currentPanelUserProvider);
                ref.invalidate(wsAccountStatusProvider);
                try {
                  await ref.read(panelUsersProvider.notifier).refresh();
                } catch (e) {
                  // 用 State.context（而非 build 的参数）配合 State.mounted，避免跨异步间隙误用。
                  if (mounted) {
                    showErrorSnack(this.context, e);
                  }
                }
              },
              onLoadMore: () =>
                  ref.read(panelUsersProvider.notifier).loadMore(),
              onRetry: () => ref.invalidate(panelUsersProvider),
              emptyMessage: '暂无面板用户',
              emptyIcon: Icons.person_outline,
              totalLabel: (total) => '共 $total 个用户',
              itemBuilder: (context, user, index) => _UserCard(
                user: user,
                isCurrent: currentUser != null && currentUser.id == user.id,
                busy: _isBusy(user.id),
                onRename: () => _renameUser(user),
                onChangeEmail: () => _changeEmail(user),
                onChangePassword: () => _changePassword(user),
                onDelete: () => _deleteUser(
                  user,
                  isCurrent: currentUser != null && currentUser.id == user.id,
                ),
                onToggleTwoFa: (value) => _toggleTwoFa(user, value),
                onPasskeys: () => _openPasskeys(user),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 列表顶部说明 + App 会话账号状态。
class _HeaderNotice extends ConsumerWidget {
  const _HeaderNotice();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final account = ref.watch(wsAccountStatusProvider).value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline,
                color: theme.colorScheme.primary,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '面板用户用于登录面板网页端与签发 API 令牌。'
                  '两步验证开启后，网页端登录与 App 的终端等实时功能都需要动态验证码。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (account != null)
          SectionCard(
            title: 'App 实时功能使用的账号',
            child: Row(
              children: [
                Icon(
                  account.twoFaEnabled
                      ? Icons.verified_user_outlined
                      : Icons.account_circle_outlined,
                  size: 20,
                  color: account.twoFaEnabled
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    account.twoFaEnabled
                        ? '${account.username}（已开启两步验证）\n'
                              '连接终端 / SSH / 实时日志时会要求输入动态验证码。'
                        : '${account.username}（未开启两步验证）',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 单个用户卡片。
class _UserCard extends StatelessWidget {
  const _UserCard({
    required this.user,
    required this.isCurrent,
    required this.busy,
    required this.onRename,
    required this.onChangeEmail,
    required this.onChangePassword,
    required this.onDelete,
    required this.onToggleTwoFa,
    required this.onPasskeys,
  });

  final PanelUser user;

  /// 是否为当前 App 所用 API 令牌的归属用户。
  final bool isCurrent;
  final bool busy;

  final VoidCallback onRename;
  final VoidCallback onChangeEmail;
  final VoidCallback onChangePassword;
  final VoidCallback onDelete;
  final ValueChanged<bool> onToggleTwoFa;
  final VoidCallback onPasskeys;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: colorScheme.primaryContainer,
                child: Icon(
                  Icons.person_outline,
                  size: 20,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            user.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        if (isCurrent) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.secondaryContainer,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '当前令牌',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colorScheme.onSecondaryContainer,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      user.email.isEmpty ? '未设置邮箱' : user.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              // 进度指示器与「更多操作」按钮占同样的 48dp 见方，避免行内跳动。
              if (busy)
                minTouchTarget(
                  child: const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                PopupMenuButton<String>(
                  tooltip: '更多操作',
                  onSelected: (value) {
                    switch (value) {
                      case 'username':
                        onRename();
                      case 'email':
                        onChangeEmail();
                      case 'password':
                        onChangePassword();
                      case 'passkey':
                        onPasskeys();
                      case 'delete':
                        onDelete();
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'username',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        leading: Icon(Icons.badge_outlined),
                        title: Text('修改用户名'),
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'email',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        leading: Icon(Icons.alternate_email),
                        title: Text('修改邮箱'),
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'password',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        leading: Icon(Icons.password_outlined),
                        title: Text('修改密码'),
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'passkey',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        leading: Icon(Icons.fingerprint_rounded),
                        title: Text('通行密钥'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        leading: Icon(
                          Icons.delete_outline,
                          color: colorScheme.error,
                        ),
                        title: Text(
                          '删除用户',
                          style: TextStyle(color: colorScheme.error),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const Divider(height: 20),
          // 列表里每张卡片都有一个「两步验证」开关，读屏只念「两步验证」无法
          // 分辨改的是哪个用户；补上用户名（开 / 关状态由 Switch 自己播报）。
          a11ySwitch(
            label: '${user.displayName} 的两步验证',
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('两步验证'),
              subtitle: Text(
                user.twoFaEnabled ? '已开启（登录需动态验证码）' : '未开启',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: user.twoFaEnabled
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
              ),
              value: user.twoFaEnabled,
              onChanged: busy ? null : onToggleTwoFa,
            ),
          ),
          Row(
            children: [
              Icon(
                Icons.schedule,
                size: 14,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '创建于 ${formatDateTime(user.createdAt)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Text(
                'ID ${user.id}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
