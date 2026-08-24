import 'package:flutter/material.dart';

import '../../../core/widgets/a11y.dart';
import '../models/app_item.dart';

/// 选择要安装的版本通道。
///
/// `POST /api/app/install` 要求同时提交 `slug` 与 `channel`，
/// 因此安装前需要用户选择一个通道。返回被选中的通道，取消时返回 null。
Future<AppChannel?> showAppChannelSheet(
  BuildContext context, {
  required AppItem app,
}) {
  return showModalBottomSheet<AppChannel>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _AppChannelSheet(app: app),
  );
}

class _AppChannelSheet extends StatelessWidget {
  const _AppChannelSheet({required this.app});

  final AppItem app;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final maxHeight = MediaQuery.of(context).size.height * 0.75;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('安装 ${app.name}', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(
                    '请选择要安装的版本',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 16),
            if (app.channels.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  '该应用没有可安装的版本，请先在应用商店更新缓存',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: app.channels.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final channel = app.channels[index];
                    return _ChannelTile(channel: channel);
                  },
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _ChannelTile extends StatelessWidget {
  const _ChannelTile({required this.channel});

  final AppChannel channel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final subtitle = <String>[
      if (channel.version.isNotEmpty) '版本 ${channel.version}',
      if (channel.panel.isNotEmpty) '需要面板 ${channel.panel}',
    ].join(' · ');

    return ListTile(
      title: Text(channel.name.isEmpty ? channel.slug : channel.name),
      subtitle: subtitle.isEmpty
          ? null
          : Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
      trailing: channel.log.isEmpty
          ? const Icon(Icons.chevron_right)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                A11yIconButton(
                  tooltip: '查看该版本的更新日志',
                  icon: const Icon(Icons.article_outlined),
                  onPressed: () => _showLog(context),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
      onTap: () => Navigator.of(context).pop(channel),
    );
  }

  void _showLog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${channel.name} 更新日志'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(child: Text(channel.log)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}
