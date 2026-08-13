import 'package:flutter/material.dart';

import '../models/container.dart';

/// 通用状态徽标（颜色全部取自 Theme 的 ColorScheme）。
class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    required this.tone,
    this.icon,
    this.dense = false,
  });

  final String label;
  final BadgeTone tone;
  final IconData? icon;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final (background, foreground) = switch (tone) {
      BadgeTone.success => (
        colorScheme.primaryContainer,
        colorScheme.onPrimaryContainer,
      ),
      BadgeTone.warning => (
        colorScheme.tertiaryContainer,
        colorScheme.onTertiaryContainer,
      ),
      BadgeTone.danger => (
        colorScheme.errorContainer,
        colorScheme.onErrorContainer,
      ),
      BadgeTone.info => (
        colorScheme.secondaryContainer,
        colorScheme.onSecondaryContainer,
      ),
      BadgeTone.neutral => (
        colorScheme.surfaceContainerHighest,
        colorScheme.onSurfaceVariant,
      ),
    };

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 6 : 8,
        vertical: dense ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: dense ? 11 : 13, color: foreground),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: foreground,
              fontSize: dense ? 11 : 12,
              fontWeight: FontWeight.w500,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// 徽标色调。
enum BadgeTone { success, warning, danger, info, neutral }

/// 容器状态徽标。
class ContainerStateBadge extends StatelessWidget {
  const ContainerStateBadge({
    super.key,
    required this.state,
    this.dense = false,
  });

  final String state;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final (tone, icon) = switch (state) {
      'running' => (BadgeTone.success, Icons.play_arrow_rounded),
      'paused' => (BadgeTone.warning, Icons.pause_rounded),
      'restarting' => (BadgeTone.warning, Icons.autorenew_rounded),
      'removing' => (BadgeTone.warning, Icons.delete_outline),
      'exited' => (BadgeTone.neutral, Icons.stop_rounded),
      'dead' => (BadgeTone.danger, Icons.error_outline),
      'created' => (BadgeTone.info, Icons.fiber_new_outlined),
      _ => (BadgeTone.neutral, Icons.help_outline),
    };
    return StatusBadge(
      label: containerStateLabel(state),
      tone: tone,
      icon: icon,
      dense: dense,
    );
  }
}
