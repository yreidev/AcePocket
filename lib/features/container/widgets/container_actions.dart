import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/confirm_dialog.dart';
import '../providers/container_providers.dart';
import 'action_runner.dart';

/// 容器可执行的操作。
enum ContainerAction {
  start('启动', Icons.play_arrow_outlined),
  stop('停止', Icons.stop_outlined),
  restart('重启', Icons.restart_alt),
  pause('暂停', Icons.pause_outlined),
  unpause('恢复', Icons.play_circle_outline),
  kill('强制终止', Icons.dangerous_outlined),
  rename('重命名', Icons.drive_file_rename_outline),
  remove('删除', Icons.delete_outline);

  const ContainerAction(this.label, this.icon);

  final String label;
  final IconData icon;

  /// 是否为危险操作（菜单项用错误色渲染）。
  bool get danger =>
      this == ContainerAction.remove || this == ContainerAction.kill;
}

/// 根据容器状态给出可用的操作列表。
List<ContainerAction> availableContainerActions(String state) {
  switch (state) {
    case 'running':
      return const [
        ContainerAction.stop,
        ContainerAction.restart,
        ContainerAction.pause,
        ContainerAction.rename,
        ContainerAction.kill,
        ContainerAction.remove,
      ];
    case 'paused':
      return const [
        ContainerAction.unpause,
        ContainerAction.stop,
        ContainerAction.restart,
        ContainerAction.rename,
        ContainerAction.kill,
        ContainerAction.remove,
      ];
    case 'restarting':
      return const [
        ContainerAction.stop,
        ContainerAction.kill,
        ContainerAction.remove,
      ];
    default:
      // created / exited / dead / removing / 未知
      return const [
        ContainerAction.start,
        ContainerAction.restart,
        ContainerAction.rename,
        ContainerAction.remove,
      ];
  }
}

/// 执行容器操作（含二次确认与结果提示）。返回是否执行成功。
Future<bool> performContainerAction(
  BuildContext context,
  WidgetRef ref, {
  required String id,
  required String name,
  required ContainerAction action,
}) async {
  final repo = ref.read(containerRepoProvider);
  final display = name.isEmpty ? id : name;

  switch (action) {
    case ContainerAction.start:
      return runAction(
        context,
        pending: '正在启动「$display」…',
        success: '「$display」已启动',
        action: () => repo.startContainer(id),
      );

    case ContainerAction.stop:
      final ok = await showConfirmDialog(
        context,
        title: '停止容器',
        content: '确定要停止「$display」吗？容器内运行的服务将中断。',
        confirmText: '停止',
        danger: true,
      );
      if (!ok || !context.mounted) return false;
      return runAction(
        context,
        pending: '正在停止「$display」…',
        success: '「$display」已停止',
        action: () => repo.stopContainer(id),
      );

    case ContainerAction.restart:
      final ok = await showConfirmDialog(
        context,
        title: '重启容器',
        content: '确定要重启「$display」吗？',
        confirmText: '重启',
      );
      if (!ok || !context.mounted) return false;
      return runAction(
        context,
        pending: '正在重启「$display」…',
        success: '「$display」已重启',
        action: () => repo.restartContainer(id),
      );

    case ContainerAction.pause:
      return runAction(
        context,
        pending: '正在暂停「$display」…',
        success: '「$display」已暂停',
        action: () => repo.pauseContainer(id),
      );

    case ContainerAction.unpause:
      return runAction(
        context,
        pending: '正在恢复「$display」…',
        success: '「$display」已恢复',
        action: () => repo.unpauseContainer(id),
      );

    case ContainerAction.kill:
      final ok = await showConfirmDialog(
        context,
        title: '强制终止容器',
        content: '确定要强制终止「$display」吗？\n将直接向容器主进程发送 SIGKILL，'
            '未保存的数据可能丢失。',
        confirmText: '强制终止',
        danger: true,
      );
      if (!ok || !context.mounted) return false;
      return runAction(
        context,
        pending: '正在终止「$display」…',
        success: '「$display」已终止',
        action: () => repo.killContainer(id),
      );

    case ContainerAction.rename:
      final newName = await showRenameContainerDialog(context, name);
      if (newName == null || !context.mounted) return false;
      return runAction(
        context,
        pending: '正在重命名…',
        success: '已重命名为「$newName」',
        action: () => repo.renameContainer(id, newName),
      );

    case ContainerAction.remove:
      final ok = await showConfirmDialog(
        context,
        title: '删除容器',
        content: '确定要删除「$display」吗？\n容器及其可写层将被移除，此操作不可恢复。',
        confirmText: '删除',
        danger: true,
      );
      if (!ok || !context.mounted) return false;
      return runAction(
        context,
        pending: '正在删除「$display」…',
        success: '「$display」已删除',
        action: () => repo.removeContainer(id),
      );
  }
}

/// 重命名输入对话框。返回新名称，取消时返回 null。
Future<String?> showRenameContainerDialog(
  BuildContext context,
  String currentName,
) {
  final controller = TextEditingController(text: currentName);
  final formKey = GlobalKey<FormState>();
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('重命名容器'),
      content: Form(
        key: formKey,
        child: TextFormField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '新名称',
            helperText: '仅允许字母、数字、下划线与短横线',
          ),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_-]')),
          ],
          validator: (value) {
            final text = (value ?? '').trim();
            if (text.isEmpty) return '请输入新名称';
            if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(text)) {
              return '仅允许字母、数字、下划线与短横线';
            }
            if (text == currentName) return '与当前名称相同';
            return null;
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            if (formKey.currentState?.validate() ?? false) {
              Navigator.of(dialogContext).pop(controller.text.trim());
            }
          },
          child: const Text('确定'),
        ),
      ],
    ),
  ).whenComplete(controller.dispose);
}
