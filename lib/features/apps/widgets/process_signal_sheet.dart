import 'package:flutter/material.dart';

import '../models/process_info.dart';

/// 选择要发送给进程的信号（`POST /api/process/signal`）。
///
/// 返回被选中的信号，取消时返回 null。
Future<ProcessSignalOption?> showProcessSignalSheet(
  BuildContext context, {
  required ProcessInfo process,
}) {
  return showModalBottomSheet<ProcessSignalOption>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      final theme = Theme.of(context);
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('发送信号', style: theme.textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text(
                      '${process.name}（PID ${process.pid}）',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: ProcessSignalOption.all.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final signal = ProcessSignalOption.all[index];
                    return ListTile(
                      title: Text('${signal.name}（${signal.value}）'),
                      subtitle: Text(signal.description),
                      onTap: () => Navigator.of(context).pop(signal),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    },
  );
}
