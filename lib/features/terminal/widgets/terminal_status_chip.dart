import 'package:flutter/material.dart';

import '../models/terminal_session_state.dart';

/// 顶栏连接状态指示：小圆点 + 状态文案 + 心跳延迟。
class TerminalStatusChip extends StatelessWidget {
  const TerminalStatusChip({super.key, required this.state});

  final TerminalSessionState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final (Color color, String label) = switch (state.status) {
      TerminalStatus.idle => (scheme.outline, '待连接'),
      TerminalStatus.connecting => (scheme.tertiary, '连接中…'),
      TerminalStatus.connected =>
        state.unstable ? (scheme.tertiary, '连接可能已中断') : (scheme.primary, '已连接'),
      TerminalStatus.disconnected => (scheme.outline, '已断开'),
      TerminalStatus.failed => (scheme.error, '连接失败'),
    };

    final latency = state.latencyMs;
    final showLatency = state.isConnected && latency != null && !state.unstable;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            showLatency ? '$label · ${latency}ms' : label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
