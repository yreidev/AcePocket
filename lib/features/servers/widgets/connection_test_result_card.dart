import 'package:flutter/material.dart';

import '../../../core/api/api_exception.dart';
import '../models/connection_test.dart';

/// 连接测试成功的结果卡片：展示面板与系统的关键信息。
class ConnectionTestResultCard extends StatelessWidget {
  const ConnectionTestResultCard({
    super.key,
    required this.result,
    this.title = '连接测试通过',
  });

  final ConnectionTestResult result;

  /// 卡片标题（列表页复测时可自定义）。
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final system = result.system;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: colorScheme.secondaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  Icons.check_circle_outline,
                  color: colorScheme.onSecondaryContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: colorScheme.onSecondaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _InfoRow(label: '面板名称', value: result.panel.name),
            _InfoRow(label: '面板版本', value: system.panelVersion),
            _InfoRow(label: '主机名', value: system.hostname),
            _InfoRow(label: '操作系统', value: system.osName),
            _InfoRow(label: '内核', value: system.kernelVersion),
            _InfoRow(label: '架构', value: system.kernelArch),
            _InfoRow(label: '已运行', value: system.uptimeText),
            if (!system.osSupported || system.osEol) ...[
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.warning_amber_outlined,
                    size: 16,
                    color: colorScheme.error,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      system.osEol
                          ? '当前系统版本已停止维护（EOL），建议尽快升级。'
                          : '当前系统版本不在面板官方支持范围内，部分功能可能异常。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 连接测试失败的错误卡片。
class ConnectionTestErrorCard extends StatelessWidget {
  const ConnectionTestErrorCard({
    super.key,
    required this.error,
    this.title = '连接测试失败',
  });

  final Object error;
  final String title;

  String get _message {
    final e = error;
    if (e is ApiException) return e.message;
    return e.toString().replaceFirst(RegExp(r'^\w+(Exception|Error):\s*'), '');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: colorScheme.errorContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.error_outline, color: colorScheme.onErrorContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: colorScheme.onErrorContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SelectableText(
              _message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onErrorContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSecondaryContainer;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(color: color),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '-' : value,
              style: theme.textTheme.bodySmall?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
