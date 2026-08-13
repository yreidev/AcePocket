import 'package:flutter/material.dart';

import '../../../core/widgets/a11y.dart';
import '../models/website.dart';
import 'formatters.dart';

/// 网站列表项卡片。
class WebsiteListTile extends StatelessWidget {
  const WebsiteListTile({
    super.key,
    required this.website,
    required this.onTap,
    required this.onToggleStatus,
    required this.onStats,
    required this.onDelete,
    this.busy = false,
  });

  final Website website;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggleStatus;
  final VoidCallback onStats;
  final VoidCallback onDelete;

  /// 状态切换中：禁用开关并显示进度。
  final bool busy;

  Color _typeColor(ColorScheme scheme) => switch (website.type) {
        'proxy' => scheme.tertiaryContainer,
        'php' => scheme.secondaryContainer,
        _ => scheme.primaryContainer,
      };

  Color _onTypeColor(ColorScheme scheme) => switch (website.type) {
        'proxy' => scheme.onTertiaryContainer,
        'php' => scheme.onSecondaryContainer,
        _ => scheme.onPrimaryContainer,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final certDays = website.certExpireDays;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      website.name,
                      style: theme.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (busy)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Semantics(
                        label: '网站 ${website.name} 正在处理中',
                        child: const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  else
                    // 读屏下裸 Switch 是匿名的，盲用户无法知道停用的是哪个网站；
                    // 开 / 关状态由 Switch 自身播报，标签只说明控制对象。
                    a11ySwitch(
                      label: '网站 ${website.name} 的运行状态',
                      child: Switch(
                        value: website.status,
                        onChanged: onToggleStatus,
                      ),
                    ),
                  PopupMenuButton<String>(
                    tooltip: '网站 ${website.name} 的更多操作',
                    onSelected: (value) {
                      switch (value) {
                        case 'edit':
                          onTap();
                        case 'stats':
                          onStats();
                        case 'delete':
                          onDelete();
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.tune),
                          title: Text('配置'),
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'stats',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.bar_chart),
                          title: Text('统计'),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading:
                              Icon(Icons.delete_outline, color: scheme.error),
                          title:
                              Text('删除', style: TextStyle(color: scheme.error)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _Chip(
                    label: website.typeLabel,
                    background: _typeColor(scheme),
                    foreground: _onTypeColor(scheme),
                  ),
                  _Chip(
                    label: website.status ? '运行中' : '已停用',
                    background: website.status
                        ? scheme.primaryContainer
                        : scheme.surfaceContainerHighest,
                    foreground: website.status
                        ? scheme.onPrimaryContainer
                        : scheme.onSurfaceVariant,
                  ),
                  if (website.ssl)
                    _Chip(
                      label: 'HTTPS',
                      background: scheme.tertiaryContainer,
                      foreground: scheme.onTertiaryContainer,
                    ),
                  if (website.php > 0)
                    _Chip(
                      label: 'PHP ${website.php}',
                      background: scheme.surfaceContainerHighest,
                      foreground: scheme.onSurfaceVariant,
                    ),
                  if (certDays != null)
                    _Chip(
                      label: website.certExpireLabel,
                      background: certDays < 0
                          ? scheme.errorContainer
                          : certDays < 15
                              ? scheme.tertiaryContainer
                              : scheme.surfaceContainerHighest,
                      foreground: certDays < 0
                          ? scheme.onErrorContainer
                          : certDays < 15
                              ? scheme.onTertiaryContainer
                              : scheme.onSurfaceVariant,
                    ),
                ],
              ),
              if (website.domains.isNotEmpty) ...[
                const SizedBox(height: 8),
                _InfoRow(
                  icon: Icons.link,
                  text: website.domains.join('、'),
                ),
              ],
              if (website.path.isNotEmpty) ...[
                const SizedBox(height: 4),
                _InfoRow(icon: Icons.folder_outlined, text: website.path),
              ],
              if (website.expireAt != null) ...[
                const SizedBox(height: 4),
                _InfoRow(
                  icon: Icons.event_busy_outlined,
                  text: '到期时间 ${formatDateTime(website.expireAt)}',
                ),
              ],
              if (website.remark.isNotEmpty) ...[
                const SizedBox(height: 4),
                _InfoRow(
                  icon: Icons.sticky_note_2_outlined,
                  text: website.remark,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style:
            Theme.of(context).textTheme.labelSmall?.copyWith(color: foreground),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
