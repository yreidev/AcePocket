import 'package:flutter/material.dart';

import '../../../core/widgets/section_card.dart';

/// 可迁移项的多选分区（网站 / 数据库 / 数据库用户 / 项目共用）。
class ItemSelectSection<T> extends StatelessWidget {
  const ItemSelectSection({
    super.key,
    required this.title,
    required this.icon,
    required this.items,
    required this.emptyText,
    required this.isSelected,
    required this.labelOf,
    required this.subtitleOf,
    required this.onToggle,
    required this.onSelectAll,
    this.tagOf,
    this.isEnabled,
    this.disabledHint,
  });

  final String title;
  final IconData icon;
  final List<T> items;

  /// 列表为空时的提示。
  final String emptyText;

  final bool Function(T item) isSelected;
  final String Function(T item) labelOf;
  final String Function(T item) subtitleOf;

  /// 右侧小标签（如数据库类型），返回 null 则不展示。
  final String? Function(T item)? tagOf;

  /// 该项是否可选（不可选时置灰并展示 [disabledHint]）。
  final bool Function(T item)? isEnabled;

  /// 不可选原因。
  final String? disabledHint;

  final void Function(T item, bool selected) onToggle;
  final void Function(bool selectAll) onSelectAll;

  bool _enabled(T item) => isEnabled?.call(item) ?? true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final selectable = items.where(_enabled).toList();
    final selectedCount = items.where(isSelected).length;
    final allSelected =
        selectable.isNotEmpty && selectedCount >= selectable.length;

    return SectionCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$title（已选 $selectedCount / ${items.length}）',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (selectable.isNotEmpty)
                TextButton(
                  onPressed: () => onSelectAll(!allSelected),
                  child: Text(allSelected ? '取消全选' : '全选'),
                ),
            ],
          ),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
              child: Text(
                emptyText,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            for (final item in items)
              _ItemTile<T>(
                item: item,
                selected: isSelected(item),
                enabled: _enabled(item),
                label: labelOf(item),
                subtitle: subtitleOf(item),
                tag: tagOf?.call(item),
                disabledHint: disabledHint,
                onChanged: (value) => onToggle(item, value),
              ),
        ],
      ),
    );
  }
}

class _ItemTile<T> extends StatelessWidget {
  const _ItemTile({
    required this.item,
    required this.selected,
    required this.enabled,
    required this.label,
    required this.subtitle,
    required this.tag,
    required this.disabledHint,
    required this.onChanged,
  });

  final T item;
  final bool selected;
  final bool enabled;
  final String label;
  final String subtitle;
  final String? tag;
  final String? disabledHint;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hint = enabled ? subtitle : (disabledHint ?? subtitle);

    return CheckboxListTile(
      value: enabled && selected,
      onChanged: enabled ? (value) => onChanged(value ?? false) : null,
      dense: true,
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      title: Row(
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: enabled ? null : colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (tag != null && tag!.isNotEmpty) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                tag!,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSecondaryContainer,
                ),
              ),
            ),
          ],
        ],
      ),
      subtitle: hint.isEmpty
          ? null
          : Text(
              hint,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: enabled
                    ? colorScheme.onSurfaceVariant
                    : colorScheme.error,
              ),
            ),
    );
  }
}
