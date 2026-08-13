import 'package:flutter/material.dart';

/// phpinfo 中的一个块：小节标题或一行表格。
class PhpInfoBlock {
  const PhpInfoBlock.heading(this.title)
    : cells = const <String>[],
      isHeading = true;

  const PhpInfoBlock.row(this.cells) : title = '', isHeading = false;

  final bool isHeading;
  final String title;
  final List<String> cells;
}

/// 把 `GET /environment/php/{version}/phpinfo` 返回的 HTML 解析成可渲染的块。
///
/// 面板执行 `php-cgi -q` 输出标准 phpinfo HTML：`<h1>/<h2>` 是小节标题，
/// 数据都在 `<tr><td>/<th>` 中。移动端没有 WebView，这里做轻量解析后
/// 用原生列表渲染。
List<PhpInfoBlock> parsePhpInfo(String html) {
  if (html.trim().isEmpty) return const [];

  var content = html
      .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '')
      .replaceAll(RegExp(r'<style[^>]*>.*?</style>', dotAll: true), '')
      .replaceAll(RegExp(r'<script[^>]*>.*?</script>', dotAll: true), '');

  final pattern = RegExp(
    r'<h[12][^>]*>(.*?)</h[12]>|<tr[^>]*>(.*?)</tr>',
    dotAll: true,
    caseSensitive: false,
  );
  final cellPattern = RegExp(
    r'<t[dh][^>]*>(.*?)</t[dh]>',
    dotAll: true,
    caseSensitive: false,
  );

  final blocks = <PhpInfoBlock>[];
  for (final match in pattern.allMatches(content)) {
    final heading = match.group(1);
    if (heading != null) {
      final text = _plainText(heading);
      if (text.isNotEmpty) blocks.add(PhpInfoBlock.heading(text));
      continue;
    }
    final row = match.group(2);
    if (row == null) continue;
    final cells = cellPattern
        .allMatches(row)
        .map((m) => _plainText(m.group(1) ?? ''))
        .toList();
    if (cells.isEmpty) continue;
    if (cells.every((c) => c.isEmpty)) continue;
    blocks.add(PhpInfoBlock.row(cells));
  }
  return blocks;
}

/// 去标签 + 反转义，压缩空白。
String _plainText(String raw) {
  var text = raw
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'<[^>]*>', dotAll: true), '');
  text = text
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#039;', "'")
      .replaceAll('&#39;', "'")
      .replaceAll('&amp;', '&');
  return text.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// phpinfo 渲染视图。
class PhpInfoView extends StatelessWidget {
  const PhpInfoView({super.key, required this.blocks});

  final List<PhpInfoBlock> blocks;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 32),
      itemCount: blocks.length,
      itemBuilder: (context, index) {
        final block = blocks[index];
        if (block.isHeading) {
          return Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 14),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.6,
            ),
            child: Text(
              block.title,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          );
        }

        final cells = block.cells;
        if (cells.length == 1) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: SelectableText(
              cells.first,
              style: theme.textTheme.bodySmall,
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SelectableText(cells.first, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 2),
              for (final value in cells.skip(1))
                if (value.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: SelectableText(
                      value,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              const SizedBox(height: 4),
              Divider(height: 1, color: theme.colorScheme.outlineVariant),
            ],
          ),
        );
      },
    );
  }
}
