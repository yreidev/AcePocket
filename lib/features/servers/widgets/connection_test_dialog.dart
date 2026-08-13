import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/panel_http_client.dart';
import '../../../core/storage/server_store.dart';
import '../providers/servers_providers.dart';
import 'certificate_trust_dialog.dart';
import 'connection_test_result_card.dart';

/// 对已保存的服务器执行连接测试，并以对话框展示结果。
///
/// [serverId] 为服务器配置的 id；失败时可原地重试。
Future<void> showConnectionTestDialog(
  BuildContext context, {
  required String serverId,
  required String serverName,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _ConnectionTestDialog(
      serverId: serverId,
      serverName: serverName,
    ),
  );
}

class _ConnectionTestDialog extends ConsumerWidget {
  const _ConnectionTestDialog({
    required this.serverId,
    required this.serverName,
  });

  final String serverId;
  final String serverName;

  /// TOFU：用户核对并信任证书后，把指纹写入已保存的配置并重新测试。
  Future<void> _trustCertificate(
    BuildContext context,
    WidgetRef ref,
    CertificateTrustRequiredException error,
  ) async {
    final trusted =
        await showCertificateTrustDialog(context, error.certificate);
    if (!trusted || !context.mounted) return;
    final server = ref.read(serverByIdProvider(serverId));
    if (server == null) return;
    await ref.read(serverListProvider.notifier).updateServer(
          server.copyWith(pinnedCertSha256: error.certificate.sha256Hex),
        );
    ref.invalidate(serverConnectionTestProvider(serverId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final testAsync = ref.watch(serverConnectionTestProvider(serverId));
    final error = testAsync.hasError ? testAsync.error : null;

    return AlertDialog(
      title: Text('测试「$serverName」'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: testAsync.when(
            loading: () => Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '正在测试连接…',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            error: (error, _) => ConnectionTestErrorCard(error: error),
            data: (result) => ConnectionTestResultCard(result: result),
          ),
        ),
      ),
      actions: [
        if (!testAsync.isLoading && error is CertificateTrustRequiredException)
          TextButton(
            onPressed: () => _trustCertificate(context, ref, error),
            child: const Text('查看并信任证书'),
          ),
        if (!testAsync.isLoading)
          TextButton(
            onPressed: () =>
                ref.invalidate(serverConnectionTestProvider(serverId)),
            child: const Text('重新测试'),
          ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}
