import 'package:flutter/material.dart';

import '../../../core/widgets/a11y.dart';
import '../models/environment_models.dart';
import 'environment_ui.dart';

/// 运行环境列表项可执行的动作。
enum EnvironmentAction { manage, install, update, uninstall }

/// 运行环境列表卡片：图标、名称、描述、版本信息与操作按钮。
class EnvironmentTile extends StatelessWidget {
  const EnvironmentTile({
    super.key,
    required this.environment,
    required this.onAction,
    this.busy = false,
  });

  final EnvironmentDetail environment;

  /// 正在提交该环境的某个操作时置灰按钮。
  final bool busy;

  final void Function(EnvironmentAction action) onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final env = environment;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: env.installed && !busy
            ? () => onAction(EnvironmentAction.manage)
            : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer.withValues(
                        alpha: 0.6,
                      ),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(
                      environmentTypeIcon(env.type),
                      size: 21,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          env.name.isEmpty
                              ? '${environmentTypeLabel(env.type)} ${env.slug}'
                              : env.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall,
                        ),
                        if (env.description.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            env.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  StatusChip(
                    label: env.installed ? '已安装' : '未安装',
                    color: env.installed
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outline,
                    icon: env.installed
                        ? Icons.check_circle_outline
                        : Icons.radio_button_unchecked,
                  ),
                  if (env.hasUpdate)
                    StatusChip(
                      label: '可更新',
                      color: theme.colorScheme.tertiary,
                      icon: Icons.upgrade_rounded,
                    ),
                  if (env.customSupported)
                    StatusChip(
                      label: '支持自定义编译',
                      color: theme.colorScheme.secondary,
                      icon: Icons.build_outlined,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      env.installed
                          ? '已装 ${_display(env.installedVersion)} · 最新 ${_display(env.version)}'
                          : '最新版本 ${_display(env.version)}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (busy)
                    const Padding(
                      padding: EdgeInsets.all(10),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else
                    ..._actions(context),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _actions(BuildContext context) {
    final theme = Theme.of(context);
    final env = environment;
    if (!env.installed) {
      return [
        TextButton.icon(
          onPressed: () => onAction(EnvironmentAction.install),
          icon: const Icon(Icons.download_rounded, size: 18),
          label: const Text('安装'),
        ),
      ];
    }
    return [
      if (env.hasUpdate)
        TextButton(
          onPressed: () => onAction(EnvironmentAction.update),
          child: const Text('更新'),
        ),
      TextButton(
        onPressed: () => onAction(EnvironmentAction.manage),
        child: const Text('管理'),
      ),
      A11yIconButton(
        tooltip: '卸载 ${env.name.isEmpty ? env.slug : env.name}',
        visualDensity: VisualDensity.compact,
        onPressed: () => onAction(EnvironmentAction.uninstall),
        icon: Icon(
          Icons.delete_outline_rounded,
          size: 20,
          color: theme.colorScheme.error,
        ),
      ),
    ];
  }

  static String _display(String version) => version.isEmpty ? '未知' : version;
}
