import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/version/panel_feature.dart';
import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/app_snack.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/empty_view.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/feature_gate.dart';
import '../../../core/widgets/loading_view.dart';
import '../../../core/widgets/section_card.dart';
import '../models/panel_user.dart';
import '../models/passkey.dart';
import '../providers/panel_user_providers.dart';
import 'panel_users_page.dart' show formatDateTime;

/// 通行密钥（Passkey）管理页。
///
/// 面板侧接口：
/// - `GET /api/user_passkeys/supported`：面板是否满足通行密钥条件（可信 HTTPS）；
/// - `GET /api/user/passkey/enabled`：面板中是否已存在任意通行密钥；
/// - `GET /api/user_passkeys?user_id=`：某用户的通行密钥列表；
/// - `DELETE /api/user_passkeys/{id}?user_id=`：删除（`user_id` 走 query，
///   由 `ApiClient.delete(query:)` 传入并参与 HMAC 签名）。
///
/// 注册（`POST/PUT /api/user/passkey/register`）与通行密钥登录
/// （`POST/PUT /api/user/passkey/login`）依赖浏览器 WebAuthn（navigator.credentials），
/// App 内无法完成，因此本页只提供**查看与停用**，并引导用户到网页端注册。
class PasskeyPage extends ConsumerStatefulWidget {
  const PasskeyPage({super.key, this.initialUserId});

  /// 从用户列表跳转时带入的用户 ID。
  final int? initialUserId;

  @override
  ConsumerState<PasskeyPage> createState() => _PasskeyPageState();
}

