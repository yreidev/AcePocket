import 'package:flutter/material.dart';

import '../../../core/widgets/section_card.dart';
import '../models/migration_environment.dart';

/// 本地与远程环境对比卡片。
class EnvCompareCard extends StatelessWidget {
  const EnvCompareCard({super.key, required this.local, required this.remote});

  final InstalledEnvironment local;
  final InstalledEnvironment remote;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[
      _EnvCompareRow(
        title: 'Web 服务器',
        localText: local.webserver.isEmpty ? '未安装' : local.webserver,
        remoteText: remote.webserver.isEmpty ? '未安装' : remote.webserver,
        matched: local.webserver == remote.webserver,
        required: true,
      ),
    ];

    for (final entry in InstalledEnvironment.runtimeKeys.entries) {
      final localItems = local.runtime(entry.key);
      final remoteItems = remote.runtime(entry.key);
      rows.add(
        _EnvCompareRow(
          title: entry.value,
          localText: _labels(localItems),
          remoteText: _labels(remoteItems),
          matched: _same(localItems, remoteItems),
        ),
      );
    }

    rows.add(
      _EnvCompareRow(
        title: '数据库',
        localText: _labels(local.databases),
        remoteText: _labels(remote.databases),
        matched: _same(local.databases, remote.databases),
      ),
    );

    rows.add(
      _EnvCompareRow(
        title: 'rsync',
        localText: local.rsync ? '已安装' : '未安装',
        remoteText: remote.rsync ? '已安装' : '未安装',
        matched: local.rsync == remote.rsync,
      ),
    );

    return SectionCard(
      title: '环境对比（本机 → 远程）',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _EnvCompareHeader(),
          const Divider(height: 12),
          for (var i = 0; i < rows.length; i++) ...[
            if (i != 0) const Divider(height: 12),
            rows[i],
          ],
        ],
      ),
    );
  }

  static String _labels(List<EnvVersion> items) => items.isEmpty
      ? '未安装'
      : items.map((e) => e.label.isEmpty ? e.value : e.label).join('、');

  static bool _same(List<EnvVersion> a, List<EnvVersion> b) {
    if (a.length != b.length) return false;
    final av = a.map((e) => e.value).toList()..sort();
    final bv = b.map((e) => e.value).toList()..sort();
    for (var i = 0; i < av.length; i++) {
      if (av[i] != bv[i]) return false;
    }
    return true;
  }
}

class _EnvCompareHeader extends StatelessWidget {
  const _EnvCompareHeader();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return Row(
      children: [
        Expanded(flex: 3, child: Text('项目', style: style)),
        Expanded(flex: 4, child: Text('本机', style: style)),
        Expanded(flex: 4, child: Text('远程', style: style)),
        SizedBox(width: 24, child: Text('', style: style)),
      ],
    );
  }
}

class _EnvCompareRow extends StatelessWidget {
  const _EnvCompareRow({
    required this.title,
    required this.localText,
    required this.remoteText,
    required this.matched,
    this.required = false,
  });

  final String title;
  final String localText;
  final String remoteText;
  final bool matched;

  /// 该项必须一致（不一致时视为阻断项，用错误色标记）。
  final bool required;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final valueStyle = theme.textTheme.bodySmall;
    final iconColor = matched
        ? colorScheme.primary
        : required
        ? colorScheme.error
        : colorScheme.tertiary;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: Text(
            title,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(flex: 4, child: Text(localText, style: valueStyle)),
        Expanded(flex: 4, child: Text(remoteText, style: valueStyle)),
        SizedBox(
          width: 24,
          child: Icon(
            matched
                ? Icons.check_circle_outline
                : required
                ? Icons.cancel_outlined
                : Icons.error_outline,
            size: 18,
            color: iconColor,
            // 是否一致仅靠图标与颜色表达，读屏用户会漏掉，补语义标签。
            semanticLabel: matched
                ? '一致'
                : required
                ? '不一致，阻断迁移'
                : '存在差异',
          ),
        ),
      ],
    );
  }
}
