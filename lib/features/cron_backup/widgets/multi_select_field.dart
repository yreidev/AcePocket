import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/error_view.dart';
import '../models/option_item.dart';
import 'feedback.dart';

/// 多选字段：展示已选项的 Chip，点击打开底部选择面板。
///
/// [options] 为异步加载的候选项（网站 / 数据库 / 容器）。
class MultiSelectField extends StatelessWidget {
  const MultiSelectField({
    super.key,
    required this.label,
    required this.selected,
    required this.options,
    required this.onChanged,
    this.emptyHint = '尚未选择',
    this.onReload,
  });

  final String label;
  final List<String> selected;
  final AsyncValue<List<OptionItem>> options;
  final ValueChanged<List<String>> onChanged;
  final String emptyHint;
  final VoidCallback? onReload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _openSheet(context),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.arrow_drop_down),
        ),
        child: selected.isEmpty
            ? Text(
                emptyHint,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            : Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final value in selected)
                    Chip(
                      // 目录路径 / 长域名可能很长，限宽省略，
                      // 否则单个 Chip 会把 Wrap 撑出屏幕。
                      label: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 200),
                        child: Text(
                          value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      deleteButtonTooltipMessage: '移除 $value',
                      onDeleted: () =>
                          onChanged(selected.where((e) => e != value).toList()),
                    ),
                ],
              ),
      ),
    );
  }

  Future<void> _openSheet(BuildContext context) async {
    final result = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _MultiSelectSheet(
        title: label,
        selected: selected,
        options: options,
        onReload: onReload,
      ),
    );
    if (result != null) onChanged(result);
  }
}

class _MultiSelectSheet extends StatefulWidget {
  const _MultiSelectSheet({
    required this.title,
    required this.selected,
    required this.options,
    this.onReload,
  });

  final String title;
  final List<String> selected;
  final AsyncValue<List<OptionItem>> options;
  final VoidCallback? onReload;

  @override
  State<_MultiSelectSheet> createState() => _MultiSelectSheetState();
}

class _MultiSelectSheetState extends State<_MultiSelectSheet> {
  late List<String> _selected = List.of(widget.selected);
  String _keyword = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: theme.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(_selected),
                    child: const Text('完成'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: '搜索',
                ),
                onChanged: (v) => setState(() => _keyword = v.trim()),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: widget.options.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) =>
                    ErrorView(error: error, onRetry: widget.onReload),
                data: (list) {
                  final filtered = _keyword.isEmpty
                      ? list
                      : list
                            .where(
                              (e) =>
                                  e.label.contains(_keyword) ||
                                  e.value.contains(_keyword),
                            )
                            .toList();
                  if (filtered.isEmpty) {
                    return Center(
                      child: Text(
                        list.isEmpty ? '暂无可选项' : '没有匹配的项',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    );
                  }
                  return ListView.builder(
                    controller: scrollController,
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final option = filtered[index];
                      final checked = _selected.contains(option.value);
                      return CheckboxListTile(
                        value: checked,
                        title: Text(
                          option.label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: option.label == option.value
                            ? null
                            : Text(
                                option.value,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                        onChanged: (v) {
                          setState(() {
                            if (v == true) {
                              if (!_selected.contains(option.value)) {
                                _selected = [..._selected, option.value];
                              }
                            } else {
                              _selected = _selected
                                  .where((e) => e != option.value)
                                  .toList();
                            }
                          });
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 单选字段（下拉选择，异步候选项）。
class AsyncDropdownField extends StatelessWidget {
  const AsyncDropdownField({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.onReload,
  });

  final String label;
  final String? value;
  final AsyncValue<List<OptionItem>> options;
  final ValueChanged<String?> onChanged;
  final VoidCallback? onReload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return options.when(
      loading: () => InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text(
              '加载中…',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      error: (error, _) => InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          // 原先直接 toString()，会把 `ApiException: ...` 这类原始类型名
          // 暴露给用户；统一走 describeError。
          errorText: describeError(error),
          suffixIcon: A11yIconButton(
            tooltip: '重新加载$label列表',
            icon: const Icon(Icons.refresh),
            onPressed: onReload,
          ),
        ),
        child: const Text('加载失败，点击右侧按钮重试'),
      ),
      data: (list) {
        final values = list.map((e) => e.value).toList();
        final current = value != null && values.contains(value) ? value : null;
        return DropdownButtonFormField<String>(
          initialValue: current,
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          items: [
            for (final option in list)
              DropdownMenuItem(
                value: option.value,
                child: Text(
                  option.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: onChanged,
          validator: (v) => (v == null || v.isEmpty) ? '请选择$label' : null,
        );
      },
    );
  }
}
