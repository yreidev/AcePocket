import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/log_entry.dart';
import 'format_utils.dart';

/// 日志级别标签配色。
({Color background, Color foreground}) _levelColors(
  BuildContext context,
  String level,
) {
  final scheme = Theme.of(context).colorScheme;
  switch (level.toUpperCase()) {
    case 'ERROR':
    case 'FATAL':
    case 'PANIC':
      return (
        background: scheme.errorContainer,
        foreground: scheme.onErrorContainer
      );
    case 'WARN':
    case 'WARNING':
      return (
        background: scheme.tertiaryContainer,
        foreground: scheme.onTertiaryContainer
      );
    case 'INFO':
      return (
        background: scheme.secondaryContainer,
        foreground: scheme.onSecondaryContainer
      );
    default:
      return (
        background: scheme.surfaceContainerHighest,
        foreground: scheme.onSurfaceVariant
      );
  }
}

/// 操作日志类型的中文名（`internal/biz/log.go` 的 OperationType*）。
String operationTypeLabel(String type) {
  const labels = {
    'panel': '面板',
    'website': '网站',
    'database': '数据库',
    'database_user': '数据库用户',
    'database_server': '数据库服务器',
    'project': '项目',
    'cert': '证书',
    'file': '文件',
    'app': '应用',
    'cron': '计划任务',
    'backup': '备份',
    'container': '容器',
    'firewall': '防火墙',
    'safe': '安全',
    'ssh': 'SSH',
    'setting': '设置',
    'monitor': '监控',
    'webhook': 'Webhook',
    'user': '用户',
  };
  return labels[type] ?? type;
}

/// 面板日志条目（可展开查看附加字段）。
class LogEntryTile extends StatelessWidget {
  const LogEntryTile({super.key, required this.entry});

  final LogEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = _levelColors(context, entry.level);
    final hasExtra = entry.extra.isNotEmpty;
    final message = entry.msg.isEmpty ? '(无内容)' : entry.msg;
    // 面板偶尔会记录整段堆栈 / SQL，不截断会让单个列表项占满好几屏。
    // 长内容折行到 3 行，展开后再给出可选中的完整文本。
    final longMessage = message.length > 120 || message.contains('\n');
    final expandable = hasExtra || longMessage;
    final operator = entry.operatorName.isNotEmpty
        ? entry.operatorName
        : (entry.operatorId > 0 ? '#${entry.operatorId}' : '系统');

    final header = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: colors.background,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            entry.level.isEmpty ? '-' : entry.level.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.foreground,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ],
    );

    final meta = Padding(
      padding: const EdgeInsets.only(top: 6, left: 2),
      child: Text(
        [
          formatDateTime(entry.time),
          if (entry.type.isNotEmpty) operationTypeLabel(entry.type),
          '操作者：$operator',
        ].join('  ·  '),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [header, meta],
    );

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: expandable
          ? Theme(
              // 去掉 ExpansionTile 的默认分割线，保持卡片观感统一。
              data: theme.copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                title: content,
                children: [
                  if (longMessage)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SelectableText(
                        message,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  if (hasExtra) ...[
                    if (longMessage) const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SelectableText(
                        _prettyJson(entry.extra),
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            )
          : Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              child: content,
            ),
    );
  }

  static String _prettyJson(Map<String, dynamic> data) {
    try {
      return const JsonEncoder.withIndent('  ').convert(data);
    } catch (_) {
      return data.toString();
    }
  }
}

/// SSH 登录日志条目。
class SshLogTile extends StatelessWidget {
  const SshLogTile({super.key, required this.log});

  final SshLoginLog log;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final success = log.isSuccess;
    final background = success
        ? theme.colorScheme.secondaryContainer
        : theme.colorScheme.errorContainer;
    final foreground = success
        ? theme.colorScheme.onSecondaryContainer
        : theme.colorScheme.onErrorContainer;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: background,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    success ? '成功' : '失败',
                    style:
                        theme.textTheme.labelSmall?.copyWith(color: foreground),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${log.user.isEmpty ? '未知用户' : log.user}@${log.ip.isEmpty ? '未知 IP' : log.ip}',
                    style: theme.textTheme.bodyMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              [
                if (log.time.isNotEmpty) log.time,
                if (log.port.isNotEmpty) '端口 ${log.port}',
                if (log.method.isNotEmpty) '方式 ${log.method}',
              ].join('  ·  '),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