class _PasskeyPageState extends ConsumerState<PasskeyPage> {
  int? _userId;
  int? _deletingId;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialUserId;
    if (initial != null && initial > 0) _userId = initial;
  }

  /// 当前选中的用户；未显式选择时回落到 API 令牌所属用户。
  int? _resolveUserId(PanelUserInfo? current) {
    if (_userId != null && _userId! > 0) return _userId;
    if (current != null && current.id > 0) return current.id;
    return null;
  }

  Future<void> _delete(Passkey passkey) async {
    final confirmed = await showConfirmDialog(
      context,
      title: '删除通行密钥？',
      content:
          '「${passkey.name.isEmpty ? '未命名' : passkey.name}」删除后，'
          '该设备将无法再用于免密登录面板。',
      confirmText: '删除',
      danger: true,
    );
    if (!confirmed) return;

    setState(() => _deletingId = passkey.id);
    try {
      // user_id 走 query 传给面板（ApiClient.delete 支持 query 且会正确参与
      // HMAC 签名），因此管理员可以删除任意用户的通行密钥。
      await ref
          .read(panelUserRepoProvider)
          .deletePasskey(passkey.id, userId: passkey.userId);
      ref.invalidate(passkeyListProvider(passkey.userId));
      ref.invalidate(passkeyStatusProvider);
      if (mounted) showSuccessSnack(context, '通行密钥已删除');
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _deletingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentAsync = ref.watch(currentPanelUserProvider);
    final current = currentAsync.value;
    final userId = _resolveUserId(current);

    return Scaffold(
      appBar: AppBar(
        title: const Text('通行密钥'),
        actions: [
          A11yIconButton(
            tooltip: '刷新通行密钥信息',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(passkeyStatusProvider);
              ref.invalidate(panelUserOptionsProvider);
              ref.invalidate(currentPanelUserProvider);
              if (userId != null) ref.invalidate(passkeyListProvider(userId));
            },
          ),
        ],
      ),
      body: Column(
        children: [
          const FeatureUnsupportedBanner(feature: PanelFeature.passkey),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(passkeyStatusProvider);
                ref.invalidate(panelUserOptionsProvider);
                ref.invalidate(currentPanelUserProvider);
                if (userId != null) ref.invalidate(passkeyListProvider(userId));
                try {
                  await ref.read(passkeyStatusProvider.future);
                } catch (_) {
                  // 失败由状态卡片自己的 ErrorView 展示；异常若抛回
                  // RefreshIndicator 会变成未捕获的 zone 异常。
                }
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(top: 6, bottom: 32),
                children: [
                  _statusCard(),
                  _noticeCard(),
                  _userSelector(userId),
                  if (userId == null)
                    _userFallbackCard(currentAsync)
                  else
                    _passkeyList(userId),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------- 用户兜底卡片

  /// 还没确定要查看哪个用户时的占位：区分「读取中」「读取失败」「取不到用户」，
  /// 避免 `GET /api/user/info` 失败后永远停在一个转不完的菊花上。
  Widget _userFallbackCard(AsyncValue<PanelUserInfo> currentAsync) {
    final error = currentAsync.error;
    if (error != null) {
      return SectionCard(
        child: ErrorView(
          error: error,
          onRetry: () => ref.invalidate(currentPanelUserProvider),
        ),
      );
    }
    if (!currentAsync.isLoading) {
      return const SectionCard(
        child: EmptyView(
          message: '未能确定要查看的用户\n请在上方选择一个面板用户',
          icon: Icons.person_search_outlined,
        ),
      );
    }
    return const SectionCard(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: LoadingView(message: '读取用户信息…'),
      ),
    );
  }

  // ------------------------------------------------------------------ 状态卡片

  Widget _statusCard() {
    final statusAsync = ref.watch(passkeyStatusProvider);
    final theme = Theme.of(context);

    return SectionCard(
      title: '面板状态',
      child: statusAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: LoadingView(),
        ),
        // 不能套固定高度的 SizedBox：ErrorView 光是图标 + 间距 + 重试按钮就要
        // 200dp 以上，固定高度会把错误文案裁掉、「重试」按钮完全看不见也点不到。
        error: (error, _) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(passkeyStatusProvider),
        ),
        data: (status) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StatusRow(
              icon: Icons.https_outlined,
              label: '面板支持通行密钥',
              value: status.supported ? '支持' : '不支持',
              ok: status.supported,
              hint: status.supported
                  ? null
                  : '通行密钥要求面板通过可信 HTTPS 访问（自签名证书不可用），'
                        '可为面板配置受信任证书或用反向代理终止 TLS。',
            ),
            const SizedBox(height: 8),
            _StatusRow(
              icon: Icons.fingerprint_rounded,
              label: '已注册通行密钥',
              value: status.enabled ? '已启用' : '未启用',
              ok: status.enabled,
              hint: status.enabled ? null : '面板中还没有任何通行密钥，登录页不会显示通行密钥入口。',
            ),
            const SizedBox(height: 4),
            Text(
              '注：「已注册」为整个面板的全局状态（GET /api/user/passkey/enabled）。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ 说明卡片

  Widget _noticeCard() {
    final theme = Theme.of(context);
    return SectionCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: theme.colorScheme.primary, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '通行密钥的注册与登录依赖浏览器的 WebAuthn 能力，App 内无法完成。'
              '请在网页端「设置 → 用户 → 通行密钥」中用本机指纹 / 面容或安全密钥完成注册；'
              'App 这里可以查看已注册的通行密钥并停用它们。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ 用户选择

  Widget _userSelector(int? userId) {
    final optionsAsync = ref.watch(panelUserOptionsProvider);

    return SectionCard(
      title: '用户',
      child: optionsAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: LoadingView(),
        ),
        error: (error, _) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(panelUserOptionsProvider),
        ),
        data: (users) {
          if (users.isEmpty) {
            return const EmptyView(
              message: '没有可选的面板用户',
              icon: Icons.person_outline,
            );
          }
          final value = users.any((u) => u.id == userId)
              ? userId
              : users.first.id;
          // 令牌所属用户不在列表首页（超过 200 条）等极端情况下同步一次选择。
          if (value != userId) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _userId = value);
            });
          }
          return DropdownButtonFormField<int>(
            initialValue: value,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: '查看哪个用户的通行密钥',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final user in users)
                DropdownMenuItem<int>(
                  value: user.id,
                  child: Text(
                    user.email.isEmpty
                        ? user.displayName
                        : '${user.displayName}（${user.email}）',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (selected) {
              if (selected == null) return;
              setState(() => _userId = selected);
            },
          );
        },
      ),
    );
  }

  // ------------------------------------------------------------------ 密钥列表

  Widget _passkeyList(int userId) {
    final listAsync = ref.watch(passkeyListProvider(userId));

    return SectionCard(
      title: '已注册的通行密钥',
      child: listAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: LoadingView(),
        ),
        error: (error, _) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(passkeyListProvider(userId)),
        ),
        data: (passkeys) {
          if (passkeys.isEmpty) {
            return const EmptyView(
              message: '该用户还没有通行密钥\n请在网页端完成注册',
              icon: Icons.fingerprint_rounded,
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < passkeys.length; i++) ...[
                if (i > 0) const Divider(height: 20),
                _PasskeyTile(
                  passkey: passkeys[i],
                  deleting: _deletingId == passkeys[i].id,
                  onDelete: () => _delete(passkeys[i]),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// 状态行（支持 / 已启用）。
class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.ok,
    this.hint,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool ok;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = ok ? theme.colorScheme.primary : theme.colorScheme.error;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 10),
            Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
            Text(
              value,
              style: theme.textTheme.labelLarge?.copyWith(color: color),
            ),
          ],
        ),
        if (hint != null) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 28),
            child: Text(
              hint!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// 单个通行密钥。
class _PasskeyTile extends StatelessWidget {
  const _PasskeyTile({
    required this.passkey,
    required this.deleting,
    required this.onDelete,
  });

  final Passkey passkey;
  final bool deleting;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.key_rounded, size: 20, color: colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                passkey.name.isEmpty ? '未命名通行密钥' : passkey.name,
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(
                '方式：${passkey.transportsLabel}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                '创建于 ${formatDateTime(passkey.createdAt)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                passkey.lastUsedAt == null
                    ? '从未使用'
                    : '最后使用 ${formatDateTime(passkey.lastUsedAt)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        // 删除中与删除按钮占同样的 48dp 见方，切换时行内不会跳动。
        if (deleting)
          minTouchTarget(
            child: const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else
          A11yIconButton(
            tooltip: '删除通行密钥 ${passkey.name.isEmpty ? '未命名' : passkey.name}',
            icon: Icon(Icons.delete_outline, color: colorScheme.error),
            onPressed: onDelete,
          ),
      ],
    );
  }
}
