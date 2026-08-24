import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/panel_http_client.dart';
import '../../../core/models/server.dart';
import '../../../core/storage/server_store.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/section_card.dart';

/// 网络与安全：已记住的服务器证书指纹总览（TOFU）。
///
/// 列出所有已固定证书指纹（[ServerConfig.pinnedCertSha256] 非空）的服务器，
/// 支持逐台清除；清除后下次连接会重新走 TOFU 确认流程，
/// 校验逻辑见 core/api/panel_http_client.dart。
class PinnedCertSection extends ConsumerWidget {
  const PinnedCertSection({super.key});

  /// 服务器显示名（空名回退「未命名服务器」）。
  String _displayName(ServerConfig server) =>
      server.name.isEmpty ? '未命名服务器' : server.name;

  /// 二次确认后清除指定服务器的已固定指纹。
  Future<void> _clearFingerprint(
    BuildContext context,
    WidgetRef ref,
    ServerConfig server,
  ) async {
    final name = _displayName(server);
    final confirmed = await showConfirmDialog(
      context,
      title: '清除证书指纹',
      content: '清除后，下次连接「$name」时将重新要求确认服务器证书指纹。',
      confirmText: '清除',
      danger: true,
    );
    if (!confirmed) return;
    await ref
        .read(serverListProvider.notifier)
        .updateServer(server.copyWith(pinnedCertSha256: ''));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已清除「$name」的证书指纹')));
  }

  /// 一台服务器的指纹条目：名称 + 地址 + 分组指纹 + 「清除」按钮。
  Widget _buildItem(BuildContext context, WidgetRef ref, ServerConfig server) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _displayName(server),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  server.normalizedBaseUrl,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  formatFingerprintGroups(server.pinnedCertSha256),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontFamily: 'monospace',
                    fontFamilyFallback: const ['Courier'],
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => _clearFingerprint(context, ref, server),
            child: const Text('清除'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    // 加载中 / 出错时降级为空列表（main 中已预加载，几乎总是有值）。
    final servers = ref.watch(serverListProvider).value ?? const [];
    final pinnedServers = servers
        .where((s) => s.pinnedCertSha256.isNotEmpty)
        .toList();

    return SectionCard(
      title: '网络与安全',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '开启「允许自签名证书」的服务器首次连接时，需确认其证书 SHA-256 指纹'
            '（TOFU），确认后指纹会被记住并固定校验，证书变化时连接将被拒绝。'
            '服务器更换证书后可在此清除对应指纹，下次连接将重新要求确认。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          if (pinnedServers.isEmpty)
            Row(
              children: [
                Icon(
                  Icons.verified_user_outlined,
                  size: 18,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '暂无已记住的证书指纹。开启「允许自签名证书」的服务器'
                    '完成首次连接确认后会显示在这里。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            )
          else
            for (var i = 0; i < pinnedServers.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              _buildItem(context, ref, pinnedServers[i]),
            ],
        ],
      ),
    );
  }
}
