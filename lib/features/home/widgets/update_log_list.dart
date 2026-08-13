import 'package:flutter/material.dart';

import '../../../core/widgets/animated_reveal.dart';
import '../../../core/widgets/section_card.dart';
import '../models/update_models.dart';
import 'formatters.dart';

/// 更新日志列表：每个版本一张卡片，最新版本在最前。
///
/// 第一个版本默认展开，其余折叠，避免版本跨度大时页面过长。
class UpdateLogList extends StatelessWidget {
  const UpdateLogList({super.key, required this.versions});

  final List<PanelVersion> versions;

  @override
  Widget build(BuildContext context) {
    if (versions.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < versions.length; i++)
          _VersionCard(
            version: versions[i],
            latest: i == 0,
            initiallyExpanded: i == 0,
          ),
      ],
    );
  }
}

class _VersionCard extends StatefulWidget {
  const _VersionCard({
    required this.version,
    required this.latest,
    required this.initiallyExpanded,
  });

  final PanelVersion version;
  final bool latest;
  final bool initiallyExpanded;

  @override
  State<_VersionCard> createState() => _VersionCardState();
}

class _VersionCardState extends State<_VersionCard> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final version = widget.version;
    final description = version.description.trim();

    return SectionCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'v${version.version}',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontFamily: 'monospace',
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      if (widget.latest)
                        _Tag(
                          text: '最新',
                          background: theme.colorScheme.primaryContainer,
                          foreground: theme.colorScheme.onPrimaryContainer,
                        ),
                      if (version.type.isNotEmpty)
                        _Tag(
                          text: version.type,
                          background: theme.colorScheme.surfaceContainerHighest,
                          foreground: theme.colorScheme.onSurfaceVariant,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                ExpandChevron(
                  expanded: _expanded,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '发布时间：${formatDateTime(version.createdAt)}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          AnimatedReveal(
            visible: _expanded,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 10),
                SelectableText(
                  description.isEmpty ? '该版本没有提供更新说明。' : description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface,
                    height: 1.5,
                  ),
                ),
                if (version.downloads.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    '架构：${version.downloads.map((e) => e.arch).join('、')}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({
    required this.text,
    required this.background,
    required this.foreground,
  });

  final String text;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(color: foreground),
      ),
    );
  }
}
