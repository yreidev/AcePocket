import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/confirm_dialog.dart';
import '../providers/container_providers.dart';
import 'action_runner.dart';

/// 启动编排（`docker compose up -d`，可选 `--pull always`）。
///
/// 返回是否执行成功。
Future<bool> composeUpAction(
  BuildContext context,
  WidgetRef ref,
  String name,
) async {
  final force = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      var pull = false;
      return StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('启动编排'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('将执行 docker compose up -d 启动「$name」。'),
              const SizedBox(height: 4),
              Text(
                '首次启动需要拉取镜像，可能耗时数分钟，请保持页面打开。'
                '若仍提示超时，服务器多半还在后台执行，稍后刷新列表即可看到结果。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
                value: pull,
                title: const Text('强制拉取最新镜像'),
                subtitle: const Text('--pull always'),
                onChanged: (value) => setState(() => pull = value ?? false),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(pull),
              child: const Text('启动'),
            ),
          ],
        ),
      );
    },
  );

  if (force == null || !context.mounted) return false;

  return runAction(
    context,
    pending: '正在启动「$name」…',
    success: '「$name」已启动',
    action: () => ref.read(containerRepoProvider).composeUp(name, force: force),
  );
}

/// 停止编排（`docker compose down`）。
Future<bool> composeDownAction(
  BuildContext context,
  WidgetRef ref,
  String name,
) async {
  final ok = await showConfirmDialog(
    context,
    title: '停止编排',
    content:
        '将执行 docker compose down 停止并移除「$name」的容器与网络，'
        '数据卷会保留。确定继续吗？',
    confirmText: '停止',
    danger: true,
  );
  if (!ok || !context.mounted) return false;
  return runAction(
    context,
    pending: '正在停止「$name」…',
    success: '「$name」已停止',
    action: () => ref.read(containerRepoProvider).composeDown(name),
  );
}

/// 删除编排（服务端会先 down 再删除编排目录）。
Future<bool> composeRemoveAction(
  BuildContext context,
  WidgetRef ref,
  String name,
) async {
  final ok = await showConfirmDialog(
    context,
    title: '删除编排',
    content:
        '将先停止「$name」，再删除其编排目录（含 docker-compose.yml 与 .env）。'
        '此操作不可恢复，确定继续吗？',
    confirmText: '删除',
    danger: true,
  );
  if (!ok || !context.mounted) return false;
  return runAction(
    context,
    pending: '正在删除「$name」…',
    success: '「$name」已删除',
    action: () => ref.read(containerRepoProvider).removeCompose(name),
  );
}
