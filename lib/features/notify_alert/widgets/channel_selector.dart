import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../models/notify_channel.dart';
import '../providers/notify_alert_providers.dart';

/// 通知渠道多选（数据来自 `GET /notify/channel/all`）。
///
/// 未选择任何渠道时表示「仅记录不通知」（告警规则）或「不发送事件通知」。
class ChannelSelector extends ConsumerWidget {
  const ChannelSelector({
    super.key,
    required this.selected,
    required this.onChanged,
    this.enabled = true,
    this.emptyHint = '尚未创建通知渠道，可先到「通知」页的「通知渠道」标签添加。',
  });

  final List<int> selected;
  final ValueChanged<List<int>> onChanged;

  /// 为 false 时禁用勾选（如保存进行中）。
  final bool enabled;

  final String emptyHint;

  void _toggle(int id, bool value) {
    final next = List<int>.from(selected);
    if (value) {
      if (!next.contains(id)) next.add(id);
    } else {
      next.remove(id);
    }
    onChanged(next);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final channels = ref.watch(allNotifyChannelsProvider);

    return channels.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      error: (error, _) => Row(
        children: [
          Expanded(
            child: Text(
              '渠道列表加载失败：${describeError(error)}',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
          TextButton(
            onPressed: () => ref.invalidate(allNotifyChannelsProvider),
            child: const Text('重试'),
          ),
        ],
      ),
      data: (list) {
        if (list.isEmpty) {
          return Text(
            emptyHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final NotifyChannel channel in list)
              CheckboxListTile(
                value: selected.contains(channel.id),
                onChanged: enabled
                    ? (value) => _toggle(channel.id, value ?? false)
                    : null,
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  channel.name.isEmpty ? '未命名渠道' : channel.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  channel.enabled
                      ? '${notifyTypeLabel(channel.type)} · ${channel.summary}'
                      : '${notifyTypeLabel(channel.type)} · 已停用（不会收到通知）',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        );
      },
    );
  }
}
