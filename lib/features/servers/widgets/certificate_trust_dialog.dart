import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/api/panel_http_client.dart';

/// 首次信任服务器证书（TOFU）的确认对话框。
///
/// 展示证书 SHA-256 指纹（每 4 字节一段分组显示，便于人工核对）、
/// subject、issuer 与有效期。返回 true 表示用户选择「信任并继续」，
/// 调用方应把 [PanelCertificateInfo.sha256Hex] 写入
/// `ServerConfig.pinnedCertSha256` 并重试连接。
Future<bool> showCertificateTrustDialog(
  BuildContext context,
  PanelCertificateInfo certificate,
) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _CertificateTrustDialog(certificate: certificate),
  );
  return result ?? false;
}

class _CertificateTrustDialog extends StatelessWidget {
  const _CertificateTrustDialog({required this.certificate});

  final PanelCertificateInfo certificate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm');

    return AlertDialog(
      icon: const Icon(Icons.security_outlined),
      title: const Text('确认服务器身份'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '无法通过系统信任链验证服务器 '
                '${certificate.host}:${certificate.port} 的 HTTPS 证书。'
                '首次连接需要确认服务器身份：请核对下方 SHA-256 指纹'
                '与面板服务器上证书的指纹是否一致。',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              _CertField(
                label: 'SHA-256 指纹',
                value: certificate.groupedSha256,
                monospace: true,
              ),
              _CertField(label: '使用者（Subject）', value: certificate.subject),
              _CertField(label: '颁发者（Issuer）', value: certificate.issuer),
              _CertField(
                label: '有效期',
                value:
                    '${dateFormat.format(certificate.validFrom)} 至 '
                    '${dateFormat.format(certificate.validTo)}',
              ),
              const SizedBox(height: 12),
              Text(
                '确认信任后指纹会被记住，日后该服务器的证书发生变化时'
                '连接将被拒绝（需在服务器编辑页清除指纹后重新确认）。'
                '若无法核对指纹来源，请勿信任。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('信任并继续'),
        ),
      ],
    );
  }
}

class _CertField extends StatelessWidget {
  const _CertField({
    required this.label,
    required this.value,
    this.monospace = false,
  });

  final String label;
  final String value;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          SelectableText(
            value.isEmpty ? '-' : value,
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: monospace ? 'monospace' : null,
              fontFamilyFallback: monospace ? const ['Courier'] : null,
            ),
          ),
        ],
      ),
    );
  }
}
