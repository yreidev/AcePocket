import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/widgets/a11y.dart';
import '../models/cert.dart';

/// 证书状态。
enum CertStatus {
  /// 尚未签发（无证书内容）。
  pending,

  /// 已签发且未临近到期。
  valid,

  /// 30 天内到期。
  expiring,

  /// 已过期。
  expired,
}

CertStatus certStatusOf(CertListItem cert) {
  if (!cert.issued) return CertStatus.pending;
  final days = cert.daysLeft ?? 0;
  if (days < 0) return CertStatus.expired;
  if (days <= 30) return CertStatus.expiring;
  return CertStatus.valid;
}

String _fmtDate(DateTime? time) =>
    time == null ? '无' : DateFormat('yyyy-MM-dd HH:mm').format(time);

/// 证书列表项卡片。
class CertTile extends StatelessWidget {
  const CertTile({
    super.key,
    required this.cert,
    required this.accountName,
    required this.websiteName,
    required this.dnsName,
    required this.onObtain,
    required this.onRenew,
    required this.onDeploy,
    required this.onView,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleAutoRenewal,
    this.busy = false,
  });

  final CertListItem cert;

  /// 关联 CA 账户显示名（无则空串）。
  final String accountName;

  /// 关联网站名（无则空串）。
  final String websiteName;

  /// 关联 DNS 账号名（无则空串）。
  final String dnsName;

  final VoidCallback onObtain;
  final VoidCallback onRenew;
  final VoidCallback onDeploy;
  final VoidCallback onView;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggleAutoRenewal;

  /// 该条目正在执行操作（禁用交互）。
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final status = certStatusOf(cert);

    final (
      Color statusColor,
      Color statusBg,
      String statusText,
    ) = switch (status) {
      CertStatus.pending => (
        colorScheme.onSurfaceVariant,
        colorScheme.surfaceContainerHighest,
        '未签发',
      ),
      CertStatus.valid => (
        colorScheme.primary,
        colorScheme.primaryContainer,
        '有效',
      ),
      CertStatus.expiring => (
        colorScheme.tertiary,
        colorScheme.tertiaryContainer,
        '即将到期',
      ),
      CertStatus.expired => (
        colorScheme.error,
        colorScheme.errorContainer,
        '已过期',
      ),
    };

    final canObtain = !cert.isUpload && cert.cert.isEmpty && cert.key.isEmpty;
    final canRenew = !cert.isUpload && cert.certUrl.isNotEmpty;
    final hasContent = cert.cert.isNotEmpty && cert.key.isNotEmpty;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    cert.domains.isEmpty ? '（无域名）' : cert.domains.first,
                    style: theme.textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                _Chip(
                  text: statusText,
                  foreground: statusColor,
                  background: statusBg,
                ),
              ],
            ),
            if (cert.domains.length > 1) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final domain in cert.domains.skip(1))
                    _Chip(
                      text: domain,
                      foreground: colorScheme.onSurfaceVariant,
                      background: colorScheme.surfaceContainerHighest,
                    ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            _InfoRow(label: '类型', value: CertListItem.typeLabel(cert.type)),
            if (cert.issuer.isNotEmpty)
              _InfoRow(label: '颁发者', value: cert.issuer),
            _InfoRow(
              label: '到期时间',
              value: _fmtDate(cert.notAfter),
              valueColor: status == CertStatus.expired
                  ? colorScheme.error
                  : status == CertStatus.expiring
                  ? colorScheme.tertiary
                  : null,
              suffix: cert.daysLeft == null
                  ? null
                  : cert.daysLeft! < 0
                  ? '（已过期 ${-cert.daysLeft!} 天）'
                  : '（剩余 ${cert.daysLeft} 天）',
            ),
            if (cert.nextRenewal != null)
              _InfoRow(label: '下次续签', value: _fmtDate(cert.nextRenewal)),
            if (accountName.isNotEmpty)
              _InfoRow(label: 'CA 账户', value: accountName),
            if (dnsName.isNotEmpty) _InfoRow(label: 'DNS 账号', value: dnsName),
            if (websiteName.isNotEmpty)
              _InfoRow(label: '关联网站', value: websiteName),
            if (!cert.isUpload)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '自动续签',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  // 读屏只念「开关」无法分辨是哪张证书，补上控制对象；
                  // 开 / 关状态由 Switch 自身播报，label 里不写状态词。
                  a11ySwitch(
                    label:
                        '证书 ${cert.domains.isEmpty ? '（无域名）' : cert.domains.first} 的自动续签',
                    child: Switch(
                      value: cert.autoRenewal,
                      onChanged: busy ? null : (_) => onToggleAutoRenewal(),
                    ),
                  ),
                ],
              ),
            const Divider(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 4,
                children: [
                  if (canObtain)
                    TextButton.icon(
                      onPressed: busy ? null : onObtain,
                      icon: const Icon(Icons.verified_outlined, size: 18),
                      label: const Text('签发'),
                    ),
                  if (canRenew)
                    TextButton.icon(
                      onPressed: busy ? null : onRenew,
                      icon: const Icon(Icons.autorenew, size: 18),
                      label: const Text('续签'),
                    ),
                  if (hasContent)
                    TextButton.icon(
                      onPressed: busy ? null : onDeploy,
                      icon: const Icon(Icons.rocket_launch_outlined, size: 18),
                      label: const Text('部署'),
                    ),
                  if (hasContent)
                    TextButton.icon(
                      onPressed: busy ? null : onView,
                      icon: const Icon(Icons.description_outlined, size: 18),
                      label: const Text('查看'),
                    ),
                  TextButton.icon(
                    onPressed: busy ? null : onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('编辑'),
                  ),
                  TextButton.icon(
                    onPressed: busy ? null : onDelete,
                    style: TextButton.styleFrom(
                      foregroundColor: colorScheme.error,
                    ),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('删除'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.text,
    required this.foreground,
    required this.background,
  });

  final String text;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: foreground),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.suffix,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 标签列宽随系统字号放大，否则 200% 字号下「到期时间」会被挤成多行；
    // 上限 140 是为了给右侧值留出足够宽度。
    final labelWidth = MediaQuery.textScalerOf(
      context,
    ).scale(76).clamp(76.0, 140.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: labelWidth,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              suffix == null ? value : '$value ${suffix!}',
              style: theme.textTheme.bodySmall?.copyWith(color: valueColor),
            ),
          ),
        ],
      ),
    );
  }
}
