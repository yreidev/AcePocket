import 'package:flutter/material.dart';

import '../../../core/widgets/a11y.dart';

export '../../../core/widgets/info_row.dart';

/// 「未保存」角标：草稿式设置页里标记改过但尚未提交到面板的项。
///
/// 仅改动本地草稿的行必须带上它——否则用户看到行上已是新值，
/// 会以为设置已生效，返回后静默丢失（安全入口 / 端口这类项代价极高）。
class UnsavedBadge extends StatelessWidget {
  const UnsavedBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return TagChip(
      label: '未保存',
      icon: Icons.edit_outlined,
      color: Theme.of(context).colorScheme.tertiary,
    );
  }
}

/// 标题行：标题文本 + 可选的「未保存」角标。
Widget _titleWithBadge(BuildContext context, String title, bool dirty) {
  final theme = Theme.of(context);
  final text = Text(
    title,
    style: theme.textTheme.bodyLarge,
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
  );
  if (!dirty) return text;
  return Row(
    children: [
      Flexible(child: text),
      const SizedBox(width: 8),
      const UnsavedBadge(),
    ],
  );
}

/// 开关行：标题 + 说明 + Switch，[busy] 为 true 时以进度指示器替代开关。
///
/// [dirty] 为 true 表示该项已改动但尚未保存，标题后展示「未保存」角标。
class SettingSwitchTile extends StatelessWidget {
  const SettingSwitchTile({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.icon,
    this.busy = false,
    this.dirty = false,
    this.contentPadding = EdgeInsets.zero,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final bool value;
  final bool busy;

  /// 已修改但未保存（仅存在于本地草稿）。
  final bool dirty;
  final ValueChanged<bool>? onChanged;
  final EdgeInsetsGeometry contentPadding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: contentPadding,
      leading: icon == null
          ? null
          : Icon(
              icon,
              color: dirty
                  ? theme.colorScheme.tertiary
                  : theme.colorScheme.onSurfaceVariant,
            ),
      title: _titleWithBadge(context, title, dirty),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
      trailing: busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          // 读屏播报「<标题>，开关，已开启」；状态词由 Switch 自己念，label 不写。
          : a11ySwitch(
              label: title,
              child: Switch(value: value, onChanged: onChanged),
            ),
      onTap: busy || onChanged == null ? null : () => onChanged!(!value),
    );
  }
}

/// 可编辑的配置行：标题 + 当前值，点击进入编辑。
///
/// [dirty] 为 true 表示当前值来自未保存的本地草稿，会以 tertiary 色 +
/// 「未保存」角标区分于服务端已生效的值。
class SettingValueTile extends StatelessWidget {
  const SettingValueTile({
    super.key,
    required this.title,
    required this.value,
    this.onTap,
    this.icon,
    this.helper,
    this.busy = false,
    this.dirty = false,
    this.contentPadding = EdgeInsets.zero,
  });

  final String title;
  final String value;
  final String? helper;
  final IconData? icon;
  final bool busy;

  /// 已修改但未保存（仅存在于本地草稿）。
  final bool dirty;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry contentPadding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color valueColor;
    if (dirty) {
      valueColor = theme.colorScheme.tertiary;
    } else if (value.isEmpty) {
      valueColor = theme.colorScheme.onSurfaceVariant;
    } else {
      valueColor = theme.colorScheme.onSurface;
    }
    return ListTile(
      contentPadding: contentPadding,
      leading: icon == null
          ? null
          : Icon(
              icon,
              color: dirty
                  ? theme.colorScheme.tertiary
                  : theme.colorScheme.onSurfaceVariant,
            ),
      title: _titleWithBadge(context, title, dirty),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value.isEmpty ? '未设置' : value,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: valueColor,
              fontWeight: dirty ? FontWeight.w600 : null,
            ),
          ),
          if (helper != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                helper!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
      trailing: busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : (onTap == null
                ? null
                : Icon(
                    Icons.chevron_right,
                    color: theme.colorScheme.onSurfaceVariant,
                  )),
      onTap: busy ? null : onTap,
    );
  }
}

/// 统计数字块（扫描汇总等）。
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.icon,
  });

  final String label;
  final String value;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(height: 6),
        ],
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// 小标签（协议 / 方向 / 状态等）。
class TagChip extends StatelessWidget {
  const TagChip({super.key, required this.label, this.color, this.icon});

  final String label;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = color ?? theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: base.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: base),
            const SizedBox(width: 4),
          ],
          Text(label, style: theme.textTheme.labelSmall?.copyWith(color: base)),
        ],
      ),
    );
  }
}
